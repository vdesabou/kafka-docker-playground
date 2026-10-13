#!/usr/bin/env python3
"""
JVM GC Log Analyzer — JDK 7 through JDK 21+

Collectors : G1GC · CMS · ParallelGC · SerialGC · ZGC · GenZGC · Shenandoah
Formats    : JDK 7/8 legacy (-XX:+PrintGCDetails / -XX:+PrintGC, multi-line records included)
             JDK 9+   unified (-Xlog:gc*), any decoration (time, uptime, timemillis, uptimenanos…)
             JDK 21+  generational ZGC

Input      : one or several files (rotated kafkaServer-gc.log, .log.0…, .gz) or folders.
             Files are ordered by timestamp and split into JVM runs (restarts); the latest run is
             analyzed unless --run is given.

Exit codes : 0 analysis done, 2 no input / no GC event found, 1 usage error.
"""

import argparse
import glob
import gzip
import html as _html
import json
import math
import os
import re
import statistics
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import datetime
from typing import Dict, List, Optional, Tuple

# ── Collector identifiers ─────────────────────────────────────────────────────
G1GC       = "G1GC"
CMS        = "CMS"
PARALLEL   = "ParallelGC"
SERIAL     = "SerialGC"
ZGC        = "ZGC"
ZGC_GEN    = "GenZGC"
SHENANDOAH = "Shenandoah"
UNKNOWN    = "Unknown"

FORMAT_LEGACY  = "legacy"
FORMAT_UNIFIED = "unified-logging"

SEVERITIES = ("CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO", "OK")

# Kafka's own JVM settings (kafka-run-class.sh, KAFKA_JVM_PERFORMANCE_OPTS)
KAFKA_G1_DEFAULTS = "-XX:+UseG1GC -XX:MaxGCPauseMillis=20 -XX:InitiatingHeapOccupancyPercent=35 -XX:+ExplicitGCInvokesConcurrent"

MIN_TREND_MINUTES = 30      # below this, no heap / pause trend and no leak verdict
MIN_THROUGHPUT_SEC = 60     # below this, no throughput figure

# ── Regex catalogue ───────────────────────────────────────────────────────────

_SIZE = r'\d+(?:\.\d+)?[BKMG]'

_VER_PATTERNS = [
    re.compile(r'\bVersion:\s+(?P<v>\d+)[.+]'),
    re.compile(r'\bJRE\s*\(1\.(?P<v>[5-9])\.\d'),
    re.compile(r'\bJRE\s*\((?P<v>[1-9]\d)[.+]'),
    re.compile(r'version\s+"1\.(?P<v>[5-9])\.', re.I),
    re.compile(r'version\s+"(?P<v>[1-9]\d)[."]', re.I),
]

_RE_USING_GC = re.compile(
    r'\bUsing\s+(?P<gc>The Z Garbage Collector|ZGC|G1|Shenandoah|Serial|Parallel(?:\s+GC)?)\b'
)

# unified logging: decorations then message
_UL_LINE    = re.compile(r'^((?:\[[^\]]*\])+)\s*(.*)$')
_UL_DECOR   = re.compile(r'\[([^\]]*)\]')
_UL_GCID    = re.compile(r'^GC\((\d+)\)\s+(?:(?P<gen>[YOyo]):\s+)?(?P<body>.*)$')
_UL_ZGC_LIVE = re.compile(r'^Live:\s+-\s+(\d+)M')
_UL_PAUSE_HEAP = re.compile(
    r'^(?P<type>Pause .+?)\s+(?P<b>\d+[KMG])->(?P<a>\d+[KMG])\((?P<t>\d+[KMG])\)\s+(?P<p>[\d.]+)ms\s*$')
_UL_PAUSE_NOHP = re.compile(r'^(?P<type>Pause .+?)\s+(?P<p>[\d.]+)ms\s*$')
# ZGC (JDK 11-17: "Garbage Collection (cause) 256M(25%)->128M(12%)"; JDK 21 GenZGC: "Major Collection (cause) A(p%)->B(q%) 0.127s")
_UL_ZGC_SUMMARY = re.compile(
    r'^(?P<kind>Garbage Collection|Major Collection|Minor Collection)\s+\((?P<cause>[^)]+)\)'
    r'(?:\s+\((?P<gen>Minor|Major)\))?'
    r'\s+(?P<b>[\d.]+[KMG])\(\d+%\)->(?P<a>[\d.]+[KMG])\(\d+%\)(?:\s+(?P<d>[\d.]+)s)?\s*$')
_UL_CONC_HEAP = re.compile(
    r'^(?P<type>Concurrent [a-z ]+?)(?:\s+\([^)]*\))*\s+(?P<b>\d+[KMG])->(?P<a>\d+[KMG])\((?P<t>\d+[KMG])\)\s+[\d.]+ms\s*$')
_UL_CONC_CYCLE = re.compile(r'^Concurrent (?:Mark Cycle|Cycle)\s+[\d.]+ms')
_UL_STALL = re.compile(r'^(?P<kind>Allocation|Relocation) Stall \((?P<thread>[^)]*)\)\s+(?P<ms>[\d.]+)ms')
_RE_HUMONGOUS = re.compile(r'Humongous regions:\s*(\d+)->(\d+)')
_RE_HEAP_MAX  = re.compile(r'^(?:Heap )?Max Capacity:\s*(\d+(?:\.\d+)?[KMG])')
_RE_HEAP_ADDR = re.compile(r'Heap address: \S+, size: (\d+) MB')
_RE_REGION    = re.compile(r'Heap [Rr]egion [Ss]ize:\s*(\d+[KMG])')
_RE_XMX_FLAG  = re.compile(r'-XX:MaxHeapSize=(\d+)|-Xmx(\d+[kKmMgG]?)\b')

# legacy: a record starts with "<date>: <uptime>: [GC" / "[Full GC"
_L_HEADER = re.compile(
    r'^(?:(?P<date>\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?[+-]\d{4}):\s*)?'
    r'(?:(?P<uptime>\d+\.\d+):\s*)?'
    r'(?P<rest>\[.*)$')
_L_TIMESTAMPED = re.compile(r'^(?:\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d|\d+\.\d+: )')
_L_TIMES   = re.compile(r'\[Times: user=(?P<user>[\d.]+) sys=(?P<sys>[\d.]+), real=(?P<real>[\d.]+) secs\]')
_L_NOISE   = re.compile(r'\[(?:Metaspace|PSPermGen|CMS Perm\s*|Perm\s*|Class Space)\s*:[^\]]*\]'
                        r'|\[CMS-concurrent[^\]]*\]|\[GC concurrent[^\]]*\]')
_L_EMBED_TS = re.compile(r'\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?[+-]\d{4}:\s*|\b\d+\.\d+:\s+(?=\[)')
_L_PAUSE   = re.compile(r'(\d+\.\d+)\s*secs\]')
_L_G1_HEAP = re.compile(r'Heap:\s*(' + _SIZE + r')\((' + _SIZE + r')\)->(' + _SIZE + r')\((' + _SIZE + r')\)')
_L_TRIPLE  = re.compile(r'(' + _SIZE + r')(?:\(' + _SIZE + r'\))?->(' + _SIZE + r')\((' + _SIZE + r')\)')
_L_OCCUP   = re.compile(r'\s(' + _SIZE + r')\((' + _SIZE + r')\),\s*\d+\.\d+\s*secs\]')
_L_CAUSE   = re.compile(r'^\[(?:Full GC|GC pause|GC)\s*\(([^)]*)\)')

_RE_CAUSE_PARENS = re.compile(r'\(([^)]*)\)')
_G1_KIND_TAGS = {"Normal", "Mixed", "Prepare Mixed", "Concurrent Start", "young", "mixed", "initial-mark"}
_NOT_CAUSES = _G1_KIND_TAGS | {"Major", "Minor", "process weakrefs", "unload classes", "update refs", "Mark", "Outside of Cycle"}

# ── HTML/CSS template (regular string — braces are literal CSS, not f-string) ──

_HTML_CSS = """<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;
     background:#f1f5f9;color:#1e293b;line-height:1.5}
.page{max-width:1300px;margin:0 auto;padding:24px}
h1{font-size:1.55rem;font-weight:700}
h2{font-size:1.05rem;font-weight:600;margin-bottom:12px;color:#334155}
.header{background:linear-gradient(135deg,#1e3a5f 0%,#2563eb 100%);color:#fff;
        border-radius:12px;padding:22px 28px;margin-bottom:22px;
        display:flex;justify-content:space-between;align-items:flex-start;
        flex-wrap:wrap;gap:16px}
.header-meta{font-size:.83rem;opacity:.85;margin-top:6px}
.header-meta span{margin-right:18px}
.health-badge{text-align:center;background:rgba(255,255,255,.92);border-radius:12px;
              padding:14px 22px;min-width:110px;box-shadow:0 2px 8px rgba(0,0,0,.15)}
.health-score{font-size:2.6rem;font-weight:800;line-height:1}
.health-label{font-size:.78rem;color:#475569;margin-top:3px}
.health-name{font-size:.85rem;font-weight:700;margin-top:2px}
.kpi-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(175px,1fr));
          gap:14px;margin-bottom:22px}
.kpi-card{background:#fff;border-radius:10px;padding:14px 16px;
          box-shadow:0 1px 3px rgba(0,0,0,.07);border-left:4px solid #2563eb}
.kpi-card.warn{border-left-color:#d97706}
.kpi-card.danger{border-left-color:#dc2626}
.kpi-card.ok{border-left-color:#16a34a}
.kpi-label{font-size:.75rem;color:#64748b;text-transform:uppercase;letter-spacing:.05em}
.kpi-value{font-size:1.75rem;font-weight:700;margin:3px 0 2px}
.kpi-unit{font-size:.73rem;color:#94a3b8}
.charts-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(560px,1fr));
             gap:18px;margin-bottom:22px}
.chart-card{background:#fff;border-radius:10px;padding:18px 20px;
            box-shadow:0 1px 3px rgba(0,0,0,.07)}
.chart-card svg{width:100%;height:auto;font-family:inherit}
.section-title{font-size:1.05rem;font-weight:600;color:#334155;
               margin:0 0 12px;padding-top:4px}
.recs-list{display:flex;flex-direction:column;gap:9px;margin-bottom:22px}
.rec-card{background:#fff;border-radius:8px;padding:12px 14px 12px 18px;
          box-shadow:0 1px 3px rgba(0,0,0,.06);border-left:5px solid #94a3b8;
          display:flex;align-items:flex-start;gap:10px}
.rec-card.critical{border-left-color:#dc2626}
.rec-card.high{border-left-color:#ea580c}
.rec-card.medium{border-left-color:#d97706}
.rec-card.low{border-left-color:#16a34a}
.rec-card.info{border-left-color:#3b82f6}
.rec-card.ok{border-left-color:#0891b2}
.rec-badge{font-size:.68rem;font-weight:700;text-transform:uppercase;
           padding:2px 7px;border-radius:20px;white-space:nowrap;margin-top:2px}
.rec-badge.critical{background:#fee2e2;color:#dc2626}
.rec-badge.high{background:#ffedd5;color:#ea580c}
.rec-badge.medium{background:#fef3c7;color:#d97706}
.rec-badge.low{background:#dcfce7;color:#16a34a}
.rec-badge.info{background:#dbeafe;color:#2563eb}
.rec-badge.ok{background:#cffafe;color:#0891b2}
.rec-text{font-size:.88rem;flex:1;color:#334155}
.rec-flag{display:block;margin-top:4px;font-family:'SFMono-Regular',Consolas,Menlo,monospace;font-size:.8rem;color:#1e293b}
.warn-box{background:#fff7ed;border-left:5px solid #ea580c;border-radius:8px;padding:12px 16px;margin-bottom:22px;font-size:.88rem}
.table-card{background:#fff;border-radius:10px;padding:18px 20px;
            box-shadow:0 1px 3px rgba(0,0,0,.07);overflow-x:auto;margin-bottom:22px}
table{width:100%;border-collapse:collapse;font-size:.84rem}
th{text-align:left;padding:7px 11px;background:#f8fafc;font-weight:600;
   border-bottom:2px solid #e2e8f0;color:#475569}
td{padding:7px 11px;border-bottom:1px solid #f1f5f9}
tr:hover td{background:#f8fafc}
.pause-hi{font-weight:700;color:#dc2626}
.full-gc-row td{background:#fff1f2!important}
.footer{text-align:center;font-size:.78rem;color:#94a3b8;padding:14px}
.flag-cell{font-family:'SFMono-Regular',Consolas,'Liberation Mono',Menlo,monospace;
           font-size:.8rem;color:#1e293b;word-break:break-all}
</style>"""


# ── Data ──────────────────────────────────────────────────────────────────────

@dataclass
class GCEvent:
    abs_ms:         Optional[float] = None   # wall clock (epoch ms) when the log has it
    uptime_ms:      Optional[float] = None   # JVM uptime when the log has it
    gc_id:          Optional[int]   = None
    gc_type:        str   = ""
    cause:          str   = ""
    pause_ms:       float = 0.0              # 0 for a concurrent cycle
    duration_ms:    float = 0.0              # concurrent cycle duration (ZGC)
    is_full:        bool  = False
    is_concurrent:  bool  = False
    old_gen:        bool  = False            # collection that reclaims the old generation (live set)
    heap_before_mb: float = 0.0
    heap_after_mb:  float = 0.0
    heap_total_mb:  float = 0.0
    evac_failure:   bool  = False
    cmf:            bool  = False            # CMS concurrent mode failure / promotion failed
    degenerated:    bool  = False
    cpu_user_s:     float = 0.0
    cpu_real_s:     float = 0.0
    src:            str   = ""
    t_ms:           float = 0.0              # time since the start of its run (computed)


@dataclass
class Marker:
    kind:      str                           # jvm_start, meta, stall, humongous, conc_cycle, conc_abort, to_space
    abs_ms:    Optional[float] = None
    uptime_ms: Optional[float] = None
    data:      dict = field(default_factory=dict)


@dataclass
class FileResult:
    path:          str
    log_format:    str = FORMAT_UNIFIED
    items:         list = field(default_factory=list)
    lines:         int = 0
    candidates:    int = 0
    parsed:        int = 0
    unparsed:      list = field(default_factory=list)
    collector:     str = UNKNOWN
    error:         str = ""

    def first_time(self) -> Tuple[Optional[float], Optional[float]]:
        for it in self.items:
            if it.abs_ms is not None or it.uptime_ms is not None:
                return it.abs_ms, it.uptime_ms
        return None, None


@dataclass
class Run:
    index:      int = 0
    events:     list = field(default_factory=list)
    stalls:     list = field(default_factory=list)
    meta:       dict = field(default_factory=dict)
    humongous_max: int = 0
    conc_cycles: int = 0
    conc_aborts: int = 0
    to_space_ids: set = field(default_factory=set)
    zgc_live:   dict = field(default_factory=dict)   # gc_id -> {"Y": mb, "O": mb, "": mb}
    has_start:  bool = False                 # starts at a JVM start header
    files:      list = field(default_factory=list)


# ── Helpers ───────────────────────────────────────────────────────────────────

def size_mb(s: str) -> float:
    m = re.match(r'([\d.]+)([BKMG])', s)
    if not m:
        return 0.0
    v, u = float(m.group(1)), m.group(2)
    return {"B": v / 1048576.0, "K": v / 1024.0, "M": v, "G": v * 1024.0}[u]


def _parse_iso(ts: str) -> Optional[float]:
    for fmt in ("%Y-%m-%dT%H:%M:%S.%f%z", "%Y-%m-%dT%H:%M:%S%z"):
        try:
            return datetime.strptime(ts, fmt).timestamp() * 1000
        except ValueError:
            pass
    return None


def _parse_decorations(decor: str) -> Tuple[Optional[float], Optional[float]]:
    """Return (abs_ms, uptime_ms) from unified logging decorations ([time][uptime][level][tags]…)"""
    abs_ms = uptime_ms = None
    for d in _UL_DECOR.findall(decor):
        d = d.strip()
        if re.match(r'^\d{4}-\d\d-\d\dT', d):
            abs_ms = _parse_iso(d)
        elif re.match(r'^\d+(?:\.\d+)?s$', d):
            uptime_ms = float(d[:-1]) * 1000
        elif re.match(r'^\d+ms$', d):
            v = float(d[:-2])
            if v > 1e11:
                abs_ms = v
            else:
                uptime_ms = v
        elif re.match(r'^\d+ns$', d):
            v = float(d[:-2])
            if v > 1e17:
                abs_ms = v / 1e6
            else:
                uptime_ms = v / 1e6
    return abs_ms, uptime_ms


def _percentile(sorted_values: list, p: float) -> float:
    """Nearest-rank percentile"""
    if not sorted_values:
        return 0.0
    k = max(0, min(len(sorted_values) - 1, math.ceil(len(sorted_values) * p) - 1))
    return sorted_values[k]


def _linreg_slope(xs: list, ys: list) -> float:
    """Least-squares slope, centered on the first x (epoch-ms x values lose precision otherwise)"""
    n = len(xs)
    if n < 2:
        return 0.0
    x0 = xs[0]
    xs = [x - x0 for x in xs]
    mx, my = sum(xs) / n, sum(ys) / n
    sxx = sum((x - mx) ** 2 for x in xs)
    if not sxx:
        return 0.0
    return sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / sxx


def _cause_and_label(gtype: str) -> Tuple[str, str, bool]:
    """'Pause Young (Concurrent Start) (G1 Humongous Allocation) (Evacuation Failure)' ->
       ('Pause Young (Concurrent Start)', 'G1 Humongous Allocation', evac_failure=True)"""
    parens = _RE_CAUSE_PARENS.findall(gtype)
    base = gtype.split(" (")[0].strip()
    evac = any("Evacuation Failure" in p or "To-space" in p or "to-space" in p for p in parens)
    kind = next((p for p in parens if p in _G1_KIND_TAGS), "")
    label = f"{base} ({kind})" if kind else base
    causes = [p for p in parens if p not in _NOT_CAUSES and "Evacuation Failure" not in p and "space" not in p]
    return label, (causes[0] if causes else ""), evac


def _read_lines(path: str) -> List[str]:
    opener = gzip.open if path.endswith(".gz") else open
    with opener(path, "rt", errors="replace") as fh:
        return [l.rstrip("\n").rstrip("\r") for l in fh]


def expand_inputs(paths: List[str]) -> Tuple[List[str], List[str]]:
    """Files as given; folders expanded to their GC logs (name containing 'gc'). Returns (files, errors)."""
    files, errors = [], []
    for p in paths:
        if os.path.isdir(p):
            found = sorted(f for f in glob.glob(os.path.join(p, "**", "*"), recursive=True)
                           if os.path.isfile(f) and "gc" in os.path.basename(f).lower()
                           and re.search(r'\.(?:log|txt|current)(?:\.\d+)?(?:\.gz)?$|\.log\.\d+$|\.gz$', f))
            if not found:
                errors.append(f"No GC log (file name containing 'gc') found in folder {p}")
            files.extend(found)
        elif os.path.isfile(p):
            files.append(p)
        else:
            errors.append(f"File not found: {p}")
    return files, errors


# ── Per-file parsing ──────────────────────────────────────────────────────────

def detect_collector(lines: List[str]) -> str:
    sample = lines[:400]
    for line in sample:
        m = _RE_USING_GC.search(line)
        if m:
            gc = m.group("gc").lower()
            if "z garbage" in gc or gc == "zgc":
                return ZGC_GEN if any("Generational" in l or "Minor Collection" in l or "Major Collection" in l
                                      or re.search(r'\((?:Minor|Major)\)', l) for l in lines[:2000]) else ZGC
            if "g1" in gc:
                return G1GC
            if "shenandoah" in gc:
                return SHENANDOAH
            if "serial" in gc:
                return SERIAL
            if "parallel" in gc:
                return PARALLEL
    text = "\n".join(lines[:3000])
    if re.search(r'-XX:\+UseG1GC', text):
        return G1GC
    if re.search(r'-XX:\+UseConcMarkSweepGC|ParNew|CMS-initial-mark|\bCMS\b', text):
        return CMS
    if re.search(r'PSYoungGen|ParOldGen|-XX:\+UseParallelGC', text):
        return PARALLEL
    if re.search(r'DefNew|Tenured|-XX:\+UseSerialGC', text):
        return SERIAL
    if re.search(r'Pause Init Mark|Pause Final Mark|Concurrent evacuation', text):
        return SHENANDOAH
    if re.search(r'(?:Major|Minor) Collection \(', text):
        return ZGC_GEN
    if re.search(r'Garbage Collection \(.*?%\)', text):
        return ZGC_GEN if re.search(r'\((?:Minor|Major)\)', text) else ZGC
    if re.search(r'G1 Evacuation|Pause Young|Pause Mixed|Pause Remark|GC pause \(', text):
        return G1GC
    return UNKNOWN


def parse_file(path: str) -> FileResult:
    fr = FileResult(path=path)
    try:
        lines = _read_lines(path)
    except (OSError, EOFError) as e:
        fr.error = f"cannot read {path}: {e}"
        return fr
    fr.lines = len(lines)
    nonempty = [l for l in lines[:300] if l.strip()]
    unified = sum(1 for l in nonempty if re.match(r'^\[[^\]]+\]', l))
    fr.log_format = FORMAT_UNIFIED if nonempty and unified > len(nonempty) * 0.5 else FORMAT_LEGACY
    fr.collector = detect_collector(lines)
    if fr.log_format == FORMAT_UNIFIED:
        _parse_unified(fr, lines)
    else:
        _parse_legacy(fr, lines)
    return fr


def _unparsed(fr: FileResult, line_no: int, line: str):
    fr.unparsed.append(f"{os.path.basename(fr.path)}:{line_no}: {line.strip()[:160]}")


def _parse_unified(fr: FileResult, lines: List[str]):
    col = fr.collector
    seen = set()
    for no, line in enumerate(lines, 1):
        m = _UL_LINE.match(line)
        if not m:
            continue
        abs_ms, uptime_ms = _parse_decorations(m.group(1))
        msg = m.group(2).strip()
        if not msg:
            continue
        g = _UL_GCID.match(msg)
        if not g:
            mu = _RE_USING_GC.match(msg)
            if mu:
                fr.items.append(Marker("jvm_start", abs_ms, uptime_ms, {"collector_line": msg}))
                continue
            data = {}
            mv = re.search(r'\bVersion:\s+(\S+)', msg)
            if mv:
                data["jdk_str"] = mv.group(1)
                data["jdk_version"] = int(re.match(r'\d+', mv.group(1)).group(0))
            mh = _RE_HEAP_MAX.search(msg)
            if mh:
                data["xmx_mb"] = size_mb(mh.group(1))
            ma = _RE_HEAP_ADDR.search(msg)
            if ma:
                data["xmx_mb"] = float(ma.group(1))
            mr = _RE_REGION.search(msg)
            if mr:
                data["region_mb"] = size_mb(mr.group(1))
            if data:
                fr.items.append(Marker("meta", abs_ms, uptime_ms, data))
                continue
            ms = _UL_STALL.match(msg)
            if ms:
                fr.items.append(Marker("stall", abs_ms, uptime_ms,
                                       {"kind": ms.group("kind"), "ms": float(ms.group("ms"))}))
            continue

        gc_id = int(g.group(1))
        body = g.group("body").strip()

        ml = _UL_ZGC_LIVE.match(body)
        if ml:
            fr.items.append(Marker("zgc_live", abs_ms, uptime_ms,
                                   {"gc_id": gc_id, "gen": (g.group("gen") or "").upper(), "mb": float(ml.group(1))}))
            continue

        if body.startswith("Pause "):
            if not re.search(r'[\d.]+ms\s*$', body):
                continue  # gc,start line, the end line carries the figures
            fr.candidates += 1
            mp = _UL_PAUSE_HEAP.match(body)
            mn = None if mp else _UL_PAUSE_NOHP.match(body)
            mm = mp or mn
            if not mm:
                _unparsed(fr, no, line)
                continue
            gtype = mm.group("type").strip()
            key = (gc_id, gtype, mm.group("p"))
            if key in seen:
                fr.candidates -= 1
                continue
            seen.add(key)
            label, cause, evac = _cause_and_label(gtype)
            base = label.split(" (")[0]
            is_full = base == "Pause Full"
            degenerated = "Degenerated" in base
            old_gen = is_full or degenerated or label == "Pause Young (Mixed)"
            ev = GCEvent(abs_ms=abs_ms, uptime_ms=uptime_ms, gc_id=gc_id, gc_type=label, cause=cause,
                         pause_ms=float(mm.group("p")), is_full=is_full, old_gen=old_gen,
                         evac_failure=evac, degenerated=degenerated,
                         src=f"{os.path.basename(fr.path)}:{no}")
            if mp:
                ev.heap_before_mb = size_mb(mp.group("b"))
                ev.heap_after_mb = size_mb(mp.group("a"))
                ev.heap_total_mb = size_mb(mp.group("t"))
            fr.items.append(ev)
            fr.parsed += 1
            continue

        mz = _UL_ZGC_SUMMARY.match(body)
        if mz:
            fr.candidates += 1
            gen = mz.group("gen") or ("Major" if mz.group("kind").startswith("Major")
                                      else "Minor" if mz.group("kind").startswith("Minor") else "")
            label = "ZGC Collection" + (f" ({gen})" if gen else "")
            fr.items.append(GCEvent(
                abs_ms=abs_ms, uptime_ms=uptime_ms, gc_id=gc_id, gc_type=label, cause=mz.group("cause"),
                is_concurrent=True, old_gen=(gen != "Minor"),
                duration_ms=float(mz.group("d")) * 1000 if mz.group("d") else 0.0,
                heap_before_mb=size_mb(mz.group("b")), heap_after_mb=size_mb(mz.group("a")),
                src=f"{os.path.basename(fr.path)}:{no}"))
            fr.parsed += 1
            continue

        if body.startswith("Concurrent "):
            mc = _UL_CONC_HEAP.match(body)
            if mc and col == SHENANDOAH:
                fr.items.append(GCEvent(
                    abs_ms=abs_ms, uptime_ms=uptime_ms, gc_id=gc_id, gc_type=mc.group("type"),
                    is_concurrent=True, old_gen=mc.group("type").startswith("Concurrent cleanup"),
                    heap_before_mb=size_mb(mc.group("b")), heap_after_mb=size_mb(mc.group("a")),
                    heap_total_mb=size_mb(mc.group("t")), src=f"{os.path.basename(fr.path)}:{no}"))
            elif _UL_CONC_CYCLE.match(body):
                fr.items.append(Marker("conc_cycle", abs_ms, uptime_ms))
            elif body.startswith("Concurrent Mark Abort"):
                fr.items.append(Marker("conc_abort", abs_ms, uptime_ms))
            continue

        if body.startswith("To-space exhausted"):
            fr.items.append(Marker("to_space", abs_ms, uptime_ms, {"gc_id": gc_id}))
            continue

        mh = _RE_HUMONGOUS.search(body)
        if mh:
            fr.items.append(Marker("humongous", abs_ms, uptime_ms, {"regions": int(mh.group(1))}))


def _parse_legacy(fr: FileResult, lines: List[str]):
    """JDK 7/8 logs: group a record header with its continuation lines, then parse the record"""
    record: Optional[Tuple[int, str, str, str]] = None   # (line_no, date, uptime, text)
    file_created = False

    def flush():
        if record is not None:
            _parse_legacy_record(fr, *record)

    for no, line in enumerate(lines, 1):
        if not line.strip():
            continue
        m = _L_HEADER.match(line) if _L_TIMESTAMPED.match(line) else None
        if m:
            rest = m.group("rest")
            # concurrent phases are printed by another thread, often in the middle of a pause record:
            # they never close the open record
            if rest.startswith("[GC concurrent") or rest.startswith("[CMS-concurrent"):
                times = _legacy_times(m.group("date"), m.group("uptime"))
                if "concurrent-mark-end" in rest or rest.startswith("[CMS-concurrent-sweep:"):
                    fr.items.append(Marker("conc_cycle", *times))
                elif "concurrent-mark-abort" in rest:
                    fr.items.append(Marker("conc_abort", *times))
                continue
            flush()
            record = None
            if rest.startswith("[GC") or rest.startswith("[Full GC"):
                record = (no, m.group("date"), m.group("uptime"), rest)
            continue
        if "GC log file created" in line:
            file_created = True
        if record is not None:
            record = (record[0], record[1], record[2], record[3] + " " + line.strip())
            continue
        # header lines before the first record
        data = {}
        v = _extract_jdk_version(line)
        if v:
            data["jdk_version"], data["jdk_str"] = v
        if line.startswith("CommandLine flags:"):
            mx = _RE_XMX_FLAG.search(line)
            if mx:
                data["xmx_mb"] = int(mx.group(1)) / 1048576.0 if mx.group(1) else size_mb(mx.group(2).upper())
            mr = re.search(r'-XX:G1HeapRegionSize=(\d+)', line)
            if mr:
                data["region_mb"] = int(mr.group(1)) / 1048576.0
            if not file_created:
                fr.items.append(Marker("jvm_start", None, None, {"collector_line": "CommandLine flags"}))
        if data:
            fr.items.append(Marker("meta", None, None, data))
    flush()


def _legacy_times(date: Optional[str], uptime: Optional[str]) -> Tuple[Optional[float], Optional[float]]:
    return (_parse_iso(date) if date else None), (float(uptime) * 1000 if uptime else None)


def _extract_jdk_version(line: str):
    for pat in _VER_PATTERNS:
        m = pat.search(line)
        if m:
            v = int(m.group("v"))
            if v > 1:
                return v, line.strip()[:120]
    return None


def _parse_legacy_record(fr: FileResult, no: int, date: Optional[str], uptime: Optional[str], text: str):
    abs_ms, uptime_ms = _legacy_times(date, uptime)
    if "secs]" not in text:
        return
    fr.candidates += 1
    cpu = _L_TIMES.search(text)
    body = _L_TIMES.sub("", text)
    body = _L_EMBED_TS.sub("", body)
    body = _L_NOISE.sub("", body)

    pauses = _L_PAUSE.findall(body)
    if not pauses:
        _unparsed(fr, no, text)
        return
    pause_ms = float(pauses[-1]) * 1000

    before = after = total = 0.0
    hm = _L_G1_HEAP.search(body)
    if hm:
        before, after, total = size_mb(hm.group(1)), size_mb(hm.group(3)), size_mb(hm.group(4))
    else:
        triples = _L_TRIPLE.findall(body)
        if triples:
            b, a, t = triples[-1]
            before, after, total = size_mb(b), size_mb(a), size_mb(t)
        else:
            oc = _L_OCCUP.search(body)
            if oc:
                before = after = size_mb(oc.group(1))
                total = size_mb(oc.group(2))

    head = body.lstrip()
    mc = _L_CAUSE.match(head)
    cause = mc.group(1) if mc else ""
    low = body.lower()
    is_full = head.startswith("[Full GC")
    cmf = "concurrent mode failure" in low or "promotion failed" in low
    evac = "to-space exhausted" in low or "to-space overflow" in low
    old_gen = False

    if head.startswith("[GC pause"):
        kind = "Mixed" if "(mixed)" in low else "Young"
        label = f"G1 {kind}" + (" (initial-mark)" if "initial-mark" in low else "")
        old_gen = kind == "Mixed"
    elif head.startswith("[GC remark"):
        label, cause = "G1 Remark", ""
    elif head.startswith("[GC cleanup"):
        label, cause = "G1 Cleanup", ""
    elif "CMS Initial Mark" in head:
        label, cause = "CMS Initial Mark", ""
    elif "CMS Final Remark" in head:
        label, cause = "CMS Final Remark", ""
    elif "ParNew" in body:
        label = "ParNew (promotion failed)" if "promotion failed" in low else "ParNew"
        if cmf:
            is_full = True
    elif is_full:
        if "concurrent mode failure" in low:
            label = "Full GC (concurrent mode failure)"
        elif "[CMS" in body:
            label = "Full GC (CMS)"
        elif "PSYoungGen" in body or "ParOldGen" in body or "PSOldGen" in body:
            label = "Full GC (Parallel)"
        elif "Tenured" in body:
            label = "Full GC (Serial)"
        else:
            label = "Full GC"
    elif "PSYoungGen" in body:
        label = "Parallel Young"
    elif "DefNew" in body:
        label = "Serial Young"
    else:
        label = "GC"
    old_gen = old_gen or is_full

    fr.items.append(GCEvent(
        abs_ms=abs_ms, uptime_ms=uptime_ms, gc_type=label, cause=cause, pause_ms=pause_ms,
        is_full=is_full, old_gen=old_gen, heap_before_mb=before, heap_after_mb=after, heap_total_mb=total,
        evac_failure=evac, cmf=cmf,
        cpu_user_s=float(cpu.group("user")) if cpu else 0.0,
        cpu_real_s=float(cpu.group("real")) if cpu else 0.0,
        src=f"{os.path.basename(fr.path)}:{no}"))
    fr.parsed += 1


# ── Merging files and splitting JVM runs ──────────────────────────────────────

def build_runs(results: List[FileResult]) -> Tuple[List[Run], List[str]]:
    warnings = []
    usable = [r for r in results if r.items]
    have_abs = all(r.first_time()[0] is not None for r in usable)
    if have_abs:
        usable.sort(key=lambda r: r.first_time()[0])
    elif len(usable) > 1:
        usable.sort(key=lambda r: (r.first_time()[1] if r.first_time()[1] is not None else 0))
        warnings.append("The files have no wall-clock timestamps: they are ordered by JVM uptime, "
                        "which is ambiguous when they span several JVM runs.")

    runs: List[Run] = []
    current = Run(index=1)
    last_uptime = None
    pending_meta: dict = {}

    def new_run(has_start: bool):
        nonlocal current, last_uptime
        if current.events or current.stalls:
            runs.append(current)
            current = Run(index=len(runs) + 1)
        current.has_start = current.has_start or has_start
        last_uptime = None

    for fr in usable:
        if fr.path not in current.files:
            current.files.append(fr.path)
        for it in fr.items:
            if isinstance(it, Marker):
                if it.kind == "jvm_start":
                    new_run(True)
                    current.files.append(fr.path) if fr.path not in current.files else None
                    current.meta.update(pending_meta)
                    pending_meta = {}
                elif it.kind == "meta":
                    current.meta.update(it.data)
                elif it.kind == "stall":
                    current.stalls.append(it)
                elif it.kind == "humongous":
                    current.humongous_max = max(current.humongous_max, it.data["regions"])
                elif it.kind == "conc_cycle":
                    current.conc_cycles += 1
                elif it.kind == "conc_abort":
                    current.conc_aborts += 1
                elif it.kind == "to_space":
                    current.to_space_ids.add(it.data["gc_id"])
                elif it.kind == "zgc_live":
                    current.zgc_live.setdefault(it.data["gc_id"], {})[it.data["gen"]] = it.data["mb"]
                continue
            # an uptime going backwards is a JVM restart even without header (rotated header lost)
            if it.uptime_ms is not None and last_uptime is not None and it.uptime_ms + 1000 < last_uptime:
                new_run(False)
                current.files.append(fr.path)
            if it.uptime_ms is not None:
                last_uptime = it.uptime_ms
            current.events.append(it)
    if current.events or current.stalls:
        runs.append(current)

    collectors = {r.collector for r in usable if r.collector != UNKNOWN}
    for run in runs:
        run.meta.setdefault("collector", sorted(collectors)[0] if len(collectors) == 1 else
                            next((r.collector for r in usable if r.path in run.files and r.collector != UNKNOWN), UNKNOWN))
        _compute_relative_times(run)
    return runs, warnings


def _compute_relative_times(run: Run):
    evs = run.events
    if not evs:
        return
    if all(e.uptime_ms is not None for e in evs):
        base = evs[0].uptime_ms
        for e in evs:
            e.t_ms = e.uptime_ms - base
    elif all(e.abs_ms is not None for e in evs):
        base = evs[0].abs_ms
        for e in evs:
            e.t_ms = e.abs_ms - base
    else:
        run.meta["no_time"] = True


# ── Analysis of one run ───────────────────────────────────────────────────────

def analyze_run(run: Run, coverage: dict) -> dict:
    col = run.meta.get("collector", UNKNOWN)
    evs = run.events
    pause_events = [e for e in evs if e.pause_ms > 0]
    stats: dict = {
        "run": run.index,
        "collector": col,
        "jdk_version": run.meta.get("jdk_version", 0),
        "jdk_version_str": run.meta.get("jdk_str", ""),
        "xmx_mb": round(run.meta["xmx_mb"], 1) if run.meta.get("xmx_mb") else None,
        "region_mb": run.meta.get("region_mb"),
        "starts_at_jvm_start": run.has_start,
        "files": [os.path.basename(f) for f in run.files],
        "total_events": len(evs),
        "pause_events": len(pause_events),
        "coverage": coverage,
    }
    if not evs:
        stats["error"] = "No GC events found in this run"
        return stats

    first, last = evs[0], evs[-1]
    stats["start"] = _fmt_abs(first.abs_ms)
    stats["end"] = _fmt_abs(last.abs_ms)
    span_ms = (last.t_ms + last.pause_ms - first.t_ms) if not run.meta.get("no_time") else 0
    stats["time_span_sec"] = round(span_ms / 1000, 1)

    pauses = sorted(e.pause_ms for e in pause_events)
    total_pause = sum(pauses)
    full = [e for e in pause_events if e.is_full]
    stats["full_gc_count"] = len(full)
    stats["full_gc_causes"] = dict(sorted(_count(e.cause or e.gc_type for e in full).items(), key=lambda x: -x[1]))
    stats["throughput_pct"] = (round(max(0.0, 100 * (1 - total_pause / span_ms)), 2)
                               if span_ms >= MIN_THROUGHPUT_SEC * 1000 else None)
    if pauses:
        stats["pause_ms"] = {
            "min": round(pauses[0], 2), "median": round(statistics.median(pauses), 2),
            "mean": round(statistics.mean(pauses), 2), "p95": round(_percentile(pauses, 0.95), 2),
            "p99": round(_percentile(pauses, 0.99), 2), "max": round(pauses[-1], 2),
            "total_sec": round(total_pause / 1000, 2),
        }
        stats["full_gc_pause_ms"] = {
            "max": round(max((e.pause_ms for e in full), default=0), 2),
            "mean": round(statistics.mean([e.pause_ms for e in full]), 2) if full else 0,
        }
    buckets = {"<10": 0, "10-50": 0, "50-200": 0, "200-500": 0, ">500": 0}
    for p in pauses:
        k = "<10" if p < 10 else "10-50" if p < 50 else "50-200" if p < 200 else "200-500" if p < 500 else ">500"
        buckets[k] += 1
    stats["pause_distribution"] = buckets

    type_map: Dict[str, list] = defaultdict(list)
    for e in evs:
        type_map[e.gc_type].append(e.pause_ms if e.pause_ms else e.duration_ms)
    stats["gc_type_breakdown"] = {
        k: {"count": len(v), "mean_ms": round(statistics.mean(v), 2), "max_ms": round(max(v), 2),
            "concurrent": all(e.is_concurrent for e in evs if e.gc_type == k)}
        for k, v in sorted(type_map.items(), key=lambda x: -len(x[1]))
    }
    stats["gc_causes"] = dict(sorted(_count(e.cause for e in evs if e.cause).items(), key=lambda x: -x[1]))

    # heap
    with_heap = [e for e in evs if e.heap_after_mb > 0 or e.heap_before_mb > 0]
    heap: dict = {}
    if with_heap:
        heap["max_before"] = round(max(e.heap_before_mb for e in with_heap), 1)
        heap["max_after"] = round(max(e.heap_after_mb for e in with_heap), 1)
        heap["min_after"] = round(min(e.heap_after_mb for e in with_heap if e.heap_after_mb > 0) if
                                  any(e.heap_after_mb > 0 for e in with_heap) else 0, 1)
        heap["max_committed"] = round(max((e.heap_total_mb for e in with_heap), default=0), 1)
        old = [e for e in with_heap if e.old_gen and e.heap_after_mb > 0]
        # ZGC reports the live size itself; its heap "after" includes what was allocated during the cycle
        zl = [v.get("") if "" in v else v["O"] + v.get("Y", 0) for v in run.zgc_live.values() if "" in v or "O" in v]
        if zl:
            zl = sorted(zl)
            heap["live_set"] = round(statistics.median(zl), 1)
            heap["live_set_max"] = round(zl[-1], 1)
            heap["live_set_method"] = f"median live size reported by ZGC over {len(zl)} {'major ' if col == ZGC_GEN else ''}collections"
            if stats["xmx_mb"]:
                heap["live_set_pct_of_xmx"] = round(100 * heap["live_set"] / stats["xmx_mb"], 1)
        elif old:
            afters = sorted(e.heap_after_mb for e in old)
            heap["live_set"] = round(statistics.median(afters), 1)
            heap["live_set_max"] = round(afters[-1], 1)
            heap["live_set_method"] = f"median heap after {len(old)} old-generation collections (Full / Mixed / Major)"
            if stats["xmx_mb"]:
                heap["live_set_pct_of_xmx"] = round(100 * heap["live_set"] / stats["xmx_mb"], 1)
        else:
            # no old-generation collection: the live set is only bounded by the post-GC floor
            # (median of the per-window lowest heap after GC over the second half of the run)
            half = [e for e in with_heap if e.heap_after_mb > 0 and e.t_ms >= (first.t_ms + last.t_ms) / 2]
            floors = []
            if half:
                t0, t1 = half[0].t_ms, half[-1].t_ms
                w = max(1.0, (t1 - t0) / 6)
                for i in range(6):
                    vals = [e.heap_after_mb for e in half if t0 + i * w <= e.t_ms < t0 + (i + 1) * w + (1 if i == 5 else 0)]
                    if vals:
                        floors.append(min(vals))
            heap["live_set"] = None
            heap["post_gc_floor"] = round(statistics.median(floors), 1) if floors else heap["min_after"]
            heap["live_set_method"] = (f"not measured: no old-generation collection in the log, "
                                       f"the live set is below the post-GC floor of {heap['post_gc_floor']}M")
    stats["heap_mb"] = heap

    # allocation rate: heap growth between consecutive collections
    seq = [e for e in with_heap if e.heap_before_mb > 0]
    if len(seq) >= 2 and span_ms >= 10000:
        alloc = sum(max(0.0, seq[i].heap_before_mb - seq[i - 1].heap_after_mb) for i in range(1, len(seq)))
        stats["allocation_rate_mb_s"] = round(alloc / (span_ms / 1000), 1)
    else:
        stats["allocation_rate_mb_s"] = None

    # trends: per-window minimum of the heap after GC (the floor), only on long enough runs
    stats["heap_trend_mb_per_hour"] = None
    stats["pause_trend_ms_per_hour"] = None
    if span_ms >= MIN_TREND_MINUTES * 60000 and with_heap:
        windows = 12
        w = span_ms / windows
        floors = []
        for i in range(windows):
            vals = [e.heap_after_mb for e in with_heap if i * w <= e.t_ms - first.t_ms < (i + 1) * w and e.heap_after_mb > 0]
            if vals:
                floors.append(((i + 0.5) * w / 3600000, min(vals)))
        if len(floors) >= 6:
            stats["heap_trend_mb_per_hour"] = round(_linreg_slope([f[0] for f in floors], [f[1] for f in floors]), 1)
            stats["heap_floor_first_last_mb"] = [round(floors[0][1], 1), round(floors[-1][1], 1)]
        p95s = []
        for i in range(windows):
            vals = sorted(e.pause_ms for e in pause_events if i * w <= e.t_ms - first.t_ms < (i + 1) * w)
            if vals:
                p95s.append(((i + 0.5) * w / 3600000, _percentile(vals, 0.95)))
        if len(p95s) >= 6:
            stats["pause_trend_ms_per_hour"] = round(_linreg_slope([p[0] for p in p95s], [p[1] for p in p95s]), 1)

    # extra findings, counted once per GC
    stats["evacuation_failure_count"] = len({(e.gc_id, e.src) if e.gc_id is None else e.gc_id
                                             for e in evs if e.evac_failure} | run.to_space_ids)
    stats["concurrent_mode_failure_count"] = sum(1 for e in evs if e.cmf)
    stats["degenerated_gc_count"] = sum(1 for e in evs if e.degenerated)
    stats["sys_gc_count"] = sum(1 for e in evs if "System.gc" in e.cause)
    stats["sys_gc_full_count"] = sum(1 for e in full if "System.gc" in e.cause)
    stats["meta_gc_threshold_count"] = sum(1 for e in evs if "Metadata GC" in e.cause)
    stats["meta_gc_full_count"] = sum(1 for e in full if "Metadata GC" in e.cause)
    stats["humongous_max_regions"] = run.humongous_max
    stats["humongous_triggered_count"] = sum(1 for e in evs if "Humongous" in e.cause)
    stats["concurrent_mark_cycles"] = run.conc_cycles
    stats["concurrent_mark_aborts"] = run.conc_aborts
    alloc_stalls = [s.data["ms"] for s in run.stalls if s.data["kind"] == "Allocation"]
    stats["allocation_stalls"] = {"count": len(alloc_stalls), "total_ms": round(sum(alloc_stalls), 1),
                                  "max_ms": round(max(alloc_stalls), 2) if alloc_stalls else 0}
    cpu = [e for e in pause_events if e.cpu_real_s > 0 and e.cpu_user_s > 0]
    stats["cpu_parallelism"] = round(statistics.mean(e.cpu_user_s / e.cpu_real_s for e in cpu), 1) if cpu else None

    score, label = health_score(stats)
    stats["health_score"] = score
    stats["health_label"] = label
    stats["recommendations"] = recommendations(stats)
    return stats


def _count(values) -> Dict[str, int]:
    c: Dict[str, int] = defaultdict(int)
    for v in values:
        c[v] += 1
    return dict(c)


def _fmt_abs(abs_ms: Optional[float]) -> Optional[str]:
    if abs_ms is None:
        return None
    return datetime.fromtimestamp(abs_ms / 1000).strftime("%Y-%m-%d %H:%M:%S")


def _concurrent_collector(col: str) -> bool:
    return col in (G1GC, CMS, ZGC, ZGC_GEN, SHENANDOAH)


def health_score(stats: dict) -> Tuple[Optional[int], str]:
    cov = stats.get("coverage", {})
    if cov.get("ratio", 1) < 0.8:
        return None, "not scored: too many unparsed GC lines"
    if not stats.get("pause_events") and not stats.get("total_events"):
        return None, "not scored"
    score = 100
    col = stats["collector"]
    if _concurrent_collector(col):
        score -= min(40, stats.get("full_gc_count", 0) * 10)
    score -= min(20, stats.get("evacuation_failure_count", 0) * 2)
    score -= min(25, stats.get("concurrent_mode_failure_count", 0) * 5)
    score -= min(20, stats.get("degenerated_gc_count", 0) * 5)
    if stats["allocation_stalls"]["count"]:
        score -= 15
    thru = stats.get("throughput_pct")
    if thru is not None:
        score -= 20 if thru < 90 else 10 if thru < 95 else 0
    p99 = stats.get("pause_ms", {}).get("p99", 0)
    score -= 15 if p99 > 500 else 8 if p99 > 200 else 0
    live_pct = stats.get("heap_mb", {}).get("live_set_pct_of_xmx")
    if live_pct is not None:
        score -= 10 if live_pct > 70 else 5 if live_pct > 50 else 0
    if _leak_suspected(stats):
        score -= 15
    score = max(0, min(100, score))
    label = ("Excellent" if score >= 90 else "Good" if score >= 80 else "Needs Attention" if score >= 60
             else "Degraded" if score >= 40 else "Critical")
    return score, label


def _leak_suspected(stats: dict) -> bool:
    trend = stats.get("heap_trend_mb_per_hour")
    if trend is None or trend <= 0:
        return False
    hours = stats["time_span_sec"] / 3600
    growth = trend * hours
    ref = stats.get("xmx_mb") or stats.get("heap_mb", {}).get("max_committed") or 0
    return ref > 0 and growth > 0.2 * ref


# ── Recommendations (only when backed by a finding) ───────────────────────────

def recommendations(stats: dict) -> List[dict]:
    recs: List[dict] = []

    def add(sev, text, flag=None):
        recs.append({"severity": sev, "text": text, **({"flag": flag} if flag else {})})

    col = stats["collector"]
    jdk = stats.get("jdk_version") or 0
    heap = stats.get("heap_mb", {})
    p = stats.get("pause_ms", {})
    xmx = stats.get("xmx_mb")

    # collector
    if col == CMS:
        if jdk >= 14:
            add("CRITICAL", "CMS was removed in JDK 14: verify which collector is really active.")
        else:
            add("MEDIUM", "CMS is deprecated (removed in JDK 14) and fragments the old generation over time. "
                          "Move to G1 with Kafka's settings.", KAFKA_G1_DEFAULTS)
    if col == SERIAL:
        add("HIGH", "SerialGC is single-threaded, only suitable for very small heaps. Use G1 for Kafka components.",
            KAFKA_G1_DEFAULTS)
    if col == PARALLEL and (p.get("max", 0) > 200):
        add("MEDIUM", f"ParallelGC pauses reach {p['max']}ms (every old-generation collection is a stop-the-world "
                      "Full GC). Kafka components run G1 by default.", KAFKA_G1_DEFAULTS)
    if jdk and jdk < 17:
        add("INFO", f"JDK {jdk}: Kafka 4.x / Confluent Platform 8.x brokers, Connect and tools require Java 17 or later.")

    # Full GC on a concurrent collector = fallback
    fgc = stats.get("full_gc_count", 0)
    if fgc and _concurrent_collector(col):
        causes = ", ".join(f"{k} ×{v}" for k, v in stats.get("full_gc_causes", {}).items())
        sev = "CRITICAL" if stats.get("full_gc_pause_ms", {}).get("max", 0) > 1000 or fgc >= 10 else "HIGH"
        add(sev, f"{fgc} Full GC(s) with {col} (max {stats['full_gc_pause_ms']['max']}ms; causes: {causes}). "
                 "A concurrent collector falling back to a Full GC means the old generation filled up before the "
                 "concurrent cycle could reclaim it: heap too small for the live set, a leak, or explicit System.gc().")

    # G1 evacuation failure / to-space exhausted
    ef = stats.get("evacuation_failure_count", 0)
    if ef:
        add("HIGH" if ef < 10 else "CRITICAL",
            f"{ef} evacuation failure(s) / to-space exhausted: G1 had no free region to copy live objects to. "
            "Give the heap more headroom (raise -Xmx), keep more free regions in reserve (raise G1ReservePercent, "
            "default 10), and check the humongous allocations below.",
            "-XX:G1ReservePercent=20")

    # CMS concurrent mode failure / promotion failed
    cmf = stats.get("concurrent_mode_failure_count", 0)
    if cmf:
        add("CRITICAL" if cmf >= 5 else "HIGH",
            f"{cmf} CMS concurrent mode failure(s) / promotion failure(s): the old generation filled before CMS "
            "finished, each one is a long stop-the-world Full GC. Start CMS earlier and give it a fixed threshold, "
            "add heap, or move to G1.",
            "-XX:CMSInitiatingOccupancyFraction=70 -XX:+UseCMSInitiatingOccupancyOnly")

    # Shenandoah / ZGC fallbacks
    if stats.get("degenerated_gc_count"):
        add("HIGH", f"{stats['degenerated_gc_count']} Shenandoah degenerated GC(s): the concurrent cycle could not "
                    "keep up with allocation and fell back to a stop-the-world pause. Raise -Xmx or start cycles earlier.")
    stalls = stats.get("allocation_stalls", {})
    if stalls.get("count"):
        add("HIGH", f"{stalls['count']} ZGC allocation stall(s), {stalls['total_ms']}ms in total (max {stalls['max_ms']}ms): "
                    "application threads waited for memory because ZGC could not reclaim it fast enough. Raise -Xmx "
                    "(ZGC needs headroom above the live set) or reduce the allocation rate.")

    # explicit System.gc()
    if stats.get("sys_gc_full_count"):
        add("HIGH", f"{stats['sys_gc_full_count']} Full GC(s) triggered by System.gc(). Kafka sets "
                    "-XX:+ExplicitGCInvokesConcurrent so that System.gc() runs a concurrent cycle instead: check that "
                    "KAFKA_JVM_PERFORMANCE_OPTS was not overridden. Find the caller (thread dump, JFR) before "
                    "considering -XX:+DisableExplicitGC, which can delay the release of direct buffers.",
            "-XX:+ExplicitGCInvokesConcurrent")

    # humongous allocations
    hum_trig = stats.get("humongous_triggered_count", 0)
    region = stats.get("region_mb")
    if col == G1GC and (hum_trig >= 10 or (stats.get("humongous_max_regions") and xmx and region and
                                           stats["humongous_max_regions"] * region > 0.1 * xmx)):
        text = (f"Humongous allocations: {hum_trig} GC(s) triggered by G1 Humongous Allocation, up to "
                f"{stats.get('humongous_max_regions', 0)} humongous regions. Objects of half a region or more "
                f"(region size {region:g}M) go straight to the old generation. " if region else
                f"Humongous allocations: {hum_trig} GC(s) triggered by G1 Humongous Allocation. ")
        text += "With Kafka this usually means large batches or records (max.request.size, fetch sizes, message.max.bytes)."
        flag = None
        if region and region < 32:
            text += (" A region must be at least twice the size of the large objects to keep them out of the "
                     "humongous path (32m maximum before JDK 18).")
            flag = "-XX:G1HeapRegionSize=16m (or 32m: 2x the largest batch / record)"
        add("MEDIUM", text, flag)

    # Metaspace
    if stats.get("meta_gc_full_count") or stats.get("meta_gc_threshold_count", 0) > 3:
        add("MEDIUM", f"{stats['meta_gc_threshold_count']} GC(s) triggered by Metadata GC Threshold "
                      f"({stats.get('meta_gc_full_count', 0)} Full GC). Metaspace keeps growing past its high-water "
                      "mark, typical of Connect workers loading many plugins: start with a larger threshold. Avoid "
                      "capping it with MaxMetaspaceSize, which turns this into an OutOfMemoryError.",
            "-XX:MetaspaceSize=256m")

    # pauses
    p99 = p.get("p99", 0)
    if p99 > 500:
        add("HIGH", f"p99 pause {p99}ms (max {p.get('max')}ms): long enough to expire broker sessions and "
                    "consumer heartbeats. Look at the Full GC / evacuation failure findings above and at the heap "
                    "sizing first; on JDK 21 Generational ZGC is an option for very large heaps.")
    elif p99 > 200 and col == G1GC:
        add("MEDIUM", f"p99 pause {p99}ms, well above the 20ms G1 target Kafka sets (MaxGCPauseMillis=20). "
                      "Check the heap sizing and the young GC pause breakdown.")

    # throughput
    thru = stats.get("throughput_pct")
    if thru is not None and thru < 95:
        add("HIGH" if thru < 90 else "MEDIUM",
            f"GC throughput {thru}%: {100 - thru:.1f}% of the wall-clock time is spent in GC pauses. "
            "The heap is too small for the allocation rate or the live set.")

    # live set
    live_pct = heap.get("live_set_pct_of_xmx")
    if live_pct is not None and live_pct > 50:
        target = int(math.ceil(heap["live_set"] * 2.5 / 256.0) * 256)
        add("HIGH" if live_pct > 70 else "MEDIUM",
            f"Live set ~{heap['live_set']}M = {live_pct}% of -Xmx ({xmx:g}M). Keep the live set under half of the heap "
            "so the collector has room to work.", f"-Xms{target}m -Xmx{target}m")

    # leak
    if _leak_suspected(stats):
        f0, f1 = stats.get("heap_floor_first_last_mb", [0, 0])
        add("HIGH", f"The heap floor after GC grows by {stats['heap_trend_mb_per_hour']}MB/hour over "
                    f"{stats['time_span_sec'] / 60:.0f} minutes ({f0}M -> {f1}M): possible memory leak. Take two heap "
                    "dumps some time apart and compare them: playground debug heap-dump, then "
                    "playground debug heap-analyze --file <first> --compare <second>.")
    pt = stats.get("pause_trend_ms_per_hour")
    if pt is not None and pt * stats["time_span_sec"] / 3600 > 100:
        add("MEDIUM", f"p95 pause grows by {pt}ms/hour over the run: pauses get longer as the run goes on.")

    if not recs or all(r["severity"] == "INFO" for r in recs):
        add("OK", "No GC problem found in this run.")
    order = {s: i for i, s in enumerate(SEVERITIES)}
    recs.sort(key=lambda r: order.get(r["severity"], 9))
    return recs


# ── Text report ───────────────────────────────────────────────────────────────

def text_report(stats: dict, runs_summary: List[dict], warnings: List[str], top: List[GCEvent]) -> str:
    W = 76

    def hdr(title):
        return f"── {title} " + "─" * max(0, W - len(title) - 4)

    cov = stats["coverage"]
    jdk = stats.get("jdk_version")
    lines = ["=" * W, "  JVM GC Log Analysis", "=" * W]
    lines.append(f"  Files          : {cov['files']} ({cov['lines']:,} lines, format {', '.join(cov['formats'])})")
    lines.append(f"  Coverage       : {cov['parsed']:,} GC records parsed out of {cov['candidates']:,} candidate lines"
                 + (f", {cov['candidates'] - cov['parsed']} unparsed" if cov['candidates'] > cov['parsed'] else ""))
    for ex in cov.get("unparsed_examples", [])[:3]:
        lines.append(f"                   unparsed: {ex}")
    for w in warnings:
        lines.append(f"  ⚠️  {w}")
    if len(runs_summary) > 1:
        lines += ["", hdr(f"JVM runs ({len(runs_summary)})")]
        for r in runs_summary:
            mark = "  ◀ analyzed" if r["run"] == stats["run"] else ""
            lines.append(f"  #{r['run']:<3} {r['start'] or '?':<19}  {r['span']:>8}  {r['pauses']:>6} pauses  "
                         f"{r['full']:>3} Full GC  max {r['max_pause']}ms{mark}")
    lines += ["", hdr(f"Run #{stats['run']}")]
    lines.append(f"  JDK / collector: {('JDK ' + str(jdk)) if jdk else 'JDK ?'}"
                 f"{(' (' + stats['jdk_version_str'] + ')') if stats.get('jdk_version_str') else ''} / {stats['collector']}")
    lines.append(f"  Heap (-Xmx)    : {str(stats['xmx_mb']) + 'M' if stats['xmx_mb'] else 'unknown (no JVM start header in the log)'}"
                 + (f", region size {stats['region_mb']:g}M" if stats.get("region_mb") else ""))
    if stats.get("start"):
        lines.append(f"  Time           : {stats['start']} -> {stats['end']} ({stats['time_span_sec']}s)")
    else:
        lines.append(f"  Time span      : {stats['time_span_sec']}s")
    hs = stats.get("health_score")
    lines.append(f"  Health score   : {str(hs) + '/100' if hs is not None else '-'}  ({stats.get('health_label')})")

    lines += ["", hdr("Summary")]
    lines.append(f"  GC events          : {stats['total_events']} (pauses={stats['pause_events']}, full={stats['full_gc_count']})")
    thru = stats.get("throughput_pct")
    lines.append(f"  GC throughput      : {str(thru) + '%' if thru is not None else f'- (needs ≥ {MIN_THROUGHPUT_SEC}s of log)'}")
    for key, label in (("evacuation_failure_count", "Evacuation failures"), ("concurrent_mode_failure_count", "CMS mode failures"),
                       ("degenerated_gc_count", "Degenerated GCs"), ("sys_gc_count", "System.gc() GCs"),
                       ("humongous_triggered_count", "Humongous-triggered"), ("concurrent_mark_cycles", "Concurrent cycles"),
                       ("concurrent_mark_aborts", "Conc. mark aborts")):
        if stats.get(key):
            lines.append(f"  {label:<19}: {stats[key]}")
    st = stats["allocation_stalls"]
    if st["count"]:
        lines.append(f"  Allocation stalls  : {st['count']} (total {st['total_ms']}ms, max {st['max_ms']}ms)")

    p = stats.get("pause_ms")
    if p:
        lines += ["", hdr("Pause Times (ms)"),
                  f"  Min / Median / Mean : {p['min']} / {p['median']} / {p['mean']}",
                  f"  p95 / p99 / Max     : {p['p95']} / {p['p99']} / {p['max']}",
                  f"  Total pause time    : {p['total_sec']}s"]
        lines += ["", hdr("Pause Distribution")]
        mx = max(stats["pause_distribution"].values()) or 1
        for bucket, count in stats["pause_distribution"].items():
            lines.append(f"  {bucket:>8}ms : {'█' * int(round(40 * count / mx)):<40} {count}")

    h = stats.get("heap_mb")
    if h:
        lines += ["", hdr("Heap (MB)")]
        if h.get("live_set") is not None:
            lines.append(f"  Live set           : {h['live_set']}M ({h['live_set_method']})"
                         + (f", {h['live_set_pct_of_xmx']}% of -Xmx" if h.get("live_set_pct_of_xmx") is not None else ""))
        else:
            lines.append(f"  Live set           : {h['live_set_method']}")
        lines.append(f"  Heap after GC      : min {h['min_after']}M / max {h['max_after']}M, before GC max {h['max_before']}M")
        if h.get("max_committed"):
            lines.append(f"  Max committed      : {h['max_committed']}M")
    if stats.get("allocation_rate_mb_s"):
        lines.append(f"  Allocation rate    : {stats['allocation_rate_mb_s']}MB/s")
    if stats.get("heap_trend_mb_per_hour") is not None:
        lines.append(f"  Heap floor trend   : {stats['heap_trend_mb_per_hour']}MB/hour")
    else:
        lines.append(f"  Heap floor trend   : - (needs ≥ {MIN_TREND_MINUTES} min of log)")

    causes = stats.get("gc_causes", {})
    if causes:
        lines += ["", hdr("GC Causes")]
        for cause, cnt in list(causes.items())[:12]:
            lines.append(f"  {cause[:52]:<54} {cnt}")

    lines += ["", hdr("GC Type Breakdown")]
    for gtype, info in stats["gc_type_breakdown"].items():
        kind = "duration" if info["concurrent"] else "pause"
        lines.append(f"  {gtype[:46]:<48} count={info['count']:<6} avg {kind}={info['mean_ms']}ms  max={info['max_ms']}ms")

    if top:
        lines += ["", hdr(f"Top {len(top)} longest pauses")]
        for e in top:
            heap_s = f"  {e.heap_before_mb:.0f}M->{e.heap_after_mb:.0f}M" if e.heap_before_mb else ""
            when = _fmt_abs(e.abs_ms) or (f"{e.uptime_ms / 1000:.3f}s" if e.uptime_ms is not None else "")
            lines.append(f"  {e.pause_ms:>9.2f}ms  {e.gc_type[:34]:<34} {(e.cause or '')[:24]:<24}{heap_s}  {when}  {e.src}")

    lines += ["", hdr("Recommendations")]
    for r in stats["recommendations"]:
        lines.append(f"  [{r['severity']}] {r['text']}")
        if r.get("flag"):
            lines.append(f"      👉 {r['flag']}")
    lines.append("=" * W)
    return "\n".join(lines)


# ── HTML report (inline SVG charts, no external resource) ─────────────────────

def _e(s) -> str:
    return _html.escape(str(s), quote=True)


def _nice_ticks(lo: float, hi: float, n: int = 5) -> List[float]:
    if hi <= lo:
        hi = lo + 1
    raw = (hi - lo) / n
    mag = 10 ** math.floor(math.log10(raw))
    step = next(m * mag for m in (1, 2, 2.5, 5, 10) if m * mag >= raw)
    start = math.floor(lo / step) * step
    ticks, v = [start], start
    while v < hi - step * 1e-9:
        v += step
        ticks.append(round(v, 10))
    return ticks


def _svg_frame(xmax: float, ymax: float, xlabel: str, ylabel: str, W=560, H=270, L=56, B=36, T=26, R=14):
    xt, yt = _nice_ticks(0, xmax), _nice_ticks(0, ymax)
    xmax, ymax = xt[-1] or 1, yt[-1] or 1
    pw, ph = W - L - R, H - T - B
    sx = lambda x: L + pw * x / xmax
    sy = lambda y: T + ph * (1 - y / ymax)
    out = [f'<svg viewBox="0 0 {W} {H}" xmlns="http://www.w3.org/2000/svg">']
    for y in yt:
        out.append(f'<line x1="{L}" y1="{sy(y):.1f}" x2="{W - R}" y2="{sy(y):.1f}" stroke="#e2e8f0"/>'
                   f'<text x="{L - 6}" y="{sy(y) + 4:.1f}" font-size="10" text-anchor="end" fill="#64748b">{y:g}</text>')
    for x in xt:
        out.append(f'<text x="{sx(x):.1f}" y="{H - B + 14}" font-size="10" text-anchor="middle" fill="#64748b">{x:g}</text>')
    out.append(f'<line x1="{L}" y1="{T + ph}" x2="{W - R}" y2="{T + ph}" stroke="#94a3b8"/>')
    out.append(f'<text x="{L + pw / 2}" y="{H - 4}" font-size="11" text-anchor="middle" fill="#475569">{_e(xlabel)}</text>')
    out.append(f'<text x="12" y="{T + ph / 2}" font-size="11" text-anchor="middle" fill="#475569" '
               f'transform="rotate(-90 12 {T + ph / 2})">{_e(ylabel)}</text>')
    return out, sx, sy


def _sample(points: list, limit: int, keep_key=None) -> list:
    if len(points) <= limit:
        return points
    step = len(points) / limit
    sampled = [points[int(i * step)] for i in range(limit)]
    if keep_key:
        sampled += sorted(points, key=keep_key, reverse=True)[: limit // 20]
    return sampled


def svg_pause_timeline(events: List[GCEvent], x_unit: float, x_label: str) -> str:
    pts = [(e.t_ms / x_unit, e.pause_ms, e.is_full or e.cmf or e.evac_failure) for e in events if e.pause_ms > 0]
    if not pts:
        return "<p>No pause.</p>"
    pts = _sample(pts, 3000, keep_key=lambda p: p[1])
    out, sx, sy = _svg_frame(max(p[0] for p in pts), max(p[1] for p in pts), x_label, "pause (ms)")
    for x, y, bad in pts:
        if not bad:
            out.append(f'<circle cx="{sx(x):.1f}" cy="{sy(y):.1f}" r="2" fill="#3b82f6" fill-opacity=".55"/>')
    for x, y, bad in pts:
        if bad:
            out.append(f'<circle cx="{sx(x):.1f}" cy="{sy(y):.1f}" r="3.5" fill="#dc2626"/>')
    out.append('<text x="60" y="12" font-size="10" fill="#3b82f6">● pause</text>'
               '<text x="115" y="12" font-size="10" fill="#dc2626">● Full GC / evacuation or mode failure</text></svg>')
    return "".join(out)


def svg_heap(events: List[GCEvent], x_unit: float, x_label: str, xmx: Optional[float]) -> str:
    pts = [(e.t_ms / x_unit, e.heap_before_mb, e.heap_after_mb) for e in events if e.heap_after_mb > 0]
    if not pts:
        return "<p>No heap figure in this log.</p>"
    pts = _sample(pts, 1500)
    ymax = max(max(p[1] for p in pts), xmx or 0)
    out, sx, sy = _svg_frame(max(p[0] for p in pts), ymax, x_label, "heap (MB)")
    for idx, color in ((1, "#f97316"), (2, "#16a34a")):
        path = " ".join(f"{'M' if i == 0 else 'L'}{sx(p[0]):.1f},{sy(p[idx]):.1f}" for i, p in enumerate(pts) if p[idx] > 0)
        out.append(f'<path d="{path}" fill="none" stroke="{color}" stroke-width="1.2" stroke-opacity=".85"/>')
    if xmx:
        out.append(f'<line x1="{sx(0):.1f}" y1="{sy(xmx):.1f}" x2="{sx(pts[-1][0]):.1f}" y2="{sy(xmx):.1f}" '
                   f'stroke="#dc2626" stroke-dasharray="4 3"/>')
    out.append('<text x="60" y="12" font-size="10" fill="#f97316">— before GC</text>'
               '<text x="140" y="12" font-size="10" fill="#16a34a">— after GC</text>'
               + ('<text x="215" y="12" font-size="10" fill="#dc2626">- - -Xmx</text>' if xmx else "") + '</svg>')
    return "".join(out)


def svg_bars(labels: List[str], values: List[float], colors: List[str], ylabel: str) -> str:
    W, H, L, B, T = 560, 290, 56, 60, 14
    ymax = _nice_ticks(0, max(values) if values and max(values) > 0 else 1)[-1]
    out, _, sy = _svg_frame(1, ymax, "", ylabel, W=W, H=H, L=L, B=B, T=T)
    out = [o for o in out if 'text-anchor="middle" fill="#64748b"' not in o]  # no numeric x ticks
    n = max(1, len(values))
    pw = W - L - 14
    bw = pw / n * 0.7
    for i, (lab, v) in enumerate(zip(labels, values)):
        x = L + pw / n * (i + 0.15)
        out.append(f'<rect x="{x:.1f}" y="{sy(v):.1f}" width="{bw:.1f}" height="{max(0, sy(0) - sy(v)):.1f}" '
                   f'fill="{colors[i % len(colors)]}"/>'
                   f'<text x="{x + bw / 2:.1f}" y="{sy(v) - 3:.1f}" font-size="10" text-anchor="middle">{v:g}</text>'
                   f'<text x="{x + bw / 2:.1f}" y="{H - B + 12}" font-size="9" text-anchor="end" fill="#475569" '
                   f'transform="rotate(-25 {x + bw / 2:.1f} {H - B + 12})">{_e(lab.replace("Pause ", "")[:26])}</text>')
    out.append("</svg>")
    return "".join(out)


def html_report(stats: dict, runs_summary: List[dict], warnings: List[str], run: Run, top: List[GCEvent],
                title: str) -> str:
    p = stats.get("pause_ms", {})
    h = stats.get("heap_mb", {})
    span = stats.get("time_span_sec", 0)
    x_unit, x_label = (60000, "minutes since start") if span > 600 else (1000, "seconds since start")
    health = stats.get("health_score")
    hcolor = "#64748b" if health is None else "#16a34a" if health >= 80 else "#d97706" if health >= 60 else "#dc2626"

    def kpi(label, val, unit, cls=""):
        return (f'<div class="kpi-card {cls}"><div class="kpi-label">{_e(label)}</div>'
                f'<div class="kpi-value">{_e(val)}</div><div class="kpi-unit">{_e(unit)}</div></div>')

    thru = stats.get("throughput_pct")
    kpis = "".join([
        kpi("Throughput", thru if thru is not None else "-", "%", "" if thru is None else "danger" if thru < 90 else "warn" if thru < 95 else "ok"),
        kpi("GC pauses", stats.get("pause_events", 0), "events"),
        kpi("Full GC", stats.get("full_gc_count", 0), "events", "danger" if stats.get("full_gc_count") and _concurrent_collector(stats["collector"]) else "ok"),
        kpi("p99 pause", p.get("p99", 0), "ms", "danger" if p.get("p99", 0) > 500 else "warn" if p.get("p99", 0) > 200 else "ok"),
        kpi("Max pause", p.get("max", 0), "ms", "warn" if p.get("max", 0) > 200 else ""),
        kpi("Live set", h.get("live_set") if h.get("live_set") is not None else f"≤{h.get('post_gc_floor', '-')}", f"MB{' of ' + format(stats['xmx_mb'], 'g') + ' MB Xmx' if stats.get('xmx_mb') else ''}"),
    ])

    recs = "".join(
        f'<div class="rec-card {r["severity"].lower()}"><span class="rec-badge {r["severity"].lower()}">{_e(r["severity"])}</span>'
        f'<span class="rec-text">{_e(r["text"])}{("<span class=rec-flag>" + _e(r["flag"]) + "</span>") if r.get("flag") else ""}</span></div>'
        for r in stats["recommendations"])

    cov = stats["coverage"]
    warn_items = list(warnings)
    if cov["candidates"] > cov["parsed"]:
        warn_items.append(f"{cov['candidates'] - cov['parsed']} GC lines could not be parsed, e.g. "
                          + "; ".join(cov.get("unparsed_examples", [])[:2]))
    warn_html = ("<div class='warn-box'>" + "<br>".join(_e(w) for w in warn_items) + "</div>") if warn_items else ""

    runs_html = ""
    if len(runs_summary) > 1:
        rows = "".join(f"<tr{' style=font-weight:700' if r['run'] == stats['run'] else ''}><td>#{r['run']}</td><td>{_e(r['start'] or '?')}</td>"
                       f"<td>{_e(r['span'])}</td><td>{r['pauses']}</td><td>{r['full']}</td><td>{r['max_pause']}</td></tr>"
                       for r in runs_summary)
        runs_html = ("<div class='table-card'><h2>JVM runs (the analyzed one is in bold)</h2><table><tr><th>Run</th><th>Start</th>"
                     "<th>Span</th><th>Pauses</th><th>Full GC</th><th>Max pause (ms)</th></tr>" + rows + "</table></div>")

    dist = stats.get("pause_distribution", {})
    types = list(stats.get("gc_type_breakdown", {}).items())[:8]
    charts = (
        "<div class='charts-grid'>"
        f"<div class='chart-card'><h2>GC pause timeline</h2>{svg_pause_timeline(run.events, x_unit, x_label)}</div>"
        f"<div class='chart-card'><h2>Heap before / after GC</h2>{svg_heap(run.events, x_unit, x_label, stats.get('xmx_mb'))}</div>"
        f"<div class='chart-card'><h2>Pause distribution</h2>{svg_bars([k + 'ms' for k in dist], list(dist.values()), ['#22c55e', '#3b82f6', '#eab308', '#f97316', '#dc2626'], 'pauses')}</div>"
        f"<div class='chart-card'><h2>GC types</h2>{svg_bars([k for k, _ in types], [v['count'] for _, v in types], ['#3b82f6', '#10b981', '#f97316', '#8b5cf6', '#ec4899', '#14b8a6', '#f59e0b', '#6366f1'], 'events')}</div>"
        "</div>")

    top_rows = "".join(
        f"<tr class='{'full-gc-row' if e.is_full else ''}'><td>{_e(_fmt_abs(e.abs_ms) or round(e.t_ms / 1000, 3))}</td>"
        f"<td>{_e(e.gc_type)}</td><td>{_e(e.cause)}</td><td class='{'pause-hi' if e.pause_ms > 500 else ''}'>{e.pause_ms:.2f}</td>"
        f"<td>{e.heap_before_mb:.0f}M -&gt; {e.heap_after_mb:.0f}M</td><td class='flag-cell'>{_e(e.src)}</td></tr>" for e in top)
    top_html = (f"<div class='table-card'><h2>Top {len(top)} longest pauses</h2><table><tr><th>When</th><th>Type</th>"
                f"<th>Cause</th><th>Pause (ms)</th><th>Heap</th><th>Source</th></tr>{top_rows}</table></div>") if top else ""

    causes = stats.get("gc_causes", {})
    causes_html = ("<div class='table-card'><h2>GC causes</h2><table><tr><th>Cause</th><th>Count</th></tr>"
                   + "".join(f"<tr><td>{_e(k)}</td><td>{v}</td></tr>" for k, v in causes.items()) + "</table></div>") if causes else ""

    jdk = stats.get("jdk_version")
    meta = [f"&#128196; {_e(title)}", f"Run #{stats['run']} of {len(runs_summary)}", f"JDK {jdk or '?'}",
            f"Collector: {_e(stats['collector'])}", f"-Xmx: {_e(str(stats['xmx_mb']) + 'M' if stats.get('xmx_mb') else 'unknown')}",
            f"Span: {span}s", f"Coverage: {cov['parsed']}/{cov['candidates']}",
            f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"]
    header = ("<div class='header'><div><h1>JVM GC Log Analysis</h1><div class='header-meta'>"
              + "".join(f"<span>{m}</span>" for m in meta) + "</div></div>"
              f"<div class='health-badge'><div class='health-score' style='color:{hcolor}'>{_e(health if health is not None else '-')}</div>"
              f"<div class='health-label'>health</div><div class='health-name' style='color:{hcolor}'>{_e(stats.get('health_label', ''))}</div></div></div>")

    return ("<!DOCTYPE html><html lang='en'><head><meta charset='UTF-8'>"
            "<meta name='viewport' content='width=device-width,initial-scale=1'>"
            f"<title>GC Report — {_e(title)}</title>{_HTML_CSS}</head><body><div class='page'>"
            + header + warn_html + f"<div class='kpi-grid'>{kpis}</div>" + charts
            + "<div class='section-title'>Recommendations</div>" + f"<div class='recs-list'>{recs}</div>"
            + runs_html + causes_html + top_html
            + "<div class='footer'>Generated by playground debug gc-analyze (self-contained, no external resource)</div>"
            "</div></body></html>")


# ── CLI ───────────────────────────────────────────────────────────────────────

def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="+", help="GC log file(s) or folder(s): rotated files of the same JVM go together")
    ap.add_argument("--json", action="store_true", help="Output JSON stats")
    ap.add_argument("--html", action="store_true", help="Generate HTML report next to the first input")
    ap.add_argument("--html-out", metavar="PATH", help="HTML output path")
    ap.add_argument("--top-pauses", type=int, default=10, metavar="N", help="Top N longest pauses (default: 10)")
    ap.add_argument("--run", type=int, metavar="N", help="JVM run to analyze (default: the latest)")
    args = ap.parse_args()

    files, errors = expand_inputs(args.files)
    for e in errors:
        print(f"❌ {e}", file=sys.stderr)
    if not files:
        return 2

    results = [parse_file(f) for f in files]
    for r in results:
        if r.error:
            print(f"❌ {r.error}", file=sys.stderr)
    runs, warnings = build_runs(results)

    coverage = {
        "files": len(results),
        "lines": sum(r.lines for r in results),
        "formats": sorted({r.log_format for r in results}),
        "candidates": sum(r.candidates for r in results),
        "parsed": sum(r.parsed for r in results),
        "unparsed_examples": [u for r in results for u in r.unparsed][:5],
    }
    coverage["ratio"] = round(coverage["parsed"] / coverage["candidates"], 3) if coverage["candidates"] else 0

    if not runs:
        msg = ("No GC event found in " + ", ".join(os.path.basename(f) for f in files)
               + f" ({coverage['lines']} lines). Is it a GC log? Expected -Xlog:gc* (JDK 9+) or "
                 "-XX:+PrintGCDetails (JDK 8) output.")
        if args.json:
            print(json.dumps({"error": msg, "coverage": coverage}, indent=2))
        else:
            print(f"❌ {msg}", file=sys.stderr)
        return 2

    if args.run is not None and not 1 <= args.run <= len(runs):
        print(f"❌ --run must be between 1 and {len(runs)}", file=sys.stderr)
        return 1
    run = runs[(args.run or len(runs)) - 1]

    runs_summary = []
    for r in runs:
        pz = [e.pause_ms for e in r.events if e.pause_ms > 0]
        span = (r.events[-1].t_ms - r.events[0].t_ms) / 1000 if r.events else 0
        runs_summary.append({
            "run": r.index, "start": _fmt_abs(r.events[0].abs_ms) if r.events else None,
            "span": f"{span:.0f}s" if span < 600 else f"{span / 60:.0f}min",
            "pauses": len(pz), "full": sum(1 for e in r.events if e.is_full and e.pause_ms > 0),
            "max_pause": round(max(pz), 1) if pz else 0, "files": [os.path.basename(f) for f in r.files],
        })

    stats = analyze_run(run, coverage)
    top = sorted((e for e in run.events if e.pause_ms > 0), key=lambda e: e.pause_ms, reverse=True)[:max(0, args.top_pauses)]

    if args.json:
        print(json.dumps({**stats, "runs": runs_summary, "warnings": warnings}, indent=2, default=str))
    else:
        print(text_report(stats, runs_summary, warnings, top))

    if args.html or args.html_out:
        out = args.html_out or (os.path.splitext(files[0])[0] + "-gc-report.html")
        title = os.path.basename(files[0]) + (f" (+{len(files) - 1} files)" if len(files) > 1 else "")
        with open(out, "w", encoding="utf-8") as fh:
            fh.write(html_report(stats, runs_summary, warnings, run, top, title))
        print(f"HTML report: {out}", file=sys.stderr)

    if "error" in stats:
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
