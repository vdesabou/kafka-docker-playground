"""🔎 Search every log line, and 🕐 the period picker, of the HTML report of playground analyze logs (log_report.py).

The search: every line of the files of the input, written next to the report (<report>-files/search/) as compressed
shards, searched in the browser on demand, so that a word only an INFO line has (a client.id, "Revoking previously
assigned partitions", a Kafka startTimeMs) is found too, not only the ERROR / WARN records of the digest. The report
stays a set of files that can be shared (the 📤 Share zip carries the shards) and opens from file:// : a page cannot
fetch() a local file, so each shard is a .js file that calls pgLogShard(id, "<base64 of the gzip of its JSON>")
when a <script> loads it. The JSON of a shard: {"x": its lines joined by \\n, "t": the time index, line and epoch
pairs, delta encoded, one pair where the time of a line changes (the lines without a timestamp of their own, a stack
trace, take the time of the line before)}. The times are the epochs of log_report.py (wall clock as written in the
logs, read back with the UTC fields), converted to UTC like the digest when the files have several offsets.

A budget (PLAYGROUND_LOG_SEARCH_MAX_MB, 200 MB of lines by default) bounds the size of the report folder and the
memory of the browser: the files with findings first (most occurrences first), then the others, smallest first; the
files left out are listed in the section. Not written for a sanitized report (--sanitize): the shards would hold the
raw lines.

The period picker: a row of the filter bar (quick ranges relative to the END of the logs, not to now; the times of
the analysis; from / to; around a pasted time; zoom out, shift; t ← / t → / t z; recent periods), setting the period
of the report (pgWindow of log_report.py, through the zoom of the occurrences chart)."""

import base64
import calendar
import gzip
import json
import os
import re
import shutil
from typing import Callable, Dict, List, Optional
from urllib.parse import quote

from report_html import e

DEFAULT_MAX_MB = 200
# lines of a shard: a few MB, so that a search shows its progress and stops early when it is replaced
SHARD_BYTES = 4 * 1024 * 1024
# a timestamp near the start of a line: 2026-10-14 09:00:03,123 / 2026-10-14T09:00:03.123Z / ...+02:00
_TS_RE = re.compile(rb"(\d{4})-(\d\d)-(\d\d)[ T](\d\d):(\d\d):(\d\d)(?:[.,]\d+)?\s?(Z|[+-]\d\d:?\d\d)?")
TS_SCAN = 120


def max_bytes() -> int:
    try:
        return max(0, int(float(os.environ.get("PLAYGROUND_LOG_SEARCH_MAX_MB", DEFAULT_MAX_MB)) * 1024 * 1024))
    except ValueError:
        return DEFAULT_MAX_MB * 1024 * 1024


def open_log(path: str):
    """a log file of the input as bytes lines, a .gz (or a gzip without the extension) decompressed"""
    return _open(path)


def _open(path: str):
    with open(path, "rb") as fh:
        magic = fh.read(2)
    return gzip.open(path, "rb") if magic == b"\x1f\x8b" else open(path, "rb")


class _Times:
    """epoch of the timestamp of a line, None without one; cached on the text of the timestamp (most lines of a
    second share it)"""

    def __init__(self, to_utc: bool):
        self.to_utc = to_utc
        self.key = None
        self.value = None

    def of(self, line: bytes) -> Optional[int]:
        m = _TS_RE.search(line, 0, TS_SCAN)
        if not m:
            return None
        key = m.group(0)[:19] + (m.group(7) or b"")
        if key == self.key:
            return self.value
        try:
            t = calendar.timegm((int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4)), int(m.group(5)),
                                 int(m.group(6)), 0, 0, 0))
        except (ValueError, OverflowError):
            return None
        off = m.group(7)
        if self.to_utc and off and off not in (b"Z", b"z"):
            sign = -1 if off[:1] == b"+" else 1
            digits = off[1:].replace(b":", b"")
            t += sign * (int(digits[:2]) * 3600 + int(digits[2:4]) * 60)
        self.key, self.value = key, t
        return t


def _write_shard(folder: str, name: str, lines: List[bytes], times: List[int]) -> None:
    payload = json.dumps({"x": b"\n".join(lines).decode("utf-8", errors="replace"), "t": times},
                         ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    b64 = base64.b64encode(gzip.compress(payload, 6)).decode("ascii")
    with open(os.path.join(folder, name), "w", encoding="ascii") as fh:
        fh.write(f'pgLogShard("{name}","{b64}");\n')


def write_index(report_path: str, entries: List[dict], to_utc: bool, budget: Optional[int] = None) -> dict:
    """writes the shards of the files of the report in <report stem>-files/search/ and returns the index the page
    embeds. entries: {label, path, comp, href, occurrences} of each file of the input (href: its viewer page, "")."""
    budget = max_bytes() if budget is None else budget
    report_dir = os.path.dirname(os.path.abspath(report_path))
    files_folder = os.path.splitext(os.path.basename(report_path))[0] + "-files"
    folder = os.path.join(report_dir, files_folder, "search")
    shutil.rmtree(folder, ignore_errors=True)
    index: dict = {"base": quote(files_folder) + "/search/", "files": [], "skipped": [],
                   "max_mb": round(budget / 1024 / 1024), "bytes": 0, "lines": 0, "stored": 0, "t0": None, "t1": None}
    if budget <= 0:
        index["reason"] = "disabled (PLAYGROUND_LOG_SEARCH_MAX_MB=0)"
        return index
    seen = set()
    todo = []
    for en in entries:
        path = en.get("path")
        if en["label"] in seen or not path or not os.path.isfile(path):
            continue
        seen.add(en["label"])
        todo.append(dict(en, size=os.path.getsize(path)))
    # the files with findings first (most occurrences first), then the others, smallest first
    todo.sort(key=lambda en: (0 if en.get("occurrences") else 1, -(en.get("occurrences") or 0), en["size"]))
    left = budget
    os.makedirs(folder, exist_ok=True)
    nb_shards = 0
    for en in todo:
        if left <= 0 or (en["size"] > left and not en["path"].endswith(".gz")):
            index["skipped"].append({"label": en["label"], "bytes": en["size"], "reason": "over the budget"})
            continue
        clock = _Times(to_utc)
        meta = {"label": en["label"], "comp": en.get("comp") or "other", "href": en.get("href") or "", "shards": [],
                "lines": 0, "bytes": 0, "t0": None, "t1": None, "partial": False}
        st = {"lines": [], "times": [], "bytes": 0, "first": 0, "last_line": 0, "last_t": 0, "cur": None, "t0": None}
        prev_t = None  # the time in effect: the last timestamp read in the file

        def flush():
            nonlocal nb_shards
            if not st["lines"]:
                return
            nb_shards += 1
            name = f"s{nb_shards}.js"
            _write_shard(folder, name, st["lines"], st["times"])
            meta["shards"].append([name, st["first"], len(st["lines"]), st["t0"], prev_t])
            st.update(first=st["first"] + len(st["lines"]), lines=[], times=[], bytes=0, last_line=0, last_t=0, cur=None, t0=None)

        try:
            with _open(en["path"]) as fh:
                for raw in fh:
                    line = raw.rstrip(b"\r\n")
                    size = len(line) + 1
                    if size > left:
                        meta["partial"] = True
                        break
                    left -= size
                    st["bytes"] += size
                    meta["bytes"] += size
                    t = clock.of(line)
                    i = len(st["lines"])
                    if i == 0 and t is None and prev_t is not None:
                        # a shard that starts in a stack trace: the time of the line before
                        st["times"] += [0, prev_t]
                        st["last_t"], st["cur"], st["t0"] = prev_t, prev_t, prev_t
                    if t is not None:
                        if t != st["cur"]:
                            st["times"] += [i - st["last_line"], t - st["last_t"]]
                            st["last_line"], st["last_t"], st["cur"] = i, t, t
                        if st["t0"] is None:
                            st["t0"] = t
                        prev_t = t
                        meta["t0"] = t if meta["t0"] is None else min(meta["t0"], t)
                        meta["t1"] = t if meta["t1"] is None else max(meta["t1"], t)
                    st["lines"].append(line)
                    meta["lines"] += 1
                    if st["bytes"] >= SHARD_BYTES:
                        flush()
        except (OSError, EOFError, gzip.BadGzipFile) as err:
            meta["partial"] = True
            meta["error"] = str(err)[:200]
        flush()
        if not meta["shards"]:
            continue
        index["files"].append(meta)
        index["bytes"] += meta["bytes"]
        index["lines"] += meta["lines"]
        for k, pick in (("t0", min), ("t1", max)):
            if meta[k] is not None:
                index[k] = meta[k] if index[k] is None else pick(index[k], meta[k])
        if meta["partial"]:
            index["skipped"].append({"label": en["label"], "bytes": en["size"],
                                     "reason": meta.get("error") or f"first {meta['lines']:,} lines only: the budget was reached"})
    name_tags(index["files"])
    index["stored"] = sum(os.path.getsize(os.path.join(folder, n)) for n in os.listdir(folder))
    if not index["files"]:
        shutil.rmtree(folder, ignore_errors=True)
        index["reason"] = "no file of the input could be read again"
    return index


def name_tags(files: List[dict]) -> None:
    """the short name of each file (its file name) and, when several files have that name (connect-1.log of 6 CFK
    bundles), the part of their path that tells them apart (the first folder that differs: the bundle)"""
    groups: Dict[str, List[dict]] = {}
    for f in files:
        parts = [x for x in re.split(r"[/:]", f["label"]) if x]
        f["short"] = parts[-1] if parts else f["label"]
        f["tag"] = ""
        f["_parts"] = parts
        groups.setdefault(f["short"], []).append(f)
    for same in groups.values():
        if len(same) > 1:
            depth = min(len(f["_parts"]) for f in same)
            for i in range(depth - 1):
                if len({f["_parts"][i] for f in same}) > 1:
                    for f in same:
                        tag = f["_parts"][i]
                        f["tag"] = tag if len(tag) <= 34 else "…" + tag[-32:]
                    break
    for f in files:
        f.pop("_parts", None)


def _mb(n: int) -> str:
    return f"{n / 1024 / 1024:,.1f} MB" if n >= 1024 * 1024 else f"{n / 1024:,.0f} KB"


SEARCH_CSS = """<style>
#log-search .ls-bar{display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin:8px 0}
#log-search .ls-q{flex:1;min-width:280px;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:.85rem;padding:8px 12px;
border-radius:8px;border:1px solid #cbd5e1;background:#fff;color:#0f172a}
#log-search .ls-q:focus{outline:2px solid #2563eb;outline-offset:-1px;border-color:transparent}
#log-search .ls-status{font-size:.8rem;color:#475569}#log-search .ls-status b{color:#0f172a}
#log-search .ls-stats{display:flex;flex-wrap:wrap;gap:6px;margin:6px 0}
#log-search .ls-stat{font-size:.74rem;padding:2px 9px;border-radius:999px;border:1px solid #e2e8f0;background:#f8fafc;cursor:pointer;color:#334155}
#log-search .ls-stat:hover{border-color:#6366f1}#log-search .ls-stat i,#log-search .ls-tag{opacity:.65;font-size:.68rem}#log-search .ls-stat b{font-variant-numeric:tabular-nums;margin-left:3px}
#log-search .ls-hist svg{display:block;width:100%;height:90px;cursor:crosshair;user-select:none}
#log-search .ls-bar-r{fill:#6366f1}#log-search .ls-bar-r:hover{fill:#4338ca}#log-search .ls-axis{fill:#64748b;font-size:10px}
#log-search .ls-sel{fill:rgba(99,102,241,.18);stroke:#6366f1;stroke-dasharray:4 3}
#log-search table.ls-table{width:100%;border-collapse:collapse;font-size:.78rem;table-layout:fixed}
#log-search table.ls-table td{padding:3px 6px;border-bottom:1px solid #f1f5f9;vertical-align:top}
#log-search table.ls-table td.ls-line{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;white-space:pre-wrap;word-break:break-all;cursor:pointer}
#log-search table.ls-table td.ls-time,#log-search table.ls-table td.ls-file{white-space:nowrap;overflow:hidden;text-overflow:ellipsis;font-family:ui-monospace,monospace;font-size:.74rem}
#log-search .ls-lvl{font-size:.68rem;font-weight:700;padding:1px 6px;border-radius:4px;background:#e2e8f0;color:#334155}
#log-search .ls-lvl.FATAL,#log-search .ls-lvl.ERROR{background:#fee2e2;color:#991b1b}#log-search .ls-lvl.WARN{background:#fef3c7;color:#92400e}
#log-search .ls-lvl.INFO{background:#dbeafe;color:#1e40af}#log-search .ls-lvl.DEBUG,#log-search .ls-lvl.TRACE{background:#f1f5f9;color:#64748b}
#log-search mark{background:#fde047;color:#111;border-radius:2px}
#log-search tr.ls-ctx td{background:#f8fafc;padding:6px 10px}#log-search .ls-ctx pre{margin:0;font-size:.74rem;white-space:pre-wrap;word-break:break-all}
#log-search .ls-ctx .ls-hit{background:#fef9c3;display:block}#log-search .ls-ctx .ls-n{color:#94a3b8;user-select:none}
#log-search .ls-more{margin:8px 0}#log-search details.ls-help{font-size:.78rem;margin:4px 0}#log-search details.ls-help code{font-size:.74rem}
html[data-theme=dark] #log-search .ls-q{background:#0f172a;border-color:#334155;color:#e2e8f0}
html[data-theme=dark] #log-search .ls-status{color:#94a3b8}html[data-theme=dark] #log-search .ls-status b{color:#e2e8f0}
html[data-theme=dark] #log-search .ls-stat{background:#1e293b;border-color:#334155;color:#cbd5e1}
html[data-theme=dark] #log-search table.ls-table td{border-color:#1e293b}html[data-theme=dark] #log-search tr.ls-ctx td{background:#0f172a}
html[data-theme=dark] #log-search .ls-ctx .ls-hit{background:#3f3a0a}html[data-theme=dark] #log-search .ls-lvl{background:#334155;color:#e2e8f0}
html[data-theme=dark] #log-search .ls-lvl.FATAL,html[data-theme=dark] #log-search .ls-lvl.ERROR{background:#450a0a;color:#fca5a5}
html[data-theme=dark] #log-search .ls-lvl.WARN{background:#422006;color:#fcd34d}html[data-theme=dark] #log-search .ls-lvl.INFO{background:#172554;color:#93c5fd}
</style>"""


def search_html(index: Optional[dict]) -> str:
    """the 🔎 Search every log line card (the index embedded, the shards loaded when a search runs)"""
    if not index:
        return ""
    head = "<div class='table-card' id='log-search'><h2>🔎 Search every log line</h2>"
    if index.get("reason") or not index.get("files"):
        return (head + f"<p class='legend'>Not available for this report: {e(index.get('reason') or 'no file')}. The search box of "
                "the filter bar searches the ERROR / WARN records only.</p></div>")
    skipped = index.get("skipped") or []
    left_out = ""
    if skipped:
        items = "".join(f"<li class='mono'>{e(s['label'])} ({_mb(s['bytes'])}): {e(s['reason'])}</li>" for s in skipped[:50])
        left_out = (f"<details class='ls-help'><summary>⚠️ {len(skipped)} file(s) not searched, or only in part (budget "
                    f"{index['max_mb']} MB: PLAYGROUND_LOG_SEARCH_MAX_MB=… playground analyze logs … for more)</summary><ul>{items}"
                    + (f"<li>… {len(skipped) - 50} more</li>" if len(skipped) > 50 else "") + "</ul></details>")
    # every < escaped (valid JSON), not only </: a file name of a bundle with <!--<script> would put the parser in the
    # double escaped state of the script element, and the rest of the page would become its text
    data = json.dumps(index, ensure_ascii=False, separators=(",", ":")).replace("<", "\\u003c")
    return (SEARCH_CSS + head
            + f"<p class='legend'>Every line of {len(index['files'])} file(s), {index['lines']:,} lines ({_mb(index['bytes'])}, "
            f"{_mb(index['stored'])} compressed next to the report), INFO and DEBUG included, not only the ERROR / WARN records: "
            "searched in your browser. It follows the 🕐 period and the component of the filter bar. Click a line for the "
            "lines around it, drag over the histogram to make it the period of the report.</p>"
            "<div class='ls-bar'><input class='ls-q' type='search' spellcheck='false' autocomplete='off' "
            "placeholder='Search every line: words, \"a phrase\", /regex/, -exclude, level:INFO, file:connect-0, comp:connect' "
            "title='Enter to search. All the terms must match (any case)'>"
            "<button type='button' class='pill ls-go'>🔎 Search</button><button type='button' class='pill ls-from-bar' "
            "title='search every line for the text of the search box of the filter bar'>⇣ from the filter bar</button></div>"
            "<details class='ls-help'><summary>Syntax</summary><ul>"
            "<li><code>rebalance timeout</code>: both words, any case · <code>\"Revoking previously assigned\"</code>: a phrase</li>"
            "<li><code>/task-\\d+ .*stopp/</code>: a regular expression (any case) · <code>-DEBUG</code>, <code>-/regex/</code>: without it</li>"
            "<li><code>level:WARN</code> (<code>level:ERROR,FATAL</code>), <code>file:connect-0</code> (part of the path), "
            "<code>comp:connect</code> (the component of the file, as the chips): fields, <code>-level:DEBUG</code> to leave out</li>"
            "<li>Lines without a timestamp of their own (a stack trace) take the time of the line before.</li></ul></details>"
            + left_out
            + "<div class='ls-status' aria-live='polite'></div><div class='ls-stats'></div><div class='ls-hist'></div>"
            "<div class='ls-results'></div></div>"
            f"<script type='application/json' id='pg-log-index'>{data}</script>")


# 📅 in a from / to box: the date and time picker of the browser (a datetime-local input, opened with showPicker(),
# min / max the period of the logs); the text box stays for a pasted time or "a → b"
CAL = ("<button type='button' class='pp-cal' title='pick a date and a time'>📅</button>"
       "<input class='pp-dt' type='datetime-local' step='1' tabindex='-1' aria-hidden='true'>")


def period_row(lo: Optional[float], hi: Optional[float], marks: List[dict]) -> str:
    """the 🕐 Period row of the filter bar; marks: {label, from, to} of the analysis (first error, peak...)"""
    if lo is None or hi is None or hi <= lo:
        return ""
    span = hi - lo
    last = [(300, "5 min"), (900, "15 min"), (3600, "1 h"), (6 * 3600, "6 h"), (86400, "24 h"), (7 * 86400, "7 days")]
    opts = "".join(f"<option value='last:{s}'>Last {lbl} of the logs</option>" for s, lbl in last if s < span)
    firsts = "".join(f"<option value='first:{s}'>First {lbl} of the logs</option>" for s, lbl in last[:4] if s < span)
    mk = "".join(f"<option value='mark:{i}'>{e(m['label'])}</option>" for i, m in enumerate(marks))
    sel = ("<select class='pp-quick' title='a period relative to the end of the logs (not to now: they were collected earlier), "
           "or a time of the analysis'><option value=''>⏱ Quick ranges…</option>"
           + (f"<optgroup label='End of the logs'>{opts}</optgroup>" if opts else "")
           + (f"<optgroup label='Start of the logs'>{firsts}</optgroup>" if firsts else "")
           + (f"<optgroup label='From the analysis'>{mk}</optgroup>" if mk else "")
           + "<optgroup label='Recent' class='pp-recent' hidden></optgroup></select>")
    data = e(json.dumps(marks, separators=(",", ":")))
    return (PERIOD_CSS + f"<div class='fb-row pg-period' data-lo='{int(lo)}' data-hi='{int(hi)}' data-marks='{data}'>"
            "<span class='fb-label'>🕐 Period</span>" + sel
            + "<span class='pp-field'><input class='pp-from' type='text' spellcheck='false' placeholder='from: 2026-10-14 09:02 (or paste a → b)' "
            "title='the start of the period, in the time of the logs: YYYY-MM-DD HH:MM[:SS], HH:MM[:SS] (the last day of the logs with that time), an epoch; paste \"a → b\" for both. Enter applies'>" + CAL + "</span>"
            "<span class='fb-label'>→</span><span class='pp-field'><input class='pp-to' type='text' spellcheck='false' placeholder='to' "
            "title='the end of the period. Enter applies'>" + CAL + "</span>"
            "<button type='button' class='pill pp-apply' title='use from / to as the period of the report'>Apply</button>"
            "<span class='pp-nav'><button type='button' class='pill pp-out' title='zoom out: twice as long, same middle (t z)'>⊖</button>"
            "<button type='button' class='pill pp-prev' title='half a period earlier (t ←)'>◀</button>"
            "<button type='button' class='pill pp-next' title='half a period later (t →)'>▶</button>"
            "<button type='button' class='pill pp-all' title='the whole period of the logs'>⤺ whole period</button></span>"
            "<span class='fb-label'>Around</span><input class='pp-at' type='text' spellcheck='false' placeholder='a time: 09:05:12' "
            "title='a time (the customer says \"it started at 09:05\"): the period around it. Enter applies'>"
            "<select class='pp-pm' title='how long around it'><option value='60'>± 1 min</option><option value='300' selected>± 5 min</option>"
            "<option value='900'>± 15 min</option><option value='3600'>± 1 h</option></select>"
            "<span class='pp-info fb-label'></span></div>")


PERIOD_CSS = ("<style>.pg-period input{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:.78rem;padding:5px 9px;border-radius:8px;"
              "border:1px solid #d1d5db;background:#fff;color:#1e293b;width:14.6em}.pg-period .pp-at{width:7em}"
              ".pg-period select{max-width:170px;font-family:inherit;font-size:.78rem;padding:4px 26px 4px 10px;border-radius:8px;border:1px solid #cbd5e1;"
              "background-color:#fff;color:#1e293b;cursor:pointer;-webkit-appearance:none;appearance:none;background-image:url(\"data:image/svg+xml,"
              "%3Csvg xmlns='http://www.w3.org/2000/svg' width='10' height='6'%3E%3Cpath d='M0 0l5 6 5-6z' fill='%2364748b'/%3E%3C/svg%3E\");"
              "background-repeat:no-repeat;background-position:right 9px center}.pg-period select:hover{border-color:#2563eb}"
              "html[data-theme=dark] .pg-period select{background-color:#0f172a;color:#e2e8f0;border-color:#334155}"
              ".pg-period input.pp-bad{border-color:#dc2626;outline:2px solid #fecaca}.pg-period .pill{padding:4px 10px}"
              ".pg-period .pp-nav{display:inline-flex;gap:4px}.pg-period .pp-info b{color:#1e293b}"
              ".pg-period.pp-on .pp-all{border-color:#6366f1;color:#4338ca}"
              "html[data-theme=dark] .pg-period input{background:#0f172a;border-color:#334155;color:#e2e8f0}"
              "html[data-theme=dark] .pg-period .pp-info b{color:#e2e8f0}"
              ".pg-period .pp-field{position:relative;display:inline-flex;align-items:center}"
              ".pg-period .pp-field input[type=text]{padding-right:28px}"
              ".pg-period .pp-cal{position:absolute;right:4px;border:0;background:none;cursor:pointer;font-size:.85rem;padding:2px;opacity:.7}"
              ".pg-period .pp-cal:hover{opacity:1}"
              ".pg-period .pp-dt{position:absolute;left:0;bottom:0;width:100%;height:0;padding:0;border:0;opacity:0;pointer-events:none}"
              "html[data-theme=dark] .pg-period .pp-dt{color-scheme:dark}"
              "button.tl-around{border:0;background:none;cursor:pointer;padding:0 0 0 4px;font-size:.8rem;opacity:.55}button.tl-around:hover{opacity:1}"
              "</style>")


PERIOD_SCRIPT = r"""<script>
// ── 🕐 the period picker (log_search.py): every way of picking a period ends in pgSetPeriod(from, to), which zooms the
// occurrences chart on what it holds of the period (its zoomchange sets pgWindow: every section follows) and keeps the
// period asked in pgPeriod (wider than the chart when the logs go on after the last record: 🔎 Search every log line uses it)
var pgPeriod = null, pgPeriodSetting = false;
(function () {
  const row = document.querySelector(".pg-period");
  if (!row) return;
  const LO = +row.dataset.lo, HI = +row.dataset.hi, MARKS = JSON.parse(row.dataset.marks || "[]");
  const fromIn = row.querySelector(".pp-from"), toIn = row.querySelector(".pp-to"), atIn = row.querySelector(".pp-at");
  const info = row.querySelector(".pp-info"), quick = row.querySelector(".pp-quick"), recentGroup = row.querySelector(".pp-recent");
  const RECENT_KEY = "pg-log-report-periods:" + document.title + ":" + LO;
  function chart() { return document.getElementById("@@CHART@@"); }
  // a time typed or pasted, in the time of the logs: YYYY-MM-DD HH:MM[:SS][,ms][offset ignored], HH:MM[:SS] (the
  // last day of the logs that has it, or the day of ref), an epoch in s or ms
  function parse(s, ref) {
    s = (s || "").trim().replace(/^\[|\]$/g, "");
    if (!s) return null;
    let m = s.match(/^(\d{4})-(\d{2})-(\d{2})[ T](\d{1,2}):(\d{2})(?::(\d{2}))?(?:[.,]\d+)?\s*(?:Z|UTC|[+-]\d{2}:?\d{2})?$/i);
    if (m) return Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +(m[6] || 0)) / 1000;
    m = s.match(/^(\d{4})-(\d{2})-(\d{2})$/);
    if (m) return Date.UTC(+m[1], +m[2] - 1, +m[3]) / 1000;
    m = s.match(/^(\d{1,2}):(\d{2})(?::(\d{2}))?(?:[.,]\d+)?$/);
    if (m) {
      const secs = +m[1] * 3600 + +m[2] * 60 + +(m[3] || 0);
      if (ref !== undefined && ref !== null) { let t = Math.floor(ref / 86400) * 86400 + secs; if (t < ref) t += 86400; return t; }
      let t = Math.floor(HI / 86400) * 86400 + secs;
      while (t > HI + 1 && t - 86400 >= Math.floor(LO / 86400) * 86400) t -= 86400;
      return t;
    }
    m = s.match(/^(\d{10})(\d{3})?$/);
    if (m) return +m[1];
    return null;
  }
  function show() {
    const p = pgPeriod || pgWindow;
    row.classList.toggle("pp-on", !!p);
    if (document.activeElement !== fromIn) fromIn.value = p ? pgStamp(p[0]) : "";
    if (document.activeElement !== toIn) toIn.value = p ? pgStamp(p[1]) : "";
    fromIn.placeholder = "from: " + pgStamp(LO);
    toIn.placeholder = "to: " + pgStamp(HI);
    info.innerHTML = p ? "🔍 <b>" + pgDur(p[1] - p[0]) + "</b> of " + pgDur(HI - LO) : "the whole logs: " + pgDur(HI - LO);
  }
  function recent() {
    let list = [];
    try { list = JSON.parse(localStorage.getItem(RECENT_KEY) || "[]"); } catch (e) {}
    return Array.isArray(list) ? list : [];
  }
  function remember(a, b) {
    const list = recent().filter(x => !(x[0] === a && x[1] === b));
    list.unshift([a, b]);
    try { localStorage.setItem(RECENT_KEY, JSON.stringify(list.slice(0, 6))); } catch (e) {}
    fillRecent();
  }
  function fillRecent() {
    if (!recentGroup) return;
    const list = recent();
    recentGroup.textContent = "";
    list.forEach(function (x) {
      const o = document.createElement("option");
      o.value = "rec:" + x[0] + "-" + x[1];
      o.textContent = pgStamp(x[0]).slice(5) + " → " + pgStamp(x[1]).slice(5) + " (" + pgDur(x[1] - x[0]) + ")";
      recentGroup.appendChild(o);
    });
    recentGroup.hidden = !list.length;
  }
  function changed() {
    show();
    document.dispatchEvent(new CustomEvent("pgperiod", {detail: {period: pgPeriod}}));
  }
  window.pgSetPeriod = function (from, to, keep) {
    from = Math.floor(Math.max(LO, from)); to = Math.ceil(Math.min(HI + 1, to));
    if (!(to > from)) return false;
    if (from <= LO && to >= HI) { pgClearPeriod(); return true; }
    pgPeriod = [from, to];
    if (!keep) remember(from, to);
    const c = chart(), r = c && c.range ? c.range() : null;
    let done = false;
    pgPeriodSetting = true;
    try {
      // the chart holds the records only: zoomed on what it has of the period (else show() would shift it)
      if (r) { const a = Math.max(from, r[0]), b = Math.min(to, r[1]); if (b > a) done = c.zoomTo(a, b); }
      if (!done) { pgWindow = [from, to]; pgApplyFilters(); }
      // the records of the period: pgWindow is the period asked, not its part on the chart
      if (done && (pgWindow === null || pgWindow[0] !== from || pgWindow[1] !== to)) { pgWindow = [from, to]; pgRead(); pgApply(); }
    } finally { pgPeriodSetting = false; }
    pgStateWrite();
    changed();
    return true;
  };
  window.pgClearPeriod = function () {
    pgPeriod = null;
    pgPeriodSetting = true;
    try {
      const all = document.querySelector("#@@CHART@@ [data-zoom='all']");
      if (all && !all.classList.contains("on")) all.click();
      if (pgWindow) { pgWindow = null; pgApplyFilters(); }
    } finally { pgPeriodSetting = false; }
    pgStateWrite();
    changed();
  };
  // a drag over the occurrences chart, its ◀ ▶, ⤺ whole period: the period of the chart
  document.addEventListener("zoomchange", function (ev) {
    if (!ev.target || ev.target.id !== "@@CHART@@" || pgPeriodSetting || pgRedrawing) return;
    pgPeriod = ev.detail.all ? null : [Math.floor(ev.detail.from), Math.ceil(ev.detail.to)];
    pgStateWrite();
    changed();
  });
  function current() { return pgPeriod || pgWindow || [LO, HI + 1]; }
  function applyFromTo() {
    let a = fromIn.value, b = toIn.value;
    const both = a.split(/\s*(?:→|->|—|–|\bto\b|\s-\s)\s*/);
    if (both.length === 2 && both[1]) { a = both[0]; b = both[1]; }
    const from = parse(a), to = parse(b, from);
    fromIn.classList.toggle("pp-bad", !!a.trim() && from === null);
    toIn.classList.toggle("pp-bad", !!b.trim() && to === null);
    if (from === null && to === null) return;
    pgSetPeriod(from === null ? LO : from, to === null ? HI + 1 : (to <= from ? to + 1 : to));
    fromIn.blur(); toIn.blur(); show();
  }
  function applyAround() {
    const t = parse(atIn.value), pm = +row.querySelector(".pp-pm").value;
    atIn.classList.toggle("pp-bad", t === null);
    if (t === null) return;
    pgSetPeriod(t - pm, t + pm);
  }
  window.pgShiftPeriod = function (k) {
    const p = current(), span = p[1] - p[0];
    if (k === "out") { const mid = (p[0] + p[1]) / 2; pgSetPeriod(mid - span, mid + span); return; }
    const d = span / 2 * (k === "prev" ? -1 : 1);
    let a = p[0] + d, b = p[1] + d;
    if (a < LO) { b += LO - a; a = LO; }
    if (b > HI + 1) { a -= b - HI - 1; b = HI + 1; }
    pgSetPeriod(a, b);
  };
  row.addEventListener("click", function (ev) {
    const b = ev.target.closest("button");
    if (!b) return;
    if (b.classList.contains("pp-apply")) applyFromTo();
    else if (b.classList.contains("pp-all")) pgClearPeriod();
    else if (b.classList.contains("pp-out")) pgShiftPeriod("out");
    else if (b.classList.contains("pp-prev")) pgShiftPeriod("prev");
    else if (b.classList.contains("pp-next")) pgShiftPeriod("next");
  });
  row.addEventListener("keydown", function (ev) {
    if (ev.key !== "Enter") return;
    if (ev.target === fromIn || ev.target === toIn) { ev.preventDefault(); applyFromTo(); }
    if (ev.target === atIn) { ev.preventDefault(); applyAround(); }
  });
  row.querySelector(".pp-pm").addEventListener("change", function () { if (atIn.value.trim()) applyAround(); });
  quick.addEventListener("change", function () {
    const v = quick.value;
    quick.value = "";
    if (!v) return;
    const [kind, arg] = [v.slice(0, v.indexOf(":")), v.slice(v.indexOf(":") + 1)];
    if (kind === "last") pgSetPeriod(HI + 1 - +arg, HI + 1);
    else if (kind === "first") pgSetPeriod(LO, LO + +arg);
    else if (kind === "mark") { const m = MARKS[+arg]; if (m) pgSetPeriod(m.from, m.to); }
    else if (kind === "rec") { const x = arg.split("-").map(Number); pgSetPeriod(x[0], x[1], true); }
  });
  // Grafana keys: t ← / t → half a period earlier / later, t z zoom out (not while typing)
  let tAt = 0;
  document.addEventListener("keydown", function (ev) {
    const tag = (ev.target.tagName || "").toLowerCase();
    if (tag === "input" || tag === "textarea" || tag === "select" || ev.target.isContentEditable || ev.metaKey || ev.ctrlKey || ev.altKey) return;
    if (ev.key === "t") { tAt = Date.now(); return; }
    if (Date.now() - tAt > 1500) return;
    if (ev.key === "ArrowLeft") { ev.preventDefault(); pgShiftPeriod("prev"); }
    else if (ev.key === "ArrowRight") { ev.preventDefault(); pgShiftPeriod("next"); }
    else if (ev.key === "z") { ev.preventDefault(); pgShiftPeriod("out"); }
    else return;
    tAt = 0;
  });
  // ⏱️ on each row of the incident timeline: ± 2 min around that event
  document.querySelectorAll("tr.tl-row[data-t] td.tl-time").forEach(function (td) {
    const b = document.createElement("button");
    b.type = "button"; b.className = "tl-around"; b.textContent = "⏱️";
    b.title = "± 2 min around this event: the period of the report (what every file said then)";
    td.appendChild(b);
  });
  document.addEventListener("click", function (ev) {
    const b = ev.target.closest("button.tl-around");
    if (!b) return;
    ev.stopPropagation();
    const t = +b.closest("tr").dataset.t;
    pgSetPeriod(t - 120, t + 120);
    row.scrollIntoView({block: "nearest"});
  });
  // 📅 the picker of the browser: opened on the current from / to, applied once a date and a time are picked
  const isoOf = t => pgStamp(t).replace(" ", "T");
  row.querySelectorAll(".pp-field").forEach(function (field) {
    const text = field.querySelector("input[type=text]"), dt = field.querySelector(".pp-dt"), btn = field.querySelector(".pp-cal");
    if (!dt || !btn) return;
    dt.min = isoOf(LO); dt.max = isoOf(HI + 1);
    let timer = null;
    btn.addEventListener("click", function () {
      const p = current();
      dt.value = isoOf(text === fromIn ? p[0] : Math.min(p[1], HI + 1));
      try { dt.showPicker(); } catch (e) { dt.style.pointerEvents = "auto"; dt.focus(); }
    });
    dt.addEventListener("change", function () {
      if (!dt.value) return;
      text.value = dt.value.replace("T", " ") + (dt.value.length === 16 ? ":00" : "");
      clearTimeout(timer);
      timer = setTimeout(applyFromTo, 400);
    });
  });
  fillRecent();
  document.addEventListener("DOMContentLoaded", function () { if (pgWindow && !pgPeriod) pgPeriod = [Math.floor(pgWindow[0]), Math.ceil(pgWindow[1])]; show(); });
  show();
})();
</script>"""


SEARCH_SCRIPT = r"""<script>
// ── 🔎 Search every log line (log_search.py): the shards are loaded with a <script> (file:// cannot fetch), inflated
// with DecompressionStream, kept while they fit in BUDGET characters, scanned shard by shard (a newer search stops
// an older one)
(function () {
  const card = document.getElementById("log-search"), idxEl = document.getElementById("pg-log-index");
  if (!card || !idxEl) return;
  const IDX = JSON.parse(idxEl.textContent);
  const q = card.querySelector(".ls-q"), status = card.querySelector(".ls-status"), stats = card.querySelector(".ls-stats");
  const hist = card.querySelector(".ls-hist"), out = card.querySelector(".ls-results");
  const BUDGET = 260e6, MAX_ROWS = 200000, PAGE = 200, CTX = 8, BINS = 80;
  const LEVEL_RE = /\b(FATAL|ERROR|WARN(?:ING)?|INFO|DEBUG|TRACE|SEVERE)\b/;
  const pending = {}, cache = new Map();
  let cached = 0, gen = 0, last = null;
  window.pgLogShard = function (id, b64) { const p = pending[id]; if (p) { delete pending[id]; p(b64); } };
  function esc(s) { return s.replace(/[&<>"']/g, c => ({"&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"}[c])); }
  async function inflate(b64) {
    const bin = atob(b64), u = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i);
    const text = await new Response(new Blob([u]).stream().pipeThrough(new DecompressionStream("gzip"))).text();
    const o = JSON.parse(text), lines = [], times = [];
    let l = 0, t = 0;
    for (let i = 0; i < o.t.length; i += 2) { l += o.t[i]; t += o.t[i + 1]; lines.push(l); times.push(t); }
    return {text: o.x, lines: lines, times: times};
  }
  function load(f, s) {
    const name = IDX.files[f].shards[s][0];
    if (cache.has(name)) { const v = cache.get(name); cache.delete(name); cache.set(name, v); return v; }
    const p = new Promise(function (resolve, reject) {
      const sc = document.createElement("script");
      pending[name] = function (b64) { sc.remove(); inflate(b64).then(resolve, reject); };
      sc.onerror = function () { delete pending[name]; sc.remove(); reject(new Error("cannot load " + IDX.base + name + " (the -files folder next to the report)")); };
      sc.src = IDX.base + name;
      document.head.appendChild(sc);
    });
    cache.set(name, p);
    p.then(function (sh) {
      cached += sh.text.length;
      // the least recently used shards out, over the budget
      for (const [k, v] of cache) { if (cached <= BUDGET || k === name) break; cache.delete(k); v.then(x => { cached -= x.text.length; }); }
    }, function () { cache.delete(name); });
    return p;
  }
  function timeOf(sh, line) {
    let lo = 0, hi = sh.lines.length - 1, r = -1;
    while (lo <= hi) { const m = (lo + hi) >> 1; if (sh.lines[m] <= line) { r = m; lo = m + 1; } else hi = m - 1; }
    return r < 0 ? null : sh.times[r];
  }
  function levelOf(line) {
    const m = LEVEL_RE.exec(line.length > 160 ? line.slice(0, 160) : line);
    if (!m) return "";
    return m[1] === "WARNING" ? "WARN" : m[1] === "SEVERE" ? "ERROR" : m[1];
  }
  function escRx(s) { return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"); }
  // the terms: words, "phrases", /regex/, -negation, field:value (level, file, comp)
  function parse(text) {
    const terms = [], re = /(-?)(?:([a-z]+):(?:"([^"]*)"|([^\s"]+))|"([^"]+)"|\/((?:\\.|[^\/])+)\/|(\S+))/gi;
    let m;
    while ((m = re.exec(text))) {
      const neg = m[1] === "-";
      let field = m[2] ? m[2].toLowerCase() : null, value = m[3] !== undefined ? m[3] : m[4];
      if (field === "component") field = "comp";
      if (field && !["level", "file", "comp"].includes(field)) { terms.push({neg: neg, word: (m[2] + ":" + value).toLowerCase()}); continue; }
      if (field) { terms.push({neg: neg, field: field, values: value.toLowerCase().split(",").filter(Boolean)}); continue; }
      if (m[6] !== undefined) { try { terms.push({neg: neg, rx: new RegExp(m[6], "i")}); } catch (e) { terms.push({neg: neg, word: m[6].toLowerCase()}); } continue; }
      const w = (m[5] !== undefined ? m[5] : m[7]);
      if (w === "-") continue;
      terms.push({neg: neg, word: w.toLowerCase()});
    }
    return terms;
  }
  function inPeriod(t, p) { return !p || t === null || (t >= p[0] && t < p[1]); }
  async function run(text) {
    const my = ++gen;
    const terms = parse(text);
    window.pgLogQuery = text.trim();
    if (typeof pgStateWrite === "function") pgStateWrite();
    if (!terms.length) { status.textContent = ""; stats.textContent = ""; hist.textContent = ""; out.textContent = ""; last = null; return; }
    const period = (typeof pgPeriod !== "undefined" && pgPeriod) || (typeof pgWindow !== "undefined" && pgWindow) || null;
    const comp = (typeof pgComponent !== "undefined" && pgComponent) || "";
    const textTerms = terms.filter(t => !t.field), levelTerms = terms.filter(t => t.field === "level");
    const anchor = textTerms.find(t => !t.neg);
    const anchorRx = anchor ? new RegExp(anchor.rx ? anchor.rx.source : escRx(anchor.word), "gi") : null;
    const files = [];
    IDX.files.forEach(function (f, i) {
      if (comp && f.comp !== comp) return;
      const lab = f.label.toLowerCase();
      for (const t of terms.filter(t => t.field === "file" || t.field === "comp")) {
        const hit = t.values.some(v => t.field === "file" ? lab.includes(v) : f.comp === v);
        if (hit === t.neg) return;
      }
      if (period && f.t0 !== null && (f.t1 < period[0] || f.t0 >= period[1])) return;
      files.push(i);
    });
    const r0 = period ? period[0] : IDX.t0, r1 = period ? period[1] : (IDX.t1 === null ? null : IDX.t1 + 1);
    const res = {rows: [], count: 0, bins: new Array(BINS).fill(0), byLevel: {}, byFile: {}, r0: r0, r1: r1, terms: terms,
                 period: period, comp: comp, files: files.length, untimed: 0};
    const nbShards = files.reduce((n, i) => n + IDX.files[i].shards.length, 0);
    let done = 0, scanned = 0;
    const started = performance.now();
    status.innerHTML = "🔎 searching… 0 / " + nbShards + " part(s)";
    for (const fi of files) {
      const f = IDX.files[fi];
      for (let si = 0; si < f.shards.length; si++) {
        const meta = f.shards[si];
        if (period && meta[3] !== null && meta[4] !== null && (meta[4] < period[0] || meta[3] >= period[1])) { done++; continue; }
        let sh;
        try { sh = await load(fi, si); } catch (err) { status.textContent = "⚠️ " + err.message; return; }
        if (my !== gen) return;
        const txt = sh.text;
        scanned += txt.length;
        let cntPos = 0, cntLine = 0;
        const advance = function (to) { let k; while ((k = txt.indexOf("\n", cntPos)) !== -1 && k < to) { cntLine++; cntPos = k + 1; } };
        const test = function (start, end) {
          const line = txt.slice(start, end);
          let low = null;
          for (const t of textTerms) {
            const hit = t.rx ? t.rx.test(line) : (low || (low = line.toLowerCase())).includes(t.word);
            if (hit === t.neg) return;
          }
          const lvl = levelOf(line);
          for (const t of levelTerms) { if (t.values.some(v => { const V = v.toUpperCase(); return lvl && (lvl.startsWith(V) || V.startsWith(lvl)); }) === t.neg) return; }
          const tm = timeOf(sh, cntLine);
          if (!inPeriod(tm, period)) return;
          res.count++;
          res.byLevel[lvl || "—"] = (res.byLevel[lvl || "—"] || 0) + 1;
          res.byFile[fi] = (res.byFile[fi] || 0) + 1;
          if (tm === null) res.untimed++;
          else if (r1 > r0) res.bins[Math.min(BINS - 1, Math.max(0, Math.floor(BINS * (tm - r0) / (r1 - r0))))]++;
          if (res.rows.length < MAX_ROWS) res.rows.push([tm === null ? Infinity : tm, fi, si, start, meta[1] + cntLine + 1]);
        };
        if (anchorRx) {
          anchorRx.lastIndex = 0;
          let m;
          while ((m = anchorRx.exec(txt))) {
            advance(m.index);
            let end = txt.indexOf("\n", m.index);
            if (end < 0) end = txt.length;
            test(cntPos, end);
            anchorRx.lastIndex = end + 1;
            if (end >= txt.length) break;
          }
        } else {
          let start = 0;
          while (start <= txt.length) {
            let end = txt.indexOf("\n", start);
            if (end < 0) end = txt.length;
            cntPos = start;
            test(start, end);
            cntLine++;
            start = end + 1;
          }
        }
        done++;
        status.innerHTML = "🔎 searching… " + done + " / " + nbShards + " part(s), <b>" + res.count.toLocaleString() + "</b> match(es)";
        await new Promise(r => setTimeout(r, 0));
        if (my !== gen) return;
      }
    }
    res.rows.sort((a, b) => a[0] - b[0] || a[1] - b[1] || a[4] - b[4]);
    res.ms = Math.round(performance.now() - started);
    res.scanned = scanned;
    last = res;
    render(res);
  }
  function highlighter(terms) {
    const parts = terms.filter(t => !t.neg && !t.field).map(t => t.rx ? t.rx.source : escRx(t.word));
    if (!parts.length) return esc;
    let rx;
    try { rx = new RegExp("(" + parts.join("|") + ")", "gi"); } catch (e) { return esc; }
    return function (s) {
      let html = "", i = 0, m;
      rx.lastIndex = 0;
      while ((m = rx.exec(s))) {
        if (!m[0]) { rx.lastIndex++; continue; }
        html += esc(s.slice(i, m.index)) + "<mark>" + esc(m[0]) + "</mark>";
        i = m.index + m[0].length;
      }
      return html + esc(s.slice(i));
    };
  }
  function render(res) {
    const scope = [];
    if (res.period) scope.push("🕐 " + pgStamp(res.period[0]) + " → " + pgStamp(res.period[1]));
    if (res.comp) scope.push("🧩 " + res.comp);
    status.innerHTML = "<b>" + res.count.toLocaleString() + "</b> line(s) in " + res.files + " file(s)" + (scope.length ? " · " + esc(scope.join(" · ")) : "")
      + " · " + (res.scanned / 1048576).toFixed(0) + " MB searched in " + (res.ms / 1000).toFixed(1) + " s"
      + (res.count > MAX_ROWS ? " · the first " + MAX_ROWS.toLocaleString() + " listed" : "")
      + (res.untimed ? " · " + res.untimed.toLocaleString() + " without a time (not in the histogram)" : "");
    // the field stats: a click adds the field to the query
    const lv = Object.entries(res.byLevel).sort((a, b) => b[1] - a[1]);
    const fl = Object.entries(res.byFile).sort((a, b) => b[1] - a[1]).slice(0, 8);
    stats.innerHTML = lv.map(([k, n]) => "<span class='ls-stat' data-add='" + (k === "—" ? "" : "level:" + k) + "' title='" + (k === "—" ? "lines without a level" : "only the " + k + " lines") + "'><span class='ls-lvl " + k + "'>" + esc(k) + "</span><b>" + n.toLocaleString() + "</b></span>").join("")
      + fl.map(([fi, n]) => { const f = IDX.files[fi], term = v => "file:" + (/\s/.test(v) ? '"' + v + '"' : v); return "<span class='ls-stat' data-add='" + esc(term(f.short) + (f.tag ? " " + term(f.tag) : "")) + "' title='" + esc(f.label) + ": only this file'>📄 " + esc(f.short) + (f.tag ? " <i>" + esc(f.tag) + "</i>" : "") + "<b>" + n.toLocaleString() + "</b></span>"; }).join("");
    drawHist(res);
    out.textContent = "";
    if (!res.count) { out.innerHTML = "<p class='legend'>No line matches" + (res.period || res.comp ? " in this period / component (⤺ whole period, 🧩 All components to search everything)" : "") + ".</p>"; return; }
    const table = document.createElement("table");
    table.className = "ls-table";
    table.innerHTML = "<colgroup><col style='width:13em'><col style='width:4.2em'><col style='width:17em'><col></colgroup><tr><th>Time</th><th>Level</th><th>File:line</th><th>Line (click: the lines around it)</th></tr>";
    out.appendChild(table);
    res.shown = 0;
    res.hl = highlighter(res.terms);
    more(res, table);
  }
  async function more(res, table) {
    const end = Math.min(res.rows.length, res.shown + PAGE), my = gen;
    for (let i = res.shown; i < end; i++) {
      const r = res.rows[i], f = IDX.files[r[1]];
      const sh = await load(r[1], r[2]);
      if (my !== gen) return;
      let e2 = sh.text.indexOf("\n", r[3]);
      if (e2 < 0) e2 = sh.text.length;
      const line = sh.text.slice(r[3], e2), lvl = levelOf(line);
      const tr = document.createElement("tr");
      tr.dataset.i = i;
      const where = f.short + ":" + r[4];
      const link = f.href ? "<a class='lv-link' href='" + f.href + "#L" + r[4] + "' target='_blank' title='" + esc(f.label) + " at line " + r[4] + "'>" + esc(where) + "</a>" : "<span title='" + esc(f.label) + "'>" + esc(where) + "</span>";
      tr.innerHTML = "<td class='ls-time'>" + (r[0] === Infinity ? "—" : esc(pgStamp(r[0]))) + "</td><td>" + (lvl ? "<span class='ls-lvl " + lvl + "'>" + lvl + "</span>" : "") + "</td><td class='ls-file'>" + link + (f.tag ? "<br><i class='ls-tag'>" + esc(f.tag) + "</i>" : "") + "</td><td class='ls-line'>" + res.hl(line.length > 2000 ? line.slice(0, 2000) + " …" : line) + "</td>";
      table.appendChild(tr);
    }
    res.shown = end;
    const old = out.querySelector(".ls-more");
    if (old) old.remove();
    if (res.shown < res.rows.length) {
      const b = document.createElement("button");
      b.type = "button"; b.className = "pill ls-more";
      b.textContent = "Show " + Math.min(PAGE, res.rows.length - res.shown) + " more (" + (res.rows.length - res.shown).toLocaleString() + " left)";
      b.addEventListener("click", function () { more(res, table); });
      out.appendChild(b);
    }
  }
  async function context(tr) {
    const next = tr.nextElementSibling;
    if (next && next.classList.contains("ls-ctx")) { next.remove(); return; }
    const r = last.rows[+tr.dataset.i], f = IDX.files[r[1]], sh = await load(r[1], r[2]), txt = sh.text;
    let a = r[3];
    for (let k = 0; k < CTX && a > 0; k++) a = txt.lastIndexOf("\n", a - 2) + 1;
    let b = r[3];
    for (let k = 0; k <= CTX && b >= 0 && b < txt.length; k++) { b = txt.indexOf("\n", b + 1); if (b < 0) b = txt.length; }
    const lines = txt.slice(a, b).split("\n");
    const firstNo = r[4] - (txt.slice(a, r[3]).split("\n").length - 1);
    const html = lines.map((l, k) => "<span class='" + (firstNo + k === r[4] ? "ls-hit" : "") + "'><span class='ls-n'>" + String(firstNo + k).padStart(6) + "  </span>" + last.hl(l) + "</span>").join("\n");
    const row = document.createElement("tr");
    row.className = "ls-ctx";
    row.innerHTML = "<td colspan='4'><pre>" + html + "</pre>" + (f.href ? "<a class='lv-link' href='" + f.href + "#L" + r[4] + "' target='_blank'>open " + esc(f.label) + " at line " + r[4] + " ↗</a>" : "") + "</td>";
    tr.after(row);
  }
  function drawHist(res) {
    hist.textContent = "";
    if (res.r0 === null || res.r1 === null || !(res.r1 > res.r0) || !res.bins.some(Boolean)) return;
    const W = 1000, H = 90, top = 6, bottom = 18, max = Math.max(...res.bins), bw = W / BINS, step = (res.r1 - res.r0) / BINS;
    let s = "<svg viewBox='0 0 " + W + " " + H + "' preserveAspectRatio='none' role='img' aria-label='matches over time'>";
    res.bins.forEach(function (n, i) {
      if (!n) return;
      const h = Math.max(2, (H - top - bottom) * n / max);
      s += "<rect class='ls-bar-r' data-b='" + i + "' x='" + (i * bw + .5) + "' y='" + (H - bottom - h) + "' width='" + Math.max(1, bw - 1) + "' height='" + h + "'><title>" + n.toLocaleString() + " line(s) " + pgStamp(res.r0 + i * step) + " → " + pgStamp(res.r0 + (i + 1) * step) + " (click: this period)</title></rect>";
    });
    s += "<text class='ls-axis' x='2' y='" + (H - 4) + "'>" + pgStamp(res.r0) + "</text><text class='ls-axis' x='" + (W - 2) + "' y='" + (H - 4) + "' text-anchor='end'>" + pgStamp(res.r1) + "</text>";
    s += "<rect class='ls-sel' x='0' y='" + top + "' width='0' height='" + (H - top - bottom) + "' visibility='hidden'/></svg>";
    hist.innerHTML = s;
    const svg = hist.querySelector("svg"), sel = svg.querySelector(".ls-sel");
    const xOf = ev => { const r = svg.getBoundingClientRect(); return Math.min(W, Math.max(0, (ev.clientX - r.left) * W / r.width)); };
    svg.addEventListener("mousedown", function (ev) {
      if (ev.button !== 0) return;
      histDrag = {from: xOf(ev), xOf: xOf, sel: sel, tOf: x => res.r0 + (res.r1 - res.r0) * x / W, bin: i => [res.r0 + i * step, res.r0 + (i + 1) * step]};
      ev.preventDefault();
    });
  }
  // the drag of the histogram shown (the listeners of the window registered once, not at each search)
  let histDrag = null;
  window.addEventListener("mousemove", function (ev) {
    const d = histDrag;
    if (!d) return;
    const x = d.xOf(ev);
    d.sel.setAttribute("x", Math.min(x, d.from)); d.sel.setAttribute("width", Math.abs(x - d.from));
    d.sel.setAttribute("visibility", Math.abs(x - d.from) > 4 ? "visible" : "hidden");
  });
  window.addEventListener("mouseup", function (ev) {
    const d = histDrag;
    if (!d) return;
    histDrag = null;
    const x = d.xOf(ev);
    d.sel.setAttribute("visibility", "hidden");
    if (typeof pgSetPeriod !== "function") return;
    if (Math.abs(x - d.from) > 4) { pgSetPeriod(d.tOf(Math.min(x, d.from)), d.tOf(Math.max(x, d.from))); return; }
    const bar = ev.target.closest && ev.target.closest(".ls-bar-r");
    if (bar) { const b = d.bin(+bar.dataset.b); pgSetPeriod(b[0], b[1]); }
  });
  let timer = null;
  q.addEventListener("keydown", function (ev) { if (ev.key === "Enter") { ev.preventDefault(); clearTimeout(timer); run(q.value); } });
  q.addEventListener("input", function () { clearTimeout(timer); if (!q.value.trim()) run(""); else if (q.value.trim().length >= 3) timer = setTimeout(() => run(q.value), 700); });
  card.addEventListener("click", function (ev) {
    if (ev.target.closest(".ls-go")) { run(q.value); return; }
    if (ev.target.closest(".ls-from-bar")) { const bar = document.querySelector(".pg-search"); if (bar && bar.value.trim()) { q.value = bar.value; run(q.value); } return; }
    const add = ev.target.closest(".ls-stat");
    if (add && add.dataset.add) { q.value = (q.value.trim() + " " + add.dataset.add).trim(); run(q.value); return; }
    const tr = ev.target.closest("tr[data-i]");
    if (tr && !ev.target.closest("a") && last) context(tr);
  });
  // the period and the component of the filter bar: the search again
  const again = () => { if (q.value.trim()) { clearTimeout(timer); timer = setTimeout(() => run(q.value), 50); } };
  document.addEventListener("pgperiod", again);
  document.addEventListener("click", function (ev) { if (ev.target.closest(".comp-chip")) setTimeout(again, 0); });
  // 🔎 next to the search box of the filter bar: the same text in every line
  const barBox = document.querySelector(".pg-search");
  if (barBox) {
    const b = document.createElement("button");
    b.type = "button"; b.className = "pill pg-every-line";
    b.textContent = "🔎 Every log line";
    b.title = "search every line of the logs (INFO included) for this text: 🔎 Search every log line";
    barBox.after(b);
    b.addEventListener("click", function () {
      if (barBox.value.trim()) { q.value = barBox.value; run(q.value); }
      card.scrollIntoView({block: "start"});
      q.focus();
    });
  }
  document.addEventListener("DOMContentLoaded", function () {
    if (window.pgLogQueryInitial) { q.value = window.pgLogQueryInitial; run(q.value); }
  });
})();
</script>"""


def scripts(chart_id: str) -> str:
    return PERIOD_SCRIPT.replace("@@CHART@@", chart_id) + SEARCH_SCRIPT


def entries_from(sources_file: str, files: List[dict], viewers: Dict[str, str], comp_of: Callable[[str], str]) -> List[dict]:
    """the files of the input (the sources file of analyze logs: label, path, stays), with their component, their page
    and their occurrences (log_report.py files)"""
    by_key = {f.get("path", f["label"]): f for f in files}
    out = []
    try:
        with open(sources_file, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                key, path = (line.rstrip("\n").split("\t") + ["", ""])[:2]
                f = by_key.get(key)
                label = f["label"] if f else key
                out.append({"label": label, "path": path, "comp": comp_of(label), "href": viewers.get(label, ""),
                            "occurrences": (f or {}).get("occurrences") or 0})
    except OSError:
        return []
    return out

