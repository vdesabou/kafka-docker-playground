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

import json_log_export as jle  # noqa: E402
import log_overview  # noqa: E402
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
