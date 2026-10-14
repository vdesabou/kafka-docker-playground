#!/usr/bin/env python3
"""
JVM thread dump analyzer — used by playground analyze thread-dump

Input  : jstack / jcmd Thread.print / kill -3 output (container logs included: log lines interleaved with the
         dump are ignored), JDK 8 to 25. A file may hold several dumps; several files (or folders, .gz) may be
         given. Dumps are ordered by their timestamp.
Output : thread states and pools, lock contention (monitors and java.util.concurrent locks), deadlocks, identical
         stacks, and with 2+ dumps of the same JVM: threads stuck on the same frames, CPU used by each thread
         between dumps, growing thread pools. Kafka / Connect aware (task threads, herder, request handlers).

Exit codes : 0 analysis done, 2 no thread dump found, 1 usage error.
"""

import argparse
import glob
import gzip
import html as _html
import json
import math
import os
import re
import sys
from collections import defaultdict, OrderedDict
from dataclasses import dataclass, field
from datetime import datetime
from typing import Dict, List, Optional, Tuple

SEVERITIES = ("CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO", "OK")

# ── Regex catalogue ───────────────────────────────────────────────────────────

_RE_DATE        = re.compile(r'^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)\s*$')
_RE_DUMP_START  = re.compile(r'Full thread dump (.*?):?\s*$')
_RE_THREAD      = re.compile(r'^"(?P<name>.*)"\s+(?P<rest>(?:#\d+|daemon|prio=|os_prio=|tid=|nid=|cpu=|\[).*)$')
_RE_STATE       = re.compile(r'^\s+java\.lang\.Thread\.State:\s+(?P<state>[A-Z_]+)(?:\s+\((?P<detail>[^)]*)\))?')
_RE_FRAME       = re.compile(r'^\s+at\s+(?P<frame>.+?)\s*$')
_RE_LOCK_LINE   = re.compile(r'^\s+-\s+(?P<kind>waiting to lock|locked|parking to wait for|waiting on|eliminated|waiting to re-lock in wait\(\))\s+<(?P<addr>0x[0-9a-f]+)>\s+\(a (?P<cls>[^)]+)\)')
_RE_OWNABLE     = re.compile(r'^\s+-\s+<(?P<addr>0x[0-9a-f]+)>\s+\(a (?P<cls>[^)]+)\)')
_RE_HEADER_ATTR = {
    "num":     re.compile(r'#(\d+)'),
    "prio":    re.compile(r'\bprio=(\d+)'),
    "cpu":     re.compile(r'\bcpu=([\d.]+)ms'),
    "elapsed": re.compile(r'\belapsed=([\d.]+)s'),
    "nid":     re.compile(r'\bnid=(0x[0-9a-f]+|\d+)'),
}
_RE_HEADER_STATE = re.compile(r'\bnid=\S+\s+(?P<s>[^\[]+?)\s*(?:\[0x[0-9a-f]+\])?\s*$')
_RE_DEADLOCK_START = re.compile(r'^Found one Java-level deadlock:')
_RE_DEADLOCK_END   = re.compile(r'^Found (?:\d+|a total of \d+) deadlocks?\.')
_RE_DL_THREAD      = re.compile(r'^"(?P<name>.*)":\s*$')
_RE_DL_HELD        = re.compile(r'which is held by "(?P<name>.*)"')
_RE_DUMP_END       = re.compile(r'^(JNI global refs|JNI global references|Heap\s*$|Threads class SMR info)')

# Frames where a RUNNABLE thread is idle (waiting for I/O or connections), not working
_IDLE_RUNNABLE = re.compile(
    r'EPoll\.wait|epollWait|EPollPort|KQueue\.(?:poll|keventPoll)|kevent0|Net\.poll|Net\.accept|socketAccept|accept0|'
    r'select0|poll0|WindowsSelectorImpl|SelectorImpl\.lockAndDoSelect|ServerSocketChannelImpl\.accept|'
    r'UnixDomainSockets\.accept|Process\.waitFor|ProcessImpl\.waitForProcessExit|ProcessHandleImpl\.waitForProcessExit0|'
    r'FileDispatcherImpl\.read0.*System\.in|Signal\.dispatch|signalDispatcherThread|Reference\.waitForReferencePendingList|'
    r'ReferenceQueue\.remove|jdk\.internal\.misc\.Unsafe\.park')

_JDK_PREFIXES = ("java.", "javax.", "jdk.", "sun.", "com.sun.", "kotlin.", "scala.runtime.")

# Kafka / Connect thread names
_RE_CONNECT_TASK   = re.compile(r'^task-thread-(?P<connector>.+)-(?P<task>\d+)$')
_RE_CONNECT_HERDER = re.compile(r'^DistributedHerder-')
_RE_REQ_HANDLER    = re.compile(r'^data-plane-kafka-request-handler-\d+$|^kafka-request-handler-\d+$')

# ── HTML/CSS (same look as analyze gc-logs) ────────────────────────────────────────

_HTML_CSS = """<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#f1f5f9;color:#1e293b;line-height:1.5}
.page{max-width:1300px;margin:0 auto;padding:24px}
h1{font-size:1.55rem;font-weight:700}
h2{font-size:1.05rem;font-weight:600;margin-bottom:12px;color:#334155}
.header{background:linear-gradient(135deg,#1e3a5f 0%,#2563eb 100%);color:#fff;border-radius:12px;padding:22px 28px;margin-bottom:22px}
.header-meta{font-size:.83rem;opacity:.85;margin-top:6px}
.header-meta span{margin-right:18px}
.kpi-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(175px,1fr));gap:14px;margin-bottom:22px}
.kpi-card{background:#fff;border-radius:10px;padding:14px 16px;box-shadow:0 1px 3px rgba(0,0,0,.07);border-left:4px solid #2563eb}
.kpi-card.warn{border-left-color:#d97706}.kpi-card.danger{border-left-color:#dc2626}.kpi-card.ok{border-left-color:#16a34a}
.kpi-label{font-size:.75rem;color:#64748b;text-transform:uppercase;letter-spacing:.05em}
.kpi-value{font-size:1.75rem;font-weight:700;margin:3px 0 2px}
.kpi-unit{font-size:.73rem;color:#94a3b8}
.charts-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(560px,1fr));gap:18px;margin-bottom:22px}
.chart-card{background:#fff;border-radius:10px;padding:18px 20px;box-shadow:0 1px 3px rgba(0,0,0,.07)}
.chart-card svg{width:100%;height:auto}
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
tr:hover td{background:#f8fafc}
.mono{font-family:'SFMono-Regular',Consolas,'Liberation Mono',Menlo,monospace;font-size:.78rem;word-break:break-all}
pre{font-family:'SFMono-Regular',Consolas,Menlo,monospace;font-size:.76rem;background:#f8fafc;padding:10px;border-radius:6px;overflow-x:auto;white-space:pre}
details summary{cursor:pointer;font-weight:600;font-size:.86rem;padding:6px 0}
.st{display:inline-block;font-size:.68rem;font-weight:700;padding:1px 7px;border-radius:12px}
.st.RUNNABLE{background:#dcfce7;color:#15803d}.st.BLOCKED{background:#fee2e2;color:#dc2626}
.st.WAITING{background:#dbeafe;color:#1d4ed8}.st.TIMED_WAITING{background:#e0e7ff;color:#4338ca}.st.OTHER{background:#f1f5f9;color:#475569}
.warn-box{background:#fff7ed;border-left:5px solid #ea580c;border-radius:8px;padding:12px 16px;margin-bottom:22px;font-size:.88rem}
.footer{text-align:center;font-size:.78rem;color:#94a3b8;padding:14px}
</style>"""

STATE_COLORS = OrderedDict([("RUNNABLE", "#22c55e"), ("BLOCKED", "#dc2626"), ("WAITING", "#3b82f6"),
                            ("TIMED_WAITING", "#8b5cf6"), ("OTHER", "#94a3b8")])


# ── Data ──────────────────────────────────────────────────────────────────────

@dataclass
class ThreadInfo:
    name: str
    num: Optional[int] = None
    daemon: bool = False
    nid: str = ""
    cpu_ms: Optional[float] = None
    elapsed_s: Optional[float] = None
    header_state: str = ""
    state: str = ""                       # java.lang.Thread.State, "" for VM / GC threads
    state_detail: str = ""
    frames: List[str] = field(default_factory=list)
    locks: List[Tuple[str, str, str]] = field(default_factory=list)    # (kind, addr, class) in stack order
    owned_sync: List[Tuple[str, str]] = field(default_factory=list)    # ownable synchronizers (j.u.c locks)

    @property
    def is_java(self) -> bool:
        return bool(self.state)

    @property
    def key(self) -> str:
        return f"{self.name}|{self.nid}"

    def state_bucket(self) -> str:
        return self.state if self.state in STATE_COLORS else "OTHER"

    def waiting_lock(self) -> Optional[Tuple[str, str]]:
        for kind, addr, cls in self.locks:
            if kind in ("waiting to lock", "waiting to re-lock in wait()"):
                return addr, cls
        return None

    def parking_on(self) -> Optional[Tuple[str, str]]:
        for kind, addr, cls in self.locks:
            if kind == "parking to wait for":
                return addr, cls
        return None

    def held_monitors(self) -> List[Tuple[str, str]]:
        return [(a, c) for k, a, c in self.locks if k == "locked"] + self.owned_sync

    def top_app_frame(self) -> str:
        for f in self.frames:
            if not f.startswith(_JDK_PREFIXES):
                return f
        return self.frames[0] if self.frames else ""

    def is_idle(self) -> bool:
        """Waiting for work: parked / waiting / sleeping, or RUNNABLE in a native poll / accept"""
        if self.state in ("WAITING", "TIMED_WAITING"):
            return True
        if self.state == "RUNNABLE" and self.frames and _IDLE_RUNNABLE.search(" ".join(self.frames[:3])):
            return True
        return not self.is_java

    def stack_signature(self, depth: int = 8) -> str:
        return self.state + "\n" + "\n".join(self.frames[:depth])


@dataclass
class Dump:
    index: int = 0
    source: str = ""
    line: int = 0
    timestamp: Optional[datetime] = None
    jvm: str = ""
    threads: List[ThreadInfo] = field(default_factory=list)
    jvm_deadlocks: List[List[str]] = field(default_factory=list)

    def label(self) -> str:
        ts = self.timestamp.strftime("%H:%M:%S") if self.timestamp else f"#{self.index}"
        return f"dump {self.index} ({ts})"


# ── Parsing ───────────────────────────────────────────────────────────────────

def _read_lines(path: str) -> List[str]:
    opener = gzip.open if path.endswith(".gz") else open
    with opener(path, "rt", errors="replace") as fh:
        return [l.rstrip("\n").rstrip("\r") for l in fh]


def expand_inputs(paths: List[str]) -> Tuple[List[str], List[str]]:
    files, errors = [], []
    for p in paths:
        if os.path.isdir(p):
            found = sorted(f for f in glob.glob(os.path.join(p, "**", "*"), recursive=True)
                           if os.path.isfile(f) and not f.endswith((".html", ".json")))
            if not found:
                errors.append(f"No file found in folder {p}")
            files.extend(found)
        elif os.path.isfile(p):
            files.append(p)
        else:
            errors.append(f"File not found: {p}")
    return files, errors


def parse_file(path: str) -> List[Dump]:
    lines = _read_lines(path)
    dumps: List[Dump] = []
    cur: Optional[Dump] = None
    thread: Optional[ThreadInfo] = None
    pending_date: Optional[datetime] = None
    in_deadlock = False
    dl_cycle: List[str] = []
    in_ownable = False

    def close_thread():
        nonlocal thread
        if cur is not None and thread is not None:
            cur.threads.append(thread)
        thread = None

    for no, line in enumerate(lines, 1):
        md = _RE_DATE.match(line)
        if md:
            try:
                pending_date = datetime.strptime(md.group(1), "%Y-%m-%d %H:%M:%S")
            except ValueError:
                pending_date = None
            continue
        ms = _RE_DUMP_START.search(line)
        if ms and line.lstrip().startswith("Full thread dump"):
            close_thread()
            cur = Dump(source=os.path.basename(path), line=no, timestamp=pending_date, jvm=ms.group(1))
            dumps.append(cur)
            pending_date = None
            in_deadlock = False
            continue

        if in_deadlock:
            if _RE_DEADLOCK_END.match(line):
                in_deadlock = False
                if dl_cycle and cur is not None:
                    cur.jvm_deadlocks.append(dl_cycle)
                dl_cycle = []
                continue
            if _RE_DEADLOCK_START.match(line):
                if dl_cycle and cur is not None:
                    cur.jvm_deadlocks.append(dl_cycle)
                dl_cycle = []
                continue
            if line.startswith("Java stack information"):
                if dl_cycle and cur is not None:
                    cur.jvm_deadlocks.append(dl_cycle)
                dl_cycle = []
                continue
            mt = _RE_DL_THREAD.match(line)
            if mt and mt.group("name") not in dl_cycle and not any(mt.group("name") in c for c in (cur.jvm_deadlocks if cur else [])):
                dl_cycle.append(mt.group("name"))
            continue

        if _RE_DEADLOCK_START.match(line):
            close_thread()
            in_deadlock = True
            dl_cycle = []
            continue

        mth = _RE_THREAD.match(line)
        if mth:
            close_thread()
            if cur is None:
                # thread lines without a "Full thread dump" header: one dump for the whole file
                cur = Dump(source=os.path.basename(path), line=no, timestamp=pending_date)
                dumps.append(cur)
            rest = mth.group("rest")
            thread = ThreadInfo(name=mth.group("name"), daemon=" daemon " in f" {rest} ")
            for k, rx in _RE_HEADER_ATTR.items():
                m = rx.search(rest)
                if not m:
                    continue
                if k == "num":
                    thread.num = int(m.group(1))
                elif k == "cpu":
                    thread.cpu_ms = float(m.group(1))
                elif k == "elapsed":
                    thread.elapsed_s = float(m.group(1))
                elif k == "nid":
                    thread.nid = m.group(1)
            mhs = _RE_HEADER_STATE.search(rest)
            if mhs:
                thread.header_state = mhs.group("s").strip()
            in_ownable = False
            continue

        if thread is None:
            continue
        if not line.strip():
            in_ownable = False
            continue
        m = _RE_STATE.match(line)
        if m:
            thread.state, thread.state_detail = m.group("state"), m.group("detail") or ""
            continue
        m = _RE_FRAME.match(line)
        if m:
            thread.frames.append(m.group("frame"))
            continue
        m = _RE_LOCK_LINE.match(line)
        if m:
            thread.locks.append((m.group("kind"), m.group("addr"), m.group("cls")))
            continue
        if "Locked ownable synchronizers:" in line:
            in_ownable = True
            continue
        if in_ownable:
            m = _RE_OWNABLE.match(line)
            if m:
                thread.owned_sync.append((m.group("addr"), m.group("cls")))
            continue
        if _RE_DUMP_END.match(line):
            close_thread()
            continue
        # anything else (interleaved application log lines) is ignored
    close_thread()
    if in_deadlock and dl_cycle and cur is not None:
        cur.jvm_deadlocks.append(dl_cycle)
    return [d for d in dumps if d.threads]


# ── Analysis ──────────────────────────────────────────────────────────────────

def pool_name(name: str) -> str:
    """'pool-3-thread-12' -> 'pool-#-thread-#', 'kafka-producer-network-thread | producer-12' -> '… | producer-#'"""
    return re.sub(r'\d+', '#', name)


def lock_contention(d: Dump) -> List[dict]:
    owners: Dict[str, ThreadInfo] = {}
    for t in d.threads:
        for addr, _ in t.held_monitors():
            owners.setdefault(addr, t)
    waits: Dict[str, dict] = {}
    for t in d.threads:
        target = t.waiting_lock() if t.state == "BLOCKED" else None
        kind = "monitor"
        if not target and t.state in ("WAITING", "TIMED_WAITING"):
            p = t.parking_on()
            if p and p[0] in owners and owners[p[0]] is not t:
                target, kind = p, "j.u.c lock"
        if not target:
            continue
        addr, cls = target
        w = waits.setdefault(addr, {"addr": addr, "class": cls, "kind": kind, "waiters": [], "owner": None})
        w["waiters"].append(t.name)
    out = []
    for addr, w in waits.items():
        o = owners.get(addr)
        if o:
            w["owner"] = {"name": o.name, "state": o.state or o.header_state, "frame": o.top_app_frame()}
        w["count"] = len(w["waiters"])
        out.append(w)
    out.sort(key=lambda x: -x["count"])
    return out


def find_deadlocks(d: Dump) -> List[List[str]]:
    """Cycles in the wait-for graph (thread -> owner of the lock it waits for), plus the JVM's own report"""
    owners: Dict[str, str] = {}
    for t in d.threads:
        for addr, _ in t.held_monitors():
            owners.setdefault(addr, t.name)
    edges: Dict[str, str] = {}
    for t in d.threads:
        target = t.waiting_lock() if t.state == "BLOCKED" else (t.parking_on() if t.state == "WAITING" else None)
        if target and target[0] in owners and owners[target[0]] != t.name:
            edges[t.name] = owners[target[0]]
    cycles, seen = [], set()
    for start in edges:
        path, node = [], start
        while node in edges and node not in path:
            path.append(node)
            node = edges[node]
        if node in path:
            cyc = path[path.index(node):]
            k = frozenset(cyc)
            if k not in seen:
                seen.add(k)
                cycles.append(cyc)
    for c in d.jvm_deadlocks:
        if frozenset(c) not in seen:
            seen.add(frozenset(c))
            cycles.append(c)
    return cycles


def identical_stacks(d: Dump, top: int) -> List[dict]:
    groups: Dict[str, List[ThreadInfo]] = defaultdict(list)
    for t in d.threads:
        if t.is_java and t.frames:
            groups[t.stack_signature()].append(t)
    out = []
    for sig, ts in sorted(groups.items(), key=lambda x: -len(x[1])):
        if len(ts) < 2:
            break
        out.append({"count": len(ts), "state": ts[0].state, "frames": ts[0].frames[:12],
                    "threads": [t.name for t in ts[:8]], "idle": ts[0].is_idle()})
        if len(out) >= top:
            break
    return out


def _interval_seconds(a: Dump, b: Dump) -> Optional[float]:
    """Seconds between two dumps: from a long-lived thread's elapsed= (precise), else from the timestamps"""
    ea = {t.key: t.elapsed_s for t in a.threads if t.elapsed_s is not None}
    for t in b.threads:
        if t.elapsed_s is not None and t.key in ea:
            delta = t.elapsed_s - ea[t.key]
            if delta > 0:
                return delta
    if a.timestamp and b.timestamp:
        s = (b.timestamp - a.timestamp).total_seconds()
        return s if s > 0 else None
    return None


def same_jvm(a: Dump, b: Dump) -> bool:
    ka = {t.key for t in a.threads if t.nid}
    kb = {t.key for t in b.threads if t.nid}
    return bool(ka) and len(ka & kb) >= 0.3 * min(len(ka), len(kb))


def analyze(dumps: List[Dump], top: int) -> dict:
    last = dumps[-1]
    res: dict = {"dumps": [], "findings": []}
    for d in dumps:
        states = defaultdict(int)
        for t in d.threads:
            states[t.state_bucket()] += 1
        res["dumps"].append({
            "index": d.index, "source": d.source, "line": d.line,
            "timestamp": d.timestamp.isoformat(sep=" ") if d.timestamp else None, "jvm": d.jvm,
            "threads": len(d.threads), "java_threads": sum(1 for t in d.threads if t.is_java),
            "daemon": sum(1 for t in d.threads if t.daemon), "states": dict(states),
        })

    # pools (latest dump) and their evolution
    pools: Dict[str, dict] = OrderedDict()
    for t in last.threads:
        p = pools.setdefault(pool_name(t.name), {"pool": pool_name(t.name), "count": 0, "states": defaultdict(int)})
        p["count"] += 1
        p["states"][t.state_bucket()] += 1
    if len(dumps) > 1:
        for p in pools.values():
            p["history"] = [sum(1 for t in d.threads if pool_name(t.name) == p["pool"]) for d in dumps]
    res["pools"] = sorted(({**p, "states": dict(p["states"])} for p in pools.values()), key=lambda x: -x["count"])

    res["contention"] = lock_contention(last)
    res["deadlocks"] = []
    for d in dumps:
        for cyc in find_deadlocks(d):
            if not any(set(cyc) == set(x["threads"]) for x in res["deadlocks"]):
                by_name = {t.name: t for t in d.threads}
                res["deadlocks"].append({"dump": d.index, "threads": cyc, "frames": {
                    n: by_name[n].frames[:6] for n in cyc if n in by_name}})
    res["identical_stacks"] = identical_stacks(last, top)

    # CPU (cumulative in the latest dump, and per interval between consecutive dumps of the same JVM)
    cpu_threads = [t for t in last.threads if t.cpu_ms is not None]
    res["cpu_top"] = [{"name": t.name, "cpu_ms": t.cpu_ms, "state": t.state or t.header_state, "frame": t.top_app_frame()}
                      for t in sorted(cpu_threads, key=lambda t: -t.cpu_ms)[:top]]
    res["cpu_interval"] = []
    res["stuck"] = []
    chain = [dumps[0]]
    for d in dumps[1:]:
        if same_jvm(chain[-1], d):
            chain.append(d)
    res["same_jvm_dumps"] = len(chain)
    if len(chain) >= 2:
        a, b = chain[0], chain[-1]
        secs = _interval_seconds(a, b)
        res["interval_s"] = round(secs, 1) if secs else None
        ca = {t.key: t.cpu_ms for t in a.threads if t.cpu_ms is not None}
        if secs:
            deltas = []
            for t in b.threads:
                if t.cpu_ms is not None and t.key in ca:
                    dm = t.cpu_ms - ca[t.key]
                    if dm >= 1:
                        deltas.append({"name": t.name, "cpu_ms": round(dm, 1), "cpu_pct": round(100 * dm / (secs * 1000), 1),
                                       "state": t.state or t.header_state, "frame": t.top_app_frame()})
            res["cpu_interval"] = sorted(deltas, key=lambda x: -x["cpu_ms"])[:top]
        # stuck: same thread, same top frames, not idle, in every dump of the chain
        maps = [{t.key: t for t in d.threads} for d in chain]
        for key, t in maps[-1].items():
            if not t.is_java or not t.frames or t.is_idle():
                continue
            if all(key in m and m[key].state == t.state and m[key].frames[:5] == t.frames[:5] for m in maps):
                busy = next((c for c in res["cpu_interval"] if c["name"] == t.name), None)
                res["stuck"].append({"name": t.name, "state": t.state, "frame": t.top_app_frame(),
                                     "frames": t.frames[:8], "cpu_pct": busy["cpu_pct"] if busy else 0.0})

    # Kafka / Connect
    tasks = []
    stuck_names = {s["name"] for s in res["stuck"]}
    for t in last.threads:
        m = _RE_CONNECT_TASK.match(t.name)
        if m:
            tasks.append({"connector": m.group("connector"), "task": int(m.group("task")), "name": t.name,
                          "state": t.state, "idle": t.is_idle(), "frame": t.top_app_frame(), "stuck": t.name in stuck_names})
    res["connect_tasks"] = sorted(tasks, key=lambda x: (x["connector"], x["task"]))
    res["herder"] = [{"name": t.name, "state": t.state, "frame": t.top_app_frame(), "stuck": t.name in stuck_names}
                     for t in last.threads if _RE_CONNECT_HERDER.match(t.name) and t.is_java]
    handlers = [t for t in last.threads if _RE_REQ_HANDLER.match(t.name)]
    if handlers:
        busy_per_dump = []
        for d in chain if len(chain) > 1 else [last]:
            hs = [t for t in d.threads if _RE_REQ_HANDLER.match(t.name)]
            busy_per_dump.append(sum(1 for t in hs if not t.is_idle()))
        res["request_handlers"] = {"count": len(handlers), "busy_per_dump": busy_per_dump}

    res["findings"] = findings(res, dumps)
    return res


def findings(res: dict, dumps: List[Dump]) -> List[dict]:
    out: List[dict] = []

    def add(sev, text):
        out.append({"severity": sev, "text": text})

    for dl in res["deadlocks"]:
        add("CRITICAL", f"Deadlock between {', '.join(dl['threads'])} (dump {dl['dump']}): each one waits for a lock "
                        "held by the next. These threads will never progress; only a restart frees them. Fix the lock "
                        "ordering in the code shown below (the top frames of each thread).")

    for c in res["contention"]:
        if c["count"] < 2:
            continue
        owner = c["owner"]
        own = (f"held by \"{owner['name']}\" ({owner['state']}, in {owner['frame']})" if owner
               else "owner not visible in the dump")
        add("HIGH" if c["count"] >= 5 else "MEDIUM",
            f"{c['count']} threads wait for the same {c['kind']} <{c['addr']}> ({c['class']}), {own}. "
            f"Waiting: {', '.join(c['waiters'][:6])}{'…' if c['count'] > 6 else ''}.")

    n = res["same_jvm_dumps"]
    if n >= 2:
        # threads already explained by a deadlock or a contended lock are not repeated one by one
        explained = {t for dl in res["deadlocks"] for t in dl["threads"]}
        explained |= {w for c in res["contention"] if c["count"] >= 2 for w in c["waiters"]}
        other_blocked = []
        for s in res["stuck"]:
            if _RE_CONNECT_TASK.match(s["name"]):
                sev, what = "HIGH", "Connect task thread"
            elif _RE_CONNECT_HERDER.match(s["name"]):
                sev, what = "HIGH", "Connect herder thread (rebalances and REST requests wait for it)"
            else:
                if s["state"] == "BLOCKED" and s["name"] not in explained:
                    other_blocked.append(s)
                continue  # busy RUNNABLE threads are reported by the CPU finding, not as stuck
            add(sev, f"{what} \"{s['name']}\" is {s['state']} on the same frames in all {n} dumps "
                     f"({res.get('interval_s', '?')}s apart), in {s['frame']}"
                     + (f", using {s['cpu_pct']}% of a CPU" if s["cpu_pct"] else ", using no CPU") + ".")
        if other_blocked:
            add("MEDIUM", f"{len(other_blocked)} thread(s) BLOCKED on the same frames in all {n} dumps: "
                          + "; ".join(f"\"{s['name']}\" in {s['frame']}" for s in other_blocked[:5])
                          + ("…" if len(other_blocked) > 5 else "") + ".")
        for c in res["cpu_interval"]:
            if c["cpu_pct"] >= 50:
                add("HIGH" if c["cpu_pct"] >= 80 else "MEDIUM",
                    f"Thread \"{c['name']}\" used {c['cpu_pct']}% of a CPU between the dumps ({c['state']}, in {c['frame']}).")
        for p in res["pools"]:
            h = p.get("history")
            if h and len(h) >= 2 and h[-1] - h[0] >= 10 and all(x <= y for x, y in zip(h, h[1:])):
                add("HIGH" if h[-1] - h[0] >= 50 else "MEDIUM",
                    f"Thread pool \"{p['pool']}\" grows across the dumps ({' -> '.join(map(str, h))}): threads are "
                    "created and never stopped (executor not shut down, client not closed).")
        rh = res.get("request_handlers")
        if rh and rh["busy_per_dump"] and min(rh["busy_per_dump"]) >= rh["count"]:
            add("HIGH", f"All {rh['count']} broker request handler threads are busy in every dump: the broker is "
                        "saturated (look at their frames: disk, locks, or num.io.threads too low).")
    else:
        add("INFO", "Single dump: take 3 dumps a few seconds apart to find stuck threads, CPU-hungry threads and growing "
                    "pools (playground analyze thread-dump --container <c> does it).")

    for t in res["connect_tasks"]:
        if t["state"] == "BLOCKED" and not t["stuck"]:
            add("MEDIUM", f"Connect task thread \"{t['name']}\" is BLOCKED in {t['frame']}.")
    total = res["dumps"][-1]["threads"]
    if total > 2000:
        add("MEDIUM", f"{total} threads in the JVM: check the biggest pools below.")
    if not out or all(f["severity"] == "INFO" for f in out):
        add("OK", "No deadlock, lock contention or stuck thread found.")
    order = {s: i for i, s in enumerate(SEVERITIES)}
    out.sort(key=lambda f: order.get(f["severity"], 9))
    return out


# ── Text report ───────────────────────────────────────────────────────────────

def text_report(res: dict, top: int) -> str:
    W = 78

    def hdr(t):
        return f"── {t} " + "─" * max(0, W - len(t) - 4)

    L = ["=" * W, "  JVM Thread Dump Analysis", "=" * W]
    L.append(f"  Dumps          : {len(res['dumps'])} ({res['same_jvm_dumps']} of the same JVM"
             + (f", {res['interval_s']}s apart in total" if res.get("interval_s") else "") + ")")
    L.append(f"  JVM            : {res['dumps'][-1]['jvm'] or '?'}")
    L += ["", hdr("Threads per dump")]
    for d in res["dumps"]:
        st = "  ".join(f"{k}={d['states'].get(k, 0)}" for k in STATE_COLORS if d["states"].get(k))
        L.append(f"  #{d['index']:<2} {d['timestamp'] or '':<19} {d['threads']:>5} threads  {st}   ({d['source']}:{d['line']})")

    L += ["", hdr("Findings")]
    for f in res["findings"]:
        L.append(f"  [{f['severity']}] {f['text']}")

    for dl in res["deadlocks"]:
        L += ["", hdr("Deadlock: " + " <-> ".join(dl["threads"]))[:W + 10]]
        for name, frames in dl["frames"].items():
            L.append(f"  \"{name}\"")
            L += [f"      at {f}" for f in frames]

    if res["contention"]:
        L += ["", hdr("Lock contention (latest dump)")]
        for c in res["contention"][:top]:
            o = c["owner"]
            L.append(f"  {c['count']:>3} waiting for <{c['addr']}> {c['class']}  owner: "
                     + (f"\"{o['name']}\" ({o['state']}) in {o['frame']}" if o else "?"))

    if res["stuck"]:
        L += ["", hdr(f"Same frames in all {res['same_jvm_dumps']} dumps (not idle)")]
        for s in res["stuck"][:top]:
            L.append(f"  {s['state']:<13} {s['name'][:40]:<40} cpu {s['cpu_pct']:>5}%  {s['frame'][:70]}")

    if res["cpu_interval"]:
        L += ["", hdr(f"CPU between the first and last dump ({res.get('interval_s')}s)")]
        for c in res["cpu_interval"][:top]:
            L.append(f"  {c['cpu_pct']:>6}%  {c['name'][:42]:<42} {c['state'][:13]:<13} {c['frame'][:60]}")
    elif res["cpu_top"]:
        L += ["", hdr("CPU since thread start (latest dump)")]
        for c in res["cpu_top"][:top]:
            L.append(f"  {c['cpu_ms']:>11.0f}ms  {c['name'][:42]:<42} {c['frame'][:60]}")
    else:
        L += ["", hdr("CPU"), "  Not in this dump (per-thread cpu= is printed from JDK 11 on)."]

    if res["connect_tasks"] or res["herder"]:
        L += ["", hdr("Kafka Connect")]
        for t in res["herder"]:
            L.append(f"  herder  {t['name'][:40]:<40} {t['state']:<13} {t['frame'][:70]}")
        for t in res["connect_tasks"]:
            flag = " STUCK" if t["stuck"] else (" idle" if t["idle"] else "")
            L.append(f"  task    {t['connector'][:30]:<30} #{t['task']:<3} {t['state']:<13}{flag:<7} {t['frame'][:70]}")
    rh = res.get("request_handlers")
    if rh:
        L += ["", hdr("Kafka broker"),
              f"  request handlers: {rh['count']}, busy per dump: {', '.join(map(str, rh['busy_per_dump']))}"]

    L += ["", hdr("Biggest thread pools (latest dump)")]
    for p in res["pools"][:top]:
        hist = f"  history {' -> '.join(map(str, p['history']))}" if p.get("history") and len(set(p["history"])) > 1 else ""
        st = " ".join(f"{k}={v}" for k, v in p["states"].items())
        L.append(f"  {p['count']:>4}  {p['pool'][:52]:<52} {st}{hist}")

    if res["identical_stacks"]:
        L += ["", hdr("Most common stacks (latest dump)")]
        for s in res["identical_stacks"][:5]:
            L.append(f"  {s['count']} threads {s['state']}{' (idle)' if s['idle'] else ''}: {', '.join(s['threads'][:4])}{'…' if s['count'] > 4 else ''}")
            L += [f"      at {f}" for f in s["frames"][:4]]
    L.append("=" * W)
    return "\n".join(L)


# ── HTML report ───────────────────────────────────────────────────────────────

def _e(s) -> str:
    return _html.escape(str(s), quote=True)


def svg_states(res: dict) -> str:
    dumps = res["dumps"]
    W, H, L, T, B = 560, 60 + 34 * len(dumps), 90, 30, 10
    pw = W - L - 20
    out = [f'<svg viewBox="0 0 {W} {H}" xmlns="http://www.w3.org/2000/svg">']
    x = L
    for k, c in STATE_COLORS.items():
        out.append(f'<rect x="{x}" y="6" width="10" height="10" fill="{c}"/><text x="{x + 14}" y="15" font-size="10">{k}</text>')
        x += 14 + 7 * len(k) + 14
    maxn = max(d["threads"] for d in dumps) or 1
    for i, d in enumerate(dumps):
        y = T + i * 34
        out.append(f'<text x="{L - 8}" y="{y + 16}" font-size="11" text-anchor="end">dump {d["index"]}</text>')
        x = L
        for k, c in STATE_COLORS.items():
            v = d["states"].get(k, 0)
            w = pw * v / maxn
            if w > 0:
                out.append(f'<rect x="{x:.1f}" y="{y}" width="{w:.1f}" height="22" fill="{c}"><title>{k}: {v}</title></rect>')
                if w > 22:
                    out.append(f'<text x="{x + w / 2:.1f}" y="{y + 15}" font-size="10" fill="#fff" text-anchor="middle">{v}</text>')
            x += w
        out.append(f'<text x="{x + 6:.1f}" y="{y + 15}" font-size="10" fill="#475569">{d["threads"]}</text>')
    out.append("</svg>")
    return "".join(out)


def svg_hbars(rows: List[Tuple[str, float, str]], unit: str) -> str:
    if not rows:
        return "<p>No data.</p>"
    W, rowh, L = 560, 22, 230
    H = 10 + rowh * len(rows)
    mx = max(v for _, v, _ in rows) or 1
    out = [f'<svg viewBox="0 0 {W} {H}" xmlns="http://www.w3.org/2000/svg">']
    for i, (lab, v, color) in enumerate(rows):
        y = 5 + i * rowh
        w = (W - L - 60) * v / mx
        out.append(f'<text x="{L - 6}" y="{y + 14}" font-size="10" text-anchor="end">{_e(lab[:38])}</text>'
                   f'<rect x="{L}" y="{y + 3}" width="{max(1, w):.1f}" height="15" fill="{color}"/>'
                   f'<text x="{L + w + 5:.1f}" y="{y + 14}" font-size="10" fill="#475569">{v:g}{unit}</text>')
    out.append("</svg>")
    return "".join(out)


def html_report(res: dict, title: str) -> str:
    last = res["dumps"][-1]
    n_block = last["states"].get("BLOCKED", 0)

    def kpi(label, val, unit, cls=""):
        return (f'<div class="kpi-card {cls}"><div class="kpi-label">{_e(label)}</div>'
                f'<div class="kpi-value">{_e(val)}</div><div class="kpi-unit">{_e(unit)}</div></div>')

    kpis = "".join([
        kpi("Dumps", len(res["dumps"]), f"{res['same_jvm_dumps']} same JVM"),
        kpi("Threads", last["threads"], f"{last['daemon']} daemon"),
        kpi("Blocked", n_block, "threads", "danger" if n_block else "ok"),
        kpi("Deadlocks", len(res["deadlocks"]), "cycles", "danger" if res["deadlocks"] else "ok"),
        kpi("Contended locks", sum(1 for c in res["contention"] if c["count"] >= 2), "locks", "warn" if any(c["count"] >= 2 for c in res["contention"]) else "ok"),
        kpi("Stuck", len(res["stuck"]), "same frames in all dumps" if res["same_jvm_dumps"] > 1 else "needs 2+ dumps",
            "warn" if res["stuck"] else ""),
    ])
    recs = "".join(f'<div class="rec-card {f["severity"].lower()}"><span class="rec-badge {f["severity"].lower()}">{_e(f["severity"])}</span>'
                   f'<span class="rec-text">{_e(f["text"])}</span></div>' for f in res["findings"])

    if res["cpu_interval"]:
        cpu_rows = [(c["name"], c["cpu_pct"], "#f97316") for c in res["cpu_interval"][:12]]
        cpu_title, cpu_unit = f"CPU between the first and last dump ({res.get('interval_s')}s)", "%"
    else:
        cpu_rows = [(c["name"], round(c["cpu_ms"] / 1000, 1), "#f97316") for c in res["cpu_top"][:12]]
        cpu_title, cpu_unit = "CPU since thread start (latest dump)", "s"
    pool_rows = [(p["pool"], p["count"], "#3b82f6") for p in res["pools"][:12]]
    charts = ("<div class='charts-grid'>"
              f"<div class='chart-card'><h2>Thread states per dump</h2>{svg_states(res)}</div>"
              f"<div class='chart-card'><h2>{_e(cpu_title)}</h2>{svg_hbars(cpu_rows, cpu_unit)}</div>"
              f"<div class='chart-card'><h2>Biggest thread pools</h2>{svg_hbars(pool_rows, '')}</div>"
              "</div>")

    def st(s):
        return f"<span class='st {_e(s if s in STATE_COLORS else 'OTHER')}'>{_e(s or 'VM')}</span>"

    sections = []
    for dl in res["deadlocks"]:
        body = "".join(f"<h2 style='margin-top:8px'>\"{_e(n)}\"</h2><pre>{_e(chr(10).join('at ' + f for f in fr))}</pre>"
                       for n, fr in dl["frames"].items())
        sections.append(f"<div class='table-card'><h2>💀 Deadlock: {_e(' ↔ '.join(dl['threads']))}</h2>{body}</div>")
    if res["contention"]:
        rows = "".join(f"<tr><td>{c['count']}</td><td class='mono'>&lt;{_e(c['addr'])}&gt; {_e(c['class'])}</td><td>{_e(c['kind'])}</td>"
                       f"<td>{(_e(c['owner']['name']) + ' ' + st(c['owner']['state']) + '<br><span class=mono>' + _e(c['owner']['frame']) + '</span>') if c['owner'] else '?'}</td>"
                       f"<td>{_e(', '.join(c['waiters'][:10]))}</td></tr>" for c in res["contention"][:20])
        sections.append("<div class='table-card'><h2>🔒 Lock contention (latest dump)</h2><table><tr><th>Waiting</th><th>Lock</th>"
                        f"<th>Kind</th><th>Owner</th><th>Waiting threads</th></tr>{rows}</table></div>")
    if res["stuck"]:
        rows = "".join(f"<tr><td>{_e(s['name'])}</td><td>{st(s['state'])}</td><td>{s['cpu_pct']}%</td>"
                       f"<td><details><summary class='mono'>{_e(s['frame'])}</summary><pre>{_e(chr(10).join(s['frames']))}</pre></details></td></tr>"
                       for s in res["stuck"][:30])
        sections.append(f"<div class='table-card'><h2>⏸️ Same frames in all {res['same_jvm_dumps']} dumps (not idle)</h2>"
                        f"<table><tr><th>Thread</th><th>State</th><th>CPU</th><th>Frames</th></tr>{rows}</table></div>")
    if res["connect_tasks"] or res["herder"]:
        rows = "".join(f"<tr><td>herder</td><td>{_e(t['name'])}</td><td>{st(t['state'])}{' <b>stuck</b>' if t['stuck'] else ''}</td><td class='mono'>{_e(t['frame'])}</td></tr>" for t in res["herder"])
        rows += "".join(f"<tr><td>{_e(t['connector'])} #{t['task']}</td><td>{_e(t['name'])}</td><td>{st(t['state'])}"
                        f"{' <b>stuck</b>' if t['stuck'] else ' idle' if t['idle'] else ''}</td><td class='mono'>{_e(t['frame'])}</td></tr>"
                        for t in res["connect_tasks"])
        sections.append(f"<div class='table-card'><h2>🔌 Kafka Connect</h2><table><tr><th>Connector / task</th><th>Thread</th><th>State</th><th>Top application frame</th></tr>{rows}</table></div>")
    if res["identical_stacks"]:
        items = "".join(f"<details><summary>{s['count']} threads {st(s['state'])}{' idle' if s['idle'] else ''} — {_e(', '.join(s['threads'][:4]))}{'…' if s['count'] > 4 else ''}</summary>"
                        f"<pre>{_e(chr(10).join('at ' + f for f in s['frames']))}</pre></details>" for s in res["identical_stacks"])
        sections.append(f"<div class='table-card'><h2>📚 Most common stacks (latest dump)</h2>{items}</div>")
    rows = "".join(f"<tr><td>{p['count']}</td><td class='mono'>{_e(p['pool'])}</td><td>{' '.join(st(k) + ' ' + str(v) for k, v in p['states'].items())}</td>"
                   f"<td>{_e(' → '.join(map(str, p['history']))) if p.get('history') else ''}</td></tr>" for p in res["pools"][:40])
    sections.append(f"<div class='table-card'><h2>🧵 Thread pools (latest dump)</h2><table><tr><th>Threads</th><th>Pool</th><th>States</th><th>Across dumps</th></tr>{rows}</table></div>")

    meta = [f"&#128196; {_e(title)}", f"JVM: {_e(last['jvm'] or '?')}", f"Dumps: {len(res['dumps'])}",
            f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"]
    return ("<!DOCTYPE html><html lang='en'><head><meta charset='UTF-8'><meta name='viewport' content='width=device-width,initial-scale=1'>"
            f"<title>Thread dump report — {_e(title)}</title>{_HTML_CSS}</head><body><div class='page'>"
            "<div class='header'><h1>JVM Thread Dump Analysis</h1><div class='header-meta'>"
            + "".join(f"<span>{m}</span>" for m in meta) + "</div></div>"
            + f"<div class='kpi-grid'>{kpis}</div>" + charts
            + "<div class='section-title'>Findings</div>" + f"<div class='recs-list'>{recs}</div>"
            + "".join(sections)
            + "<div class='footer'>Generated by playground analyze thread-dump (self-contained, no external resource)</div>"
            "</div></body></html>")


# ── CLI ───────────────────────────────────────────────────────────────────────

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="+", help="thread dump file(s) or folder(s)")
    ap.add_argument("--json", action="store_true", help="Output JSON")
    ap.add_argument("--html-out", metavar="PATH", help="Write a self-contained HTML report")
    ap.add_argument("--top", type=int, default=10, metavar="N", help="Rows per section (default: 10)")
    args = ap.parse_args()

    files, errors = expand_inputs(args.files)
    for e in errors:
        print(f"❌ {e}", file=sys.stderr)
    dumps: List[Dump] = []
    for f in files:
        try:
            dumps.extend(parse_file(f))
        except (OSError, EOFError) as e:
            print(f"❌ cannot read {f}: {e}", file=sys.stderr)
    if not dumps:
        msg = ("No thread dump found in " + ", ".join(os.path.basename(f) for f in files)
               + ". Expected jstack, jcmd Thread.print or kill -3 output (\"Full thread dump …\" and \"\\\"thread\\\" #12 …\" lines).")
        if args.json:
            print(json.dumps({"error": msg}, indent=2))
        else:
            print(f"❌ {msg}", file=sys.stderr)
        return 2

    if all(d.timestamp for d in dumps):
        dumps.sort(key=lambda d: d.timestamp)
    for i, d in enumerate(dumps, 1):
        d.index = i
    res = analyze(dumps, max(1, args.top))

    if args.json:
        print(json.dumps(res, indent=2, default=str))
    else:
        print(text_report(res, max(1, args.top)))
    if args.html_out:
        title = os.path.basename(files[0]) + (f" (+{len(files) - 1} files)" if len(files) > 1 else "")
        with open(args.html_out, "w", encoding="utf-8") as fh:
            fh.write(html_report(res, title))
        print(f"HTML report: {args.html_out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
