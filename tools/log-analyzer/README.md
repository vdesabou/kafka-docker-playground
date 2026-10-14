# log-analyzer

Samples of `playground analyze logs`, the ERROR/FATAL digest of log files, folders and bundles. The command
itself is plain bash (`scripts/cli/src/commands/analyze/logs.sh`): it de-duplicates records with an occurrence
count and collapses stack traces to their `Caused by:` chain.

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
