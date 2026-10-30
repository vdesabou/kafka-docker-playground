#!/usr/bin/env python3
"""
Log viewer pages of the HTML reports of playground analyze logs (tools/log-analyzer/log_report.py, and the CFK bundle
report cfk-analysis/html_report.py): one page per file with findings, written next to the report in a
<report>-files/ folder, with line numbers, a #L<n> anchor per line, the lines of the findings highlighted and
"previous / next finding" buttons. A location of the report (connect-0.log:33) links to <report>-files/<page>#L33.

The input files are often extracted from an archive to a temporary folder deleted at the end of the command, and the
report is sanitized: so the pages are a copy of the files, sanitized with the same placeholders as the report.
A big file keeps only the lines around the findings.
"""

import gzip
import os
import re
import shutil
from typing import Callable, Dict, Iterable, List, Optional, Tuple

from report_html import e, log_html, style

# a file up to this size is copied whole, a bigger one only around the findings
MAX_FULL_BYTES = 2 * 1024 * 1024
# lines kept before and after each finding of a big file
WINDOW = 250
# findings highlighted per file (their windows for a big file)
MAX_HITS = 300
# lines sanitized at once (several lines together: a multi-line secret, a PEM block)
SANITIZE_CHUNK = 500

VIEWER_CSS = """
.page{max-width:none}
.lv-bar{position:sticky;top:0;z-index:5;display:flex;flex-wrap:wrap;align-items:center;gap:8px;padding:8px 12px;margin-bottom:12px;
border-radius:8px;background:#fff;box-shadow:0 1px 3px rgba(0,0,0,.08);font-size:.8rem;color:#475569}
.lv-bar button,.lv-bar a.lv-btn{font-family:inherit;font-size:.78rem;padding:3px 10px;border-radius:6px;border:1px solid #cbd5e1;
background:#f8fafc;color:#1e293b;cursor:pointer;text-decoration:none}
.lv-bar button:hover,.lv-bar a.lv-btn:hover{background:#e2e8f0}
.lv{background:#fff;border-radius:10px;box-shadow:0 1px 3px rgba(0,0,0,.07);padding:8px 0;overflow-x:auto;
font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:.76rem;line-height:1.45}
.lv .l{display:flex;white-space:pre;scroll-margin-top:90px}
.lv .l:hover{background:#f1f5f9}
.lv .n{flex:0 0 auto;min-width:5.5em;padding:0 10px;text-align:right;color:#94a3b8;user-select:none;text-decoration:none;
border-right:1px solid #e2e8f0;margin-right:10px}
.lv .n:hover{color:#2563eb}
.lv .l.hit{background:#fef3c7}.lv .l.hit .n{color:#b45309;font-weight:600}
.lv .l:target,.lv .l.cur{background:#fde68a;box-shadow:inset 4px 0 0 #d97706}
.lv .gap{padding:4px 16px;color:#64748b;font-style:italic;background:#f8fafc;border-top:1px dashed #cbd5e1;border-bottom:1px dashed #cbd5e1}
html[data-theme=dark] .lv-bar,html[data-theme=dark] .lv{background:#1e293b;color:#cbd5e1}
html[data-theme=dark] .lv-bar button,html[data-theme=dark] .lv-bar a.lv-btn{background:#0f172a;color:#cbd5e1;border-color:#334155}
html[data-theme=dark] .lv .l:hover{background:#0f172a}
html[data-theme=dark] .lv .n{border-right-color:#334155}
html[data-theme=dark] .lv .l.hit{background:#422006}
html[data-theme=dark] .lv .l:target,html[data-theme=dark] .lv .l.cur{background:#713f12}
html[data-theme=dark] .lv .gap{background:#0f172a;border-color:#334155}
"""

# previous / next finding (buttons, n / p keys), from the line of the URL (#L33) or the current one
VIEWER_SCRIPT = """<script>
(function () {
  const hits = [...document.querySelectorAll(".lv .l.hit")];
  let cur = -1;
  function show(i) {
    if (!hits.length) return;
    cur = (i + hits.length) % hits.length;
    document.querySelectorAll(".lv .l.cur").forEach(l => l.classList.remove("cur"));
    hits[cur].classList.add("cur");
    hits[cur].scrollIntoView({block: "center"});
    history.replaceState(null, "", "#" + hits[cur].id);
    document.getElementById("lv-pos").textContent = (cur + 1) + " / " + hits.length;
  }
  function fromHash() {
    const line = document.getElementById(location.hash.slice(1));
    if (!line) return;
    const n = +line.id.slice(1);
    cur = hits.findIndex(h => +h.id.slice(1) >= n);
    if (cur < 0) cur = hits.length - 1;
    if (hits.length) document.getElementById("lv-pos").textContent = (cur + 1) + " / " + hits.length;
    line.scrollIntoView({block: "center"});
  }
  document.getElementById("lv-prev").addEventListener("click", () => show(cur < 0 ? hits.length - 1 : cur - 1));
  document.getElementById("lv-next").addEventListener("click", () => show(cur + 1));
  document.addEventListener("keydown", ev => {
    if (ev.target.closest("input,textarea") || ev.metaKey || ev.ctrlKey || ev.altKey) return;
    if (ev.key === "n") show(cur + 1);
    if (ev.key === "p") show(cur < 0 ? hits.length - 1 : cur - 1);
  });
  window.addEventListener("hashchange", fromHash);
  fromHash();
})();
</script>"""


def read_lines(path: str) -> Optional[List[str]]:
    """lines of a text file (a .gz one decompressed), None when it cannot be read"""
    try:
        if path.endswith(".gz"):
            with gzip.open(path, "rt", encoding="utf-8", errors="replace") as fh:
                text = fh.read()
        else:
            with open(path, encoding="utf-8", errors="replace") as fh:
                text = fh.read()
    except (OSError, EOFError, gzip.BadGzipFile):
        return None
    return text.split("\n")[:-1] if text.endswith("\n") else text.split("\n")


def file_size(path: str) -> int:
    """size of the text of a file: its decompressed size for a .gz (from its trailer, modulo 4 GB)"""
    try:
        if path.endswith(".gz"):
            with open(path, "rb") as fh:
                fh.seek(-4, os.SEEK_END)
                return int.from_bytes(fh.read(4), "little")
        return os.path.getsize(path)
    except OSError:
        return 0


def kept_ranges(nb_lines: int, hits: Iterable[int], whole: bool) -> List[Tuple[int, int]]:
    """(first, last) line numbers (1-based, inclusive) kept: every line, or WINDOW lines around each finding merged"""
    if whole or nb_lines == 0:
        return [(1, nb_lines)] if nb_lines else []
    ranges: List[Tuple[int, int]] = []
    for h in sorted(set(hits)) or [1]:
        lo, hi = max(1, h - WINDOW), min(nb_lines, h + WINDOW)
        if ranges and lo <= ranges[-1][1] + 1:
            ranges[-1] = (ranges[-1][0], max(ranges[-1][1], hi))
        else:
            ranges.append((lo, hi))
    return ranges


def sanitized_lines(lines: List[str], sanitize: Optional[Callable[[str], str]]) -> List[str]:
    """the lines sanitized by chunks, one output line per input line (the line numbers of the report stay right)"""
    if sanitize is None:
        return lines
    out: List[str] = []
    for i in range(0, len(lines), SANITIZE_CHUNK):
        chunk = lines[i:i + SANITIZE_CHUNK]
        done = sanitize("\n".join(chunk)).split("\n")
        # a multi-line secret collapsed: line by line
        if len(done) != len(chunk):
            done = [sanitize(line).replace("\n", " ") for line in chunk]
        out.extend(done)
    return out


def page_name(index: int, label: str) -> str:
    """file name of the page of a file: its number and its base name (the label may hold a path or archive:path)"""
    base = re.sub(r"[^\w.-]+", "_", re.split(r"[/:\\]", label.rstrip("/"))[-1])[:80] or "file"
    return f"{index:03d}-{base}.html"


def write_page(path: str, out_path: str, label: str, hits: Iterable[int], sanitize: Optional[Callable[[str], str]],
               report_name: str, note: str = "") -> bool:
    """writes the viewer page of one file; hits: line numbers of its findings (highlighted); report_name: file name of
    the report, for the link back. False when the file cannot be read."""
    lines = read_lines(path)
    if lines is None:
        return False
    hits = sorted({h for h in hits if h and 0 < h <= len(lines)})[:MAX_HITS]
    whole = file_size(path) <= MAX_FULL_BYTES
    ranges = kept_ranges(len(lines), hits, whole)
    hit_set = set(hits)
    body: List[str] = []
    previous_end = 0
    for lo, hi in ranges:
        if lo > previous_end + 1:
            body.append(f"<div class='gap'>⋯ lines {previous_end + 1}–{lo - 1} not copied (file over "
                        f"{MAX_FULL_BYTES // (1024 * 1024)} MB: {WINDOW} lines around each finding)</div>")
        for n, text in enumerate(sanitized_lines(lines[lo - 1:hi], sanitize), start=lo):
            body.append(f"<div class='l{' hit' if n in hit_set else ''}' id='L{n}'><a class='n' href='#L{n}'>{n}</a>"
                        f"<span>{log_html(text)}</span></div>")
        previous_end = hi
    if previous_end < len(lines):
        body.append(f"<div class='gap'>⋯ lines {previous_end + 1}–{len(lines)} not copied (file over "
                    f"{MAX_FULL_BYTES // (1024 * 1024)} MB: {WINDOW} lines around each finding)</div>")
    copied = "whole file" if whole else f"{sum(hi - lo + 1 for lo, hi in ranges)} of {len(lines)} lines"
    bar = (f"<div class='lv-bar'><a class='lv-btn' href='../{e(report_name)}'>⬅️ Report</a>"
           f"<button type='button' id='lv-prev' title='previous finding (p)'>▲ Previous</button>"
           f"<button type='button' id='lv-next' title='next finding (n)'>▼ Next</button>"
           f"<span>finding <span id='lv-pos'>– / {len(hits)}</span></span>"
           f"<span class='mono'>· {e(label)} · {len(lines)} lines · {copied}</span>"
           + (f"<span>· {e(note)}</span>" if note else "") + "</div>")
    html = ("<!DOCTYPE html><html lang='en'><head><meta charset='UTF-8'><meta name='viewport' content='width=device-width,initial-scale=1'>"
            f"<title>{e(label.rsplit('/', 1)[-1])}</title>{style(VIEWER_CSS)}</head><body><div class='page'>"
            f"{bar}<div class='lv'>{''.join(body)}</div></div>{VIEWER_SCRIPT}</body></html>")
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as fh:
        fh.write(html)
    return True


def write_pages(report_path: str, files: List[Tuple[str, str, Iterable[int]]], sanitize: Optional[Callable[[str], str]],
                note: str = "") -> Dict[str, str]:
    """writes the viewer pages of the files of a report, in <report stem>-files/ next to it.
    files: (label, path on disk, line numbers of the findings). Returns label -> href relative to the report."""
    report_dir = os.path.dirname(os.path.abspath(report_path))
    report_name = os.path.basename(report_path)
    folder = os.path.splitext(report_name)[0] + "-files"
    # the pages of a previous report with the same name
    shutil.rmtree(os.path.join(report_dir, folder), ignore_errors=True)
    hrefs: Dict[str, str] = {}
    for i, (label, path, hits) in enumerate(files, start=1):
        if label in hrefs or not path or not os.path.isfile(path):
            continue
        name = page_name(i, label)
        if write_page(path, os.path.join(report_dir, folder, name), label, hits, sanitize, report_name, note):
            hrefs[label] = f"{folder}/{name}"
    return hrefs


def link(hrefs: Dict[str, str], label: str, text: str, line: Optional[int] = None) -> str:
    """text (already escaped) as a link to the page of a file at a line, unchanged when the file has no page"""
    href = hrefs.get(label)
    if not href:
        return text
    return (f"<a class='lv-link' href='{e(href)}{f'#L{line}' if line else ''}' target='_blank' rel='noopener' "
            f"title='open {e(label)}{f' at line {line}' if line else ''}'>{text}</a>")
