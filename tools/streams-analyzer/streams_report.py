#!/usr/bin/env python3
"""
Kafka Streams view of log files, from the lines the Kafka Streams library itself logs (any application, any version
since 3.0): no JMX, no code in the application.

- playground streams status: the logs of the running Streams containers (docker logs), one file per instance
- playground analyze logs: the files of a customer bundle that contain Kafka Streams lines

For each application (application.id, from the client id "<application.id>-<process UUID>"), and each instance
(a file, or a container), it reports:

- the state of the KafkaStreams client (`stream-client [...] State transition from REBALANCING to RUNNING`), since when,
  the number of rebalances and the time spent in REBALANCING, the last transitions
- the stream threads, their state and their tasks (`Handle new assignment with: New active tasks: [...]
  New standby tasks: [...]`, the full assignment of the thread)
- the active tasks not restored yet (no `task [1_5] Restored and ready to run` since their assignment), the changelog
  end offsets and the "Restoration in progress" lines, the records restored (`Finished restoring changelog …`)
- the known Kafka Streams errors (task migrated, fenced producer, deserialization handler, missing source topic,
  co-partitioning, state directory lock, task timeout, uncaught exception…), with their advice

A restarted instance logs its start again (`Kafka Streams version: …`) with the same client id when its state.dir
survived (the process UUID is stored there), or with a new client id otherwise: either way only the current run is
reported, the restarts are counted and kept in the timeline of the HTML view (streams_html.py).

Usage:
  streams_report.py [--json] [--application-id ID] [--sources FILE] [label=path ...]

--sources: a file of "label<TAB>path[<TAB>…]" lines (the sources file of playground analyze logs).
Prints a text report, or JSON with --json. Exit code 0, or 2 when no Kafka Streams line was found.
"""

import argparse
import json
import os
import re
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from datetime import datetime

TS = re.compile(r"(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2}:\d{2})(?:[,.](\d{1,3}))?")
# a line that starts a new log record: a timestamp near its start (after a "[", a container or pod prefix…)
NEW_RECORD = re.compile(r"^.{0,60}?\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}")
UUID_SUFFIX = re.compile(r"^(?P<app>.+)-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
THREAD = re.compile(r"^(?P<client>.+)-(?:StreamThread|GlobalStreamThread|StateUpdater)-?(?P<n>\d*)(?:-[a-z-]+)?$")

CLIENT_TRANSITION = re.compile(r"stream-client \[(?P<client>[^\]]+)\] State transition from (?P<src>[A-Z_]+) to (?P<dst>[A-Z_]+)")
THREAD_TRANSITION = re.compile(r"stream-thread \[(?P<thread>[^\]]+)\] State transition from (?P<src>[A-Z_]+) to (?P<dst>[A-Z_]+)")
VERSION = re.compile(r"stream-client \[(?P<client>[^\]]+)\] Kafka Streams version: (?P<version>\S+)")
ASSIGNMENT = re.compile(r"stream-thread \[(?P<thread>[^\]]+)\] Handle new assignment with:")
NEW_ACTIVE = re.compile(r"New active tasks: \[(?P<tasks>[^\]]*)\]")
NEW_STANDBY = re.compile(r"New standby tasks: \[(?P<tasks>[^\]]*)\]")
RESTORED_TASK = re.compile(r"(?:stream-thread|state-updater) \[(?P<thread>[^\]]+)\].{0,40}?task \[(?P<task>\d+_\d+)\] Restored and ready to run")
END_OFFSET = re.compile(r"\[(?P<thread>[^\]]+)\] End offset for changelog (?P<changelog>\S+) initialized as (?P<end>\d+)")
RESTORE_FINISHED = re.compile(r"\[(?P<thread>[^\]]+)\] Finished restoring changelog (?P<changelog>\S+) to store (?P<store>\S+) "
                              r"with a total number of (?P<records>\d+) records")
RESTORE_PROGRESS = re.compile(r"\[(?P<thread>[^\]]+)\] Restoration in progress for \d+ partitions?\. \{(?P<parts>.*)\}")
PROGRESS_PART = re.compile(r"(?P<changelog>[^\s,{}:]+): position=(?P<position>\d+), end=(?P<end>\d+), totalRestored=(?P<restored>\d+)")
# any line naming a client or a thread of Kafka Streams, for the errors
CONTEXT = re.compile(r"(?:stream-client|stream-thread|state-updater|stream-task|task) \[(?P<id>[^\]]+)\]")

# Kafka Streams errors worth explaining, in order: the first match names the line
KNOWN_ERRORS = [
    ("copartition", r"Topics not co-partitioned",
     "🧩 Topics not co-partitioned",
     "the source topics of a join do not have the same number of partitions: repartition one side (selectKey / "
     "repartition()) or create the topics with the same partition count. Since Kafka Streams 3.2 the check only runs "
     "when the topology has repartition topics: two source topics joined directly are no longer refused, and join "
     "results are silently missing for some keys"),
    ("missing_source", r"MissingSourceTopicException|One or more source topics were missing",
     "🕳️ Missing source topic",
     "a source topic of the topology does not exist (or the application cannot describe it, an ACL): create it before "
     "starting the application. The client goes to ERROR"),
    ("fenced", r"Detected that the thread is being fenced|Producer got fenced|ProducerFencedException"
               r"|InvalidProducerEpochException",
     "🧟 Producer fenced (exactly-once)",
     "another instance took over the tasks of this thread (it was paused, too slow or lost its session): its "
     "transaction is aborted and the tasks are migrated. Look at GC pauses, max.poll.interval.ms and "
     "transaction.timeout.ms; occasional fencing after a rebalance is expected with exactly_once_v2"),
    ("task_migrated", r"TaskMigratedException",
     "🔀 Task migrated",
     "the thread lost the ownership of its tasks (rebalance while it was processing, fenced producer, consumer "
     "kicked out of the group): Kafka Streams rejoins the group and recovers. Frequent occurrences point at long "
     "processing between polls (max.poll.interval.ms), GC pauses or unstable members"),
    ("poll_interval", r"max\.poll\.interval\.ms|consumer poll timeout has expired",
     "⏱️ max.poll.interval.ms exceeded",
     "a stream thread did not poll within max.poll.interval.ms and left the group: the processing of one batch is too "
     "slow (a slow external call in a processor, a large max.poll.records, RocksDB stalls). Raise "
     "max.poll.interval.ms or make the processing faster"),
    ("deserialization", r"Exception caught during Deserialization|DeserializationExceptionHandler|deserialization error callback",
     "🧪 Deserialization error",
     "a record could not be deserialized with the configured serdes (poison pill, wrong format, schema not found): "
     "deserialization.exception.handler (default.deserialization.exception.handler before 4.0) decides: "
     "LogAndFailExceptionHandler stops the thread, LogAndContinueExceptionHandler skips the record "
     "(dropped-records-total)"),
    ("production", r"ProductionExceptionHandler|Error encountered sending record to topic|Exception caught during Production"
                   r"|RecordTooLargeException",
     "📤 Production error",
     "a record could not be written to an output, repartition or changelog topic (too large, authorization, "
     "timeout): production.exception.handler (default.production.exception.handler before 4.0) decides whether "
     "the thread fails or continues"),
    ("state_dir_lock", r"Failed to lock the state directory|LockException|Failed to lock state directory",
     "🔒 State directory locked",
     "two threads or two instances use the same state.dir for the same task (two instances on the same host or "
     "volume, or a previous instance still running): give each instance its own state.dir"),
    ("task_timeout", r"task\.timeout\.ms|exceeded the task timeout",
     "⌛ Task timeout",
     "a task could not make progress (a broker or a topic unavailable, an authorization error) for longer than "
     "task.timeout.ms: look at the cause logged with it"),
    ("rocksdb", r"RocksDBException|Error opening store .{0,80} at location",
     "🪨 RocksDB error",
     "a state store could not be opened or written (disk full, corrupted files, too many open files, memory): "
     "look at the disk of state.dir and the RocksDB settings (rocksdb.config.setter)"),
    ("authorization", r"(?:Topic|Group|TransactionalId|Cluster)AuthorizationException",
     "🚫 Authorization error",
     "the principal of the application misses an ACL or a role binding: it needs its source and sink topics, its "
     "internal topics and its group (prefixed on application.id), and transactional ids with exactly-once"),
    ("uncaught", r"Encountered the following exception during processing|stream thread will shut down"
                 r"|Replacing thread in the streams uncaught exception handler|StreamsUncaughtExceptionHandler"
                 r"|Uncaught exception in a stream thread",
     "💀 Uncaught exception in a stream thread",
     "a stream thread died: the StreamsUncaughtExceptionHandler decides (REPLACE_THREAD, SHUTDOWN_CLIENT, "
     "SHUTDOWN_APPLICATION). The cause is in the exception chain of the record"),
]
KNOWN_ERRORS = [(key, re.compile(pattern, re.IGNORECASE), title, advice) for key, pattern, title, advice in KNOWN_ERRORS]
ERROR_STATES = {"ERROR", "PENDING_ERROR", "DEAD", "PENDING_SHUTDOWN", "NOT_RUNNING"}


def timestamp(line):
    m = TS.search(line[:80])
    if not m:
        return None
    return f"{m.group(1)}T{m.group(2)}" + (f".{m.group(3).ljust(3, '0')}" if m.group(3) else "")


def seconds(ts):
    try:
        return datetime.fromisoformat(ts).timestamp()
    except (TypeError, ValueError):
        return None


def app_of(client):
    m = UUID_SUFFIX.match(client)
    return m.group("app") if m else client


def client_of_thread(thread):
    m = THREAD.match(thread)
    return m.group("client") if m else None


def tasks(text):
    return sorted((t.strip() for t in text.split(",") if t.strip()), key=task_key)


def set_active(thread, active):
    """The new assignment of a thread: a task it already had stays restored, a new one has to restore first."""
    thread["restored"] = {t for t in thread["restored"] if t in active}
    thread["active"] = active


def task_key(task):
    a, _, b = task.partition("_")
    return (int(a), int(b)) if a.isdigit() and b.isdigit() else (0, 0)


class Client:
    def __init__(self, label, client_id, line_no):
        self.label = label
        self.client_id = client_id
        self.application_id = app_of(client_id)
        self.first_line = line_no
        self.last_line = line_no
        self.version = None
        self.state = None
        self.state_since = None
        self.transitions = []
        self.rebalances = 0
        self.rebalancing_seconds = 0.0
        self.rebalancing_since = None
        self.threads = {}
        self.restored_records = 0
        self.restored_changelogs = 0
        self.end_offsets = {}
        self.finished = set()
        self.progress = {}
        self.last_ts = None
        self.starts = 0

    def thread(self, name):
        return self.threads.setdefault(name, {"name": name, "state": None, "active": [], "standby": [],
                                              "restored": set(), "assigned_at": None})


class Parser:
    def __init__(self):
        self.clients = {}      # (label, client id) -> Client
        self.errors = {}       # (application id or "", key) -> error
        self.labels = set()
        self.current_ts = None
        self.last_app = {}     # label -> application of the last line with a Kafka Streams context
        self.record = 0        # number of the log record the current line belongs to (stack traces continue it)
        self.counted = set()   # (label, record, error key): an error counts once per record
        self.file_last_ts = {} # label -> last timestamp of the file: the current run lasts until then

    def client(self, label, client_id, line_no):
        key = (label, client_id)
        if key not in self.clients:
            self.clients[key] = Client(label, client_id, line_no)
        c = self.clients[key]
        c.last_line = line_no
        if self.current_ts:
            c.last_ts = self.current_ts
        return c

    def client_for_thread(self, label, thread, line_no):
        client_id = client_of_thread(thread)
        return self.client(label, client_id, line_no) if client_id else None

    def parse(self, label, lines):
        pending_assignment = None  # (client, thread name, lines left)
        for line_no, line in enumerate(lines, 1):
            if "[" not in line and pending_assignment is None:
                # a line of a stack trace ("Caused by: …TaskMigratedException"): only the errors are looked for
                if "Exception" in line or "Error" in line:
                    self.error(label, line, self.current_ts, line_no)
                continue
            ts = timestamp(line)
            self.current_ts = ts
            if ts:
                self.file_last_ts[label] = ts
            if NEW_RECORD.match(line):
                self.record += 1
            ctx = CONTEXT.search(line)
            if ctx:
                ident = ctx.group("id")
                self.last_app[label] = app_of(client_of_thread(ident) or ident)
            if pending_assignment:
                # the lines of a multi-line assignment record are the ones that do not start a new record
                if NEW_RECORD.match(line):
                    pending_assignment = None
                else:
                    c, name, left = pending_assignment
                    t = c.thread(name)
                    m = NEW_ACTIVE.search(line)
                    if m:
                        set_active(t, tasks(m.group("tasks")))
                    m = NEW_STANDBY.search(line)
                    if m:
                        t["standby"] = tasks(m.group("tasks"))
                    pending_assignment = (c, name, left - 1) if left > 1 else None
                    continue
            m = ASSIGNMENT.search(line)
            if m:
                c = self.client_for_thread(label, m.group("thread"), line_no)
                if c:
                    t = c.thread(m.group("thread"))
                    t["assigned_at"] = ts
                    # the tasks may be on the same line (one-line log formats) or on the next ones
                    a, s = NEW_ACTIVE.search(line), NEW_STANDBY.search(line)
                    if a:
                        set_active(t, tasks(a.group("tasks")))
                    if s:
                        t["standby"] = tasks(s.group("tasks"))
                    pending_assignment = None if (a and s) else (c, m.group("thread"), 4)
                continue
            if "State transition from" in line:
                m = CLIENT_TRANSITION.search(line)
                if m:
                    self.client_transition(self.client(label, m.group("client"), line_no), m.group("src"), m.group("dst"), ts)
                    continue
                m = THREAD_TRANSITION.search(line)
                if m:
                    c = self.client_for_thread(label, m.group("thread"), line_no)
                    if c:
                        c.thread(m.group("thread"))["state"] = m.group("dst")
                    continue
            m = VERSION.search(line)
            if m:
                key = (label, m.group("client"))
                previous = self.clients.get(key)
                previous_ts = previous.last_ts if previous else None
                c = self.client(label, m.group("client"), line_no)
                c.starts += 1
                if c.starts > 1:
                    # a restart that kept the process UUID (it is stored in state.dir): the previous run ended at the
                    # last line seen before this one
                    c.transitions.append({"at": ts, "restart": True, "previous_last_seen": previous_ts})
                    c.state = None
                    c.threads = {}
                c.version = m.group("version")
                continue
            m = RESTORED_TASK.search(line)
            if m:
                c = self.client_for_thread(label, m.group("thread"), line_no)
                if c:
                    for t in c.threads.values():
                        if m.group("task") in t["active"]:
                            t["restored"].add(m.group("task"))
                continue
            m = END_OFFSET.search(line)
            if m:
                c = self.client_for_thread(label, m.group("thread"), line_no)
                if c:
                    c.end_offsets[m.group("changelog")] = (int(m.group("end")), ts)
                    c.finished.discard(m.group("changelog"))
                continue
            m = RESTORE_FINISHED.search(line)
            if m:
                c = self.client_for_thread(label, m.group("thread"), line_no)
                if c:
                    c.restored_records += int(m.group("records"))
                    c.restored_changelogs += 1
                    c.finished.add(m.group("changelog"))
                    c.progress.pop(m.group("changelog"), None)
                continue
            m = RESTORE_PROGRESS.search(line)
            if m:
                c = self.client_for_thread(label, m.group("thread"), line_no)
                if c:
                    for p in PROGRESS_PART.finditer(m.group("parts")):
                        c.progress[p.group("changelog")] = {k: int(p.group(k)) for k in ("position", "end", "restored")} | {"at": ts}
                continue
            if re.search(r"ERROR|WARN|Exception", line):
                self.error(label, line, ts, line_no)

    def client_transition(self, c, src, dst, ts):
        if dst == "REBALANCING" and src != "REBALANCING":
            c.rebalances += 1
            c.rebalancing_since = ts
        elif src == "REBALANCING" and dst != "REBALANCING":
            a, b = seconds(c.rebalancing_since), seconds(ts)
            if a is not None and b is not None:
                c.rebalancing_seconds += max(0.0, b - a)
            c.rebalancing_since = None
        c.state = dst
        c.state_since = ts
        c.transitions.append({"at": ts, "from": src, "to": dst})
        if len(c.transitions) > 2000:
            c.transitions = c.transitions[-2000:]

    def error(self, label, line, ts, line_no):
        for key, pattern, title, advice in KNOWN_ERRORS:
            if pattern.search(line):
                if (label, self.record, key) in self.counted:
                    return
                self.counted.add((label, self.record, key))
                # the error line names its client or thread, or it belongs to the last application seen in the file
                # (a handler that logs without the Kafka Streams context, the line of an exception)
                m = CONTEXT.search(line)
                if m:
                    ident = m.group("id")
                    app = app_of(client_of_thread(ident) or ident)
                else:
                    app = self.last_app.get(label, "")
                e = self.errors.setdefault((app, key), {"key": key, "title": title, "advice": advice, "count": 0,
                                                        "first": ts, "last": ts, "labels": set(), "sample": line.strip()[:400],
                                                        "first_line": line_no, "first_label": label,
                                                        "occurrences": []})
                e["count"] += 1
                # each occurrence (time, instance), for the chart and the markers of the timeline (HTML view)
                if ts and len(e["occurrences"]) < 1000:
                    e["occurrences"].append([ts, label])
                e["last"] = ts or e["last"]
                e["first"] = e["first"] or ts
                e["labels"].add(label)
                return

    def report(self, application_id=None):
        apps = {}
        # the last client of an application in a file is the current one: the others are previous runs (restarts)
        latest = {}
        restarts = {}
        for (label, client_id), c in self.clients.items():
            key = (label, c.application_id)
            if key not in latest or c.last_line > latest[key].last_line:
                if key in latest:
                    restarts[key] = restarts.get(key, 0) + 1
                latest[key] = c
            else:
                restarts[key] = restarts.get(key, 0) + 1
        for (label, app), c in sorted(latest.items(), key=lambda kv: (kv[0][1], kv[0][0])):
            if application_id and app != application_id:
                continue
            if c.state is None and not c.threads:
                continue
            instance = {
                "instance": label,
                "client_id": c.client_id,
                "version": c.version,
                "state": c.state,
                "state_since": c.state_since,
                "rebalances": c.rebalances,
                "rebalancing_seconds": round(c.rebalancing_seconds + (0 if not c.rebalancing_since else 0), 1),
                "rebalancing_since": c.rebalancing_since,
                "restarts": restarts.get((label, app), 0) + max(0, c.starts - 1),
                "last_transitions": [t for t in c.transitions if not t.get("restart")][-5:],
                "threads": [],
                "restored_records": c.restored_records,
                "restored_changelogs": c.restored_changelogs,
                "restoring": [],
            }
            for name in sorted(c.threads):
                t = c.threads[name]
                restoring = [task for task in t["active"] if task not in t["restored"]]
                instance["threads"].append({"name": name, "state": t["state"], "active": t["active"],
                                            "standby": t["standby"], "not_restored": restoring})
            # changelogs whose restoration started (end offset known) and did not finish, with the progress if logged
            for changelog, (end, at) in sorted(c.end_offsets.items()):
                if changelog in c.finished or end == 0:
                    continue
                p = c.progress.get(changelog)
                instance["restoring"].append({"changelog": changelog, "end_offset": end, "since": at,
                                              "position": p["position"] if p else None,
                                              "restored": p["restored"] if p else None})
            history = sorted((x for x in self.clients.values() if x.label == label and x.application_id == app),
                             key=lambda x: x.first_line)
            instance["timeline_end"] = self.file_last_ts.get(label)
            instance["timeline"] = [{"client_id": x.client_id, "last_seen": x.last_ts,
                                     "transitions": x.transitions} for x in history if x.transitions]
            apps.setdefault(app, {"application_id": app, "instances": [], "errors": []})["instances"].append(instance)
        for (app, key), e in sorted(self.errors.items(), key=lambda kv: -kv[1]["count"]):
            if application_id and app and app != application_id:
                continue
            target = apps.get(app)
            if target is None:
                if app == "" and len(apps) == 1:
                    target = next(iter(apps.values()))
                else:
                    target = apps.setdefault(app or "(unknown application)", {"application_id": app or "(unknown application)",
                                                                              "instances": [], "errors": []})
            target["errors"].append({k: (sorted(v) if isinstance(v, set) else v) for k, v in e.items()})
        for a in apps.values():
            a["tasks"] = task_table(a["instances"])
            a["findings"] = findings(a)
        # the applications with a problem first: an instance not RUNNING, then the most errors
        ordered = sorted(apps.values(), key=lambda a: (-sum(1 for i in a["instances"] if i["state"] != "RUNNING"),
                                                       -sum(err["count"] for err in a["errors"]), a["application_id"]))
        return {"applications": ordered}


def task_table(instances):
    table = {}
    for i in instances:
        for t in i["threads"]:
            for task in t["active"]:
                table.setdefault(task, {"active": [], "standby": []})["active"].append(i["instance"])
            for task in t["standby"]:
                table.setdefault(task, {"active": [], "standby": []})["standby"].append(i["instance"])
    return {k: table[k] for k in sorted(table, key=task_key)}


def findings(app):
    out = []
    for i in app["instances"]:
        if i["state"] in ERROR_STATES:
            out.append(f"❌ {i['instance']}: the client is {i['state']} since {short_ts(i['state_since'])}")
        elif i["state"] == "REBALANCING":
            out.append(f"⏳ {i['instance']}: rebalancing since {short_ts(i['state_since'])}")
        not_restored = sorted({t for th in i["threads"] for t in th["not_restored"]}, key=task_key)
        if not_restored and i["state"] != "RUNNING":
            out.append(f"♻️ {i['instance']}: active task(s) not restored yet: {', '.join(not_restored)}")
        for th in i["threads"]:
            if th["state"] in ("DEAD", "PENDING_SHUTDOWN") and i["state"] not in ERROR_STATES:
                out.append(f"💀 {i['instance']}: thread {th['name']} is {th['state']}")
        if i["restarts"]:
            out.append(f"🔁 {i['instance']}: restarted {i['restarts']} time(s) in these logs")
    for task, owners in app["tasks"].items():
        if len(owners["active"]) > 1:
            out.append(f"⚠️ task {task} is active on {len(owners['active'])} instances ({', '.join(owners['active'])}): "
                       f"one of them has not caught up with the last rebalance yet, or is a zombie")
    versions = sorted({i["version"] for i in app["instances"] if i["version"]})
    if len(versions) > 1:
        out.append(f"⚠️ instances run different Kafka Streams versions: {', '.join(versions)}")
    return out


def short_ts(ts):
    return ts.replace("T", " ")[:19] if ts else "?"


def text(rep):
    lines = []
    for a in rep["applications"]:
        versions = sorted({i["version"] for i in a["instances"] if i["version"]})
        lines.append(f"🌊 application {a['application_id']}" + (f" (Kafka Streams {', '.join(versions)})" if versions else "")
                     + f": {len(a['instances'])} instance(s)")
        if a["instances"]:
            rows = [("INSTANCE", "STATE", "SINCE", "REBALANCES", "THREADS", "ACTIVE TASKS", "STANDBY TASKS", "NOT RESTORED")]
            for i in a["instances"]:
                active = sorted({t for th in i["threads"] for t in th["active"]}, key=task_key)
                standby = sorted({t for th in i["threads"] for t in th["standby"]}, key=task_key)
                not_restored = sorted({t for th in i["threads"] for t in th["not_restored"]}, key=task_key)
                thread_states = sorted({th["state"] or "?" for th in i["threads"]})
                state = i["state"] or "?"
                if i.get("container_status", "running") != "running":
                    state = f"{state} (container {i['container_status']})"
                rows.append((i["instance"], state, short_ts(i["state_since"])[11:] or "?",
                             f"{i['rebalances']} ({i['rebalancing_seconds']:g}s)",
                             f"{len(i['threads'])} {'/'.join(thread_states)}" if i["threads"] else "-",
                             ", ".join(active) or "-", ", ".join(standby) or "-", ", ".join(not_restored) or "-"))
            widths = [max(len(r[k]) for r in rows) for k in range(len(rows[0]))]
            for r in rows:
                lines.append("  " + "  ".join(v.ljust(widths[k]) for k, v in enumerate(r)).rstrip())
        restored = [(i["instance"], i["restored_records"], i["restored_changelogs"]) for i in a["instances"] if i["restored_changelogs"]]
        if restored:
            lines.append("  ♻️ restored: " + ", ".join(f"{n} {r} record(s) from {c} changelog partition(s)" for n, r, c in restored))
        for i in a["instances"]:
            for r in i["restoring"]:
                progress = f", position {r['position']}, {r['restored']} restored" if r["position"] is not None else ""
                lines.append(f"  ♻️ {i['instance']}: restoring {r['changelog']} (end offset {r['end_offset']}{progress}) since {short_ts(r['since'])}")
        for f in a["findings"]:
            lines.append(f"  {f}")
        for e in a["errors"]:
            lines.append(f"  {e['title']} x{e['count']} ({', '.join(e['labels'])}, first {short_ts(e['first'])}, last {short_ts(e['last'])})")
            lines.append(f"     👉 {e['advice']}")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def shorten_labels(rep):
    """Files of a bundle are labelled with their path: drop the folders they all share (pod-1/kafka.log and
    pod-2/kafka.log stay apart)"""
    labels = {i["instance"] for a in rep["applications"] for i in a["instances"]}
    labels |= {lab for a in rep["applications"] for err in a["errors"] for lab in err["labels"]}
    if len(labels) < 1 or not all("/" in lab for lab in labels):
        return
    common = os.path.commonpath(list(labels)) if len(labels) > 1 else os.path.dirname(next(iter(labels)))
    if not common or common == "/":
        return

    def short(lab):
        return os.path.relpath(lab, common)

    for a in rep["applications"]:
        for i in a["instances"]:
            i["instance"] = short(i["instance"])
        for err in a["errors"]:
            err["labels"] = [short(lab) for lab in err["labels"]]
            err["first_label"] = short(err["first_label"])
            err["occurrences"] = [[at, short(lab)] for at, lab in err.get("occurrences", [])]
        a["tasks"] = {t: {k: [short(x) for x in v] for k, v in owners.items()} for t, owners in a["tasks"].items()}
        a["findings"] = [f.replace(common + "/", "") for f in a["findings"]]


def write_html(rep, args):
    if not (args.html_out or args.html_fragment) or not rep["applications"]:
        return
    import streams_html
    if args.html_out:
        with open(args.html_out, "w", encoding="utf-8") as fh:
            fh.write(streams_html.page_html(rep, args.title))
    if args.html_fragment:
        with open(args.html_fragment, "w", encoding="utf-8") as fh:
            fh.write(streams_html.fragment(rep))


def main():
    ap = argparse.ArgumentParser(description="Kafka Streams view of log files")
    ap.add_argument("files", nargs="*", help="label=path")
    ap.add_argument("--sources", help="file of label<TAB>path lines")
    ap.add_argument("--application-id")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--html-out", help="write a standalone HTML page (playground streams status --html)")
    ap.add_argument("--html-fragment", help="write the HTML section of the log report (playground analyze logs)")
    ap.add_argument("--from-json", help="render a report already written with --json (with the consumer group of "
                                        "playground streams status) instead of reading log files")
    ap.add_argument("--title", default="Kafka Streams status")
    ap.add_argument("--container-status", action="append", default=[],
                    help="label=status of the container of an instance (playground streams status): an instance whose "
                         "container is not running keeps the last state of its logs, it is flagged")
    args = ap.parse_intermixed_args()

    inputs = []
    for f in args.files:
        label, _, path = f.partition("=")
        inputs.append((label, path or label))
    if args.sources:
        with open(args.sources, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                parts = line.rstrip("\n").split("\t")
                if len(parts) >= 2 and parts[1]:
                    inputs.append((parts[0], parts[1]))

    if args.from_json:
        with open(args.from_json, encoding="utf-8") as fh:
            rep = json.load(fh)
        write_html(rep, args)
        return 0 if rep["applications"] else 2

    parser = Parser()
    for label, path in inputs:
        try:
            with open(path, encoding="utf-8", errors="replace") as fh:
                parser.parse(label, fh)
        except OSError as e:
            print(f"⚠️ cannot read {path}: {e}", file=sys.stderr)
    rep = parser.report(args.application_id)
    shorten_labels(rep)
    statuses = dict(x.partition("=")[::2] for x in args.container_status)
    for a in rep["applications"]:
        for i in a["instances"]:
            if i["instance"] in statuses:
                i["container_status"] = statuses[i["instance"]]
                if statuses[i["instance"]] != "running":
                    a["findings"].insert(0, f"🛑 {i['instance']}: the container is {statuses[i['instance']]}, "
                                            f"its last logged state ({i['state']}) is stale")
    write_html(rep, args)
    if args.json:
        print(json.dumps(rep, indent=2))
    elif rep["applications"]:
        sys.stdout.write(text(rep))
    return 0 if rep["applications"] else 2


if __name__ == "__main__":
    sys.exit(main())
