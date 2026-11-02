#!/usr/bin/env python3
"""Headless check of the kdp Alfred workflow (scripts/alfred-workflow), run nightly by CI (other/cli/alfred-workflow.sh).

- info.plist: every connection points to an existing object, the view_output trigger opens the Text View, the
  scripts call flags that kdp.py handles, the workflow settings are read by kdp.py.
- every mode (and every kind of selected text of the Universal Action) returns valid Alfred JSON: a list of items
  with a title, valid items with an argument and a known action, no "kdp workflow error".
- the output view: one background job per command, "run again" only once the output was shown, watch mode.

No Alfred and no running environment needed (the modes about the environment then answer "nothing running").
A change of the JSON of find-example, history, repro list, connector-plugin versions… breaks this check instead of
the workflow.

    python3 -I scripts/alfred-workflow/check.py [--root <kafka-docker-playground>]
"""
import argparse
import glob
import importlib.util
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.realpath(__file__))
KNOWN_ACTIONS = {"copy", "copyfile", "open", "reveal", "code", "refresh_repros", "terminal", "run_in_terminal",
                 "view", "alfred_search"}
SETTINGS = {"kdp_root", "ticket_url", "notes_dir", "terminal", "show_output"}

failures = []


def fail(msg):
    failures.append(msg)
    print("❌ " + msg)


def ok(msg):
    print("✅ " + msg)


def check_plist():
    with open(os.path.join(HERE, "info.plist"), "rb") as f:
        d = plistlib.load(f)
    objects = {o["uid"]: o for o in d["objects"]}
    for src, conns in d["connections"].items():
        if src not in objects:
            fail("info.plist: connection from unknown object " + src)
        for c in conns:
            if c["destinationuid"] not in objects:
                fail("info.plist: connection to unknown object " + c["destinationuid"])
    types = lambda t: [o for o in d["objects"] if o["type"] == t]
    text_views = types("alfred.workflow.userinterface.text")
    triggers = [o for o in types("alfred.workflow.trigger.external") if o["config"].get("triggerid") == "view_output"]
    if len(text_views) != 1 or len(triggers) != 1:
        fail("info.plist: expected one Text View and one view_output external trigger")
    else:
        if not any(c["destinationuid"] == text_views[0]["uid"] for c in d["connections"].get(triggers[0]["uid"], [])):
            fail("info.plist: the view_output trigger does not open the Text View")
        script = os.path.join(HERE, text_views[0]["config"].get("inputfile", ""))
        if not os.access(script, os.X_OK):
            fail("info.plist: Text View script {} missing or not executable".format(script))
    code = open(os.path.join(HERE, "kdp.py"), encoding="utf-8").read()
    for o in d["objects"]:
        script = o.get("config", {}).get("script", "")
        for flag in re.findall(r"kdp\.py (--[a-z-]+)", script):
            if '"{}"'.format(flag) not in code:
                fail("info.plist: {} calls kdp.py {} which kdp.py does not handle".format(o["type"], flag))
    variables = {c["variable"] for c in d.get("userconfigurationconfig", [])}
    if variables != SETTINGS:
        fail("info.plist: settings {} != expected {}".format(sorted(variables), sorted(SETTINGS)))
    for v in variables:
        if 'os.environ.get("{}")'.format(v) not in code:
            fail("info.plist: setting {} is not read by kdp.py".format(v))
    if not re.fullmatch(r"\d+\.\d+\.\d+", d.get("version", "")):
        fail("info.plist: version {!r} is not X.Y.Z".format(d.get("version")))
    ok("info.plist: {} objects, version {}".format(len(objects), d.get("version")))


def run_query(query, env, timeout=90):
    """Alfred JSON of a query; waits while the answer asks for a rerun (list being built in the background)."""
    deadline = time.time() + timeout
    while True:
        p = subprocess.run([sys.executable, "-I", os.path.join(HERE, "kdp.py"), query], env=env,
                           capture_output=True, text=True, timeout=120)
        try:
            out = json.loads(p.stdout)
        except ValueError:
            return None, "not JSON: {} {}".format(p.stdout[:200], p.stderr[-300:])
        if "rerun" not in out or time.time() > deadline:
            return out, ""
        time.sleep(min(float(out["rerun"]), 2))


def check_items(query, out):
    label = "kdp " + (query if "\n" not in query else query.split("\n")[0][:30] + "…")
    items = out.get("items")
    if not isinstance(items, list) or not items:
        fail("{}: no items".format(label))
        return
    for i in items:
        if not isinstance(i.get("title"), str) or not isinstance(i.get("valid"), bool):
            fail("{}: item without title or valid: {}".format(label, i))
        if i["title"].startswith("⚠️ kdp workflow error"):
            fail("{}: {} — {}".format(label, i["title"], i.get("subtitle")))
        for name, entry in [("item", i)] + [("mod " + k, m) for k, m in (i.get("mods") or {}).items()]:
            if entry.get("valid"):
                action = (entry.get("variables") or {}).get("action")
                if entry.get("arg") is None or action not in KNOWN_ACTIONS:
                    fail("{}: valid {} '{}' without argument or with unknown action {!r}".format(label, name, i["title"], action))
    ok("{}: {} items, first: {}".format(label, len(items), items[0]["title"][:70]))


QUERIES = [
    "", "find", "find s3 sink", "history", "docs", "docs schema", "status",
    "key", "key batch", "key batch.size ", "key errors tolerance", "key my.custom.key ",
    "plugin", "plugin jdbc", "plugin jdbc 10.7", "plugin confluentinc/kafka-connect-jdbc ", "plugin io.confluent.connect.jdbc.JdbcSinkConnector ",
    "connector", "logs", "topic", "schema", "ci", "ci jdbc", "repro", "notes", "case 123456",
    "errors.tolerance", "io.confluent.connect.s3.S3SinkConnector", "task failed for lcc-abc123 yesterday",
    '{\n  "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",\n  "tasks.max": "1"\n}',
    "org.apache.kafka.connect.errors.ConnectException: Exiting WorkerSinkTask\n\tat org.apache.kafka.connect.runtime."
    "WorkerSinkTask.deliverMessages(WorkerSinkTask.java:632)\nCaused by: java.sql.SQLException: boom",
]


def check_modes(root, cache):
    env = {"HOME": os.environ.get("HOME", "/tmp"), "USER": os.environ.get("USER", "ci"), "PATH": "/usr/bin:/bin",
           "PYTHONUTF8": "1", "kdp_root": root, "alfred_workflow_cache": cache}
    for q in QUERIES:
        out, err = run_query(q, env)
        if out is None:
            fail("kdp {}: {}".format(q, err))
        else:
            check_items(q, out)


def check_view(root, cache):
    os.environ.update({"kdp_root": root, "alfred_workflow_cache": cache, "PYTHONUTF8": "1"})
    spec = importlib.util.spec_from_file_location("kdp", os.path.join(HERE, "kdp.py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    jobs = lambda: [d for d in glob.glob(os.path.join(m.VIEW_DIR, "*")) if os.path.isdir(d)]
    key = m.start_view_job("echo kdp-check; printf '\\033[0;31mERROR red\\033[0m\\n'", "check")
    r = m.view(key)
    deadline = time.time() + 30
    while "rerun" in r and time.time() < deadline:
        time.sleep(0.3)
        r = m.view("")      # the automatic reruns: never start the command again
    if "kdp-check" not in r["response"] or "✅" not in r["footer"] or len(jobs()) != 1:
        fail("view: output / footer / one job: {} {} jobs={}".format(r["response"][-100:], r["footer"], len(jobs())))
    if "🔴 ERROR red" not in r["response"]:
        fail("view: red line not marked with 🔴")
    m.view("")             # ↩ once the output was shown: run again, exactly one new job
    if len(jobs()) != 2:
        fail("view: ↩ run again started {} jobs instead of 1".format(len(jobs()) - 1))
    f = m.view("kdp-check")
    if "lines containing" not in f["response"]:
        fail("view: text↩ filter")
    w = m.view("watch 2")
    if w.get("rerun") is None or "👀" not in w["footer"]:
        fail("view: watch↩ did not start watching")
    s = m.view("stop")
    if "👀" in s["footer"]:
        fail("view: stop↩ did not stop watching")
    ok("view: streaming, run again, filter, watch, colour markers ({} jobs)".format(len(jobs())))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=os.path.realpath(os.path.join(HERE, os.pardir, os.pardir)))
    args = parser.parse_args()
    cache = tempfile.mkdtemp(prefix="kdp-alfred-check-")
    try:
        check_plist()
        check_modes(args.root, cache)
        check_view(args.root, cache)
    finally:
        shutil.rmtree(cache, ignore_errors=True)
    if failures:
        print("\n❌ {} failure(s)".format(len(failures)))
        sys.exit(1)
    print("\n✅ kdp Alfred workflow check passed")


if __name__ == "__main__":
    main()
