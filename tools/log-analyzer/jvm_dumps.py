#!/usr/bin/env python3
"""
🧵 🔬 The JVM dumps of the input of playground analyze logs (found by bundle_triage.py, .other_files):

- the thread dumps are analyzed right away, in this process, by tools/thread-analyzer/thread_dump_analyzer.py (pure python,
  a few hundred ms): deadlocks, lock contention, lock stalls, threads stuck in socket I/O, stuck threads, CPU per thread
  between dumps, growing pools. One group per command of the triage (the dumps of a folder) and per JVM (the dumps of 2
  Connect workers in one folder are 2 groups, each one compared with the dumps of its own JVM); its findings go to the
  log report, the dumps to its incident timeline, and the full thread report is written next to the log report.
- the heap dumps are not: Eclipse MAT runs in Docker and needs about as much memory as the dump. They are listed with the
  command to run, at the top of the report so that they are not missed.

Python 3.8, stdlib only.
"""

import os
import shlex
import sys
from typing import List, Optional, Tuple

HERE = os.path.dirname(os.path.abspath(__file__))
THREAD_ANALYZER = os.path.join(HERE, "..", "thread-analyzer")
REPORT_COMMON = os.path.join(HERE, "..", "report-common")

# the findings of a group shown in the log report (the full thread report has every one)
FINDINGS_SHOWN = 6
CPU_SHOWN = 5
# a thread dump file larger than this is not analyzed inline (a container log of several GB with a kill -3 in it): the
# command is given instead
MAX_INLINE_BYTES = 512 * 1024 * 1024


def _paths(of: dict, labels: List[str]) -> List[Tuple[str, str]]:
    """(label, path) of the files still on disk: the label of each path kept with it, whatever was skipped before"""
    out = []
    by_label = {f.get("label"): f for f in of.get("files") or []}
    for x in labels:
        f = by_label.get(x) or {}
        # the copy kept next to the report, else where analyze logs read it in this run (the tmp dir, with --json)
        p = next((c for c in (f.get("path"), f.get("read_path")) if c and os.path.isfile(c)), None)
        if p:
            out.append((x, p))
    return out


def _size(path: str) -> int:
    """the size of a dump once read: for a .gz, the uncompressed size of its trailer (modulo 4 GB, never less than the
    file), not the compressed one (a 50 MB .gz of thread dumps is 500 MB to parse)"""
    size = os.path.getsize(path)
    if path.endswith(".gz") and size >= 18:
        try:
            with open(path, "rb") as fh:
                fh.seek(-4, os.SEEK_END)
                return max(size, int.from_bytes(fh.read(4), "little"))
        except OSError:
            pass
    return size


def _import_analyzer():
    if THREAD_ANALYZER not in sys.path:
        sys.path.insert(0, THREAD_ANALYZER)
    import thread_dump_analyzer  # noqa: E402
    return thread_dump_analyzer


def _iso(ts) -> Optional[str]:
    return ts.strftime("%Y-%m-%dT%H:%M:%S") if ts else None


def thread_dumps(of: Optional[dict], html_dir: Optional[str] = None, stem: str = "report") -> List[dict]:
    """[{folder, files, command, dumps: [{index, time, file, line, threads, states}], same_jvm, interval_s, jvm,
    findings: [{severity, text}], cpu: [{name, cpu_pct, state, frame}], deadlocks, stuck, stalls, report (path of the full
    thread report, with html_dir), error}] for each thread dump command of the triage, one per JVM when its dumps are of
    several JVMs (then files and command are those of the JVM, and jvm_index, jvm_count are set)"""
    out: List[dict] = []
    if not of:
        return out
    cmds = [c for c in of.get("commands") or [] if c.get("kind") == "thread_dump"]
    if not cmds:
        return out
    try:
        tda = _import_analyzer()
    except Exception as ex:  # the analyzer missing from a sparse clone: the command stays in 🧰
        return [{"folder": c.get("folder") or "", "files": c.get("files") or [], "command": c.get("command") or "",
                 "error": f"thread analyzer not available: {ex}"} for c in cmds]
    pages = []  # (group, analysis, paths of its files): the full thread reports, written once the groups are known
    for c in cmds:
        base = {"folder": c.get("folder") or "", "files": c.get("files") or [], "command": c.get("command") or ""}
        g = dict(base)
        found = _paths(of, g["files"])
        paths = [p for _, p in found]
        if not paths:
            out.append({**g, "error": "the files are no longer on disk"})
            continue
        if sum(_size(p) for p in paths) > MAX_INLINE_BYTES:
            out.append({**g, "error": "too large to analyze inline: run the command"})
            continue
        dumps = []
        try:
            for p in paths:
                dumps.extend(tda.parse_file(p))
        except (OSError, EOFError, ValueError) as ex:
            out.append({**g, "error": f"cannot read: {ex}"})
            continue
        if not dumps:
            out.append({**g, "error": "no thread dump found in the files"})
            continue
        if all(d.timestamp for d in dumps):
            dumps.sort(key=lambda d: d.timestamp)
        for i, d in enumerate(dumps, 1):
            d.index = i
        # the dumps of several JVMs in one folder (2 Connect workers): one group per JVM, each one compared with the
        # earlier dumps of its own JVM (else the dumps of the second one are never compared with each other)
        jvms = tda.split_jvms(dumps) if hasattr(tda, "split_jvms") else [dumps]
        # the analyzer gives the file of a dump by its path or its name: back to its label in the input
        label_of = {p: x for x, p in found}
        label_of.update({os.path.basename(p): x for x, p in found})
        for j, jd in enumerate(jvms, 1):
            g = dict(base)
            out.append(g)
            try:
                res = tda.analyze(jd, 10)
            except Exception as ex:  # a dump the analyzer does not expect: never break the log report for it
                g["error"] = f"analysis failed: {ex}"
                continue
            mine = [x for x in g["files"] if x in {label_of.get(d.source, d.source) for d in jd}]
            if len(jvms) > 1:
                g["files"] = mine or g["files"]
                g["jvm_index"], g["jvm_count"] = j, len(jvms)
                by_label = {x: p for x, p in found}
                if base["command"] and all(by_label.get(x) for x in g["files"]) and not base["command"].endswith("first>"):
                    g["command"] = "playground analyze thread-dump" + "".join(f" -f {shlex.quote(by_label[x])}" for x in g["files"][:20])
            g["dumps"] = [{"index": d["index"], "time": (d.get("timestamp") or "").replace(" ", "T")[:19] or None,
                           "file": label_of.get(d.get("source"), os.path.basename(d.get("source") or "")), "line": d.get("line"),
                           "threads": d.get("threads"), "states": d.get("states") or {}} for d in res["dumps"]]
            g["jvm"] = next((d.get("jvm") for d in res["dumps"] if d.get("jvm")), None)
            if len(jvms) > 1:
                # which JVM: shown after the JVM version wherever the log report prints it
                names = [os.path.basename(x) for x in g["files"]]
                g["jvm"] = ((g["jvm"] + " · ") if g["jvm"] else "") + (
                    f"JVM {j} of {len(jvms)}: {', '.join(names[:3])}{f' (+{len(names) - 3})' if len(names) > 3 else ''}")
            g["same_jvm"] = res.get("same_jvm_dumps") or 1
            g["interval_s"] = res.get("interval_s")
            g["findings"] = [f for f in res.get("findings") or []][:FINDINGS_SHOWN]
            g["findings_total"] = len(res.get("findings") or [])
            g["cpu"] = [{k: x.get(k) for k in ("name", "cpu_pct", "state", "frame")} for x in (res.get("cpu_interval") or [])[:CPU_SHOWN]]
            g["deadlocks"] = len(res.get("deadlocks") or [])
            g["stuck"] = len(res.get("stuck") or [])
            g["stalls"] = len(res.get("stalls") or []) + len(res.get("stuck_io") or [])
            g["connect_tasks"] = [{k: t.get(k) for k in ("name", "state", "stuck")} for t in res.get("connect_tasks") or []]
            pages.append((g, res, [p for x, p in found if x in g["files"]] or paths))
    if html_dir:
        for n, (g, res, paths) in enumerate(pages, 1):
            path = os.path.join(html_dir, f"{stem}-thread-dumps{'' if len(pages) == 1 else '-' + str(n)}.html")
            try:
                title = os.path.basename(paths[0]) + (f" (+{len(paths) - 1} files)" if len(paths) > 1 else "")
                if g.get("jvm_count"):
                    title += f", JVM {g['jvm_index']} of {g['jvm_count']}"
                page = tda.html_report(res, title)
                try:
                    if REPORT_COMMON not in sys.path:
                        sys.path.insert(0, REPORT_COMMON)
                    import report_html  # noqa: E402
                    if hasattr(report_html, "with_share"):
                        page = report_html.with_share(page, summary=tda.text_report(res, 10),
                                                      command="playground analyze thread-dump")
                except Exception:
                    pass
                with open(path, "w", encoding="utf-8") as fh:
                    fh.write(page)
                g["report"] = path
            except Exception as ex:  # the page of a dump the analyzer does not expect: never break the log report for it
                g["error"] = f"cannot write the thread report: {ex}"
    return out


def heap_dumps(of: Optional[dict]) -> List[dict]:
    """[{file, bytes, command}] of the heap dumps of the triage: not analyzed here (MAT, Docker, memory)"""
    out: List[dict] = []
    if not of:
        return out
    size_of = {f.get("label"): f.get("bytes") for f in of.get("files") or []}
    for c in of.get("commands") or []:
        if c.get("kind") != "heap_dump":
            continue
        for label in c.get("files") or []:
            out.append({"file": label, "bytes": size_of.get(label), "command": c.get("command") or ""})
    return out


def timeline_events(groups: List[dict]) -> List[dict]:
    """one event per thread dump with a time: {time, file, line, text}"""
    out = []
    for g in groups:
        worst = next((f for f in g.get("findings") or [] if f.get("severity") in ("CRITICAL", "HIGH")), None)
        for n, d in enumerate(g.get("dumps") or []):
            if not d.get("time"):
                continue
            text = f"🧵 thread dump #{d['index']} ({d.get('threads') or 0} threads)"
            # the worst finding on the first dump of the group (of its JVM: #4 when the dumps of 2 JVMs are given)
            if worst and n == 0:
                text += f": {worst['severity']} {worst['text'].split(': ')[0].split('. ')[0]}"
            out.append({"time": d["time"], "file": d.get("file") or "", "line": d.get("line"), "text": text[:200]})
    return out
