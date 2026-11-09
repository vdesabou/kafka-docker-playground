"""
Regression tests of the helpers of playground analyze logs (exports of log events, overview, progress), plain asserts,
no dependency:

    python3 -I tools/log-analyzer/test_log_analyzer.py
"""
import csv
import io
import json
import os
import re
import sys
import tempfile

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bundle_triage  # noqa: E402
import json_log_export as jle  # noqa: E402
import log_overview  # noqa: E402
import log_report  # noqa: E402
import progress  # noqa: E402


def check(name, ok, detail=""):
    if not ok:
        raise AssertionError(f"{name}: {detail}")


def lines(event):
    return "\n".join(jle.to_lines(event)[1])


def test_numeric_levels():
    out = lines({"time": 1793896102923, "level": 50, "msg": "db exploded"})
    check("pino 50", " ERROR db exploded" in out, out)
    out = lines({"timestamp": "2026-11-06T10:00:00Z", "level": 3, "short_message": "x", "message": "gelf error"})
    check("syslog 3", " ERROR gelf error" in out, out)
    check("pino 30", " INFO " in lines({"time": 1, "level": "30", "msg": "m"}))


def test_level_word_in_message_keeps_level_and_stack():
    out = lines({"@timestamp": "2026-11-06T10:00:00.000Z", "level": "ERROR", "logger_name": "c.e.Task",
                 "message": "Task failed: WARN threshold reached", "stack_trace": "java.lang.IllegalStateException: x\n\tat a.b(C.java:1)"})
    check("level kept", "ERROR Task failed: WARN threshold reached (c.e.Task)" in out, out)
    check("stack kept", "java.lang.IllegalStateException: x" in out, out)


def test_stack_without_level():
    out = lines({"timestamp": "2026-11-06T10:00:00Z", "message": "boom", "stack_trace": "java.lang.X: y\n\tat a.b(C.java:1)"})
    check("stack without level", "java.lang.X: y" in out, out)


def test_epoch_float_string():
    out = lines({"@timestamp": "1697310809.5", "message": "m"})
    check("epoch float", out.startswith("[2023-10-14T19:13:29.500Z]"), out)


def test_splunk_time_reversed():
    with tempfile.TemporaryDirectory() as d:
        src, dst = os.path.join(d, "splunk.csv"), os.path.join(d, "out.log")
        with open(src, "w", newline="") as fh:
            w = csv.writer(fh)
            w.writerow(["_time", "_raw"])
            w.writerow(["2026-11-06T10:00:02.000Z", "second"])
            w.writerow(["2026-11-06T10:00:01.000Z", "first"])
        sys.argv = ["x", src, dst]
        with open(os.devnull, "w") as null:
            old, sys.stdout = sys.stdout, null
            try:
                rc = jle.main()
            finally:
                sys.stdout = old
        text = open(dst).read()
        check("splunk", rc == 0 and text.index("first") < text.index("second"), text)


def test_csv_json_value_cell_kept():
    with tempfile.TemporaryDirectory() as d:
        src = os.path.join(d, "k.csv")
        with open(src, "w", newline="") as fh:
            w = csv.writer(fh)
            w.writerow(["@timestamp", "message"])
            w.writerow(["2026-11-06T10:00:01.000Z", '{"id":1,"name":"x"}'])
        events = jle.load_csv(src)
        check("csv json cell", events and events[0].get("message") == '{"id":1,"name":"x"}', events)


def test_mixed_offsets_not_reversed():
    first, last = jle.sortable("2026-11-06T21:00:00+02:00"), jle.sortable("2026-11-06T19:30:00Z")
    check("offsets", first < last, (first, last))


def test_loki_and_fields():
    loki = {"status": "success", "data": {"resultType": "streams", "result": [
        {"stream": {"level": "error", "container": "connect"}, "values": [["1793896102000000000", "boom 2"], ["1793896101000000000", "boom 1"]]}]}}
    ev = jle.events_of(loki)
    check("loki", ev and ev[0]["message"] == "boom 1" and ev[0]["level"] == "error", ev)
    hits = [{"_id": "1", "fields": {"@timestamp": ["2026-11-06T10:00:00Z"], "message": ["m"]}}]
    ev = jle.events_of(hits)
    check("fields", ev and ev[0]["message"] == "m", ev)


def test_overview_levels():
    check("klog", log_overview.parse_line("E1014 10:00:05.123   1 controller.go:12] failed")[0] == "ERROR")
    check("logfmt", log_overview.parse_line('ts=2026-11-06T10:00:00Z level=error msg="x"')[0] == "ERROR")
    check("json", log_overview.parse_line('{"level":"warn","msg":"x"}')[0] == "WARN")
    check("zap", log_overview.parse_line("2026-11-06T10:00:00.000Z\terror\tcontroller\tfailed")[0] == "ERROR")
    check("dotnet", log_overview.parse_line("fail: Confluent.Kafka[0]")[0] == "ERROR")
    check("mask 0x", log_overview.mask("addr 0xdeadbeef") == "addr <hex>", log_overview.mask("addr 0xdeadbeef"))


def test_overview_unleveled_after_leveled():
    with tempfile.TemporaryDirectory() as d:
        log = os.path.join(d, "a.log")
        with open(log, "w") as fh:
            fh.write("2026-11-06 10:00:00,000 INFO started\n")
            fh.write("2026-11-06 10:00:01 plain line without level\n")
            fh.write("2026-11-06 10:00:02 another one\n")
            fh.write("    continuation of it\n")
        records, sources = os.path.join(d, "records"), os.path.join(d, "sources")
        open(records, "w").write(f"@@PGFILE@@\ta.log\t4\t0\t0\t2026-11-06T10:00:00\t2026-11-06T10:00:02\n")
        open(sources, "w").write(f"a.log\t{log}\t1\n")
        ov = log_overview.overview(records, sources, None, 5)
        levels = ov["files"][0]["levels"]
        check("unleveled", levels.get("INFO") == 1 and levels.get("no level") == 2, dict(levels))


def test_human():
    check("human KB", progress.human(1023.6 * 1024) == "1.0 MB", progress.human(1023.6 * 1024))
    check("human B", progress.human(1023.6) == "1 KB", progress.human(1023.6))
    check("human MB", progress.human(5 * 1024 * 1024) == "5.0 MB", progress.human(5 * 1024 * 1024))


def test_no_syntax_warning():
    # an invalid escape in a Python string (the JavaScript of a report: "\/" instead of "\\/") is a SyntaxWarning
    # today and an error in a future Python, and it can change what the browser gets
    import ast
    import warnings
    here = os.path.dirname(os.path.abspath(__file__))
    for folder in (here, os.path.join(os.path.dirname(here), "report-common")):
        for name in sorted(os.listdir(folder)):
            if name.endswith(".py"):
                with open(os.path.join(folder, name), encoding="utf-8") as fh:
                    source = fh.read()
                with warnings.catch_warnings():
                    warnings.simplefilter("error", SyntaxWarning)
                    try:
                        ast.parse(source, name)
                    except SyntaxError as ex:
                        raise AssertionError(f"{name}: {ex}")


def test_bundle_triage():
    """🧰 the files for another analyzer: recognized by content or name, kept out of the tmp dir, one command per folder
    for the GC logs, nothing for a plain log that names a GC or a thread"""
    import gzip
    with tempfile.TemporaryDirectory() as tmp:
        src = os.path.join(tmp, "x")
        keep = os.path.join(tmp, "keep")
        os.makedirs(os.path.join(src, "b"))
        files = {
            "b/kafkaServer-gc.log": b"[2026-11-07T10:00:00.000+0000][info][gc] GC(1) Pause Young (Normal) 10M->5M(20M) 3.1ms\n",
            "b/stdout.log": b"x\n" * 1000 + b"Full thread dump OpenJDK 64-Bit Server VM\n\"main\" #1\n   java.lang.Thread.State: RUNNABLE\n",
            "b/cap.pcap": b"\xd4\xc3\xb2\xa1rest",
            "b/heap.bin": b"JAVA PROFILE 1.0.2\0rest",
            "b/rec.jfr": b"FLR\0rest",
            "b/orclcdc_diag_x.html": b"<html>orclcdc_diag</html>",
            "b/other.html": b"<html>hello</html>",
            "b/connect.log": b"2026-11-07 10:00:00 INFO GC overhead is fine, thread pool started (Worker)\n",
        }
        walked = os.path.join(tmp, "walked")
        with open(walked, "w") as w:
            for name, data in files.items():
                path = os.path.join(src, name)
                with open(path, "wb") as fh:
                    fh.write(data)
                w.write(f"case.zip:{name}\t{path}\n")
            gz = os.path.join(src, "b", "kafkaServer-gc.log.1.gz")
            with gzip.open(gz, "wb") as fh:
                fh.write(files["b/kafkaServer-gc.log"])
            w.write(f"case.zip:b/kafkaServer-gc.log.1.gz\t{gz}\n")
        res = bundle_triage.triage(walked, keep, src, {os.path.join(src, "b/stdout.log")})
        kinds = {f["label"].split("/")[-1]: f["kind"] for f in res["files"]}
        check("kinds", kinds == {"kafkaServer-gc.log": "gc_log", "kafkaServer-gc.log.1.gz": "gc_log", "stdout.log": "thread_dump",
                                 "cap.pcap": "network_capture", "heap.bin": "heap_dump", "rec.jfr": "flight_recording",
                                 "orclcdc_diag_x.html": "xstream_report"}, kinds)
        gc = [c for c in res["commands"] if c["kind"] == "gc_log"]
        check("one gc command", len(gc) == 1 and gc[0]["command"].count(" -f ") == 2, gc)
        check("kept", all(f["kept"] and f["path"].startswith(keep + "/case.zip/b/") and os.path.exists(f["path"]) for f in res["files"]), res["files"])
        # the file the report links to stays where it is (copied), a binary one is moved
        check("linked copied", os.path.exists(os.path.join(src, "b/stdout.log")))
        check("binary moved", not os.path.exists(os.path.join(src, "b/cap.pcap")))
        res = bundle_triage.triage(walked, None, src, set())
        check("no keep dir: extract first", all("<extract case.zip first>" in c["command"] for c in res["commands"]), res["commands"])


def records_file(tmp, text):
    path = os.path.join(tmp, "records")
    # | separates the fields of the @@…@@ lines (the payload of @@PGCTX@@ is a raw log line, kept as it is)
    out = []
    for line in text.split("\n"):
        if line.startswith("@@PGCTX@@"):
            line = line.replace("|", "\t", 1)
        elif line.startswith("@@"):
            # not the | of a [connector|task-0] context
            line = re.sub(r"\|(?![^\[]*\])", "\t", line)
        out.append(line)
    with open(path, "w") as fh:
        fh.write("\n".join(out))
    return path


def test_infra_events_and_bursts():
    """♻️ GC pauses, 🛑 stops and 👑 controller changes in the timeline; 💥 a burst of errors right after one, only when
    well above the usual rate"""
    burst = " ".join(f"2026-11-07T10:10:{s:02d}" for s in range(2, 40))
    usual = " ".join(f"2026-11-07T10:{m:02d}:30" for m in range(0, 30, 5))
    text = ("@@PGFILE@@|connect.log|100|2|44|2026-11-07T10:00:00|2026-11-07T10:30:00\n"
            "@@PGREC@@|WARN|38|4|60|2026-11-07T10:10:02|2026-11-07T10:10:39\n"
            "[2026-11-07 10:10:02,000] WARN [Producer clientId=p] Got error produce response. Error: NOT_LEADER_OR_FOLLOWER (x)\n"
            f"@@PGTS@@|{burst}\n"
            "@@PGREC@@|WARN|6|2|90|2026-11-07T10:00:30|2026-11-07T10:25:30\n"
            "[2026-11-07 10:00:30,000] WARN Offset commit failed (x)\n"
            f"@@PGTS@@|{usual}\n"
            "@@PGFILE@@|broker/server.log|50|0|0|2026-11-07T10:00:00|2026-11-07T10:30:00\n"
            "@@PGEVT@@|process_stop|32|2026-11-07T10:10:00||Kafka broker shutting down\n"
            "@@PGEVT@@|controller_change|34|2026-11-07T10:20:00||node 3 became the active controller (epoch 7)\n"
            "@@PGEVT@@|gc_pause|2|2026-11-07T10:25:00||2512 Pause Full\n"
            "@@PGEVTN@@|process_stop|broker|1\n@@PGEVTN@@|controller_change|controller|1\n@@PGEVTN@@|gc_pause|jvm|1\n")
    with tempfile.TemporaryDirectory() as tmp:
        res = log_report.analyze(log_report.parse_records(records_file(tmp, text)))
    infra = {ev["text"]: ev for ev in res["timeline"] if ev["kind"] == "infra"}
    check("infra events", set(infra) == {"🛑 Kafka broker shutting down", "👑 node 3 became the active controller (epoch 7)",
                                         "♻️ GC pause of 2.5 s (Pause Full)"}, list(infra))
    fx = infra["🛑 Kafka broker shutting down"].get("effects")
    check("burst after the stop", fx and fx["occurrences"] == 39 and fx["top"][0]["count"] == 38, fx)
    check("no burst after the GC pause", "effects" not in infra["♻️ GC pause of 2.5 s (Pause Full)"])
    kinds = {r["kind"] for r in res["lifecycle"]["rows"]}
    check("lifecycle rows", {"process_stop", "controller_change", "gc_pause"} <= kinds, kinds)
    out = log_report.text_summary(res, [])
    check("summary", "💥 39 ERROR/WARN occurrence(s) in the next 60 s" in out, out)


def test_fixed_bugs_found():
    """🩹 a verdict per connector from its plugin version; the context lines before a record (the end of the previous
    stack trace) do not make it match"""
    text = ("@@PGFILE@@|connect.log|20|2|2|2026-11-07T10:00:00|2026-11-07T10:10:00\n"
            "@@PGREC@@|ERROR|1|3|8|2026-11-07T10:05:00|2026-11-07T10:05:00\n"
            "[2026-11-07 10:05:00,000] ERROR [jdbc-sink|task-0] Task threw an uncaught and unrecoverable exception (x)\n"
            "    java.lang.NullPointerException: fields must be non-null\n"
            "@@PGTS@@|2026-11-07T10:05:00\n"
            "@@PGCTX@@|before\n@@PGCTX@@|before\n"
            "@@PGCTX@@|[2026-11-07 10:05:00,000] ERROR [jdbc-sink|task-0] Task threw an uncaught and unrecoverable exception (x)\n"
            "@@PGCTX@@|java.lang.NullPointerException: fields must be non-null\n"
            "@@PGCTX@@|\tat io.confluent.connect.jdbc.sink.JdbcDbWriter.getSchemaSafe(JdbcDbWriter.java:149)\n"
            "@@PGREC@@|ERROR|1|9|11|2026-11-07T10:06:00|2026-11-07T10:06:00\n"
            "[2026-11-07 10:06:00,000] ERROR [s3-sink|task-0] Task threw an uncaught and unrecoverable exception (x)\n"
            "    java.lang.NullPointerException\n"
            "@@PGTS@@|2026-11-07T10:06:00\n"
            "@@PGCTX@@|\tat io.confluent.connect.jdbc.sink.JdbcDbWriter.getSchemaSafe(JdbcDbWriter.java:149)\n"
            "@@PGCTX@@|\tat io.confluent.connect.jdbc.sink.JdbcDbWriter.write(JdbcDbWriter.java:69)\n"
            "@@PGCTX@@|[2026-11-07 10:06:00,000] ERROR [s3-sink|task-0] Task threw an uncaught and unrecoverable exception (x)\n"
            "@@PGCTX@@|java.lang.NullPointerException\n"
            "@@PGEVT@@|plugin_version|1|2026-11-07T10:00:00|jdbc-sink|10.8.5 io.confluent.connect.jdbc.JdbcSinkConnector\n")
    with tempfile.TemporaryDirectory() as tmp:
        res = log_report.analyze(log_report.parse_records(records_file(tmp, text)))
    bugs = {b["ref"]: b for b in res["fixed_bugs"]}
    check("only the JDBC bug", list(bugs) == ["CC-46266 (PR-1707)"], list(bugs))
    b = bugs["CC-46266 (PR-1707)"]
    check("verdict", b["connectors"] == [{"connector": "jdbc-sink", "version": "10.8.5", "verdict": "affected", "upgrade_to": "10.8.13"}], b["connectors"])
    card = next(c for c in res["connectors"] if c["connector"] == "jdbc-sink")
    check("on the card", card.get("fixed_bugs") and card["fixed_bugs"][0]["verdict"] == "affected", card.get("fixed_bugs"))


def test_cp_version_not_control_center():
    """the images of Control Center next-gen, Prometheus and Alertmanager (2.3.0) are not a Confluent Platform version"""
    comps = {"kafka": {"image": "acr.io/confluentinc/cp-server:8.1.4"},
             "controlcenter": {"image": "acr.io/confluentinc/cp-enterprise-control-center-next-gen:2.3.0"},
             "prometheus": {"image": "acr.io/confluentinc/cp-enterprise-prometheus:2.3.0"},
             "alertmanager": {"image": "acr.io/confluentinc/cp-enterprise-alertmanager:2.3.0"}}
    got = log_report.cp_versions({"kafka_versions": ["8.1.4-ce"]}, [{"environment": {"components": comps}}])
    check("CP 8.1.4 only", got == ["8.1.4"], got)


def test_short_message_level_first():
    """[LEVEL] timestamp [thread] logger method - message (log4j2): the message; the usual layouts unchanged"""
    got = log_report.short_message("[ERROR] 2026-10-09 03:01:46,058 [MultiLicenseBrokerHandler RUNNING] "
                                   "io.confluent.telemetry.events.exporter.http.HttpExporter emit - app=kafka failed")
    check("level first", got == "app=kafka failed", got)
    got = log_report.short_message("[2026-11-02 20:18:21,286] ERROR [etb|task-0] Connection to node 2 failed (org.apache.kafka.clients.NetworkClient:941)")
    check("usual layout", got == "Connection to node 2 failed", got)
    check("plural", (log_report.plural(1, "error"), log_report.plural(1234, "error")) == ("1 error", "1,234 errors"))


def test_task_workers():
    """🖥️ the task runs per worker (rotated files are one worker, shown by their folder), and 🎯 a connector whose errors
    all come from one worker while its tasks also ran elsewhere"""
    def start(t, task):
        return f"@@PGEVT@@|task_start|1|2026-11-07T{t}|{task.rsplit('-', 1)[0]}|{task}\n"
    text = ("@@PGFILE@@|w1/connect.log|10|0|0|2026-11-07T10:00:00|2026-11-07T10:20:00\n" + start("10:00:00", "jdbc-0") + start("10:00:00", "x-0")
            + "@@PGFILE@@|w1/connect.log.1|10|0|0|2026-11-07T09:00:00|2026-11-07T09:20:00\n" + start("09:00:00", "jdbc-1")
            + "@@PGFILE@@|w2/connect.log|10|1|5|2026-11-07T10:00:00|2026-11-07T10:20:00\n"
            "@@PGREC@@|ERROR|5|3|8|2026-11-07T10:11:00|2026-11-07T10:15:00\n"
            "[2026-11-07 10:11:00,000] ERROR [jdbc|task-0] UnknownHostException: db.internal (x)\n"
            "@@PGTS@@|2026-11-07T10:11:00\n" + start("10:10:00", "jdbc-0") + start("10:00:00", "Starting-task with")
            + "@@PGFILE@@|w2/server.log|10|0|0|2026-11-07T10:00:00|2026-11-07T10:20:00\n")
    with tempfile.TemporaryDirectory() as tmp:
        res = log_report.analyze(log_report.parse_records(records_file(tmp, text)))
    tw = res["task_workers"]
    check("workers", tw["workers"] == ["w1", "w2"], tw["workers"])
    runs = {t["task"]: [(r["worker"], r["to"]) for r in t["runs"]] for t in tw["tasks"]}
    check("runs", runs == {"jdbc-1": [("w1", None)], "jdbc-0": [("w1", "2026-11-07T10:10:00"), ("w2", None)], "x-0": [("w1", None)]}, runs)
    jdbc = next(c for c in tw["connectors"] if c["connector"] == "jdbc")
    check("only on w2", jdbc["only_on"] == "w2", jdbc)
    check("card", next(c for c in res["connectors"] if c["connector"] == "jdbc").get("only_on") == "w2")
    check("period", (tw["start"], tw["end"]) == ("2026-11-07T09:00:00", "2026-11-07T10:20:00"), (tw["start"], tw["end"]))
    html = log_report.task_workers_html(tw)
    check("html: a lane per task, a 🎯 block", html.count("class='tw-lane'") == 3 and "class='tw-group'" in html and "tw-tile tw-suspect" in html, html[-600:])
    # an incident that ended before the task moved (and logs of the other worker that start later): no 🎯
    def ev(t, task):
        return {"kind": "task_start", "time": t, "detail": task, "connector": task.rsplit("-", 1)[0]}
    def rec(conn, n, a, b):
        return {"connector": conn, "level": "ERROR", "count": n, "first_ts": a, "last_ts": b}
    files = [{"label": "w1/connect.log", "log_first_ts": "2026-11-02T20:00:00", "log_last_ts": "2026-11-03T16:00:00",
              "records": [rec("etb", 15000, "2026-11-02T20:18:21", "2026-11-02T21:07:19"), rec("both", 50, "2026-11-03T10:00:00", "2026-11-03T11:00:00")],
              "events": [ev("2026-11-02T21:15:07", "etb-0"), ev("2026-11-02T21:15:07", "both-0")]},
             {"label": "w2/connect.log", "log_first_ts": "2026-11-02T21:00:00", "log_last_ts": "2026-11-03T16:00:00", "records": [],
              "events": [ev("2026-11-03T12:19:32", "etb-0"), ev("2026-11-02T21:15:08", "both-1")]}]
    tw2 = log_report.task_workers({"connectors": []}, files)
    only = {c["connector"]: c["only_on"] for c in tw2["connectors"]}
    check("no 🎯 when the task ran elsewhere only after the errors", only == {"etb": None, "both": "w1"}, only)
    both = next(c for c in tw2["connectors"] if c["connector"] == "both")
    check("the overlap is named", "at the same time" in log_report.only_on_text(both) and "both-1 on w2" in log_report.only_on_text(both), log_report.only_on_text(both))
    one = log_report.task_workers({"connectors": []}, [{"label": "a.log", "records": [], "events": [{"kind": "task_start", "time": "2026-11-07T10:00:00", "detail": "a-0", "connector": "a"}]}])
    check("one worker: nothing", one["tasks"] == [] and one["connectors"] == [], one)


def test_data_to_request():
    """📥 the startup logs of a worker without one, the DEBUG logger of the plugin for an error no known cause explains
    (the package of its first frame, not the Connect runtime), nothing about the broker for a database login failure"""
    text = ("@@PGFILE@@|w1/connect.log|900|2|2|2026-11-07T10:00:00|2026-11-07T11:00:00\n"
            "@@PGREC@@|ERROR|1|3|8|2026-11-07T10:05:00|2026-11-07T10:05:00\n"
            "[2026-11-07 10:05:00,000] ERROR [jdbc|task-0] Failed to write the batch (org.apache.kafka.connect.runtime.WorkerSinkTask:1)\n"
            "    org.apache.kafka.connect.errors.ConnectException: weird state\n"
            "@@PGTS@@|2026-11-07T10:05:00\n"
            "@@PGCTX@@|[2026-11-07 10:05:00,000] ERROR [jdbc|task-0] Failed to write the batch (org.apache.kafka.connect.runtime.WorkerSinkTask:1)\n"
            "@@PGCTX@@|\tat org.apache.kafka.connect.runtime.WorkerSinkTask.put(WorkerSinkTask.java:1)\n"
            "@@PGCTX@@|\tat io.confluent.connect.jdbc.sink.JdbcDbWriter.write(JdbcDbWriter.java:69)\n"
            "@@PGREC@@|ERROR|1|9|9|2026-11-07T10:06:00|2026-11-07T10:06:00\n"
            "[2026-11-07 10:06:00,000] ERROR [jdbc|task-0] java.sql.SQLException: ORA-01017: invalid username/password; logon denied (x:1)\n"
            "@@PGTS@@|2026-11-07T10:06:00\n")
    with tempfile.TemporaryDirectory() as tmp:
        files = log_report.parse_records(records_file(tmp, text))
        res = log_report.analyze(files)
        asks = log_report.data_to_request(res, files)
    whats = [x["what"] for x in asks]
    check("startup logs", any(w.startswith("the logs since the last (re)start of connect.log") for w in whats), whats)
    check("debug logger", any("io.confluent.connect.jdbc at DEBUG" in w for w in whats), whats)
    check("no broker logs for ORA-01017", not any("broker" in w for w in whats), whats)
    check("in the ticket", "### Data to request" in log_report.ticket_markdown(dict(res, data_to_request=asks), "t", "ERROR/FATAL/WARN"))


def test_cluster_events_in_timeline():
    """☸️ the changes of a CFK bundle in the incident timeline: a CR edit links the first ERROR that follows (🔗), a pod
    restart followed by a burst of errors gets 💥"""
    burst = " ".join(f"2026-11-07T10:20:{s:02d}" for s in range(1, 30))
    text = ("@@PGFILE@@|bundle:confluent/connect/logs/connect-0.log|100|2|30|2026-11-07T10:00:00|2026-11-07T11:00:00\n"
            "@@PGREC@@|ERROR|1|5|5|2026-11-07T10:03:00|2026-11-07T10:03:00\n"
            "[2026-11-07 10:03:00,000] ERROR [s3|task-0] boom (x)\n"
            "@@PGTS@@|2026-11-07T10:03:00\n"
            "@@PGREC@@|ERROR|29|9|60|2026-11-07T10:20:01|2026-11-07T10:20:29\n"
            "[2026-11-07 10:20:01,000] ERROR [s3|task-0] Disconnected from node 1 (x)\n"
            f"@@PGTS@@|{burst}\n")
    with tempfile.TemporaryDirectory() as tmp:
        files = log_report.parse_records(records_file(tmp, text))
        files.cluster_events = [
            {"time": "2026-11-07T10:01:00Z", "kind": "Connect", "name": "connect", "what": "Update by kubectl-edit: spec.image", "component": "connect"},
            {"time": "2026-11-07T10:20:00Z", "kind": "Pod", "name": "kafka-1", "what": "container kafka terminated: OOMKilled", "component": "kafka"},
            {"time": "bad", "kind": "Pod", "name": "x"}]
        res = log_report.analyze(files)
    cl = [ev for ev in res["timeline"] if ev.get("cluster")]
    check("two cluster events", [ev["kind"] for ev in cl] == ["config_change", "infra"], cl)
    first = next(ev for ev in res["timeline"] if ev["kind"] == "first_error" and "boom" in ev["text"])
    check("🔗 after the CR edit", (first.get("after") or {}).get("text", "").startswith("☸️ Connect/connect"), first)
    check("💥 after the pod restart", (cl[1].get("effects") or {}).get("occurrences") == 29, cl[1])


def test_cfk_bundle_in_ticket_and_data_to_request():
    """☸️ the section of a CFK bundle in the summary for a ticket (public links only, never the 🔒 internal ones) and its
    data to request in the one 📥 list"""
    bundle = {"label": "/x/case.tgz:bundle", "summary": {"total_issues": 3, "critical": 1, "high": 1, "medium": 1, "low": 0},
              "environment": {"kubernetes_version": "v1.33.4", "cfk_version": "3.1.0"},
              "runbooks": [{"title": "Expired certificate", "occurrences": 2, "advice": "renew it",
                            "links": [{"title": "Manage TLS", "url": "https://docs.confluent.io/x"}],
                            "internal_links": [{"title": "GTS runbook", "url": "https://confluentinc.atlassian.net/wiki/x"}]}],
              "issues": [{"severity": "critical", "category": "Pod Failures", "message": "CrashLoopBackOff", "component": "kafka", "count": 4},
                         {"severity": "medium", "category": "Other", "message": "meh"}],
              "data_to_request": [{"what": "the nodes and the volumes", "why": "a pod cannot be scheduled", "command": "kubectl describe nodes"}],
              "timeline": []}
    text = "@@PGFILE@@|bundle:confluent/kafka/logs/kafka-0.log|10|0|0|2026-11-07T10:00:00|2026-11-07T10:10:00\n"
    with tempfile.TemporaryDirectory() as tmp:
        files = log_report.parse_records(records_file(tmp, text))
        files.cfk_bundles = [bundle]
        res = log_report.analyze(files)
        res["data_to_request"] = log_report.data_to_request(res, files)
        res["_cfk_bundles"] = files.cfk_bundles
    md = log_report.ticket_markdown(res, "t", "ERROR/FATAL/WARN")
    for x in ("### ☸️ CFK support bundle: case.tgz:bundle", "Kubernetes v1.33.4, CFK 3.1.0", "critical 1", "Expired certificate",
              "https://docs.confluent.io/x", "`critical` Pod Failures: CrashLoopBackOff (kafka) ×4", "☸️ the nodes and the volumes",
              "kubectl describe nodes"):
        check(x, x in md, md)
    check("no internal link", "atlassian" not in md and "meh" not in md, md)


def test_cfk_configuration_and_drift():
    """⚙️ the properties rendered by CFK, the configOverrides and the Connector CRs in the configuration of the logs; 🔀 a key
    of the CR whose value differs from the config the worker logged (formats normalized, [hidden] and ${…} skipped)"""
    bundle = {"configuration": {
        "components": {"connect": {"connect": {"source": "confluent/connect/cm/configmaps.yaml",
                                               "files": {"connect.properties": "group.id=connect\nkey.converter=x"},
                                               "overrides": {"server": "consumer.max.poll.records=2000"}}}},
        "connectors": {"orders-sink": {"cr": {"file": "confluent/connect/connector-orders-sink.yaml",
                                              "text": "tasks.max=4\ntopics=orders, refunds\nconnection.password=s3cr3t\n"
                                                      "connection.user=${file:/s/x:user}\nkey.converter=io.confluent.connect.avro.AvroConverter"}}}}}
    text = ("@@PGFILE@@|bundle:confluent/connect/logs/connect-0.log|10|0|0|2026-11-07T10:00:00|2026-11-07T10:10:00\n"
            "@@PGCFG@@|SinkConnectorConfig|[orders-sink|worker]|10|2026-11-07T10:01:10|orders-sink\n"
            "@@PGCFGL@@|tasks.max=2\n@@PGCFGL@@|topics=[orders, refunds]\n@@PGCFGL@@|key.converter=class io.confluent.connect.avro.AvroConverter\n"
            "@@PGCFG@@|JdbcSinkConfig|[orders-sink|task-0]|11|2026-11-07T10:01:11|\n"
            "@@PGCFGL@@|connection.password=[hidden]\n@@PGCFGL@@|connection.user=connect\n")
    with tempfile.TemporaryDirectory() as tmp:
        files = log_report.parse_records(records_file(tmp, text))
        files.cfk_bundles = [bundle]
        res = log_report.analyze(files)
    cfk = [c["title"] for c in res["configuration"] if c["source"] == "cfk"]
    check("cfk configs", cfk == ["connect.properties (rendered by CFK, ConfigMap connect-shared-config)",
                                 "configOverrides.server of the connect CR connect", "Connector CR"], cfk)
    check("drift", [(x["key"], x["cr"], x["logged"]) for x in res["config_drift"]] == [("tasks.max", "4", "2")], res["config_drift"])
    card = next(c for c in res["connectors"] if c["connector"] == "orders-sink") if res["connectors"] else None
    check("text", "🔀 Connector CR and config logged differ (1 key(s)" in log_report.text_summary(res, []))
    check("show-config", "Connector CR" in log_report.show_config(res, "orders-sink"))


def test_cfk_sections_and_verdict():
    """☸️ the sections of a CFK bundle drawn by the log report (one report): KPI tiles, known CFK issues, the issues by
    category with their file page link, the environment; no log coverage (🕰️ of the logs); one verdict for both"""
    bundle = {"label": "/x/case.tgz:bundle", "summary": {"total_issues": 2, "critical": 1, "high": 1, "medium": 0, "low": 0},
              "environment": {"kubernetes_version": "v1.33.4", "cfk_version": "3.1.0", "components": {"kafka": {"image": "cp-server:8.1.0"}}},
              "runbooks": [{"name": "cert", "title": "Expired certificate", "severity": "high", "occurrences": 2, "advice": "renew it", "links": []}],
              "issues": [{"severity": "critical", "category": "Pod Failures", "message": "CrashLoopBackOff", "component": "kafka",
                          "file": "pods.yaml", "viewer": "bundle-cfk-files/001-pods.yaml.html#L3", "line_number": 3,
                          "recommendation": {"summary": "Pod is crashing", "steps": ["kubectl describe pod"]}},
                         {"severity": "high", "category": "Certificate/TLS Issues", "message": "PKIX", "runbooks": ["cert"]}],
              "coverage": {"log_windows": [{"file": "x.log", "pod": "kafka-0"}]},
              "timeline": [{"time": "2026-11-07T10:00:00Z", "kind": "Kafka", "name": "kafka", "what": "Update by kubectl-edit: spec.image"}]}
    text = "@@PGFILE@@|bundle:confluent/kafka/logs/kafka-0.log|10|0|0|2026-11-07T10:00:00|2026-11-07T10:10:00\n"
    with tempfile.TemporaryDirectory() as tmp:
        files = log_report.parse_records(records_file(tmp, text))
        res = log_report.analyze(files)
    res["_cfk_bundles"] = [bundle]
    html = log_report.cfk_sections_html([bundle])
    for x in ("☸️ CFK support bundle: case.tgz:bundle", "Expired certificate", "cp-server:8.1.0",
              "Update by kubectl-edit: spec.image"):
        check(x, x in html, x)
    check("no tiles in the card", '<div class="kpi-card' not in html)
    tiles = "".join(log_report.cfk_kpi_tiles([bundle]))
    check("cfk tiles", "<a class='cfk-kpi' href='#findings' data-bundle='*' data-sev=''>" in tiles and "1 critical, 1 high" in tiles
          and "v1.33.4" in tiles and "3.1.0" in tiles and "🔴 Critical" not in tiles, tiles)
    sev = "".join(log_report.findings_severity_tiles(log_report.cfk_findings([bundle])))
    check("severity tiles", "<a class='sev-kpi' href='#findings' data-sev='CRITICAL'>" in sev and "1 ☸️ CFK" in sev
          and "data-sev='MEDIUM'>" not in sev, sev)
    check("CP tile", "🏷️ CP" in log_report.version_tile({"kafka_versions": []}, [bundle]) and "8.1.0" in log_report.version_tile({}, [bundle]))
    check("CP from -ce", ">8.3.2<" in log_report.version_tile({"kafka_versions": ["8.3.2-ce"]}, []))
    check("Kafka", "🏷️ Kafka" in log_report.version_tile({"kafka_versions": ["4.1.0"]}, []))
    check("no issue list, no log coverage", "Pod Failures" not in html and "kafka-0" not in html and "Log coverage" not in html)
    cards = log_report.cfk_findings([bundle])
    check("cards", [c["severity"] for c in cards] == ["CRITICAL", "HIGH"], cards)
    pod = cards[0]["_view"]
    check("card content", "☸️ Pod Failures" in pod["html"] and "Pod is crashing" in pod["html"]
          and "data-level='0' data-component='kafka'" in pod["html"]
          and "href='bundle-cfk-files/001-pods.yaml.html#L3'" in pod["details"][0], pod)
    check("runbook in card", "📕 <strong>Expired certificate</strong>" in cards[1]["_view"]["details"][0], cards[1])
    check("in findings", any(f.get("_view", {}).get("kind") == "cfk" for f in log_report.analyze(
        (lambda fs: (setattr(fs, "cfk_bundles", [bundle]), fs)[1])(log_report.parse_records(records_file(tempfile.mkdtemp(), text))))["findings"]))
    cls, text = log_report.verdict(res, "ERROR/FATAL/WARN")
    check("one verdict", cls == "danger" and text.startswith("✅ No") and "☸️ CFK bundle: 1 critical, 1 high issue(s) of 2, start with Pod Failures" in text, (cls, text))


def test_kb_articles_of_variants():
    kc = log_report.known_causes
    saved = kc.LINKS.get("🔑 Authentication failure")
    kc.LINKS["🔑 Authentication failure"] = [
        {"kb": "https://kb/general", "kb_title": "general"},
        {"kb": "https://kb/ora", "kb_title": "ORA-01017", "pattern": r"ORA-01017"},
        {"kb": "https://kb/mysql", "kb_title": "MySQL", "pattern": r"Access denied for user"},
        {"kb": "https://kb/cloud", "kb_title": "cloud", "fallback": True}]
    try:
        got = kc.links("🔑 Authentication failure", ["java.sql.SQLException: ORA-01017: invalid username/password"])
        check("variant first, then general, no fallback", [a["url"] for a in got["kb_articles"]] == ["https://kb/ora", "https://kb/general"], got)
        check("kb is the first article", got["kb"] == "https://kb/ora" and got["kb_title"] == "ORA-01017", got)
        got = kc.links("🔑 Authentication failure", ["SaslAuthenticationException: Authentication failed"])
        check("no variant: general and fallback", [a["url"] for a in got["kb_articles"]] == ["https://kb/general", "https://kb/cloud"], got)
        check("reading links", log_report.reading_links(got) == [("KB: general", "https://kb/general"), ("KB: cloud", "https://kb/cloud")], got)
    finally:
        if saved is None:
            kc.LINKS.pop("🔑 Authentication failure", None)
        else:
            kc.LINKS["🔑 Authentication failure"] = saved
    check("single dict entry still works", kc.links("📜 License error").get("kb", "").startswith(kc.KB))
    check("unknown cause", kc.links("no such cause") == {})


def test_log_search_index():
    """🔎 the shards of Search every log line: every line, the time index (a stack trace takes the time of the line
    before, also across a shard), a .gz read decompressed, the budget leaves a file out"""
    import base64
    import gzip
    import log_search
    with tempfile.TemporaryDirectory() as d:
        plain = os.path.join(d, "connect.log")
        with open(plain, "w") as fh:
            fh.write("[2026-10-14 09:00:00,001] INFO start (x)\n"
                     "[2026-10-14 09:00:05,002] ERROR boom (x)\n"
                     "java.lang.IllegalStateException: boom\n"
                     "\tat a.b.C(C.java:1)\n"
                     "[2026-10-14 09:01:00,003] WARN later (x)\n")
        zipped = os.path.join(d, "server.log.gz")
        with gzip.open(zipped, "wt") as fh:
            fh.write("2026-10-14T08:59:00.000Z INFO broker up\n")
        big = os.path.join(d, "big.log")
        with open(big, "w") as fh:
            fh.write("x" * 5000 + "\n")
        report = os.path.join(d, "r-log-report.html")
        entries = [{"label": "connect.log", "path": plain, "comp": "connect", "href": "", "occurrences": 1},
                   {"label": "server.log.gz", "path": zipped, "comp": "kafka", "href": "", "occurrences": 0},
                   {"label": "big.log", "path": big, "comp": "other", "href": "", "occurrences": 0}]
        saved = log_search.SHARD_BYTES
        log_search.SHARD_BYTES = 100  # a shard per ~2 lines: the stack trace is cut
        try:
            ix = log_search.write_index(report, entries, False, budget=1000)
        finally:
            log_search.SHARD_BYTES = saved
        check("two files searched", [f["label"] for f in ix["files"]] == ["connect.log", "server.log.gz"], ix["files"])
        check("the big one left out", [s["label"] for s in ix["skipped"]] == ["big.log"], ix["skipped"])
        check("lines", ix["lines"] == 6, ix["lines"])
        check("period", ix["t0"] == 1791968340 and ix["t1"] == 1791968460, (ix["t0"], ix["t1"]))
        folder = os.path.join(d, "r-log-report-files", "search")

        def shard(name):
            js = open(os.path.join(folder, name)).read()
            o = json.loads(gzip.decompress(base64.b64decode(js.split('","', 1)[1].rsplit('"', 1)[0])))
            pairs, l, t = [], 0, 0
            for i in range(0, len(o["t"]), 2):
                l += o["t"][i]
                t += o["t"][i + 1]
                pairs.append((l, t))
            return o["x"].split("\n"), pairs
        texts, times = [], []
        for name, first, n, _, _ in ix["files"][0]["shards"]:
            x, pairs = shard(name)
            check("lines of the shard", len(x) == n, (name, x))
            texts += x
            times.append((first, pairs))
        check("every line, in order", texts[2] == "java.lang.IllegalStateException: boom" and len(texts) == 5, texts)

        def time_of(line):
            for first, pairs in times:
                local = line - first
                if 0 <= local and (first, pairs) == max((f, p) for f, p in times if f <= line):
                    return max((t for l, t in pairs if l <= local), default=None)
        check("stack trace takes the time before", time_of(2) == 1791968405 and time_of(3) == 1791968405, [time_of(i) for i in range(5)])
        check("next record", time_of(4) == 1791968460, time_of(4))


def test_connect_without_mdc():
    """⚠️ a Connect log whose task lines have no [connector|task-0] context is reported, not one that has it (also
    with a scope, [c|task-0|redoLog]), nor a broker log, nor a Connect log with too few task lines to tell"""
    with tempfile.TemporaryDirectory() as d:
        task_lines = ("[2026-10-14 09:00:00,001] INFO {ctx}Instantiated task orders-sink-0 with version 1 (org.apache.kafka.connect.runtime.Worker:1)\n"
                      "[2026-10-14 09:00:00,002] INFO {ctx}Creating task orders-sink-0 (org.apache.kafka.connect.runtime.Worker:1)\n"
                      "[2026-10-14 09:00:01,003] INFO {ctx}WorkerSinkTask{{id=orders-sink-0}} Sink task finished initialization and its start (x:1)\n")
        paths = {}
        for name, ctx in (("without/connect.log", ""), ("with/connect.log", "[orders-sink|task-0] "),
                          ("scoped/connect.log", "[orders-sink|task-0|redoLog] ")):
            paths[name] = os.path.join(d, name.replace("/", "-"))
            with open(paths[name], "w") as fh:
                fh.write(task_lines.format(ctx=ctx))
        paths["few/connect.log"] = os.path.join(d, "few.log")
        with open(paths["few/connect.log"], "w") as fh:
            fh.write(task_lines.format(ctx="").splitlines(True)[0])
        paths["broker/server.log"] = os.path.join(d, "server.log")
        with open(paths["broker/server.log"], "w") as fh:
            fh.write(task_lines.format(ctx=""))
        sources = os.path.join(d, "sources")
        with open(sources, "w") as fh:
            fh.writelines(f"{label}\t{path}\t1\n" for label, path in paths.items())
        out = log_report.connect_without_mdc(sources, [])
        check("only the Connect log without context", [i["file"] for i in out] == ["without/connect.log"], out)
        check("its task lines", out[0]["task_lines"] == 3, out)
        res = {"summary": {"connect_without_mdc": out}}
        check("warning text", "No connector context (MDC)" in log_report.mdc_text(out) and "connect.log" in log_report.mdc_text(out))
        check("fix", "%X{connector.context}" in log_report.MDC_HOW and res)


if __name__ == "__main__":
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_") and callable(v)]
    failed = 0
    for t in tests:
        try:
            t()
            print(f"✅ {t.__name__}")
        except Exception as ex:  # noqa: BLE001
            failed += 1
            print(f"❌ {t.__name__}: {type(ex).__name__}: {ex}")
    sys.exit(1 if failed else 0)
