#!/usr/bin/env python3
"""Where the time of the connector tasks goes, from a Java Flight Recorder recording.

Reads the digest(s) printed by JfrDigest.java (one per recording, several for several connect workers) and reports, for
the selected threads (Kafka Connect task threads by default):

  - the time of each task thread by state: running, blocked on network I/O (by remote host), Kafka client, locks,
    waiting, file I/O
  - the CPU by layer (connector, converters, SMTs, Kafka client, libraries, logging, JDK), from the execution samples
  - the hot methods, the allocation by class and site, locks, GC and exceptions
  - findings: one sentence, a number, a next step

    jfr_analyzer.py --digest <digest.json> [--digest ...] [--connector-class <class>] [--connector-type sink|source]
                    [--mode drain|steady] [--source-url <github url>] [--top N] [--json] [--html-out <report.html>]

render_section() and render_comparison() are also used by tools/benchmark-report/benchmark_report.py.
"""
import argparse
import html
import json
import os
import sys
from collections import Counter, defaultdict

# ── classification of the frames ──────────────────────────────────────────────────────────────────────────────────

# frames that say nothing about who does the work: the time goes to the first frame below them
NEUTRAL = ("java.", "javax.", "jdk.", "sun.", "com.sun.", "kotlin.", "scala.", "org.apache.kafka.connect.data.",
           "com.google.common.", "org.apache.commons.", "com.fasterxml.jackson.", "org.apache.avro.", "com.google.protobuf.",
           "org.apache.kafka.connect.errors.")
LOGGING = ("org.apache.log4j.", "org.apache.logging.", "org.slf4j.", "ch.qos.logback.", "io.confluent.log4j.")
CONVERTERS = ("io.confluent.connect.avro.", "io.confluent.connect.json.", "io.confluent.connect.protobuf.",
              "io.confluent.connect.schema.", "io.confluent.kafka.serializers.", "io.confluent.kafka.schemaregistry.",
              "org.apache.kafka.connect.json.", "org.apache.kafka.connect.converters.",
              "org.apache.kafka.connect.storage.StringConverter", "org.apache.kafka.connect.storage.SimpleHeaderConverter",
              "com.networknt.", "org.everit.")
SMTS = ("org.apache.kafka.connect.transforms.", "io.confluent.connect.transforms.")
KAFKA_CLIENT = ("org.apache.kafka.clients.", "org.apache.kafka.common.")
FRAMEWORK = ("org.apache.kafka.connect.",)
CONNECTORS = ("io.confluent.connect.", "io.confluent.kafka.connect.", "io.debezium.", "com.github.jcustenborder.")

LAYERS = ["Connector", "Converters (serialization)", "SMTs", "Kafka client", "Connect framework", "Libraries (drivers, SDKs)",
          "Logging", "JDK"]

# state of the task threads: fixed order and color, a category keeps its color whatever the others
STATES = [
    ("running", "Running (CPU)", "var(--series-1)"),
    ("io", "Blocked on network I/O", "var(--series-2)"),
    ("kafka", "Kafka client (poll, send)", "var(--series-3)"),
    ("locks", "Lock contention", "var(--series-4)"),
    ("waiting", "Waiting (sleep, park, wait)", "var(--series-7)"),
    ("file", "File I/O", "var(--series-5)"),
    ("other", "Not attributed", "var(--axis)"),
]
# known slow code paths: when the execution samples of the task threads go through all the frames of an entry (prefixes),
# the finding names the issue instead of a generic "CPU in layer X"
KNOWN_ISSUES = [
    {"frames": ("org.apache.kafka.connect.storage.SimpleHeaderConverter", "java.math.BigInteger"),
     "title": "The header converter parses huge numbers (KAFKA-17792).",
     "text": "{share} of the task-thread CPU samples are in SimpleHeaderConverter parsing header values as numbers with "
             "java.math.BigInteger: string headers that look like huge numbers, such as the Zipkin B3 trace ids "
             "(X-B3-SpanId: 407127e212797209), cost seconds of CPU each.",
     "next": "A regression of Apache Kafka 3.8 and 3.9 (Confluent Platform 7.8.0, 7.8.1, 7.9.0 and 7.9.1), fixed in 3.9.1 and "
             "4.0.0 (Confluent Platform 7.8.2, 7.9.2 and later): upgrade the Connect workers, or set "
             "header.converter=org.apache.kafka.connect.storage.StringConverter on the connector, which keeps the headers "
             "as strings.",
     "link": "https://issues.apache.org/jira/browse/KAFKA-17792"},
]
BROKER_PORTS = {9091, 9092, 9093, 9094, 19092, 29092, 39092, 49092}


def is_neutral(frame):
    return frame.startswith(NEUTRAL) or frame.startswith("[")


def classify(stack, connector_package):
    """(layer, package of the frame that decided) of an execution sample, frames top first."""
    for frame in stack:
        if is_neutral(frame):
            continue
        if connector_package and frame.startswith(connector_package):
            return "Connector", package_root(frame)
        if frame.startswith(LOGGING):
            return "Logging", package_root(frame)
        if frame.startswith(CONVERTERS):
            return "Converters (serialization)", package_root(frame)
        if frame.startswith(SMTS):
            return "SMTs", package_root(frame)
        if frame.startswith(KAFKA_CLIENT):
            return "Kafka client", package_root(frame)
        if frame.startswith(FRAMEWORK):
            return "Connect framework", package_root(frame)
        if frame.startswith(CONNECTORS):
            return "Connector", package_root(frame)
        return "Libraries (drivers, SDKs)", package_root(frame)
    return "JDK", package_root(stack[0]) if stack else "-"


def package_root(frame):
    parts = frame.split(".")
    # package.Class.method: drop the class and the method
    pkg = [p for p in parts[:-2] if p]
    n = 4 if len(pkg) > 1 and pkg[1] in ("apache", "confluent") else 3 if len(pkg) > 1 and pkg[1] in ("google", "amazon", "microsoft", "ibm", "azure") else 2
    return ".".join(pkg[:n]) if pkg else frame


PRIMITIVES = {"B": "byte", "C": "char", "D": "double", "F": "float", "I": "int", "J": "long", "S": "short", "Z": "boolean"}


def pretty_class(name):
    """JVM names of arrays to java ones: [B -> byte[], [Ljava.lang.Object; -> java.lang.Object[]"""
    if not name or not name.startswith("["):
        return name
    dims = len(name) - len(name.lstrip("["))
    base = name[dims:]
    base = base[1:-1] if base.startswith("L") and base.endswith(";") else PRIMITIVES.get(base, base)
    return base + "[]" * dims


def first_non_neutral(stack):
    for frame in stack:
        if not is_neutral(frame):
            return frame
    return stack[0] if stack else "-"


def short_method(frame):
    """package.Class.method -> Class.method"""
    parts = frame.rsplit(".", 2)
    return ".".join(parts[-2:]) if len(parts) >= 2 else frame


def connector_package_of(connector_class):
    if not connector_class or "." not in connector_class:
        return None
    parts = connector_class.split(".")[:-1]
    # io.confluent.connect.jdbc.JdbcSinkConnector -> io.confluent.connect.jdbc.
    return ".".join(parts[:4]) + "."


def kafka_native(stack):
    return any(f.startswith("org.apache.kafka.clients.") for f in stack)


def native_category(stack):
    if kafka_native(stack):
        return "kafka"
    if any(f.startswith(("java.io.FileInputStream", "java.io.FileOutputStream", "java.io.RandomAccessFile", "sun.nio.ch.FileChannelImpl",
                         "sun.nio.fs.")) for f in stack):
        return "file"
    if any(f.startswith(("java.net.", "sun.nio.ch.")) for f in stack):
        return "io"
    return "other"


def is_broker(remote):
    host, _, port = remote.rpartition(":")
    try:
        port = int(port)
    except ValueError:
        port = 0
    return port in BROKER_PORTS or host.startswith(("broker", "kafka", "controller"))


# ── digest loading ────────────────────────────────────────────────────────────────────────────────────────────────

def load_digests(paths):
    model = {"files": [], "digests": [], "threads": [], "exec": Counter(), "monitor": [], "park": [], "alloc_classes": Counter(),
             "alloc_stacks": Counter(), "alloc_all": 0, "file_io": [], "gc": {"count": 0, "pause_total_ms": 0.0, "pause_max_ms": 0.0,
             "pause_p99_ms": None, "by_name": Counter(), "heap_after_gc_max_bytes": None}, "throwables": 0, "throwable_seconds": 0.0,
             "duration_s": 0.0, "jvm_versions": set(), "selection": set(), "thread_filter": None, "events": 0}
    for path in paths:
        with open(path) as f:
            d = json.load(f)
        frames = d.get("frames", [])

        def stack(ids):
            return tuple(frames[i] for i in ids if 0 <= i < len(frames))

        duration = float(d.get("duration_s") or 0)
        cpus = d.get("effective_cpus") or d.get("hw_threads") or 1
        model["files"] += d.get("files", [])
        model["events"] += d.get("events", 0)
        model["digests"].append({"duration_s": duration, "cpus": cpus, "start": d.get("start"), "end": d.get("end")})
        model["duration_s"] = max(model["duration_s"], duration)
        if d.get("jvm_version"):
            model["jvm_versions"].add(d["jvm_version"])
        model["selection"].add(d.get("thread_selection"))
        model["thread_filter"] = d.get("thread_filter")
        # the samples carry the context of the benchmark they come from
        for key in ("connector_class", "connector_type", "mode"):
            if d.get(key):
                model.setdefault("context", {})[key] = d[key]
        for t in d.get("threads", []):
            t = dict(t)
            t["duration_s"] = duration
            t["cpus"] = cpus
            t["native"] = [(c, stack(ids)) for c, ids in t.get("native_stacks", [])]
            model["threads"].append(t)
        for c, ids in d.get("exec_stacks", []):
            model["exec"][stack(ids)] += c
        for a in d.get("monitor", []):
            model["monitor"].append(dict(a, stack=stack(a.get("stack", []))))
        for a in d.get("park", []):
            model["park"].append(dict(a, stack=stack(a.get("stack", []))))
        for cls, b in d.get("alloc_classes", {}).items():
            model["alloc_classes"][pretty_class(cls)] += b
        for b, ids in d.get("alloc_stacks", []):
            model["alloc_stacks"][stack(ids)] += b
        model["alloc_all"] += d.get("alloc_all_threads_bytes", 0)
        model["file_io"] += d.get("file_io", [])
        gc = d.get("gc", {})
        mg = model["gc"]
        mg["count"] += gc.get("count", 0)
        mg["pause_total_ms"] += gc.get("pause_total_ms") or 0
        mg["pause_max_ms"] = max(mg["pause_max_ms"], gc.get("pause_max_ms") or 0)
        if gc.get("pause_p99_ms") is not None:
            mg["pause_p99_ms"] = max(mg["pause_p99_ms"] or 0, gc["pause_p99_ms"])
        for name, n in (gc.get("by_name") or {}).items():
            mg["by_name"][name] += n
        if gc.get("heap_after_gc_max_bytes") is not None:
            mg["heap_after_gc_max_bytes"] = max(mg["heap_after_gc_max_bytes"] or 0, gc["heap_after_gc_max_bytes"])
        ex = d.get("exceptions", {})
        if ex.get("throwables") is not None and ex.get("seconds"):
            model["throwables"] += ex["throwables"]
            model["throwable_seconds"] = max(model["throwable_seconds"], ex["seconds"])
    return model


# ── analysis ──────────────────────────────────────────────────────────────────────────────────────────────────────

def pct(x):
    return f"{x * 100:.0f}%"


def fmt_bytes(b):
    for unit, size in (("GB", 1e9), ("MB", 1e6), ("kB", 1e3)):
        if b >= size:
            return f"{b / size:.1f} {unit}"
    return f"{b:.0f} B"


def analyze(model, connector_class=None, connector_type=None, mode=None, source_url=None, top=10):
    connector_package = connector_package_of(connector_class)
    selected = [t for t in model["threads"] if t.get("selected")]
    if not connector_type:
        connector_type = infer_type(model, selected)
    duration = model["duration_s"]

    # share of the parks spent by the kafka producer (buffer full, metadata): kafka client time, not waiting
    park_total = sum(a["ms"] for a in model["park"]) or 0
    park_kafka = sum(a["ms"] for a in model["park"] if kafka_native(a["stack"]))
    kafka_park_share = park_kafka / park_total if park_total else 0

    remotes = defaultdict(lambda: {"ms": 0.0, "count": 0, "bytes": 0, "broker": False})
    io_short = {}
    thread_states = []
    for t in selected:
        d_ms = (t["duration_s"] or duration or 1) * 1000
        v = {k: 0.0 for k, _, _ in STATES}
        if t.get("cpu_n"):
            v["running"] = min(1.0, ((t.get("cpu_user") or 0) + (t.get("cpu_system") or 0)) * t["cpus"])
        io_remotes = {}
        for s in t.get("socket", []):
            r = remotes[s["remote"]]
            r["ms"] += s["ms"]
            r["count"] += s["count"]
            r["bytes"] += s["bytes"]
            r["broker"] = is_broker(s["remote"])
            key = "kafka" if r["broker"] else "io"
            v[key] += s["ms"] / d_ms
            if not r["broker"]:
                io_remotes[s["remote"]] = io_remotes.get(s["remote"], 0) + s["ms"] / d_ms
        v["file"] += (t.get("file_ms") or 0) / d_ms
        v["locks"] += (t.get("monitor_ms") or 0) / d_ms
        park = (t.get("park_ms") or 0) / d_ms
        v["kafka"] += park * kafka_park_share
        v["waiting"] += park * (1 - kafka_park_share) + ((t.get("wait_ms") or 0) + (t.get("sleep_ms") or 0)) / d_ms
        attributed = sum(v.values())
        if attributed > 1:
            for k in v:
                v[k] /= attributed
            for k in io_remotes:
                io_remotes[k] /= attributed
            attributed = 1.0
        # the rest: native code (a consumer poll in epoll, short socket calls), split by the native samples of the thread
        rest = 1 - attributed
        natives = Counter()
        io_natives = Counter()
        for c, st in t.get("native", []):
            cat = native_category(st)
            natives[cat] += c
            if cat == "io":
                io_natives[package_root(first_non_neutral(st))] += c
        n = sum(natives.values())
        if rest > 0 and n:
            for cat, c in natives.items():
                v[cat] += rest * c / n
            # short network calls (under 1 ms, no event): to the remote when the thread talks to one system only
            own = [r for r in io_remotes]
            for lib, c in io_natives.items():
                label = own[0] if len(own) == 1 else f"calls from {lib}"
                io_short[label] = io_short.get(label, 0) + rest * c / n / max(len(selected), 1)
                io_remotes[label] = io_remotes.get(label, 0) + rest * c / n
        else:
            v["other"] += max(rest, 0)
        thread_states.append({"name": t["name"], "values": v, "io_remotes": io_remotes, "exec_samples": t.get("exec_samples", 0)})
    thread_states.sort(key=lambda s: natural_key(s["name"]))
    mean = {k: (sum(s["values"][k] for s in thread_states) / len(thread_states) if thread_states else 0) for k, _, _ in STATES}

    # cpu by layer and hot methods, from the execution samples of the selected threads
    nb_exec = sum(model["exec"].values())
    layers = Counter()
    layer_packages = defaultdict(Counter)
    methods = Counter()
    method_self = defaultdict(Counter)
    method_layer = defaultdict(Counter)
    for st, c in model["exec"].items():
        layer, pkg = classify(st, connector_package)
        layers[layer] += c
        layer_packages[layer][pkg] += c
        m = first_non_neutral(st)
        methods[m] += c
        if st:
            method_self[m][st[0]] += c
        method_layer[m][layer] += c
    layer_rows = []
    for layer in LAYERS:
        if layers[layer] == 0:
            continue
        pk = layer_packages[layer]
        layer_rows.append({"layer": layer, "samples": layers[layer], "share": layers[layer] / nb_exec,
                           "packages": [{"package": p, "share": c / nb_exec} for p, c in pk.most_common(3)]})
    layer_rows.sort(key=lambda r: -r["share"])
    # several java threads under one task thread name: the previous thread of a restarted task is still running
    abandoned = sorted(((t["name"], t["java_threads"]) for t in selected if (t.get("java_threads") or 0) > 1), key=lambda x: natural_key(x[0]))
    known = []
    for issue in KNOWN_ISSUES:
        c = sum(n for st, n in model["exec"].items() if all(any(f.startswith(p) for f in st) for p in issue["frames"]))
        if nb_exec and c / nb_exec >= 0.2:
            known.append(dict(issue, share=c / nb_exec))
    hot = []
    github = source_url if source_url and source_url.startswith("https://github.com/") else None
    for m, c in methods.most_common(top):
        layer = method_layer[m].most_common(1)[0][0]
        self_frame = method_self[m].most_common(1)[0][0] if method_self[m] else m
        link = None
        if github and layer == "Connector":
            cls = m.rsplit(".", 2)[-2] if m.count(".") >= 2 else m
            link = github.rstrip("/") + "/search?q=" + cls.split("$")[0]
        hot.append({"method": m, "share": c / nb_exec, "layer": layer, "self": self_frame if self_frame != m else None, "link": link})

    # allocation
    alloc_total = sum(model["alloc_classes"].values())
    alloc = {"rate_bytes_s": alloc_total / duration if duration else 0, "total_bytes": alloc_total,
             "all_threads_rate_bytes_s": model["alloc_all"] / duration if duration else 0,
             "classes": [{"class": cls, "bytes_s": b / duration if duration else 0, "share": b / alloc_total}
                         for cls, b in model["alloc_classes"].most_common(top)] if alloc_total else [],
             "sites": []}
    sites = Counter()
    for st, b in model["alloc_stacks"].items():
        sites[first_non_neutral(st)] += b
    stotal = sum(sites.values())
    alloc["sites"] = [{"method": m, "share": b / stotal} for m, b in sites.most_common(5)] if stotal else []

    # locks and waits by site
    def by_site(aggs):
        rows = defaultdict(lambda: {"ms": 0.0, "count": 0, "class": None, "kind": None})
        for a in aggs:
            key = (a.get("kind"), a.get("class"), first_non_neutral(a["stack"]))
            r = rows[key]
            r["ms"] += a["ms"]
            r["count"] += a["count"]
            r["class"], r["kind"], r["site"] = a.get("class"), a.get("kind"), key[2]
        return sorted(rows.values(), key=lambda r: -r["ms"])[:top]
    locks = by_site(model["monitor"])
    waits = by_site(model["park"])

    io = sorted(({"remote": r, **v} for r, v in remotes.items()), key=lambda x: -x["ms"])
    nb_threads = len(thread_states) or 1
    for x in io:
        x["share"] = x["ms"] / 1000 / (duration or 1) / nb_threads
        x["short_share"] = io_short.pop(x["remote"], 0)
    # short calls of libraries talking to several systems, without a remote
    for label, share in io_short.items():
        io.append({"remote": label, "ms": 0.0, "count": 0, "bytes": 0, "broker": False, "share": 0.0, "short_share": share})
    io.sort(key=lambda x: -(x["share"] + x["short_share"]))

    # busiest threads of the whole jvm (cpu cores)
    top_threads = []
    for t in model["threads"]:
        if t.get("cpu_n"):
            top_threads.append({"name": t["name"], "cores": ((t.get("cpu_user") or 0) + (t.get("cpu_system") or 0)) * t["cpus"],
                                "selected": bool(t.get("selected"))})
    top_threads.sort(key=lambda x: -x["cores"])
    jit_cores = sum(t["cores"] for t in top_threads if t["name"].startswith(("C1 CompilerThread", "C2 CompilerThread")))
    task_cores = sum(t["cores"] for t in top_threads if t["selected"])
    top_threads = top_threads[:top]

    gc = dict(model["gc"])
    gc["by_name"] = dict(gc["by_name"])
    gc["percent"] = gc["pause_total_ms"] / 10 / duration if duration else None
    exceptions_per_s = model["throwables"] / model["throwable_seconds"] if model["throwable_seconds"] else None

    analysis = {
        "recording": {"files": model["files"], "duration_s": duration, "events": model["events"],
                      "jvm_versions": sorted(model["jvm_versions"]), "thread_filter": model["thread_filter"],
                      "thread_selection": "all" if "all" in model["selection"] else "filter",
                      "threads": [s["name"] for s in thread_states], "workers": len(model["digests"]),
                      "cpus": sorted({d["cpus"] for d in model["digests"]})},
        "connector_class": connector_class, "connector_type": connector_type, "mode": mode,
        "states": {"categories": [{"key": k, "label": label, "color": color} for k, label, color in STATES],
                   "threads": thread_states, "mean": mean},
        "jit_cores": jit_cores, "task_cores": task_cores,
        "exec_samples": nb_exec, "layers": layer_rows, "hot_methods": hot, "known_issues": known, "abandoned_threads": abandoned, "alloc": alloc,
        "locks": locks, "waits": waits, "io": io, "top_threads": top_threads, "gc": gc,
        "exceptions_per_s": exceptions_per_s,
        "file_io": sorted(model["file_io"], key=lambda x: -x["ms"])[:top],
    }
    analysis["findings"], analysis["normal"] = findings(analysis)
    return analysis


def infer_type(model, selected):
    """sink or source, from the connect frames of the task threads (WorkerSinkTask / WorkerSourceTask)"""
    seen = Counter()
    stacks = [st for st in model["exec"]] + [st for t in selected for _, st in t.get("native", [])]
    for st in stacks:
        for f in st:
            if f.startswith("org.apache.kafka.connect.runtime.WorkerSinkTask."):
                seen["sink"] += 1
                break
            if f.startswith(("org.apache.kafka.connect.runtime.WorkerSourceTask.", "org.apache.kafka.connect.runtime.AbstractWorkerSourceTask.",
                             "org.apache.kafka.connect.runtime.ExactlyOnceWorkerSourceTask.")):
                seen["source"] += 1
                break
    return seen.most_common(1)[0][0] if seen else None


def natural_key(name):
    import re
    return [int(p) if p.isdigit() else p for p in re.split(r"(\d+)", name)]


SEVERITY_ORDER = {"critical": 0, "warning": 1, "info": 2}


def findings(a):
    out, normal = [], []
    m = a["states"]["mean"]
    nb_threads = len(a["states"]["threads"])
    ctype, mode = a.get("connector_type"), a.get("mode")
    layers = {r["layer"]: r["share"] for r in a["layers"]}
    io = [x for x in a["io"] if not x["broker"]]

    def add(severity, title, text, next_step=None, link=None):
        out.append({"severity": severity, "title": title, "text": text, "next": next_step, "link": link})

    for k in a.get("known_issues", []):
        add("critical", k["title"], k["text"].format(share=pct(k["share"])), k["next"], k["link"])
    if a.get("abandoned_threads"):
        names = ", ".join(f"{n} ({c} threads)" for n, c in a["abandoned_threads"])
        add("warning", "A restarted task left its previous thread running.",
            f"Several java threads run under the same task thread name: {names}. Connect cannot stop a thread: when a task is "
            "restarted while it is stuck (a put or a conversion that does not return), the old thread keeps running next to "
            "the new one, and the CPU and samples of the tasks below include it.",
            "Restart the worker to get rid of it, once the cause is fixed: until then it keeps using CPU.")

    if nb_threads == 0:
        add("info", "No task thread in the recording.",
            f"No thread matched {a['recording']['thread_filter']}: the analysis covers every thread of the JVM.")
    if m["io"] >= 0.2 and io:
        r = io[0]
        avg = r["ms"] / r["count"] if r["count"] else 0
        parts = []
        if r["count"]:
            parts.append(f"{pct(r['share'])} in {r['count']:,} calls of 1 ms or more, {avg:.1f} ms on average")
        if r.get("short_share", 0) >= 0.005:
            parts.append(f"{pct(r['short_share'])} in shorter calls seen by the native samples")
        add("critical" if m["io"] >= 0.4 else "warning",
            f"The tasks wait on {r['remote']}." if m["io"] >= 0.4 else f"The tasks spend {pct(m['io'])} of the time on network I/O.",
            f"The task threads spent {pct(m['io'])} of the recording blocked on network I/O, {pct(r['share'] + r.get('short_share', 0))} "
            f"on {r['remote']} ({'; '.join(parts)}), and were running only {pct(m['running'])} of the time.",
            "The system behind the connector (or the network to it) is the limit, not the connector code: look at its latency "
            "and load, at how the connector batches its calls, and at tasks.max.")
    else:
        normal.append(("Network I/O", f"{pct(m['io'])} of the task time blocked on calls of 1 ms or more"))
    if m["kafka"] >= 0.4:
        if ctype == "sink":
            fetch = ("the fetch is the limit: consumer.override.max.poll.records, fetch.max.bytes, max.partition.fetch.bytes "
                     "and fetch.min.bytes, and the number of partitions of the topic (one task reads its partitions one fetch at a time).")
            next_step = {"drain": "The backlog was there, so " + fetch,
                         "steady": "The load is slower than the connector: measure its maximum with --mode drain."}.get(
                mode, "Either the topic had no data (the load is slower than the connector), or " + fetch)
            add("warning" if mode == "drain" else "info", "The tasks wait for records from Kafka.",
                f"The task threads spent {pct(m['kafka'])} of the recording in the Kafka consumer (poll, fetch).", next_step)
        elif ctype == "source":
            add("warning", "The tasks wait for the Kafka producer.",
                f"The task threads spent {pct(m['kafka'])} of the recording in the Kafka producer (buffer full, metadata).",
                "The producer or the brokers are the limit: producer.override.linger.ms, batch.size, buffer.memory, "
                "compression.type, and the throughput of the brokers.")
        else:
            add("info", "The tasks spend most of their time in the Kafka client.",
                f"The task threads spent {pct(m['kafka'])} of the recording in the Kafka client (poll, fetch, send).")
    else:
        normal.append(("Kafka client", f"{pct(m['kafka'])} of the task time in the Kafka client (poll, send)"))
    if m["locks"] >= 0.1 and a["locks"]:
        lk = a["locks"][0]
        add("warning", "The tasks contend on a lock.",
            f"The task threads spent {pct(m['locks'])} of the recording waiting to enter a monitor, mostly "
            f"{lk['class'] or 'a lock'} in {short_method(lk['site'])} ({lk['ms'] / 1000:.1f} s over {lk['count']:,} waits).",
            "Tasks serialised on a shared lock do not scale with tasks.max: look at what is shared between them.")
    else:
        normal.append(("Lock contention", f"{pct(m['locks'])} of the task time"))
    if m["waiting"] >= 0.4:
        site = next((w for w in a["waits"] if not kafka_native((w["site"],))), None)
        where = f", mostly in {short_method(site['site'])} ({site['kind']})" if site else ""
        add("warning", f"The tasks sleep or wait {pct(m['waiting'])} of the time.",
            f"The task threads spent {pct(m['waiting'])} of the recording sleeping, parked or waiting{where}.",
            "A poll interval, a backoff or a retry loop: check the poll.interval.ms / retry.backoff.ms settings of the "
            "connector and its logs.")
    if m["running"] >= 0.8:
        add("warning", "The tasks are CPU bound.",
            f"The task threads were running {pct(m['running'])} of the recording.",
            "The code path is the limit: see the CPU by layer and the hot methods below. More tasks help only if the worker "
            "has idle cpus.")
    if a["exec_samples"] >= 50:
        sev = "warning" if m["running"] >= 0.5 else "info"
        conv, conn = layers.get("Converters (serialization)", 0), layers.get("Connector", 0)
        # a known issue in a converter already says why
        if conv >= 0.3 and not a.get("known_issues"):
            add(sev, "Most of the CPU goes to conversion.",
                f"{pct(conv)} of the task-thread CPU samples are in converters and serializers, against {pct(conn)} in the "
                "connector itself.",
                "Expected with large or nested records. If the CPU is the limit, compare with another converter or a smaller "
                "schema before tuning the connector.")
        top = a["hot_methods"][0] if a["hot_methods"] else None
        if top and top["share"] >= 0.5 and not a.get("known_issues"):
            add(sev, f"One method takes {pct(top['share'])} of the CPU of the tasks.",
                f"{pct(top['share'])} of the task-thread CPU samples are in {short_method(top['method'])}"
                + (f" (running {short_method(top['self'])})" if top.get("self") else "") + f", {top['layer'].lower()} layer.",
                "A single hot spot: search the issue tracker of that code for it with the class name, and look at what in the "
                "records (size, headers, values) makes it expensive.")
        if layers.get("Logging", 0) >= 0.1:
            add("warning", "Logging takes a large part of the CPU.",
                f"{pct(layers['Logging'])} of the task-thread CPU samples are in logging.",
                "A DEBUG or TRACE log level slows the connector down: check it with playground debug log-level get, set it "
                "back with playground debug log-level set --level INFO.")
        if layers.get("SMTs", 0) >= 0.2:
            add(sev, "The transforms take a large part of the CPU.", f"{pct(layers['SMTs'])} of the task-thread CPU samples are in SMTs.",
                "See which one with playground connector smt test.")
    elif nb_threads:
        add("info", "Few CPU samples.", f"Only {a['exec_samples']} execution samples of the task threads: the tasks were rarely "
            "running Java code, the CPU by layer and the hot methods are not meaningful.")
    rate = a["alloc"]["rate_bytes_s"]
    if rate >= 300e6 and a["alloc"]["classes"]:
        c = a["alloc"]["classes"][0]
        site = a["alloc"]["sites"][0]["method"] if a["alloc"]["sites"] else None
        add("warning" if rate >= 1e9 else "info", "Allocation is high.",
            f"The task threads allocate {fmt_bytes(rate)}/s, {pct(c['share'])} of it as {c['class']}"
            + (f", mostly from {short_method(site)}" if site else "") + ".",
            "This is what keeps the GC busy: check the GC pauses before comparing runs, and KAFKA_HEAP_OPTS if they grow.")
    else:
        normal.append(("Allocation", f"{fmt_bytes(rate)}/s by the task threads"))
    eps = a["exceptions_per_s"]
    if eps is not None and eps >= 100:
        add("warning" if eps >= 1000 else "info", "Many exceptions are thrown.",
            f"The JVM throws {eps:,.0f} exceptions per second (all threads).",
            "Exceptions thrown and caught in a loop: retries, errors.tolerance=all, or a library using exceptions for "
            "control flow. Look at the connector logs at DEBUG.")
    elif eps is not None:
        normal.append(("Exceptions thrown", f"{eps:,.0f} per second"))
    gc = a["gc"]
    if gc["count"] and gc["pause_max_ms"] >= 200:
        add("warning", "Long GC pauses.", f"The longest GC pause took {gc['pause_max_ms']:.0f} ms ({gc['count']} collections, "
            f"{gc['percent']:.1f}% of the time in pauses).", "Increase the heap of the worker (KAFKA_HEAP_OPTS) or look at what allocates.")
    elif gc["count"]:
        normal.append(("GC pauses", f"{gc['count']} collections, longest {gc['pause_max_ms']:.0f} ms, p99 {gc['pause_p99_ms'] or 0:.0f} ms"))
    if a.get("jit_cores", 0) >= 0.5 and a["jit_cores"] > a.get("task_cores", 0) >= 0.05:
        add("warning" if mode else "info", "The JVM was still compiling code (JIT).",
            f"The JIT compiler threads used {a['jit_cores']:.1f} cores on average, more than the task threads "
            f"({a['task_cores']:.2f}): the code of the connector was not at its full speed yet.",
            "The measure includes the warm-up of the JVM: increase --nb-records (or --duration), or run the benchmark twice "
            "and keep the second run." if mode else "The JVM had just started, or a new code path was hit.")
    if m["other"] >= 0.5 and nb_threads:
        add("info", f"{pct(m['other'])} of the task time is not attributed.",
            "Time in native code without a sample, or I/O shorter than 1 ms: the recording cannot tell where it goes.")
    out.sort(key=lambda f: SEVERITY_ORDER[f["severity"]])
    return out, [{"label": k, "text": v} for k, v in normal]


# ── comparison of runs (connector versions) ───────────────────────────────────────────────────────────────────────

def compare(entries, noun="version"):
    """entries: [{"version", "records_per_second", "analyses": [analysis...]}], first one is the reference."""
    rows = []
    for e in entries:
        layers, states, hot = Counter(), Counter(), Counter()
        n = len(e["analyses"]) or 1
        for a in e["analyses"]:
            for r in a["layers"]:
                layers[r["layer"]] += r["share"] / n
            for k, v in a["states"]["mean"].items():
                states[k] += v / n
            for h in a["hot_methods"]:
                hot[h["method"]] += h["share"] / n
        rows.append({"version": e["version"], "records_per_second": e.get("records_per_second"), "layers": dict(layers),
                     "states": dict(states), "hot": dict(hot)})
    out = []
    if len(rows) < 2:
        return {"versions": rows, "findings": out}
    ref = rows[0]
    for r in rows[1:]:
        if not ref["records_per_second"] or not r["records_per_second"]:
            continue
        delta = (r["records_per_second"] - ref["records_per_second"]) / ref["records_per_second"] * 100
        if abs(delta) < 5:
            continue
        slower = delta < 0
        # what grew the most (slower) or shrank the most (faster), among the layers and the states
        changes = []
        for k in set(ref["layers"]) | set(r["layers"]):
            changes.append(("layer", k, r["layers"].get(k, 0) - ref["layers"].get(k, 0)))
        for k, label, _ in STATES:
            if k == "other":
                continue
            changes.append(("state", label, r["states"].get(k, 0) - ref["states"].get(k, 0)))
        kind, name, d = max(changes, key=lambda c: c[2] if slower else -c[2])
        text = (f"{r['version']} processes {abs(delta):.0f}% {'fewer' if slower else 'more'} records per second than {ref['version']} "
                f"({r['records_per_second']:,.0f} vs {ref['records_per_second']:,.0f}).")
        if abs(d) >= 0.05:
            before = ref["layers" if kind == "layer" else "states"]
            after = r["layers" if kind == "layer" else "states"]
            key = name if kind == "layer" else next(k for k, label, _ in STATES if label == name)
            what = f"{name} went from {pct(before.get(key, 0))} to {pct(after.get(key, 0))} of the " + \
                ("task-thread CPU samples" if kind == "layer" else "task time")
            text += f" {what}."
            hd = max(((m, r["hot"].get(m, 0) - ref["hot"].get(m, 0)) for m in set(r["hot"]) | set(ref["hot"])),
                     key=lambda x: x[1] if slower else -x[1], default=None)
            if hd and abs(hd[1]) >= 0.03:
                text += f" Hot method that changed the most: {hd[0]} ({pct(ref['hot'].get(hd[0], 0))} → {pct(r['hot'].get(hd[0], 0))})."
            title = f"{r['version']} is {abs(delta):.0f}% {'slower' if slower else 'faster'}: the difference is in {name if name.startswith(('Kafka', 'JDK', 'SMTs')) else name[0].lower() + name[1:]}."
        else:
            title = f"{r['version']} is {abs(delta):.0f}% {'slower' if slower else 'faster'}, with the same profile."
            text += " No layer or state changed by 5 points or more: the difference is spread out."
        out.append({"severity": "critical" if slower and delta <= -15 else "warning" if slower else "info",
                    "title": title, "text": text,
                    "next": "Look at the changes between the two versions in that area." if noun == "version" else
                    "The phases work on the same rows: the difference comes from the type of change and the records it gives "
                    "(an update carries the before and after images, a delete can give a tombstone too)."})
    return {"versions": rows, "findings": out}


# ── text output ───────────────────────────────────────────────────────────────────────────────────────────────────

ICONS = {"critical": "🔴", "warning": "🟠", "info": "ℹ️ "}


def text_report(a, top):
    rec = a["recording"]
    lines = [f"🛩️  Flight recording of {rec['duration_s']:.0f} s, {len(rec['threads'])} task thread(s)"
             + (" (no task thread: all threads)" if rec["thread_selection"] == "all" else "")
             + (f", {rec['workers']} workers" if rec["workers"] > 1 else ""), ""]
    if a["findings"]:
        lines.append("Findings")
        for f in a["findings"]:
            lines.append(f"  {ICONS[f['severity']]} {f['title']} {f['text']}")
            if f.get("next"):
                lines.append(f"     → {f['next']}")
            if f.get("link"):
                lines.append(f"     ↗ {f['link']}")
        lines.append("")
    lines.append("Task thread time, by state (mean of the task threads)")
    for k, label, _ in STATES:
        v = a["states"]["mean"][k]
        if v >= 0.005:
            lines.append(f"  {label:<30} {pct(v):>5}")
    lines.append("")
    if a["layers"]:
        lines.append(f"CPU of the task threads, by layer ({a['exec_samples']:,} samples)")
        for r in a["layers"]:
            pk = ", ".join(p["package"] for p in r["packages"])
            lines.append(f"  {r['layer']:<30} {pct(r['share']):>5}   {pk}")
        lines.append("")
        lines.append("Hot methods")
        for h in a["hot_methods"][:top]:
            lines.append(f"  {pct(h['share']):>5}  {h['method']}" + (f"  (in {short_method(h['self'])})" if h["self"] else ""))
        lines.append("")
    if a["io"]:
        lines.append("Network I/O of the task threads (calls of 1 ms or more, and shorter calls seen by the native samples)")
        for x in a["io"][:top]:
            lines.append(f"  {x['remote']:<30} {x['count']:>8,} calls  {x['ms'] / 1000:>8.1f} s  {pct(x['share']):>5} + {pct(x.get('short_share', 0)):>4} shorter"
                         " of the task time")
        lines.append("")
    if a["normal"]:
        lines.append("Checked and normal: " + "; ".join(f"{n['label']}: {n['text']}" for n in a["normal"]))
    return "\n".join(lines)


# ── html ──────────────────────────────────────────────────────────────────────────────────────────────────────────

SECTION_CSS = """
.jfr-section { margin-top: 26px; }
.jfr-section > h2 { font-size: 1.15rem; margin: 0 0 4px; }
.jfr-findings { list-style: none; margin: 14px 0 18px; padding: 0; display: grid; gap: 8px; }
.jfr-findings li { background: var(--surface-1); border: 1px solid var(--border); border-left: 4px solid var(--sev); border-radius: 8px;
  padding: 10px 14px; font-size: .875rem; line-height: 1.45; }
.jfr-findings .title { font-weight: 600; margin-right: 6px; }
.jfr-findings .next { color: var(--text-secondary); display: block; margin-top: 3px; }
.jfr-section code { font-family: 'SFMono-Regular', Consolas, Menlo, monospace; font-size: .78rem; }
.jfr-section .muted { color: var(--text-muted); }
.jfr-verdict { margin: 18px 0 0; padding: 12px 16px; border-left: 4px solid var(--sev); font-size: 1rem; font-weight: 500; }
.jfr-section td code { word-break: break-all; }
"""

TOOLTIP_JS = """
<script>
(function () {
  document.querySelectorAll(".jfr-section .card").forEach(card => {
    const tt = card.querySelector(".tooltip");
    if (!tt) return;
    card.querySelectorAll("[data-tip]").forEach(el => {
      const show = e => {
        const r = card.getBoundingClientRect();
        tt.textContent = el.dataset.tip; tt.style.display = "block";
        const x = (e.clientX !== undefined ? e.clientX : el.getBoundingClientRect().left) - r.left + 12;
        const y = (e.clientY !== undefined ? e.clientY : el.getBoundingClientRect().top) - r.top + 12;
        tt.style.left = Math.min(x, r.width - tt.offsetWidth - 8) + "px"; tt.style.top = y + "px";
      };
      el.addEventListener("pointermove", show); el.addEventListener("focus", show);
      el.addEventListener("pointerleave", () => tt.style.display = "none"); el.addEventListener("blur", () => tt.style.display = "none");
    });
  });
})();
</script>
"""

SEV_COLOR = {"critical": "var(--critical)", "warning": "var(--warning)", "info": "var(--axis)"}
e = html.escape


def tip(text):
    return f' data-tip="{e(text, quote=True)}" tabindex="0"'


def findings_html(items):
    if not items:
        return ""
    lis = []
    for f in items:
        nxt = f'<span class="next">→ {e(f["next"])}</span>' if f.get("next") else ""
        if f.get("link"):
            nxt += f'<span class="next">↗ <a href="{e(f["link"], quote=True)}" target="_blank" rel="noopener">{e(f["link"])}</a></span>'

        lis.append(f'<li style="--sev: {SEV_COLOR[f["severity"]]}"><span class="title">{ICONS[f["severity"]].strip()} {e(f["title"])}</span>'
                   f'{e(f["text"])}{nxt}</li>')
    return '<ul class="jfr-findings">' + "".join(lis) + "</ul>"


def states_svg(a):
    threads = a["states"]["threads"]
    if not threads:
        return '<div class="empty">🤷 no task thread in the recording</div>'
    w, left, rowh, gap, top = 640, 150, 24, 12, 6
    plot = w - left - 8
    height = top + len(threads) * (rowh + gap) + 20
    out = [f'<svg viewBox="0 0 {w} {height}" role="img" aria-label="Task thread time by state">']
    bottom = top + len(threads) * (rowh + gap) - gap
    for g in range(0, 101, 25):
        x = left + plot * g / 100
        out.append(f'<line x1="{x:.1f}" x2="{x:.1f}" y1="{top - 4}" y2="{bottom + 4}" stroke="var(--grid)"/>')
        out.append(f'<text x="{x:.1f}" y="{bottom + 18}" fill="var(--text-muted)" font-size="11" text-anchor="middle">{g}%</text>')
    labels = {k: label for k, label, _ in STATES}
    for i, t in enumerate(threads):
        y = top + i * (rowh + gap)
        name = t["name"].replace("task-thread-", "")
        out.append(f'<text x="{left - 8}" y="{y + rowh / 2 + 4}" fill="var(--text-secondary)" font-size="12" text-anchor="end">{e(name[-24:])}</text>')
        x = left
        segs = [(k, color, t["values"][k]) for k, _, color in STATES if t["values"][k] > 0.0005]
        for j, (k, color, v) in enumerate(segs):
            sw = plot * v
            detail = ""
            if k == "io" and t["io_remotes"]:
                detail = " (" + ", ".join(f"{r} {pct(f)}" for r, f in sorted(t["io_remotes"].items(), key=lambda x: -x[1])[:3]) + ")"
            rx = 3 if j in (0, len(segs) - 1) else 0
            out.append(f'<rect x="{x:.1f}" y="{y}" width="{max(sw - 2, 0.8):.1f}" height="{rowh}" rx="{rx}" fill="{color}"'
                       f'{tip(t["name"] + " · " + labels[k] + ": " + pct(v) + detail)}/>')
            if v >= 0.08:
                out.append(f'<text x="{x + sw / 2 - 1:.1f}" y="{y + rowh / 2 + 4}" fill="#fff" font-size="11" font-weight="600" '
                           f'text-anchor="middle" pointer-events="none">{pct(v)}</text>')
            x += sw
    out.append("</svg>")
    return "".join(out)


def layers_svg(a):
    rows = a["layers"]
    if not rows:
        return '<div class="empty">🤷 no execution sample of the task threads</div>'
    w, left, rowh, gap, top = 640, 190, 20, 9, 4
    plot = w - left - 50
    mx = max(r["share"] for r in rows)
    mx = max(0.1, min(1.0, (int(mx * 10) + 1) / 10))
    height = top + len(rows) * (rowh + gap) + 18
    bottom = top + len(rows) * (rowh + gap) - gap
    out = [f'<svg viewBox="0 0 {w} {height}" role="img" aria-label="CPU of the task threads by layer">']
    step = 0.1 if mx <= 0.5 else 0.2
    g = 0.0
    while g <= mx + 1e-9:
        x = left + plot * g / mx
        out.append(f'<line x1="{x:.1f}" x2="{x:.1f}" y1="0" y2="{bottom + 2}" stroke="var(--grid)"/>')
        out.append(f'<text x="{x:.1f}" y="{bottom + 14}" fill="var(--text-muted)" font-size="11" text-anchor="middle">{g * 100:.0f}%</text>')
        g += step
    for i, r in enumerate(rows):
        y = top + i * (rowh + gap)
        out.append(f'<text x="{left - 8}" y="{y + rowh / 2 + 4}" fill="var(--text-secondary)" font-size="12" text-anchor="end">{e(r["layer"])}</text>')
        bw = max(plot * r["share"] / mx, 1)
        rad = min(4, bw / 2)
        pk = ", ".join(f'{p["package"]} {pct(p["share"])}' for p in r["packages"])
        out.append(f'<path d="M{left},{y} h{bw - rad:.1f} a{rad},{rad} 0 0 1 {rad},{rad} v{rowh - 2 * rad} a{rad},{rad} 0 0 1 -{rad},{rad} '
                   f'h-{bw - rad:.1f} z" fill="var(--series-1)"{tip(r["layer"] + ": " + pct(r["share"]) + " of the CPU samples (" + pk + ")")}/>')
        out.append(f'<text x="{left + bw + 6:.1f}" y="{y + rowh / 2 + 4}" fill="var(--text-primary)" font-size="12">{pct(r["share"])}</text>')
    out.append("</svg>")
    return "".join(out)


def table(header, rows, nums=()):
    th = "".join(f'<th{" class=num" if i in nums else ""}>{e(h)}</th>' for i, h in enumerate(header))
    trs = "".join("<tr>" + "".join(f'<td{" class=num" if i in nums else ""}>{c}</td>' for i, c in enumerate(r)) + "</tr>" for r in rows)
    return f"<table><tr>{th}</tr>{trs}</table>"


def render_section(a, title="🛩️ Where the time goes", recording_link=None, subtitle_prefix=""):
    rec = a["recording"]
    legend = "".join(f'<span style="--c: {color}">{e(label)}</span>' for k, label, color in STATES
                     if any(t["values"][k] > 0.0005 for t in a["states"]["threads"]))
    threads = rec["threads"]
    thread_text = (f"task threads <code>{e(threads[0])}</code>" + (f" … <code>{e(threads[-1])}</code>" if len(threads) > 1 else "")
                   if rec["thread_selection"] == "filter" and threads else "all threads (no thread matched the filter)")
    link = f' · recording <a href="{e(recording_link, quote=True)}">{e(os.path.basename(recording_link))}</a> (opens in JDK Mission Control)' \
        if recording_link else ""
    sub = (f'{e(subtitle_prefix)}Java Flight Recorder, {rec["duration_s"]:.0f} s · {thread_text}'
           + (f' · {rec["workers"]} workers' if rec["workers"] > 1 else "") + link)
    state_rows = [[e(t["name"])] + [pct(t["values"][k]) for k, _, _ in STATES] for t in a["states"]["threads"]]
    state_table = table(["Thread"] + [label for _, label, _ in STATES], state_rows, nums=range(1, len(STATES) + 1))
    layer_table = table(["Layer", "Top packages", "CPU samples"],
                        [[e(r["layer"]), e(", ".join(f'{p["package"]} {pct(p["share"])}' for p in r["packages"])), pct(r["share"])]
                         for r in a["layers"]], nums=(2,))
    hot_rows = []
    for h in a["hot_methods"]:
        cell = f'<code>{e(h["method"])}</code>'
        if h.get("self"):
            cell += f' <span class="muted">in {e(short_method(h["self"]))}</span>'
        if h.get("link"):
            cell += f' <a href="{e(h["link"], quote=True)}" target="_blank" rel="noopener">source</a>'
        hot_rows.append([cell, e(h["layer"]), pct(h["share"])])
    alloc = a["alloc"]
    alloc_rows = [[f'<code>{e(c["class"])}</code>', f'{c["bytes_s"] / 1e6:,.0f}', pct(c["share"])] for c in alloc["classes"][:6]]
    io_rows = [[f'<code>{e(x["remote"])}</code>' + (' <span class="muted">broker</span>' if x["broker"] else ""), f'{x["count"]:,}',
                f'{x["ms"] / x["count"] if x["count"] else 0:.1f}', f'{x["ms"] / 1000:,.1f}', pct(x["share"]), pct(x.get("short_share", 0))]
               for x in a["io"][:6]]
    normal_rows = [[f'✅ {e(n["label"])}', e(n["text"])] for n in a["normal"]]
    other_rows = []
    for lk in a["locks"][:3]:
        other_rows.append([f'<code>{e(short_method(lk["site"]))}</code>', e(lk["class"] or "-"), f'{lk["count"]:,}', f'{lk["ms"] / 1000:,.1f}'])
    waits_rows = [[f'<code>{e(short_method(w["site"]))}</code>', e(w["kind"] or "-"), f'{w["count"]:,}', f'{w["ms"] / 1000:,.1f}']
                  for w in a["waits"][:5]]
    top_rows = [[e(t["name"]) + (' <span class="muted">task</span>' if t["selected"] else ""), f'{t["cores"]:.2f}'] for t in a["top_threads"][:8]]

    cards = [
        f'<div class="card"><h2>🧵 Task thread time, by state</h2><p class="sub">Share of the recording each task thread spent running, '
        f'blocked or waiting (calls of 1 ms or more; the rest is split by native samples)</p><div class="legend">{legend}</div>'
        f'{states_svg(a)}<details><summary>Table</summary>{state_table}</details><div class="tooltip"></div></div>',
        f'<div class="card"><h2>🔥 CPU of the task threads, by layer</h2><p class="sub">{a["exec_samples"]:,} execution samples, each '
        f'classified by its first frame outside the JDK</p>{layers_svg(a)}<details><summary>Table</summary>{layer_table}</details>'
        f'<div class="tooltip"></div></div>',
    ]
    if hot_rows:
        cards.append('<div class="card full"><h2>🧩 Hot methods (task threads)</h2><p class="sub">First frame outside the JDK of the '
                     'execution samples, and the JDK method running in it</p>'
                     + table(["Method", "Layer", "CPU samples"], hot_rows, nums=(2,)) + "</div>")
    if io_rows:
        cards.append('<div class="card"><h2>🌐 Network I/O of the task threads</h2><p class="sub">Socket reads and writes of 1 ms or more '
                     '(events), and shorter calls seen by the native samples, by remote</p>'
                     + table(["Remote", "Calls ≥ 1 ms", "Avg ms", "Total s", "Task time", "Shorter calls"], io_rows, nums=(1, 2, 3, 4, 5)) + "</div>")
    if alloc_rows:
        cards.append(f'<div class="card"><h2>💾 Allocation by class</h2><p class="sub">Task threads, {fmt_bytes(alloc["rate_bytes_s"])}/s in total'
                     f' ({fmt_bytes(alloc["all_threads_rate_bytes_s"])}/s for the whole JVM)</p>'
                     + table(["Class", "MB/s", "Share"], alloc_rows, nums=(1, 2)) + "</div>")
    if waits_rows or other_rows:
        body = ""
        if other_rows:
            body += "<p class=\"sub\">🔒 Locks (monitor enter)</p>" + table(["Site", "Monitor", "Waits", "Total s"], other_rows, nums=(2, 3))
        if waits_rows:
            body += "<p class=\"sub\" style=\"margin-top:10px\">💤 Sleep, park and wait</p>" + table(["Site", "Kind", "Count", "Total s"], waits_rows, nums=(2, 3))
        cards.append('<div class="card"><h2>🔒 Locks and waits (task threads)</h2>' + body + "</div>")
    if top_rows:
        cards.append('<div class="card"><h2>🔥 Busiest threads of the JVM</h2><p class="sub">CPU cores used, average over the recording</p>'
                     + table(["Thread", "Cores"], top_rows, nums=(1,)) + "</div>")
    if normal_rows:
        cards.append('<div class="card"><h2>✅ Other signals</h2><p class="sub">Checked and found normal</p>' + table(["Signal", "Value"], normal_rows) + "</div>")
    return (f'<section class="jfr-section"><h2>{e(title)}</h2><p class="sub">{sub}</p>{findings_html(a["findings"])}'
            f'<div class="grid">{"".join(cards)}</div></section>')


def render_comparison(cmp, noun="version"):
    versions = cmp["versions"]
    if len(versions) < 2:
        return ""
    names = [v["version"] for v in versions]
    layer_names = [l for l in LAYERS if any(v["layers"].get(l, 0) > 0 for v in versions)]

    def rows_for(key, keys, labels):
        rows = []
        for k, label in zip(keys, labels):
            vals = [v[key].get(k, 0) for v in versions]
            d = (vals[-1] - vals[0]) * 100
            rows.append([e(label)] + [pct(x) for x in vals] + [f"<strong>{'+' if d > 0 else ''}{d:.0f} pts</strong>"])
        return rows
    header = ["Layer"] + names + [f"Δ {names[-1]} vs {names[0]}"]
    layers = table(header, rows_for("layers", layer_names, layer_names), nums=range(1, len(names) + 2))
    skeys = [k for k, _, _ in STATES]
    slabels = [label for _, label, _ in STATES]
    states = table(["State"] + names + [f"Δ {names[-1]} vs {names[0]}"], rows_for("states", skeys, slabels), nums=range(1, len(names) + 2))
    return (f'<section class="jfr-section"><h2>🆚 Where the time goes, by {noun}</h2><p class="sub">Flight recordings of the measured runs, '
            f'averaged over the rounds of each {noun}</p>{findings_html(cmp["findings"])}<div class="grid">'
            f'<div class="card"><h2>🔥 CPU of the task threads, by layer</h2><p class="sub">Share of the execution samples of each {noun}</p>{layers}</div>'
            f'<div class="card"><h2>🧵 Task thread time, by state</h2><p class="sub">Mean of the task threads of each {noun}</p>{states}</div>'
            f'</div></section>')


STANDALONE_CSS = """
.viz-root {
  color-scheme: light;
  --page: #f9f9f7; --surface-1: #fcfcfb; --text-primary: #0b0b0b; --text-secondary: #52514e; --text-muted: #898781;
  --grid: #e1e0d9; --axis: #c3c2b7; --border: rgba(11,11,11,0.10); --series-1: #2a78d6;
  --series-2: #eb6834; --series-3: #1baf7a; --series-4: #eda100; --series-5: #e87ba4; --series-6: #008300; --series-7: #6250d6; --series-8: #e34948;
  --good: #0ca30c; --good-text: #006300; --critical: #d03b3b; --warning: #fab219;
}
@media (prefers-color-scheme: dark) {
  :root:where(:not([data-theme="light"])) .viz-root {
    color-scheme: dark;
    --page: #0d0d0d; --surface-1: #1a1a19; --text-primary: #f0efec; --text-secondary: #c3c2b7; --text-muted: #898781;
    --grid: #2c2c2a; --axis: #383835; --border: rgba(255,255,255,0.10); --series-1: #3987e5;
    --series-2: #d95926; --series-3: #199e70; --series-4: #c98500; --series-5: #d55181; --series-6: #008300; --series-7: #9085e9; --series-8: #e66767;
    --good-text: #0ca30c;
  }
}
:root[data-theme="dark"] .viz-root {
  color-scheme: dark;
  --page: #0d0d0d; --surface-1: #1a1a19; --text-primary: #f0efec; --text-secondary: #c3c2b7; --text-muted: #898781;
  --grid: #2c2c2a; --axis: #383835; --border: rgba(255,255,255,0.10); --series-1: #3987e5;
  --series-2: #d95926; --series-3: #199e70; --series-4: #c98500; --series-5: #d55181; --series-6: #008300; --series-7: #9085e9; --series-8: #e66767;
  --good-text: #0ca30c;
}
* { box-sizing: border-box; }
body { margin: 0; }
.viz-root { background: var(--page); color: var(--text-primary); min-height: 100vh;
  font-family: system-ui, -apple-system, "Segoe UI", sans-serif; padding: 28px 32px 48px; }
header { display: flex; justify-content: space-between; align-items: flex-start; gap: 16px; }
h1 { font-size: 1.35rem; margin: 0 0 4px; font-weight: 600; }
h2 { font-size: 1rem; margin: 0 0 2px; font-weight: 600; }
.sub { color: var(--text-secondary); font-size: .875rem; margin: 0; }
a { color: var(--series-1); }
.theme-toggle { white-space: nowrap; flex-shrink: 0; font: inherit; font-size: .8rem; color: var(--text-secondary); background: var(--surface-1);
  border: 1px solid var(--border); border-radius: 6px; padding: 4px 10px; cursor: pointer; }
.card { background: var(--surface-1); border: 1px solid var(--border); border-radius: 10px; padding: 16px 18px; position: relative; }
.card .sub { margin-bottom: 8px; }
.grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(520px, 1fr)); gap: 16px; }
svg { display: block; width: 100%; height: auto; overflow: visible; }
svg text { font-family: inherit; }
.tooltip { position: absolute; pointer-events: none; background: var(--surface-1); border: 1px solid var(--border);
  border-radius: 6px; padding: 6px 9px; font-size: .78rem; box-shadow: 0 2px 8px rgba(0,0,0,.12); display: none; white-space: nowrap; z-index: 2; }
.legend { display: flex; gap: 16px; flex-wrap: wrap; font-size: .8rem; color: var(--text-secondary); margin: 2px 0 6px; }
.legend span::before { content: ""; display: inline-block; width: 10px; height: 10px; border-radius: 2px; background: var(--c); margin-right: 6px; vertical-align: -1px; }
table { border-collapse: collapse; width: 100%; font-size: .82rem; font-variant-numeric: tabular-nums; }
th, td { text-align: left; padding: 5px 10px; border-bottom: 1px solid var(--grid); }
th { color: var(--text-secondary); font-weight: 500; }
td.num, th.num { text-align: right; }
details { margin-top: 12px; } summary { cursor: pointer; font-weight: 600; font-size: .9rem; padding: 6px 0; }
.full { grid-column: 1 / -1; }
.empty { color: var(--text-muted); font-size: .875rem; padding: 24px 0; }
footer { color: var(--text-muted); font-size: .78rem; margin-top: 24px; }
"""


def verdict_html(a):
    """one friendly sentence at the top of the standalone report, from its findings"""
    crit = [f for f in a["findings"] if f["severity"] == "critical"]
    warn = [f for f in a["findings"] if f["severity"] == "warning"]
    if crit:
        text = f"🚨 {len(crit)} critical finding{'s' if len(crit) > 1 else ''}" + (f", {len(warn)} to look at" if warn else "") + \
            f": start with “{crit[0]['title'].rstrip('.')}”."
        sev = "var(--critical)"
    elif warn:
        text = f"⚠️ {len(warn)} thing{'s' if len(warn) > 1 else ''} to look at, nothing critical: “{warn[0]['title'].rstrip('.')}”."
        sev = "var(--warning)"
    else:
        text = "✅ Nothing alarming in this recording."
        sev = "var(--good)"
    return f'<div class="card jfr-verdict" style="--sev: {sev}">{e(text)}</div>'


def standalone_html(a, recording_link=None):
    rec = a["recording"]
    title = "Flight recording analysis"
    sub = " · ".join(x for x in [", ".join(rec["files"]), rec["jvm_versions"][0].split(" for ")[0] if rec["jvm_versions"] else None,
                                 a.get("connector_class")] if x)
    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>{e(title)}</title><style>{STANDALONE_CSS}{SECTION_CSS}</style></head>
<body><div class="viz-root">
<header><div><h1>🛩️ {e(title)}</h1><p class="sub">{e(sub)}</p></div>
<button class="theme-toggle" id="theme-toggle" type="button">Toggle theme</button></header>
{verdict_html(a)}
{render_section(a, title="🔎 Where the time goes", recording_link=recording_link)}
<footer>🛠️ Generated by playground analyze flight-recorder. Open the recording in JDK Mission Control (https://jdk.java.net/jmc/) for the details.</footer>
</div>
<script>
document.getElementById("theme-toggle").addEventListener("click", () => {{
  const root = document.documentElement;
  const dark = root.dataset.theme ? root.dataset.theme === "dark" : matchMedia("(prefers-color-scheme: dark)").matches;
  root.dataset.theme = dark ? "light" : "dark";
}});
</script>
{TOOLTIP_JS}
</body></html>"""


def main():
    parser = argparse.ArgumentParser(description="Where the time of the connector tasks goes, from flight recording digest(s)")
    parser.add_argument("--digest", action="append", required=True, help="digest json printed by JfrDigest.java (repeat for several workers)")
    parser.add_argument("--connector-class")
    parser.add_argument("--connector-type", choices=["sink", "source"])
    parser.add_argument("--mode", choices=["drain", "steady"])
    parser.add_argument("--source-url")
    parser.add_argument("--top", type=int, default=10)
    parser.add_argument("--json", action="store_true", help="print the analysis as json")
    parser.add_argument("--json-out", help="also write the analysis json to this file")
    parser.add_argument("--html-out")
    parser.add_argument("--recording-link", help="path of the .jfr, linked from the html report")
    args = parser.parse_args()

    model = load_digests(args.digest)
    if model["events"] == 0:
        print("no flight recorder event found in the recording", file=sys.stderr)
        return 2
    context = model.get("context", {})
    a = analyze(model, args.connector_class or context.get("connector_class"), args.connector_type or context.get("connector_type"),
                args.mode or context.get("mode"), args.source_url, args.top)
    if args.json_out:
        with open(args.json_out, "w") as f:
            json.dump(a, f)
    if args.html_out:
        with open(args.html_out, "w") as f:
            f.write(standalone_html(a, args.recording_link))
    if args.json:
        print(json.dumps(a, indent=2))
    else:
        print(text_report(a, args.top))
    return 0


if __name__ == "__main__":
    sys.exit(main())
