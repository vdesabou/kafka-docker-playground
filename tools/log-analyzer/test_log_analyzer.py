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
import ocr  # noqa: E402
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


def make_xlsx(path, rows, date_col=None, images=0):
    """a minimal .xlsx as Excel writes it: shared strings, a date format (numFmtId 22) on date_col, the sheet through
    workbook.xml.rels; rows of str / float (a float in date_col: an Excel date)"""
    import zipfile
    from xml.sax.saxutils import escape
    shared, cells_xml = [], []
    for r, row in enumerate(rows, start=1):
        cells = []
        for c, v in enumerate(row):
            ref = chr(65 + c) + str(r)
            if isinstance(v, float):
                style = ' s="1"' if c == date_col else ""
                cells.append(f'<c r="{ref}"{style}><v>{v}</v></c>')
            else:
                shared.append(v)
                cells.append(f'<c r="{ref}" t="s"><v>{len(shared) - 1}</v></c>')
        cells_xml.append(f'<row r="{r}">{"".join(cells)}</row>')
    ns = 'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"'
    with zipfile.ZipFile(path, "w") as z:
        z.writestr("[Content_Types].xml", "<Types/>")
        z.writestr("xl/workbook.xml", f'<workbook {ns} xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
                   '<sheets><sheet name="export" sheetId="1" r:id="rId1"/></sheets></workbook>')
        z.writestr("xl/_rels/workbook.xml.rels", '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                   '<Relationship Id="rId1" Target="worksheets/sheet1.xml" Type="x"/></Relationships>')
        z.writestr("xl/sharedStrings.xml", f'<sst {ns}>' + "".join(f"<si><t>{escape(s)}</t></si>" for s in shared) + "</sst>")
        z.writestr("xl/styles.xml", f'<styleSheet {ns}><cellXfs><xf numFmtId="0"/><xf numFmtId="22"/></cellXfs></styleSheet>')
        z.writestr("xl/worksheets/sheet1.xml", f'<worksheet {ns}><sheetData>{"".join(cells_xml)}</sheetData></worksheet>')
        for i in range(images):
            z.writestr(f"xl/media/image{i + 1}.png", b"\x89PNG")


def test_office_export():
    """📄 logs in a Word document (a paragraph a line, a line break, a tab, the non-breaking spaces) and in an Excel
    export (newest first, Excel dates, level column) back to log lines; a sheet that is not an export gives its rows"""
    import zipfile
    import office_export
    with tempfile.TemporaryDirectory() as d:
        docx = os.path.join(d, "pasted.docx")
        ns = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
        body = ("<w:p><w:r><w:t>[2026-10-14 09:00:00,001] ERROR boom (x)</w:t></w:r></w:p>"
                "<w:p><w:r><w:t>java.lang.IllegalStateException: boom</w:t><w:br/><w:tab/><w:t>at a.b.C(C.java:1)</w:t></w:r></w:p>"
                "<w:p/><w:p><w:r><w:t xml:space=\"preserve\">[2026-10-14 09:00:01,000] WARN later</w:t></w:r></w:p><w:p/>")
        with zipfile.ZipFile(docx, "w") as z:
            z.writestr("word/document.xml", f"<w:document {ns}><w:body>{body}</w:body></w:document>")
            z.writestr("word/media/image1.png", b"\x89PNG")
        out = os.path.join(d, "a.log")
        fmt, nb, pictures = office_export.convert(docx, out)
        lines = open(out).read().split("\n")
        check("word", (fmt, nb, pictures) == ("Word", 4, 1), (fmt, nb, pictures))
        check("word lines", lines[:5] == ["[2026-10-14 09:00:00,001] ERROR boom (x)", "java.lang.IllegalStateException: boom",
                                          "\tat a.b.C(C.java:1)", "", "[2026-10-14 09:00:01,000] WARN later"], lines)
        # an export of Kibana, newest first; 45944.375 = 2025-10-14 09:00:00 (days since 1899-12-30)
        xlsx = os.path.join(d, "export.xlsx")
        make_xlsx(xlsx, [["@timestamp", "log.level", "message"],
                         [45944.375 + 1 / 86400, "WARN", "later"],
                         [45944.375, "ERROR", "Task threw an uncaught and unrecoverable exception"]], date_col=0, images=2)
        fmt, nb, pictures = office_export.convert(xlsx, out)
        lines = open(out).read().splitlines()
        check("excel export", (fmt, nb, pictures) == ("Excel export", 2, 2), (fmt, nb, pictures))
        check("excel oldest first, dates", lines == ["[2025-10-14T09:00:00.000] ERROR Task threw an uncaught and unrecoverable exception",
                                                     "[2025-10-14T09:00:01.000] WARN later"], lines)
        plain = os.path.join(d, "lines.xlsx")
        make_xlsx(plain, [["[2026-10-14 09:00:00,001] ERROR boom (x)"], ["[2026-10-14 09:00:02,000] INFO ok"]])
        fmt, nb, _ = office_export.convert(plain, out)
        check("a sheet of log lines", (fmt, nb) == ("Excel", 2) and open(out).read().startswith("[2026-10-14 09:00:00,001] ERROR boom"),
              (fmt, nb, open(out).read()))


def test_share_formats():
    """📤 the summary for a ticket as text to paste in Slack (a table row as a bullet, links "text (url)", nothing escaped: the message box shows &lt; as is) and as HTML
    with inline styles (real tables, a cell with an escaped |, the text escaped)"""
    import share_formats as sf
    md = ("## 🔥 Log analysis: t\n\n**Verdict:** 3 ERROR in `a<b>`\n\n### What to look at first\n\n"
          "| Severity | Known cause | Occurrences | What to do |\n| --- | --- | --- | --- |\n"
          "| HIGH | 🔑 Auth \\| SASL | 3 | check [the KB](https://kb.example/a?x=1&y=2) |\n\n"
          "### Data to request\n\n- **logs**: why\n  - sub item\n\n_Generated by x._\n")
    slack = sf.md_to_slack(md)
    check("slack heading", slack.startswith("*🔥 Log analysis: t*\n"), slack)
    check("slack bold", "*Verdict:* 3 ERROR in `a<b>`" in slack, slack)
    check("slack row", "• HIGH · 🔑 Auth | SASL · Occurrences: 3 · What to do: check the KB (https://kb.example/a?x=1&y=2)" in slack, slack)
    check("slack bullets", "• *logs*: why\n    ◦ sub item" in slack, slack)
    check("slack no table syntax", "| --- |" not in slack and "**" not in slack, slack)
    page = sf.md_to_html(md)
    check("html table", page.count("<th ") == 4 and page.count("<td ") == 4, page)
    check("html cell", ">🔑 Auth | SASL</td>" in page, page)
    check("html escaped code", "a&lt;b&gt;</code>" in page, page)
    check("html link", '<a href="https://kb.example/a?x=1&amp;y=2">the KB</a>' in page, page)
    check("html lists", "<li><b>logs</b>: why</li><ul" in page and "<li>sub item</li></ul>" in page, page)
    check("html italic", "<i>Generated by x.</i>" in page, page)


def test_consumer_leaving_not_a_storm():
    """🔄 a group whose rejoins are a consumer closed on purpose (the short-lived consumers of Oracle CDC, every 30 s) is
    not a storm, also when none of its events is among the 300 noted per kind and file: the digest counts those leaves
    over the whole file (4th column of @@PGEVTN@@); a group with as many real rejoins still is one, and comes first"""
    text = ("@@PGFILE@@|connect.log|1000|1|1|2026-10-22T14:16:00|2026-10-22T15:40:00\n"
            "@@PGREC@@|ERROR|1|5|5|2026-10-22T14:20:00|2026-10-22T14:20:00\n"
            "[2026-10-22 14:20:00,000] ERROR boom (x)\n"
            "@@PGTS@@|2026-10-22T14:20:00\n"
            "@@PGEVT@@|consumer_rejoin|9|2026-10-22T14:30:00|sink|connect-sink · rebalance failed due to 'The coordinator is not aware of this member.'\n"
            "@@PGEVTN@@|consumer_rejoin|cdc-orcl-39-T24-FUSP|140|140\n"
            "@@PGEVTN@@|consumer_rejoin|connect-sink|140|0\n"
            "@@PGEVTN@@|consumer_rejoin|old-digest-group|20\n")
    with tempfile.TemporaryDirectory() as tmp:
        res = log_report.analyze(log_report.parse_records(records_file(tmp, text)))
    rows = {r["who"]: r for r in res["lifecycle"]["rows"]}
    cdc = rows["cdc-orcl-39-T24-FUSP"]
    check("leaving: not a storm", not cdc["storm"] and cdc["leaving"], cdc)
    check("leaving: its reason from the counts", cdc["reason"] == "consumer pro-actively leaving the group (140 of 140)", cdc["reason"])
    check("real rejoins: a storm", rows["connect-sink"]["storm"], rows["connect-sink"])
    check("a digest without the 4th column: a storm as before", rows["old-digest-group"]["storm"], rows["old-digest-group"])
    order = [r["who"] for r in res["lifecycle"]["rows"]]
    check("the leaving group last", order[-1] == "cdc-orcl-39-T24-FUSP", order)


def test_member_eviction():
    """🚪 the members of a consumer group removed by the group coordinator (broker log): a 🔄 row per group with the
    timeout as its reason, tied to the sink connector of a connect-<name> group, and in the timeline, not a 💥 trigger"""
    text = ("@@PGFILE@@|broker.log|1000|1|1|2026-11-07T10:00:00|2026-11-07T11:00:00\n"
            "@@PGREC@@|ERROR|1|1|1|2026-11-07T10:40:00|2026-11-07T10:40:00\n"
            "[2026-11-07 10:40:00,000] ERROR boom (x)\n"
            "@@PGTS@@|2026-11-07T10:40:00\n"
            "@@PGEVT@@|member_eviction|5|2026-11-07T10:30:05|s3-sink|connect-s3-sink · rebalance timeout (did not rejoin)\n"
            "@@PGEVT@@|member_eviction|6|2026-11-07T10:31:05|s3-sink|connect-s3-sink · rebalance timeout (did not rejoin)\n"
            "@@PGEVT@@|member_eviction|7|2026-11-07T10:32:00||payments · session timeout (no heartbeat)\n"
            "@@PGEVTN@@|member_eviction|connect-s3-sink|2\n"
            "@@PGEVTN@@|member_eviction|payments|1\n")
    with tempfile.TemporaryDirectory() as tmp:
        res = log_report.analyze(log_report.parse_records(records_file(tmp, text)))
    rows = {r["who"]: r for r in res["lifecycle"]["rows"] if r["kind"] == "member_eviction"}
    check("a row per group", set(rows) == {"connect-s3-sink", "payments"}, rows)
    s3 = rows["connect-s3-sink"]
    check("count and reason", s3["count"] == 2 and s3["reason"] == "rebalance timeout (did not rejoin)", s3)
    check("tied to its connector", log_report.lifecycle_connector(s3) == "s3-sink", s3)
    check("not a storm", not s3["storm"], s3)
    tl = [ev for ev in res["timeline"] if ev["text"].startswith("🚪")]
    check("in the timeline", len(tl) == 3 and all(ev["kind"] == "lifecycle" for ev in tl), tl)
    check("timeline text", any(ev["text"] == "🚪 members of group payments removed by the coordinator: session timeout (no heartbeat)"
                               for ev in tl), [ev["text"] for ev in tl])
    check("text summary", any("group members removed by the coordinator" in x for x in log_report.lifecycle_text(res["lifecycle"])),
          log_report.lifecycle_text(res["lifecycle"]))


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


def test_connector_class_from_loggers():
    """🔎 no "Instantiated connector" line nor config: the class of a connector from the loggers of the lines of its tasks
    (the longest prefix wins, a shared package decides nothing), marked inferred, no support badge; the class of an
    "Instantiated connector" line wins; an unknown plugin: its package"""
    def rec(conn, t):
        return (f"@@PGREC@@|ERROR|1|3|3|2026-11-07T10:0{t}:00|2026-11-07T10:0{t}:00\n"
                f"[2026-11-07 10:0{t}:00,000] ERROR [{conn}|task-0] boom (x)\n@@PGTS@@|2026-11-07T10:0{t}:00\n")

    def lg(conn, logger):
        return f"@@PGEVT@@|plugin_logger|1|2026-11-07T10:00:00|{conn}|{logger}\n"
    text = ("@@PGFILE@@|connect.log|20|4|4|2026-11-07T10:00:00|2026-11-07T10:10:00\n"
            + rec("hdfs", 1) + rec("cdc", 2) + rec("jdbc", 3) + rec("acme", 4) + rec("versioned", 5)
            + lg("hdfs", "org.apache.hadoop.ipc.Client") + lg("hdfs", "io.confluent.connect.hdfs3.TopicPartitionWriter")
            + lg("cdc", "io.debezium.util.Threads") + lg("cdc", "io.debezium.connector.postgresql.connection.PostgresConnection")
            + lg("jdbc", "io.confluent.connect.jdbc.util.CachedConnectionProvider") + lg("jdbc", "io.confluent.connect.jdbc.sink.JdbcSinkTask")
            + lg("acme", "io.confluent.license.LicenseManager") + lg("acme", "com.acme.kafka.connect.foo.FooTask")
            + lg("versioned", "io.confluent.connect.jdbc.sink.JdbcSinkTask")
            + "@@PGEVT@@|plugin_version|1|2026-11-07T10:00:00|versioned|10.8.4 io.confluent.connect.s3.S3SinkConnector\n")
    with tempfile.TemporaryDirectory() as tmp:
        res = log_report.analyze(log_report.parse_records(records_file(tmp, text)))
    cards = {c["connector"]: c for c in res["connectors"]}
    check("hdfs3", cards["hdfs"].get("class") == "io.confluent.connect.hdfs3.Hdfs3SinkConnector", cards["hdfs"])
    check("hdfs3 evidence", cards["hdfs"].get("class_inferred_from") == "io.confluent.connect.hdfs3", cards["hdfs"])
    check("debezium postgres", cards["cdc"].get("class") == "io.debezium.connector.postgresql.PostgresConnector", cards["cdc"])
    check("jdbc sink", cards["jdbc"].get("class") == "io.confluent.connect.jdbc.JdbcSinkConnector", cards["jdbc"])
    check("no support badge", not cards["jdbc"].get("support") and not cards["jdbc"].get("versions"), cards["jdbc"])
    check("unknown plugin: its package", not cards["acme"].get("class") and cards["acme"].get("plugin_package") == "com.acme.kafka.connect.foo", cards["acme"])
    check("Instantiated wins", cards["versioned"]["class"] == "io.confluent.connect.s3.S3SinkConnector"
          and not cards["versioned"].get("class_inferred_from"), cards["versioned"])
    html = log_report.connectors_health_html(res["connectors"])
    check("card says inferred", "inferred from its log lines" in html and "Hdfs3SinkConnector" in html, "")
    check("card shows the package", "com.acme.kafka.connect.foo" in html, "")
    check("text", any("🔎 JdbcSinkConnector (inferred" in x for x in log_report.connectors_text(res["connectors"], top=10)),
          log_report.connectors_text(res["connectors"], top=10))


def test_jdbc_database_without_url():
    """🗄️ the database of a JDBC connector without connection.url: its SQL dialect (sink and source wording), else the
    exception of its driver; not for a connector of another plugin; the icon follows"""
    def rec(conn, t, msg):
        return (f"@@PGREC@@|ERROR|1|3|3|2026-11-07T10:0{t}:00|2026-11-07T10:0{t}:00\n"
                f"[2026-11-07 10:0{t}:00,000] ERROR [{conn}|task-0] {msg} (x)\n@@PGTS@@|2026-11-07T10:0{t}:00\n")
    text = ("@@PGFILE@@|connect.log|20|4|4|2026-11-07T10:00:00|2026-11-07T10:10:00\n"
            + rec("sink", 1, "boom") + rec("source", 2, "boom") + rec("pg", 3, "org.postgresql.util.PSQLException: ERROR: deadlock")
            + rec("s3", 4, "com.microsoft.sqlserver.jdbc.SQLServerException: x")
            + "@@PGEVT@@|plugin_logger|1|2026-11-07T10:00:00|sink|io.confluent.connect.jdbc.sink.JdbcSinkTask\n"
            + "@@PGEVT@@|connector_hint|1|2026-11-07T10:00:00|sink|dialect SqlServerDatabaseDialect\n"
            + "@@PGEVT@@|connector_hint|1|2026-11-07T10:00:00|source|dialect PostgreSql\n"
            + "@@PGEVT@@|plugin_logger|1|2026-11-07T10:00:00|pg|io.confluent.connect.jdbc.sink.JdbcDbWriter\n"
            + "@@PGEVT@@|plugin_version|1|2026-11-07T10:00:00|s3|10.5.13 io.confluent.connect.s3.S3SinkConnector\n")
    with tempfile.TemporaryDirectory() as tmp:
        res = log_report.analyze(log_report.parse_records(records_file(tmp, text)))
    cards = {c["connector"]: c for c in res["connectors"]}
    check("sink dialect", (cards["sink"].get("jdbc"), cards["sink"].get("jdbc_from")) == ("sqlserver", "SqlServerDatabaseDialect"), cards["sink"])
    check("source dialect", cards["source"].get("jdbc") == "postgresql", cards["source"])
    check("driver exception", (cards["pg"].get("jdbc"), cards["pg"].get("jdbc_from")) == ("postgresql", "org.postgresql.util.PSQLException"), cards["pg"])
    check("not another plugin", not cards["s3"].get("jdbc"), cards["s3"])
    html = log_report.connectors_health_html(res["connectors"])
    check("icon", "sql_server.png" in html and "postgresql.png" in html, "")
    check("card", "🗄️ SQL Server" in html, "")


def test_connector_sink_or_source():
    """🔎 a sink or a source when nothing names the plugin: the record of an error reported by the runtime, the task class
    of the runtime, the clients it owns; nothing when the class is known"""
    def rec(conn, t):
        return (f"@@PGREC@@|ERROR|1|3|3|2026-11-07T10:0{t}:00|2026-11-07T10:0{t}:00\n"
                f"[2026-11-07 10:0{t}:00,000] ERROR [{conn}|task-0] boom (x)\n@@PGTS@@|2026-11-07T10:0{t}:00\n")
    text = ("@@PGFILE@@|connect.log|20|4|4|2026-11-07T10:00:00|2026-11-07T10:10:00\n"
            + rec("logreporter", 1) + rec("runtime", 2) + rec("known", 3)
            + "@@PGEVT@@|connector_hint|1|2026-11-07T10:00:00|logreporter|direction sink\n"
            + "@@PGEVT@@|plugin_logger|1|2026-11-07T10:00:00|runtime|org.apache.kafka.connect.runtime.AbstractWorkerSourceTask\n"
            + "@@PGEVT@@|plugin_logger|1|2026-11-07T10:00:00|known|io.confluent.connect.jdbc.sink.JdbcSinkTask\n")
    with tempfile.TemporaryDirectory() as tmp:
        res = log_report.analyze(log_report.parse_records(records_file(tmp, text)))
    cards = {c["connector"]: c for c in res["connectors"]}
    check("LogReporter: sink", cards["logreporter"].get("direction") == "sink", cards["logreporter"])
    check("runtime task: source", cards["runtime"].get("direction") == "source", cards["runtime"])
    html = log_report.connectors_health_html(res["connectors"])
    check("card", "a sink connector, plugin unknown" in html and "a source connector, plugin unknown (from AbstractWorkerSourceTask)" in html, "")
    check("class known: no direction line", "JdbcSinkConnector" in html and html.count("plugin unknown") == 2, "")


def test_connector_name_hints():
    """💡 a card without class: the words of its name, the class of the connectors with the same name prefix (only when
    they agree); never a class nor an icon"""
    def rec(conn, t):
        return (f"@@PGREC@@|ERROR|1|3|3|2026-11-07T10:0{t}:00|2026-11-07T10:0{t}:00\n"
                f"[2026-11-07 10:0{t}:00,000] ERROR [{conn}|task-0] boom (x)\n@@PGTS@@|2026-11-07T10:0{t}:00\n")
    text = ("@@PGFILE@@|connect.log|20|5|5|2026-11-07T10:00:00|2026-11-07T10:10:00\n"
            + rec("mdm_sink_tidb_syncme", 1) + rec("mdm_sink_tidb_maintainparty", 2) + rec("dea_hdfs3_sink_metro", 3)
            + rec("brimo_stretch-elasticsearch-sink-v2", 4) + rec("cars3_list", 5)
            + "@@PGEVT@@|plugin_logger|1|2026-11-07T10:00:00|mdm_sink_tidb_syncme|io.confluent.connect.jdbc.sink.JdbcSinkTask\n")
    with tempfile.TemporaryDirectory() as tmp:
        res = log_report.analyze(log_report.parse_records(records_file(tmp, text)))
    cards = {c["connector"]: c for c in res["connectors"]}
    check("family", cards["mdm_sink_tidb_maintainparty"].get("family_hint") == {"connectors": ["mdm_sink_tidb_syncme"],
          "class": "io.confluent.connect.jdbc.JdbcSinkConnector"}, cards["mdm_sink_tidb_maintainparty"])
    check("not a class", not cards["mdm_sink_tidb_maintainparty"].get("class"), cards["mdm_sink_tidb_maintainparty"])
    check("hdfs3", cards["dea_hdfs3_sink_metro"].get("name_hint") == ["HDFS"], cards["dea_hdfs3_sink_metro"])
    check("elasticsearch", cards["brimo_stretch-elasticsearch-sink-v2"].get("name_hint") == ["Elasticsearch"], cards["brimo_stretch-elasticsearch-sink-v2"])
    check("s3 is a word", not cards["cars3_list"].get("name_hint"), cards["cars3_list"])
    check("not on a card with a class", not cards["mdm_sink_tidb_syncme"].get("name_hint"), cards["mdm_sink_tidb_syncme"])
    html = log_report.connectors_health_html(res["connectors"])
    check("card", "💡 same name prefix as mdm_sink_tidb_syncme (JdbcSinkConnector)" in html and "💡 its name suggests HDFS" in html, "")


def test_connector_plugins_and_data_to_request():
    """📥 a connector without known class or version: ask for /connectors?expand=info and /connector-plugins; a
    /connector-plugins of the input gives the version of a class (inferred too), the support check follows"""
    text = ("@@PGFILE@@|connect.log|20|2|2|2026-11-07T10:00:00|2026-11-07T10:10:00\n"
            "@@PGREC@@|ERROR|1|3|3|2026-11-07T10:01:00|2026-11-07T10:01:00\n"
            "[2026-11-07 10:01:00,000] ERROR [jdbc|task-0] boom (x)\n@@PGTS@@|2026-11-07T10:01:00\n"
            "@@PGREC@@|ERROR|1|4|4|2026-11-07T10:02:00|2026-11-07T10:02:00\n"
            "[2026-11-07 10:02:00,000] ERROR [mystery|task-0] boom (x)\n@@PGTS@@|2026-11-07T10:02:00\n"
            "@@PGEVT@@|kafka_version|1|2026-11-07T10:00:00||7.9.1-ce\n"
            "@@PGEVT@@|plugin_logger|1|2026-11-07T10:00:00|jdbc|io.confluent.connect.jdbc.sink.JdbcSinkTask\n")
    with tempfile.TemporaryDirectory() as tmp:
        res = log_report.analyze(log_report.parse_records(records_file(tmp, text)))
    asks = [x["what"] for x in log_report.data_to_request(res, res["files"])]
    check("ask the configs", any(a.startswith("the configuration of the connectors (2 whose class is inferred or unknown") for a in asks), asks)
    check("ask the versions", any(a.startswith("the version of the connector plugin of") for a in asks), asks)
    how = next(x["how"] for x in log_report.data_to_request(res, res["files"]) if x["what"].startswith("the configuration"))
    check("expand=info", "connectors?expand=info&expand=status" in how, how)
    plugins = ("@@PGCFG@@|connector plugins|file|||connector-plugins.json\n"
               "@@PGCFGL@@|io.confluent.connect.jdbc.JdbcSinkConnector=10.7.4\n"
               "@@PGCFGL@@|io.confluent.connect.s3.S3SinkConnector=10.5.13\n")
    with tempfile.TemporaryDirectory() as tmp:
        res = log_report.analyze(log_report.parse_records(records_file(tmp, text + plugins)))
    card = next(c for c in res["connectors"] if c["connector"] == "jdbc")
    check("version installed", card.get("versions") == ["10.7.4"] and card.get("version_from") == "GET /connector-plugins", card)
    check("support", (card.get("support") or {}).get("state") == "unsupported", card.get("support"))
    html = log_report.connectors_health_html(res["connectors"])
    check("card", "version from GET /connector-plugins" in html and "class inferred from its log lines" in html, "")
    asks = [x["what"] for x in log_report.data_to_request(res, res["files"])]
    check("version of mystery still asked", any("mystery" in a for a in asks if a.startswith("the version")), asks)
    check("not jdbc", not any("jdbc" in a for a in asks if a.startswith("the version")), asks)


def test_max_poll_not_on_config_check():
    """🐢 max.poll.interval.ms exceeded: the real messages, not a config check that names the key"""
    rx = next(re.compile(p) for p, _, t, _ in log_report.HINTS if t.startswith("🐢"))
    check("config check", not rx.search("WARN Configuration 'connections.max.idle.ms' with value '540000' is lower than "
                                        "configuration 'max.poll.interval.ms' with value '21600000'. This may cause…"))
    check("CommitFailedException", rx.search("CommitFailedException: … the time between subsequent calls to poll() was longer "
                                             "than the configured max.poll.interval.ms, which typically implies…"))
    check("librdkafka", rx.search("%4|1|MAXPOLL|rdkafka#consumer-1| Application maximum poll interval (300000ms) exceeded"))


def test_startup_connection_retries():
    """🌅 the connection failures of a component that starts before the broker: LOW, apart from the HIGH 🔌 ones that
    come back after the startup"""
    retry = "WARN [AdminClient clientId=adminclient-1] Connection to node -1 (broker/172.27.0.5:9092) could not be established. Node may not be available. (org.apache.kafka.clients.NetworkClient:992)"
    later = "WARN [Producer clientId=p] Connection to node 2 (broker2/10.0.0.2:9092) could not be established. Node may not be available. (org.apache.kafka.clients.NetworkClient:992)"
    text = ("@@PGFILE@@|connect.log|100|2|9|2026-11-09T13:00:51|2026-11-09T14:00:00\n"
            "@@PGREC@@|WARN|7|10|40|2026-11-09T13:00:51|2026-11-09T13:00:54\n"
            f"[2026-11-09 13:00:51,509] {retry}\n"
            "@@PGTS@@|2026-11-09T13:00:51 2026-11-09T13:00:54\n"
            "@@PGREC@@|WARN|2|80|90|2026-11-09T13:30:00|2026-11-09T13:31:00\n"
            f"[2026-11-09 13:30:00,000] {later}\n"
            "@@PGTS@@|2026-11-09T13:30:00 2026-11-09T13:31:00\n"
            "@@PGCFG@@|DistributedConfig||50|2026-11-09T13:01:05|\n"
            "@@PGCFGL@@|group.id = connect-cluster\n"
            "@@PGEVT@@|process_start|60|2026-11-09T13:01:06||Kafka Connect worker started\n")
    with tempfile.TemporaryDirectory() as tmp:
        res = log_report.analyze(log_report.parse_records(records_file(tmp, text)))
    causes = {h["title"]: (h["severity"], h["occurrences"]) for h in res["known_causes"]}
    check("startup retries", causes.get(log_report.STARTUP_CONNECTION_TITLE) == ("LOW", 7), causes)
    check("later failure stays HIGH", causes.get(log_report.CONNECTION_TITLE) == ("HIGH", 2), causes)
    # no start in the file (a rotated customer log): the HIGH one, as before
    with tempfile.TemporaryDirectory() as tmp:
        res = log_report.analyze(log_report.parse_records(records_file(tmp, text.split("@@PGCFG@@")[0])))
    causes = {h["title"]: (h["severity"], h["occurrences"]) for h in res["known_causes"]}
    check("no start: HIGH", causes.get(log_report.CONNECTION_TITLE) == ("HIGH", 9) and log_report.STARTUP_CONNECTION_TITLE not in causes, causes)


def test_harmless_left_out():
    """🙈 the known harmless records: left out of the findings and the counts, listed with their reason"""
    text = ("@@PGFILE@@|broker.log|100|2|4|2026-11-09T13:00:51|2026-11-09T13:02:00\n"
            "@@PGREC@@|ERROR|3|10|12|2026-11-09T13:00:54|2026-11-09T13:00:55\n"
            "[2026-11-09 13:00:54,795] ERROR Unable to submit events without credentials (io.confluent.telemetry.events.exporter.http.HttpExporter)\n"
            "@@PGTS@@|2026-11-09T13:00:54\n"
            "@@PGREC@@|ERROR|1|20|20|2026-11-09T13:01:00|2026-11-09T13:01:00\n"
            "[2026-11-09 13:01:00,000] ERROR Disk error while writing (kafka.log.LogManager)\n"
            "@@PGTS@@|2026-11-09T13:01:00\n")
    with tempfile.TemporaryDirectory() as tmp:
        files = log_report.parse_records(records_file(tmp, text))
        left = log_report.drop_harmless(files)
        res = log_report.analyze(files)
    check("left out", [(h["occurrences"], h["files"]) for h in left] == [(3, ["broker.log"])], left)
    check("counts", (res["summary"]["distinct"], res["summary"]["occurrences"]) == (1, 1), res["summary"])
    check("text", "🙈 3 occurrence(s)" in log_report.harmless_text(left)[0], log_report.harmless_text(left))
    check("html", "id='harmless'" in log_report.harmless_html(left))


def test_healthy_connector_card_and_jvm():
    """✅ a connector without an error or a warning has its card (its start, plugin version, config); ☕ the JDK of the
    logs and of --jvm-versions"""
    text = ("@@PGFILE@@|connect.log|100|0|0|2026-11-09T13:00:51|2026-11-09T13:02:00\n"
            "@@PGEVT@@|connector_start|10|2026-11-09T13:01:16|http-sink|http-sink\n"
            "@@PGEVT@@|plugin_version|11|2026-11-09T13:01:16|http-sink|1.7.14 io.confluent.connect.http.HttpSinkConnector\n"
            "@@PGEVT@@|connector_start|12|2026-11-09T13:01:16|other|other\n"
            "@@PGEVT@@|jvm_version|5|2026-11-09T13:01:05||25.0.4.1+1-LTS Eclipse Adoptium\n")
    with tempfile.TemporaryDirectory() as tmp:
        res = log_report.analyze(log_report.parse_records(records_file(tmp, text)))
        jvm = os.path.join(tmp, "jvm")
        with open(jvm, "w") as fh:
            fh.write("connect.log\t25.0.4.1+1-LTS\tEclipse Adoptium\nbroker.log\t21.0.9+10-LTS\tAzul Systems, Inc.\n")
        jvms = log_report.add_jvm_versions(res["summary"]["jvm_versions"], jvm)
        files = log_report.parse_records(records_file(tmp, text))
        log_report.filter_connectors(files, ["http-sink"])
        filtered = log_report.analyze(files)
    card = next((c for c in res["connectors"] if c["connector"] == "http-sink"), None)
    check("healthy card", card and card["records"] == 0 and card.get("versions") == ["1.7.14"], card)
    check("text", any("http-sink: ✅ no error or warning" in l for l in log_report.connectors_text(res["connectors"])),
          log_report.connectors_text(res["connectors"]))
    check("--connector keeps its card only", [c["connector"] for c in filtered["connectors"]] == ["http-sink"], filtered["connectors"])
    check("jvm merged", [(j["version"], j["files"]) for j in jvms] == [("25.0.4.1+1-LTS", ["connect.log"]), ("21.0.9+10-LTS", ["broker.log"])], jvms)
    res["summary"]["jvm_versions"] = jvms
    check("tile", "☕ JDK" in log_report.jvm_tile(res["summary"]) and "25 / 21" in log_report.jvm_tile(res["summary"]), log_report.jvm_tile(res["summary"]))


def test_confluent_connect_logs():
    """the logs of a fully managed connector (confluent connect logs): --output-file keys of any case, the stacktrace of
    an exception object (-o json), and the [connector|task-0] context with PG_LOG_CONNECTOR_NAME"""
    out_file = {"Timestamp": "2026-11-09T10:00:05.456Z", "Level": "ERROR", "TaskId": "task-0", "Message": "Task is being killed",
                "Exception": "org.x.ConnectException: boom\n\tat a.b(C.java:1)\nCaused by: java.sql.SQLException: ORA-00942"}
    api = {"timestamp": "2026-11-09T10:00:06Z", "level": "WARN", "task_id": "", "message": "Retrying",
           "exception": {"stacktrace": "java.lang.IllegalStateException: x\n\tat a.b(C.java:1)"}}
    os.environ.pop("PG_LOG_CONNECTOR_NAME", None)
    text = lines(out_file)
    check("any case", text.startswith("[2026-11-09T10:00:05.456Z] ERROR Task is being killed") and "Caused by: java.sql.SQLException: ORA-00942" in text, text)
    check("stacktrace of -o json", "java.lang.IllegalStateException: x" in lines(api), lines(api))
    os.environ["PG_LOG_CONNECTOR_NAME"] = "OracleSink"
    try:
        check("task context", "ERROR [OracleSink|task-0] Task is being killed" in lines(out_file), lines(out_file))
        check("worker context", "WARN [OracleSink|worker] Retrying" in lines(api), lines(api))
        already = dict(out_file, Message="[other|task-3] Task is being killed")
        check("context kept", "ERROR [other|task-3] Task is being killed" in lines(already), lines(already))
    finally:
        os.environ.pop("PG_LOG_CONNECTOR_NAME", None)


def test_ocr_rebuild():
    """📷 the lines of a screenshot (ocr.py): the brackets of a timestamp, the {} of a task id, the tab of a frame, the
    spaces tesseract adds inside a Java name, the usual g/q j/i misreadings of a package; a line wrapped by the terminal
    joined to its record; never a digit (task-@ stays: a regex would invent the value)"""
    raw = ["|2026-11-09 10:00:05,4561 ERROR [jdbc-sink|task-0] WorkerSinkTaskiid=jdbc-sink-0; Task threw an uncaught and",
           "unrecoverable exception. (orq.apache.kafka.connect.runtime.WorkerTask: 234)",
           "org.apache. kafka.connect.errors.ConnectException: Exiting WorkerSinkTask due to unrecoverable exception.",
           "at org.apache. kafka. connect. runtime.WorkerSinkTask.deliverMessages (WorkerSinkTask. java: 632)",
           "Caused by: java.sql.SQLException: ORA-01017: invalid username/password; logon denied",
           "[2026-11-09 10:00:06,000] WARN [s|task-@] (orq.apache.kafka.connect.ison.JsonConverterConfiq:375)"]
    out = ocr.rebuild([ocr.fix_line(l) for l in raw])
    check("record", out[0] == "[2026-11-09 10:00:05,456] ERROR [jdbc-sink|task-0] WorkerSinkTask{id=jdbc-sink-0} Task threw an "
          "uncaught and unrecoverable exception. (org.apache.kafka.connect.runtime.WorkerTask:234)", out[0])
    check("exception", out[1] == "org.apache.kafka.connect.errors.ConnectException: Exiting WorkerSinkTask due to unrecoverable exception.", out[1])
    check("frame", out[2] == "\tat org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:632)", out[2])
    check("caused by", out[3].startswith("Caused by: java.sql.SQLException: ORA-01017"), out[3])
    check("package names, not digits", out[4] == "[2026-11-09 10:00:06,000] WARN [s|task-@] (org.apache.kafka.connect.json.JsonConverterConfig:375)", out[4])
    check("prose kept", ocr.fix_line("Node may not be available. Retrying.") == "Node may not be available. Retrying.")


def test_other_files_copy_button():
    """🧰 a 📋 copy button per command, with the command alone (not the note after it), none for a step"""
    of = {"files": [], "commands": [
        {"icon": "🧵", "what": "thread dumps", "files": ["a.txt"], "command": "playground analyze thread-dump -f /x/a.txt"},
        {"icon": "🖼️", "what": "screenshot", "files": ["s.png"], "command": "playground analyze logs --ocr -f /x/s.png (or: open /x/s.png)"},
        {"icon": "📄", "what": "document", "files": ["d.pdf"], "command": "pdftotext -layout /x/d.pdf /tmp/pdf.log && playground analyze logs -f /tmp/pdf.log (pdftotext: brew install poppler)"},
        {"icon": "📄", "what": "document", "files": ["d.xls"], "command": "save /x/d.xls again as .docx / .xlsx"}]}
    html = log_report.other_files_html(of)
    cmds = re.findall(r"data-cmd='([^']*)'", html)
    check("commands copied alone", cmds == ["playground analyze thread-dump -f /x/a.txt", "playground analyze logs --ocr -f /x/s.png",
                                            "pdftotext -layout /x/d.pdf /tmp/pdf.log &amp;&amp; playground analyze logs -f /tmp/pdf.log"], cmds)


def test_host_path_map():
    """the ✏️ links inside the kdp-analyze-logs image (tools/analyze-logs-image): /data is the folder of the host"""
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "report-common"))
    import log_viewer
    saved = os.environ.pop("PLAYGROUND_HOST_PATH_MAP", None)
    try:
        check("no map: unchanged", log_viewer.editor_url("/Users/me/a:b.log", 3) == "vscode://file/Users/me/a%3Ab.log:3",
              log_viewer.editor_url("/Users/me/a:b.log", 3))
        os.environ["PLAYGROUND_HOST_PATH_MAP"] = "/data=/home/me/case/"
        check("under /data", log_viewer.editor_url("/data/out/x.log", 7) == "vscode://file/home/me/case/out/x.log:7",
              log_viewer.editor_url("/data/out/x.log", 7))
        check("/data itself", log_viewer.host_path("/data") == "/home/me/case", log_viewer.host_path("/data"))
        check("not /database", log_viewer.editor_url("/database/x.log", 1) == "", log_viewer.editor_url("/database/x.log", 1))
        check("elsewhere in the container", log_viewer.editor_url("/tmp/pg-x/a.log", 1) == "")
        os.environ["PLAYGROUND_HOST_PATH_MAP"] = "/data=C:\\Users\\me\\case"
        check("Windows folder", log_viewer.editor_url("/data/a b.log", 2) == "vscode://file/C:/Users/me/case/a%20b.log:2",
              log_viewer.editor_url("/data/a b.log", 2))
        os.environ["PLAYGROUND_HOST_PATH_MAP"] = "/data=."
        check("host folder not known: no link", log_viewer.editor_url("/data/a.log", 2) == "")
    finally:
        os.environ.pop("PLAYGROUND_HOST_PATH_MAP", None)
        if saved is not None:
            os.environ["PLAYGROUND_HOST_PATH_MAP"] = saved


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
