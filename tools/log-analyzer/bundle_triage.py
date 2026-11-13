#!/usr/bin/env python3
"""
Bundle triage of playground analyze logs: the files of the input that another analyzer of the playground reads better
than the log digest (GC logs, thread dumps, heap dumps, flight recordings, network captures, Oracle XStream diagnostics
reports), each with the command to run on it; and the ones no analyzer reads (screenshots, the pictures of a Word
document, PDF, .doc / .xls / .pptx), with what to do instead.

Customers send them in the same zip as the logs: today the binary ones are counted as "binary files skipped", and a
GC log or a thread dump is only read as log lines.

Input: --walked FILE, label<tab>path of every file of the input (written by analyze logs while it walks the input,
archives extracted). A file extracted from an archive lives in the tmp dir of analyze logs, deleted at the end: with
--keep-dir it is copied there (moved when it is not a text file that the report links to), so the commands printed still
work after the run. Output: JSON on stdout,
  {"files": [{"label", "path", "kind", "bytes", "kept"}],
   "commands": [{"kind", "icon", "what", "folder", "files": [labels], "command"}]}
"""

import argparse
import gzip
import json
import mmap
import os
import re
import shlex
import shutil
import sys
from typing import Dict, List, Optional, Tuple

# kind -> (icon, what, playground command, several files in one command)
KINDS = {
    "gc_log": ("♻️", "GC log", "playground analyze gc-logs", True),
    "thread_dump": ("🧵", "thread dumps", "playground analyze thread-dump", True),
    "heap_dump": ("🔬", "heap dump", "playground analyze heap-dump", False),
    "flight_recording": ("🛩️", "flight recording", "playground analyze flight-recorder", False),
    "network_capture": ("🦈", "network capture", "playground analyze tcp-dump", False),
    "xstream_report": ("🅾️", "Oracle XStream diagnostics report", "playground analyze oracle-xstream-report", True),
    # read by analyze logs itself (cluster_layout.py: partitions and leaders per broker, disk per log dir): no command
    "topic_describe": ("🗺️", "kafka-topics --describe output", "", True),
    "log_dirs": ("💽", "kafka-log-dirs --describe output", "", True),
    # no analyzer reads them: what to do instead (command_of)
    "screenshot": ("🖼️", "screenshot / picture (not analyzed)", "open", True),
    "document": ("📄", "document (not analyzed)", "", False),
}
ORDER = list(KINDS)
# the kinds analyze logs reads itself (🗺️ Cluster layout of the report): not listed in 🧰 Other files
INLINE = ("topic_describe", "log_dirs")

SNIFF_BYTES = 64 * 1024
# a thread dump printed by kill -3 lands anywhere in the stdout of a container: the whole file is searched (mmap, a few
# GB/s) up to this size, the first MB of a .gz
SEARCH_BYTES = 2 * 1024 ** 3
GZ_SEARCH_BYTES = 1024 ** 2

GC_NAME = re.compile(r"(?:^|[-_.])gc(?:[-_.]|$)|gc\.log|garbage", re.I)
# unified JVM logging (-Xlog:gc*): "[2026-11-07T10:00:00.123+0000][info][gc] GC(12) Pause Young …", "[gc,start" …;
# legacy -XX:+PrintGCDetails: "[GC (Allocation Failure)", "[Full GC", "[GC pause (G1 Evacuation Pause)"
GC_CONTENT = re.compile(rb"\]\[gc[\],]|\[gc,[a-z]+ *\]|\bGC\(\d+\) (?:Pause|Concurrent)|\[(?:Full )?GC \(|\[GC pause \(|\[Full GC\b")
THREAD_DUMP = (b"Full thread dump ", b"java.lang.Thread.State: ")
# kafka-topics --describe: "\tTopic: orders\tPartition: 0\tLeader: 1\tReplicas: 1,2,3\tIsr: 1,2,3" (TopicId with recent versions)
TOPIC_DESCRIBE = re.compile(rb"(?m)^\s*Topic: *\S+\s+(?:TopicId: *\S+\s+)?Partition: *\d+\s+Leader: *\S+\s+Replicas: ")
# kafka-log-dirs --describe: {"brokers":[{"broker":1,"logDirs":[{"logDir":"/var/lib/kafka/data","error":null,"partitions":[…
LOG_DIRS = (b'"brokers"', b'"logDirs"')
PCAP_MAGIC = (b"\xd4\xc3\xb2\xa1", b"\xa1\xb2\xc3\xd4", b"\x4d\x3c\xb2\xa1", b"\xa1\xb2\x3c\x4d", b"\x0a\x0d\x0d\x0a")


def head(path: str, size: int = SNIFF_BYTES) -> bytes:
    try:
        if path.endswith(".gz"):
            with gzip.open(path, "rb") as fh:
                return fh.read(size)
        with open(path, "rb") as fh:
            return fh.read(size)
    except (OSError, EOFError, gzip.BadGzipFile):
        return b""


def contains(path: str, needles: Tuple[bytes, ...]) -> bool:
    """every needle somewhere in the file (the first MB of a .gz)"""
    try:
        if path.endswith(".gz"):
            data = head(path, GZ_SEARCH_BYTES)
            return all(n in data for n in needles)
        size = os.path.getsize(path)
        if size == 0 or size > SEARCH_BYTES:
            data = head(path, SNIFF_BYTES)
            return all(n in data for n in needles)
        with open(path, "rb") as fh, mmap.mmap(fh.fileno(), 0, access=mmap.ACCESS_READ) as mm:
            return all(mm.find(n) >= 0 for n in needles)
    except (OSError, ValueError):
        return False


def is_text(data: bytes) -> bool:
    return b"\0" not in data[:8192]


# the files no analyzer reads, listed with what to do rather than counted as "binary files skipped": pictures (a log sent
# as screenshots, or the pictures of a Word document), documents that analyze logs does not convert (.docx / .xlsx /
# .odt / .ods are converted by office_export.py)
IMAGE_NAME = re.compile(r"\.(?:png|jpe?g|gif|bmp|tiff?|webp|heic|emf|wmf)$", re.I)
DOCUMENT_NAME = re.compile(r"\.(?:pdf|doc|xls|ppt|pptx|pages|numbers|key)$", re.I)


def kind_of(label: str, path: str) -> Optional[str]:
    name = os.path.basename(label).lower()
    if IMAGE_NAME.search(name):
        return "screenshot"
    if DOCUMENT_NAME.search(name):
        return "document"
    data = head(path)
    if not data:
        return None
    if data.startswith(b"JAVA PROFILE 1.0") or name.endswith(".hprof") or name.endswith(".hprof.gz"):
        return "heap_dump"
    if data.startswith(b"FLR\0") or name.endswith(".jfr"):
        return "flight_recording"
    if data[:4] in PCAP_MAGIC or re.search(r"\.(pcap|pcapng|cap)(\.gz)?$", name):
        return "network_capture"
    if not is_text(data):
        return None
    if name.endswith((".html", ".htm")):
        return "xstream_report" if (b"orclcdc" in data.lower() or "orclcdc" in name) else None
    # a "commands output" file of a support bundle: a kafka-topics --describe, then a jstack. The thread dumps first (the
    # describe is still read: layout_kinds), else they were never analyzed
    if TOPIC_DESCRIBE.search(data) and contains(path, THREAD_DUMP):
        return "thread_dump"
    if TOPIC_DESCRIBE.search(data):
        return "topic_describe"
    if all(n in data for n in LOG_DIRS):
        return "log_dirs"
    if GC_CONTENT.search(data) and (GC_NAME.search(name) or len(GC_CONTENT.findall(data)) >= 5):
        return "gc_log"
    if contains(path, THREAD_DUMP):
        return "thread_dump"
    return None


def layout_kinds(path: str) -> List[str]:
    """the cluster layout outputs (topic_describe, log_dirs) in the head of a file of another kind"""
    data = head(path)
    return ([k for k, found in (("topic_describe", bool(TOPIC_DESCRIBE.search(data))),
                                ("log_dirs", all(n in data for n in LOG_DIRS))) if found] if data else [])


def keep(path: str, label: str, keep_dir: str, linked: bool) -> str:
    """copies (moves when the report does not link to it) a file of the tmp dir to keep_dir/<label>, returns its path"""
    # /path/to/case.zip:bundle/broker-1/gc.log -> case.zip/bundle/broker-1/gc.log
    archive, sep, inside = label.partition(":")
    rel = os.path.basename(archive.rstrip("/")) + ("/" + inside.replace(":", "/") if sep else "")
    rel = os.path.normpath(rel.lstrip("/"))
    if rel.startswith(".."):
        rel = os.path.basename(rel)
    dest = os.path.join(keep_dir, rel)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    if os.path.exists(dest):
        os.remove(dest)
    if linked:
        try:
            os.link(path, dest)
        except OSError:
            shutil.copy2(path, dest)
    else:
        shutil.move(path, dest)
    return dest


def triage(walked: str, keep_dir: Optional[str], tmp_dir: Optional[str], linked_paths: set) -> dict:
    files: List[dict] = []
    seen = set()
    try:
        fh = open(walked, encoding="utf-8", errors="replace")
    except OSError:
        return {"files": [], "commands": []}
    with fh:
        for line in fh:
            label, _, path = line.rstrip("\n").partition("\t")
            if not path or path in seen or not os.path.isfile(path):
                continue
            seen.add(path)
            kind = kind_of(label, path)
            if not kind:
                continue
            entry = {"label": label, "path": path, "kind": kind, "bytes": os.path.getsize(path), "kept": False}
            if kind == "thread_dump":
                also = layout_kinds(path)
                if also:
                    entry["also"] = also
            if kind in INLINE:
                # read by analyze logs in this run (from the tmp dir when extracted): not kept, no command
                entry["inline"] = True
                files.append(entry)
                continue
            # where analyze logs reads it in this run (thread dumps analyzed inline): the tmp dir is still there
            entry["read_path"] = path
            if tmp_dir and path.startswith(tmp_dir.rstrip("/") + "/"):
                if keep_dir:
                    try:
                        entry["path"] = keep(path, label, keep_dir, path in linked_paths)
                        entry["kept"] = True
                    except OSError as ex:
                        print(f"⚠️ cannot keep {label}: {ex}", file=sys.stderr)
                        entry["path"] = None
                else:
                    # only in the archive: extract it to run the command
                    entry["path"] = None
            files.append(entry)
    # one command per kind and folder for the analyzers that read several files (the rotated GC logs of a broker, the
    # thread dumps of one JVM), one per file for the others
    groups: Dict[Tuple[str, str], List[dict]] = {}
    for f in files:
        folder = f["label"].rsplit("/", 1)[0] if "/" in f["label"] else ""
        key = (f["kind"], folder if KINDS[f["kind"]][3] else f["label"])
        groups.setdefault(key, []).append(f)
    commands = []
    for (kind, folder), items in sorted(groups.items(), key=lambda g: (ORDER.index(g[0][0]), g[0][1])):
        icon, what, cmd, _ = KINDS[kind]
        items.sort(key=lambda f: f["label"])
        paths = [f["path"] for f in items]
        if kind in INLINE:
            command = ""
        elif kind in ("screenshot", "document"):
            command = command_of(kind, items, paths)
        elif all(paths):
            command = cmd + "".join(f" -f {shlex.quote(p)}" for p in paths[:20])
        else:
            command = f"{cmd} -f <extract {items[0]['label'].split(':', 1)[0]} first>"
        commands.append({"kind": kind, "icon": icon, "what": what,
                         "folder": folder if KINDS[kind][3] else os.path.dirname(folder),
                         "files": [f["label"] for f in items], "command": command, **({"inline": True} if kind in INLINE else {})})
    return {"files": files, "commands": commands}


def command_of(kind: str, items: List[dict], paths: List[Optional[str]]) -> str:
    """what to do with the files no analyzer reads: look at the pictures, turn a document into text"""
    where = [shlex.quote(p) if p else f"<extract {f['label'].split(':', 1)[0]} first>" for f, p in zip(items, paths)]
    if kind == "screenshot":
        # OCR them (approximate lines, marked 📷 in the report), or look at them
        readable = [w for w in where if not w.startswith("<extract")]
        return ("playground analyze logs --ocr" + "".join(f" -f {w}" for w in readable[:20]) + " (or: open " + " ".join(where[:20]) + ")"
                if readable else "open " + " ".join(where[:20]))
    name = items[0]["label"].lower()
    if name.endswith(".pdf"):
        return (f"pdftotext -layout {where[0]} /tmp/pdf.log && playground analyze logs -f /tmp/pdf.log "
                "(pdftotext: brew install poppler / apt install poppler-utils; a scanned PDF is pictures: transcribe them)")
    if name.endswith((".pptx", ".ppt", ".key")):
        return f"copy the log lines of the slides of {where[0]} to a .log file, then playground analyze logs -f <it>"
    return (f"save {where[0]} again as .docx / .xlsx (or ask for the logs as text): playground analyze logs converts "
            "those")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--walked", help="label<tab>path of every file of the input")
    ap.add_argument("--gc-logs", metavar="SOURCES", help="only print the labels of the files of SOURCES (label<tab>path…, the "
                    "files digested by analyze logs) that are GC logs, one per line: they are not logs of a component")
    ap.add_argument("--keep-dir", help="where to keep the files recognized that were extracted to --tmp-dir")
    ap.add_argument("--tmp-dir", help="the tmp dir of analyze logs, deleted at the end")
    ap.add_argument("--sources", help="label<tab>path of the files the report links to (copied, not moved)")
    args = ap.parse_args()
    if args.gc_logs:
        seen = set()
        with open(args.gc_logs, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                parts = line.rstrip("\n").split("\t")
                if len(parts) >= 2 and parts[0] not in seen and os.path.isfile(parts[1]):
                    seen.add(parts[0])
                    if kind_of(parts[0], parts[1]) == "gc_log":
                        print(parts[0])
        return 0
    if not args.walked:
        ap.error("--walked is required")
    linked = set()
    if args.sources:
        try:
            with open(args.sources, encoding="utf-8", errors="replace") as fh:
                linked = {l.rstrip("\n").split("\t")[1] for l in fh if l.count("\t") >= 1}
        except OSError:
            pass
    print(json.dumps(triage(args.walked, args.keep_dir, args.tmp_dir, linked), ensure_ascii=False, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
