#!/usr/bin/env python3
"""
The 🔥 Log analysis banner of a CFK support bundle report.

playground analyze logs also digests the pod and operator logs of a CFK support bundle with the regular log pipeline
(tools/log-analyzer/log_report.py): root causes, incident timeline, connector cards, plugin versions, restarts and
rebalances, known bugs fixed later, tasks by worker, data to request, a summary for a ticket. Once that log report is
written, this script puts its key lines at the top of the report of the bundle (the Kubernetes view: pods, custom
resources, events, versions, recent changes), with a link to it. The CFK report has a marker for it
(<!--pg-log-analysis--> after the verdict, cfk-analysis/html_report.py); stdlib only, run on the host.

    log_banner.py --report <cfk report.html> --logs-json <analyze logs --json> --log-report <log report.html>
"""

import argparse
import html
import json
import os
import sys
import urllib.parse

MARKER = "<!--pg-log-analysis-->"


def esc(s) -> str:
    return html.escape(str(s), quote=True)


def lines_of(logs: dict) -> list:
    """the key lines of the log analysis: what the bundle report does not have"""
    out = []
    for h in (logs.get("known_causes") or [])[:4]:
        first = (h.get("first") or {}).get("timestamp") or ""
        out.append(f"🧠 {h['title']} ×{h['occurrences']:,}" + (f" (first {first.replace('T', ' ')})" if first else ""))
    for b in (logs.get("fixed_bugs") or [])[:3]:
        for c in b.get("connectors") or []:
            if c.get("verdict") == "affected":
                out.append(f"🩹 {c['connector']} runs {c['version']}: {b['title'][2:].strip()} ({b['ref']}), upgrade to {c['upgrade_to']} or later")
    for c in ((logs.get("task_workers") or {}).get("connectors") or []):
        if c.get("only_on"):
            out.append(f"🎯 {c['connector']}: every error comes from {c['only_on']}, its tasks also ran on other workers")
    bursts = [ev for ev in logs.get("timeline") or [] if ev.get("effects")]
    for ev in bursts[:2]:
        out.append(f"💥 {ev['effects']['occurrences']:,} errors in the {ev['effects']['seconds']} s after {ev['text']} "
                   f"({ev['time'].replace('T', ' ')})")
    linked = [ev for ev in logs.get("timeline") or [] if ev.get("after")]
    if linked:
        ev = linked[0]
        out.append(f"🔗 {ev['time'].replace('T', ' ')} first error right after {ev['after']['text']}")
    return out


def banner(logs: dict, href: str) -> str:
    s = logs.get("summary") or {}
    conns = logs.get("connectors") or []
    head = (f"{s.get('occurrences', 0):,} occurrence(s) of {s.get('distinct', 0):,} distinct record(s) in "
            f"{s.get('files_with_findings', 0)} of {s.get('files_scanned', 0)} log file(s)"
            + (f", {len(conns)} connector(s)" if conns else ""))
    items = "".join(f"<li>{esc(x)}</li>" for x in lines_of(logs))
    asks = len(logs.get("data_to_request") or [])
    return (
        "<section class='pg-log-analysis' style='border:1px solid #fdba74;border-left:6px solid #ea580c;border-radius:10px;"
        "padding:12px 16px;margin:14px 0'>"
        f"<h2 style='margin:0 0 6px;font-size:1.05rem'>🔥 Log analysis of the pod logs: {esc(head)}</h2>"
        f"<p style='margin:0 0 6px'><a href='{esc(href)}' target='_blank' rel='noopener'><strong>Open the log report</strong></a> "
        "(the regular <code>playground analyze logs</code> report of the same pod and operator logs): every distinct error with "
        "its exception chain and root cause, the incident timeline, a card per connector with its plugin version, restarts "
        "and rebalances, known bugs fixed in a later version, tasks by worker, "
        + (f"{asks} item(s) of data to request, " if asks else "")
        + "and a summary for a ticket. This report has the Kubernetes view: pods, custom resources, events, versions, recent "
        "changes.</p>"
        + (f"<ul style='margin:4px 0 0 18px;padding:0'>{items}</ul>" if items else "")
        + "</section>")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--report", required=True, action="append", help="HTML report of a CFK bundle (repeatable)")
    ap.add_argument("--logs-json", required=True, help="JSON of playground analyze logs on the same logs")
    ap.add_argument("--log-report", required=True, help="the HTML log report, linked from the banner")
    args = ap.parse_args()
    try:
        with open(args.logs_json, encoding="utf-8") as fh:
            logs = json.load(fh)
    except (OSError, ValueError) as ex:
        print(f"⚠️ log banner: cannot read {args.logs_json}: {ex}", file=sys.stderr)
        return 1
    rc = 0
    for report in args.report:
        try:
            with open(report, encoding="utf-8") as fh:
                page = fh.read()
        except OSError as ex:
            print(f"⚠️ log banner: cannot read {report}: {ex}", file=sys.stderr)
            rc = 1
            continue
        if MARKER not in page:
            continue
        href = urllib.parse.quote(os.path.relpath(args.log_report, os.path.dirname(os.path.abspath(report))))
        with open(report, "w", encoding="utf-8") as fh:
            fh.write(page.replace(MARKER, banner(logs, href), 1))
    return rc


if __name__ == "__main__":
    sys.exit(main())
