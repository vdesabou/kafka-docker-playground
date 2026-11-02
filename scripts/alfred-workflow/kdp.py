#!/usr/bin/env python3
"""Alfred workflow for kafka-docker-playground (keyword: kdp).

Script filter:  python3 kdp.py "<query>"        -> Alfred JSON on stdout
Action:         python3 kdp.py --action "<arg>"  -> runs $action, prints a notification text

Sub-commands (first word of the query):
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
  ↩ copy the command      ⌘ open in VS Code      ⌃ run in the terminal
  ⌥ / ⇧ depend on the mode (shown in the subtitle when the key is held)

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
    ("find", "🔎", "Find an example or a reproduction model", "find-example, ↩ copies playground run -f"),
    ("repro", "🧪", "Reproduction models (mine first)", "repro list, cached"),
    ("history", "🕘", "Replay a playground run", "playground history"),
    ("case", "🎫", "Everything about a support case", "ticket, notes, repro models of the case"),
    ("notes", "📝", "Search notes", "open a note, resume the Claude Code session that wrote it"),
    ("plugin", "🔌", "Connector plugin: info, changelog, source code, jars, CVEs", "kdp plugin <owner/name|class|FM type> [version]"),
    ("key", "🔑", "Connector config key: doc, default, since when", "kdp key <key> [connector class]"),
    ("docs", "🍪", "Deep dive pages", "kafka-docker-playground.io"),
    ("status", "🚦", "What is running right now", "status, connector status / diagnose, connect errors"),
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


WARN_RUN = "⌃ ▶️ run in the terminal (stops the environment that is running)"


# --------------------------------------------------------------------------- helpers


def q(s):
    return shlex.quote(str(s))


def env():
    e = dict(os.environ)
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


def script_mods(script, run_command, alt=None, shift=None):
    """⌘ VS Code, ⌃ run in terminal, ⌥ README (default), ⇧ copy repro bootstrap (default)."""
    readme = readme_of(script)
    return {
        "cmd": mod("⌘ open the script in VS Code", "code", script),
        "alt": alt or (mod("⌥ open the README", "open", readme) if readme else mod("⌥ no README in this folder")),
        "shift": shift or mod("⇧ copy: playground repro bootstrap -f … --no-run", "copy", bootstrap_cmd(script)),
        "ctrl": mod(WARN_RUN, "terminal", in_root(run_command)),
    }


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
    return item(
        short(m.get("description") or os.path.basename(script), 100),
        " · ".join(bits) or m.get("path", ""),
        "copy", run,
        mods=script_mods(
            script, run,
            alt=mod("⌥ hand-off report (repro export --report-only)", "output",
                    in_root("playground repro export -f {} --report-only".format(q(script)))),
            shift=mod("⇧ open ticket " + case, "open", ticket_url(case)) if ticket_url(case)
            else mod("⇧ no case number on this model" if not case else "⇧ set ticket_url to open ticket " + case),
        ),
        quicklook=script,
    )


# --------------------------------------------------------------------------- modes


def mode_menu(rest):
    first = rest.split()[0].lower() if rest.split() else ""
    items = []
    if first and HAS_CASE and re.fullmatch(r"\d{5,7}", first):
        return mode_case(rest)
    for name, emoji, title, sub in SUBCOMMANDS:
        if available(name) and (not first or name.startswith(first)):
            items.append(info("{} {}".format(emoji, title), "kdp {} — {}".format(name, sub), autocomplete=name + " "))
    if first and not items:
        # free text: offer the modes that take free text
        items.append(info("🔎 Find examples: " + rest, "↩ search with find-example", autocomplete="find " + rest))
        if HAS_NOTES:
            items.append(info("📝 Search notes: " + rest, "↩ search the notes", autocomplete="notes " + rest))
        if HAS_REPROS:
            items.append(info("🧪 Search repro models: " + rest, "↩ search the repro models", autocomplete="repro " + rest))
        if re.fullmatch(r"[a-z0-9_.\-]+\.[a-z0-9_.\-]+", rest.strip()):
            items.insert(0, info("🔑 Config key " + rest, "↩ connector-plugin config-key", autocomplete="key " + rest))
        m = re.search(r"\b(\d{6})\b", rest)
        if m and HAS_CASE:
            items.insert(0, info("🎫 Support case " + m.group(1), "↩ ticket, notes, repro models", autocomplete="case " + m.group(1)))
    return {"items": items}


def mode_find(rest):
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
        items.append(item(
            os.path.basename(path), sub, "copy", h["run_command"],
            mods=script_mods(script, h["run_command"]), quicklook=readme_of(script) or script,
        ))
    return {"items": items}


def mode_repro(rest):
    models, age = load_repros()
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
        items.append(item(r.get("path", script), " · ".join(bits), "copy", cmd,
                          mods=script_mods(script, cmd), quicklook=readme_of(script) or script))
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


def plugin_name(p):
    if "/" not in p and p.startswith("kafka-connect-"):
        return "confluentinc/" + p
    return p


def mode_plugin(rest):
    w = rest.split()
    if not w:
        return {"items": [info("🔌 Type a connector plugin [version]",
                               "owner/name (confluentinc/kafka-connect-jdbc), kafka-connect-…, a class or a fully managed type (S3_SINK)")]}
    p = plugin_name(w[0])
    v = w[1] if len(w) > 1 else None
    base = "playground connector-plugin {{}} -c {}".format(q(p))
    need_v = "add a version: kdp plugin {} <version>".format(p)

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
    if "/" in p:
        items.append(item("🌐 Confluent Hub page", HUB_URL.format(p), "open", HUB_URL.format(p)))
    items.append(info("🔎 Examples using " + p, "↩ find-example", autocomplete="find " + p.split("/")[-1].replace("kafka-connect-", "")))
    return {"items": items}


def mode_key(rest):
    w = rest.split()
    if not w:
        return {"items": [info("🔑 Type a config key [connector class]", "e.g. kdp key batch.size io.confluent.connect.jdbc.JdbcSinkConnector")]}
    k = w[0]
    cls = w[1] if len(w) > 1 else None
    extra = " --connector-class " + q(cls) if cls else ""
    items = [item("🔑 " + k + (" in " + cls if cls else ""), "connector-plugin config-key: doc, default, values used in examples",
                  "output", in_root("playground connector-plugin config-key -k {}{}".format(q(k), extra)))]
    if cls:
        items.append(item("📅 Since which version does " + k + " exist?", "config-key --since-version (downloads plugin versions)",
                          "output", in_root("playground connector-plugin config-key -k {}{} --since-version".format(q(k), extra))))
    else:
        items.append(info("📅 Since which version?", "add a connector class: kdp key {} <class>".format(k), autocomplete="key {} ".format(k)))
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


MODES = {
    "find": mode_find, "repro": mode_repro, "history": mode_history, "case": mode_case, "notes": mode_notes,
    "plugin": mode_plugin, "key": mode_key, "docs": mode_docs, "status": mode_status,
}


def script_filter(query):
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
    return mode_menu(query)


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


def clean_output(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            text = f.read()
    except OSError:
        return ""
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


def view(arg=None):
    """Script of the Text View: the output of the job so far, rerun every 0.5 s until the command exits."""
    key = view_key(arg)
    if not key:
        return {"response": "Nothing to show."}
    job = os.path.join(VIEW_DIR, key)
    cmd, title = job_file(job, "cmd"), job_file(job, "title", "kdp")
    try:
        elapsed = int(time.time() - float(job_file(job, "start", "0")))
    except ValueError:
        elapsed = 0
    done = os.path.exists(os.path.join(job, "exit"))
    code = job_file(job, "exit")
    out = clean_output(os.path.join(job, "output.log")).rstrip()
    lines = out.split("\n")
    if len(lines) > VIEW_MAX_LINES:
        out = "✂️ {} first lines not shown (⌘↩ copies everything)\n".format(len(lines) - VIEW_MAX_LINES) + "\n".join(lines[-VIEW_MAX_LINES:])
    fence = "```"
    while fence in out:
        fence += "`"
    body = "{f}text\n{o}\n{f}".format(f=fence, o=out) if out else ("_no output_" if done else "⏳ running…")
    response = "**{}**\n\n`{}`\n\n{}".format(title, display_cmd(cmd), body)
    if not done:
        status = "⏳ running {}s".format(elapsed)
    elif code == "0":
        status = "✅ done in {}s".format(elapsed)
    else:
        status = "❌ exit {} after {}s".format(code, elapsed)
    result = {
        "response": response,
        "footer": status + " · ⌘↩ copy output · ⌥↩ copy command · ⎋ close",
        "behaviour": {"response": "replace", "scroll": "auto" if done else "end"},
    }
    if not done:
        result["rerun"] = 0.5
    return result


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
    subprocess.run(["pbcopy"], input=cmd, text=True)
    return "📋 Copied, paste it in your terminal: " + short(cmd, 100)



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
