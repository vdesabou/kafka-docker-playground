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
        if n < 1024:
            return f"{n:.0f} {unit}" if unit in ("B", "KB") else f"{n:.1f} {unit}"
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


def write_page(step: str, read_bytes: int = 0) -> None:
    path = os.environ.get("PG_PROGRESS_HTML")
    if not path:
        return
    title = os.environ.get("PG_PROGRESS_TITLE", "playground analyze logs")
    started = float(os.environ.get("PG_PROGRESS_STARTED") or time.time())
    done, total = env_int("PG_PROGRESS_DONE"), env_int("PG_PROGRESS_TOTAL")
    done_bytes, total_bytes = env_int("PG_PROGRESS_BYTES"), env_int("PG_PROGRESS_TOTAL_BYTES")
    detail = []
    if total:
        detail.append(f"file {min(done + 1, total)} of {total}")
    if total_bytes:
        detail.append(f"{human(min(done_bytes + read_bytes, total_bytes))} of {human(total_bytes)} read")
    bar = ""
    if total_bytes:
        pct = min(100.0, 100.0 * (done_bytes + read_bytes) / total_bytes)
        bar = f"<div class='bar'><div style='width:{pct:.1f}%'></div></div><p class='pct'>{pct:.0f}%</p>"
    page = f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta http-equiv="refresh" content="2">
<title>🔄 {html.escape(title)}</title>
<style>
body {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 4rem auto; max-width: 46rem;
       padding: 0 1rem; color: #1f2328; background: #fff; }}
@media (prefers-color-scheme: dark) {{ body {{ color: #e6edf3; background: #0d1117; }} .bar {{ background: #30363d; }} }}
h1 {{ font-size: 1.4rem; }} .step {{ font-size: 1.1rem; margin: 1.5rem 0 .5rem; word-break: break-all; }}
.bar {{ height: 14px; border-radius: 7px; background: #eaeef2; overflow: hidden; }}
.bar div {{ height: 100%; background: #2f81f7; }}
.pct {{ margin: .3rem 0 0; font-variant-numeric: tabular-nums; }} .muted {{ color: #8b949e; font-size: .9rem; word-break: break-all; }}
</style></head><body>
<h1>🔥 Log Analysis in progress</h1>
<p class="muted">{html.escape(title)}</p>
<p class="step">{html.escape(step)}</p>
{bar}
<p class="muted">{html.escape(" · ".join(detail))}</p>
<p class="muted">⏱️ {clock(time.time() - started)} elapsed · this page reloads every 2 s and becomes the report when the analysis ends</p>
</body></html>
"""
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
        write_page(self.step)

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
            write_page(self.step, self.read)

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
