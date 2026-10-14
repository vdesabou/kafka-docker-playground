# xstream-analyzer

Oracle XStream CDC diagnostics report analyzer behind `playground analyze oracle-xstream-report`. Standard
library only, runs with the host `python3` (3.9+), like `tools/thread-analyzer/` and `gc-analysis/`.

## What it reads

The HTML report of `orclcdc_diag.sql`, the
[connector diagnostics script](https://docs.confluent.io/kafka-connectors/oracle-xstream-cdc-source/current/troubleshooting.html#connector-diagnostics-script)
that support asks for (`orclcdc_diag_<YYYYMMDD_HH24MI>.html`). The report is a fixed SQL*Plus HTML layout: one
`<h3>` per section (`Capture Process: Status`, `Apply: Parameters`…), each followed by its tables. Sections with
no row have no table. Older versions of the script (fewer sections) are read too.

Several reports of the same database are ordered by their generation time (the `Report generated on instance:
… at time: …` footer, or the file name) and compared.

The report is untrusted data: it is only parsed, nothing in it is executed.

## What it reports

| Section | Content |
| --- | --- |
| Header | database, role, open mode, CDB, platform, version, current SCN, overall health (🔴 CRITICAL, 🟠 DEGRADED, 🟡 AT RISK, 🟢 HEALTHY) |
| Prerequisites | ARCHIVELOG, supplemental logging (MIN / ALL), `streams_pool_size`, `pga_aggregate_target`, `MAX_SGA_SIZE` of capture and apply |
| Capture | status and error, state, latency, SGA used vs `MAX_SGA_SIZE`, SCNs (start, captured, applied, gap to the current SCN), messages captured / enqueued, redo mined, registered log files still needed, LogMiner sessions and memory |
| Outbound server | status (ATTACHED / DETACHED), LCRs sent, time since the last LCR sent, apply reader latency and spills, spill thresholds, buffered queue, streams pool, open transactions, capture rules |
| Findings | sorted by severity, each with the report section, the exact values and, when there is one, the SQL to run |
| Matched patterns | A undersized streams pool / SGA, B large or long transactions, C flow control, D outbound server detached, E LogMiner memory pressure, F overlapping captures, G database prerequisite missing, H component disabled or aborted |
| Between reports | per capture: captured SCN, messages captured, latency, restart; per outbound server: status and LCRs sent |

With `--html`, the same content as a self-contained page (no script, no external resource, every value from the
report escaped) to share in a case: findings first, then prerequisites, components, a chart of the streams pool
advice (estimated spills per pool size) and the deltas between reports.

Thresholds:

| Check | Rule |
| --- | --- |
| Capture / apply reader latency | > 60 s HIGH, > 300 s CRITICAL. INFO when the capture is `WAITING FOR REDO` (idle database), or for the apply reader when the outbound server is DETACHED |
| LogMiner memory | > 80 % HIGH, > 95 % CRITICAL |
| SGA | used > 90 % of a finite `MAX_SGA_SIZE` (SGA is allocated on demand: allocated vs used means nothing with `INFINITE`) |
| Large transaction | > 100,000 LCRs, one finding per XID (capture and apply merged) |
| Long transaction | open > 1 hour in capture or apply; database transactions > 30 minutes (from the report) |
| Open transactions | > 1,000 HIGH, > 10,000 CRITICAL |
| Spilled transactions | above `TXN_LCR_SPILL_THRESHOLD` or `TXN_AGE_SPILL_THRESHOLD`: spilled by design (pattern B, MEDIUM); below: memory pressure (pattern A, HIGH) |
| Outbound server idle | last LCR sent > 5 minutes before the report while ATTACHED; INFO when the capture has no backlog |
| Streams pool advice | spills estimated at the current size: the smallest size without spill becomes the `ALTER SYSTEM` to run |
| Capture rules | `GLOBAL` rule, or the same table / schema captured by two capture processes |

Exit codes: `0` analysis done, `2` not an `orclcdc_diag` report, `1` usage error.

## Usage

Always go through the playground CLI:

```bash
playground analyze oracle-xstream-report --sample synthetic_failures --html                   # try it on a shipped sample
playground analyze oracle-xstream-report -s large_transaction -s detached                      # compare two samples
playground analyze oracle-xstream-report -f orclcdc_diag_20261013_0912.html                   # customer report
playground analyze oracle-xstream-report -f day1.html -f day2.html --html                      # what moved between two reports, as HTML
playground analyze oracle-xstream-report -c oracle                                             # running example: generate the report, then analyze
playground analyze oracle-xstream-report -f orclcdc_diag_20261013_0912.html --json             # for agents and scripts
```

`--sample <name>` (repeatable) picks `samples/orclcdc_diag_<name>.html` (names below), from any directory.
The HTML report goes to `--output-dir` as `<last report>-xstream-report.html`.

With `--container`, the report is generated with `playground connector oracle-cdc-xstream generate-report` and
kept in `--output-dir` (default `./xstream-analysis-output`) as `orclcdc_diag_<date>.html`, so successive runs can
be compared.

## Samples

| File (`--sample` name) | Content |
| --- | --- |
| `samples/orclcdc_diag_healthy.html` | `connect/connect-cdc-xstream-oracle19-source`, connector running, idle database |
| `samples/orclcdc_diag_large_transaction.html` | same, with an uncommitted 150,000-row insert (large transaction, spilled by design) |
| `samples/orclcdc_diag_detached.html` | same, after the connector was deleted: outbound server DETACHED, capture restarted |
| `samples/orclcdc_diag_older_script_version.html` | report of an older version of `orclcdc_diag.sql` (no Database Version, Downstream Capture, Events sections) |
| `samples/orclcdc_diag_synthetic_failures.html` | built from the healthy sample by `samples/make_synthetic_failures.py`: NOARCHIVELOG, no supplemental logging, capture ABORTED with ORA-01291, flow control, LogMiner memory at 97 %, streams pool advice with spills, alerts and events |

To get a new reference report after `orclcdc_diag.sql` changes, run the example and
`playground analyze oracle-xstream-report -c oracle`.
