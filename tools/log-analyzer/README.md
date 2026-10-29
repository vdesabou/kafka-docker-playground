# log-analyzer

Samples and HTML report of `playground analyze logs`, the ERROR/FATAL digest of log files, folders and bundles. The
digest itself is plain bash (`scripts/cli/src/commands/analyze/logs.sh`, `summarize_log_errors` in
`scripts/cli/src/lib/cli_function.sh`): it de-duplicates records with an occurrence count and collapses stack traces
to their `Caused by:` chain.

## HTML report and JSON

With `PG_LOG_DIGEST_RECORDS_FILE` set, `summarize_log_errors` also appends every distinct record to that file.
`log_report.py` reads it and writes the HTML report (`--html-out`) or prints the analysis (`--json`): known causes
(task killed, with one line per distinct exception chain of the killed tasks, authentication, TLS, unknown magic byte,
`OutOfMemoryError`…, each pointing at its earliest occurrence; the list is shared with the CFK analyzer, in
`tools/report-common/known_causes.py`), occurrences over time, root causes
(deepest exception of each record) and every record (with a 📋 Show context block: the raw lines around its first
occurrence, from the `@@PGCTX@@` lines of the records file), with a level and connector filter (connector taken from the
`[connector|task-0]` / `[connector|worker]` context of the line, also with a scope like `[connector|task-0|redoLog]`, or `WorkerSinkTask{id=connector-0}`). `tools/connector-diagnose/diagnose_report.py` imports it for the
errors section of the `playground connector diagnose` report. `get-ci-result --logs`, `container logs --errors --html`
and `container display-error-all --html` write the same report (`--unit script|container`, `--section` for the last
lines of a failed CI script, `--link` for the issue and the job).

```bash
playground analyze logs --sample support_bundle --output-dir /tmp/log-reports   # support_bundle-log-report.html
playground analyze logs --sample connect_task_failure --json 2>/dev/null | jq '.known_causes[].title'
```

## Samples

Real logs of `connect/connect-cdc-xstream-oracle19-source`, CP 8.3.2, Oracle XStream CDC connector 1.6.0:

| `--sample` | File | Content |
| --- | --- | --- |
| `connect_task_failure` | `samples/connect-oracle-xstream-task-failure.log` | 6 minutes of Connect worker log: a connector created with a wrong password (`ORA-01017`), one with an unknown outbound server, then a task failing after the outbound server was stopped with `DBMS_XSTREAM_ADM.STOP_OUTBOUND` |
| `support_bundle` | `samples/support-bundle.zip` | that log and the broker log of the same period (gzipped), as a customer would attach them: shows the archive extraction and that only files with findings are listed |

Passwords are masked by Connect (`password=********`).

```bash
playground analyze logs --sample connect_task_failure
playground analyze logs --sample support_bundle --include-warnings
```

The repository ignores `*.log`: `.gitignore` keeps `samples/*.log`.
