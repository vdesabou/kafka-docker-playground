#!/usr/bin/env python3
"""
JVM GC Log Analyzer — JDK 7 through JDK 21+

Collectors : G1GC · CMS · ParallelGC · SerialGC · ZGC · GenZGC · Shenandoah
Formats    : JDK 7/8 legacy (-XX:+PrintGCDetails)
             JDK 9-10 transitional
             JDK 9+   unified (-Xlog:gc*)
             JDK 21+  generational ZGC
"""

import re
import sys
import os
import argparse
import statistics
import json
import html as _html
from datetime import datetime
from collections import defaultdict
from dataclasses import dataclass
from typing import List, Dict, Tuple

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

# ── Extra-metric regex ────────────────────────────────────────────────────────
_RE_HUMONGOUS   = re.compile(r'Humongous regions:\s*(\d+)->(\d+)')
_RE_EVAC_FAIL   = re.compile(r'Evacuation Failure|to-space exhausted|To-space overflow', re.I)
_RE_META_GC     = re.compile(r'Metadata GC Threshold|Metadata GC Clear', re.I)
_RE_SYS_GC      = re.compile(r'\(System\.gc\(\)\)|\bSystem GC\b', re.I)
_RE_CONC_MARK   = re.compile(r'Concurrent Mark Cycle|Concurrent Marking\b', re.I)
_RE_CAUSE_PARENS = re.compile(r'\(([^)]+)\)')

# ── HTML/CSS template (regular string — braces are literal CSS/JS, not f-string) ──

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
.charts-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(500px,1fr));
             gap:18px;margin-bottom:22px}
.chart-card{background:#fff;border-radius:10px;padding:18px 20px;
            box-shadow:0 1px 3px rgba(0,0,0,.07)}
.chart-container{position:relative;height:255px}
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
.sev{display:inline-block;font-size:.68rem;font-weight:700;text-transform:uppercase;
     padding:2px 8px;border-radius:20px;white-space:nowrap}
.sev.high{background:#ffedd5;color:#ea580c}
.sev.medium{background:#fef3c7;color:#d97706}
.sev.info{background:#dbeafe;color:#2563eb}
.sev.critical{background:#fee2e2;color:#dc2626}
.flag-cell{font-family:'SFMono-Regular',Consolas,'Liberation Mono',Menlo,monospace;
           font-size:.8rem;color:#1e293b;word-break:break-all}
.params-grid{display:grid;grid-template-columns:1fr 1fr;gap:18px;margin-bottom:22px}
@media(max-width:900px){.params-grid{grid-template-columns:1fr}}
</style>"""

# Chart.js initialization — plain string, not f-string; braces are JavaScript syntax
_HTML_CHARTS_JS = """<script>
(function(){
  var raw=document.getElementById('gc-chart-data');
  if(!raw)return;
  var D=JSON.parse(raw.textContent);

  function mkChart(id,cfg){
    var el=document.getElementById(id);
    if(!el)return;
    new Chart(el,cfg);
  }

  // Pause Timeline
  var minorPts=D.pauseTimeline.filter(function(p){return !p.full;});
  var fullPts =D.pauseTimeline.filter(function(p){return  p.full;});
  mkChart('chartPause',{
    type:'scatter',
    data:{datasets:[
      {label:'Minor/Concurrent',data:minorPts.map(function(p){return{x:p.x,y:p.y};}),
       backgroundColor:'rgba(59,130,246,.65)',pointRadius:4},
      {label:'Full GC',data:fullPts.map(function(p){return{x:p.x,y:p.y};}),
       backgroundColor:'rgba(220,38,38,.85)',pointRadius:8,pointStyle:'triangle'}
    ]},
    options:{responsive:true,maintainAspectRatio:false,
      plugins:{legend:{position:'top',labels:{boxWidth:12}}},
      scales:{
        x:{title:{display:true,text:'Uptime (s)'}},
        y:{title:{display:true,text:'Pause (ms)'},min:0}
      }}
  });

  // Heap Evolution
  mkChart('chartHeap',{
    type:'line',
    data:{
      labels:D.heapEvolution.map(function(p){return p.x.toFixed(1);}),
      datasets:[
        {label:'Before GC',data:D.heapEvolution.map(function(p){return p.before;}),
         borderColor:'#f97316',backgroundColor:'rgba(249,115,22,.07)',
         fill:true,tension:.3,pointRadius:3},
        {label:'After GC',data:D.heapEvolution.map(function(p){return p.after;}),
         borderColor:'#22c55e',backgroundColor:'rgba(34,197,94,.07)',
         fill:true,tension:.3,pointRadius:3}
      ]
    },
    options:{responsive:true,maintainAspectRatio:false,
      plugins:{legend:{position:'top',labels:{boxWidth:12}}},
      scales:{
        x:{title:{display:true,text:'Uptime (s)'}},
        y:{title:{display:true,text:'Heap (MB)'},min:0}
      }}
  });

  // Pause Distribution
  mkChart('chartDist',{
    type:'bar',
    data:{
      labels:D.pauseDist.labels,
      datasets:[{label:'Events',data:D.pauseDist.values,
        backgroundColor:['rgba(34,197,94,.75)','rgba(59,130,246,.75)',
                         'rgba(234,179,8,.75)','rgba(249,115,22,.75)',
                         'rgba(220,38,38,.75)']}]
    },
    options:{responsive:true,maintainAspectRatio:false,
      plugins:{legend:{display:false}},
      scales:{y:{beginAtZero:true,title:{display:true,text:'Count'}}}}
  });

  // GC Type Doughnut
  var PAL=['#3b82f6','#10b981','#f97316','#8b5cf6','#ec4899','#14b8a6','#f59e0b','#6366f1'];
  mkChart('chartTypes',{
    type:'doughnut',
    data:{
      labels:D.gcTypes.labels,
      datasets:[{data:D.gcTypes.values,
        backgroundColor:PAL.slice(0,D.gcTypes.labels.length),hoverOffset:6}]
    },
    options:{responsive:true,maintainAspectRatio:false,
      plugins:{legend:{position:'right',labels:{boxWidth:13,font:{size:11}}}}}
  });
})();
</script>"""


# ── Regex catalogue ───────────────────────────────────────────────────────────

_VER_PATTERNS = [
    re.compile(r'\bVersion:\s+(?P<v>\d+)\.'),
    re.compile(r'\bJRE\s*\(1\.(?P<v>[5-9])\.\d'),
    re.compile(r'\bJRE\s*\((?P<v>[1-9]\d)\.\d'),
    re.compile(r'version\s+"1\.(?P<v>[5-9])\.', re.I),
    re.compile(r'version\s+"(?P<v>[1-9]\d)\.', re.I),
]


def _extract_jdk_version(line: str):
    for pat in _VER_PATTERNS:
        m = pat.search(line)
        if m:
            v = int(m.group("v"))
            if v > 1:
                return v, line.strip()
    return 0, ""


_RE_USING_GC = re.compile(
    r'Using\s+(?P<gc>The Z Garbage Collector|ZGC|G1|Shenandoah|Serial|Parallel\s+GC|Parallel)'
)
_RE_PERMGEN = re.compile(r'(?:PSPerm|PermGen|Perm\s*:)', re.I)
_RE_ZGC_GEN = re.compile(r'\((?:Minor|Major)\)')

_ULP = r'\[(?P<ts>[^\]]+)\](?:\[[^\]]+\])*\s+'

_UL_PAUSE_HEAP = re.compile(
    _ULP +
    r'GC\(\d+\)\s+(?P<type>Pause\s+\S+(?:\s+\([^)]+\))*)'
    r'.*?(?P<before>\d+)M->(?P<after>\d+)M\((?P<heap>\d+)M\)'
    r'\s+(?P<pause>[\d.]+)ms'
)
_UL_PAUSE_NOHP = re.compile(
    _ULP +
    r'GC\(\d+\)\s+(?P<type>Pause\s+(?:'
    r'Remark|Cleanup'
    r'|Mark Start|Mark End|Relocate Start'
    r'|Init Mark|Final Mark|Init Update Refs|Final Update Refs'
    r')(?:\s+\([^)]+\))?)\s+(?P<pause>[\d.]+)ms'
)
_UL_ZGC_SUMMARY = re.compile(
    _ULP +
    r'GC\(\d+\)\s+Garbage Collection\s+\([^)]+\)'
    r'(?:\s+\((?P<gen>Minor|Major)\))?'
    r'\s+(?P<before>[\d.]+)M\(\d+%\)->(?P<after>[\d.]+)M\(\d+%\)'
)

_LH = (
    r'(?:(?P<ts>[\d]{4}-\d{2}-\d{2}T[\d:+.Z-]+):\s*)?'
    r'(?P<uptime>[\d.]+):\s+'
)

_L_G1_PAUSE = re.compile(
    _LH +
    r'\[GC pause\s*\((?P<reason>[^)]+)\)\s*(?:\([^)]+\))?'
    r'.*?(?P<before>\d+)M->(?P<after>\d+)M\((?P<heap>\d+)M\)'
    r',?\s*(?P<pause>[\d.]+)\s*secs'
)
_L_G1_REMARK  = re.compile(_LH + r'\[GC remark.*?,\s*(?P<pause>[\d.]+)\s*secs')
_L_G1_CLEANUP = re.compile(
    _LH +
    r'\[GC cleanup\s*(?:(?P<before>\d+)M->(?P<after>\d+)M\((?P<heap>\d+)M\))?'
    r',?\s*(?P<pause>[\d.]+)\s*secs'
)
_L_G1_FULL = re.compile(
    _LH +
    r'\[Full GC\s*(?:\([^)]*\))?\s*'
    r'(?:(?P<before>\d+)M->(?P<after>\d+)M\((?P<heap>\d+)M\))?'
    r',?\s*(?P<pause>[\d.]+)\s*secs'
)
_L_PARALLEL = re.compile(
    _LH +
    r'\[GC\s*(?:\([^)]*\))?\s*'
    r'\[PS(?:YoungGen|OldGen):[^\]]*\]'
    r'\s*(?P<before>\d+)K->(?P<after>\d+)K\((?P<heap>\d+)K\)'
    r',?\s*(?P<pause>[\d.]+)\s*secs'
)
_L_PARALLEL7 = re.compile(
    _LH +
    r'\[GC\s+\[PS(?:YoungGen|OldGen):[^\]]*\]'
    r'\s*(?P<before>\d+)K->(?P<after>\d+)K\((?P<heap>\d+)K\)'
    r',?\s*(?P<pause>[\d.]+)\s*secs'
)
_L_FULL_MULTI = re.compile(
    _LH +
    r'\[Full GC\s*(?:\([^)]*\))?\s*'
    r'(?:\[[^\]]+\]\s*)+'
    r'(?P<before>\d+)K->(?P<after>\d+)K\((?P<heap>\d+)K\)'
    r'.*?,?\s*(?P<pause>[\d.]+)\s*secs'
)
_L_SERIAL = re.compile(
    _LH +
    r'\[(?P<type>GC|Full GC)\s*(?:\([^)]*\))?\s*'
    r'\[(?:DefNew|Tenured):'
    r'.*?(?P<before>\d+)K->(?P<after>\d+)K\((?P<heap>\d+)K\)'
    r'.*?,?\s*(?P<pause>[\d.]+)\s*secs'
)
_L_PARNEW = re.compile(
    _LH +
    r'\[GC\s*(?:\([^)]*\))?\s*\[ParNew:'
    r'.*?(?P<before>\d+)K->(?P<after>\d+)K\((?P<heap>\d+)K\)'
    r',?\s*(?P<pause>[\d.]+)\s*secs'
)
_L_CMS_STW = re.compile(
    _LH +
    r'\[GC\s*\((?P<phase>CMS[^)]+)\)'
    r'.*?(?P<before>\d+)K->(?P<after>\d+)K\((?P<heap>\d+)K\)'
    r',?\s*(?P<pause>[\d.]+)\s*secs'
)
_L_CMS_FULL = re.compile(
    _LH +
    r'\[Full GC\s*(?:\([^)]*\))?\s*\[CMS:'
    r'.*?(?P<before>\d+)K->(?P<after>\d+)K\((?P<heap>\d+)K\)'
    r'.*?,?\s*(?P<pause>[\d.]+)\s*secs'
)
_L_GENERIC_KB = re.compile(
    _LH +
    r'\[(?P<type>GC|Full GC)\s*'
    r'.*?(?P<before>\d+)K->(?P<after>\d+)K\((?P<heap>\d+)K\)'
    r',?\s*(?P<pause>[\d.]+)\s*secs'
)
_CPU_TIMES = re.compile(
    r'\[Times: user=(?P<user>[\d.]+) sys=(?P<sys>[\d.]+), real=(?P<real>[\d.]+) secs\]'
)


# ── Data ──────────────────────────────────────────────────────────────────────

@dataclass
class DetectedConfig:
    jdk_version:  int  = 0
    jdk_str:      str  = ""
    collector:    str  = UNKNOWN
    log_format:   str  = FORMAT_UNIFIED
    has_perm_gen: bool = False


@dataclass
class GCEvent:
    timestamp:      str   = ""
    uptime_ms:      float = 0.0
    gc_type:        str   = ""
    collector:      str   = ""
    pause_ms:       float = 0.0
    is_full:        bool  = False
    is_concurrent:  bool  = False
    heap_before_mb: float = 0.0
    heap_after_mb:  float = 0.0
    heap_total_mb:  float = 0.0
    gc_cause:       str   = ""
    cpu_user_s:     float = 0.0
    cpu_real_s:     float = 0.0


# ── Helpers ───────────────────────────────────────────────────────────────────

def _to_mb(kb: str) -> float:
    return float(kb) / 1024.0


def _parse_ul_ts(ts: str) -> float:
    ts = ts.strip()
    if re.match(r'^\d+\.\d+s$', ts):
        return float(ts[:-1]) * 1000
    if re.match(r'^\d+ms$', ts):
        return float(ts[:-2])
    for fmt in ("%Y-%m-%dT%H:%M:%S.%f%z", "%Y-%m-%dT%H:%M:%S%z"):
        try:
            return datetime.strptime(ts, fmt).timestamp() * 1000
        except ValueError:
            pass
    return 0.0


def _is_full(gc_type: str) -> bool:
    t = gc_type.lower()
    return "full" in t or "compaction" in t


def _linreg_slope(xs: list, ys: list) -> float:
    n = len(xs)
    if n < 2:
        return 0.0
    sx  = sum(xs); sy = sum(ys)
    sxy = sum(x * y for x, y in zip(xs, ys))
    sxx = sum(x * x for x in xs)
    d   = n * sxx - sx * sx
    return (n * sxy - sx * sy) / d if d else 0.0


def _last_cause(gc_type: str) -> str:
    """Return the last parenthesized group in a gc_type string as a cause label."""
    matches = _RE_CAUSE_PARENS.findall(gc_type)
    # filter out generational labels
    for m in reversed(matches):
        if m not in ("Minor", "Major", "young", "mixed"):
            return m
    return ""


# ── Main class ────────────────────────────────────────────────────────────────

class GCLogAnalyzer:
    def __init__(self):
        self.events:      List[GCEvent]  = []
        self.config:      DetectedConfig = DetectedConfig()
        self.total_lines: int            = 0
        self._raw_lines:  List[str]      = []

    # ── I/O ───────────────────────────────────────────────────────────────────

    def parse_file(self, path: str):
        with open(path, "r", errors="replace") as fh:
            lines = fh.readlines()
        self._raw_lines = [l.rstrip() for l in lines]
        self._detect_config()
        for line in self._raw_lines:
            self.total_lines += 1
            self._parse_line(line)

    def parse_text(self, text: str):
        self._raw_lines = text.splitlines()
        self._detect_config()
        for line in self._raw_lines:
            self.total_lines += 1
            self._parse_line(line)

    # ── Config detection ──────────────────────────────────────────────────────

    def _detect_config(self):
        cfg    = self.config
        sample = self._raw_lines[:200]

        ul_count = sum(1 for l in sample if l.lstrip().startswith('['))
        cfg.log_format = FORMAT_UNIFIED if ul_count > len(sample) * 0.3 else FORMAT_LEGACY

        for line in sample:
            v, raw = _extract_jdk_version(line)
            if v:
                cfg.jdk_version = v
                cfg.jdk_str     = raw
                break

        for line in sample:
            m = _RE_USING_GC.search(line)
            if m:
                gc = m.group("gc").lower()
                if "z garbage" in gc or gc == "zgc":
                    cfg.collector = ZGC
                elif "g1" in gc:
                    cfg.collector = G1GC
                elif "shenandoah" in gc:
                    cfg.collector = SHENANDOAH
                elif "serial" in gc:
                    cfg.collector = SERIAL
                elif "parallel" in gc:
                    cfg.collector = PARALLEL
                break

        if cfg.collector == UNKNOWN:
            full_sample = "\n".join(sample)
            if _RE_PERMGEN.search(full_sample):
                cfg.has_perm_gen  = True
                cfg.jdk_version   = 7
            if re.search(r'PSYoungGen|ParOldGen', full_sample):
                cfg.collector = PARALLEL
            elif re.search(r'DefNew|Tenured', full_sample):
                cfg.collector = SERIAL
            elif re.search(r'\bCMS\b|ParNew', full_sample):
                cfg.collector = CMS
            elif re.search(r'Pause Init Mark|Pause Final Mark|Pause Init Update|Pause Final Update'
                           r'|Concurrent evacuation', full_sample):
                cfg.collector = SHENANDOAH
            elif re.search(r'Garbage Collection.*?->.*?%\)', full_sample):
                cfg.collector = ZGC_GEN if _RE_ZGC_GEN.search(full_sample) else ZGC
            elif re.search(r'G1 Evacuation|Pause Young|Pause Mixed|Pause Remark', full_sample):
                cfg.collector = G1GC
            elif re.search(r'GC pause.*?G1', full_sample):
                cfg.collector = G1GC

        if cfg.collector == ZGC:
            for l in sample:
                if _RE_ZGC_GEN.search(l):
                    cfg.collector = ZGC_GEN
                    break

        if cfg.jdk_version == 0:
            if cfg.log_format == FORMAT_UNIFIED:
                cfg.jdk_version = 9
            elif cfg.collector in (ZGC, ZGC_GEN, SHENANDOAH):
                cfg.jdk_version = 11
            elif cfg.has_perm_gen:
                cfg.jdk_version = 7
            else:
                cfg.jdk_version = 8

    # ── Line dispatch ─────────────────────────────────────────────────────────

    def _parse_line(self, line: str):
        if not line.strip():
            return
        if self.config.log_format == FORMAT_UNIFIED:
            self._parse_unified(line)
        else:
            self._parse_legacy(line)

    # ── Unified logging parsers ───────────────────────────────────────────────

    def _parse_unified(self, line: str):
        col = self.config.collector

        if col in (ZGC, ZGC_GEN):
            m = _UL_ZGC_SUMMARY.search(line)
            if m:
                ts     = m.group("ts")
                gen    = m.group("gen") or ""
                cm     = re.search(r'Garbage Collection\s+\(([^)]+)\)', line)
                cause  = cm.group(1) if cm else ""
                label  = "ZGC Collection" + (" (" + gen + ")" if gen else "")
                self.events.append(GCEvent(
                    timestamp=ts, uptime_ms=_parse_ul_ts(ts),
                    gc_type=label, collector=col,
                    pause_ms=0.0, is_concurrent=True,
                    heap_before_mb=float(m.group("before")),
                    heap_after_mb=float(m.group("after")),
                    gc_cause=cause,
                ))
                return

        m = _UL_PAUSE_HEAP.search(line)
        if m:
            ts    = m.group("ts")
            gtype = m.group("type").strip()
            cause = _last_cause(gtype)
            self.events.append(GCEvent(
                timestamp=ts, uptime_ms=_parse_ul_ts(ts),
                gc_type=gtype, collector=col,
                pause_ms=float(m.group("pause")),
                is_full=_is_full(gtype),
                heap_before_mb=float(m.group("before")),
                heap_after_mb=float(m.group("after")),
                heap_total_mb=float(m.group("heap")),
                gc_cause=cause,
            ))
            return

        m = _UL_PAUSE_NOHP.search(line)
        if m:
            ts    = m.group("ts")
            gtype = m.group("type").strip()
            self.events.append(GCEvent(
                timestamp=ts, uptime_ms=_parse_ul_ts(ts),
                gc_type=gtype, collector=col,
                pause_ms=float(m.group("pause")),
            ))
            return

    # ── Legacy parsers ────────────────────────────────────────────────────────

    def _parse_legacy(self, line: str):
        col  = self.config.collector
        cpu  = _CPU_TIMES.search(line)
        us   = float(cpu.group("user")) if cpu else 0.0
        rs   = float(cpu.group("real")) if cpu else 0.0

        def _kb(m, gc_type, collector, is_full, cause="") -> GCEvent:
            return GCEvent(
                timestamp=m.group("ts") or "",
                uptime_ms=float(m.group("uptime")) * 1000,
                gc_type=gc_type, collector=collector,
                pause_ms=float(m.group("pause")) * 1000,
                is_full=is_full,
                heap_before_mb=_to_mb(m.group("before")),
                heap_after_mb=_to_mb(m.group("after")),
                heap_total_mb=_to_mb(m.group("heap")),
                gc_cause=cause, cpu_user_s=us, cpu_real_s=rs,
            )

        def _mb(m, gc_type, collector, is_full, cause="") -> GCEvent:
            heap = m.group("heap") if m.group("heap") else None
            return GCEvent(
                timestamp=m.group("ts") or "",
                uptime_ms=float(m.group("uptime")) * 1000,
                gc_type=gc_type, collector=collector,
                pause_ms=float(m.group("pause")) * 1000,
                is_full=is_full,
                heap_before_mb=float(m.group("before")),
                heap_after_mb=float(m.group("after")),
                heap_total_mb=float(heap) if heap else 0.0,
                gc_cause=cause, cpu_user_s=us, cpu_real_s=rs,
            )

        if col in (G1GC, UNKNOWN):
            m = _L_G1_PAUSE.search(line)
            if m:
                reason   = m.group("reason")
                is_mixed = "mixed" in line.lower()
                phase    = "Mixed" if is_mixed else "Young"
                self.events.append(_mb(m, f"G1 {phase} ({reason})", G1GC, False, reason))
                return
            m = _L_G1_FULL.search(line)
            if m and m.group("before"):
                cm = re.search(r'\(([^)]+)\)', line)
                self.events.append(_mb(m, "Full GC (G1)", G1GC, True,
                                       cm.group(1) if cm else ""))
                return
            m = _L_G1_REMARK.search(line)
            if m:
                self.events.append(GCEvent(
                    timestamp=m.group("ts") or "",
                    uptime_ms=float(m.group("uptime")) * 1000,
                    gc_type="GC Remark", collector=G1GC,
                    pause_ms=float(m.group("pause")) * 1000,
                    cpu_user_s=us, cpu_real_s=rs,
                ))
                return
            m = _L_G1_CLEANUP.search(line)
            if m:
                b = float(m.group("before")) if m.group("before") else 0.0
                a = float(m.group("after"))  if m.group("after")  else 0.0
                h = float(m.group("heap"))   if m.group("heap")   else 0.0
                self.events.append(GCEvent(
                    timestamp=m.group("ts") or "",
                    uptime_ms=float(m.group("uptime")) * 1000,
                    gc_type="GC Cleanup", collector=G1GC,
                    pause_ms=float(m.group("pause")) * 1000,
                    heap_before_mb=b, heap_after_mb=a, heap_total_mb=h,
                    cpu_user_s=us, cpu_real_s=rs,
                ))
                return

        if col in (CMS, UNKNOWN):
            m = _L_CMS_STW.search(line)
            if m:
                self.events.append(_kb(m, f"CMS {m.group('phase')}", CMS, False,
                                       m.group("phase")))
                return
            m = _L_PARNEW.search(line)
            if m:
                self.events.append(_kb(m, "CMS ParNew (young)", CMS, False))
                return
            m = _L_CMS_FULL.search(line)
            if m:
                self.events.append(_kb(m, "Full GC (CMS)", CMS, True,
                                       "Promotion Failure"))
                return

        if "[Full GC" in line and "K->" in line:
            m = _L_FULL_MULTI.search(line)
            if m:
                label = "Full GC (Parallel)" if col in (PARALLEL, UNKNOWN) else "Full GC"
                cm    = re.search(r'Full GC\s*\(([^)]+)\)', line)
                self.events.append(_kb(m, label, col or PARALLEL, True,
                                       cm.group(1) if cm else ""))
                return

        if col in (PARALLEL, UNKNOWN):
            m = _L_PARALLEL.search(line) or _L_PARALLEL7.search(line)
            if m:
                self.events.append(_kb(m, "Parallel Young GC", PARALLEL, False))
                return

        if col in (SERIAL, UNKNOWN):
            m = _L_SERIAL.search(line)
            if m:
                is_f = "full" in m.group("type").lower()
                self.events.append(_kb(m, f"Serial {'Full' if is_f else 'Young'} GC",
                                       SERIAL, is_f))
                return

        m = _L_GENERIC_KB.search(line)
        if m:
            is_f = "full" in m.group("type").lower()
            self.events.append(_kb(m, m.group("type"), col or UNKNOWN, is_f))

    # ── Extra-metric scan ─────────────────────────────────────────────────────

    def _scan_extra_metrics(self) -> dict:
        evac_fail = 0
        to_space  = 0
        meta_gc   = 0
        sys_gc    = 0
        conc_mark = 0
        hum_max   = 0

        for line in self._raw_lines:
            if _RE_EVAC_FAIL.search(line):
                low = line.lower()
                if "to-space exhausted" in low or "to-space overflow" in low:
                    to_space += 1
                else:
                    evac_fail += 1
            m = _RE_HUMONGOUS.search(line)
            if m:
                hum_max = max(hum_max, int(m.group(1)))
            if _RE_META_GC.search(line):
                meta_gc += 1
            if _RE_SYS_GC.search(line):
                sys_gc += 1
            if _RE_CONC_MARK.search(line):
                conc_mark += 1

        return {
            "evacuation_failure_count":  evac_fail,
            "to_space_exhaustion_count": to_space,
            "meta_gc_threshold_count":   meta_gc,
            "sys_gc_count":              sys_gc,
            "concurrent_mark_cycles":    conc_mark,
            "humongous_max_regions":     hum_max,
        }

    # ── Detected JVM parameters ───────────────────────────────────────────────

    def _extract_init_params(self) -> dict:
        """Scan gc,init lines and infer JVM parameters from the log."""
        params = {}
        col = self.config.collector
        _COL_FLAG = {
            G1GC: "-XX:+UseG1GC", CMS: "-XX:+UseConcMarkSweepGC",
            PARALLEL: "-XX:+UseParallelGC", SERIAL: "-XX:+UseSerialGC",
            ZGC: "-XX:+UseZGC", ZGC_GEN: "-XX:+UseZGC -XX:+ZGenerational",
            SHENANDOAH: "-XX:+UseShenandoahGC",
        }
        if col in _COL_FLAG:
            params["Collector flag"] = _COL_FLAG[col]

        for line in self._raw_lines:
            if "gc,init" not in line and "gc,heap" not in line:
                continue
            m = re.search(r'Heap Max Capacity:\s*(\S+)', line)
            if m: params["-Xmx"] = m.group(1)
            m = re.search(r'Heap Initial Capacity:\s*(\S+)', line)
            if m: params["-Xms"] = m.group(1)
            m = re.search(r'Heap Region Size:\s*(\S+)', line)
            if m: params["-XX:G1HeapRegionSize"] = m.group(1)
            m = re.search(r'Workers\s+for\s+\S[^:]*:\s*(\d+)', line)
            if m: params["-XX:ConcGCThreads (approx)"] = m.group(1)

        # GC thread count from task lines
        for line in self._raw_lines:
            m = re.search(r'Using (\d+) workers of (\d+) for', line)
            if m and "-XX:ParallelGCThreads" not in params:
                params["-XX:ParallelGCThreads (detected)"] = m.group(2)
                break

        # Infer Xmx from heap total when not in init lines
        if "-Xmx" not in params:
            totals = [e.heap_total_mb for e in self.events if e.heap_total_mb > 0]
            if totals:
                params["-Xmx (inferred)"] = f"~{int(max(totals))}M"

        if self.config.log_format == FORMAT_UNIFIED:
            params["GC log format"] = "-Xlog:gc* (unified, JDK 9+)"
        else:
            params["GC log format"] = "-XX:+PrintGCDetails (legacy, JDK 8)"

        if self.config.has_perm_gen:
            params["-XX:MaxPermSize"] = "not detected (set explicitly)"

        return params

    # ── Tuning recommendations (flag-level) ───────────────────────────────────

    def _tuning_params(self, stats: dict) -> list:
        """Return list of specific JVM flag recommendations based on analysis."""
        col = stats.get("collector", UNKNOWN)
        jdk = stats.get("jdk_version", 0)
        h   = stats.get("heap_mb", {})
        p   = stats.get("pause_ms", {})
        tuning: list = []

        def _add(flag, reason, category, severity="INFO"):
            tuning.append({"flag": flag, "reason": reason,
                           "category": category, "severity": severity})

        # ── Heap sizing ───────────────────────────────────────────────────────
        if h.get("configured"):
            live = h["max_after"]
            xmx  = h["configured"]
            lr   = live / xmx
            if lr > 0.60:
                recommended = int((live * 2.5) / 256 + 1) * 256
                sev = "HIGH" if lr > 0.80 else "MEDIUM"
                _add(f"-Xmx{recommended}m",
                     f"Live set {live:.0f}M = {lr*100:.0f}% of current {xmx:.0f}M. "
                     "Target: Xmx ≥ 2.5× live set.",
                     "Heap Sizing", sev)
                _add(f"-Xms{recommended}m",
                     "Match Xms to Xmx to prevent heap resize pauses on startup.",
                     "Heap Sizing", "INFO")

        # ── G1GC tuning ───────────────────────────────────────────────────────
        if col == G1GC:
            _add("-XX:MaxGCPauseMillis=200",
                 "Set explicit pause target (default 200ms). "
                 "Lower to 100ms for latency-sensitive workloads.",
                 "G1GC", "INFO")

            if stats.get("full_gc_count", 0) > 0:
                _add("-XX:InitiatingHeapOccupancyPercent=35",
                     "Default 45%. Trigger concurrent marking earlier so old gen is "
                     "reclaimed before the heap fills, preventing Full GC.",
                     "G1GC", "HIGH")
                _add("-XX:G1ReservePercent=20",
                     "Default 10%. Reserve more free space as an evacuation buffer "
                     "to avoid to-space exhaustion during mixed GC.",
                     "G1GC", "HIGH")

            if stats.get("humongous_max_regions", 0) > 0:
                _add("-XX:G1HeapRegionSize=16m",
                     "Humongous objects (>50% of region size) bypass the young gen. "
                     "Larger regions raise the threshold. Valid values: 1m–32m.",
                     "G1GC", "MEDIUM")

            if p.get("p99", 0) > 200:
                _add("-XX:G1NewSizePercent=20",
                     "Increase minimum young gen to reduce GC frequency.",
                     "G1GC", "MEDIUM")
                _add("-XX:G1MaxNewSizePercent=40",
                     "Cap young gen size to keep pause durations bounded.",
                     "G1GC", "MEDIUM")

            _add("-XX:+G1UseAdaptiveIHOP",
                 "Let G1 auto-tune IHOP based on observed marking times. "
                 "Enabled by default in JDK 9+; verify it is not disabled.",
                 "G1GC", "INFO")

        # ── CMS tuning ────────────────────────────────────────────────────────
        if col == CMS:
            _add("-XX:CMSInitiatingOccupancyFraction=70",
                 "Default ~92%. Trigger CMS collection earlier to avoid promotion failure.",
                 "CMS", "HIGH")
            _add("-XX:+UseCMSInitiatingOccupancyOnly",
                 "Disable CMS adaptive triggering — use the fixed fraction above.",
                 "CMS", "HIGH")
            _add("-XX:+CMSScavengeBeforeRemark",
                 "Run a minor GC before the CMS Remark pause to reduce promoted objects.",
                 "CMS", "MEDIUM")

        # ── ZGC tuning ────────────────────────────────────────────────────────
        if col in (ZGC, ZGC_GEN):
            if jdk and jdk >= 21 and col != ZGC_GEN:
                _add("-XX:+UseZGC -XX:+ZGenerational",
                     "Enable Generational ZGC (JDK 21+) for higher throughput "
                     "and fewer allocation stalls.",
                     "ZGC", "HIGH")
            if h.get("configured"):
                soft = int(h["configured"] * 0.9)
                _add(f"-XX:SoftMaxHeapSize={soft}m",
                     "ZGC soft limit: JVM tries to stay below this before the hard Xmx, "
                     "leaving headroom for allocation bursts.",
                     "ZGC", "INFO")

        # ── Shenandoah tuning ─────────────────────────────────────────────────
        if col == SHENANDOAH:
            _add("-XX:ShenandoahGCHeuristics=adaptive",
                 "Adaptive (default) balances frequency and duration. "
                 "Use 'compact' if heap pressure is consistently high.",
                 "Shenandoah", "INFO")

        # ── ParallelGC migration ───────────────────────────────────────────────
        if col == PARALLEL and jdk and jdk >= 11:
            _add("-XX:+UseG1GC",
                 "Switch from ParallelGC to G1GC for more predictable pauses "
                 "on heap > 4GB.",
                 "Collector", "HIGH")

        # ── Metaspace ─────────────────────────────────────────────────────────
        if stats.get("meta_gc_threshold_count", 0) > 0:
            _add("-XX:MetaspaceSize=256m",
                 "Pre-size Metaspace to eliminate GC cycles triggered by "
                 "the initial small Metaspace commit threshold.",
                 "Metaspace", "MEDIUM")
            _add("-XX:MaxMetaspaceSize=512m",
                 "Cap Metaspace growth (useful for frameworks that generate classes dynamically).",
                 "Metaspace", "MEDIUM")

        # ── System.gc() ───────────────────────────────────────────────────────
        if stats.get("sys_gc_count", 0) > 0:
            _add("-XX:+DisableExplicitGC",
                 "Suppress System.gc() calls which force Full GC. "
                 "Identify the caller first (jstack, JFR).",
                 "General", "HIGH")

        # ── GC logging ────────────────────────────────────────────────────────
        if jdk and jdk >= 9:
            _add("-Xlog:gc*:file=gc.log:time,uptime,level,tags:filecount=10,filesize=20m",
                 "Comprehensive GC logging with auto-rotation (10 × 20MB). "
                 "Essential for post-incident analysis.",
                 "Logging", "INFO")
        else:
            _add("-XX:+PrintGCDetails -XX:+PrintGCDateStamps "
                 "-XX:+PrintGCApplicationStoppedTime "
                 "-Xloggc:/var/log/app/gc.log "
                 "-XX:+UseGCLogFileRotation -XX:NumberOfGCLogFiles=10 "
                 "-XX:GCLogFileSize=20m",
                 "Full GC logging with rotation for JDK 8.",
                 "Logging", "INFO")

        # ── JFR profiling ─────────────────────────────────────────────────────
        if jdk and jdk >= 11:
            _add("-XX:+FlightRecorder "
                 "-XX:StartFlightRecording=duration=60s,filename=app.jfr",
                 "JDK Flight Recorder: near-zero overhead profiling for GC, "
                 "allocations, and CPU. Use JMC to analyse.",
                 "Profiling", "INFO")

        # Sort: HIGH first, then MEDIUM, INFO
        order = {"CRITICAL": 0, "HIGH": 1, "MEDIUM": 2, "INFO": 3}
        tuning.sort(key=lambda x: order.get(x["severity"], 4))
        return tuning

    # ── Health score ──────────────────────────────────────────────────────────

    def _health_score(self, stats: dict) -> Tuple[int, str]:
        score = 100

        fgc = stats.get("full_gc_count", 0)
        score -= min(40, fgc * 20)

        thru = stats.get("throughput_pct", 100.0)
        if thru < 90:   score -= 20
        elif thru < 95: score -= 10

        p99 = stats.get("pause_ms", {}).get("p99", 0)
        if p99 > 500:   score -= 15
        elif p99 > 200: score -= 8

        h = stats.get("heap_mb", {})
        if h.get("configured"):
            lr = h["max_after"] / h["configured"]
            if lr > 0.80:   score -= 10
            elif lr > 0.60: score -= 5

        if stats.get("evacuation_failure_count", 0) > 0: score -= 15
        if stats.get("to_space_exhaustion_count", 0) > 0: score -= 20

        jdk = stats.get("jdk_version", 0)
        if jdk and jdk <= 7:  score -= 5
        elif jdk == 8:        score -= 3

        if stats.get("collector") == CMS and jdk and jdk >= 9:
            score -= 5

        trend = stats.get("heap_trend_mb_per_min", 0.0)
        if trend > 100:   score -= 15
        elif trend > 50:  score -= 8
        elif trend > 20:  score -= 3

        score = max(0, min(100, score))

        if score >= 90:   label = "Excellent"
        elif score >= 80: label = "Good"
        elif score >= 60: label = "Needs Attention"
        elif score >= 40: label = "Degraded"
        else:             label = "Critical"

        return score, label

    # ── Analysis ──────────────────────────────────────────────────────────────

    def analyze(self) -> dict:
        if not self.events:
            return {
                "error":       "No GC events found",
                "jdk_version": self.config.jdk_version,
                "collector":   self.config.collector,
                "log_format":  self.config.log_format,
            }

        cfg          = self.config
        pause_events = [e for e in self.events if e.pause_ms > 0]
        if not pause_events:
            return {"error": "Events found but all have zero pause (concurrent-only log?)"}

        pauses     = [e.pause_ms for e in pause_events]
        full_gc    = [e for e in pause_events if e.is_full]
        nonfull_gc = [e for e in pause_events if not e.is_full]

        total_pause_ms = sum(pauses)
        total_time_ms  = (self.events[-1].uptime_ms - self.events[0].uptime_ms) or 1
        throughput_pct = max(0.0, (1 - total_pause_ms / total_time_ms) * 100)

        heap_befores = [e.heap_before_mb for e in self.events if e.heap_before_mb]
        heap_afters  = [e.heap_after_mb  for e in self.events if e.heap_after_mb]
        heap_totals  = [e.heap_total_mb  for e in self.events if e.heap_total_mb]

        alloc_rate = None
        if len(self.events) >= 2:
            total_alloc = sum(
                max(0, self.events[i].heap_before_mb - self.events[i - 1].heap_after_mb)
                for i in range(1, len(self.events))
            )
            alloc_rate = total_alloc / (total_time_ms / 1000)

        gc_intervals = [
            self.events[i].uptime_ms - self.events[i - 1].uptime_ms
            for i in range(1, len(self.events))
            if self.events[i].uptime_ms - self.events[i - 1].uptime_ms > 0
        ]

        sp = sorted(pauses)
        buckets = {"<10": 0, "10-50": 0, "50-200": 0, "200-500": 0, ">500": 0}
        for p in pauses:
            if p < 10:      buckets["<10"]     += 1
            elif p < 50:    buckets["10-50"]   += 1
            elif p < 200:   buckets["50-200"]  += 1
            elif p < 500:   buckets["200-500"] += 1
            else:           buckets[">500"]    += 1

        type_map: Dict[str, list] = defaultdict(list)
        for e in pause_events:
            type_map[e.gc_type.split("(")[0].strip()].append(e.pause_ms)

        cpu_events    = [e for e in pause_events if e.cpu_user_s > 0]
        cpu_efficiency = None
        if cpu_events:
            ratios = [e.cpu_real_s / e.cpu_user_s for e in cpu_events if e.cpu_user_s > 0]
            cpu_efficiency = round(statistics.mean(ratios), 2) if ratios else None

        # GC causes
        causes_ctr: Dict[str, int] = defaultdict(int)
        _GEN = {"Minor", "Major", "young", "mixed"}
        for e in self.events:
            cause = e.gc_cause
            if not cause:
                cause = _last_cause(e.gc_type)
            if cause and cause not in _GEN:
                causes_ctr[cause] += 1

        # Heap growth trend (MB per minute)
        htrend_pts = [(e.uptime_ms / 60000, e.heap_after_mb)
                      for e in self.events if e.heap_after_mb > 0 and e.uptime_ms > 0]
        heap_trend = 0.0
        if len(htrend_pts) >= 3:
            heap_trend = round(_linreg_slope(
                [p[0] for p in htrend_pts], [p[1] for p in htrend_pts]), 2)

        # Pause trend (ms per minute)
        ptrend_pts = [(e.uptime_ms / 60000, e.pause_ms)
                      for e in pause_events if e.uptime_ms > 0]
        pause_trend = 0.0
        if len(ptrend_pts) >= 3:
            pause_trend = round(_linreg_slope(
                [p[0] for p in ptrend_pts], [p[1] for p in ptrend_pts]), 2)

        # Extra metrics
        extra = self._scan_extra_metrics()

        stats: dict = {
            "jdk_version":        cfg.jdk_version,
            "jdk_version_str":    cfg.jdk_str,
            "collector":          cfg.collector,
            "log_format":         cfg.log_format,
            "has_perm_gen":       cfg.has_perm_gen,
            "total_events":       len(self.events),
            "pause_events":       len(pause_events),
            "full_gc_count":      len(full_gc),
            "nonfull_gc_count":   len(nonfull_gc),
            "total_lines_parsed": self.total_lines,
            "time_span_sec":      round(total_time_ms / 1000, 1),
            "throughput_pct":     round(throughput_pct, 2),
            "pause_ms": {
                "min":       round(min(pauses), 2),
                "max":       round(max(pauses), 2),
                "mean":      round(statistics.mean(pauses), 2),
                "median":    round(statistics.median(pauses), 2),
                "p95":       round(sp[max(0, int(len(sp) * 0.95) - 1)], 2),
                "p99":       round(sp[max(0, int(len(sp) * 0.99) - 1)], 2),
                "total_sec": round(total_pause_ms / 1000, 2),
            },
            "pause_distribution": buckets,
            "full_gc_pause_ms": {
                "count": len(full_gc),
                "max":   round(max((e.pause_ms for e in full_gc), default=0), 2),
                "mean":  round(statistics.mean([e.pause_ms for e in full_gc]), 2)
                         if full_gc else 0,
            },
            "heap_mb": {
                "max_before": round(max(heap_befores), 1) if heap_befores else 0,
                "min_after":  round(min(heap_afters),  1) if heap_afters  else 0,
                "max_after":  round(max(heap_afters),  1) if heap_afters  else 0,
                "configured": round(max(heap_totals),  1) if heap_totals  else 0,
            },
            "allocation_rate_mb_s": round(alloc_rate, 1) if alloc_rate else None,
            "gc_interval_ms": {
                "mean": round(statistics.mean(gc_intervals), 0) if gc_intervals else 0,
                "min":  round(min(gc_intervals), 0)             if gc_intervals else 0,
            },
            "gc_type_breakdown": {
                k: {"count": len(v), "mean_pause_ms": round(statistics.mean(v), 2)}
                for k, v in sorted(type_map.items(), key=lambda x: -len(x[1]))
            },
            "gc_causes":              dict(sorted(causes_ctr.items(), key=lambda x: -x[1])),
            "cpu_efficiency":         cpu_efficiency,
            "heap_trend_mb_per_min":  heap_trend,
            "pause_trend_ms_per_min": pause_trend,
            **extra,
        }

        score, label = self._health_score(stats)
        stats["health_score"] = score
        stats["health_label"] = label
        stats["detected_params"] = self._extract_init_params()
        stats["tuning_params"]   = self._tuning_params(stats)
        return stats

    # ── Recommendations ───────────────────────────────────────────────────────

    def recommendations(self, stats: dict) -> list:
        if "error" in stats:
            return [f"[ERROR] {stats['error']}. Verify log flags and format."]

        recs = []
        p    = stats["pause_ms"]
        heap = stats["heap_mb"]
        jdk  = stats["jdk_version"]
        col  = stats["collector"]
        thru = stats["throughput_pct"]

        # ── JDK version ───────────────────────────────────────────────────────
        if jdk and jdk <= 7:
            recs.append(
                "[CRITICAL] JDK 7 is EOL (April 2015). Upgrade to JDK 21 LTS immediately "
                "for security patches and access to G1GC, ZGC, Shenandoah."
            )
        elif jdk == 8:
            recs.append(
                "[HIGH] JDK 8 mainstream support ended March 2022. Plan migration to JDK 21 LTS. "
                "Modern low-latency collectors (ZGC, Shenandoah) require JDK 11+."
            )
        elif 9 <= jdk <= 10:
            recs.append("[MEDIUM] JDK 9/10 are non-LTS and EOL. Migrate to JDK 11 or 21 LTS.")
        elif jdk == 11:
            recs.append(
                "[INFO] JDK 11 LTS is supported. JDK 21 adds generational ZGC and significant "
                "G1GC improvements. Consider a planned upgrade."
            )
        elif jdk == 17:
            recs.append(
                "[INFO] JDK 17 LTS. JDK 21 adds generational ZGC for better low-latency. "
                "Upgrade when ready."
            )

        # ── Collector ─────────────────────────────────────────────────────────
        if col == CMS:
            if jdk and jdk >= 14:
                recs.append(
                    "[CRITICAL] CMS was removed in JDK 14. If running JDK 14+, "
                    "-XX:+UseConcMarkSweepGC may be silently ignored — verify active collector."
                )
            elif jdk and jdk >= 9:
                recs.append(
                    "[HIGH] CMS is deprecated since JDK 9 and removed in JDK 14. "
                    "Migrate to G1GC (-XX:+UseG1GC) or ZGC (-XX:+UseZGC) now."
                )
            else:
                recs.append(
                    "[MEDIUM] CMS produces fragmentation and promotion failures over time. "
                    "Consider migrating to G1GC for heap > 4 GB."
                )

        if col == PARALLEL:
            if jdk and jdk >= 9:
                recs.append(
                    "[MEDIUM] ParallelGC maximises throughput but has long STW pauses. "
                    "For latency-sensitive Kafka workloads switch to G1GC or ZGC."
                )
            else:
                recs.append(
                    "[MEDIUM] ParallelGC is the JDK 7/8 default — good for batch, "
                    "but unpredictable Full GC pauses. For Kafka/Connect heap >4GB, use G1GC."
                )

        if col == SERIAL:
            recs.append(
                "[HIGH] SerialGC is single-threaded — only suitable for <256MB heaps. "
                "Kafka/Connect needs at least ParallelGC or G1GC."
            )

        if col == G1GC:
            if jdk and jdk >= 9:
                recs.append(
                    "[INFO] G1GC is the correct default. Key knobs: "
                    "-XX:MaxGCPauseMillis (pause target), -XX:G1HeapRegionSize, "
                    "-XX:G1NewSizePercent, -XX:InitiatingHeapOccupancyPercent."
                )
            else:
                recs.append(
                    "[INFO] G1GC in JDK 8 is mature for heap >4GB. "
                    "Ensure JDK 8u40+ for critical G1 bug fixes."
                )

        if col == ZGC:
            recs.append(
                "[INFO] ZGC targets sub-millisecond pauses. "
                "Upgrade to JDK 21 for generational ZGC (-XX:+ZGenerational) "
                "which drastically reduces allocation stalls."
            )

        if col == ZGC_GEN:
            recs.append(
                "[INFO] Generational ZGC (JDK 21+) — excellent choice. "
                "Ensure -XX:+UseZGC -XX:+ZGenerational and heap is 2-4× live set."
            )

        if col == SHENANDOAH:
            recs.append(
                "[INFO] Shenandoah: concurrent compaction with very low pauses. "
                "Watch for 'Degenerated GC' events (fallback to STW) as a key health signal."
            )

        # ── Full GC ───────────────────────────────────────────────────────────
        fgc = stats["full_gc_count"]
        if fgc > 0:
            recs.append(
                f"[CRITICAL] {fgc} Full GC(s) detected "
                f"(avg {stats['full_gc_pause_ms']['mean']}ms, "
                f"max {stats['full_gc_pause_ms']['max']}ms). "
                "Full GCs indicate heap pressure, fragmentation, to-space exhaustion, "
                "or explicit System.gc() calls. Investigate root cause immediately."
            )

        # ── Evacuation failure / to-space exhaustion ──────────────────────────
        ef = stats.get("evacuation_failure_count", 0)
        ts = stats.get("to_space_exhaustion_count", 0)
        if ts > 0:
            recs.append(
                f"[CRITICAL] {ts} to-space exhaustion event(s) — G1GC ran out of survivor/old "
                "regions during evacuation. Symptoms: massive Full GC, application stall. "
                "Fix: increase -Xmx, lower -XX:InitiatingHeapOccupancyPercent (try 35), "
                "or reduce -XX:G1ReservePercent."
            )
        if ef > 0:
            recs.append(
                f"[HIGH] {ef} evacuation failure(s) detected. Old gen is too full to absorb "
                "promoted objects. Increase heap or tune -XX:G1MixedGCCountTarget."
            )

        # ── System.gc() ───────────────────────────────────────────────────────
        sgc = stats.get("sys_gc_count", 0)
        if sgc > 0:
            recs.append(
                f"[HIGH] {sgc} explicit System.gc() call(s) found. These trigger Full GCs "
                "regardless of heap state. Add -XX:+DisableExplicitGC to suppress them, "
                "or use -XX:+ExplicitGCInvokesConcurrent to make them concurrent (G1/CMS)."
            )

        # ── Humongous allocations ──────────────────────────────────────────────
        hum = stats.get("humongous_max_regions", 0)
        if hum > 0:
            recs.append(
                f"[MEDIUM] Humongous object allocations detected (up to {hum} regions). "
                "Objects >50% of G1 region size bypass the young gen and trigger major GCs. "
                "Increase -XX:G1HeapRegionSize (up to 32M) or reduce large object allocations."
            )

        # ── Metadata GC threshold ──────────────────────────────────────────────
        mgc = stats.get("meta_gc_threshold_count", 0)
        if mgc > 0:
            recs.append(
                f"[MEDIUM] {mgc} Metadata GC threshold trigger(s). Metaspace is filling up, "
                "causing GC cycles to reclaim class metadata. Set "
                "-XX:MetaspaceSize=256m -XX:MaxMetaspaceSize=512m to reduce thrashing."
            )

        # ── Pause SLO ─────────────────────────────────────────────────────────
        p99 = p["p99"]
        if p99 > 500:
            if col in (ZGC, ZGC_GEN, SHENANDOAH):
                recs.append(
                    f"[HIGH] p99 pause {p99}ms is unexpectedly high for {col}. "
                    "Check for allocation bursts, degenerated GC, or OS-level jitter (THP, swapping)."
                )
            else:
                upgrade = ("Switch to ZGC/Shenandoah for sub-ms pauses."
                           if jdk and jdk >= 11 else
                           "Upgrade to JDK 11+ to access ZGC/Shenandoah.")
                recs.append(
                    f"[HIGH] p99 pause {p99}ms exceeds 500ms SLO. {upgrade}"
                )
        elif p99 > 200:
            recs.append(
                f"[MEDIUM] p99 pause {p99}ms. Tune -XX:MaxGCPauseMillis to match SLO. "
                "Target <100ms for interactive/streaming workloads."
            )

        # ── Throughput ────────────────────────────────────────────────────────
        if thru < 90:
            recs.append(
                f"[HIGH] GC throughput {thru}% — {100-thru:.1f}% of CPU time in GC. "
                "Increase -Xmx, reduce allocation rate, or switch to a more efficient collector."
            )
        elif thru < 95:
            recs.append(
                f"[MEDIUM] GC throughput {thru}% (target ≥95%). "
                "Consider increasing heap or tuning young gen sizing."
            )

        # ── Heap utilisation ──────────────────────────────────────────────────
        if heap["configured"] > 0:
            lr = heap["max_after"] / heap["configured"]
            if lr > 0.80:
                recs.append(
                    f"[HIGH] Live set {heap['max_after']}M = {lr*100:.0f}% of -Xmx "
                    f"({heap['configured']}M). Increase heap or investigate memory leak. "
                    "Rule of thumb: live set should be <50% of Xmx."
                )
            elif lr > 0.60:
                recs.append(
                    f"[LOW] Live set {lr*100:.0f}% of heap. "
                    "Add 30-50% headroom to reduce GC frequency."
                )

        # ── Heap growth trend (memory leak indicator) ──────────────────────────
        trend = stats.get("heap_trend_mb_per_min", 0.0)
        if trend > 100:
            recs.append(
                f"[CRITICAL] Heap growing at {trend}MB/min — strong memory leak signal. "
                "Capture heap dump (jmap -dump:live,format=b,file=heap.hprof <pid>) "
                "and analyse with Eclipse MAT or JVisualVM immediately."
            )
        elif trend > 50:
            recs.append(
                f"[HIGH] Heap growing at {trend}MB/min. Investigate object retention "
                "and allocation patterns with async-profiler or JFR."
            )
        elif trend > 20:
            recs.append(
                f"[MEDIUM] Heap growing at {trend}MB/min. Monitor over a longer window "
                "to confirm steady-state vs. genuine leak."
            )

        # ── Pause trend ────────────────────────────────────────────────────────
        pt = stats.get("pause_trend_ms_per_min", 0.0)
        if pt > 50:
            recs.append(
                f"[HIGH] GC pauses increasing at {pt}ms/min — heap filling over time. "
                "Expand -Xmx or investigate long-lived object accumulation."
            )

        # ── Allocation rate ────────────────────────────────────────────────────
        ar = stats.get("allocation_rate_mb_s")
        if ar and ar > 500:
            recs.append(
                f"[MEDIUM] High allocation rate {ar}MB/s. Profile with "
                "async-profiler (alloc mode) or JFR. Object pooling or off-heap "
                "buffers (DirectByteBuffer) can reduce GC pressure."
            )

        # ── GC frequency ──────────────────────────────────────────────────────
        mean_iv = stats["gc_interval_ms"]["mean"]
        if mean_iv < 1000 and stats["pause_events"] > 10:
            recs.append(
                f"[MEDIUM] GC firing every {mean_iv:.0f}ms on average. "
                "Increase Eden/young gen size or -XX:G1NewSizePercent to reduce frequency."
            )

        # ── PermGen ───────────────────────────────────────────────────────────
        if stats.get("has_perm_gen"):
            recs.append(
                "[INFO] PermGen detected (JDK 7). Set -XX:MaxPermSize=256m to avoid OOM. "
                "Upgrading to JDK 8+ replaces PermGen with auto-sizing Metaspace."
            )

        # ── GC causes ─────────────────────────────────────────────────────────
        causes = stats.get("gc_causes", {})
        if "Allocation Failure" in causes and causes["Allocation Failure"] > 5:
            recs.append(
                f"[MEDIUM] {causes['Allocation Failure']} Allocation Failure triggers. "
                "Heap is consistently full when GC starts — increase -Xmx or tune "
                "-XX:G1NewSizePercent/-XX:NewRatio."
            )
        if "Ergonomics" in causes:
            recs.append(
                "[INFO] GC triggered by Ergonomics (JVM auto-tuning). "
                "This is normal but tuning -XX:MaxGCPauseMillis can improve predictability."
            )

        if not recs:
            recs.append("[OK] No significant issues detected. GC behaviour looks healthy.")

        return recs

    # ── Text report ───────────────────────────────────────────────────────────

    def report(self, stats: dict) -> str:
        if "error" in stats:
            return (
                f"  JDK version : {stats.get('jdk_version', '?')}\n"
                f"  Collector   : {stats.get('collector', '?')}\n"
                f"  Error       : {stats['error']}\n"
            )

        recs = self.recommendations(stats)
        jdk  = stats["jdk_version"]
        col  = stats["collector"]
        W    = 72

        def _hdr(title):
            return f"── {title} " + "─" * (W - len(title) - 4)

        jdk_label = f"JDK {jdk}" if jdk else "unknown"
        if stats.get("jdk_version_str"):
            jdk_label += f"  ({stats['jdk_version_str'][:50]})"

        lines = [
            "=" * W,
            "  JVM GC Log Analysis Report",
            "=" * W,
            f"  JDK version    : {jdk_label}",
            f"  Collector      : {col}",
            f"  Log format     : {stats['log_format']}",
            f"  PermGen        : {'yes (JDK 7)' if stats.get('has_perm_gen') else 'no'}",
            f"  Health score   : {stats.get('health_score', '?')}/100  "
            f"({stats.get('health_label', '?')})",
            "",
            _hdr("Summary"),
            f"  Total GC events    : {stats['total_events']}  "
            f"(pausing={stats['pause_events']}, full={stats['full_gc_count']})",
            f"  Log time span      : {stats['time_span_sec']}s",
            f"  GC throughput      : {stats['throughput_pct']}%",
        ]

        if stats.get("evacuation_failure_count"):
            lines.append(f"  Evacuation failures: {stats['evacuation_failure_count']}")
        if stats.get("to_space_exhaustion_count"):
            lines.append(f"  To-space exhaustion: {stats['to_space_exhaustion_count']}")
        if stats.get("sys_gc_count"):
            lines.append(f"  Explicit System.gc(): {stats['sys_gc_count']}")
        if stats.get("humongous_max_regions"):
            lines.append(f"  Humongous regions  : {stats['humongous_max_regions']} (max seen)")

        p = stats["pause_ms"]
        lines += [
            "",
            _hdr("Pause Times (ms)"),
            f"  Min / Median / Mean : {p['min']} / {p['median']} / {p['mean']}",
            f"  p95 / p99 / Max     : {p['p95']} / {p['p99']} / {p['max']}",
            f"  Total pause time    : {p['total_sec']}s",
        ]

        if stats.get("heap_trend_mb_per_min") is not None:
            lines.append(f"  Heap growth trend   : {stats['heap_trend_mb_per_min']}MB/min")
        if stats.get("pause_trend_ms_per_min") is not None:
            lines.append(f"  Pause trend         : {stats['pause_trend_ms_per_min']}ms/min")

        lines += ["", _hdr("Pause Distribution")]
        for bucket, count in stats["pause_distribution"].items():
            bar = "█" * min(count, 40)
            lines.append(f"  {bucket:>8}ms : {bar} {count}")

        h = stats["heap_mb"]
        if h["configured"]:
            pct = h["max_after"] / h["configured"] * 100
            lines += [
                "",
                _hdr("Heap"),
                f"  Configured (Xmx)    : {h['configured']}M",
                f"  Max live set (post) : {h['max_after']}M ({pct:.0f}% of Xmx)",
                f"  Max before GC       : {h['max_before']}M",
            ]
        if stats.get("allocation_rate_mb_s"):
            lines.append(f"  Allocation rate     : {stats['allocation_rate_mb_s']}MB/s")

        causes = stats.get("gc_causes", {})
        if causes:
            lines += ["", _hdr("GC Causes")]
            for cause, cnt in causes.items():
                lines.append(f"  {cause:<45} {cnt}")

        lines += ["", _hdr("GC Type Breakdown")]
        for gtype, info in stats["gc_type_breakdown"].items():
            lines.append(
                f"  {gtype[:48]:<50} count={info['count']}  avg={info['mean_pause_ms']}ms"
            )

        lines += ["", _hdr("Recommendations")]
        for r in recs:
            lines.append(f"  {r}")

        lines.append("=" * W)
        return "\n".join(lines)

    # ── HTML report ───────────────────────────────────────────────────────────

    def generate_html(self, stats: dict, output_path: str,
                      filename: str = "", top_n: int = 20) -> str:
        """Write a self-contained HTML dashboard to output_path; return the path."""

        if "error" in stats:
            content = (
                '<!DOCTYPE html><html><head><meta charset="UTF-8">'
                '<title>GC Analysis Error</title></head>'
                '<body style="font-family:sans-serif;padding:40px">'
                '<h1 style="color:#dc2626">GC Analysis Error</h1>'
                f'<p><b>File:</b> {_html.escape(filename)}</p>'
                f'<p><b>Error:</b> {_html.escape(stats["error"])}</p>'
                f'<p>JDK: {stats.get("jdk_version","?")} | '
                f'Collector: {stats.get("collector","?")}</p>'
                '</body></html>'
            )
            with open(output_path, "w", encoding="utf-8") as f:
                f.write(content)
            return output_path

        recs   = self.recommendations(stats)
        jdk    = stats.get("jdk_version", 0)
        col    = stats.get("collector", UNKNOWN)
        p      = stats.get("pause_ms", {})
        h      = stats.get("heap_mb", {})
        health = stats.get("health_score", 100)
        hlabel = stats.get("health_label", "")
        thru   = stats.get("throughput_pct", 0)

        # ── Chart data ────────────────────────────────────────────────────────
        chart_data = {
            "pauseTimeline": [
                {"x": round(e.uptime_ms / 1000, 3),
                 "y": round(e.pause_ms, 2),
                 "full": e.is_full}
                for e in self.events if e.pause_ms > 0
            ],
            "heapEvolution": [
                {"x": round(e.uptime_ms / 1000, 3),
                 "before": round(e.heap_before_mb, 1),
                 "after":  round(e.heap_after_mb, 1)}
                for e in self.events if e.heap_before_mb > 0
            ],
            "pauseDist": {
                "labels": [k + "ms" for k in stats.get("pause_distribution", {}).keys()],
                "values": list(stats.get("pause_distribution", {}).values()),
            },
            "gcTypes": {
                "labels": [k[:28] for k in stats.get("gc_type_breakdown", {}).keys()],
                "values": [v["count"] for v in stats.get("gc_type_breakdown", {}).values()],
            },
        }

        # ── Health badge color ────────────────────────────────────────────────
        if health >= 80:   hcolor = "#16a34a"
        elif health >= 60: hcolor = "#d97706"
        elif health >= 40: hcolor = "#ea580c"
        else:              hcolor = "#dc2626"

        # ── KPI cards ─────────────────────────────────────────────────────────
        p99_v  = p.get("p99", 0)
        fgc_n  = stats.get("full_gc_count", 0)
        kpi_rows = [
            ("Throughput",    f"{thru}",          "%",
             "danger" if thru < 90 else "warn" if thru < 95 else "ok"),
            ("Total Events",  str(stats.get("total_events", 0)), "events", ""),
            ("Full GC",       str(fgc_n),          "events",
             "danger" if fgc_n > 0 else "ok"),
            ("p99 Pause",     str(p99_v),           "ms",
             "danger" if p99_v > 500 else "warn" if p99_v > 200 else "ok"),
            ("Max Pause",     str(p.get("max", 0)), "ms",
             "warn" if p.get("max", 0) > 200 else ""),
            ("Heap -Xmx",     str(h.get("configured", 0)), "MB", ""),
        ]
        kpi_html = '<div class="kpi-grid">\n'
        for label, val, unit, cls in kpi_rows:
            kpi_html += (
                f'<div class="kpi-card {cls}">'
                f'<div class="kpi-label">{_html.escape(label)}</div>'
                f'<div class="kpi-value">{_html.escape(val)}</div>'
                f'<div class="kpi-unit">{_html.escape(unit)}</div>'
                f'</div>\n'
            )
        kpi_html += '</div>\n'

        # ── Recommendation cards ──────────────────────────────────────────────
        recs_html = '<div class="recs-list">\n'
        for rec in recs:
            sev = "ok"
            for tag in ("CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO"):
                if rec.startswith(f"[{tag}]"):
                    sev = tag.lower()
                    break
            text = re.sub(r'^\[\w+\]\s*', '', rec)
            recs_html += (
                f'<div class="rec-card {sev}">'
                f'<span class="rec-badge {sev}">{sev.upper()}</span>'
                f'<span class="rec-text">{_html.escape(text)}</span>'
                f'</div>\n'
            )
        recs_html += '</div>\n'

        # ── Top pauses table ──────────────────────────────────────────────────
        top = sorted(self.events, key=lambda e: e.pause_ms, reverse=True)[:top_n]
        tbl = (
            f'<div class="table-card">'
            f'<h2>Top {top_n} Longest Pauses</h2>'
            '<table><tr><th>Uptime (s)</th><th>GC Type</th><th>Pause (ms)</th>'
            '<th>Heap Before</th><th>Heap After</th><th>Full GC</th></tr>\n'
        )
        for e in top:
            rc = "full-gc-row" if e.is_full else ""
            pc = "pause-hi" if e.pause_ms > 500 else ""
            tbl += (
                f'<tr class="{rc}">'
                f'<td>{e.uptime_ms/1000:.3f}</td>'
                f'<td>{_html.escape(e.gc_type[:55])}</td>'
                f'<td class="{pc}">{e.pause_ms:.2f}</td>'
                f'<td>{e.heap_before_mb:.1f}M</td>'
                f'<td>{e.heap_after_mb:.1f}M</td>'
                f'<td>{"&#x2716;" if e.is_full else ""}</td>'
                f'</tr>\n'
            )
        tbl += '</table></div>\n'

        # ── GC causes table ───────────────────────────────────────────────────
        causes    = stats.get("gc_causes", {})
        cause_tbl = ""
        if causes:
            cause_tbl = (
                '<div class="table-card">'
                '<h2>GC Cause Breakdown</h2>'
                '<table><tr><th>Cause</th><th>Count</th></tr>\n'
            )
            for cause, cnt in causes.items():
                cause_tbl += f'<tr><td>{_html.escape(cause)}</td><td>{cnt}</td></tr>\n'
            cause_tbl += '</table></div>\n'

        # ── Additional findings table ─────────────────────────────────────────
        findings = {}
        if stats.get("evacuation_failure_count"):
            findings["Evacuation Failures"] = stats["evacuation_failure_count"]
        if stats.get("to_space_exhaustion_count"):
            findings["To-Space Exhaustion"] = stats["to_space_exhaustion_count"]
        if stats.get("sys_gc_count"):
            findings["Explicit System.gc() Calls"] = stats["sys_gc_count"]
        if stats.get("meta_gc_threshold_count"):
            findings["Metadata GC Threshold Triggers"] = stats["meta_gc_threshold_count"]
        if stats.get("humongous_max_regions"):
            findings["Humongous Regions (peak)"] = stats["humongous_max_regions"]
        if stats.get("heap_trend_mb_per_min"):
            findings["Heap Growth Trend"] = f"{stats['heap_trend_mb_per_min']} MB/min"
        if stats.get("pause_trend_ms_per_min"):
            findings["Pause Trend"] = f"{stats['pause_trend_ms_per_min']} ms/min"
        if stats.get("concurrent_mark_cycles"):
            findings["Concurrent Mark Cycles"] = stats["concurrent_mark_cycles"]

        findings_html = ""
        if findings:
            findings_html = (
                '<div class="table-card">'
                '<h2>Additional Findings</h2>'
                '<table><tr><th>Metric</th><th>Value</th></tr>\n'
            )
            for k, v in findings.items():
                findings_html += f'<tr><td>{_html.escape(k)}</td><td>{_html.escape(str(v))}</td></tr>\n'
            findings_html += '</table></div>\n'

        # ── JVM Parameters section ────────────────────────────────────────────
        detected = stats.get("detected_params", {})
        tuning   = stats.get("tuning_params", [])

        detected_tbl = (
            '<div class="table-card" style="margin-bottom:0">'
            '<h2>Detected from Log</h2>'
            '<table><tr><th>Parameter</th><th>Value</th></tr>\n'
        )
        for k, v in detected.items():
            detected_tbl += (
                f'<tr><td class="flag-cell">{_html.escape(k)}</td>'
                f'<td>{_html.escape(str(v))}</td></tr>\n'
            )
        detected_tbl += '</table></div>'

        tuning_tbl = (
            '<div class="table-card" style="margin-bottom:0">'
            '<h2>Recommended Tuning Flags</h2>'
            '<table><tr><th>Severity</th><th>Category</th>'
            '<th>Flag / Action</th><th>Why</th></tr>\n'
        )
        for t in tuning:
            sev = t["severity"].lower()
            tuning_tbl += (
                f'<tr>'
                f'<td><span class="sev {sev}">{t["severity"]}</span></td>'
                f'<td>{_html.escape(t["category"])}</td>'
                f'<td class="flag-cell">{_html.escape(t["flag"])}</td>'
                f'<td style="font-size:.83rem;color:#475569">{_html.escape(t["reason"])}</td>'
                f'</tr>\n'
            )
        tuning_tbl += '</table></div>'

        params_html = (
            '<div class="section-title">JVM Parameters</div>'
            '<div class="params-grid">'
            + detected_tbl
            + tuning_tbl
            + '</div>\n'
        )

        # ── Header ────────────────────────────────────────────────────────────
        jdk_label = f"JDK {jdk}" if jdk else "Unknown"
        ts_now    = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

        header_html = (
            '<div class="header">'
            '<div>'
            '<h1>JVM GC Log Analysis</h1>'
            '<div class="header-meta">'
            f'<span>&#128196; {_html.escape(filename or "stdin")}</span>'
            f'<span>JDK: {_html.escape(jdk_label)}</span>'
            f'<span>Collector: {_html.escape(col)}</span>'
            f'<span>Format: {_html.escape(stats.get("log_format",""))}</span>'
            f'<span>Events: {stats.get("total_events",0)}</span>'
            f'<span>Span: {stats.get("time_span_sec",0)}s</span>'
            f'<span>Generated: {ts_now}</span>'
            '</div>'
            '</div>'
            '</div>\n'
        )

        charts_html = (
            '<div class="charts-grid">'
            '<div class="chart-card"><h2>GC Pause Timeline</h2>'
            '<div class="chart-container"><canvas id="chartPause"></canvas></div></div>'
            '<div class="chart-card"><h2>Heap Evolution (MB)</h2>'
            '<div class="chart-container"><canvas id="chartHeap"></canvas></div></div>'
            '<div class="chart-card"><h2>Pause Distribution</h2>'
            '<div class="chart-container"><canvas id="chartDist"></canvas></div></div>'
            '<div class="chart-card"><h2>GC Type Breakdown</h2>'
            '<div class="chart-container"><canvas id="chartTypes"></canvas></div></div>'
            '</div>\n'
        )

        # ── Assemble ──────────────────────────────────────────────────────────
        parts = [
            '<!DOCTYPE html><html lang="en"><head>',
            '<meta charset="UTF-8">',
            '<meta name="viewport" content="width=device-width,initial-scale=1">',
            f'<title>GC Report — {_html.escape(filename or "analysis")}</title>',
            '<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js">'
            '</script>',
            _HTML_CSS,
            '</head><body><div class="page">',
            header_html,
            kpi_html,
            charts_html,
            params_html,
            '<div class="section-title">Recommendations</div>',
            recs_html,
            findings_html,
            cause_tbl,
            tbl,
            '<div class="footer">Generated by gc_log_analyzer.py</div>',
            '</div>',
            '<script id="gc-chart-data" type="application/json">',
            json.dumps(chart_data, ensure_ascii=False),
            '</script>',
            _HTML_CHARTS_JS,
            '</body></html>',
        ]

        html_content = "".join(parts)
        with open(output_path, "w", encoding="utf-8") as f:
            f.write(html_content)
        return output_path


# ── CLI ───────────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(
        description=(
            "Analyze JVM GC logs — JDK 7-21+\n"
            "Collectors: G1GC, CMS, ParallelGC, SerialGC, ZGC, GenZGC, Shenandoah\n"
            "Formats:    JDK 7/8 legacy (-XX:+PrintGCDetails)\n"
            "            JDK 9+ unified (-Xlog:gc*)"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("files", nargs="+", help="GC log file(s)")
    ap.add_argument("--json",       action="store_true", help="Output raw JSON stats")
    ap.add_argument("--html",       action="store_true", help="Generate HTML report")
    ap.add_argument("--html-out",   metavar="PATH",      help="HTML output path (default: <input>.html)")
    ap.add_argument("--top-pauses", type=int, default=10, metavar="N",
                    help="Show top N longest pauses in text/HTML report (default: 10)")
    args = ap.parse_args()

    for path in args.files:
        if not os.path.exists(path):
            print(f"File not found: {path}", file=sys.stderr)
            continue

        az    = GCLogAnalyzer()
        az.parse_file(path)
        stats = az.analyze()

        if args.json:
            print(json.dumps(stats, indent=2))
        else:
            print(f"\nAnalyzing: {path}")
            print(az.report(stats))

            if args.top_pauses and az.events:
                top = sorted(az.events, key=lambda e: e.pause_ms, reverse=True)[:args.top_pauses]
                print(f"\n── Top {args.top_pauses} longest pauses " + "─" * 40)
                for e in top:
                    heap = (f"  {e.heap_before_mb:.0f}M->{e.heap_after_mb:.0f}M"
                            if e.heap_before_mb else "")
                    print(f"  {e.pause_ms:>9.2f}ms  {e.gc_type[:48]:<50}{heap}")

        if args.html or args.html_out:
            out = args.html_out or (os.path.splitext(path)[0] + ".html")
            az.generate_html(stats, out, filename=os.path.basename(path),
                             top_n=args.top_pauses)
            print(f"HTML report: {out}")


if __name__ == "__main__":
    main()
