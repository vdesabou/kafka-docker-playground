# Flink

[Apache Flink](https://nightlies.apache.org/flink/flink-docs-stable/) is a stream processing engine: a **jobmanager** plans the jobs and serves the UI and REST API, **taskmanagers** run them. Jobs are written in SQL (submitted with the SQL client) or in Java (a jar).

## Start Flink with any example

Add `--enable-flink` to `playground run` (or set `ENABLE_FLINK=1`): the plaintext environment then also starts the `jobmanager`, `taskmanager` and `sql-client` containers, next to the broker.

* Flink UI and REST API: [http://localhost:18081](http://localhost:18081)
* Flink connectors (Kafka, JDBC…) are not in the Flink image: the CLI asks which ones to download from [Maven](https://repo.maven.apache.org/maven2/org/apache/flink/). To skip the question, set `FLINK_URL` to the jar(s) to download.
* The Flink version is `FLINK_TAG` (default `latest`).

## playground flink commands

```bash
# one SQL client session: CREATE TABLE and the INSERT INTO that uses it go in the same call
playground flink sql << 'EOF'
CREATE TABLE orders (id INT, product STRING) WITH ('connector' = 'datagen', 'rows-per-second' = '1');
CREATE TABLE sink (id INT, product STRING) WITH ('connector' = 'print');
INSERT INTO sink SELECT * FROM orders;
EOF

playground flink list-jobs            # state, start time, duration, root cause of FAILED jobs
playground flink cancel --all         # or --job <id>
```

## Examples

* [Flink SQL with Kafka](flink-sql-kafka/): streaming and batch Flink SQL on Kafka topics
