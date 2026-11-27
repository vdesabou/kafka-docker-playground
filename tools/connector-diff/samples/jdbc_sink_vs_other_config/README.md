Synthetic input of `tools/connector-diff/diff_report.py` (the `diff.json` that `playground connector diff` writes): a JDBC sink
`jdbc-sink` compared with another config file, `other-jdbc-sink.json`. Neutral names only. Build the report with:

    python3 -I tools/connector-diff/diff_report.py --diff tools/connector-diff/samples/jdbc_sink_vs_other_config/diff.json --a jdbc-sink --b other-jdbc-sink.json --connector-class io.confluent.connect.jdbc.JdbcSinkConnector --reference connect/connect-jdbc-postgresql-sink/config-io.confluent.connect.jdbc.JdbcSinkConnector.txt --html-out <report>.html
