"""
Regression tests of the helpers of playground analyze logs (exports of log events, overview, progress), plain asserts,
no dependency:

    python3 -I tools/log-analyzer/test_log_analyzer.py
"""
import csv
import io
import json
import os
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
            line = line.replace("|", "\t")
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


def test_cfk_log_banner():
    """🔥 the banner of a CFK bundle report: the key lines of the log analysis at the marker, a link to the log report
    relative to the CFK report, nothing changed in a report without the marker"""
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "cfk-analysis"))
    import log_banner
    logs = {"summary": {"occurrences": 8, "distinct": 6, "files_with_findings": 4, "files_scanned": 4},
            "known_causes": [{"title": "💥 OutOfMemoryError", "occurrences": 2, "first": {"timestamp": "2026-10-14T09:00:03"}}],
            "fixed_bugs": [{"title": "🩹 S3 sink NullPointerException", "ref": "CC-35613", "connectors": [
                {"connector": "s3", "version": "10.6.1", "verdict": "affected", "upgrade_to": "10.6.11"}]}],
            "task_workers": {"connectors": [{"connector": "jdbc", "only_on": "connect-1"}]},
            "timeline": [{"time": "2026-10-14T09:01:00", "text": "🛑 Kafka broker shutting down",
                          "effects": {"occurrences": 39, "seconds": 60}}],
            "connectors": [{}], "data_to_request": [{}]}
    with tempfile.TemporaryDirectory() as tmp:
        report, other = os.path.join(tmp, "b-cfk-report.html"), os.path.join(tmp, "x.html")
        for p in (report, other):
            with open(p, "w") as fh:
                fh.write("<main><div>verdict</div><!--pg-log-analysis--></main>" if p == report else "<main></main>")
        js = os.path.join(tmp, "logs.json")
        with open(js, "w") as fh:
            json.dump(logs, fh)
        saved = sys.argv
        sys.argv = ["log_banner.py", "--report", report, "--report", other, "--logs-json", js,
                    "--log-report", os.path.join(tmp, "case #1-log-report.html")]
        try:
            rc = log_banner.main()
        finally:
            sys.argv = saved
        page = open(report).read()
        check("rc", rc == 0)
        check("marker replaced", "<!--pg-log-analysis-->" not in page and "🔥 Log analysis of the pod logs: 8 occurrence(s)" in page, page[:300])
        check("link", "href='case%20%231-log-report.html'" in page, page)
        for x in ("💥 OutOfMemoryError ×2", "🩹 s3 runs 10.6.1", "🎯 jdbc", "💥 39 errors"):
            check(x, x in page, page)
        check("other untouched", open(other).read() == "<main></main>")


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
