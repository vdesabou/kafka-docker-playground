#!/usr/bin/env python3
"""Progress of playground analyze logs on large inputs: a bar in the terminal and a page in the browser.

  progress.py page --step <text>
      writes the 🔄 progress page: it reloads itself every 2 s until the HTML report replaces it at the same path
      (log_report.py writes the report next to it then renames it)
  progress.py cat --label <file> [--size <bytes>]
      copies stdin to stdout (the input of the digest) and shows the bytes read: a bar on stderr when it is a terminal
      and the input is large, and the page every 2 s
  progress.py human <bytes>
      prints 2.4 GB, 168.1 MB, 12 KB
  progress.py size <path>…
      prints "<bytes> <files> <1 when there is an archive, else 0>" of files and folders (recursively)

The page and the overall progress come from the environment, exported once by analyze logs:
  PG_PROGRESS_HTML         the progress page (the path of the report), none: no page
  PG_PROGRESS_TITLE        what is analyzed
  PG_PROGRESS_STARTED      epoch seconds of the start of the command
  PG_PROGRESS_STEP         the step shown on the page (progress.py cat, json_log_export.py)
  PG_PROGRESS_COUNTS       0: the bytes read are not bytes of the input (the converted copy of an export)
  PG_PROGRESS_DONE / PG_PROGRESS_TOTAL              files analyzed / to analyze
  PG_PROGRESS_BYTES / PG_PROGRESS_TOTAL_BYTES       bytes of the files analyzed / of all the files
No bar when stderr is not a terminal (CI, --json piped): the page only.
"""
import argparse
import html
import os
import sys
import time

CHUNK = 1 << 20
MIN_BAR_SIZE = 20 << 20


def human(n: float) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        # rounded first: 1023.6 KB is 1.0 MB, not "1024 KB"
        text = f"{n:.0f}" if unit in ("B", "KB") else f"{n:.1f}"
        if float(text) < 1024:
            return f"{text} {unit}"
        n /= 1024
    return f"{n:.1f} TB"


def clock(seconds: float) -> str:
    seconds = int(seconds)
    return f"{seconds // 60}:{seconds % 60:02d}"


def env_int(name: str) -> int:
    try:
        return int(os.environ.get(name) or 0)
    except ValueError:
        return 0


# the look of the reports (tools/report-common/report_html.py): same stylesheet, header, tiles and dark theme, so that the
# progress page looks like the report it becomes
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "report-common"))
try:
    import report_html as rh  # noqa: E402
except ImportError:  # the page stays plain
    rh = None

BAR_CSS = """
.step-card{background:#fff;border-radius:10px;padding:16px 20px;box-shadow:0 1px 3px rgba(0,0,0,.07);border-left:4px solid #2563eb;font-size:1rem;font-weight:500;margin-bottom:22px;word-break:break-all}
.bars{background:#fff;border-radius:10px;padding:18px 20px;box-shadow:0 1px 3px rgba(0,0,0,.07);margin-bottom:22px}
.bar-label{display:flex;justify-content:space-between;font-size:.84rem;color:#475569;margin:0 0 6px;font-variant-numeric:tabular-nums}
.pbar{height:14px;border-radius:7px;background:#e2e8f0;overflow:hidden;margin-bottom:16px}
.pbar:last-child{margin-bottom:0}
.pbar div{height:100%;background:linear-gradient(90deg,#1e3a5f,#2563eb);border-radius:7px}
.note{font-size:.8rem;color:#64748b}
"""


def bar_html(label: str, pct: float, text: str) -> str:
    e = rh.e if rh else html.escape
    return (f"<div class='bar-label'><span>{e(label)}</span><span>{pct:.0f}% · {e(text)}</span></div>"
            f"<div class='pbar'><div style='width:{pct:.1f}%'></div></div>")


def write_page(step: str, read_bytes: int = 0, file_size=None, speed: float = 0) -> None:
    """the page: the step, a bar for the file being read (same as the terminal: %, MB, speed, ETA) and one for the whole
    input, with the stylesheet and the header of the reports"""
    path = os.environ.get("PG_PROGRESS_HTML")
    if not path:
        return
    title = os.environ.get("PG_PROGRESS_TITLE", "playground analyze logs")
    try:
        started = float(os.environ.get("PG_PROGRESS_STARTED") or time.time())
    except ValueError:
        started = time.time()
    done, total = env_int("PG_PROGRESS_DONE"), env_int("PG_PROGRESS_TOTAL")
    done_bytes, total_bytes = env_int("PG_PROGRESS_BYTES"), env_int("PG_PROGRESS_TOTAL_BYTES")
    elapsed = time.time() - started
    e = rh.e if rh else html.escape
    bars = []
    tiles = [("⏱️ Elapsed", clock(elapsed), "min:s", "")]
    whole_eta = None
    if file_size:
        pct = min(100.0, 100.0 * read_bytes / file_size)
        bars.append(bar_html("📄 this file", pct, f"{human(read_bytes)} of {human(file_size)}"))
        tiles.append(("📄 This file", f"{pct:.0f}%", f"{human(read_bytes)} of {human(file_size)}", ""))
    elif read_bytes:
        tiles.append(("📄 This file", human(read_bytes), "read", ""))
    if total_bytes:
        # PG_PROGRESS_COUNTS=0: the file read is not a file of the input (the converted copy of an export)
        whole = min(total_bytes, done_bytes + (read_bytes if os.environ.get("PG_PROGRESS_COUNTS", "1") != "0" else 0))
        pct = 100.0 * whole / total_bytes
        bars.append(bar_html("📦 whole input", pct, f"{human(whole)} of {human(total_bytes)}"))
        tiles.append(("📦 Whole input", f"{pct:.0f}%", f"{human(whole)} of {human(total_bytes)}", ""))
        # global ETA: the average rate since the start (extraction, conversion and digest together) applied to what is
        # left; an estimate, shown once the rate means something
        whole_eta = None
        if whole > 0 and elapsed >= 5 and whole < total_bytes:
            whole_eta = (total_bytes - whole) / (whole / elapsed)
    if speed:
        tiles.append(("⚡ Speed", human(speed) + "/s", "this file", ""))
        if file_size:
            tiles.append(("⏳ ETA", clock(max(0, file_size - read_bytes) / speed), "this file", ""))
    if total_bytes and whole_eta is not None:
        tiles.append(("🏁 ETA", "~" + clock(whole_eta), "whole input, average rate", ""))
    if total:
        tiles.append(("🗂️ Files", f"{min(done, total)} / {total}", "done", ""))
    note = "This page reloads every 2 s and becomes the report when the analysis ends."
    if rh:
        body = (f"<div class='step-card'>{e(step)}</div>"
                + rh.kpis_html([rh.kpi(label, value, unit, cls) for label, value, unit, cls in tiles])
                + (f"<div class='bars'>{''.join(bars)}</div>" if bars else "")
                + f"<p class='note'>{e(note)}</p>")
        page = rh.page(f"🔄 {title}", "🔥 Log Analysis in progress", [e(title)], body, "playground analyze logs")
        style = f"<style>{BAR_CSS}" + rh.dark("""
.step-card,.bars{background:#1e293b;box-shadow:none;color:#e2e8f0}
.bar-label,.note{color:#94a3b8}
.pbar{background:#334155}
""") + "</style>"
        # reloaded every 2 s; the stylesheet of the bars after the shared one
        page = page.replace("<head>", "<head><meta http-equiv='refresh' content='2'>", 1).replace("</head>", style + "</head>", 1)
    else:
        page = (f"<!DOCTYPE html><html><head><meta charset='utf-8'><meta http-equiv='refresh' content='2'>"
                f"<title>🔄 {e(title)}</title></head><body><h1>🔥 Log Analysis in progress</h1><p>{e(title)}</p>"
                f"<p>{e(step)}</p>{''.join(bars)}<p>{e(note)}</p></body></html>")
    tmp = path + ".progress"
    try:
        with open(tmp, "w", encoding="utf-8") as fh:
            fh.write(page)
        os.replace(tmp, path)
    except OSError:
        pass


class Progress:
    """bytes read from one input: update(n) as it is read, close() at the end"""

    def __init__(self, label: str, size, step: str = ""):
        self.label = os.path.basename(label) or label
        self.size = size or None
        self.step = step or os.environ.get("PG_PROGRESS_STEP") or f"🔎 reading {label}"
        self.bar = sys.stderr.isatty() and (self.size is None or self.size >= MIN_BAR_SIZE)
        self.read = 0
        self.begin = time.time()
        self.last_bar = 0.0
        self.last_page = 0.0
        write_page(self.step, 0, self.size)

    def update(self, n: int) -> None:
        self.read += n
        now = time.time()
        if self.bar and now - self.last_bar >= 0.5:
            self.last_bar = now
            speed = self.read / max(now - self.begin, 0.001)
            if self.size:
                pct = min(100.0, 100.0 * self.read / self.size)
                full = int(pct / 4)
                eta = max(0, self.size - self.read) / speed if speed else 0
                line = (f"\r⏳ {self.label} ▕{'█' * full}{'░' * (25 - full)}▏ {pct:3.0f}% "
                        f"{human(self.read)}/{human(self.size)} {human(speed)}/s ETA {clock(eta)}  ")
            else:
                line = f"\r⏳ {self.label}: {human(self.read)} read, {human(speed)}/s  "
            sys.stderr.write(line)
            sys.stderr.flush()
        if now - self.last_page >= 2:
            self.last_page = now
            write_page(self.step, self.read, self.size, self.read / max(now - self.begin, 0.001))

    def close(self) -> None:
        if self.bar:
            sys.stderr.write("\r\033[K")
            sys.stderr.flush()


ARCHIVES = (".zip", ".tar", ".tgz", ".tar.gz", ".tbz2", ".tar.bz2", ".txz", ".tar.xz", ".7z")


def cmd_size(paths) -> int:
    total = files = 0
    archive = 0
    for path in paths:
        walk = [(os.path.dirname(path), [], [os.path.basename(path)])] if os.path.isfile(path) else os.walk(path)
        for root, _, names in walk:
            for name in names:
                try:
                    total += os.path.getsize(os.path.join(root, name))
                except OSError:
                    continue
                files += 1
                if name.lower().endswith(ARCHIVES):
                    archive = 1
    print(total, files, archive)
    return 0


def cmd_cat(args) -> int:
    progress = Progress(args.label, args.size)
    src, out = sys.stdin.buffer, sys.stdout.buffer
    try:
        while True:
            chunk = src.read(CHUNK)
            if not chunk:
                break
            out.write(chunk)
            progress.update(len(chunk))
        out.flush()
    except BrokenPipeError:
        pass
    finally:
        progress.close()
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("page")
    p.add_argument("--step", required=True)
    c = sub.add_parser("cat")
    c.add_argument("--label", required=True)
    c.add_argument("--size", type=int, help="bytes of the input, for a percentage")
    h = sub.add_parser("human")
    h.add_argument("bytes", type=int)
    z = sub.add_parser("size")
    z.add_argument("paths", nargs="+")
    args = ap.parse_args()
    if args.cmd == "size":
        return cmd_size(args.paths)
    if args.cmd == "human":
        print(human(args.bytes))
        return 0
    if args.cmd == "page":
        write_page(args.step)
        return 0
    return cmd_cat(args)


if __name__ == "__main__":
    sys.exit(main())
