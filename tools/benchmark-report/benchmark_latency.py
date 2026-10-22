#!/usr/bin/env python3
"""End-to-end latency of a source connector, for 'playground connector benchmark --mode steady'.

Reads the records written to the topics of the connector during the measure ('playground topic consume --json',
one record per line), and computes for each one: kafka record timestamp - timestamp of the change in the source system
(a field of the value).

    benchmark_latency.py --records <file.jsonl>... --from-ms <ms> --to-ms <ms> [--field <path>] [--hint <field>]
                         --csv-out <latencies.csv> --json-out <summary.json>

Field: --field (a dotted path, e.g. after.create_ts), otherwise the first that is found in the records of
- source.ts_ms of a CDC envelope (debezium, when the unwrap smt is not used): commit time in the database
- __source_ts_ms (debezium unwrap smt with add.fields=source.ts_ms)
- --hint (BENCHMARK_LATENCY_FIELD printed by the load: create_ts...), then after.<hint>
- wallTime, then clusterTime (mongodb change stream events)
Keys are matched case insensitively (oracle columns are upper case), avro unions ({"long": 1}, {"<record name>": {...}})
are unwrapped. Values: epoch in s, ms, us or ns, ISO-8601 strings, mongodb extended json ($date, $timestamp).

The summary json is {"enabled": true, field, field_source, records, p50_ms, p95_ms, p99_ms, max_ms, min_ms, mean_ms,
negative, unparsable, warnings, csv}, or {"enabled": false, reason} when no latency could be computed.
"""
import argparse
import csv
import json
import math
import sys
from datetime import datetime, timezone

sys.dont_write_bytecode = True

AUTO_FIELDS = ["__source_ts_ms"]
MONGO_FIELDS = ["wallTime", "clusterTime"]
# epoch values below this are not timestamps of the last decades (a date in days, an integer column)
MIN_EPOCH_S = 1e8


def lookup(node, key):
    """node[key], case insensitive, through avro unions (a dict with a single key wrapping the value)"""
    for _ in range(3):
        if not isinstance(node, dict):
            return None
        if key in node:
            return node[key]
        lower = key.lower()
        for k, v in node.items():
            if k.lower() == lower:
                return v
        if len(node) != 1:
            return None
        node = next(iter(node.values()))
    return None


def resolve(value, path):
    node = value
    for key in path.split("."):
        node = lookup(node, key)
        if node is None:
            return None
    return node


def to_epoch_ms(value):
    """epoch ms of a timestamp value, None when it is not one"""
    # avro union, mongodb extended json
    for _ in range(3):
        if not isinstance(value, dict):
            break
        if "$timestamp" in value and isinstance(value["$timestamp"], dict):
            value = value["$timestamp"].get("t")
            break
        if "$date" in value:
            value = value["$date"]
            continue
        if "$numberLong" in value:
            value = value["$numberLong"]
            continue
        if len(value) == 1:
            value = next(iter(value.values()))
            continue
        return None
    if isinstance(value, bool) or value is None:
        return None
    if isinstance(value, str):
        text = value.strip()
        try:
            value = float(text)
        except ValueError:
            return iso_to_ms(text)
    if not isinstance(value, (int, float)) or math.isnan(value):
        return None
    n = float(value)
    if n >= 1e17:
        return n / 1e6
    if n >= 1e14:
        return n / 1e3
    if n >= 1e11:
        return n
    if n >= MIN_EPOCH_S:
        return n * 1e3
    return None


def iso_to_ms(text):
    text = text.replace("Z", "+00:00").replace(" ", "T", 1)
    # fromisoformat takes at most 6 digits of fraction before python 3.11
    if "." in text:
        head, _, rest = text.partition(".")
        digits = ""
        while rest and rest[0].isdigit():
            digits, rest = digits + rest[0], rest[1:]
        text = head + "." + (digits + "000000")[:6] + rest
    try:
        d = datetime.fromisoformat(text)
    except ValueError:
        return None
    if d.tzinfo is None:
        d = d.replace(tzinfo=timezone.utc)
    return d.timestamp() * 1000


def candidates(value, field, hint):
    if field:
        return [(field, "--latency-field")]
    out = []
    source = lookup(value, "source") if isinstance(value, dict) else None
    if isinstance(source, dict) and lookup(source, "ts_ms") is not None and lookup(value, "op") is not None:
        out.append(("source.ts_ms", "cdc envelope"))
    out += [(f, "auto") for f in AUTO_FIELDS]
    if hint:
        out += [(hint, "load"), ("after." + hint, "load")]
    out += [(f, "mongodb change event") for f in MONGO_FIELDS]
    return out


def choose_field(records, field, hint):
    """first candidate field that gives a timestamp in most of the first records"""
    probe = [r for r in records[:200] if isinstance(r.get("value"), dict)]
    if not probe:
        return None, None
    for path, origin in candidates(probe[0]["value"], field, hint):
        ok = sum(1 for r in probe if to_epoch_ms(resolve(r["value"], path)) is not None)
        if ok >= max(1, len(probe) // 2):
            return path, origin
    return None, None


def percentile(sorted_values, p):
    if not sorted_values:
        return None
    k = (len(sorted_values) - 1) * p / 100
    f = int(k)
    c = min(f + 1, len(sorted_values) - 1)
    return sorted_values[f] + (sorted_values[c] - sorted_values[f]) * (k - f)


def stats(latencies):
    s = sorted(latencies)
    return {"records": len(s), "p50_ms": percentile(s, 50), "p95_ms": percentile(s, 95), "p99_ms": percentile(s, 99),
            "max_ms": s[-1] if s else None, "min_ms": s[0] if s else None, "mean_ms": sum(s) / len(s) if s else None}


def read_records(paths):
    records, seen = [], set()
    for path in paths:
        with open(path, errors="replace") as f:
            for line in f:
                line = line.strip()
                if not line.startswith("{"):
                    continue
                try:
                    record = json.loads(line)
                except ValueError:
                    continue
                if not isinstance(record, dict) or record.get("timestamp") is None:
                    continue
                # the slices of the measure can overlap
                key = (record.get("topic"), record.get("partition"), record.get("offset"))
                if key in seen:
                    continue
                seen.add(key)
                records.append(record)
    return records


def measure(records, from_ms, to_ms, field, hint):
    in_window = [r for r in records if from_ms <= r["timestamp"] <= to_ms]
    if not in_window:
        return {"enabled": False, "reason": "no record written to the topics during the measure could be read"}, []
    path, origin = choose_field(in_window, field, hint)
    if path is None:
        if not any(isinstance(r.get("value"), dict) for r in in_window):
            reason = "the values of the records are not json, avro, protobuf or json schema"
        elif field:
            reason = "field " + field + " (--latency-field) is not a timestamp in the records"
        else:
            reason = "no timestamp field found in the records" + (" (" + hint + " from the load)" if hint else "") + ": use --latency-field <path>"
        return {"enabled": False, "reason": reason}, []
    rows, unparsable, whole_seconds = [], 0, 0
    for r in in_window:
        source_ms = to_epoch_ms(resolve(r.get("value"), path)) if isinstance(r.get("value"), dict) else None
        if source_ms is None:
            unparsable += 1
            continue
        if source_ms % 1000 == 0:
            whole_seconds += 1
        rows.append({"elapsed_s": round((r["timestamp"] - from_ms) / 1000, 3), "kafka_ts_ms": r["timestamp"], "topic": r.get("topic"),
                     "partition": r.get("partition"), "offset": r.get("offset"), "latency_ms": round(r["timestamp"] - source_ms, 1)})
    rows.sort(key=lambda x: x["kafka_ts_ms"])
    latencies = [x["latency_ms"] for x in rows]
    summary = {"enabled": True, "field": path, "field_source": origin, "read": len(records), **stats(latencies),
               "negative": sum(1 for v in latencies if v < 0), "unparsable": unparsable}
    warnings = []
    if summary["negative"]:
        warnings.append(f"end-to-end latency: {summary['negative']} record(s) with a negative latency, the clocks of the source system and of the connect worker (or the broker) are not in sync")
    if unparsable:
        warnings.append(f"end-to-end latency: {unparsable} record(s) without a timestamp in {path} were skipped")
    if latencies and sum(1 for v in latencies if v == 0) >= 0.9 * len(latencies):
        warnings.append(f"end-to-end latency: the kafka timestamp of the records is {path} itself (latency 0 ms): the connector sets the record timestamp from the source, use --latency-field with another field, or a topic with message.timestamp.type=LogAppendTime")
    elif rows and whole_seconds == len(rows):
        warnings.append(f"end-to-end latency: {path} has a precision of one second, the latencies are known within ±1 s (use a column with milliseconds, e.g. TIMESTAMP(3))")
    summary["warnings"] = warnings
    return summary, rows


def buckets(rows, step_s):
    """p50 / p95 / p99 per <step_s> of the measure"""
    out, cur, start = [], [], None
    for row in rows:
        b = int(row["elapsed_s"] // step_s)
        if start is not None and b != start:
            out.append(bucket(start, step_s, cur))
            cur = []
        start = b
        cur.append(row["latency_ms"])
    if cur:
        out.append(bucket(start, step_s, cur))
    return out


def bucket(index, step_s, values):
    s = sorted(values)
    return {"elapsed": round((index + 0.5) * step_s, 1), "n": len(s), "p50": percentile(s, 50), "p95": percentile(s, 95), "p99": percentile(s, 99)}


def histogram(latencies, p95):
    """bins up to p95 x 2, the slower records in one last "tail" bin"""
    if not latencies:
        return []
    lo, hi = min(min(latencies), 0), max(latencies)
    tail = hi > 2 * p95 > 0
    top = 2 * p95 if tail else hi
    raw = (top - lo) / 20 or 1
    p = 10 ** math.floor(math.log10(raw))
    step = next(m * p for m in (1, 2, 5, 10) if m * p >= raw)
    start = math.floor(lo / step) * step
    nb = max(1, math.ceil((top - start) / step + 1e-9))
    bins = [{"from": start + i * step, "to": start + (i + 1) * step, "n": 0} for i in range(nb)]
    if tail:
        bins.append({"from": start + nb * step, "to": hi, "n": 0, "tail": True})
    for v in latencies:
        i = int((v - start) // step)
        bins[min(max(i, 0), len(bins) - 1)]["n"] += 1
    return bins


def load_csv(path):
    rows = []
    with open(path, newline="") as f:
        for row in csv.DictReader(f):
            try:
                rows.append({"elapsed_s": float(row["elapsed_s"]), "kafka_ts_ms": int(float(row["kafka_ts_ms"])), "topic": row["topic"],
                             "partition": int(row["partition"]), "offset": int(row["offset"]), "latency_ms": float(row["latency_ms"])})
            except (KeyError, TypeError, ValueError):
                continue
    return rows


def report_payload(summary, step_s=5, offset_s=0):
    """what the html report of the benchmark shows: percentiles over time, histogram, slowest records; offset_s moves the
    times from the start of the measure to the time axis of the samples (from the start of the benchmark)"""
    try:
        rows = load_csv(summary["csv"])
    except (KeyError, OSError):
        return None
    if not rows:
        return None
    latencies = [r["latency_ms"] for r in rows]
    s = sorted(latencies)
    duration = rows[-1]["elapsed_s"]
    # one point per sample interval of the benchmark, at most about 60 over the measure
    step = max(1, step_s, math.ceil(duration / 60))
    out = buckets(rows, step)
    for b in out:
        b["elapsed"] = round(b["elapsed"] + offset_s, 1)
    slowest = sorted(rows, key=lambda r: -r["latency_ms"])[:10]
    for r in slowest:
        r["elapsed_s"] = round(r["elapsed_s"] + offset_s, 1)
    return {"buckets": out, "bucket_s": step, "histogram": histogram(latencies, percentile(s, 95)), "slowest": slowest}


def main():
    parser = argparse.ArgumentParser(description="end-to-end latency of a source connector during a benchmark")
    parser.add_argument("--records", nargs="+", required=True, help="output of playground topic consume --json")
    parser.add_argument("--from-ms", type=int, required=True)
    parser.add_argument("--to-ms", type=int, required=True)
    parser.add_argument("--field", help="dotted path of the timestamp field in the value")
    parser.add_argument("--hint", help="timestamp field given by the load (BENCHMARK_LATENCY_FIELD)")
    parser.add_argument("--csv-out", required=True)
    parser.add_argument("--json-out", required=True)
    args = parser.parse_args()
    summary, rows = measure(read_records(args.records), args.from_ms, args.to_ms, args.field, args.hint)
    if summary["enabled"]:
        with open(args.csv_out, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=["elapsed_s", "kafka_ts_ms", "topic", "partition", "offset", "latency_ms"])
            writer.writeheader()
            writer.writerows(rows)
        summary["csv"] = args.csv_out
        for key in ("p50_ms", "p95_ms", "p99_ms", "max_ms", "min_ms", "mean_ms"):
            summary[key] = round(summary[key], 1)
    with open(args.json_out, "w") as f:
        json.dump(summary, f)
    if summary["enabled"]:
        print(f"p50 {summary['p50_ms']:,.0f} ms  p95 {summary['p95_ms']:,.0f} ms  p99 {summary['p99_ms']:,.0f} ms  max {summary['max_ms']:,.0f} ms "
              f"({summary['records']:,} records, {summary['field']})")
    else:
        print(summary["reason"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
