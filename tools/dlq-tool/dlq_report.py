#!/usr/bin/env python3
"""
HTML report of playground topic dlq inspect: the records of a dead letter queue grouped by connector, stage and
exception (decoded from the __connect.errors.* headers by DlqTool.java), with the known causes, when they arrived,
where they came from, a sample value of each group and the commands to replay them.

Inputs, written by scripts/cli/src/commands/topic/dlq/inspect.sh:
  --groups   groups.json  (one group per connector, stage, exception and message, most frequent first)
  --records  records.json (one DLQ_RECORD per line: partition, offset, timestamp, errors...)
  --summary  the DLQ_SUMMARY json of DlqTool (total, read, skipped_filter)
"""

import argparse
import json
import os
import re
import sys
from collections import Counter
from datetime import datetime
from typing import List, Tuple

# no __pycache__ left in the repository
sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "report-common"))
sys.path.insert(0, os.path.join(HERE, "..", "log-analyzer"))
import report_html as rh  # noqa: E402
from log_report import HINTS  # noqa: E402


def read_json_lines(path: str) -> List[dict]:
    out = []
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                line = line.strip()
                if line:
                    try:
                        out.append(json.loads(line))
                    except ValueError:
                        pass
    except OSError:
        pass
    return out


def short_class(name) -> str:
    return (name or "").split(".")[-1]


def group_text(g: dict) -> str:
    return f"{g.get('exception') or ''} {g.get('message') or ''} {g.get('root_cause') or ''}"


def group_title(g: dict) -> str:
    if not g.get("exception"):
        return "no __connect.errors.* headers"
    cause = g.get("root_cause") or f"{g['exception']}: {g.get('message') or ''}"
    return cause


def findings(groups: List[dict], summary: dict, grep: str, max_messages: str) -> List[dict]:
    res = []
    matched = summary["read"] - summary["skipped_filter"]
    no_headers = sum(g["count"] for g in groups if not g.get("exception"))
    if no_headers:
        res.append({"severity": "HIGH", "text": f"🏷️ {no_headers} record(s) have no __connect.errors.* headers, so their error is unknown: set "
                                                 "\"errors.deadletterqueue.context.headers.enable\": \"true\" on the connector, and look at "
                                                 "the connect logs (errors.log.enable=true)"})
    explained = set()
    for pattern, severity, title, advice in HINTS:
        rx = re.compile(pattern)
        hit = [g for g in groups if g.get("exception") and rx.search(group_text(g))]
        if hit:
            explained.update(id(g) for g in hit)
            n = sum(g["count"] for g in hit)
            res.append({"severity": severity, "text": f"{title}: {n} record(s) in {len(hit)} group(s): {advice}"})
    for g in groups:
        if id(g) in explained or not g.get("exception"):
            continue
        stage = f" at stage {g['stage']}" if g.get("stage") else ""
        res.append({"severity": "MEDIUM", "text": f"☠️ {g['count']} record(s){stage}: {group_title(g)[:300]}"})
    if summary["read"] < summary["total"]:
        res.append({"severity": "INFO", "text": f"✂️ Only the first {summary['read']} records of {summary['total']} were read "
                                                f"(--max-messages {max_messages}): raise it to see them all"})
    if grep:
        res.append({"severity": "INFO", "text": f"🔎 {matched} of {summary['read']} records match --grep {grep}"})
    return rh.sort_findings(res)


def verdict(groups: List[dict], summary: dict, topic: str) -> Tuple[str, str]:
    matched = summary["read"] - summary["skipped_filter"]
    if not summary["total"]:
        return "ok", f"✅ Dead letter queue {topic} is empty."
    if not matched:
        return "ok", f"✅ No record of {topic} matches the filter."
    top = groups[0]
    return "danger", (f"☠️ {matched} record(s) in {len(groups)} group(s) in {topic}: start with the {top['count']} record(s) "
                      f"of {group_title(top)[:160].rstrip('.')}")


def group_html(i: int, g: dict, topic: str) -> str:
    badges = " ".join(x for x in [
        rh.badge(f"×{g['count']}", "error"),
        rh.badge(g["connector"], "mine") if g.get("connector") else "",
        rh.badge(f"stage {g['stage']}", "warn") if g.get("stage") else "",
    ] if x)
    rows = []
    if g.get("class"):
        rows.append(("Failing class", f"<span class='mono'>{rh.e(g['class'])}</span>"))
    if g.get("exception"):
        rows.append(("Exception", f"<span class='mono'>{rh.e(g['exception'])}</span>"))
        rows.append(("Message", f"<pre>{rh.log_html(g.get('message') or '')}</pre>"))
    if g.get("root_cause") and g["root_cause"] != f"{g.get('exception') or ''}: {g.get('message') or ''}":
        rows.append(("Root cause", f"<pre>{rh.log_html(g['root_cause'])}</pre>"))
    if g.get("original_topics"):
        rows.append(("Original records", "<br>".join(
            f"<span class='mono'>{rh.e(o['topic'])}</span> partition {o['partition']} offsets {o['first_offset']}..{o['last_offset']} ({o['count']})"
            for o in g["original_topics"])))
    if g.get("dlq_offsets"):
        rows.append(("In the DLQ", "<br>".join(f"partition {o['partition']} offsets {o['first']}..{o['last']}" for o in g["dlq_offsets"])))
    if g.get("sample_value") is not None:
        rows.append(("Sample value", f"<pre>{rh.e(g['sample_value'])}</pre><span class='legend'>first 200 bytes, non printable "
                                     "characters (binary Avro / Protobuf, magic byte) as '.'</span>"))
    grep = re.escape(short_class(g.get("exception"))) if g.get("exception") else ""
    replay = f"playground topic dlq replay --topic {topic}" + (f" --grep \"{grep}\"" if grep else "") + " --dry-run"
    rows.append(("Replay", f"<pre>{rh.e(replay)}</pre>"))
    table = "".join(f"<tr><td style='white-space:nowrap;width:140px'><b>{k}</b></td><td>{v}</td></tr>" for k, v in rows)
    return (f"<details{' open' if i < 2 else ''}><summary>{badges} <span class='mono'>{rh.e(group_title(g)[:200])}</span></summary>"
            f"<table>{table}</table></details>")


def html_report(groups: List[dict], records: List[dict], summary: dict, topic: str, grep: str, max_messages: str) -> str:
    matched = summary["read"] - summary["skipped_filter"]
    connectors = sorted({g["connector"] for g in groups if g.get("connector")})
    originals = sorted({o["topic"] for g in groups for o in g.get("original_topics") or []})
    stages = Counter()
    for g in groups:
        stages[g.get("stage") or "unknown"] += g["count"]
    kpis = rh.kpis_html([
        rh.kpi("☠️ Records in the DLQ", summary["total"], f"{summary['read']} read", "danger" if summary["total"] else "ok"),
        rh.kpi("🔎 Matching", matched, f"--grep {grep}" if grep else "no filter"),
        rh.kpi("🧬 Groups", len(groups), "connector + stage + exception"),
        rh.kpi("🧩 Connectors", len(connectors), ", ".join(connectors)[:60] or "-"),
        rh.kpi("📍 Original topics", len(originals), ", ".join(originals)[:60] or "-"),
        rh.kpi("🏭 Stages", len(stages), ", ".join(f"{k} ({v})" for k, v in stages.most_common(3))),
    ])
    points = []
    for r in records:
        ts = r.get("timestamp")
        if isinstance(ts, (int, float)) and ts > 0:
            points.append((datetime.fromtimestamp(ts / 1000), "records"))
    tl = rh.time_bins(points, ("records",))
    bars = [(f"{g.get('stage') or '?'}: {short_class(g.get('exception')) or 'no headers'}", g["count"],
             f"{g['count']} record(s): {group_title(g)}") for g in groups[:10]]
    charts = rh.charts_grid([
        ("📈 When they arrived in the DLQ (record timestamps)", rh.svg_time_columns(tl, [("records", "records", rh.SERIES_1)]) if tl else ""),
        ("🔝 Groups (records)", rh.svg_hbars(bars)),
    ])
    body = [rh.verdict_html(*verdict(groups, summary, topic)), kpis, rh.findings_html(findings(groups, summary, grep, max_messages)),
            charts]
    if groups:
        body.append(rh.card(f"🧬 Groups ({len(groups)}), most frequent first", "".join(group_html(i, g, topic) for i, g in enumerate(groups))))
    body.append(rh.card("🔁 Once the cause is fixed", "<pre>" + rh.e(
        f"playground topic dlq replay --topic {topic} --dry-run      # what would be replayed, and where\n"
        f"playground topic dlq replay --topic {topic}                # to the original topics (errors headers stripped)\n"
        f"playground topic dlq replay --topic {topic} --to <topic>   # or to another topic") + "</pre>"
        "<p class='legend'>Records are re-produced byte for byte; the DLQ itself is never truncated.</p>"))
    meta = [f"☠️ {rh.e(topic)}", f"{summary['read']} of {summary['total']} records read"]
    if grep:
        meta.append(f"--grep {rh.e(grep)}")
    return rh.page(f"Dead letter queue report — {topic}", "☠️ Dead Letter Queue", meta, "".join(body),
                   "🛠️ Generated by playground topic dlq inspect (self-contained, no external resource). Errors come from the "
                   "__connect.errors.* headers (errors.deadletterqueue.context.headers.enable=true).")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--groups", required=True)
    ap.add_argument("--records", required=True)
    ap.add_argument("--summary", required=True, help="DLQ_SUMMARY json")
    ap.add_argument("--topic", required=True)
    ap.add_argument("--grep", default="")
    ap.add_argument("--max-messages", default="")
    ap.add_argument("--html-out", required=True)
    args = ap.parse_args()
    with open(args.groups, encoding="utf-8") as fh:
        groups = json.load(fh)
    summary = json.loads(args.summary)
    with open(args.html_out, "w", encoding="utf-8") as fh:
        fh.write(html_report(groups, read_json_lines(args.records), summary, args.topic, args.grep, args.max_messages))
    return 0


if __name__ == "__main__":
    sys.exit(main())
