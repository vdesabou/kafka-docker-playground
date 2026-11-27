Synthetic input of `tools/dlq-tool/dlq_report.py` (what `playground topic dlq inspect` writes): 20 records of the dead letter
queue `dlq-jdbc-sink` of a JDBC sink `jdbc-sink` reading `orders`, over an hour, in 3 groups (Avro deserialization, a NOT NULL
violation in PostgreSQL, a Cast transform). Neutral names only. `--summary` takes the JSON itself, not a path:

    python3 -I tools/dlq-tool/dlq_report.py --groups tools/dlq-tool/samples/jdbc_sink_dlq/groups.json --records tools/dlq-tool/samples/jdbc_sink_dlq/records.json --summary "$(cat tools/dlq-tool/samples/jdbc_sink_dlq/summary.json)" --topic dlq-jdbc-sink --html-out <report>.html
