#!/usr/bin/env python3
"""Alfred workflow for kafka-docker-playground (keyword: kdp).

Script filter:  python3 kdp.py "<query>"        -> Alfred JSON on stdout
Action:         python3 kdp.py --action "<arg>"  -> runs $action, prints a notification text

Sub-commands (first word of the query):
  how <question>      playground find-command: the command that answers a question or a symptom
  find <words>        playground find-example (examples + reproduction models)
  repro [words]       reproduction models (repro list, cached, mine first)
  history [words]     playground history: replay a run
  case <number>       ticket link (ticket_url), notes and repro models of a case, /kdp-case
  notes [words]       notes folder (notes_dir, default claude-notes/), resume the Claude Code session that wrote them
  plugin <p> [ver]    connector-plugin info / changelog / sourcecode / dependencies / cve-scan
  key <key> [class]   connector-plugin config-key
  docs [words]        deep dive pages
  status              playground status, connector status / diagnose, connect errors

Keys on result items (same meaning everywhere when they apply):
  ↩ copy the command (or open)      ⌘ open in VS Code      ⌃ run in the terminal
  ⌥ / ⇧ depend on the mode (shown in the subtitle when the key is held)
  Scripts (find, repro, history): ↩ opens the script in VS Code, ⌘ copies 'playground run -f …' 

Never runs an example by itself: running one stops the environment that is up.
Only ⌃ (an explicit choice, with a warning) sends `playground run` to the terminal.

Optional parts, shown only when available:
  repro           the reproduction-models/ folder (private submodule) has models
  notes           the notes folder exists (*.md, Claude Code resume footer)
  case            ticket_url is set, or notes / repro models exist
  /kdp-case item  the kdp-case Claude Code skill is installed (~/.claude/skills/kdp-case)

Workflow configuration (environment variables set by Alfred):
  kdp_root    kafka-docker-playground folder (default: the clone this file is in, when linked)
  ticket_url  support ticket URL, {} is replaced by the number (empty: no ticket link)
  notes_dir   notes folder (default <kdp_root>/claude-notes)
  show_output where read-only commands (status, plugin, key…) show their output: alfred (a Text View,
              default) or terminal
  terminal    where "run in the terminal" goes: alfred (Alfred Preferences > Features > Terminal),
              vscode (a new VS Code integrated terminal), terminal_app (Terminal.app) or copy

Python 3.9 compatible (macOS system python).
"""
import glob
import hashlib
import json
import os
import re
import shlex
import subprocess
import sys
import time

def _find_root():
    """kdp_root if set, else the clone this file lives in (linked install), else the usual clone path."""
    here = os.path.join(os.path.dirname(os.path.realpath(__file__)), os.pardir, os.pardir)
    for cand in (os.environ.get("kdp_root"), here, "~/Documents/github/kafka-docker-playground"):
        if cand:
            r = os.path.realpath(os.path.expanduser(cand))
            if os.path.exists(os.path.join(r, "scripts", "cli", "playground")):
                return r
    return os.path.expanduser(os.environ.get("kdp_root") or "~/Documents/github/kafka-docker-playground").rstrip("/")


ROOT = _find_root()
CLI = os.path.join(ROOT, "scripts", "cli", "playground")
NOTES_DIR = os.path.expanduser(os.environ.get("notes_dir") or os.path.join(ROOT, "claude-notes"))
REPRO_DIR = os.path.join(ROOT, "reproduction-models")
TICKET_URL = (os.environ.get("ticket_url") or "").strip()
TERMINAL = (os.environ.get("terminal") or "alfred").strip()
SHOW_OUTPUT = (os.environ.get("show_output") or "alfred").strip()
DOCS_DIR = os.path.join(ROOT, "docs")
CACHE_DIR = os.environ.get("alfred_workflow_cache") or os.path.expanduser(
    "~/Library/Caches/com.vdesabou.kdp-alfred"
)
REPRO_CACHE = os.path.join(CACHE_DIR, "repro-list.json")
REPRO_TTL = 6 * 3600
DOCS_URL = "https://kafka-docker-playground.io/#/{}"
HUB_URL = "https://www.confluent.io/hub/{}"
ME = os.environ.get("USER", "")
HAS_REPROS = next(glob.iglob(os.path.join(REPRO_DIR, "*", "*-repro-*.sh")), None) is not None
HAS_NOTES = os.path.isdir(NOTES_DIR)
HAS_CASE = bool(TICKET_URL) or HAS_NOTES or HAS_REPROS
HAS_KDP_CASE = os.path.exists(os.path.expanduser("~/.claude/skills/kdp-case"))


def ticket_url(n):
    if not TICKET_URL or not n:
        return None
    return TICKET_URL.replace("{}", n) if "{}" in TICKET_URL else TICKET_URL + n

SUBCOMMANDS = [
    ("status", "🚦", "What is running right now", "status, connector status / diagnose, connect errors"),
    ("connector", "🧩", "Running connectors: status, diagnose, tasks, metrics, history…", "kdp connector [words]: pick a connector"),
    ("topic", "🧵", "Topics: describe, records, last records, DLQ", "kdp topic [words]: pick a topic"),
    ("schema", "📐", "Schema Registry subjects: describe, history, diff", "kdp schema [words]: pick a subject"),
    ("logs", "📜", "Container logs: errors, last lines, grep", "kdp logs [container] [pattern]"),
    ("how", "🧭", "Which command answers my question?", "kdp how <question or symptom>: find-command"),
    ("find", "🔎", "Find an example or a reproduction model", "find-example, ↩ copies playground run -f"),
    ("repro", "🧪", "Reproduction models (mine first)", "repro list, cached"),
    ("history", "🕘", "Replay a playground run", "playground history"),
    ("plugin", "🔌", "Connector plugin: info, changelog, source code, jars, CVEs", "kdp plugin <words> to pick it in the list, then [version]"),
    ("key", "🔑", "Connector config key: doc, default, since when", "kdp key <words> to pick it in the list, then a connector"),
    ("case", "🎫", "Everything about a support case", "ticket, notes, repro models of the case"),
    ("notes", "📝", "Search notes", "open a note, resume the Claude Code session that wrote it"),
    ("docs", "🍪", "Deep dive pages", "kafka-docker-playground.io"),
    ("ci", "🤖", "CI result of a test directory", "kdp ci [words]: pick a test of the CI matrix"),

]

AVAILABLE = {
    "repro": lambda: HAS_REPROS,
    "notes": lambda: HAS_NOTES,
    "case": lambda: HAS_CASE,
}
UNAVAILABLE = {
    "repro": "no reproduction model in " + REPRO_DIR,
    "notes": "no notes folder " + NOTES_DIR + " (set notes_dir in the workflow configuration)",
    "case": "set ticket_url in the workflow configuration, or have notes / reproduction models",
}


def available(name):
    return AVAILABLE.get(name, lambda: True)()




# --------------------------------------------------------------------------- helpers


def q(s):
    return shlex.quote(str(s))


def env():
    e = dict(os.environ)
    # Alfred runs scripts without LANG: give the commands a UTF-8 locale (emojis, sort, setlocale warnings)
    if not e.get("LANG") and not e.get("LC_ALL"):
        e["LANG"] = "en_US.UTF-8"
    e["PATH"] = ":".join(
        [os.path.join(ROOT, "scripts", "cli"), "/opt/homebrew/bin", "/usr/local/bin", e.get("PATH", "/usr/bin:/bin")]
    )
    return e


def run_json(args, timeout=30):
    """Run a playground command, return (parsed json or None, error text)."""
    try:
        p = subprocess.run(
            [CLI] + args, cwd=ROOT, env=env(), capture_output=True, text=True, timeout=timeout,
            stdin=subprocess.DEVNULL,
        )
    except subprocess.TimeoutExpired:
        return None, "timed out after {}s".format(timeout)
    except OSError as e:
        return None, str(e)
    out = p.stdout.strip()
    try:
        return json.loads(out) if out else None, p.stderr.strip()
    except ValueError:
        return None, (p.stderr or p.stdout).strip()


def in_root(cmd):
    return "cd {} && {}".format(q(ROOT), cmd)


def words_match(words, *fields):
    hay = " ".join(str(f) for f in fields if f).lower()
    return all(w.lower() in hay for w in words)


def short(s, n=90):
    s = re.sub(r"\s+", " ", str(s or "")).strip()
    return s if len(s) <= n else s[: n - 1] + "…"


def ago(ts):
    d = time.time() - ts
    if d < 3600:
        return "{} min ago".format(int(d // 60))
    if d < 86400:
        return "{} h ago".format(int(d // 3600))
    return time.strftime("%Y-%m-%d", time.localtime(ts))


def routed(action):
    """'terminal' goes to Alfred's Terminal Command, unless the terminal setting picks another target."""
    return "run_in_terminal" if action == "terminal" and TERMINAL != "alfred" else action


def action_vars(action, arg, title):
    """Variables of an item or modifier. 'output' = a read-only command: Text View or terminal."""
    if action == "output":
        if SHOW_OUTPUT == "alfred":
            return {"action": "view", "view_title": title}
        action = "terminal"
    return {"action": routed(action)}


def mod(subtitle, action=None, arg=None):
    if action is None or arg is None:
        return {"valid": False, "subtitle": subtitle}
    return {"valid": True, "subtitle": subtitle, "arg": arg, "variables": action_vars(action, arg, subtitle)}


def item(title, subtitle="", action=None, arg=None, autocomplete=None, mods=None, icon=None,
         copy=None, quicklook=None, valid=None):
    it = {"title": title, "subtitle": subtitle}
    if action and arg is not None:
        it["arg"] = arg
        it["variables"] = action_vars(action, arg, title)
        it["valid"] = True if valid is None else valid
        if action == "output" and SHOW_OUTPUT == "alfred":
            mods = dict(mods or {})
            mods.setdefault("ctrl", mod("⌃ run in the terminal instead", "terminal", arg))
    else:
        it["valid"] = False
    if autocomplete is not None:
        it["autocomplete"] = autocomplete
    if mods:
        it["mods"] = mods
    if icon:
        it["icon"] = {"path": icon}
    if copy or arg:
        it["text"] = {"copy": copy or arg, "largetype": copy or arg}
    if quicklook:
        it["quicklookurl"] = quicklook
    return it


def info(title, subtitle="", autocomplete=None):
    return item(title, subtitle, autocomplete=autocomplete)


def readme_of(script):
    r = os.path.join(os.path.dirname(script), "README.md")
    return r if os.path.exists(r) else None


def bootstrap_cmd(script):
    return 'playground repro bootstrap -f {} -d "<case number> <symptom>" --no-run'.format(q(script))


def notified(cmd):
    """A command for the terminal that posts a notification with its result and duration when it ends."""
    wrapper = os.path.join(os.path.dirname(os.path.realpath(__file__)), "notify-run.sh")
    return in_root("{} {}".format(q(wrapper), cmd))


def last_example():
    """(example started last, environment) from playground.ini."""
    try:
        import configparser
        ini = configparser.ConfigParser(strict=False, interpolation=None)
        ini.read(os.path.join(ROOT, "playground.ini"), encoding="utf-8")
        test_file = ini.get("run", "test_file", fallback="")
        return "/".join(test_file.split("/")[-3:]) if test_file else "", ini.get("run", "environment", fallback="")
    except Exception:
        return "", ""


def stop_warning():
    """What playground run would stop: the example that runs and its containers."""
    containers = cached_cli_text("container-list", ["get-container-list"], LIVE_TTL).split()
    if not containers:
        return "nothing is running"
    example, _ = last_example()
    return "⚠️ stops {} · {} container{}".format(example or "the running environment", len(containers),
                                               "s" if len(containers) > 1 else "")


def script_mods(script, run_command, alt=None, shift=None):
    """⌘ copy the run command, ⌃ run in terminal, ⌥ README (default), ⇧ copy repro bootstrap (default)."""
    readme = readme_of(script)
    return {
        "cmd": mod("⌘ copy: " + short(run_command, 120), "copy", run_command),
        "alt": alt or (mod("⌥ open the README", "open", readme) if readme else mod("⌥ no README in this folder")),
        "shift": shift or mod("⇧ copy: playground repro bootstrap -f … --no-run", "copy", bootstrap_cmd(script)),
        "ctrl": mod("⌃ ▶️ run it in the terminal · " + stop_warning(), "terminal", notified(run_command)),
    }


def script_item(title, subtitle, script, run_command, alt=None, shift=None, **kw):
    """A result that is a script (example or repro model): ↩ opens it in VS Code, ⌘C / large type: the run command."""
    return item(title, subtitle, "code", script, copy=run_command,
                mods=script_mods(script, run_command, alt=alt, shift=shift), **kw)


def example_actions(script, flags="", extra=None):
    """The page of one example (Tab on a find / history / repro result): ▶️ run it first, saying what it stops."""
    run = "playground run -f {}{}".format(q(script), " " + flags if flags else "")
    warn = stop_warning()
    readme = readme_of(script)
    items = []
    if flags:
        items.append(item("🔁 Re-run with the same flags", "{} · {}".format(flags, warn), "terminal", notified(run)))
    items += [
        item("▶️ Run " + os.path.basename(script) + (" without these flags" if flags else ""),
             "in the terminal, notification when it ends · " + warn, "terminal",
             notified("playground run -f {}".format(q(script)))),
        item("📝 Open in VS Code", script, "code", script),
        item("📋 Copy the run command", run, "copy", run),
    ]
    if readme:
        items.append(item("📖 Open the README", readme, "open", readme))
    items += extra or []
    items.append(item("🧪 Copy: repro bootstrap from this example", bootstrap_cmd(script), "copy", bootstrap_cmd(script)))
    return {"items": items}


# --------------------------------------------------------------------------- repro cache


def refresh_repro_cache():
    os.makedirs(CACHE_DIR, exist_ok=True)
    lock = REPRO_CACHE + ".lock"
    if os.path.exists(lock) and time.time() - os.path.getmtime(lock) < 180:
        return
    open(lock, "w").close()
    tmp = REPRO_CACHE + ".tmp"
    cmd = (
        "{cli} repro list --json --limit 100000 > {tmp} 2>/dev/null; "
        "if head -c1 {tmp} | grep -q '\\['; then mv {tmp} {cache}; else rm -f {tmp}; fi; rm -f {lock}"
    ).format(cli=q(CLI), tmp=q(tmp), cache=q(REPRO_CACHE), lock=q(lock))
    subprocess.Popen(
        ["/bin/bash", "-c", cmd], cwd=ROOT, env=env(), stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True,
    )


def load_repros():
    """Return (models or None, age in seconds). Refreshes in the background when stale."""
    if not os.path.exists(REPRO_CACHE):
        refresh_repro_cache()
        return None, 0
    age = time.time() - os.path.getmtime(REPRO_CACHE)
    if age > REPRO_TTL:
        refresh_repro_cache()
    try:
        with open(REPRO_CACHE) as f:
            return json.load(f), age
    except ValueError:
        refresh_repro_cache()
        return None, 0


def verdict_text(v):
    if not v:
        return ""
    if isinstance(v, dict):
        return str(v.get("verdict") or v.get("result") or "")
    return str(v)


def repro_item(m):
    script = m.get("script", "")
    run = "playground run -f {}".format(q(script))
    bits = []
    # the file name says more than the description when several models share one (87 do)
    slug = os.path.basename(script)[:-3].split("-repro-", 1)[-1]
    desc = m.get("description") or ""
    if slug != re.sub(r"[^a-z0-9]+", "-", desc.lower()).strip("-"):
        bits.append("📄 " + slug)
    elif m.get("case"):
        bits.append("🎫 " + m["case"])
    if m.get("created"):
        bits.append(m["created"])
    if m.get("author") and m["author"] != ME:
        bits.append("👤 " + m["author"])
    if m.get("status"):
        bits.append("🩹 " + m["status"])
    if verdict_text(m.get("last_verdict")):
        bits.append("⚖️ " + verdict_text(m.get("last_verdict")))
    if not m.get("committed", True):
        bits.append("✏️ uncommitted")
    if m.get("expected") or m.get("actual"):
        bits.append("🎯 {} 💥 {}".format(short(m.get("expected"), 40), short(m.get("actual"), 40)))
    case = m.get("case")
    return script_item(
        short(m.get("description") or os.path.basename(script), 100),
        " · ".join(bits) or m.get("path", ""),
        script, run, autocomplete="repro @{} ".format(script),
        alt=mod("⌥ hand-off report (repro export --report-only)", "output",
                in_root("playground repro export -f {} --report-only".format(q(script)))),
        shift=mod("⇧ open ticket " + case, "open", ticket_url(case)) if ticket_url(case)
        else mod("⇧ no case number on this model" if not case else "⇧ set ticket_url to open ticket " + case),
        quicklook=script,
    )


# --------------------------------------------------------------------------- modes


def version_tuple(v):
    return tuple(int(x) for x in re.findall(r"\d+", v or "")[:3])


def update_item():
    """🆕 when the clone has a newer workflow than the imported copy (a linked copy is the clone itself)."""
    here = os.path.dirname(os.path.realpath(__file__))
    source = os.path.join(ROOT, "scripts", "alfred-workflow")
    installed = os.environ.get("alfred_workflow_version", "")
    if not installed or os.path.realpath(source) == here:
        return None
    try:
        import plistlib
        with open(os.path.join(source, "info.plist"), "rb") as f:
            latest = plistlib.load(f).get("version", "")
    except (OSError, ValueError):
        return None
    if version_tuple(latest) <= version_tuple(installed):
        return None
    return item("🆕 kdp {} is available (installed: {})".format(latest, installed), "↩ playground tools install-alfred-workflow",
                "output", in_root("playground tools install-alfred-workflow"))


def running_item():
    """▶️ the example started last (playground.ini) and how many containers run: ↩ status, ⌘ re-run, ⌥ stop, ⇧ versions."""
    example, environment = last_example()
    if not example:
        return None
    containers = cached_cli_text("container-list", ["get-container-list"], LIVE_TTL).split()
    if containers:
        title = "▶️ {} · {} · {} container{}".format(example, environment, len(containers), "s" if len(containers) > 1 else "")
        mods = {
            "cmd": mod("⌘ 🔁 re-run it with the same flags (playground re-run, stops it first)", "terminal", notified("playground re-run")),
            "alt": mod("⌥ ⏹️ stop the environment (playground stop)", "terminal", notified("playground stop")),
            "shift": mod("⇧ 🔄 update versions: CP, connect or connector (playground update-version prompts)", "terminal",
                         notified("playground update-version")),
        }
        sub = "↩ status · ⌘ re-run · ⌥ stop · ⇧ update versions · Tab: kdp connector"
    else:
        title = "⏹️ Nothing running · last example: {}".format(example)
        mods = {
            "cmd": mod("⌘ 🔁 run it again with the same flags (playground re-run)", "terminal", notified("playground re-run")),
            "alt": mod("⌥ nothing to stop"),
            "shift": mod("⇧ nothing running to update"),
        }
        sub = "↩ status · ⌘ run it again with the same flags"
    return item(title, sub, "output", in_root("playground status"), autocomplete="connector ", mods=mods)


CONNECTOR_CLASS_RE = re.compile(r"\b((?:io|com|org|net|de|ai|co)\.[a-z0-9_]+(?:\.[a-zA-Z0-9_]+)*\.[A-Z][A-Za-z0-9_]*(?:Connector|Sink|Source))\b")


def save_selection(raw, ext):
    folder = os.path.join(CACHE_DIR, "selection")
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, hashlib.sha1(raw.encode()).hexdigest()[:12] + "." + ext)
    with open(path, "w", encoding="utf-8") as f:
        f.write(raw)
    return path


def smart_items(raw):
    """What the selected text (Universal Action) or the typed text looks like: a connector config, a stack trace,
    a connector class, a config key, an lcc id."""
    text = raw.strip()
    items = []
    if not text:
        return items
    multiline = "\n" in text
    # a connector config: json, CFK / Strimzi yaml, terraform, properties, curl ?expand=info dump
    if "connector.class" in text or re.search(r"kind:\s*(Connector|KafkaConnector)\b", text) or 'resource "confluent_connector"' in text:
        ext = "json" if text.startswith(("{", "[")) else "yaml" if re.search(r"^\s*apiVersion:", text, re.M) else \
            "tf" if "resource " in text else "properties"
        path = save_selection(text, ext)
        items += [
            item("✅ Validate this connector config", "connector validate ({})".format(ext), "output",
                 in_root("playground connector validate < {}".format(q(path)))),
            item("🔄 Convert this config to a playground heredoc", "connector convert (values as variables)", "output",
                 in_root("playground connector convert {}".format(q(path)))),
            item("🧪 Copy: repro bootstrap from this config", "playground repro bootstrap --config … --no-run (description to fill in)", "copy",
                 'playground repro bootstrap --config {} -d "<case number> <symptom>" --no-run'.format(q(path))),
        ]
    # log lines or a stack trace
    elif re.search(r"Exception\b|Caused by:|\bat [a-z][\w.$]+\(|\b(ERROR|FATAL)\b", text) and (multiline or len(text) > 80):
        path = save_selection(text, "log")
        items.append(item("🧭 Analyze these log lines", "playground analyze logs: known causes, root causes, what to do", "output",
                          in_root("playground analyze logs -f {} --output-dir /tmp/kdp-analyze-logs".format(q(path)))))
    m = CONNECTOR_CLASS_RE.search(text)
    if m:
        cls = m.group(1)
        items += [
            info("🔌 Plugin of " + cls.split(".")[-1], "↩ info, versions, changelog, source code", autocomplete="plugin {} ".format(cls)),
            info("🔎 Examples with " + cls.split(".")[-1], "↩ find-example", autocomplete="find {}".format(cls)),
        ]
    if not multiline and re.fullmatch(r"[a-z][a-z0-9_.\-]*\.[a-z0-9_.\-]+", text) and text in load_config_keys():
        items.insert(0, info("🔑 Config key " + text, "↩ the connectors that have it, doc, default", autocomplete="key {} ".format(text)))
    lcc = re.search(r"\blcc-[a-z0-9]+\b", text)
    if lcc:
        items.append(item("🕵️ OpenSearch / Grafana for " + lcc.group(0), "the fm_ccloud workflow (Confluent employees)", "alfred_search",
                          "fm_ccloud " + lcc.group(0)))
    return items


def mode_menu(rest, raw=""):
    first = rest.split()[0].lower() if rest.split() else ""
    items = []
    smart = smart_items(raw or rest)
    if first and HAS_CASE and re.fullmatch(r"\d{5,7}", first) and not smart:
        return mode_case(rest)
    if not first:
        items += [x for x in (update_item(), running_item()) if x]
    for name, emoji, title, sub in SUBCOMMANDS:
        if available(name) and (not first or name.startswith(first)):
            items.append(info("{} {}".format(emoji, title), "kdp {} — {}".format(name, sub), autocomplete=name + " "))
    if first and not items:
        items += smart
        # free text: offer the modes that take free text (not for a selected config or stack trace)
        if "\n" not in (raw or "").strip():
            items.append(info("🧭 Which command: " + rest, "↩ search with find-command", autocomplete="how " + rest))
            items.append(info("🔎 Find examples: " + rest, "↩ search with find-example", autocomplete="find " + rest))
            if HAS_NOTES:
                items.append(info("📝 Search notes: " + rest, "↩ search the notes", autocomplete="notes " + rest))
            if HAS_REPROS:
                items.append(info("🧪 Search repro models: " + rest, "↩ search the repro models", autocomplete="repro " + rest))
        if re.fullmatch(r"[a-z0-9_.\-]+\.[a-z0-9_.\-]+", rest.strip()) and not any(i["title"].startswith("🔑") for i in smart):
            items.insert(0, info("🔑 Config key " + rest, "↩ connector-plugin config-key", autocomplete="key {} ".format(rest.strip())))
        m = re.search(r"\b(\d{6})\b", rest)
        if m and HAS_CASE:
            items.insert(0, info("🎫 Support case " + m.group(1), "↩ ticket, notes, repro models", autocomplete="case " + m.group(1)))
    return {"items": items}


def mode_find(rest):
    if rest.strip().startswith("@"):
        return example_actions(rest.strip()[1:].split()[0])
    if len(rest.strip()) < 2:
        return {"items": [info("🔎 Type words to find an example", "e.g. oracle cdc ssl · s3 sink parquet · 123456")]}
    hits, err = run_json(["find-example", rest.strip(), "--json", "--limit", "20"], timeout=30)
    if hits is None:
        return {"items": [info("⚠️ find-example failed", short(err, 200))]}
    if not hits:
        return {"items": [info("🤷 No example matches: " + rest, "every word must match the path, class, README title or script")]}
    items = []
    for h in hits:
        script = h["script"]
        path = h.get("path") or script
        sub = " · ".join(x for x in [h.get("title"), os.path.dirname(path)] if x)
        items.append(script_item(
            os.path.basename(path), sub + " · Tab: ▶️ run it, README…", script, h["run_command"],
            quicklook=readme_of(script) or script,
            autocomplete="find @{} ".format(script),
        ))
    return {"items": items}


def mode_how(rest):
    if len(rest.strip()) < 2:
        return {"items": [info("🧭 Type a question or a symptom", "e.g. connector stuck high cpu · who deleted the schema · docker logs")]}
    hits, err = run_json(["find-command", rest.strip(), "--json", "--limit", "10"], timeout=30)
    if hits is None:
        return {"items": [info("⚠️ find-command failed", short(err, 200))]}
    if not hits:
        return {"items": [info("🤷 No command matches: " + rest, "try other words, or kdp docs for the deep dive pages")]}
    items = []
    for h in hits:
        command = h["command"]
        usage = re.sub(r"`", "", h.get("usage") or "")
        url = h.get("deep_dive") or ""
        page = os.path.join(DOCS_DIR, url.rsplit("/", 1)[-1] + ".md") if url else ""
        mods = {
            "cmd": mod("⌘ open the deep dive in VS Code", "code", page) if page and os.path.exists(page)
            else mod("⌘ no deep dive for this command"),
            "alt": mod("⌥ show: " + command + " --help", "output", in_root(h["help_command"])),
            "shift": mod("⇧ open the deep dive", "open", url) if url else mod("⇧ no deep dive for this command"),
        }
        items.append(item(command, short(re.sub(r"`", "", h.get("matched") or ""), 120) + (" · " + short(usage, 80) if usage else ""),
                          "copy", command, mods=mods, copy=usage or command, quicklook=url or None))
    return {"items": items}


def repro_actions(rest, models):
    """kdp repro @<script> [status text]: the actions on one reproduction model (Tab on a model opens this page)."""
    script, _, status = rest[1:].strip().partition(" ")
    status = status.strip()
    m = next((x for x in models or [] if x.get("script") == script), {})
    run = "playground run -f {}".format(q(script))
    f = q(script)
    items = [
        item("▶️ Run " + os.path.basename(script), "in the terminal, notification when it ends · " + stop_warning(),
             "terminal", notified(run)),
        item("📝 Open in VS Code", script, "code", script),
        item("📋 Copy the run command", run, "copy", run),
        item("🔀 What it changes vs its base example", "repro diff --summary ({})".format(m.get("base_example") or "base example"),
             "output", in_root("playground repro diff -f {} --summary".format(f))),
        item("🔀 Full diff vs its base example", "repro diff (connector keys and compose override)", "output",
             in_root("playground repro diff -f {}".format(f))),
        item("📋 Hand-off report", "repro export --report-only (for a Jira)", "output",
             in_root("playground repro export -f {} --report-only".format(f))),
        item("📦 Export a bundle", "repro export --no-clipboard (blocked if it holds a secret)", "output",
             in_root("playground repro export -f {} --no-clipboard".format(f))),
    ]
    if status:
        items.insert(0, item("🩹 Set the status: " + status, "repro status --set (header of the model)", "output",
                             in_root("playground repro status -f {} --set {}".format(f, q(status)))))
    else:
        items.append(info("🩹 Set the status", "type it: kdp repro @… fixed in 10.7.5 (now: {})".format(m.get("status") or "none"),
                          autocomplete="repro @{} ".format(script)))
    url = ticket_url(m.get("case"))
    if url:
        items.append(item("🎫 Open ticket " + m["case"], url, "open", url))
    return {"items": items}


def mode_repro(rest):
    models, age = load_repros()
    if rest.strip().startswith("@"):
        return repro_actions(rest.strip(), models)
    if models is None:
        return {"rerun": 2, "items": [info("⏳ Building the repro model list (about 10 s)…", "playground repro list runs in the background, the list appears by itself")]}
    words = rest.split()
    hits = [m for m in models if words_match(
        words, m.get("path"), m.get("description"), m.get("case"), m.get("status"), m.get("jira"),
        m.get("expected"), m.get("actual"), m.get("base_example"), m.get("author"),
        verdict_text(m.get("last_verdict")))]
    # mine first, then newest first inside each group
    mine = sorted([m for m in hits if m.get("author") == ME], key=lambda m: m.get("created") or "", reverse=True)
    others = sorted([m for m in hits if m.get("author") != ME], key=lambda m: m.get("created") or "", reverse=True)
    items = [repro_item(m) for m in (mine + others)[:50]]
    if not items:
        items = [info("🤷 No repro model matches: " + rest, "{} models in the cache".format(len(models)))]
    items.append(item(
        "🔄 Refresh the repro model list", "cache updated {} · {} models".format(ago(time.time() - age), len(models)),
        "refresh_repros", "refresh"))
    return {"items": items}


def mode_history(rest):
    if rest.strip().startswith("@"):
        script, _, flags = rest.strip()[1:].partition(" ")
        return example_actions(script, flags.strip())
    args = ["history", "--list", "--json"] + rest.split()
    runs, err = run_json(args, timeout=15)
    if runs is None:
        return {"items": [info("⚠️ playground history failed", short(err, 200))]}
    items = []
    for r in runs:
        script = r.get("script", "")
        cmd = r.get("command", "")
        flags = cmd.split(script, 1)[1].strip() if script and script in cmd else ""
        res = r.get("result") or ""
        emoji = {"SUCCESS": "✅", "FAILURE": "❌", "FAILED": "❌"}.get(res.upper(), "⏺️")
        dur = r.get("duration_seconds")
        bits = [emoji + " " + res if res else emoji, (r.get("date") or "").replace("T", " ")]
        if dur:
            bits.append("{}m{:02d}s".format(dur // 60, dur % 60) if dur >= 60 else "{}s".format(dur))
        if r.get("branch"):
            bits.append("🌿 " + r["branch"])
        if r.get("runs", 1) > 1:
            bits.append("{} runs".format(r["runs"]))
        if flags:
            bits.append(flags)
        if not r.get("exists", True):
            items.append(info("⚠️ " + r.get("path", script), "script no longer exists · " + " · ".join(bits)))
            continue
        items.append(script_item(r.get("path", script), " · ".join(bits), script, cmd,
                                 quicklook=readme_of(script) or script,
                                 autocomplete="history @{} {}".format(script, flags).rstrip() + " "))
    if not items:
        items = [info("🤷 No run in the history matches: " + rest)]
    return {"items": items}


def parse_note(path):
    title, resume = None, None
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            head = f.read(4096)
            f.seek(0, os.SEEK_END)
            size = f.tell()
            f.seek(max(0, size - 4096))
            tail = f.read()
    except OSError:
        return None, None
    m = re.search(r"^#\s+(.+)$", head, re.M)
    if m:
        title = m.group(1).strip()
    found = re.findall(r"claude --resume ([0-9a-f-]{36})`?\s*\(from `([^`]+)`\)", tail)
    if found:
        resume = found[-1]
    return title, resume


def note_item(path):
    title, resume = parse_note(path)
    name = os.path.basename(path)
    stem = path[:-3]
    slack = stem + ".slack.txt"
    bits = [ago(os.path.getmtime(path)), name]
    if resume:
        bits.append("🔁 resumable")
    if os.path.exists(slack):
        bits.append("💬 slack text")
    return item(
        short(title or name, 100), " · ".join(bits), "open", path,
        mods={
            "cmd": mod("⌘ resume the Claude Code session that wrote it", "terminal",
                       "cd {} && claude --resume {}".format(q(resume[1]), resume[0])) if resume
            else mod("⌘ no 🔁 resume footer in this note"),
            "alt": mod("⌥ copy the Slack text (" + os.path.basename(slack) + ")", "copyfile", slack)
            if os.path.exists(slack) else mod("⌥ no .slack.txt next to this note"),
            "shift": mod("⇧ reveal in Finder", "reveal", path),
            "ctrl": mod("⌃ open in VS Code", "code", path),
        },
        quicklook=path, copy=path,
    )


def mode_notes(rest):
    words = rest.split()
    paths = glob.glob(os.path.join(NOTES_DIR, "*.md"))
    paths.sort(key=os.path.getmtime, reverse=True)
    items = []
    for p in paths:
        if words:
            title, _ = parse_note(p)
            if not words_match(words, os.path.basename(p), title):
                continue
        items.append(note_item(p))
        if len(items) >= 40:
            break
    if not items:
        items = [info("🤷 No note matches: " + rest, NOTES_DIR)]
    return {"items": items}


def mode_case(rest):
    m = re.search(r"\b(\d{5,7})\b", rest)
    if not m:
        return {"items": [info("🎫 Type a case number", "e.g. kdp case 368608")]}
    n = m.group(1)
    items = []
    url = ticket_url(n)
    if url:
        items.append(item("🎫 Ticket " + n, url, "open", url, mods={"shift": mod("⇧ copy the ticket URL", "copy", url)}))
    notes = [p for p in glob.glob(os.path.join(NOTES_DIR, "*.md"))
             if re.search(r"(^|[^0-9]){}([^0-9]|$)".format(n), os.path.basename(p))]
    notes.sort(key=os.path.getmtime, reverse=True)
    items += [note_item(p) for p in notes]
    if HAS_REPROS:
        models, _ = load_repros()
        if models is None:
            items.append(info("⏳ Repro model list is being built…", "come back in a few seconds"))
        else:
            items += [repro_item(x) for x in models if (x.get("case") or "") == n][:30]
    if HAS_KDP_CASE:
        items.append(item(
            "🤖 Investigate with Claude Code: /kdp-case " + n,
            "opens a terminal in the playground with claude \"/kdp-case {}\"".format(n),
            "terminal", in_root('claude "/kdp-case {}"'.format(n))))
    if not items:
        items = [info("🤷 Nothing found for case " + n, "no ticket_url set, no note and no repro model with this number")]
    return {"items": items}


PLUGIN_LIST = os.path.join(ROOT, "scripts", "cli", "confluent-hub-plugin-list.txt")
PLUGIN_LIST_TTL = 7 * 86400
PLUGIN_KINDS = {"🤖": "fully managed", "🔗": "Confluent, self-managed", "👽": "partner / community"}
VERSION_RE = re.compile(r"^v?\d+(\.\d+)*([.-][0-9A-Za-z]+)*$")


def refresh_plugin_list():
    """playground generate-connector-plugin-list (Confluent Hub API) in the background, the file shell completion uses."""
    os.makedirs(CACHE_DIR, exist_ok=True)
    lock = os.path.join(CACHE_DIR, "plugin-list.lock")
    if os.path.exists(lock) and time.time() - os.path.getmtime(lock) < 180:
        return
    open(lock, "w").close()
    subprocess.Popen(
        ["/bin/bash", "-c", '"$1" generate-connector-plugin-list > /dev/null 2>&1; rm -f "$2"', "kdp", CLI, lock],
        cwd=ROOT, env=env(), stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def load_plugins():
    """[(name, emoji, source url)] from confluent-hub-plugin-list.txt, or None while it is being generated."""
    if not os.path.exists(PLUGIN_LIST):
        refresh_plugin_list()
        return None
    if time.time() - os.path.getmtime(PLUGIN_LIST) > PLUGIN_LIST_TTL:
        refresh_plugin_list()
    plugins = []
    with open(PLUGIN_LIST, encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line or "#" in line.split("|")[0]:
                continue
            emoji, _, rest = line.partition(" ")
            if emoji not in PLUGIN_KINDS:
                emoji, rest = "", line
            fields = rest.split("|")
            url = fields[1] if len(fields) > 1 and fields[1] not in ("", "null") else ""
            plugins.append((fields[0], emoji, url))
    return plugins


def plugin_matches(plugins, words):
    """Plugins matching every word, best first: exact name, exact short name, prefix, substring, source url."""
    ranked = []
    first = words[0].lower() if words else ""
    for name, emoji, url in plugins:
        n = name.lower()
        short_name = n.split("/")[-1]
        bare = short_name.replace("kafka-connect-", "")
        if not words_match(words, n, url):
            continue
        if n == first:
            score = 0
        elif short_name == first or bare == first:
            score = 1
        elif short_name.startswith(first) or bare.startswith(first):
            score = 2
        elif words_match(words, n):
            score = 3
        else:
            score = 4
        # Confluent plugins first at equal score
        ranked.append((score, {"🔗": 0, "🤖": 1}.get(emoji, 2), n, (name, emoji, url)))
    return [x[-1] for x in sorted(ranked)]


def plugin_name(p):
    if "/" not in p and p.startswith("kafka-connect-"):
        return "confluentinc/" + p
    return p


def mode_plugin_list(rest):
    """kdp plugin <words> [version]: pick the plugin, ↩ fills in kdp plugin <owner/name> [version] and shows the actions."""
    w = rest.split()
    words = [x for x in w if not VERSION_RE.match(x)]
    version = next((x for x in w if VERSION_RE.match(x)), "")
    plugins = load_plugins()
    if plugins is None:
        return {"rerun": 2, "items": [info("⏳ Building the connector plugin list…",
                                           "playground generate-connector-plugin-list (Confluent Hub) runs in the background")]}
    hits = plugin_matches(plugins, words)
    items = []
    for name, emoji, url in hits[:40]:
        then = "plugin {} {}".format(name, version)
        items.append(item(
            name, " · ".join(x for x in ["{} {}".format(emoji, PLUGIN_KINDS[emoji]) if emoji else "", url] if x),
            autocomplete=then, copy=name,
            mods={"cmd": mod("⌘ open the Confluent Hub page", "open", HUB_URL.format(name)) if emoji != "🤖"
                  else mod("⌘ no Hub page for a fully managed connector"),
                  "alt": mod("⌥ open the source repository", "open", url) if url else mod("⌥ no source repository known")},
        ))
    if words:
        # a class, a fully managed type or an owner/name the list does not know: use it as typed
        typed = plugin_name(words[0])
        items.append(info("➡️ Use \"{}\" as typed".format(typed), "a connector class, a fully managed type (S3_SINK) or owner/name",
                          autocomplete="plugin {} {}".format(typed, version + " " if version else "")))
    if not hits:
        items.insert(0, info("🤷 No plugin in the list matches: " + " ".join(words), "{} plugins in {}".format(len(plugins), os.path.basename(PLUGIN_LIST))))
    return {"items": items}


VERSIONS_TTL = 3600


def plugin_versions(p, plugins):
    """[(version, release date, days ago)] newest first from connector-plugin versions --json (Confluent Hub),
    cached one hour per plugin; [] for fully managed plugins (not on the Hub) or on error."""
    if any(name.lower() == p.lower() and emoji == "🤖" for name, emoji, _ in (plugins or [])) or "/" not in p:
        return []
    cache = os.path.join(CACHE_DIR, "versions", re.sub(r"[^A-Za-z0-9._-]", "_", p) + ".json")
    data = None
    if os.path.exists(cache) and time.time() - os.path.getmtime(cache) < VERSIONS_TTL:
        try:
            with open(cache, encoding="utf-8") as f:
                data = json.load(f)
        except ValueError:
            data = None
    if data is None:
        data, _ = run_json(["connector-plugin", "versions", "-c", p, "--json"], timeout=20)
        if not isinstance(data, dict):
            return []
        os.makedirs(os.path.dirname(cache), exist_ok=True)
        with open(cache, "w", encoding="utf-8") as f:
            json.dump(data, f)
    versions = [(v.get("version"), v.get("release_date"), v.get("days_ago")) for v in data.get("versions") or [] if v.get("version")]
    return list(reversed(versions))


def version_items(p, versions, typed=""):
    """🔢 one item per version (newest first), ↩ fills in kdp plugin <p> <version> and shows the actions for it."""
    latest = versions[0][0] if versions else None
    hits = [v for v in versions if not typed or v[0].startswith(typed)] or [v for v in versions if typed in v[0]]
    items = []
    for version, date, days in hits[:60]:
        when = " · ".join(x for x in [date or "", "{} days ago".format(days) if days is not None else ""] if x)
        items.append(info(
            "🔢 {}{}".format(version, "  (latest)" if version == latest else ""),
            (when + " · " if when else "") + "↩ changelog since, jars, CVE scan, info --from, source at this version",
            autocomplete="plugin {} {} ".format(p, version)))
    return items


FM_VERSIONS_TTL = 6 * 3600


def is_fully_managed(p, plugins):
    return any(name.lower() == p.lower() and emoji == "🤖" for name, emoji, _ in (plugins or []))


def fm_versions(p):
    """connector versions of a fully managed plugin, newest first: [(connector version, first cc-connect, last cc-connect)],
    None while connector-plugin fm-versions --json (about 30 s, VPN + GH_TOKEN) runs in the background, [] when it failed."""
    os.makedirs(os.path.join(CACHE_DIR, "versions"), exist_ok=True)
    base = os.path.join(CACHE_DIR, "versions", re.sub(r"[^A-Za-z0-9._-]", "_", p) + ".fm")
    cache, lock = base + ".json", base + ".lock"
    fresh = os.path.exists(cache) and time.time() - os.path.getmtime(cache) < FM_VERSIONS_TTL
    if not fresh:
        if not (os.path.exists(lock) and time.time() - os.path.getmtime(lock) < 120):
            open(lock, "w").close()
            subprocess.Popen(
                ["/bin/bash", "-c", '"$1" connector-plugin fm-versions -c "$2" --last 60 --json > "$3.tmp" 2>/dev/null; '
                 'mv "$3.tmp" "$3"; rm -f "$4"', "kdp", CLI, p, cache, lock],
                cwd=ROOT, env=env(), stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
        if not os.path.exists(cache):
            return None
    try:
        with open(cache, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        return []
    return [(c.get("connector_version"), c.get("from"), c.get("to")) for c in reversed(data.get("changes") or [])]


def fm_plugin_page(p, v, rest):
    """Actions of a fully managed plugin: its versions are cc-connect images (connector-plugin fm-versions)."""
    base = "playground connector-plugin {{}} -c {}".format(q(p))
    cmd = lambda sub, extra="": in_root((base.format(sub) + " " + extra).strip())
    items = [
        item("ℹ️ Info: license, examples, self-managed equivalent", "connector-plugin info", "output", cmd("info")),
        item("☁️ cc-connect images and connector versions", "connector-plugin fm-versions --last 20 --with-log (VPN + GH_TOKEN)",
             "output", cmd("fm-versions", "--last 20 --with-log")),
    ]
    if v:
        items += [
            item("🔍 What cc-connect " + v + " ships", "connector-plugin fm-versions --cc-connect-version " + v,
                 "output", cmd("fm-versions", "--cc-connect-version " + q(v))),
            item("💻 Source code at cc-connect " + v, "connector-plugin sourcecode --connector-tag {} --only-show-url".format(v),
                 "output", cmd("sourcecode", "--connector-tag {} --only-show-url".format(q(v)))),
        ]
        return {"items": items}
    items.append(item("💻 Source code URL", "connector-plugin sourcecode --only-show-url", "output", cmd("sourcecode", "--only-show-url")))
    versions = fm_versions(p)
    if versions is None:
        return {"rerun": 2, "items": items + [info("⏳ Listing the cc-connect versions… (about 30 s, VPN + GH_TOKEN)",
                                                     "connector-plugin fm-versions runs in the background")]}
    if not versions:
        items.append(info("🤷 Could not list the cc-connect versions", "VPN on? GH_TOKEN set? (retried in 6 hours, or delete the cache)"))
    for version, first, last in versions[:40]:
        items.append(info("🔢 connector {}".format(version), "cc-connect {} → {} · ↩ what the image ships, source at that tag".format(first, last),
                          autocomplete="plugin {} {} ".format(p, last)))
    return {"items": items}


def plugin_known(p, plugins):
    return any(p.lower() == name.lower() for name, _, _ in (plugins or []))


def mode_plugin(rest):
    w = rest.split()
    if not w:
        return mode_plugin_list(rest)
    p = plugin_name(w[0])
    # the actions once the plugin is known (picked in the list) or typed as a class / fully managed type / owner/name,
    # and followed by a space or a version; otherwise the list to pick from
    as_typed = "." in p or "/" in p or re.fullmatch(r"[A-Z0-9_]+", p)
    plugins = load_plugins()
    if not (plugin_known(p, plugins) or (as_typed and (len(w) > 1 or rest.endswith(" ")))):
        return mode_plugin_list(rest)
    v = w[1] if len(w) > 1 else None
    if is_fully_managed(p, plugins):
        return fm_plugin_page(p, v, rest)
    versions = plugin_versions(p, plugins)
    # a partial version (10.7) or a version the Hub does not list: pick one in the list
    if v and versions and v not in [x[0] for x in versions] and not rest.endswith(" "):
        picked = version_items(p, versions, v)
        if picked:
            return {"items": picked + [info("➡️ Use version {} as typed".format(v), "not in the Confluent Hub list",
                                             autocomplete="plugin {} {} ".format(p, v))]}
    base = "playground connector-plugin {{}} -c {}".format(q(p))
    need_v = "pick a version below, or type it: kdp plugin {} <version>".format(p) if versions else \
        "add a version: kdp plugin {} <version>".format(p)

    def cmd(sub, extra=""):
        return in_root((base.format(sub) + " " + extra).strip())

    items = [
        item("ℹ️ Info: license, latest version, examples, fully managed equivalents" + (", how far is " + v if v else ""),
             "connector-plugin info", "output", cmd("info", "--from " + q(v) if v else "")),
        item("📜 Changelog since " + v, "connector-plugin changelog --from " + v, "output", cmd("changelog", "--from " + q(v)))
        if v else info("📜 Changelog", need_v, autocomplete="plugin {} ".format(p)),
        item("💻 Source code URL" + (" at " + v if v else ""), "connector-plugin sourcecode --only-show-url", "output",
             cmd("sourcecode", ("--connector-tag " + q(v) + " " if v else "") + "--only-show-url")),
        item("📦 Dependencies (jars) of " + v, "connector-plugin dependencies --connector-tag " + v, "output",
             cmd("dependencies", "--connector-tag " + q(v))) if v else info("📦 Dependencies (jars)", need_v, autocomplete="plugin {} ".format(p)),
        item("🛡️ CVE scan of " + v, "connector-plugin cve-scan --connector-tag " + v + " (grype in Docker)", "output",
             cmd("cve-scan", "--connector-tag " + q(v))) if v else info("🛡️ CVE scan", need_v, autocomplete="plugin {} ".format(p)),
        item("☁️ Fully managed versions (cc-connect images)", "connector-plugin fm-versions --last 20 (Confluent employees: VPN + GH_TOKEN)", "output",
             cmd("fm-versions", "--last 20")),
    ]
    fully_managed = any(name.lower() == p.lower() and emoji == "🤖" for name, emoji, _ in (plugins or []))
    if "/" in p and not fully_managed:
        items.append(item("🌐 Confluent Hub page", HUB_URL.format(p), "open", HUB_URL.format(p)))
    items.append(info("🔎 Examples using " + p, "↩ find-example", autocomplete="find " + p.split("/")[-1].replace("kafka-connect-", "")))
    if not v:
        # versions need a version: drop their placeholders, the version list below replaces them
        if versions:
            items = [i for i in items if i.get("valid") or not i["subtitle"].startswith("pick a version")]
        items += version_items(p, versions)
    return {"items": items}


CONFIG_KEYS_CACHE = os.path.join(CACHE_DIR, "config-keys.json")


def config_reference_files():
    """The */config-<connector class>.txt references recorded by CI, the files config-key reads."""
    try:
        p = subprocess.run(["git", "ls-files", "--", "*/config-*.txt"], cwd=ROOT, capture_output=True, text=True, timeout=10)
        files = [f for f in p.stdout.splitlines() if f]
    except (OSError, subprocess.TimeoutExpired):
        files = []
    return files or [os.path.relpath(f, ROOT) for f in glob.glob(os.path.join(ROOT, "*", "*", "config-*.txt"))]


CONFIG_TYPES = {"STRING", "INT", "LONG", "SHORT", "DOUBLE", "BOOLEAN", "LIST", "PASSWORD", "CLASS"}


def parse_config_reference(path):
    """{key: (type, default, first doc line)} of one config-<class>.txt."""
    keys = {}
    cur = {}

    def flush():
        if cur.get("key"):
            typ, default, doc = cur.get("type", ""), cur.get("default", ""), cur.get("doc", "")
            # fully managed references are written with the fields shifted by one:
            # Type = required, Default = type, Importance = documentation
            if typ in ("true", "false") and default.upper() in CONFIG_TYPES:
                typ, default, doc = default, "", doc or cur.get("importance", "")
            keys[cur["key"]] = (typ, default, doc)
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            stripped = line.strip()
            if stripped.startswith("🔘 "):
                flush()
                cur = {"key": stripped[2:].strip()}
            elif stripped.startswith("====="):
                # a section header ends the current key
                flush()
                cur = {}
            elif cur.get("key"):
                m = re.match(r"- (Type|Default|Importance):\s*(.*)$", stripped)
                if m:
                    cur[m.group(1).lower()] = m.group(2).strip()
                elif stripped and "doc" not in cur and not stripped.startswith("- "):
                    cur["doc"] = re.sub(r"<[^>]+>", "", stripped)
    flush()
    return keys


def load_config_keys():
    """{key: [[class, type, default, doc], ...]}, rebuilt when the reference files change."""
    files = config_reference_files()
    sig = "{}:{}".format(len(files), max([os.path.getmtime(os.path.join(ROOT, f)) for f in files] or [0]))
    try:
        with open(CONFIG_KEYS_CACHE, encoding="utf-8") as f:
            cached = json.load(f)
        if cached.get("sig") == sig:
            return cached["keys"]
    except (OSError, ValueError):
        pass
    index, seen = {}, set()
    for f in sorted(files):
        cls = os.path.basename(f)[len("config-"):-len(".txt")]
        if cls in seen:   # several examples of one connector carry the same reference
            continue
        seen.add(cls)
        try:
            for key, (typ, default, doc) in parse_config_reference(os.path.join(ROOT, f)).items():
                index.setdefault(key, []).append([cls, typ, default, doc])
        except OSError:
            continue
    os.makedirs(CACHE_DIR, exist_ok=True)
    with open(CONFIG_KEYS_CACHE, "w", encoding="utf-8") as f:
        json.dump({"sig": sig, "keys": index}, f)
    return index


def key_summary(entries):
    defaults = {}
    for _, _, default, _ in entries:
        defaults[default] = defaults.get(default, 0) + 1
    common = max(defaults, key=defaults.get) if defaults else ""
    doc = next((e[3] for e in entries if e[3]), "")
    typ = next((e[1] for e in entries if e[1]), "")
    bits = ["{} connector{}".format(len(entries), "s" if len(entries) > 1 else "")]
    if typ:
        bits.append(typ)
    if common not in ("", "null"):
        bits.append("default " + common + (" (most common)" if len(defaults) > 1 else ""))
    if doc:
        bits.append(short(doc, 80))
    return " · ".join(bits)


def mode_key_list(rest, index):
    words = rest.split()
    first = words[0].lower() if words else ""
    ranked = []
    for key, entries in index.items():
        k = key.lower()
        if not words_match(words, k):
            continue
        score = 0 if k == first else 1 if k.startswith(first) else 2 if ("." + first) in k else 3
        ranked.append((score, -len(entries), k, key))
    items = []
    for _, _, _, key in sorted(ranked)[:50]:
        items.append(info(key, key_summary(index[key]), autocomplete="key {} ".format(key)))
    if words and words[0] not in index:
        items.append(info("➡️ Use \"{}\" as typed".format(words[0]), "a key the references do not have (worker or client key…)",
                          autocomplete="key {} ".format(words[0])))
    if not ranked:
        items.insert(0, info("🤷 No config key matches: " + " ".join(words), "{} keys in the connector references".format(len(index))))
    return {"items": items}


def mode_key(rest):
    """kdp key <words>: pick a key, then a connector that has it, then config-key [--since-version]."""
    w = rest.split()
    index = load_config_keys()
    if not w:
        return {"items": [info("🔑 Type words of a config key", "{} keys from the connector references: ↩ picks one".format(len(index)))]}
    k = w[0]
    # the actions once the key is known (picked in the list) or typed and followed by a space; else the list
    # an unknown first word is a search (several words narrow it), unless it is alone and followed by a space ("as typed")
    if k not in index and not (len(w) == 1 and rest.endswith(" ")):
        return mode_key_list(rest, index)
    cls = w[1] if len(w) > 1 else None
    entries = index.get(k, [])
    classes = [e[0] for e in entries]
    # a partial connector class: pick it in the list of the connectors that have the key
    if cls and classes and cls not in classes and not rest.endswith(" "):
        hits = [e for e in entries if cls.lower() in e[0].lower()]
        if hits:
            entries, cls = hits, None
    extra = " --connector-class " + q(cls) if cls else ""
    items = [item("🔑 " + k + (" in " + cls.split(".")[-1] if cls else ""),
                  "connector-plugin config-key: doc, default, values used in examples",
                  "output", in_root("playground connector-plugin config-key -k {}{}".format(q(k), extra)))]
    if cls:
        items.append(item("📅 Since which version does " + k + " exist?", "config-key --since-version (downloads plugin versions)",
                          "output", in_root("playground connector-plugin config-key -k {}{} --since-version".format(q(k), extra))))
    else:
        if not entries:
            items.append(info("📅 Since which version?", "add a connector class: kdp key {} <class>".format(k), autocomplete="key {} ".format(k)))
        for c, typ, default, doc in sorted(entries, key=lambda e: e[0].lower()):
            sub = " · ".join(x for x in [typ, "default " + default if default not in ("", "null") else "", short(doc, 70)] if x)
            items.append(info("🔌 " + c, (sub + " · " if sub else "") + "↩ this connector: doc, since which version",
                              autocomplete="key {} {} ".format(k, c)))
    return {"items": items}


DOC_PAGES_EXTRA = ["how-to-use", "how-it-works", "reusables", "reports", "sessions", "claude-code", "deep-dives"]


def mode_docs(rest):
    words = rest.split()
    pages = sorted(glob.glob(os.path.join(DOCS_DIR, "deep-dive-*.md")))
    pages = [os.path.join(DOCS_DIR, p + ".md") for p in DOC_PAGES_EXTRA] + pages
    pages += sorted(glob.glob(os.path.join(DOCS_DIR, "toolkit-*.md")))
    items = []
    for p in pages:
        if not os.path.exists(p):
            continue
        title, _ = parse_note(p)
        page = os.path.basename(p)[:-3]
        if not words_match(words, page, title):
            continue
        url = DOCS_URL.format(page)
        items.append(item(short(title or page, 100), url, "open", url,
                          mods={"cmd": mod("⌘ open the markdown in VS Code", "code", p),
                                "shift": mod("⇧ copy the URL", "copy", url)},
                          quicklook=p))
    if not items:
        items = [info("🤷 No page matches: " + rest)]
    return {"items": items}


def mode_status(rest):
    rows = [
        ("🚦 playground status", "containers, exited / restarting ones", "playground status"),
        ("🔌 Connector status", "playground connector status", "playground connector status"),
        ("🩺 Diagnose connectors", "status + error digest + lag + next steps", "playground connector diagnose"),
        ("🔥 Connect errors", "container logs -c connect --errors", "playground container logs -c connect --errors"),
        ("🏥 Broker health", "under-replicated / offline partitions, quorum", "playground broker health"),
    ]
    return {"items": [item(t, s, "output", in_root(c), copy=c) for t, s, c in rows if words_match(rest.split(), t, c)]}


# --------------------------------------------------------------------------- running environment

LIVE_TTL = 5


def cached_cli_text(name, args, ttl, timeout=20):
    """stdout of a playground command (colour codes stripped), cached a few seconds while the query is typed."""
    path = os.path.join(CACHE_DIR, "live-" + name + ".txt")
    if os.path.exists(path) and time.time() - os.path.getmtime(path) < ttl:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    try:
        p = subprocess.run([CLI] + args, cwd=ROOT, env=env(), capture_output=True, text=True, timeout=timeout,
                           stdin=subprocess.DEVNULL)
        text = ANSI.sub("", p.stdout)
    except (OSError, subprocess.TimeoutExpired):
        return ""
    os.makedirs(CACHE_DIR, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    return text


CONNECTOR_STATES = "RUNNING|FAILED|PAUSED|UNASSIGNED|STOPPED|RESTARTING|DESTROYED"


def running_connectors():
    """[(name, status, tasks)] from playground connector status (any environment), or names only from get-connector-list."""
    text = cached_cli_text("connector-status", ["connector", "status"], LIVE_TTL)
    rows, in_table = [], False
    for line in text.splitlines():
        if line.startswith("Name") and "Status" in line and "Tasks" in line:
            in_table = True
            continue
        if not in_table or not line.strip() or line.startswith("---") or re.match(r"\d\d:\d\d:\d\d ", line):
            continue
        # emojis take 2 columns in the table: parse the words, not the column positions
        name = line.split()[0]
        m = re.search(r"\b({})\b".format(CONNECTOR_STATES), line)
        status = m.group(1) if m else ""
        tasks = re.findall(r"(\d+):\s*\S*\s*({})".format(CONNECTOR_STATES), line[m.end():] if m else line)
        rows.append((name, status, ", ".join("{} {}".format(t, st) for t, st in tasks)))
    if rows:
        return rows
    names = cached_cli_text("connector-list", ["get-connector-list"], LIVE_TTL).split()
    return [(n, "", "") for n in names]


def connector_actions(name, status):
    c = q(name)
    pg = lambda sub: in_root("playground connector {} --connector {}".format(sub, c))
    failed = "FAILED" in status
    rows = [
        ("🩺 Diagnose", "status + error digest + lag + offsets + next steps (diagnose --no-open)", pg("diagnose --no-open")),
        ("🚦 Status", "connector status", pg("status")),
        ("🧩 Tasks", "state, worker, config per task, partitions of sink tasks", pg("tasks")),
        ("📈 Metrics", "JMX task metrics, Debezium lag / queue / snapshot", pg("metrics")),
        ("🕰️ History", "states, restarts and config changes from connect-status / connect-configs", pg("history")),
        ("⚙️ Config", "connector show-config", pg("show-config")),
        ("📍 Offsets", "connector offsets get", pg("offsets get")),
        ("🧵 Topics", "active topics of the connector", pg("topics")),
    ]
    if not failed:
        rows.insert(0, rows.pop(1))   # status first, diagnose first when it failed
    items = [item("{} {}".format(t, name), sub, "output", cmd) for t, sub, cmd in rows]
    # actions that change the connector: shown with a warning, still one keystroke (all reversible)
    changes = [("🔁 Restart failed tasks of " + name, "connector restart --only-failed", pg("restart --only-failed"))]
    if "PAUSED" in status:
        changes.append(("▶️ Resume " + name, "connector resume", pg("resume")))
    elif status:
        changes.append(("⏸️ Pause " + name, "connector pause", pg("pause")))
    items += [item(t, "⚠️ changes the connector · " + sub, "output", cmd) for t, sub, cmd in changes]
    items.append(info("📜 Logs of the connect worker", "kdp logs connect", autocomplete="logs connect "))
    return items


STATUS_EMOJI = (("FAILED", "❌"), ("PAUSED", "⏸️"), ("RUNNING", "✅"), ("UNASSIGNED", "⏳"), ("STOPPED", "⏹️"))


def mode_connector(rest):
    """kdp connector [words]: pick a running connector (with its state), then its actions."""
    w = rest.split()
    connectors = running_connectors()
    names = [c[0] for c in connectors]
    if w and w[0] in names and (len(w) > 1 or rest.endswith(" ") or len([n for n in names if n.startswith(w[0])]) == 1):
        status = next(c[1] for c in connectors if c[0] == w[0])
        return {"items": connector_actions(w[0], status)}
    if not connectors:
        return {"items": [info("🤷 No connector running", "playground connector status shows none in the current environment"),
                          item("🚦 playground status", "containers, exited / restarting ones", "output", in_root("playground status"))]}
    hits = [c for c in connectors if words_match(w, c[0])]
    # failed first, then by name
    hits.sort(key=lambda c: ("FAILED" not in c[1], c[0].lower()))
    items = []
    for name, status, tasks in hits:
        emoji = next((e for k, e in STATUS_EMOJI if k in status), "🧩")
        sub = " · ".join(x for x in [status, ("tasks " + tasks) if tasks else ""] if x) or "↩ status, diagnose, tasks, metrics…"
        items.append(info("{} {}".format(emoji, name), sub, autocomplete="connector {} ".format(name)))
    if not items:
        items = [info("🤷 No connector matches: " + rest, "{} running: {}".format(len(names), ", ".join(names)[:100]))]
    items.append(item("🧩 Status of all connectors", "connector status", "output", in_root("playground connector status")))
    return {"items": items}


def mode_logs(rest):
    """kdp logs [container] [pattern]: pick a container, then its errors, last lines or the lines matching a pattern."""
    w = rest.split()
    containers = cached_cli_text("container-list", ["get-container-list"], LIVE_TTL).split()
    if w and w[0] in containers and (len(w) > 1 or rest.endswith(" ") or len([c for c in containers if c.startswith(w[0])]) == 1):
        c = w[0]
        pattern = " ".join(w[1:])
        logs = lambda flags: in_root("playground container logs --container {} {}".format(q(c), flags))
        items = []
        if pattern:
            items.append(item("🔍 Lines of {} matching \"{}\"".format(c, pattern), "container logs --grep … --no-follow",
                              "output", logs("--grep {} --no-follow".format(q(pattern)))))
        items += [
            item("🔥 Errors of " + c, "ERROR / FATAL records, de-duplicated, Caused by chains (--errors)", "output", logs("--errors")),
            item("⚠️ Errors and warnings of " + c, "--errors --include-warnings", "output", logs("--errors --include-warnings")),
            item("🕐 Errors of the last 10 minutes of " + c, "--errors --since 10m", "output", logs("--errors --since 10m")),
            item("📜 Last 300 lines of " + c, "--no-follow --tail 300", "output", logs("--no-follow --tail 300")),
            item("👀 Follow the logs of " + c, "in the terminal (container logs follows until ctrl-c)", "terminal", logs("").rstrip()),
        ]
        if not pattern:
            items.append(info("🔍 Grep the logs of " + c, "type a pattern: kdp logs {} <pattern>".format(c), autocomplete="logs {} ".format(c)))
        return {"items": items}
    if not containers:
        return {"items": [info("🤷 No container running", "playground get-container-list returns none"),
                          item("🚦 playground status", "containers, exited / restarting ones", "output", in_root("playground status"))]}
    # connect first: it is the one you want most of the time
    hits = sorted([c for c in containers if words_match(w[:1], c)], key=lambda c: (not c.startswith("connect"), c))
    items = [info("📜 " + c, "↩ errors, last lines, grep, follow", autocomplete="logs {} ".format(c)) for c in hits]
    if not items:
        items = [info("🤷 No container matches: " + rest, "running: " + ", ".join(containers)[:120])]
    return {"items": items}


def picked(w, rest, names):
    """The first word is one of the names, picked (followed by a space or more words) or the only one starting so."""
    return bool(w) and w[0] in names and (len(w) > 1 or rest.endswith(" ") or len([n for n in names if n.startswith(w[0])]) == 1)


def mode_topic(rest):
    """kdp topic [words]: pick a topic (internal ones only when the query starts with _), then its actions."""
    w = rest.split()
    topics = cached_cli_text("topic-list", ["get-topic-list"], LIVE_TTL).split()
    if picked(w, rest, topics):
        t = w[0]
        pattern = " ".join(w[1:])
        tp = lambda sub: in_root("playground topic {} --topic {}".format(sub, q(t)))
        items = []
        if pattern:
            items.append(item("🔍 Records of {} matching \"{}\"".format(t, pattern), "topic consume --grep",
                              "output", tp("consume --grep {}".format(q(pattern)))))
        items += [
            item("📋 Describe " + t, "partitions, replicas, configs (topic describe)", "output", tp("describe")),
            item("🔢 Number of records of " + t, "topic get-number-records", "output", tp("get-number-records")),
            item("👀 Last 10 records of " + t, "topic consume --last 10 (the most recent, across partitions)", "output", tp("consume --last 10")),
            item("⏮️ First 10 records of " + t, "topic consume --max-messages 10", "output", tp("consume --max-messages 10")),
        ]
        if re.search(r"dlq|dead|error", t, re.I):
            items.insert(0, item("🧯 Dead letter queue " + t, "records grouped by exception and root cause (topic dlq inspect)",
                                 "output", tp("dlq inspect --no-open")))
        if not pattern:
            items.append(info("🔍 Grep the records of " + t, "type a pattern: kdp topic {} <pattern>".format(t), autocomplete="topic {} ".format(t)))
        return {"items": items}
    if not topics:
        return {"items": [info("🤷 No topic", "playground get-topic-list returns none (is the environment running?)")]}
    internal = bool(w) and w[0].startswith("_")
    hits = [t for t in topics if words_match(w, t) and (internal or not t.startswith("_"))]
    hits.sort(key=lambda t: (not re.search(r"dlq|dead|error", t, re.I), t))
    items = [info(("🧯 " if re.search(r"dlq|dead|error", t, re.I) else "🧵 ") + t, "↩ describe, records, last records, DLQ inspect",
                  autocomplete="topic {} ".format(t)) for t in hits[:60]]
    if not items:
        items = [info("🤷 No topic matches: " + rest, "internal topics are listed when the query starts with _")]
    return {"items": items}


def mode_schema(rest):
    """kdp schema [words]: pick a subject, then describe, latest schema, history, diff, compatibility."""
    w = rest.split()
    subjects = cached_cli_text("subject-list", ["get-subject-list"], LIVE_TTL).split()
    if picked(w, rest, subjects):
        sub = w[0]
        sc = lambda c: in_root("playground schema {} --subject {}".format(c, q(sub)))
        return {"items": [
            item("📖 Describe " + sub, "compatibility rule and mode with their source, versions, references, shared ids", "output", sc("describe")),
            item("📄 Latest schema of " + sub, "schema get", "output", sc("get")),
            item("🕰️ History of " + sub, "registrations, soft / hard deletes, rule changes from _schemas", "output", sc("history")),
            item("🔀 Diff of the last two versions of " + sub, "field-level changes + the registry's verdict per rule", "output", sc("diff")),
            item("🛡️ Compatibility of " + sub, "schema get-compatibility", "output", sc("get-compatibility")),
        ]}
    if not subjects:
        return {"items": [info("🤷 No subject", "playground get-subject-list returns none (Schema Registry running?)")]}
    hits = [x for x in subjects if words_match(w, x)]
    items = [info("📐 " + x, "↩ describe, latest schema, history, diff, compatibility", autocomplete="schema {} ".format(x)) for x in hits[:60]]
    return {"items": items or [info("🤷 No subject matches: " + rest)]}


def ci_tests():
    """Test directories of the CI matrix (the 🚀 strings of .github/workflows/ci.yml)."""
    try:
        with open(os.path.join(ROOT, ".github", "workflows", "ci.yml"), encoding="utf-8") as f:
            text = f.read()
    except OSError:
        return []
    tests = set()
    for group in re.findall(r'"🚀 ([^"]+)"', text):
        # test directories only (some strings also hold ${{ … }} expressions)
        tests.update(t for t in group.split() if re.fullmatch(r"[a-z0-9-]+/[A-Za-z0-9_./-]+", t))
    return sorted(tests)


def mode_ci(rest):
    """kdp ci [words]: pick a test directory of the CI matrix, then its CI result."""
    w = rest.split()
    tests = ci_tests()
    if picked(w, rest, tests):
        d = w[0]
        issue = "https://github.com/vdesabou/kafka-docker-playground/issues?q=" + "is%3Aissue+in%3Atitle+%22%F0%9F%94%A5+{}%22".format(d.replace("/", "%2F"))
        ci = lambda extra: in_root("playground get-ci-result --test {} {}".format(q(d), extra).strip())
        return {"items": [
            item("🤖 CI result of " + d, "get-ci-result: last runs per CP version and environment", "output", ci("")),
            item("📜 CI result of " + d + " with the logs", "get-ci-result --logs --no-open (HTML report: ⇧↩ in the view)", "output", ci("--logs --no-open")),
            item("🔥 GitHub issues of " + d, "🔥 issues opened by CI for this test", "open", issue),
            item("📂 Open " + d + " in VS Code", os.path.join(ROOT, d), "code", os.path.join(ROOT, d)),
            info("🔎 Examples of " + d, "find-example", autocomplete="find {}".format(d)),
        ]}
    hits = [t for t in tests if words_match(w, t)]
    items = [info("🤖 " + t, "↩ CI result, logs, 🔥 issues", autocomplete="ci {} ".format(t)) for t in hits[:60]]
    return {"items": items or [info("🤷 No CI test matches: " + rest, "{} test directories in ci.yml".format(len(tests)))]}


MODES = {
    "how": mode_how, "find": mode_find, "repro": mode_repro, "history": mode_history, "case": mode_case, "notes": mode_notes,
    "plugin": mode_plugin, "key": mode_key, "docs": mode_docs, "status": mode_status,
    "connector": mode_connector, "logs": mode_logs, "topic": mode_topic, "schema": mode_schema, "ci": mode_ci,
}


def script_filter(query):
    raw = query
    query = re.sub(r"\s+", " ", query.replace("\n", " ")).lstrip()
    if not os.path.exists(CLI):
        return {"items": [info("⚠️ kafka-docker-playground not found in " + ROOT,
                               "set kdp_root in the workflow configuration")]}
    first, _, rest = query.partition(" ")
    fn = MODES.get(first.lower())
    if fn:
        if not available(first.lower()):
            return {"items": [info("🚫 kdp {} is not available".format(first.lower()), UNAVAILABLE[first.lower()])]}
        return fn(rest)
    return mode_menu(query, raw)


# --------------------------------------------------------------------------- actions

# VS Code has no command line or URL to run something in its integrated terminal: open a *new* one from the
# command palette (never type into an existing one, it may run a process such as a Claude Code session),
# paste the command and press return. Needs Accessibility for Alfred (System Events keystrokes).
VSCODE_SCRIPT = """
on run argv
    tell application id "com.microsoft.VSCode" to activate
    delay 0.6
    tell application "System Events"
        keystroke "p" using {command down, shift down}
        delay 0.5
        keystroke "Terminal: Create New Terminal"
        delay 0.7
        key code 36
        delay 1.5
        keystroke "v" using command down
        delay 0.3
        key code 36
    end tell
end run
"""

TERMINAL_APP_SCRIPT = """
on run argv
    tell application "Terminal"
        activate
        do script (item 1 of argv)
    end tell
end run
"""


ANSI = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(\x07|\x1b\\)|\x1b[()][0-9A-B]")
VIEW_MAX_LINES = 3000


def md_escape(text):
    """Markdown of the Text View: server1_mydb_CUSTOMERS-value must not turn mydb into italics."""
    return re.sub(r"([\\`*_\[\]<>#|~])", r"\\\1", text)


def display_cmd(cmd):
    prefix = "cd {} && ".format(q(ROOT))
    return cmd[len(prefix):] if cmd.startswith(prefix) else cmd


VIEW_DIR = os.path.join(CACHE_DIR, "view")
VIEW_CURRENT = os.path.join(VIEW_DIR, "current")
VIEW_TRIGGER = "view_output"
BUNDLE_ID = os.environ.get("alfred_workflow_bundleid") or "com.vdesabou.kdp-alfred"
RUN_TRIGGER_SCRIPT = """
on run argv
    tell application id "com.runningwithcrayons.Alfred" to run trigger (item 1 of argv) in workflow (item 2 of argv) with argument (item 3 of argv)
end run
"""


def job_file(job, name, default=""):
    try:
        with open(os.path.join(job, name), encoding="utf-8") as f:
            return f.read().strip()
    except OSError:
        return default


def start_view_job(cmd, title):
    """Run a read-only command in the background, its output going to <cache>/view/<key>/output.log."""
    os.makedirs(VIEW_DIR, exist_ok=True)
    # drop the jobs of previous days
    for old in glob.glob(os.path.join(VIEW_DIR, "*")):
        if os.path.isdir(old) and time.time() - os.path.getmtime(old) > 86400:
            subprocess.run(["rm", "-rf", old])
    key = hashlib.sha1((cmd + "\0" + repr(time.time())).encode()).hexdigest()[:16]
    job = os.path.join(VIEW_DIR, key)
    os.makedirs(job)
    for name, value in (("cmd", cmd), ("title", title), ("start", repr(time.time()))):
        with open(os.path.join(job, name), "w", encoding="utf-8") as f:
            f.write(value)
    subprocess.Popen(
        ["/bin/bash", "-c", 'eval "$1" > "$2" 2>&1 < /dev/null; echo $? > "$3"', "kdp-view", cmd,
         os.path.join(job, "output.log"), os.path.join(job, "exit")],
        cwd=ROOT, env=env(), stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    with open(VIEW_CURRENT, "w") as f:
        f.write(key)
    return key


def view_key(arg=None):
    """The job given by the Text View argument, else the last one started."""
    k = (arg or "").strip()
    if not re.fullmatch(r"[0-9a-f]{16}", k):
        k = job_file(VIEW_DIR, "current")
    return k if k and os.path.isdir(os.path.join(VIEW_DIR, k)) else None


COLOUR_MARKERS = ((re.compile(r"\x1b\[(?:[01];)?(?:31|91)m"), "🔴 "), (re.compile(r"\x1b\[(?:[01];)?(?:35|95)m"), "🟠 "),
                  (re.compile(r"\x1b\[(?:[01];)?(?:32|92)m"), "🟢 "))
EMOJI_START = re.compile(r"^(\d\d:\d\d:\d\d )?[^\x00-\x7F]")


def mark_colours(line):
    """A Markdown view cannot show ANSI colours: red / magenta / green lines get 🔴 / 🟠 / 🟢, unless they start with an emoji."""
    for pattern, marker in COLOUR_MARKERS:
        if pattern.search(line):
            plain = ANSI.sub("", line)
            return plain if EMOJI_START.match(plain.split(" ", 1)[-1] if re.match(r"\d\d:\d\d:\d\d ", plain) else plain) else marker + plain
    return line


def clean_output(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            text = f.read()
    except OSError:
        return ""
    text = "\n".join(mark_colours(line) for line in text.split("\n"))
    text = ANSI.sub("", text)
    # progress bars: keep what a terminal would show after each carriage return
    text = "\n".join(line.split("\r")[-1] for line in text.split("\n"))
    return text


def open_view(cmd, title):
    """Action of a read-only item: start the job, then open the Text View through the workflow's external trigger.

    A Text View reached directly from the script filter result never shows (Alfred closes its window when an
    item is actioned): Alfred's own workflows open their views with run trigger, so does this one.
    """
    key = start_view_job(cmd, title)
    rc, err = osascript(RUN_TRIGGER_SCRIPT, VIEW_TRIGGER, BUNDLE_ID, key)
    if rc != 0:
        return "⚠️ could not open the output view ({}): ⌃↩ runs it in the terminal".format(short(err, 80))
    return ""


REPORT_RE = re.compile(r"(?:file://)?(/[^\s'\"<>]+\.html)\b")


def html_report(output):
    """The last HTML report path printed by the command (diagnose, dlq inspect, get-ci-result…), if it exists."""
    paths = [m.group(1) for m in REPORT_RE.finditer(output)]
    return next((p for p in reversed(paths) if os.path.exists(p)), None)


def view(arg=None):
    """Script of the Text View: the output of the job so far, rerun every 0.5 s until the command exits.

    Alfred runs it again on ↩ with the text of the input field: empty = run the command again, text = keep the
    lines that contain it. "Run again" needs the final output to have been shown ("shown" file): that response
    has no rerun, so the next empty call is a ↩ and never one of the automatic 0.5 s reruns, which would
    otherwise restart the command in a loop.
    """
    arg = (arg or "").strip()
    line_filter = ""
    if re.fullmatch(r"[0-9a-f]{16}", arg) and os.path.isdir(os.path.join(VIEW_DIR, arg)):
        key = arg
        with open(VIEW_CURRENT, "w") as f:
            f.write(key)
    else:
        key = view_key()
        watch_cmd = re.fullmatch(r"watch(?:\s+(\d+))?", arg, re.I)
        if key and watch_cmd:
            # watch [seconds]: run the command again every N seconds while the view is open
            with open(os.path.join(VIEW_DIR, key, "watch"), "w") as f:
                f.write(str(max(2, int(watch_cmd.group(1) or 5))))
        elif key and arg.lower() in ("stop", "unwatch"):
            try:
                os.remove(os.path.join(VIEW_DIR, key, "watch"))
            except OSError:
                pass
        elif key and arg:
            line_filter = arg
        elif key and os.path.exists(os.path.join(VIEW_DIR, key, "shown")):
            key = restart_view_job(key)
    if not key:
        return {"response": "Nothing to show."}
    job = os.path.join(VIEW_DIR, key)
    watch = job_file(job, "watch")
    if watch and os.path.exists(os.path.join(job, "exit")) and time.time() - os.path.getmtime(os.path.join(job, "exit")) >= int(watch):
        key = restart_view_job(key)
        job = os.path.join(VIEW_DIR, key)
    cmd, title = job_file(job, "cmd"), job_file(job, "title", "kdp")
    # watching: keep the previous output on screen until the new run is done
    shown_job = job
    previous = job_file(job, "previous")
    if watch and previous and not os.path.exists(os.path.join(job, "exit")) and os.path.isdir(os.path.join(VIEW_DIR, previous)):
        shown_job = os.path.join(VIEW_DIR, previous)
    try:
        elapsed = int(time.time() - float(job_file(job, "start", "0")))
    except ValueError:
        elapsed = 0
    done = os.path.exists(os.path.join(job, "exit"))
    code = job_file(job, "exit")
    out = clean_output(os.path.join(shown_job, "output.log")).rstrip()
    report = html_report(out)
    if line_filter:
        kept = [x for x in out.split("\n") if line_filter.lower() in x.lower()]
        out = "\n".join(kept)
    lines = out.split("\n")
    if len(lines) > VIEW_MAX_LINES:
        out = "✂️ {} first lines not shown (⌘↩ copies everything)\n".format(len(lines) - VIEW_MAX_LINES) + "\n".join(lines[-VIEW_MAX_LINES:])
    fence = "```"
    while fence in out:
        fence += "`"
    body = "{f}text\n{o}\n{f}".format(f=fence, o=out) if out else ("_no output_" if done else "⏳ running…")
    response = "**{}**\n\n`{}`\n\n".format(md_escape(title), display_cmd(cmd))
    if line_filter:
        response += "🔍 lines containing **{}**: {} · ↩ with an empty field runs the command again\n\n".format(
            line_filter, len([x for x in out.split("\n") if x]))
    response += body
    if report:
        response += "\n\n📊 HTML report: `{}` · ⇧↩ opens it".format(report)
    if not done:
        status = "⏳ running {}s".format(elapsed)
    elif code == "0":
        status = "✅ done in {}s".format(elapsed)
    else:
        status = "❌ exit {} after {}s".format(code, elapsed)
    if watch:
        status = "👀 every {}s (stop↩) · {}".format(watch, "⏳ refreshing" if not done else status + " at " + time.strftime("%H:%M:%S"))
    result = {
        "response": response,
        "footer": status + (" · ↩ run again" if done and not watch else "") + (" · watch↩" if not watch else "")
                  + " · text↩ filter · ⌘↩ copy output · ⌥↩ copy command" + (" · ⇧↩ open report" if report else "") + " · ⎋ close",
        "behaviour": {"response": "replace", "scroll": "auto" if done else "end"},
    }
    if done:
        # final output on screen: from now on an empty ↩ means "run again"
        open(os.path.join(job, "shown"), "w").close()
    if not done or watch:
        result["rerun"] = 0.5 if not done else 1
    return result


def restart_view_job(key):
    """Run the command of job <key> again (↩ or watch): the new job keeps the title and the watch interval."""
    job = os.path.join(VIEW_DIR, key)
    new = start_view_job(job_file(job, "cmd"), job_file(job, "title", "kdp"))
    for name, value in (("previous", key), ("watch", job_file(job, "watch"))):
        if value:
            with open(os.path.join(VIEW_DIR, new, name), "w") as f:
                f.write(value)
    return new


def view_open_report():
    key = view_key()
    report = html_report(clean_output(os.path.join(VIEW_DIR, key, "output.log"))) if key else None
    if not report:
        return "🤷 No HTML report in this output"
    subprocess.run(["open", report])
    return ""


def view_copy(what):
    key = view_key()
    job = os.path.join(VIEW_DIR, key) if key else ""
    if what == "command":
        text = display_cmd(job_file(job, "cmd")) if job else ""
    else:
        text = (clean_output(os.path.join(job, "output.log")).rstrip() + "\n") if job else ""
    subprocess.run(["pbcopy"], input=text, text=True)
    return "📋 Copied the {} ({} lines)".format(what, text.count("\n") + 1) if what == "output" else "📋 Copied: " + short(text, 100)


def osascript(script, *argv):
    p = subprocess.run(["osascript", "-e", script] + list(argv), capture_output=True, text=True)
    return p.returncode, p.stderr.strip()


def run_in_terminal(cmd):
    if TERMINAL == "terminal_app":
        rc, err = osascript(TERMINAL_APP_SCRIPT, cmd)
        if rc == 0:
            return ""
        subprocess.run(["pbcopy"], input=cmd, text=True)
        return "⚠️ Terminal.app: {} · command copied to the clipboard".format(short(err, 80))
    if TERMINAL == "vscode":
        previous = subprocess.run(["pbpaste"], capture_output=True, text=True).stdout
        subprocess.run(["pbcopy"], input=cmd, text=True)
        rc, err = osascript(VSCODE_SCRIPT)
        if rc != 0:
            # the command stays in the clipboard, to paste by hand
            hint = " · allow Alfred in System Settings > Privacy & Security > Accessibility" if "1002" in err or "ssistive" in err or "not allowed" in err else ""
            return "⚠️ VS Code: {}{} · command copied to the clipboard".format(short(err, 80), hint)
        time.sleep(0.5)
        subprocess.run(["pbcopy"], input=previous, text=True)
        return ""
    # copy only: the command itself, without the cd to the playground and the notification wrapper
    plain = re.sub(r"^'?[^ ']*notify-run\.sh'? ", "", display_cmd(cmd))
    subprocess.run(["pbcopy"], input=plain, text=True)
    return "📋 Copied, paste it in your terminal: " + short(plain, 100)



def action(arg):
    act = os.environ.get("action", "")
    if act == "copy":
        subprocess.run(["pbcopy"], input=arg, text=True)
        return "📋 Copied: " + short(arg, 120)
    if act == "copyfile":
        with open(arg) as f:
            subprocess.run(["pbcopy"], input=f.read(), text=True)
        return "📋 Copied " + os.path.basename(arg)
    if act == "open":
        subprocess.run(["open", arg])
        return ""
    if act == "reveal":
        subprocess.run(["open", "-R", arg])
        return ""
    if act == "code":
        subprocess.run(["code", arg], env=env())
        return ""
    if act == "view":
        return open_view(arg, os.environ.get("view_title") or "kdp")
    if act == "run_in_terminal":
        return run_in_terminal(arg)
    if act == "alfred_search":
        rc, err = osascript('on run argv\n tell application id "com.runningwithcrayons.Alfred" to search (item 1 of argv)\nend run', arg)
        return "" if rc == 0 else "⚠️ " + short(err, 100)
    if act == "refresh_repros":
        try:
            os.remove(REPRO_CACHE + ".lock")
        except OSError:
            pass
        refresh_repro_cache()
        return "🔄 Refreshing the repro model list (about 10 s)"
    return "⚠️ unknown action " + act


def main():
    # Alfred runs scripts without LANG: never fall back to ascii
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except AttributeError:
            pass
    if len(sys.argv) > 1 and sys.argv[1] == "--view":
        sys.stdout.write(json.dumps(view(sys.argv[2] if len(sys.argv) > 2 else None)))
        return
    if len(sys.argv) > 1 and sys.argv[1] == "--view-open-report":
        sys.stdout.write(view_open_report())
        return
    if len(sys.argv) > 2 and sys.argv[1] == "--view-copy":
        sys.stdout.write(view_copy(sys.argv[2]))
        return
    if len(sys.argv) > 2 and sys.argv[1] == "--action":
        msg = action(sys.argv[2])
        if msg:
            sys.stdout.write(msg)
        return
    query = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        out = script_filter(query)
    except Exception as e:  # never show Alfred an empty list without a reason
        out = {"items": [info("⚠️ kdp workflow error", "{}: {}".format(type(e).__name__, e))]}
    sys.stdout.write(json.dumps(out))


if __name__ == "__main__":
    main()
