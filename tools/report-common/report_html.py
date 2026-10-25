#!/usr/bin/env python3
"""
Look shared by the HTML reports of the playground commands (same as analyze thread-dump / gc-logs / tcp-dump):
header, verdict banner, tiles, findings with severity badges, tables, SVG charts. Self-contained: no external resource.

Imported by tools/log-analyzer/log_report.py, tools/connector-diagnose/diagnose_report.py, tools/dlq-tool/dlq_report.py,
tools/heap-analyzer/heap_report.py and tools/connector-diff/diff_report.py, which add this folder to sys.path.
"""

import re
from datetime import datetime, timedelta
from typing import Callable, Dict, List, Optional, Sequence, Tuple

SEVERITY_ORDER = ["CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO", "OK"]
SEVERITY_ICONS = {"CRITICAL": "🔴", "HIGH": "🟠", "MEDIUM": "🟡", "LOW": "🟢", "INFO": "ℹ️", "OK": "✅"}

# same palette as the other playground reports
SERIES_1 = "#2a78d6"
SERIES_2 = "#eb6834"

HTML_CSS = """<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#f1f5f9;color:#1e293b;line-height:1.5}
.page{max-width:1300px;margin:0 auto;padding:24px}
h1{font-size:1.55rem;font-weight:700}
h2{font-size:1.05rem;font-weight:600;margin-bottom:12px;color:#334155}
h3{font-size:.95rem;font-weight:600;margin:14px 0 8px;color:#334155}
.header{background:linear-gradient(135deg,#1e3a5f 0%,#2563eb 100%);color:#fff;border-radius:12px;padding:22px 28px;margin-bottom:22px}
.header-meta{font-size:.83rem;opacity:.85;margin-top:6px}
.header-meta span{margin-right:18px}
.kpi-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(175px,1fr));gap:14px;margin-bottom:22px}
.kpi-card{background:#fff;border-radius:10px;padding:14px 16px;box-shadow:0 1px 3px rgba(0,0,0,.07);border-left:4px solid #2563eb}
.kpi-card.warn{border-left-color:#d97706}.kpi-card.danger{border-left-color:#dc2626}.kpi-card.ok{border-left-color:#16a34a}
.kpi-label{font-size:.75rem;color:#64748b;text-transform:uppercase;letter-spacing:.05em}
.kpi-value{font-size:1.75rem;font-weight:700;margin:3px 0 2px;word-break:break-word}
.kpi-unit{font-size:.73rem;color:#94a3b8}
.charts-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(560px,1fr));gap:18px;margin-bottom:22px}
.chart-card{background:#fff;border-radius:10px;padding:18px 20px;box-shadow:0 1px 3px rgba(0,0,0,.07)}
.chart-card svg{width:100%;height:auto}
.chart-card svg rect:hover{opacity:.75}
.legend{font-size:.78rem;color:#475569;margin-bottom:6px}
.legend i{display:inline-block;width:10px;height:10px;border-radius:2px;margin:0 5px 0 12px;vertical-align:-1px}
.section-title{font-size:1.05rem;font-weight:600;color:#334155;margin:0 0 12px;padding-top:4px}
.recs-list{display:flex;flex-direction:column;gap:9px;margin-bottom:22px}
.rec-card{background:#fff;border-radius:8px;padding:12px 14px 12px 18px;box-shadow:0 1px 3px rgba(0,0,0,.06);border-left:5px solid #94a3b8;display:flex;align-items:flex-start;gap:10px}
.rec-card.critical{border-left-color:#dc2626}.rec-card.high{border-left-color:#ea580c}.rec-card.medium{border-left-color:#d97706}
.rec-card.low{border-left-color:#16a34a}.rec-card.info{border-left-color:#3b82f6}.rec-card.ok{border-left-color:#0891b2}
.rec-badge{font-size:.68rem;font-weight:700;text-transform:uppercase;padding:2px 7px;border-radius:20px;white-space:nowrap;margin-top:2px}
.rec-badge.critical{background:#fee2e2;color:#dc2626}.rec-badge.high{background:#ffedd5;color:#ea580c}.rec-badge.medium{background:#fef3c7;color:#d97706}
.rec-badge.low{background:#dcfce7;color:#16a34a}.rec-badge.info{background:#dbeafe;color:#2563eb}.rec-badge.ok{background:#cffafe;color:#0891b2}
.rec-text{font-size:.88rem;flex:1;color:#334155}
.table-card{background:#fff;border-radius:10px;padding:18px 20px;box-shadow:0 1px 3px rgba(0,0,0,.07);overflow-x:auto;margin-bottom:22px}
table{width:100%;border-collapse:collapse;font-size:.84rem}
th{text-align:left;padding:7px 11px;background:#f8fafc;font-weight:600;border-bottom:2px solid #e2e8f0;color:#475569}
td{padding:7px 11px;border-bottom:1px solid #f1f5f9;vertical-align:top}
td.num,th.num{text-align:right;font-variant-numeric:tabular-nums}
tr:hover td{background:#f8fafc}
.mono{font-family:'SFMono-Regular',Consolas,'Liberation Mono',Menlo,monospace;font-size:.78rem;word-break:break-all}
details{border-top:1px solid #f1f5f9;padding:2px 0}
details summary{cursor:pointer;font-size:.84rem;padding:6px 0}
.st{display:inline-block;font-size:.68rem;font-weight:700;padding:1px 7px;border-radius:12px;background:#f1f5f9;color:#475569;white-space:nowrap}
.st.fatal,.st.failed{background:#fee2e2;color:#dc2626}.st.error{background:#ffedd5;color:#c2410c}.st.warn,.st.paused,.st.unassigned{background:#fef3c7;color:#b45309}
.st.running{background:#dcfce7;color:#15803d}.st.mine{background:#dbeafe;color:#1d4ed8}
.verdict{background:#fff;border-radius:10px;padding:14px 18px;box-shadow:0 1px 3px rgba(0,0,0,.07);border-left:4px solid #16a34a;font-size:1rem;font-weight:500;margin-bottom:22px}
.verdict.danger{border-left-color:#dc2626}.verdict.warn{border-left-color:#d97706}.verdict.ok{border-left-color:#16a34a}
pre{font-family:'SFMono-Regular',Consolas,Menlo,monospace;font-size:.76rem;background:#f8fafc;padding:10px;border-radius:6px;overflow-x:auto;white-space:pre-wrap;word-break:break-all;margin:4px 0 8px}
.diff-a{background:#fee2e2}.diff-b{background:#dcfce7}.muted{color:#94a3b8}
code{font-family:'SFMono-Regular',Consolas,Menlo,monospace;font-size:.8rem;background:#f1f5f9;padding:1px 5px;border-radius:4px}
.footer{text-align:center;font-size:.78rem;color:#94a3b8;padding:14px}
</style>"""


def e(s) -> str:
    return (str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;"))


def kpi(label, val, unit, cls="") -> str:
    return (f'<div class="kpi-card {cls}"><div class="kpi-label">{e(label)}</div>'
            f'<div class="kpi-value">{e(val)}</div><div class="kpi-unit">{e(unit)}</div></div>')


def kpis_html(cards: Sequence[str]) -> str:
    return f"<div class='kpi-grid'>{''.join(cards)}</div>"


def verdict_html(cls: str, text: str) -> str:
    """cls: danger, warn or ok"""
    return f"<div class='verdict {cls}'>{e(text)}</div>"


def sort_findings(items: List[dict]) -> List[dict]:
    return sorted(items, key=lambda f: SEVERITY_ORDER.index(f["severity"]))


def findings_html(items: List[dict]) -> str:
    if not items:
        return ""
    return ("<div class='section-title'>🔎 Findings</div><div class='recs-list'>"
            + "".join(f'<div class="rec-card {f["severity"].lower()}"><span class="rec-badge {f["severity"].lower()}">'
                      f'{SEVERITY_ICONS.get(f["severity"], "")} {e(f["severity"])}</span><span class="rec-text">{e(f["text"])}</span></div>'
                      for f in items)
            + "</div>")


def badge(text: str, cls: str = "") -> str:
    """Small pill: cls among fatal, failed, error, warn, paused, running, mine"""
    return f"<span class='st {e(cls or text.lower())}'>{e(text)}</span>"


def card(title: str, body: str) -> str:
    return f"<div class='table-card'><h2>{title}</h2>{body}</div>"


def table(headers: Sequence[str], rows: Sequence[Sequence[str]], num: Sequence[int] = ()) -> str:
    """Cells are HTML already (escape them with e()); num: indexes of the right-aligned numeric columns"""
    head = "".join(f"<th class='num'>{h}</th>" if i in num else f"<th>{h}</th>" for i, h in enumerate(headers))
    body = "".join("<tr>" + "".join(f"<td class='num'>{c}</td>" if i in num else f"<td>{c}</td>" for i, c in enumerate(r)) + "</tr>"
                   for r in rows)
    return f"<table><tr>{head}</tr>{body}</table>"


def charts_grid(cards: Sequence[Tuple[str, str]]) -> str:
    """cards: (title, svg)"""
    cards = [c for c in cards if c[1]]
    if not cards:
        return ""
    return "<div class='charts-grid'>" + "".join(f"<div class='chart-card'><h2>{t}</h2>{s}</div>" for t, s in cards) + "</div>"


def nice_max(v: float) -> int:
    """Axis maximum: an even integer of the form 1, 2, 2.5, 3, 4, 5, 6 or 8 x 10^n, so that the middle tick is an integer too."""
    if v <= 2:
        return 2
    magnitude = 10 ** (len(str(int(v))) - 1)
    for m in (1, 2, 2.5, 3, 4, 5, 6, 8, 10):
        top = int(m * magnitude)
        if top >= v and top % 2 == 0:
            return top
    return int(10 * magnitude)


def fmt_bytes(n: float) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if abs(n) < 1024 or unit == "GB":
            return f"{n:,.0f} {unit}" if unit == "B" else f"{n:,.1f} {unit}"
        n /= 1024.0
    return f"{n:,.1f} GB"


BUCKETS = [1, 5, 10, 30, 60, 300, 600, 1800, 3600, 7200, 21600, 43200, 86400]


def fmt_bucket(seconds: int) -> str:
    if seconds < 60:
        return f"{seconds}s"
    if seconds < 3600:
        return f"{seconds // 60}min"
    if seconds < 86400:
        return f"{seconds // 3600}h"
    return f"{seconds // 86400}d"


def time_bins(points: List[Tuple[datetime, str]], keys: Sequence[str]) -> Optional[dict]:
    """Count of points per key and per time bucket (at most 60 buckets); None without points."""
    if not points:
        return None
    start = min(p[0] for p in points)
    end = max(p[0] for p in points)
    span = (end - start).total_seconds()
    bucket = next((b for b in BUCKETS if span / b <= 60), BUCKETS[-1])
    start = datetime.fromtimestamp(int(start.timestamp()) // bucket * bucket)
    n = int((end - start).total_seconds() // bucket) + 1
    bins: List[Dict] = [dict({"start": start + timedelta(seconds=i * bucket)}, **{k: 0 for k in keys}) for i in range(n)]
    for ts, key in points:
        bins[int((ts - start).total_seconds() // bucket)][key] += 1
    return {"bucket": bucket, "bins": bins}


def svg_time_columns(tl: dict, series: Sequence[Tuple[str, str, str]], note: str = "") -> str:
    """Columns per time bucket; several series side by side in each bucket (never stacked on two scales).
    series: (key, label, color); the series without any value are left out."""
    bins = tl["bins"]
    series = [s for s in series if any(b[s[0]] for b in bins)] or list(series[:1])
    W, H, L, B, T = 600, 190, 44, 26, 8
    pw, ph = W - L - 10, H - B - T
    mx = nice_max(max((b[k] for b in bins for k, _, _ in series), default=0))
    n = len(bins)
    slot = pw / n
    bw = max(1.0, (slot - 2) / len(series))
    one_day = bins[0]["start"].date() == bins[-1]["start"].date()
    fmt = "%H:%M:%S" if tl["bucket"] < 60 else "%H:%M" if one_day else "%m-%d %H:%M"
    out = [f'<svg viewBox="0 0 {W} {H}" xmlns="http://www.w3.org/2000/svg" role="img">']
    for frac in (0, 0.5, 1):
        y = T + ph * (1 - frac)
        out.append(f'<line x1="{L}" x2="{W - 10}" y1="{y:.1f}" y2="{y:.1f}" stroke="#e2e8f0" stroke-width="1"/>'
                   f'<text x="{L - 6}" y="{y + 3:.1f}" font-size="10" fill="#64748b" text-anchor="end">{int(mx * frac)}</text>')
    for i, b in enumerate(bins):
        for j, (key, label, color) in enumerate(series):
            v = b[key]
            if not v:
                continue
            h = max(1.5, ph * v / mx)
            x = L + i * slot + 1 + j * bw
            out.append(f'<rect x="{x:.1f}" y="{T + ph - h:.1f}" width="{bw:.1f}" height="{h:.1f}" rx="1" fill="{color}">'
                       f'<title>{b["start"].strftime("%Y-%m-%d %H:%M:%S")}: {v} {e(label)}</title></rect>')
    step = max(1, n // 6)
    for i in range(0, n, step):
        out.append(f'<text x="{L + i * slot + slot / 2:.1f}" y="{H - 8}" font-size="10" fill="#64748b" text-anchor="middle">'
                   f'{bins[i]["start"].strftime(fmt)}</text>')
    out.append("</svg>")
    legend = "".join(f"<i style='background:{c}'></i>{e(l)}" for _, l, c in series)
    return f"<div class='legend'>{legend} · per {fmt_bucket(tl['bucket'])}{e(note)}</div>" + "".join(out)


def svg_hbars(rows: Sequence[Tuple[str, float, str]], fmt: Optional[Callable[[float], str]] = None) -> str:
    """Horizontal bars: (label, value, tooltip)"""
    if not rows:
        return ""
    fmt = fmt or (lambda v: f"{int(v)}")
    W, rowh, L = 600, 22, 300
    H = 10 + rowh * len(rows)
    mx = max(v for _, v, _ in rows) or 1
    out = [f'<svg viewBox="0 0 {W} {H}" xmlns="http://www.w3.org/2000/svg" role="img">']
    for i, (lab, v, tip) in enumerate(rows):
        y = 5 + i * rowh
        w = (W - L - 70) * v / mx
        out.append(f'<text x="{L - 6}" y="{y + 14}" font-size="10" fill="#334155" text-anchor="end">{e(lab[:52])}</text>'
                   f'<rect x="{L}" y="{y + 3}" width="{max(1, w):.1f}" height="15" rx="2" fill="{SERIES_1}"><title>{e(tip)}</title></rect>'
                   f'<text x="{L + w + 5:.1f}" y="{y + 14}" font-size="10" fill="#475569">{e(fmt(v))}</text>')
    out.append("</svg>")
    return "".join(out)


def page(title: str, h1: str, meta: List[str], body: str, footer: str) -> str:
    """meta: HTML snippets of the header line (escape them with e())"""
    meta = meta + [f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"]
    return ("<!DOCTYPE html><html lang='en'><head><meta charset='UTF-8'><meta name='viewport' content='width=device-width,initial-scale=1'>"
            f"<title>{e(title)}</title>{HTML_CSS}</head><body><div class='page'>"
            f"<div class='header'><h1>{h1}</h1><div class='header-meta'>"
            + "".join(f"<span>{m}</span>" for m in meta) + "</div></div>"
            + body + f"<div class='footer'>{footer}</div></div></body></html>")


# connector config keys holding a secret, and the ones that only look like it
SECRET_KEY_RE = re.compile(r"password|secret|token|credential|jaas|api\.key|apikey|private\.key|keytab|\.key$", re.I)
NOT_SECRET_KEY_RE = re.compile(r"(^|\.)(key|value|header)\.converter|key\.ignore|\.key\.field|key\.fields|key\.mode|primary\.key|"
                               r"\.keys?$|secret\.manager|\.provider", re.I)


def mask_secret(key: str, value) -> str:
    """The value of a connector config key, masked when the key holds a secret (except ${...} config provider references)"""
    value = "" if value is None else str(value)
    if SECRET_KEY_RE.search(key) and not NOT_SECRET_KEY_RE.search(key) and value and not value.startswith("${"):
        return "********"
    return value
