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
:root{--t:0s}
@keyframes pg-shift{0%{background-position:0% 50%}50%{background-position:100% 50%}100%{background-position:0% 50%}}
@keyframes pg-pulse{0%{box-shadow:0 0 0 0 rgba(74,222,128,.7)}70%{box-shadow:0 0 0 9px rgba(74,222,128,0)}100%{box-shadow:0 0 0 0 rgba(74,222,128,0)}}
@keyframes pg-stripes{from{background-position:0 0}to{background-position:40px 0}}
@keyframes pg-shine{0%{transform:translateX(-100%)}100%{transform:translateX(250%)}}
@keyframes pg-spin{to{transform:rotate(360deg)}}
@keyframes pg-glow{0%,100%{filter:drop-shadow(0 0 4px rgba(56,189,248,.45))}50%{filter:drop-shadow(0 0 12px rgba(139,92,246,.75))}}
.header{background:linear-gradient(120deg,#0f172a,#1e3a8a,#4f46e5,#0ea5e9,#1e3a8a);background-size:300% 300%;animation:pg-shift 20s ease infinite;animation-delay:var(--t);position:relative;overflow:hidden}
.header h1{display:flex;align-items:center;gap:12px}
.live{display:inline-flex;align-items:center;gap:7px;font-size:.68rem;font-weight:700;letter-spacing:.14em;background:rgba(255,255,255,.14);border:1px solid rgba(255,255,255,.25);padding:3px 10px 3px 8px;border-radius:999px;backdrop-filter:blur(6px)}
.live i{width:8px;height:8px;border-radius:50%;background:#4ade80;animation:pg-pulse 2s infinite;animation-delay:var(--t)}
.hero{display:grid;grid-template-columns:auto 1fr;gap:28px;align-items:center;background:#fff;border-radius:16px;padding:24px 28px;margin-bottom:22px;box-shadow:0 10px 30px -12px rgba(30,58,138,.25);border:1px solid #e2e8f0;position:relative;overflow:hidden}
.hero:before{content:"";position:absolute;inset:-40% -10% auto auto;width:420px;height:420px;background:radial-gradient(circle,rgba(99,102,241,.16),transparent 65%);pointer-events:none}
.ring{position:relative;width:148px;height:148px}
.ring svg{width:148px;height:148px;transform:rotate(-90deg);animation:pg-glow 4s ease-in-out infinite;animation-delay:var(--t)}
.ring .track{stroke:#e2e8f0}
.ring .arc{transition:stroke-dashoffset 1.6s cubic-bezier(.22,1,.36,1)}
.ring .orbit{position:absolute;inset:0;animation:pg-spin 4s linear infinite;animation-delay:var(--t)}
.ring .orbit:after{content:"";position:absolute;top:6px;left:50%;width:8px;height:8px;margin-left:-4px;border-radius:50%;background:#38bdf8;box-shadow:0 0 10px 3px rgba(56,189,248,.7)}
.ring-center{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;font-variant-numeric:tabular-nums}
.ring-pct{font-size:2.1rem;font-weight:800;line-height:1;background:linear-gradient(135deg,#2563eb,#7c3aed);-webkit-background-clip:text;background-clip:text;color:transparent}
.ring-sub{font-size:.68rem;color:#64748b;text-transform:uppercase;letter-spacing:.1em;margin-top:4px}
.step{display:flex;align-items:center;gap:12px;font-size:1.08rem;font-weight:600;word-break:break-all;position:relative}
.spinner{flex:none;width:20px;height:20px;border-radius:50%;border:3px solid rgba(99,102,241,.2);border-top-color:#6366f1;border-right-color:#0ea5e9;animation:pg-spin 1s linear infinite;animation-delay:var(--t)}
.phases{display:flex;align-items:center;gap:0;margin-top:20px;flex-wrap:wrap;position:relative}
.phase{display:flex;align-items:center;gap:8px;font-size:.8rem;color:#94a3b8;font-weight:600;white-space:nowrap}
.phase b{display:flex;align-items:center;justify-content:center;width:26px;height:26px;border-radius:50%;border:2px solid #cbd5e1;font-size:.75rem;background:#fff}
.phase.done{color:#16a34a}.phase.done b{border-color:#16a34a;background:#16a34a;color:#fff}
.phase.now{color:#4f46e5}.phase.now b{border-color:#6366f1;background:linear-gradient(135deg,#6366f1,#0ea5e9);color:#fff;animation:pg-pulse 2s infinite;animation-delay:var(--t)}
.link{flex:1;min-width:24px;height:2px;margin:0 10px;background:#e2e8f0;border-radius:2px}
.link.done{background:linear-gradient(90deg,#16a34a,#22c55e)}
.link.now{background:linear-gradient(90deg,#6366f1 0%,#0ea5e9 50%,#e2e8f0 50%);background-size:200% 100%;animation:pg-shift 2s linear infinite;animation-delay:var(--t)}
.kpi-grid{grid-template-columns:repeat(auto-fit,minmax(150px,1fr))}
.kpi-card{border-left:0;border-radius:14px;border:1px solid #e2e8f0;position:relative;overflow:hidden;transition:transform .2s,box-shadow .2s}
.kpi-card:before{content:"";position:absolute;left:0;top:0;right:0;height:3px;background:linear-gradient(90deg,#2563eb,#7c3aed,#0ea5e9)}
.kpi-card:hover{transform:translateY(-2px);box-shadow:0 10px 24px -12px rgba(37,99,235,.45)}
.kpi-value{font-variant-numeric:tabular-nums;letter-spacing:-.02em}
.bars{background:#fff;border-radius:14px;padding:20px 22px;border:1px solid #e2e8f0;margin-bottom:22px}
.bar-label{display:flex;justify-content:space-between;font-size:.84rem;color:#475569;margin:0 0 8px;font-variant-numeric:tabular-nums;font-weight:500}
.pbar{height:16px;border-radius:999px;background:#e2e8f0;overflow:hidden;margin-bottom:18px;box-shadow:inset 0 1px 3px rgba(0,0,0,.12)}
.pbar:last-child{margin-bottom:0}
.pbar div{position:relative;height:100%;border-radius:999px;overflow:hidden;background:linear-gradient(90deg,#2563eb,#7c3aed,#0ea5e9);background-size:200% 100%;box-shadow:0 0 14px rgba(99,102,241,.55);transition:width 1.6s cubic-bezier(.22,1,.36,1)}
.pbar div:before{content:"";position:absolute;inset:0;background-image:linear-gradient(45deg,rgba(255,255,255,.18) 25%,transparent 25%,transparent 50%,rgba(255,255,255,.18) 50%,rgba(255,255,255,.18) 75%,transparent 75%);background-size:40px 40px;animation:pg-stripes 1s linear infinite;animation-delay:var(--t)}
.pbar div:after{content:"";position:absolute;top:0;bottom:0;width:40%;background:linear-gradient(90deg,transparent,rgba(255,255,255,.45),transparent);animation:pg-shine 2s ease-in-out infinite;animation-delay:var(--t)}
.note{font-size:.8rem;color:#64748b;display:flex;align-items:center;gap:8px}
.note i{width:6px;height:6px;border-radius:50%;background:#6366f1;animation:pg-pulse 2s infinite;animation-delay:var(--t)}
@media (max-width:640px){.hero{grid-template-columns:1fr;justify-items:center}}
@media (prefers-reduced-motion:reduce){*,*:before,*:after{animation:none!important;transition:none!important}}
"""

DARK_BAR_CSS = """
.hero,.bars,.kpi-card{background:#1e293b;border-color:#334155;box-shadow:0 10px 30px -14px rgba(0,0,0,.7)}
.hero:before{background:radial-gradient(circle,rgba(99,102,241,.28),transparent 65%)}
.ring .track{stroke:#334155}
.ring-pct{background:linear-gradient(135deg,#60a5fa,#c084fc);-webkit-background-clip:text;background-clip:text}
.step{color:#f1f5f9}
.phase b{background:#0f172a;border-color:#475569}
.phase.now{color:#a5b4fc}.phase.done{color:#4ade80}
.phase.done b{background:#16a34a;border-color:#16a34a}
.phase.now b{background:linear-gradient(135deg,#6366f1,#0ea5e9);border-color:#6366f1}
.link{background:#334155}
.link.done{background:linear-gradient(90deg,#16a34a,#22c55e)}
.link.now{background:linear-gradient(90deg,#6366f1 0%,#0ea5e9 50%,#334155 50%);background-size:200% 100%}
.bar-label,.note,.ring-sub{color:#94a3b8}
.pbar{background:#0f172a;box-shadow:inset 0 1px 3px rgba(0,0,0,.6)}
"""

# continuous animations carry on across the reloads of the page (every period divides 100 s), the bars and the ring grow
# from their width at the previous reload, and the elapsed time ticks between two reloads
PAGE_SCRIPT = """<script>
document.documentElement.style.setProperty("--t", -(Date.now() % 100000) / 1000 + "s");
document.addEventListener("DOMContentLoaded", function () {
  var store = null;
  try { store = window.sessionStorage; } catch (e) {}
  document.querySelectorAll("[data-pct]").forEach(function (el, i) {
    var key = "pg-progress-" + i, pct = parseFloat(el.dataset.pct), prev = null;
    try { prev = store && store.getItem(key); } catch (e) {}
    var set = function (p) {
      if (el.dataset.c) el.style.strokeDashoffset = el.dataset.c * (1 - p / 100);
      else el.style.width = p + "%";
    };
    if (prev !== null && parseFloat(prev) <= pct) {
      el.style.transition = "none"; set(parseFloat(prev)); el.getBoundingClientRect(); el.style.transition = "";
    }
    requestAnimationFrame(function () { requestAnimationFrame(function () { set(pct); }); });
    try { store && store.setItem(key, pct); } catch (e) {}
  });
  var tile = document.querySelector("[data-started] .kpi-value"), started = parseFloat((tile && tile.parentNode.dataset.started) || 0);
  if (tile && started) setInterval(function () {
    var s = Math.max(0, Math.floor(Date.now() / 1000 - started));
    tile.textContent = Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
  }, 1000);
});
</script>"""

RING_C = 2 * 3.14159265 * 64

PHASES = ("📦 extract", "🔎 digest", "🧠 analyze", "📝 report")


def phase_of(step: str) -> int:
    """index in PHASES of a step of analyze logs (from its emoji), -1 before the first one"""
    if step.startswith("📦"):
        return 0
    if "starting" in step:
        return -1
    if step.startswith(("🔎", "🔄")):
        return 1
    if step.startswith("📝"):
        return 3
    return 2


def phases_html(step: str) -> str:
    now = phase_of(step)
    out = []
    for i, label in enumerate(PHASES):
        cls = "done" if i < now else "now" if i == now else ""
        if i:
            out.append(f"<span class='link {'done' if i <= now else 'now' if i == now + 1 and now >= 0 else ''}'></span>")
        icon, name = label.split(" ", 1)
        out.append(f"<span class='phase {cls}'><b>{'✓' if cls == 'done' else icon}</b>{name}</span>")
    return f"<div class='phases'>{''.join(out)}</div>"


def ring_html(pct, sub: str) -> str:
    gid = "pg-ring-grad"
    if pct is None:
        center = "<div class='ring-pct'>…</div>"
        arc = ""
    else:
        center = f"<div class='ring-pct'>{pct:.0f}%</div>"
        arc = (f"<circle class='arc' data-pct='{pct:.1f}' data-c='{RING_C:.1f}' cx='74' cy='74' r='64' fill='none' "
               f"stroke='url(#{gid})' stroke-width='12' stroke-linecap='round' stroke-dasharray='{RING_C:.1f}' "
               f"style='stroke-dashoffset:{RING_C * (1 - pct / 100):.1f}'/>")
    return (f"<div class='ring'><svg viewBox='0 0 148 148' aria-hidden='true'><defs><linearGradient id='{gid}' x1='0' y1='0' x2='1' y2='1'>"
            "<stop offset='0' stop-color='#2563eb'/><stop offset='.55' stop-color='#7c3aed'/><stop offset='1' stop-color='#0ea5e9'/>"
            "</linearGradient></defs><circle class='track' cx='74' cy='74' r='64' fill='none' stroke-width='12'/>"
            f"{arc}</svg><div class='orbit'></div><div class='ring-center'>{center}<div class='ring-sub'>{html.escape(sub)}</div></div></div>")


def bar_html(label: str, pct: float, text: str) -> str:
    e = rh.e if rh else html.escape
    return (f"<div class='bar-label'><span>{e(label)}</span><span>{pct:.0f}% · {e(text)}</span></div>"
            f"<div class='pbar'><div data-pct='{pct:.1f}' style='width:{pct:.1f}%'></div></div>")


def write_page(step: str, read_bytes: int = 0, file_size=None, speed: float = 0) -> None:
    """the page: a ring with the progress of the whole input, the step and the phase it belongs to, tiles (elapsed, %, MB,
    speed, ETA, files) and a bar for the file being read and one for the whole input, with the stylesheet and the header
    of the reports"""
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
    ring_pct, ring_sub = None, "whole input"
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
        ring_pct = pct
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
        cards = [rh.kpi(label, value, unit, cls) for label, value, unit, cls in tiles]
        # the elapsed time ticks every second between two reloads (PAGE_SCRIPT)
        cards[0] = cards[0].replace('<div class="kpi-card ', f'<div data-started="{started:.0f}" class="kpi-card ', 1)
        body = (f"<div class='hero'>{ring_html(ring_pct, ring_sub)}<div><div class='step'><span class='spinner'></span>"
                f"<span>{e(step)}</span></div>{phases_html(step)}</div></div>"
                + rh.kpis_html(cards)
                + (f"<div class='bars'>{''.join(bars)}</div>" if bars else "")
                + f"<p class='note'><i></i>{e(note)}</p>")
        page = rh.page(f"🔄 {title}", "🔥 Log Analysis in progress <span class='live'><i></i>LIVE</span>", [e(title)], body,
                       "playground analyze logs")
        style = f"<style>{BAR_CSS}" + rh.dark(DARK_BAR_CSS) + "</style>"
        # reloaded every 2 s; the stylesheet of the page after the shared one
        page = page.replace("<head>", "<head><meta http-equiv='refresh' content='2'>", 1).replace("</head>", style + PAGE_SCRIPT + "</head>", 1)
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
