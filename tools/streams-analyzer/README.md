# streams-analyzer

Kafka Streams view of log files, from the lines the Kafka Streams library itself logs at INFO: any application, any
Kafka Streams version since 3.0, no JMX and no code in the application.

| Used by | Input |
| --- | --- |
| `playground streams status` | the `docker logs` of the Streams containers (`streams`, `streams2`, `streams3` of `other/kafka-streams`, or `--container`), plus the consumer group of each application (state, members, lag) |
| `playground analyze logs` | the files of a bundle that contain `stream-client [` or `stream-thread [`: a 🌊 Kafka Streams section in the terminal, the HTML report (`log_report.py --html-section`) and `--json` (`kafka_streams`) |

`streams_report.py` parses, `streams_html.py` renders (shared look of `tools/report-common/report_html.py`): KPI tiles,
findings, the state of each instance over time (restarts and time without logs, a marker on each Kafka Streams error),
📈 the Kafka Streams errors and the rebalances over time (zoomable chart of `time_chart`), the instances, the task
assignment (task × instance). Each error keeps its occurrences (time, instance; 1000 at most) in the JSON.

## What is read

| Line of the Kafka Streams library | Gives |
| --- | --- |
| `stream-client [<application.id>-<process UUID>] State transition from REBALANCING to RUNNING` | state of the instance, since when, rebalances, time in REBALANCING, the timeline |
| `stream-thread [...-StreamThread-1] State transition from PARTITIONS_ASSIGNED to RUNNING` | state of each thread |
| `stream-thread [...] Handle new assignment with:` + `New active tasks: [...]` / `New standby tasks: [...]` | the full assignment of each thread |
| `task [1_5] Restored and ready to run` | an active task restored: the others of the last assignment are "not restored yet" |
| `End offset for changelog <p> initialized as N`, `Restoration in progress for …`, `Finished restoring changelog <p> to store <s> with a total number of N records` | changelog partitions being restored, records restored |
| `stream-client [...] Kafka Streams version: X` | the version, and a restart when it is logged again (the process UUID, kept in `state.dir`, often survives a restart) |
| `TaskMigratedException`, `Detected that the thread is being fenced`, `Exception caught during Deserialization`, `Error encountered sending record`, `MissingSourceTopicException`, `Topics not co-partitioned`, `Failed to lock the state directory`, `RocksDBException`, `Encountered the following exception during processing`… | known errors, counted once per log record, attributed to the application of the line (or the last one seen in the file), with their advice |

The same Kafka Streams errors are known causes of the log report (`tools/report-common/known_causes.py`, category
`Kafka Streams Issues`).

```bash
python3 -I tools/streams-analyzer/streams_report.py streams=/tmp/streams.log streams2=/tmp/streams2.log           # text
python3 -I tools/streams-analyzer/streams_report.py --json --sources <label TAB path file>                       # JSON
python3 -I tools/streams-analyzer/streams_report.py --html-out /tmp/streams.html streams=/tmp/streams.log         # page
```

Exit code 2 when no Kafka Streams line was found.

## Sample

`tools/log-analyzer/samples/kafka-streams/`: the logs of the 3 instances of `other/kafka-streams/serde-errors.sh`
(Kafka Streams 4.4.0): the main application and a demo application in ERROR after a poison pill, with its dead
stream thread, deserialization and production handler errors.

```bash
playground streams status --sample kafka_streams --html     # the page of the reports gallery (🌊 Kafka Streams)
playground analyze logs --sample kafka_streams              # the 🌊 Kafka Streams section of the log report
```
