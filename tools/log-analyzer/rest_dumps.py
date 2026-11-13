#!/usr/bin/env python3
"""
The outputs of the Kafka Connect REST API that customers send next to their logs, recognized by their content whatever
the extension (a .txt with the shell prompt, the curl progress meter and one or more pretty-printed JSON documents):

  - GET /connectors/<name>/status and GET /connectors?expand=status (also with expand=info): the stack trace of each
    FAILED connector or task (its "trace") is written as an ERROR record of a log file, [<connector>|task-<id>] as its
    connector context and the worker in its message, so that the known causes and the root causes see it (the records
    have no time: none is in the dump)
  - GET /connector-plugins (also ?connectorsOnly=false, whose transformations and converters have no "version"), and the
    connector configs (GET /connectors/<name>, ?expand=info): each JSON document is written to its own .json file, read
    by append_config_file of analyze logs (⚙️ Configuration, versions of the plugins, a class listed twice)

usage: rest_dumps.py <file> <output folder>
  writes <output folder>/rest-status.log (FAILED connectors and tasks) and <output folder>/blocks/<n>.json, prints
  "<statuses>\t<failed>\t<blocks>\t<1 when the JSON documents are most of the file>"; exit 1 when the file has neither a
  status nor a plugin list (the caller reads it as before)
"""

import json
import os
import re
import sys
from typing import Iterator, List, Tuple

sys.dont_write_bytecode = True

MAX_BYTES = 50 * 1024 * 1024
# a JSON document starts a line: "{", or "[" alone or before "{" (pretty-printed by jq / python -m json.tool, or one
# line), not the "[2026-11-06 06:16:24,209]" of a log line
START_RE = re.compile(r"(?m)^[ \t]*(?:\{|\[[ \t]*(?:\{|$))")
# documents read without finding a status nor a plugin list: a log of JSON lines, not a REST API output
MAX_OTHER_DOCUMENTS = 50


def documents(text: str) -> Iterator[Tuple[object, int]]:
    """the JSON documents of the text, with their length: the whole text, else each one starting a line"""
    stripped = text.strip()
    if stripped[:1] in ("{", "["):
        try:
            yield json.loads(stripped), len(stripped)
            return
        except ValueError:
            pass
    dec = json.JSONDecoder()
    pos = 0
    for m in START_RE.finditer(text):
        start = m.start() + len(m.group(0)) - len(m.group(0).lstrip(" \t"))
        if start < pos:
            continue
        try:
            value, end = dec.raw_decode(text, start)
        except ValueError:
            continue
        if isinstance(value, (dict, list)) and value:
            pos = end
            yield value, end - start


def is_status(o: object) -> bool:
    """the body of GET /connectors/<name>/status"""
    return (isinstance(o, dict) and isinstance(o.get("connector"), dict) and "state" in o["connector"]
            and isinstance(o.get("tasks"), list))


def statuses(o: object) -> List[dict]:
    """the connector statuses of a document: one status, a list of them, or the map of ?expand=status"""
    if is_status(o):
        return [o]
    out: List[dict] = []
    if isinstance(o, list):
        for x in o:
            if is_status(x):
                out.append(x)
    elif isinstance(o, dict):
        for name, v in o.items():
            if isinstance(v, dict) and is_status(v.get("status")):
                st = v["status"]
                if not st.get("name"):
                    st = dict(st, name=name)
                out.append(st)
    return out


def is_plugins(o: object) -> bool:
    """GET /connector-plugins (?connectorsOnly=false: the transformations, converters… have no version)"""
    return (isinstance(o, list) and len(o) > 0
            and all(isinstance(x, dict) and "class" in x and "type" in x for x in o))


def one_line(s: object) -> str:
    return re.sub(r"\s+", " ", str(s or "")).strip()


def failed_records(st: dict) -> List[str]:
    """the log lines of the FAILED connector and tasks of a status: an ERROR line, then the trace"""
    name = one_line(st.get("name")) or "unknown"
    kind = one_line(st.get("type"))
    out: List[str] = []

    def record(context: str, what: str, s: dict) -> None:
        worker = one_line(s.get("worker_id"))
        trace = str(s.get("trace") or "").rstrip()
        head = (f"ERROR [{context}] REST status: {what} is FAILED"
                + (f" on worker {worker}" if worker else "") + (f" ({kind} connector)" if kind else "")
                + (", trace:" if trace else ", no trace") + " (org.apache.kafka.connect.runtime.rest.resources.ConnectorsResource)")
        out.append(head)
        # the stack trace as a log prints it: the first line, then "\tat …" and "Caused by: …"
        for line in trace.splitlines():
            out.append(line.rstrip())
    c = st.get("connector") or {}
    if str(c.get("state", "")).upper() == "FAILED":
        record(name, f"connector {name}", c)
    for t in st.get("tasks") or []:
        if isinstance(t, dict) and str(t.get("state", "")).upper() == "FAILED":
            tid = t.get("id", "")
            record(f"{name}|task-{tid}", f"task {name}-{tid}", t)
    return out


def main(argv: List[str]) -> int:
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    path, out_dir = argv[1], argv[2]
    try:
        if os.path.getsize(path) > MAX_BYTES:
            return 1
        with open(path, encoding="utf-8", errors="replace") as fh:
            text = fh.read()
    except OSError:
        return 1
    # a quick look before parsing: a status has "state" and "tasks", a plugin list "class" and "type"
    if not (('"tasks"' in text and '"state"' in text) or ('"class"' in text and '"type"' in text)):
        return 1
    found_status, found_plugins = [], False
    blocks: List[object] = []
    covered = 0
    for doc, length in documents(text):
        covered += length
        st = statuses(doc)
        if st:
            found_status += st
            continue
        if is_plugins(doc):
            found_plugins = True
        blocks.append(doc)
        if not found_status and not found_plugins and len(blocks) >= MAX_OTHER_DOCUMENTS:
            return 1
    if not found_status and not found_plugins:
        return 1
    os.makedirs(os.path.join(out_dir, "blocks"), exist_ok=True)
    lines: List[str] = []
    failed = 0
    for st in found_status:
        rec = failed_records(st)
        failed += sum(1 for line in rec if line.startswith("ERROR ["))
        lines += rec
    if lines:
        with open(os.path.join(out_dir, "rest-status.log"), "w", encoding="utf-8") as fh:
            fh.write("\n".join(lines) + "\n")
    for i, doc in enumerate(blocks, 1):
        with open(os.path.join(out_dir, "blocks", f"{i}.json"), "w", encoding="utf-8") as fh:
            json.dump(doc, fh)
    most = 1 if covered * 2 >= len(text.strip()) else 0
    print(f"{len(found_status)}\t{failed}\t{len(blocks)}\t{most}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
