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


def test_root_cause_ignores_offsets_and_table_lists():
    # Oracle CDC: one table list per task and the offsets in the message, still one root cause (526 before, one per task)
    def rec(line, msg, ts):
        return {"message": f"[{ts},707] WARN [cdc-A|task-{line}] {msg} (io.confluent.connect.oracle.cdc.OracleCdcSourceTask:683)",
                "root_cause": "", "root_cause_message": "", "level": "WARN", "count": 1, "connector": "cdc-A",
                "timestamps": [ts.replace(" ", "T")], "first_ts": ts.replace(" ", "T"), "first_line": line, "index": line}
    tables = "|".join(f"F_TABLE_NUMBER_{n}_WITH_A_LONG_NAME" for n in range(8))
    files = [{"label": "connect.log", "records": [
        rec(1, f"Failed to commit consumer offset {{}} for tables 0=DB1.T24({tables}). Attempt 1 of 50", "2026-10-13 22:47:39"),
        rec(2, "Failed to commit consumer offset {0=36227957} for tables 0=DB2.T24(FLXP_SEC_TRADE|FLYU_EFG). Attempt 2 of 50",
            "2026-10-13 22:48:58"),
        rec(3, "Task threw an uncaught and unrecoverable exception", "2026-10-13 22:49:00")]}]
    produce = ("Got error produce response with correlation id {} on topic-partition _confluent-monitoring-{}, retrying "
               "(2147483646 attempts left). Error: NETWORK_EXCEPTION. Error Message: Disconnected from node 2")
    files[0]["records"] += [rec(4, produce.format(4755, 3), "2026-10-13 22:50:00"), rec(5, produce.format(102568, 10), "2026-10-13 22:51:00")]
    causes = log_report.root_causes(files)
    check("one cause for the commit warnings, one for the produce errors", len(causes) == 3, [c["label"] for c in causes])
    check("occurrences merged", causes[0]["occurrences"] == 2 and causes[0]["label"].startswith("Failed to commit consumer offset {}"),
          causes[0])


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


def test_expanded_size():
    # a 5 MB .zip of a 250 MB support bundle is a large input: the progress page opens for it (20 MB threshold)
    import gzip
    import zipfile
    with tempfile.TemporaryDirectory() as d:
        data = b"2026-11-06 10:00:00 INFO the same line\n" * 50000
        z, g, t = os.path.join(d, "b.zip"), os.path.join(d, "b.log.gz"), os.path.join(d, "b.tar")
        with zipfile.ZipFile(z, "w", zipfile.ZIP_DEFLATED) as zf:
            zf.writestr("a.log", data)
            zf.writestr("b.log", data)
        with gzip.open(g, "wb") as fh:
            fh.write(data)
        open(t, "wb").write(data)
        zs, gs, ts = os.path.getsize(z), os.path.getsize(g), os.path.getsize(t)
        check("zip content", progress.expanded_size(z, zs) == 2 * len(data), (zs, progress.expanded_size(z, zs)))
        check("gzip content", progress.expanded_size(g, gs) == len(data), (gs, progress.expanded_size(g, gs)))
        check("tar as is", progress.expanded_size(t, ts) == ts, progress.expanded_size(t, ts))
        bad = os.path.join(d, "bad.zip")
        open(bad, "wb").write(b"not a zip")
        check("bad zip", progress.expanded_size(bad, 9) == 9 * progress.COMPRESSION_RATIO, progress.expanded_size(bad, 9))


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


def test_secret_registry_duplicate_urls_and_failed_start():
    """🪞 the secret registry group refusing two members with the same URL, 🚫 the worker exiting at startup, and 🧷 a
    ${provider:path:key} placeholder that reached a connector: known causes; a WARN quoting a placeholder is not one"""
    text = ("@@PGFILE@@|connect.log|40|5|5|2026-11-07T10:00:00|2026-11-07T10:10:00\n"
            "@@PGREC@@|ERROR|2|3|4|2026-11-07T10:01:00|2026-11-07T10:06:00\n"
            "[2026-11-07 10:01:00,000] ERROR Found duplicate URLs for secret registry group members. This indicates a "
            "misconfiguration and is common when executing in containers. (io.confluent.kafka.secretregistry.masterelector."
            "kafka.SecretRegistryCoordinator:191)\n"
            "@@PGTS@@|2026-11-07T10:01:00\n"
            "@@PGREC@@|ERROR|2|5|9|2026-11-07T10:01:00|2026-11-07T10:06:00\n"
            "[2026-11-07 10:01:00,010] ERROR Unexpected exception in secret registry group processing thread (io.confluent."
            "kafka.secretregistry.masterelector.kafka.KafkaGroupMasterElector:214)\n"
            "    java.lang.IllegalStateException: The secret registry group contained multiple members advertising the same "
            "URL. Verify that each instance has a unique, routable listener by setting the 'listeners' configuration.\n"
            "@@PGTS@@|2026-11-07T10:01:00\n"
            "@@PGREC@@|ERROR|2|10|14|2026-11-07T10:02:00|2026-11-07T10:07:00\n"
            "[2026-11-07 10:02:00,000] ERROR Failed to start Connect (org.apache.kafka.connect.cli.AbstractConnectCli:178)\n"
            "    org.apache.kafka.connect.errors.ConnectException: Error initializing the secret registry\n"
            "    Caused by: io.confluent.kafka.secretregistry.exceptions.SecretRegistryTimeoutException: Timed out waiting "
            "for join group to complete\n"
            "@@PGTS@@|2026-11-07T10:02:00\n"
            "@@PGREC@@|ERROR|1|20|22|2026-11-07T10:08:00|2026-11-07T10:08:00\n"
            "[2026-11-07 10:08:00,000] ERROR [http-sink|task-0] Task threw an uncaught and unrecoverable exception (x)\n"
            "    org.jose4j.jwt.consumer.InvalidJwtException: JWT processing failed. Additional details: [[17] Unable to "
            "process JOSE object (cause: org.jose4j.lang.JoseException: Invalid JOSE Compact Serialization. Expecting "
            "either 3 or 5 parts for JWS or JWE respectively but was 1.): ${secret:http-sink:token}]\n"
            "@@PGTS@@|2026-11-07T10:08:00\n"
            "@@PGREC@@|WARN|1|30|30|2026-11-07T10:09:00|2026-11-07T10:09:00\n"
            "[2026-11-07 10:09:00,000] WARN The value ${file:/opt/props.properties:user} of key user is kept as it is (x)\n"
            "@@PGTS@@|2026-11-07T10:09:00\n")
    with tempfile.TemporaryDirectory() as tmp:
        res = log_report.analyze(log_report.parse_records(records_file(tmp, text)))
    hints = {h["title"]: h for h in res["known_causes"]}
    dup = hints.get("🪞 Secret registry: duplicate URLs, Connect does not start")
    check("duplicate URLs: both records, critical", dup and dup["occurrences"] == 4 and dup["severity"] == "CRITICAL", dup)
    check("advice names admin.listeners", "admin.listeners" in dup["advice"], dup["advice"])
    start = hints.get("🚫 Connect worker failed to start")
    check("failed to start", start and start["occurrences"] == 2, start)
    ph = hints.get("🧷 Config provider placeholder not resolved")
    check("placeholder: the task error only, not the WARN", ph and ph["occurrences"] == 1, ph)
    check("secret registry cause before the generic ones", list(hints).index(dup["title"]) < list(hints).index(start["title"]),
          list(hints))


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
    check("never logs at DEBUG", not any("DEBUG" in w for w in whats), whats)
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


def test_restart_loop():
    """🔁 a worker that failed to start again and again (ERROR Failed to start Connect, its rotated files merged), a process
    stopped every few minutes: a restart loop, first in the 🔄 table, in its text and in the verdict; two stops or two failed
    starts are not one"""
    def failed(f, n, t0):
        return "".join(f"@@PGEVT@@|process_start_failed|{10 + i}|2026-11-07T{t0 + i // 6:02d}:{i % 6 * 10 + 5:02d}:00||Kafka Connect failed to start\n"
                       f"@@PGEVT@@|process_stop|{11 + i}|2026-11-07T{t0 + i // 6:02d}:{i % 6 * 10 + 5:02d}:01||Kafka Connect worker stopping\n"
                       for i in range(n)) + f"@@PGEVTN@@|process_start_failed|connect|{n}\n@@PGEVTN@@|process_stop|connect|{n}\n"
    err = ("@@PGREC@@|ERROR|1|5|5|2026-11-07T10:00:00|2026-11-07T10:00:00\n"
           "[2026-11-07 10:00:00,000] ERROR Failed to start Connect (org.apache.kafka.connect.cli.AbstractConnectCli:178)\n"
           "@@PGTS@@|2026-11-07T10:00:00\n")
    text = ("@@PGFILE@@|w1/connect.log.1|1000|1|0|2026-11-07T10:00:00|2026-11-07T10:20:00\n" + err + failed("", 2, 10)
            + "@@PGFILE@@|w1/connect.log|1000|1|0|2026-11-07T11:00:00|2026-11-07T11:20:00\n" + err + failed("", 2, 11)
            # another worker: two failed starts only
            + "@@PGFILE@@|w2/connect.log|1000|1|0|2026-11-07T10:00:00|2026-11-07T10:20:00\n" + err + failed("", 2, 10)
            # a broker stopped every 10 min, four times: a loop; another one stopped twice is not
            + "@@PGFILE@@|b1/server.log|1000|1|0|2026-11-07T10:00:00|2026-11-07T11:00:00\n" + err
            + "".join(f"@@PGEVT@@|process_stop|{i}|2026-11-07T10:{i * 10:02d}:00||Kafka broker shutting down\n" for i in range(4))
            + "@@PGEVTN@@|process_stop|broker|4\n"
            + "@@PGFILE@@|b2/server.log|1000|1|0|2026-11-07T10:00:00|2026-11-07T11:00:00\n" + err
            + "".join(f"@@PGEVT@@|process_stop|{i}|2026-11-07T10:{i * 10:02d}:00||Kafka broker shutting down\n" for i in range(2))
            + "@@PGEVTN@@|process_stop|broker|2\n")
    with tempfile.TemporaryDirectory() as tmp:
        res = log_report.analyze(log_report.parse_records(records_file(tmp, text)))
    loops = {(lp["worker"], lp["who"]): lp for lp in res["lifecycle"]["loops"]}
    check("the loops", set(loops) == {("w1/connect.log", "connect"), ("b1/server.log", "broker")}, loops)
    w1 = loops[("w1/connect.log", "connect")]
    check("rotated files merged", w1["failed"] == 4 and w1["first"] == "2026-11-07 10:05:00" and w1["last"] == "2026-11-07 11:15:00", w1)
    b1 = loops[("b1/server.log", "broker")]
    check("broker stopped every 10 min", b1["failed"] == 0 and b1["stops"] == 4 and b1["every_seconds"] == 600, b1)
    check("loop text", log_report.restart_loop_text(w1).startswith("Kafka Connect (w1/connect.log) failed to start 4 times, 2026-11-07 10:05:00 → 11:15:00"),
          log_report.restart_loop_text(w1))
    first = res["lifecycle"]["rows"][0]
    check("failed starts first, with the loop badge", first["kind"] == "process_start_failed" and first["loop"], first)
    text_out = "\n".join(log_report.lifecycle_text(res["lifecycle"]))
    check("in the text", "🔁 RESTART LOOP Kafka Connect (w1/connect.log) failed to start 4 times" in text_out, text_out)
    check("in the verdict", "🔁 Restart loop: Kafka Connect (w1/connect.log) failed to start 4 times" in log_report.logs_verdict(res, "ERROR")[1],
          log_report.logs_verdict(res, "ERROR"))
    check("in the HTML", "🔁 Restart loop: Kafka Connect (w1/connect.log)" in log_report.lifecycle_html(res["lifecycle"]), "")
    tl = [ev["text"] for ev in res["timeline"] if ev["text"].startswith("💥 Kafka Connect failed")]
    check("failed starts in the timeline", len(tl) >= 1, tl)


def test_verdict_box_and_bare_exception():
    """🚨 the verdict of the HTML report: the headline, then a line per finding (👉 start with, 🔁 restart loop), each a link;
    the text verdict stays one sentence. 📍 an exception without a message (WakeupException): its card says where it was
    thrown and the message of the log line that reported it"""
    stack = ("org.apache.kafka.common.errors.WakeupException\n"
             "\tat org.apache.kafka.clients.consumer.internals.ConsumerNetworkClient.maybeTriggerWakeup(ConsumerNetworkClient.java:531)\n"
             "\tat org.apache.kafka.clients.consumer.internals.ConsumerNetworkClient.poll(ConsumerNetworkClient.java:295)\n"
             "\tat com.example.registry.GroupCoordinator.poll(GroupCoordinator.java:124)\n"
             "\tat java.base/java.lang.Thread.run(Thread.java:840)")
    check("thrown at", log_report.thrown_at(stack) == "ConsumerNetworkClient.maybeTriggerWakeup(ConsumerNetworkClient.java:531)"
          " ← GroupCoordinator.poll(GroupCoordinator.java:124)", log_report.thrown_at(stack))
    check("no stack", log_report.thrown_at("boom") == "")
    # the record keeps 3 frames (indented by the digest), its context (numbered) the whole stack
    head_line = "[2026-11-07 10:00:00,000] ERROR Unexpected exception in group processing thread (com.example.registry.Elector:214)"
    rec_lines = [head_line, "    " + stack.splitlines()[0]] + ["        " + l.strip() for l in stack.splitlines()[1:3]]
    ctx_lines = [f"@@PGCTX@@|{i + 1:6d} {'▶' if i == 0 else ' '} {l}" for i, l in enumerate([head_line] + stack.splitlines())]
    text = ("@@PGFILE@@|connect.log|1000|1|0|2026-11-07T10:00:00|2026-11-07T11:00:00\n"
            "@@PGREC@@|ERROR|4|5|10|2026-11-07T10:00:00|2026-11-07T10:30:00\n"
            + "\n".join(rec_lines) + "\n@@PGTS@@|2026-11-07T10:00:00 2026-11-07T10:30:00\n" + "\n".join(ctx_lines) + "\n"
            + "".join(f"@@PGEVT@@|process_start_failed|{i}|2026-11-07T10:{i * 10:02d}:00||Kafka Connect failed to start\n" for i in range(3))
            + "@@PGEVTN@@|process_start_failed|connect|3\n")
    with tempfile.TemporaryDirectory() as tmp:
        res = log_report.analyze(log_report.parse_records(records_file(tmp, text)))
    cls, head, lines = log_report.verdict_parts(res, "ERROR")
    check("verdict lines", [l["icon"] for l in lines] == ["👉", "🔁"], lines)
    box = log_report.verdict_box_html(cls, head, lines)
    check("box: headline and links", "<span class='vd-head'>🚨 4 ERROR/FATAL occurrence(s)" in box and "href='#lc-section'" in box, box)
    check("text: one sentence", log_report.verdict(res, "ERROR")[1].startswith("🚨 4 ERROR/FATAL occurrence(s), 1 distinct record(s) in 1 file(s): start with "),
          log_report.verdict(res, "ERROR")[1])
    rows = log_report.chain_rows(log_report.killed_task_chains([(0, res["files"][0], r) for r in res["files"][0]["records"]]), 3, "high", {})
    check("bare exception: thrown at and logged as", "📍 thrown at" in rows[0] and "GroupCoordinator.poll(GroupCoordinator.java:124)" in rows[0] and "Unexpected exception in group processing thread" in rows[0], rows)


def test_overlapping_copy_and_worker_names():
    """✂️ an overlapping copy of another input (analyze logs --same-source) is the worker of that one: no second worker in
    🖥️ Tasks by worker, no task "moving" between the two; 🖥️ the worker names shown are the part that differs"""
    with tempfile.TemporaryDirectory() as tmp:
        same = os.path.join(tmp, "same-source")
        with open(same, "w") as fh:
            fh.write("/data/s3-sink-log (1).txt\t/data/s3-sink-log.txt\t4936\t65\n")
        try:
            log_report.read_same_source(same)
            check("alias", log_report.worker_of("/data/s3-sink-log (1).txt") == log_report.worker_of("/data/s3-sink-log.txt"))
            files = [{"label": "/data/s3-sink-log.txt"}, {"label": "/data/s3-sink-log (1).txt"}]
            log_report.shorten_labels(files)
            check("alias after the labels are shortened", log_report.SAME_SOURCE == {"s3-sink-log (1).txt": "s3-sink-log.txt"}
                  and log_report.OVERLAPS[0]["kept_lines"] == 65, log_report.SAME_SOURCE)
            check("overlaps note", "only its 65 other lines were read" in log_report.overlaps_html(), log_report.overlaps_html())
        finally:
            log_report.SAME_SOURCE.clear()
            log_report.OVERLAPS.clear()
    names = log_report.worker_short_names
    check("short: rotated pods", list(names(["b/pods/connect-0/connect.log", "b/pods/connect-1/connect.log"]).values())
          == ["…connect-0", "…connect-1"], names(["b/pods/connect-0/connect.log", "b/pods/connect-1/connect.log"]))
    check("short: long file names", list(names(["acme.s3-sink.v2-PROD-log (1) 1.txt", "acme.s3-sink.v2-PROD-log.txt"]).values())
          == ["…PROD-log (1) 1.txt", "…PROD-log.txt"], names(["acme.s3-sink.v2-PROD-log (1) 1.txt", "acme.s3-sink.v2-PROD-log.txt"]))
    check("short: already short", names(["w1", "w2"]) == {"w1": "w1", "w2": "w2"})
    check("short: one worker", names(["connect.log"]) == {"connect.log": "connect.log"})


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


def test_broker_signals():
    """🐢 the signals of a broker under pressure (INFO / WARN lines): a row per kind and broker with the partitions they
    happen to most, a storm when they repeat, the bursts on the timeline (💥 after-effects), their own text block and table"""
    evs = "".join(f"@@PGEVT@@|isr_shrink|{10 + i}|2026-11-07T10:{i:02d}:00||broker 1 · orders-{i % 2} (1,2,3 -> 1,3)\n" for i in range(12))
    text = ("@@PGFILE@@|broker-1/server.log|1000|1|1|2026-11-07T10:00:00|2026-11-07T11:00:00\n"
            "@@PGREC@@|ERROR|1|1|1|2026-11-07T10:40:00|2026-11-07T10:40:00\n"
            "[2026-11-07 10:40:00,000] ERROR boom (x)\n"
            "@@PGTS@@|2026-11-07T10:40:00\n" + evs +
            "@@PGEVT@@|log_cleaner|50|2026-11-07T10:30:00||log cleaner · thread died\n"
            "@@PGEVT@@|response_dropped|51|2026-11-07T10:31:00||broker · client gone before the response\n"
            "@@PGEVTN@@|isr_shrink|broker 1|12\n@@PGEVTN@@|log_cleaner|log cleaner|1\n@@PGEVTN@@|response_dropped|broker|1\n")
    with tempfile.TemporaryDirectory() as tmp:
        res = log_report.analyze(log_report.parse_records(records_file(tmp, text)))
    rows = {(r["kind"], r["who"]): r for r in res["lifecycle"]["rows"]}
    isr = rows.get(("isr_shrink", "broker 1"))
    check("an ISR row for broker 1", isr and isr["count"] == 12, rows.keys())
    check("its partitions as reason", isr and isr["reason"] == "orders-0 ×6, orders-1 ×6", isr)
    check("12 in an hour: a storm", isr and isr["storm"], isr)
    check("a broker without id: its file", any(k == "response_dropped" and w.startswith("broker (") and w.endswith("server.log)")
                                              for k, w in rows), rows.keys())
    # the log cleaner lines name no broker: its file (two brokers, two rows)
    cleaner = [r for (k, w), r in rows.items() if k == "log_cleaner" and w.startswith("log cleaner (") and w.endswith("server.log)")]
    check("the log cleaner, not a storm", cleaner and not cleaner[0]["storm"], rows.keys())
    tl = [ev["text"] for ev in res["timeline"]]
    check("ISR shrinks on the timeline, one burst", sum(t.startswith("📉") for t in tl) == 1
          and any(t.startswith("📉 12 ISR shrinks on broker 1 in 11 min (orders-0, orders-1)") for t in tl), tl)
    check("log cleaner on the timeline", any(t.startswith("🧽 1 log cleaner failure on log cleaner (") for t in tl), tl)
    check("a single response dropped is not on the timeline", not any(t.startswith("📭") for t in tl), tl)
    bt = log_report.broker_signals_text(res["lifecycle"])
    check("broker text block", bt and bt[0].startswith("🐢") and any("🌀 STORM broker 1: 12 ISR shrinks" in x for x in bt), bt)
    check("not in the restarts block", not any("ISR" in x for x in log_report.lifecycle_text(res["lifecycle"])),
          log_report.lifecycle_text(res["lifecycle"]))
    md = log_report.ticket_markdown(res, "t", "ERROR")
    check("broker table in the ticket", "### Broker signals" in md and "orders-0 ×6" in md, md[-800:])


def test_cluster_layout():
    """🗺️ kafka-topics --describe and 💽 kafka-log-dirs outputs (the broker_pressure sample): found by the triage, leaders
    and disk per broker, the findings (offline log dir, under-replicated, non-preferred leaders, disk skew)"""
    import bundle_triage
    import cluster_layout
    here = os.path.join(os.path.dirname(os.path.abspath(__file__)), "samples", "broker-pressure")
    topics, dirs = os.path.join(here, "kafka-topics-describe.txt"), os.path.join(here, "kafka-log-dirs.txt")
    check("triage: topics describe", bundle_triage.kind_of("topics.txt", topics) == "topic_describe")
    check("triage: log dirs", bundle_triage.kind_of("dirs.txt", dirs) == "log_dirs")
    check("triage: a broker log is neither", bundle_triage.kind_of("server.log", os.path.join(here, "broker-1", "server.log")) is None)
    res = cluster_layout.analyze([("topics.txt", topics), ("dirs.txt", dirs)])
    b = {x["id"]: x for x in res["brokers"]}
    check("31 partitions of 4 topics", res["partitions"] == 31 and res["topics"] == 4, res)
    check("leaders per broker", (b[1]["leaders"], b[2]["leaders"], b[3]["leaders"]) == (11, 4, 16), b)
    check("non-preferred leaders of broker 2", b[2]["not_preferred"] == 6, b[2])
    texts = [f["severity"] + " " + f["text"] for f in res["findings"]]
    check("offline log dir first", texts[0].startswith("HIGH broker 3: log dir /var/lib/kafka/data2 has an error"), texts)
    check("under-replicated", any(t.startswith("MEDIUM 3 under-replicated partition(s) of 31") for t in texts), texts)
    check("disk skew", any("Disk usage skew: broker 1 uses 18.4 GB" in t for t in texts), texts)
    check("rf 1", res["rf1_topics"] == ["audit"], res["rf1_topics"])
    # an offline partition and a partition under min.insync.replicas
    with tempfile.TemporaryDirectory() as tmp:
        p = os.path.join(tmp, "t.txt")
        with open(p, "w") as fh:
            fh.write("Topic: t\tTopicId: x\tPartitionCount: 2\tReplicationFactor: 3\tConfigs: min.insync.replicas=2\n"
                     "\tTopic: t\tPartition: 0\tLeader: none\tReplicas: 1,2,3\tIsr: \n"
                     "\tTopic: t\tPartition: 1\tLeader: 1\tReplicas: 1,2,3\tIsr: 1\n")
        r2 = cluster_layout.analyze([("t.txt", p)])
    check("offline: critical", r2["findings"][0]["severity"] == "CRITICAL" and r2["offline"] == ["t-0"], r2["findings"])
    check("under min ISR", r2["under_min_isr"] == ["t-0", "t-1"], r2)


def test_jvm_dumps():
    """🧵 the thread dumps of the triage analyzed in the log report (the read_path of the run when no copy is kept, the
    full thread report written), each dump on the timeline; 🔬 the heap dumps listed with their command"""
    import jvm_dumps
    samples = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "thread-analyzer", "samples")
    files = [os.path.join(samples, f"jdk21-scenario-{i}.txt") for i in (1, 2, 3)]
    of = {"files": [{"label": f"b/td-{i}.txt", "path": None, "read_path": p, "kind": "thread_dump"} for i, p in enumerate(files, 1)]
                   + [{"label": "b/heap.hprof", "path": "/x/heap.hprof", "kind": "heap_dump", "bytes": 2048}],
          "commands": [{"kind": "thread_dump", "folder": "b", "files": ["b/td-1.txt", "b/td-2.txt", "b/td-3.txt"], "command": "playground analyze thread-dump -f …"},
                       {"kind": "heap_dump", "folder": "b", "files": ["b/heap.hprof"], "command": "playground analyze heap-dump -f /x/heap.hprof"}]}
    with tempfile.TemporaryDirectory() as tmp:
        groups = jvm_dumps.thread_dumps(of, tmp, "case")
        check("one group, 3 dumps of the same JVM", len(groups) == 1 and len(groups[0]["dumps"]) == 3 and groups[0]["same_jvm"] == 3, groups)
        check("deadlock first", groups[0]["findings"][0]["severity"] == "CRITICAL" and "Deadlock" in groups[0]["findings"][0]["text"], groups[0]["findings"])
        check("thread report written", os.path.isfile(os.path.join(tmp, "case-thread-dumps.html")), os.listdir(tmp))
        check("labels of the dumps", groups[0]["dumps"][0]["file"] == "b/td-1.txt", groups[0]["dumps"][0])
    tl = jvm_dumps.timeline_events(groups)
    check("a timeline event per dump", len(tl) == 3 and tl[0]["text"].startswith("🧵 thread dump #1 (47 threads): CRITICAL Deadlock"), tl)
    heaps = jvm_dumps.heap_dumps(of)
    check("heap dump listed", heaps == [{"file": "b/heap.hprof", "bytes": 2048, "command": "playground analyze heap-dump -f /x/heap.hprof"}], heaps)
    res = {"summary": {}, "thread_dumps": groups, "heap_dumps": heaps}
    cls, text = log_report.dumps_verdict(res, "ok", "✅ fine.")
    check("verdict", cls == "danger" and "🧵 thread dumps:" in text and "🔬 1 heap dump(s)" in text, (cls, text))
    gone = jvm_dumps.thread_dumps({"files": [{"label": "x", "path": None, "read_path": "/nope"}],
                                   "commands": [{"kind": "thread_dump", "files": ["x"], "command": "c"}]})
    check("files gone: an error, not an exception", gone[0].get("error") == "the files are no longer on disk", gone)


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


def test_dns_outage():
    """🌐 host names not resolved: their own known cause (not 🔌), the window, the hosts, the Java lookups that failed in the
    resolver vs the failures served from the negative cache of the JVM, the clients not created; the ones of a component
    starting go to the one 🌅 LOW cause with the connection retries; 🧹 the clients aborted by a task stop are LOW"""
    def rec(level, count, line, first, last, body):
        return (f"@@PGREC@@|{level}|{count}|{line}|{line + 5}|{first}|{last}\n{body}\n@@PGTS@@|{first} {last}\n")
    text = ("@@PGFILE@@|connect.log|1000|6|0|2026-10-24T17:00:00|2026-10-24T18:00:00\n"
            + rec("WARN", 4, 10, "2026-10-24T17:00:01", "2026-10-24T17:00:05",
                  "[2026-10-24 17:00:01,000] WARN Couldn't resolve server broker:9092 from bootstrap.servers as DNS resolution failed for broker (org.apache.kafka.clients.ClientUtils:106)")
            + rec("WARN", 3, 12, "2026-10-24T17:00:02", "2026-10-24T17:00:06",
                  "[2026-10-24 17:00:02,000] WARN [AdminClient clientId=a] Connection to node -1 (broker/172.27.0.5:9092) could not be established. Node may not be available. (org.apache.kafka.clients.NetworkClient:992)")
            + rec("WARN", 2, 100, "2026-10-24T17:22:59", "2026-10-24T17:23:55",
                  "[2026-10-24 17:22:59,302] WARN [cdc|task-16] [Consumer clientId=c] Error connecting to node broker-6.acme.corp:9091 (id: -3 rack: null) (org.apache.kafka.clients.NetworkClient:1207)\n"
                  "java.net.UnknownHostException: broker-6.acme.corp: Name or service not known")
            + rec("WARN", 30, 110, "2026-10-24T17:22:59", "2026-10-24T17:27:04",
                  "[2026-10-24 17:22:59,301] WARN [cdc|task-26] [AdminClient clientId=a] Error connecting to node broker-4.acme.corp:9092 (id: 0 rack: null) (org.apache.kafka.clients.NetworkClient:1207)\n"
                  "java.net.UnknownHostException: broker-4.acme.corp")
            + rec("ERROR", 3, 200, "2026-10-24T17:23:27", "2026-10-24T17:23:27",
                  "[2026-10-24 17:23:27,434] ERROR [cdc|task-42] WorkerSourceTask{id=cdc-42} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:234)\n"
                  "org.apache.kafka.connect.errors.ConnectException: Failed to commit consumer offset\n"
                  "Caused by: org.apache.kafka.common.KafkaException: Failed to construct kafka consumer\n"
                  "Caused by: org.apache.kafka.common.config.ConfigException: No resolvable bootstrap urls given in bootstrap.servers")
            + rec("ERROR", 5, 300, "2026-10-24T17:23:28", "2026-10-24T17:23:29",
                  "[2026-10-24 17:23:28,000] ERROR [cdc|task-42|changeEvent] [Consumer clientId=c] Failed to close fetcher with a timeout(ms)=30000 (org.apache.kafka.clients.consumer.internals.ClassicKafkaConsumer:1240)\n"
                  "org.apache.kafka.common.errors.InterruptException: java.lang.InterruptedException")
            + "@@PGCFG@@|DistributedConfig||50|2026-10-24T17:01:05|\n"
            "@@PGCFGL@@|group.id = connect-cluster\n")
    with tempfile.TemporaryDirectory() as tmp:
        res = log_report.analyze(log_report.parse_records(records_file(tmp, text)))
    causes = {h["title"]: h for h in res["known_causes"]}
    dns = causes.get(log_report.DNS_TITLE)
    check("DNS: HIGH, the outage only (the startup records apart)", dns and (dns["severity"], dns["occurrences"]) == ("HIGH", 35),
          {t: (h["severity"], h["occurrences"]) for t, h in causes.items()})
    check("not a 🔌 connection failure", log_report.CONNECTION_TITLE not in causes, list(causes))
    startup = causes.get(log_report.STARTUP_CONNECTION_TITLE)
    check("🌅 one LOW cause for the DNS and connection retries of the startup",
          startup and (startup["severity"], startup["occurrences"]) == ("LOW", 7), startup)
    d = dns["dns"]
    check("window", (d["first"], d["last"], d["ended"]) == ("2026-10-24T17:22:59", "2026-10-24T17:27:04", True), d)
    check("hosts", d["hosts"] == ["broker-4.acme.corp", "broker-6.acme.corp"], d["hosts"])
    check("resolver vs JVM cache", (d["java_resolver_failures"], d["java_cached_failures"]) == (2, 30), d)
    check("clients not created", d["clients_not_created"] == 3, d)
    check("details", any(x.startswith("🧊 JVM DNS cache: 2 lookup(s)") for x in dns["details"])
          and any(x.startswith("🧱 ×3 Java client(s)") for x in dns["details"]), dns["details"])
    check("KB of No resolvable bootstrap urls", "4408266460308" in (dns.get("kb") or ""), dns.get("kb"))
    aborted = causes.get("🧹 Clients aborted while a task stopped")
    check("🧹 LOW", aborted and (aborted["severity"], aborted["occurrences"]) == ("LOW", 5), aborted)


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


def test_cluster_layout_observers_and_broker_down():
    """observers of a Multi-Region Cluster are not replicas missing from the ISR; a broker in Replicas but missing from
    kafka-log-dirs (down) does not break the HTML report"""
    import cluster_layout
    with tempfile.TemporaryDirectory() as tmp:
        describe = os.path.join(tmp, "topics.txt")
        with open(describe, "w") as fh:
            fh.write("Topic: orders\tTopicId: abc\tPartitionCount: 2\tReplicationFactor: 5\tConfigs: min.insync.replicas=2\n"
                     "\tTopic: orders\tPartition: 0\tLeader: 1\tReplicas: 1,2,3,4,5\tIsr: 1,2,3\tOffline: \tObservers: 4,5\n"
                     "\tTopic: orders\tPartition: 1\tLeader: 2\tReplicas: 2,3,1,5,4\tIsr: 2,3,1\tOffline: \tObservers: 5,4\n")
        res = cluster_layout.analyze([("topics.txt", describe)])
        check("observers: no under-replicated", res["under_replicated_count"] == 0, res["findings"])
        check("observers: no broker in no ISR", not any("in no ISR" in f["text"] for f in res["findings"]), res["findings"])
        check("observers counted", {b["id"]: b["observers"] for b in res["brokers"]} == {1: 0, 2: 0, 3: 0, 4: 2, 5: 2}, res["brokers"])
        # a sync replica out of the ISR is still under-replicated, an observer promoted into it changes nothing
        with open(describe, "w") as fh:
            fh.write("\tTopic: orders\tPartition: 0\tLeader: 1\tReplicas: 1,2,3,4\tIsr: 1,3,4\tOffline: 2\tObservers: 4\n")
        res = cluster_layout.analyze([("topics.txt", describe)])
        check("sync replica out of the ISR", res["under_replicated_count"] == 1, res)
        check("parsed without Observers", cluster_layout.parse_describe(
            "Topic: t\tPartition: 0\tLeader: 1\tReplicas: 1,2\tIsr: 1")[1][("t", 0)]["observers"] == [])
        # broker 3 is in Replicas but not in kafka-log-dirs (down)
        with open(describe, "w") as fh:
            fh.write("\tTopic: orders\tPartition: 0\tLeader: 1\tReplicas: 1,2,3\tIsr: 1,2\n")
        log_dirs = os.path.join(tmp, "log-dirs.txt")
        with open(log_dirs, "w") as fh:
            fh.write("Querying brokers for log directories information\nReceived log directory information from brokers 1,2\n"
                     + json.dumps({"version": 1, "brokers": [
                         {"broker": b, "logDirs": [{"logDir": "/var/lib/kafka", "error": None,
                                                    "partitions": [{"partition": "orders-0", "size": 1000, "offsetLag": 0, "isFuture": False}]}]}
                         for b in (1, 2)]}) + "\n")
        cl = cluster_layout.analyze([("topics.txt", describe), ("log-dirs.txt", log_dirs)])
        page = log_report.cluster_layout_html(cl)
        check("broker down: a row", "broker 3" in page and "not in kafka-log-dirs" in page, page[:300])
        check("broker down: text", "broker 3" in "\n".join(log_report.cluster_layout_text(cl)))
        # a truncated .gz is skipped, not an exception
        broken = os.path.join(tmp, "topics.txt.gz")
        with open(broken, "wb") as fh:
            fh.write(b"\x1f\x8b\x08\x00garbage")
        check("truncated gz", cluster_layout.analyze([("topics.txt.gz", broken)]) is None)


def test_broker_signal_bursts_are_not_causes():
    """🔗 a burst of request timeouts of the worker itself (a symptom) is not the cause of the next error: the stop
    30 s before it stays the cause; an ISR shrink burst can be one"""
    timeouts = "".join(f"@@PGEVT@@|request_timeout|{20 + i}|2026-11-07T10:00:{30 + i:02d}||broker 2 · Producer\n" for i in range(5))
    def first_error_after(signals):
        text = ("@@PGFILE@@|connect.log|100|1|0|2026-11-07T09:59:00|2026-11-07T10:01:00\n"
                "@@PGREC@@|ERROR|1|1|60|2026-11-07T10:00:40|2026-11-07T10:00:40\n"
                "[2026-11-07 10:00:40,000] ERROR [s3-sink|task-0] Task threw an uncaught exception (org.apache.kafka.connect.runtime.WorkerTask)\n"
                "@@PGTS@@|2026-11-07T10:00:40\n"
                "@@PGEVT@@|process_stop|10|2026-11-07T10:00:00||Kafka Connect worker stopping\n"
                + signals)
        with tempfile.TemporaryDirectory() as tmp:
            res = log_report.analyze(log_report.parse_records(records_file(tmp, text)))
        first = [ev for ev in res["timeline"] if ev["kind"] == "first_error"]
        check("one first error", len(first) == 1, res["timeline"])
        return (first[0].get("after") or {}).get("text", ""), res
    after, res = first_error_after(timeouts)
    check("the burst is on the timeline", any((ev.get("text") or "").startswith("⏱️") for ev in res["timeline"]), res["timeline"])
    check("request timeouts: not the cause", after.startswith("🛑"), after)
    shrinks = "".join(f"@@PGEVT@@|isr_shrink|{20 + i}|2026-11-07T10:00:{30 + i:02d}||broker 1 · orders-{i} (1,2,3 -> 1)\n" for i in range(5))
    after, _ = first_error_after(shrinks)
    check("ISR shrinks: the cause", after.startswith("📉"), after)


def test_describe_then_thread_dump_and_log_dirs_merge():
    """a commands output with a kafka-topics --describe then a jstack is a thread dump whose describe is still read; a
    truncated kafka-log-dirs output is parsed in linear time; two log-dirs snapshots are not added up"""
    import time
    import cluster_layout
    with tempfile.TemporaryDirectory() as tmp:
        both = os.path.join(tmp, "commands-output.txt")
        with open(both, "w") as fh:
            fh.write("$ kafka-topics --describe\n\tTopic: orders\tPartition: 0\tLeader: 1\tReplicas: 1,2\tIsr: 1,2\n"
                     "$ jstack 1\nFull thread dump OpenJDK 64-Bit Server VM (21.0.1+12-LTS mixed mode):\n\n"
                     '"main" #1 prio=5 os_prio=0 tid=0x1 nid=0x2 runnable\n   java.lang.Thread.State: RUNNABLE\n')
        check("thread dump first", bundle_triage.kind_of("commands-output.txt", both) == "thread_dump")
        check("its describe", bundle_triage.layout_kinds(both) == ["topic_describe"], bundle_triage.layout_kinds(both))
        walked = os.path.join(tmp, "walked")
        with open(walked, "w") as fh:
            fh.write(f"commands-output.txt\t{both}\n")
        of = bundle_triage.triage(walked, None, None, set())
        check("also in the triage", of["files"][0].get("also") == ["topic_describe"], of)
        # truncated: a { at each partition, no end
        cut = os.path.join(tmp, "log-dirs-cut.txt")
        with open(cut, "w") as fh:
            fh.write('{"version":1,"brokers":[{"broker":1,"logDirs":[{"logDir":"/d","error":null,"partitions":['
                     + ",".join('{"partition":"t-%d","size":1,"offsetLag":0,"isFuture":false}' % i for i in range(100000)))
        started = time.time()
        check("truncated log-dirs", cluster_layout.parse_log_dirs(open(cut).read()) is None)
        check("in linear time", time.time() - started < 2, f"{time.time() - started:.1f} s")
        snaps = []
        for n, size in enumerate((1000, 3000)):
            path = os.path.join(tmp, f"log-dirs-{n}.txt")
            with open(path, "w") as fh:
                fh.write(json.dumps({"version": 1, "brokers": [{"broker": 1, "logDirs": [{"logDir": "/d", "error": None,
                         "partitions": [{"partition": "t-0", "size": size, "offsetLag": 0, "isFuture": False}]}]}]}))
            snaps.append((f"log-dirs-{n}.txt", path))
        res = cluster_layout.analyze(snaps)
        b1 = [b for b in res["brokers"] if b["id"] == 1][0]
        check("the last snapshot, not the sum", b1["disk_bytes"] == 3000 and len(b1["log_dirs"]) == 1, b1)
        check("merge said", any("merged" in f["text"] for f in res["findings"]), res["findings"])


def test_thread_dump_labels_after_a_missing_file():
    """a dump file gone from the disk does not shift the labels of the next ones"""
    import jvm_dumps
    with tempfile.TemporaryDirectory() as tmp:
        kept = os.path.join(tmp, "b.txt")
        open(kept, "w").close()
        of = {"files": [{"label": "a.txt", "path": os.path.join(tmp, "gone.txt")}, {"label": "b.txt", "path": kept}]}
        check("label kept with its path", jvm_dumps._paths(of, ["a.txt", "b.txt"]) == [("b.txt", kept)])



def test_not_enough_replicas_single_replica_isr():
    """🧬 NotEnoughReplicas: the partitions refused with their window, most refused first, and the single in-sync replica
    diagnosis (RF=1 with min.insync.replicas=2 exposed by replicas being added); 🐢 ISR expands without any shrink are
    replicas being added, not a broker that falls behind"""
    def rec(count, line, first, last, isr, part):
        body = (f"[{first.replace('T', ' ')},000] ERROR [ReplicaManager broker=1] Error processing append operation on partition {part} (kafka.server.ReplicaManager)\n"
                f"org.apache.kafka.common.errors.NotEnoughReplicasException: The size of the current ISR Set({isr}) is insufficient to satisfy the min.isr requirement of 2 for partition {part}")
        return f"@@PGREC@@|ERROR|{count}|{line}|{line + 1}|{first}|{last}\n{body}\n@@PGTS@@|{first} {last}\n"
    text = ("@@PGFILE@@|server.log|1000|3|0|2026-10-31T22:00:00|2026-11-01T04:00:00\n"
            + rec(40, 10, "2026-10-31T22:10:50", "2026-10-31T22:12:16", "3", "orders-changelog-1")
            + rec(800, 20, "2026-11-01T00:42:39", "2026-11-01T03:59:06", "2", "events-repartition-0")
            + rec(5, 30, "2026-11-01T01:00:00", "2026-11-01T01:00:10", "2, 3", "payments-2"))
    with tempfile.TemporaryDirectory() as tmp:
        res = log_report.analyze(log_report.parse_records(records_file(tmp, text)))
    ner = next((h for h in res["known_causes"] if h["title"] == log_report.NOT_ENOUGH_REPLICAS_TITLE), None)
    check("🧬 known cause", ner and ner["occurrences"] == 845, [h["title"] for h in res["known_causes"]])
    d = ner["not_enough_replicas"]
    check("most refused partition first, with its window",
          [(p["partition"], p["occurrences"], p["first"], p["last"]) for p in d["partitions"]][:2]
          == [("events-repartition-0", 800, "2026-11-01T00:42:39", "2026-11-01T03:59:06"),
              ("orders-changelog-1", 40, "2026-10-31T22:10:50", "2026-10-31T22:12:16")], d["partitions"])
    check("duration", d["partitions"][0]["duration_seconds"] == 3 * 3600 + 16 * 60 + 27, d["partitions"][0])
    check("single in-sync replica: 2 partitions (not the one with ISR 2,3)", (d["single_replica_isr"], d["min_isr"]) == (2, 2), d)
    check("diagnosis names RF=1 / min.insync.replicas and KAFKA-15583",
          "KAFKA-15583" in ner["details"][0] and "min.insync.replicas=1" in ner["details"][0], ner["details"])
    check("partition line", ner["details"][1].startswith("🎯 events-repartition-0: ×800, 2026-11-01 00:42:39 → 03:59:06 (3 h 16 min)")
          and ner["details"][1].endswith("ISR [2] for min.isr 2"), ner["details"])
    md = log_report.ticket_markdown(res, "server.log", "ERROR")
    check("ticket section", f"### {log_report.NOT_ENOUGH_REPLICAS_TITLE}" in md, md[-800:])
    row = lambda kind, n: {"kind": kind, "who": "broker 1", "count": n, "per_hour": 70.0, "storm": True, "first": None,
                           "last": None, "reason": ""}
    expands = "\n".join(log_report.broker_signals_text({"rows": [row("isr_expand", 450)]}))
    check("expands only: replicas being added", "replicas being added" in expands and "falls behind:" not in expands, expands)
    both = "\n".join(log_report.broker_signals_text({"rows": [row("isr_expand", 450), row("isr_shrink", 400)]}))
    check("shrinks and expands: a broker that falls behind", "falls behind:" in both and "replicas being added" not in both, both)


def test_live_config_changes_in_timeline():
    """⚙️ a broker config changed live (DynamicConfigPublisher): the KafkaConfig dump logged right after is not a start,
    its changes are one timeline row per minute for all brokers (🔧 in the config section), and ♻️ the topics given
    throttled replicas are one row per burst"""
    def dump(name, line, t, changes):
        out = f"@@PGCFG@@|KafkaConfig||{line}|{t}|\n@@PGCFGL@@|leader.replication.throttled.rate = 10485760\n"
        for k, a, b in changes:
            out += f"@@PGCFGCHG@@|{line}|{t}|{k}={a}|{k}={b}\n"
        return out
    files = ""
    for b in (1, 2):
        files += (f"@@PGFILE@@|broker-{b}.log|1000|1|0|2026-11-07T10:00:00|2026-11-07T12:00:00\n"
                  "@@PGREC@@|ERROR|1|5|5|2026-11-07T11:00:00|2026-11-07T11:00:00\n"
                  "[2026-11-07 11:00:00,000] ERROR boom (x)\n@@PGTS@@|2026-11-07T11:00:00\n"
                  + dump("KafkaConfig", 10, "2026-11-07T10:00:00", [])
                  + f"@@PGEVT@@|dynamic_config|99|2026-11-07T10:42:37||broker {b} · node: leader.replication.throttled.rate -> 10485760\n"
                  + dump("KafkaConfig", 100, "2026-11-07T10:42:37", [("leader.replication.throttled.rate", "9223372036854775807", "10485760")])
                  + f"@@PGEVT@@|replica_move|200|2026-11-07T10:42:39||broker {b} · orders: 0:1,0:4\n"
                  + f"@@PGEVT@@|replica_move|201|2026-11-07T10:43:10||broker {b} · payments: 1:2,1:3\n"
                  + f"@@PGEVT@@|replica_move|300|2026-11-07T11:30:00||broker {b} · events: 2:1,2:2\n")
    with tempfile.TemporaryDirectory() as tmp:
        res = log_report.analyze(log_report.parse_records(records_file(tmp, files)))
    tl = res["timeline"]
    starts = [ev["time"] for ev in tl if ev["kind"] == "start"]
    check("the dump of the live change is not a start", starts == ["2026-11-07T10:00:00", "2026-11-07T10:00:00"], starts)
    live = [ev for ev in tl if ev["text"].startswith("⚙️ broker config changed live")]
    check("one row for both brokers, with the previous value and what it means",
          len(live) == 1 and "on 2 files: leader.replication.throttled.rate 9223372036854775807 → 10485760" in live[0]["text"]
          and "🐢 replication throttle" in live[0]["text"], [ev["text"] for ev in tl])
    moves = [ev for ev in tl if ev["text"].startswith("♻️")]
    check("two bursts of moves", [(ev["time"], ev["text"].split(":")[0]) for ev in moves]
          == [("2026-11-07T10:42:39", "♻️ replicas moved under a throttle on 2 topic(s) in 31 s"),
              ("2026-11-07T11:30:00", "♻️ replicas moved under a throttle on 1 topic(s) in 0 s")], [ev["text"] for ev in moves])
    check("🔧 in the config section", any("🔧 changed live, no restart" in x for x in log_report.config_changes_lines(res["configuration"])),
          log_report.config_changes_lines(res["configuration"]))
    text = "\n".join(log_report.timeline_text(tl, top=2))
    check("terminal: the changes further down listed", "⚙️ changes later in the timeline" in text and "♻️" in text, text)

def test_known_causes_from_past_cases():
    """causes that real support bundles got wrong (synthetic lines of the same shape): the MDS client is not Schema
    Registry, a wrong SASL mechanism is not a wrong password, an SMT that throws is not a converter, HTTP 5xx and the
    records of errors.log.enable have their cause, the more precise cause of a record comes first"""
    def causes_of(body, level="ERROR"):
        text = ("@@PGFILE@@|connect.log|100|1|0|2026-10-24T17:00:00|2026-10-24T18:00:00\n"
                f"@@PGREC@@|{level}|3|10|20|2026-10-24T17:00:01|2026-10-24T17:00:09\n{body}\n@@PGTS@@|2026-10-24T17:00:01 2026-10-24T17:00:09\n")
        with tempfile.TemporaryDirectory() as tmp:
            res = log_report.analyze(log_report.parse_records(records_file(tmp, text)))
        return [h["title"] for h in res["known_causes"]], res
    # the token login of a client to MDS (metadataServerUrls): 🪪, not 📐 Schema Registry, not the SR API key article
    got, res = causes_of("[2026-10-24 17:00:01,000] ERROR [worker] Failed to authenticate (org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule)\n"
                         "    io.confluent.security.auth.client.rest.exceptions.RestClientException: Unauthorized; error code: 401")
    check("MDS client: 🪪", "🪪 MDS / RBAC token error" in got and "📐 Schema Registry error" not in got, got)
    kb = next(h for h in res["known_causes"] if h["title"] == "🔑 Authentication failure").get("kb_articles", [])
    check("MDS 401: not the Schema Registry API key article", not any("Schema Registry" in a.get("title", "") for a in kb), kb)
    got, _ = causes_of("[2026-10-24 17:00:01,000] WARN Error while refreshing active metadata server urls (io.confluent.security.auth.client.provider.HttpBasicCredentialProvider)", "WARN")
    check("MDS urls refresh: 🪪", got == ["🪪 MDS / RBAC token error"], got)
    got, _ = causes_of("[2026-10-24 17:00:01,000] ERROR Unexpected exception sending HTTP Request. (io.confluent.security.auth.client.rest.RestClient:449)\n"
                       "    java.net.SocketTimeoutException: Read timed out")
    check("MDS RestClient logger: 🪪", "🪪 MDS / RBAC token error" in got and "📐 Schema Registry error" not in got, got)
    # the Schema Registry client keeps its cause and its article
    got, res = causes_of("[2026-10-24 17:00:01,000] ERROR [sink|task-0] failed\n"
                         "    io.confluent.kafka.schemaregistry.client.rest.exceptions.RestClientException: Unauthorized; error code: 401")
    check("SR client: 📐", "📐 Schema Registry error" in got, got)
    kb = next(h for h in res["known_causes"] if h["title"] == "🔑 Authentication failure").get("kb_articles", [])
    check("SR 401: the Schema Registry API key article", any("Schema Registry" in a.get("title", "") for a in kb), kb)
    # a SASL mechanism the listener does not enable: 🛂, not 🔑
    got, _ = causes_of("[2026-10-24 17:00:01,000] INFO [SocketServer listenerType=BROKER, nodeId=1] Failed authentication with /10.0.0.1 "
                       "(channelId=10.0.0.2:9092-10.0.0.1:50000-0) (errorMessage=Client SASL mechanism 'OAUTHBEARER' not enabled in the server, "
                       "enabled mechanisms are [PLAIN]) (org.apache.kafka.common.network.Selector)")
    check("wrong SASL mechanism: 🛂 not 🔑", "🛂 Wrong security.protocol or SASL mechanism" in got and "🔑 Authentication failure" not in got, got)
    got, _ = causes_of("[2026-10-24 17:00:01,000] INFO [SocketServer listenerType=BROKER, nodeId=1] Failed authentication with /10.0.0.1 "
                       "(channelId=x) (errorMessage=Authentication failed: Invalid username or password) (org.apache.kafka.common.network.Selector)")
    check("a wrong password stays 🔑", "🔑 Authentication failure" in got, got)
    # an SMT that throws: 🪄, not 🔀 (with the Flatten advice); a converter error stays 🔀
    got, res = causes_of("[2026-10-24 17:00:01,000] ERROR [src|task-0] Error encountered in task src-0. Executing stage 'TRANSFORMATION' with class "
                         "'org.apache.kafka.connect.transforms.Flatten$Value', where source record is = SourceRecord{...}. (org.apache.kafka.connect.runtime.errors.LogReporter)\n"
                         "    org.apache.kafka.connect.errors.DataException: Flatten transformation does not support ARRAY for record with schemas (for field a.b).")
    check("SMT: 🪄 not 🔀", "🪄 Transformation (SMT) failed" in got and "🔀 Serialization or conversion error" not in got, got)
    check("SMT: ⏭️ errors.log.enable", "⏭️ Records failed in a stage (errors.log.enable)" in got, got)
    smt = next(h for h in res["known_causes"] if h["title"] == "🪄 Transformation (SMT) failed")
    check("Flatten advice", "connect-transforms jar" in smt["advice"], smt["advice"])
    got, _ = causes_of("[2026-10-24 17:00:01,000] ERROR [sink|task-0] Error encountered in task sink-0. Executing stage 'VALUE_CONVERTER' with class "
                       "'io.confluent.connect.avro.AvroConverter'. (org.apache.kafka.connect.runtime.errors.LogReporter)\n"
                       "    org.apache.kafka.connect.errors.DataException: Converting byte[] to Kafka Connect data failed due to serialization error")
    check("converter: 🔀 not 🪄", "🔀 Serialization or conversion error" in got and "🪄 Transformation (SMT) failed" not in got, got)
    # an HTTP 504 of the endpoint
    got, _ = causes_of("[2026-10-24 17:00:01,000] ERROR [http-sink|task-0] Error while processing HTTP request with Url : https://api.example.com/x, "
                       "Status code : 504, Reason Phrase : Gateway Timeout, Response Content : , (io.confluent.connect.http.writer.HttpWriterImpl)")
    check("HTTP 5xx: 🌩️", "🌩️ HTTP 5xx from the external system" in got, got)
    # the more precise cause first: 🗝️ before 🔐 for the same records, 🧬 before 🚫
    got, _ = causes_of("[2026-10-24 17:00:01,000] ERROR [s3|task-0] task failed\n"
                       "    javax.net.ssl.SSLException: java.lang.RuntimeException: Unexpected error: java.security.InvalidAlgorithmParameterException: the trustAnchors parameter must be non-empty")
    check("🗝️ before 🔐", got.index("🗝️ Empty or unreadable truststore") < got.index("🔐 TLS handshake failure"), got)
    order = [t for _, _, t, _ in log_report.HINTS]
    check("🧬 before 🚫 and 🔑", order.index("🧬 Not enough replicas") < order.index("🔑 Authentication failure") < order.index("🚫 Authorization failure"), order[:15])
    # the host of a Netty "UnknownHostException: Failed to resolve 'db.example.com.'" is the name, not "Failed"
    m = log_report.DNS_HOST_RX.search("java.net.UnknownHostException: Failed to resolve 'db.example.com' [A(1)]")
    check("DNS host", m and next(g for g in m.groups() if g) == "db.example.com", m and m.groups())
    # broker logs named server_<date>_<host>.log
    check("server_<date>_<host>.log is a broker log", log_report.file_component("logs/server_20261101_bk01.log") == "kafka",
          log_report.file_component("logs/server_20261101_bk01.log"))


def test_sslexception_socket_error_is_not_tls():
    """an SSLException that only wraps a socket error (an LDAPS connection, already open, that times out or is reset) is
    not 🔐 TLS handshake failure, and must not become the 👉 start with of the verdict ahead of the connect timeouts; a
    real handshake failure stays 🔐"""
    def rec(level, count, line, first, last, body):
        return (f"@@PGREC@@|{level}|{count}|{line}|{line + 5}|{first}|{last}\n{body}\n@@PGTS@@|{first} {last}\n")
    ldap = "(io.confluent.security.auth.provider.ldap.LdapAuthenticateCallbackHandler)"
    text = ("@@PGFILE@@|metadata-service.log|1000|3|0|2026-10-24T17:00:00|2026-10-24T18:00:00\n"
            + rec("WARN", 6, 10, "2026-10-24T17:15:00", "2026-10-24T17:16:00",
                  f"[2026-10-24 17:15:00,000] WARN Caught exception searching for LDAP User. javax.naming.ldap.InitialLdapContext@1a2b3c4d  {ldap}\n"
                  "    javax.naming.CommunicationException: Connection timed out (Read failed) [Root exception is javax.net.ssl.SSLException: Connection timed out (Read failed)]; remaining name 'OU=Users,DC=example,DC=com'\n"
                  "    Caused by: javax.net.ssl.SSLException: Connection timed out (Read failed)\n"
                  "    Caused by: java.net.SocketException: Connection timed out (Read failed)")
            + rec("WARN", 2, 20, "2026-10-24T17:15:01", "2026-10-24T17:15:02",
                  f"[2026-10-24 17:15:01,000] WARN Caught exception searching for LDAP Group. javax.naming.ldap.InitialLdapContext@1a2b3c4d  {ldap}\n"
                  "    javax.naming.CommunicationException: Connection reset [Root exception is javax.net.ssl.SSLException: Connection reset]; remaining name 'CN=group,DC=example,DC=com'\n"
                  "    Caused by: javax.net.ssl.SSLException: Connection reset")
            + rec("ERROR", 40, 30, "2026-10-24T17:20:00", "2026-10-24T17:59:00",
                  f"[2026-10-24 17:20:00,000] ERROR Failed to obtain user DN for user1. javax.naming.ldap.InitialLdapContext@1a2b3c4d  {ldap}\n"
                  "    io.confluent.security.auth.provider.ldap.LdapException: LDAP context could not be created with provided configs\n"
                  "    Caused by: javax.naming.CommunicationException: 10.0.0.1:636 [Root exception is java.net.SocketTimeoutException: connect timed out]\n"
                  "    Caused by: java.net.SocketTimeoutException: connect timed out"))
    with tempfile.TemporaryDirectory() as tmp:
        res = log_report.analyze(log_report.parse_records(records_file(tmp, text)))
    causes = {h["title"]: h["occurrences"] for h in res["known_causes"]}
    check("no 🔐 for socket errors under an SSLException", "🔐 TLS handshake failure" not in causes, causes)
    check("the read timeout is a ⏱️", causes.get("⏱️ Timeouts", 0) >= 6, causes)
    cls, verdict = log_report.verdict(res, "ERROR/FATAL/WARN")
    check("start with 🔌", "start with 🔌 Connection failure" in verdict, verdict)
    # a real TLS failure still matches the 🔐 pattern, the socket errors under an SSLException do not
    tls = next(c for c in log_report.known_causes.KNOWN_CAUSES if c["name"] == "tls_handshake")["pattern"]
    for line, want in (("javax.net.ssl.SSLException: Unrecognized SSL message, plaintext connection?", True),
                       ("javax.net.ssl.SSLException: Received fatal alert: certificate_expired", True),
                       ("javax.net.ssl.SSLException: Tag mismatch", True),
                       ("javax.net.ssl.SSLHandshakeException: Remote host terminated the handshake", True),
                       ("Caused by: javax.net.ssl.SSLException: Connection reset", False),
                       ("Caused by: javax.net.ssl.SSLException: Read timed out", False),
                       ("Caused by: javax.net.ssl.SSLException: Broken pipe (Write failed)", False),
                       ("Caused by: javax.net.ssl.SSLException: Socket closed", False)):
        check(f"🔐 {want}: {line}", bool(re.search(tls, line, re.I)) == want, line)


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
