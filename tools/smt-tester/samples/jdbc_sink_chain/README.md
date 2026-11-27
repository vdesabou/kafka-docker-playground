Synthetic input of `tools/smt-tester/smt_report.py` (the result JSON that `SmtTester.java` writes for `playground connector
smt test`): a sink record of `orders` through 4 transforms (ReplaceField, InsertField skipped by a TopicNameMatches predicate,
TimestampConverter, RegexRouter). Neutral names only. Build the report with:

    python3 -I tools/smt-tester/smt_report.py --result tools/smt-tester/samples/jdbc_sink_chain/result.json --output <report>.html --title "SMT test of jdbc-sink"
