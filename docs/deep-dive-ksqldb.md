# 🍪 Deep dive: ksqlDB, `playground ksqldb sql`, `list`, `describe`, `wait`

The commands that run ksqlDB statements next to the playground's Kafka cluster and inspect what they created, without
`docker exec ksqldb-cli ksql` or `curl` on the REST API: what one `playground ksqldb sql` call does, pull queries vs
push queries, why a query returns nothing, how to wait for a persistent query instead of a `sleep`, where the records
that fail a query go, and how tombstones reach a table. This is how you reproduce "my table is empty", "the query
skips records", "the push query never returns" or "the deleted key is still there". Takes about 15 minutes to read and
run.

| You want | Command |
| --- | --- |
| a ksqlDB server next to any example | `playground run -f <example> --enable-ksqldb` (or `ENABLE_KSQLDB=1`), the `ksqldb/` examples enable it |
| another ksqlDB version than the CP one | `--ksqldb-tag <version>` (server and cli) |
| run statements | `playground ksqldb sql << 'EOF' … EOF` / `playground ksqldb sql --file queries.sql` |
| a statement that is expected to fail | `… --ignore-errors` (the error is printed, exit 0) |
| a push query (`EMIT CHANGES`) that stops | `LIMIT <n>` in the query, or `--query-timeout <seconds>` |
| wait until a `CREATE … AS SELECT` (or a source table) has processed its input | `playground ksqldb wait [--source <name>]` |
| the streams, tables and persistent queries, with their state | `playground ksqldb list` (`--json`) |
| fields, queries, lag, statistics and errors of one stream or table | `playground ksqldb describe --source <name>` (`--json`) |
| queries in ERROR, rebalancing, messages per second (JMX) | `playground ksqldb metrics`, see the [observability deep dive](/deep-dive-observability.md) |
| the records that failed a query | `SELECT … FROM KSQL_PROCESSING_LOG EMIT CHANGES LIMIT <n>;` (needs the processing log stream, [section 5](/deep-dive-ksqldb?id=_5-the-processing-log-the-records-a-query-skipped)) |
| the REST API | [http://localhost:8088](http://localhost:8088) |

---

## 1. Mental model (the 3 things to remember)

1. **One call = one ksql cli session.** `playground ksqldb sql` copies the statements into the `ksqldb-cli` container
   and runs `ksql --file <file> http://ksqldb-server:8088` there. Streams, tables and persistent queries live in the
   server and stay; **`SET` only lasts for the call**. `SET 'auto.offset.reset' = 'earliest';` must be at the top of
   every call that creates a query or runs a push query on records already in the topic: without it, they start
   from the end of the topic, and see nothing.

2. **Pull queries return, push queries never do.** A pull query (`SELECT … FROM <table> WHERE …;`, no `EMIT
   CHANGES`) reads the current state of a materialized table and returns. A push query (`… EMIT CHANGES`) subscribes to
   the changes and **never ends** unless it has a `LIMIT`, or `--query-timeout`: otherwise the cli is stopped after
   `--max-wait` seconds (exit 1). A persistent query (`CREATE STREAM|TABLE … AS SELECT`, `INSERT INTO … SELECT`) is
   started on the server and the call returns at once, while it processes its input in the background: **`playground
   ksqldb wait`** is what tells you it is done, not a `sleep`.

3. **A record that can't be deserialized is skipped, not fatal.** A wrong value (not JSON, a field of the wrong type)
   or a wrong key (a string key for an `INT KEY`) doesn't stop the query: the record is dropped, counted in the
   errors of `ksqldb describe`, and written to the **processing log** (`KSQL_PROCESSING_LOG`), once per query that
   reads it. "The query is RUNNING but records are missing" starts there.

---

## 2. `playground ksqldb sql`

```bash
# statements on stdin (quote the heredoc delimiter, so that $ and ' survive)
playground ksqldb sql << 'EOF'
SET 'auto.offset.reset' = 'earliest';
CREATE STREAM ORDERS (ID INT KEY, PRODUCT VARCHAR, QUANTITY INT) WITH (KAFKA_TOPIC = 'orders', VALUE_FORMAT = 'JSON', PARTITIONS = 1);
INSERT INTO ORDERS (ID, PRODUCT, QUANTITY) VALUES (1, 'laptop', 1);
SELECT * FROM ORDERS EMIT CHANGES LIMIT 1;
EOF

# statements in a file, separated by ;
playground ksqldb sql --file ./queries.sql

# a push query without LIMIT, stopped after 10 seconds
echo "SELECT * FROM ORDERS EMIT CHANGES;" | playground ksqldb sql --query-timeout 10
```

What it prints: the version of the server, then the output of the cli for each statement (the JVM warnings and the
banner are removed). DDL statements are echoed with every property ksqlDB filled in, which shows the defaults it chose
(`KEY_FORMAT='KAFKA'`, `CLEANUP_POLICY`, `PARTITIONS`, `REPLICAS`, `RETENTION_MS`):

```bash
# 🧮 Running ksqlDB statements in ksqldb-cli container (ksqlDB 8.4.1, http://localhost:8088)
# Successfully changed local property 'auto.offset.reset' to 'earliest'. Use the UNSET command to revert your change.
#
# CREATE STREAM ORDERS (ID INTEGER KEY, PRODUCT STRING, QUANTITY INTEGER) WITH (CLEANUP_POLICY='delete', KAFKA_TOPIC='orders', KEY_FORMAT='KAFKA', PARTITIONS=1, VALUE_FORMAT='JSON');
#  Message
# ----------------
#  Stream created
# ----------------
```

How it fails, and what the command adds:

| What happens | Exit | What it prints |
| --- | --- | --- |
| no statements (empty stdin, no `--file`) | 1 | `❌ no ksqlDB statements: pass them on stdin (heredoc) or with --file` |
| a statement fails | 1 | the error of the cli prefixed with `❌`, **the next statements still run**, then `❌ <n> ksqlDB statement(s) failed (the other statements were run):`, the errors again, and `🎓 add --ignore-errors when the failure is expected` |
| … with `--ignore-errors` | 0 | the errors with `❌`, then `⚠️ <n> ksqlDB statement(s) failed (ignored, --ignore-errors is set)` |
| the cli is still running after `--max-wait` (default `120`) | 1 | `⏱️ the ksql cli was stopped after <n>s: a push query (EMIT CHANGES) never ends without a LIMIT` and `add LIMIT <n> to the query, set --query-timeout, or increase --max-wait` |
| `ksqldb-cli` is not running | 1 | `❌ the ksqldb-cli container is not running: start an example with playground run --enable-ksqldb` |

Gotchas:

- **Every statement runs, even after a failing one** (unlike `playground flink sql`, which stops at the first error).
  A `CREATE … AS SELECT` that depends on a failed `CREATE STREAM` then fails too: read the first `❌`, not the last.
- **Unquoted names are upper-cased**: `orders` and `ORDERS` are the same stream, but the Kafka topic keeps the case
  of `KAFKA_TOPIC`. The topic of a `CREATE … AS SELECT` is the upper-case name of the stream or table
  (`ORDERS_BY_PRODUCT`), unless the statement sets `KAFKA_TOPIC`.
- **The result tables use the whole width**: the width of the terminal, 200 characters when the output is not a
  terminal (a script, CI), split between the columns. Long values wrap on several lines: `--width 400` for wide rows.
- **`--query-timeout` applies to each push query**, `--max-wait` to the whole call. `--query-timeout` is the clean way
  ("Query terminated", exit 0), `--max-wait` the safety net (exit 1).
- **`INSERT INTO … VALUES` writes with the formats of the stream** (JSON value, `KAFKA` key here), which is the
  easiest way to get records the stream can read. `playground topic produce` writes what you give it: see
  [section 5](/deep-dive-ksqldb?id=_5-the-processing-log-the-records-a-query-skipped) for what happens when it
  doesn't match.

---

## 3. Pull queries, push queries, and `auto.offset.reset`

```bash
# pull query: the current state of a table, returns
playground ksqldb sql << 'EOF'
SELECT * FROM ORDERS_BY_PRODUCT WHERE PRODUCT = 'laptop';
EOF
# |PRODUCT   |NB_ORDERS   |TOTAL_QUANTITY   |
# |laptop    |3           |10               |
# Query terminated

# push query: the changes, from the beginning because of the SET, stops after 3 rows
playground ksqldb sql << 'EOF'
SET 'auto.offset.reset' = 'earliest';
SELECT ID, PRODUCT FROM ORDERS EMIT CHANGES LIMIT 3;
EOF
# |ID   |PRODUCT   |
# |1    |laptop    |
# |2    |phone     |
# |3    |laptop    |
# Limit Reached
# Query terminated
```

(The result tables are shown with narrowed columns on this page.)

- **A pull query needs a materialized table**: a `CREATE TABLE … AS SELECT`, or a `CREATE SOURCE TABLE` on a topic.
  A plain `CREATE TABLE` on a topic (no `SOURCE`) is refused: ``The `PRODUCTS_PLAIN` table isn't queryable. To derive
  a queryable table, you can do 'CREATE TABLE QUERYABLE_PRODUCTS_PLAIN AS SELECT * FROM PRODUCTS_PLAIN'.``, followed
  by `Add EMIT CHANGES if you intended to issue a push query.`
- **`auto.offset.reset` decides where a new query starts**, and it is read when the query is created: a `CREATE …
  AS SELECT` sent without `SET 'auto.offset.reset' = 'earliest';` in the same call only processes the records that
  arrive afterwards. It is the most common "my table is empty" ([lab step 4](/deep-dive-ksqldb?id=_6-hands-on-lab-≈15-min)).
  Changing it later doesn't help: drop the query (`DROP TABLE … DELETE TOPIC;` or `TERMINATE <query id>;`) and create
  it again with the `SET`.
- **Old event times make the output disappear**: with `TIMESTAMP = '<column>'` on event times older than the
  retention of the topics (records from 2019 / 2020), a persistent query writes its output with those timestamps, its
  topic gets the default `retention.ms` (7 days), and the broker deletes it seconds later
  (`Deleting segment … due to retention time 604800000ms breach based on the largest record timestamp in the
  segment` in `playground container logs -c broker --no-follow`). `ksqldb wait` is happy and the push query on the
  output prints no row. Add `RETENTION_MS = -1` to the `WITH` of the source stream: the derived topics get the same
  retention, as in [`ksqldb/tumbling-windows`](https://github.com/vdesabou/kafka-docker-playground/tree/master/ksqldb/tumbling-windows)
  and `manage-deserialization-errors` (#10230).
- **A source table is read-only**: `INSERT INTO <source table> VALUES …` fails with `Cannot insert values into
  read-only table: <name>`. Produce to its topic with `playground topic produce --key … --value …`.

---

## 4. `list`, `describe` and `wait`

```bash
playground ksqldb list                                  # SHOW STREAMS + SHOW TABLES + SHOW QUERIES
playground ksqldb list --json | jq -r '.queries[] | select(.state != "RUNNING") | .id'
playground ksqldb describe --source ORDERS_BY_PRODUCT   # DESCRIBE … EXTENDED, digested
playground ksqldb describe --source ORDERS_BY_PRODUCT --json | jq '.stats."total-messages"'
playground ksqldb wait                                  # every persistent query, and the source tables
playground ksqldb wait --source ORDERS_BY_PRODUCT --max-wait 600
```

```bash
playground ksqldb list
# 🧮 Streams, tables and queries of ksqlDB 8.4.1 (http://localhost:8088)
# TYPE    NAME                 TOPIC                KEY FORMAT  VALUE FORMAT  WINDOWED
# STREAM  BIG_ORDERS           BIG_ORDERS           KAFKA       JSON          false
# STREAM  KSQL_PROCESSING_LOG  ksql_processing_log  KAFKA       JSON          false
# STREAM  ORDERS               orders               KAFKA       JSON          false
# TABLE   ORDERS_BY_PRODUCT    ORDERS_BY_PRODUCT    KAFKA       JSON          false
#
# QUERY ID                  STATE    TYPE        SINKS              SINK TOPICS
# CTAS_ORDERS_BY_PRODUCT_3  RUNNING  PERSISTENT  ORDERS_BY_PRODUCT  ORDERS_BY_PRODUCT
# CSAS_BIG_ORDERS_5         RUNNING  PERSISTENT  BIG_ORDERS         BIG_ORDERS

playground ksqldb describe --source ORDERS_BY_PRODUCT
# 🧮 TABLE ORDERS_BY_PRODUCT: topic ORDERS_BY_PRODUCT (1 partitions, replication 1), key format KAFKA, value format JSON
#
# FIELD           TYPE     KEY
# PRODUCT         STRING   🔑
# NB_ORDERS       BIGINT
# TOTAL_QUANTITY  INTEGER
#
# ✍️ Queries writing to ORDERS_BY_PRODUCT
# QUERY ID                  STATE    LAG
# CTAS_ORDERS_BY_PRODUCT_3  RUNNING  0
#
# 📊 Statistics (sum over the ksqlDB servers)
#    messages-per-sec: 0.060164851693640574
#    total-messages: 6.0
```

- **The query id tells the statement**: `CSAS_` (`CREATE STREAM AS SELECT`), `CTAS_` (`CREATE TABLE AS SELECT`),
  `INSERTQUERY_`, `CST_` (the query that materializes a `CREATE SOURCE TABLE`), then the sink and a counter. Its
  consumer group is `_confluent-ksql-<ksql.service.id>query_<query id>` (`_confluent-ksql-default_query_…` here):
  `playground consumer-group describe --group <it>` shows its lag per partition.
- **`describe` sums the statistics and errors over the servers**, and prints the errors in a `⚠️ Errors` block with
  the processing log query to run. The lag of a query is the sum over the partitions of its input topics, `-` when
  it has not committed any offset (or for the queries reading from the stream or table).
- **`wait` is done when every query is RUNNING and has committed the end of its input topics**. A query that has not
  committed anything yet is done when its input topics are empty, or after 20 seconds RUNNING without commit, with a
  warning: `⚠️ <query id> is RUNNING but has not committed any offset after 20s: nothing to process from where it
  started (auto.offset.reset is latest unless SET 'auto.offset.reset' = 'earliest' was sent with its CREATE)`. That
  warning is the "empty table" diagnosis. `wait` exits 1 when a query is in ERROR (`❌ query <id> writing to <source>
  is in ERROR`), or after `--max-wait` seconds with what is still pending.
- **A source table is waited for too**: its `CST_` query has no sink, so `wait` finds it in the queries reading the
  table, and reads its lag from its consumer group.
- **The internal topics are not in `list`**: the repartition and changelog topics of a query
  (`_confluent-ksql-default_query_CTAS_ORDERS_BY_PRODUCT_3-Aggregate-GroupBy-repartition`…) are in
  `playground topic list`.

---

## 5. The processing log: the records a query skipped

The processing log is a Kafka topic (`ksql_processing_log`) with a stream on top of it (`KSQL_PROCESSING_LOG`). The
plaintext environment doesn't enable it: add these variables to the `ksqldb-server` service of a docker compose
override, as [`ksqldb/manage-deserialization-errors`](https://github.com/vdesabou/kafka-docker-playground/tree/master/ksqldb/manage-deserialization-errors)
and the lab do:

```yaml
services:
  ksqldb-server:
    environment:
      KSQL_KSQL_LOGGING_PROCESSING_TOPIC_NAME: ksql_processing_log
      KSQL_KSQL_LOGGING_PROCESSING_TOPIC_AUTO_CREATE: "true"
      KSQL_KSQL_LOGGING_PROCESSING_STREAM_AUTO_CREATE: "true"
      KSQL_KSQL_LOGGING_PROCESSING_ROWS_INCLUDE: "true"     # the record itself, in RECORDB64
      KSQL_LOG4J_PROCESSING_LOG_BROKERLIST: broker:9092
      KSQL_LOG4J_PROCESSING_LOG_TOPIC: ksql_processing_log
```

```bash
playground ksqldb sql << 'EOF'
SET 'auto.offset.reset' = 'earliest';
SELECT LOGGER, MESSAGE->DESERIALIZATIONERROR->ERRORMESSAGE AS ERROR,
       ENCODE(MESSAGE->DESERIALIZATIONERROR->RECORDB64, 'base64', 'utf8') AS RECORD
FROM KSQL_PROCESSING_LOG EMIT CHANGES LIMIT 4;
EOF
# |LOGGER                                               |ERROR                                                      |RECORD    |
# |processing.CTAS_ORDERS_BY_PRODUCT_3.KsqlTopic.Source…|Failed to deserialize value from topic: orders. Unrecogniz…|not json  |
# |processing.CSAS_BIG_ORDERS_5.KsqlTopic.Source.deseri…|Failed to deserialize value from topic: orders. Unrecogniz…|not json  |
# |processing.CSAS_BIG_ORDERS_5.KsqlTopic.Source.deseri…|Error deserializing KAFKA message from topic: orders       |9         |
# |processing.CTAS_ORDERS_BY_PRODUCT_3.KsqlTopic.Source…|Error deserializing KAFKA message from topic: orders       |9         |
```

- **One row per record and per query that reads it**: 2 bad records read by 2 queries are 4 rows, and
  `consumer-failed-messages: 4.0` in `ksqldb describe --source ORDERS`. `LOGGER` has the query id.
- **A key error doesn't say "key"**: a value that is not JSON gives `Failed to deserialize value from topic: orders.
  Unrecognized token 'not': …`, but the string key `"9"` sent to a stream with `ID INT KEY` (key format `KAFKA`, a
  4 bytes integer) gives `Error deserializing KAFKA message from topic: orders`, and `RECORDB64` is the key. The cause
  is in `MESSAGE->DESERIALIZATIONERROR->CAUSE`: `[Size of data received by IntegerDeserializer is not 4]`. A producer
  that writes keys as strings (`kafka-console-producer`, `playground topic produce --key 9`) needs a `VARCHAR KEY`
  (or `KEY_FORMAT='JSON'` for a JSON key).
- **The processing log is a stream like the others**: filter it in the push query (`WHERE
  MESSAGE->DESERIALIZATIONERROR->ERRORMESSAGE LIKE 'Error deserializing KAFKA%'`), or read the raw topic with
  `playground topic consume -t ksql_processing_log`.

---

## 6. Hands-on lab (≈15 min)

Start the plaintext environment with ksqlDB and the processing log (the override of
[section 5](/deep-dive-ksqldb?id=_5-the-processing-log-the-records-a-query-skipped) in
`docker-compose.plaintext.ksqldb.yml`):

```bash
export ENABLE_KSQLDB=true
playground start-environment --environment plaintext --docker-compose-override-file "${PWD}/docker-compose.plaintext.ksqldb.yml"
```

**Step 1: a stream and a table built from it, in one session**

```bash
playground ksqldb sql << 'EOF'
SET 'auto.offset.reset' = 'earliest';
CREATE STREAM ORDERS (ID INT KEY, PRODUCT VARCHAR, QUANTITY INT) WITH (KAFKA_TOPIC = 'orders', VALUE_FORMAT = 'JSON', PARTITIONS = 1);
INSERT INTO ORDERS (ID, PRODUCT, QUANTITY) VALUES (1, 'laptop', 1);
INSERT INTO ORDERS (ID, PRODUCT, QUANTITY) VALUES (2, 'phone', 2);
INSERT INTO ORDERS (ID, PRODUCT, QUANTITY) VALUES (3, 'laptop', 3);
INSERT INTO ORDERS (ID, PRODUCT, QUANTITY) VALUES (4, 'tablet', 4);
INSERT INTO ORDERS (ID, PRODUCT, QUANTITY) VALUES (5, 'phone', 5);
INSERT INTO ORDERS (ID, PRODUCT, QUANTITY) VALUES (6, 'laptop', 6);
CREATE TABLE ORDERS_BY_PRODUCT AS
  SELECT PRODUCT, COUNT(*) AS NB_ORDERS, SUM(QUANTITY) AS TOTAL_QUANTITY
  FROM ORDERS GROUP BY PRODUCT EMIT CHANGES;
EOF
# Successfully changed local property 'auto.offset.reset' to 'earliest'. …
#  Stream created
# CREATE TABLE ORDERS_BY_PRODUCT WITH (CLEANUP_POLICY='compact', KAFKA_TOPIC='ORDERS_BY_PRODUCT', PARTITIONS=1, REPLICAS=1, RETENTION_MS=604800000) AS SELECT …
#  Created query with ID CTAS_ORDERS_BY_PRODUCT_3
```

**Step 2: wait for the query instead of a sleep**

```bash
playground ksqldb wait --source ORDERS_BY_PRODUCT
# ⏳ Waiting up to 120s for the queries writing to ORDERS_BY_PRODUCT to be RUNNING and to have processed all their input records
# ✅ the queries writing to ORDERS_BY_PRODUCT are RUNNING and have no lag (after 6s)
```

**Step 3: a pull query, then a push query**

The two queries of [section 3](/deep-dive-ksqldb?id=_3-pull-queries-push-queries-and-autooffsetreset): `laptop`, 3
orders, quantity 10, returned at once; then the first 3 orders, `Limit Reached`.

**Step 4: `SET` only lasts for the call**

```bash
# the same push query, in a new call without the SET: it starts from the end of the topic
playground ksqldb sql --query-timeout 10 << 'EOF'
SELECT ID, PRODUCT FROM ORDERS EMIT CHANGES;
EOF
# |ID   |PRODUCT   |
# Query terminated                    <- no row, after 10 seconds, exit 0

# a persistent query created without the SET
playground ksqldb sql << 'EOF'
CREATE STREAM BIG_ORDERS AS SELECT * FROM ORDERS WHERE QUANTITY >= 3 EMIT CHANGES;
EOF
#  Created query with ID CSAS_BIG_ORDERS_5
playground ksqldb wait --source BIG_ORDERS
#    ⏳ CSAS_BIG_ORDERS_5: RUNNING, no committed offsets yet
# ⚠️ CSAS_BIG_ORDERS_5 is RUNNING but has not committed any offset after 20s: nothing to process from where it started (auto.offset.reset is latest unless SET 'auto.offset.reset' = 'earliest' was sent with its CREATE)
# ⚠️ the queries writing to BIG_ORDERS are RUNNING without lag, but CSAS_BIG_ORDERS_5 processed none of the records already in its input (started at the end of it, see above) (after 20s)
playground topic get-number-records --topic BIG_ORDERS
# 0                                   <- 4 orders have QUANTITY >= 3, none of them is in BIG_ORDERS
```

**Step 5: list and describe**

```bash
playground ksqldb list
playground ksqldb describe --source ORDERS_BY_PRODUCT
playground ksqldb list --json | jq -r '.queries[] | "\(.id) \(.state)"'
# CTAS_ORDERS_BY_PRODUCT_3 RUNNING
# CSAS_BIG_ORDERS_5 RUNNING
```

The outputs of [section 4](/deep-dive-ksqldb?id=_4-list-describe-and-wait): `KSQL_PROCESSING_LOG` is listed with the
streams, `ORDERS_BY_PRODUCT` has `PRODUCT` as key, a lag of 0 and 6 messages.

**Step 6: records that can't be deserialized, and the processing log**

```bash
playground topic produce -t orders --value 'not json' --value-format raw                                  # a bad value
playground topic produce -t orders --value '{"PRODUCT": "phone", "QUANTITY": 8}' --value-format raw        # a good record (null key)
playground topic produce -t orders --key 9 --value '{"PRODUCT": "phone", "QUANTITY": 100}' --value-format raw   # a bad key: the string "9"
playground ksqldb wait --source ORDERS_BY_PRODUCT
playground ksqldb sql << 'EOF'
SELECT * FROM ORDERS_BY_PRODUCT WHERE PRODUCT = 'phone';
EOF
# |phone   |3   |15   |                <- 2 + 5 + 8: the record with QUANTITY 100 is not counted
playground ksqldb describe --source ORDERS
# 📊 Statistics (sum over the ksqlDB servers)
#    consumer-messages-per-sec: 0.12031737238999092
#    consumer-total-bytes: 378.0
#    consumer-total-messages: 12.0
# ⚠️ Errors
#    consumer-failed-messages: 4.0
#    consumer-failed-messages-per-sec: 0.040075341646310145
#    🎓 the records that failed are in the processing log: SELECT * FROM KSQL_PROCESSING_LOG EMIT CHANGES LIMIT 10;
```

Then the processing log query of [section 5](/deep-dive-ksqldb?id=_5-the-processing-log-the-records-a-query-skipped)
(4 rows), and the cause of the key error:

```bash
playground ksqldb sql << 'EOF'
SET 'auto.offset.reset' = 'earliest';
SELECT MESSAGE->DESERIALIZATIONERROR->CAUSE AS CAUSE
FROM KSQL_PROCESSING_LOG
WHERE MESSAGE->DESERIALIZATIONERROR->ERRORMESSAGE LIKE 'Error deserializing KAFKA%'
EMIT CHANGES LIMIT 1;
EOF
# |[Size of data received by IntegerDeserializer is not 4]   |
```

**Step 7: tombstones on a source table**

```bash
playground ksqldb sql << 'EOF'
SET 'auto.offset.reset' = 'earliest';
CREATE SOURCE TABLE PRODUCTS (ID VARCHAR PRIMARY KEY, NAME VARCHAR) WITH (KAFKA_TOPIC = 'products', VALUE_FORMAT = 'JSON', PARTITIONS = 1);
EOF
#  Created query with ID CST_PRODUCTS_7          <- a source table is materialized by a query
playground topic produce -t products --key p1 --value '{"NAME": "laptop"}' --value-format raw
playground topic produce -t products --key p2 --value '{"NAME": "phone"}' --value-format raw
playground ksqldb wait --source PRODUCTS
# ✅ the queries writing to PRODUCTS are RUNNING and have no lag (after 1s)
playground ksqldb sql --ignore-errors << 'EOF'
INSERT INTO PRODUCTS (ID, NAME) VALUES ('p3', 'tablet');
SELECT * FROM PRODUCTS;
EOF
# ❌ Cannot insert values into read-only table: PRODUCTS
# |ID   |NAME     |
# |p1   |laptop   |
# |p2   |phone    |
# Query terminated
# ⚠️ 1 ksqlDB statement(s) failed (ignored, --ignore-errors is set)

playground topic produce -t products --tombstone --key p1
# 🧟 Sending tombstone(s)
playground ksqldb wait --source PRODUCTS
playground ksqldb sql << 'EOF'
SELECT * FROM PRODUCTS;
EOF
# |ID   |NAME     |
# |p2   |phone    |                  <- the tombstone deleted p1

# the same topic as a plain table (no SOURCE): not materialized, no pull query
playground ksqldb sql --ignore-errors << 'EOF'
CREATE TABLE PRODUCTS_PLAIN (ID VARCHAR PRIMARY KEY, NAME VARCHAR) WITH (KAFKA_TOPIC = 'products', VALUE_FORMAT = 'JSON');
SELECT * FROM PRODUCTS_PLAIN;
EOF
#  Table created
# ❌ The `PRODUCTS_PLAIN` table isn't queryable. To derive a queryable table, you can do 'CREATE TABLE QUERYABLE_PRODUCTS_PLAIN AS SELECT * FROM PRODUCTS_PLAIN'. See https://cnfl.io/queries for more info.
# Add EMIT CHANGES if you intended to issue a push query.
```

**Step 8: the three classic mistakes**

```bash
playground ksqldb sql < /dev/null
# ❌ no ksqlDB statements: pass them on stdin (heredoc) or with --file

playground ksqldb sql << 'EOF'
CREATE STREAM ORDERS (ID INT KEY, PRODUCT VARCHAR) WITH (KAFKA_TOPIC = 'orders', VALUE_FORMAT = 'JSON');
SELECT * FROM NOPE EMIT CHANGES LIMIT 1;
SHOW STREAMS;
EOF
# ❌ Cannot add stream 'ORDERS': A stream with the same name already exists
# ❌ Exception while preparing statement: NOPE does not exist.
#
#  Stream Name         | Kafka Topic         | Key Format | Value Format | Windowed      <- SHOW STREAMS still ran
#  …
# ❌ 2 ksqlDB statement(s) failed (the other statements were run):
#    Cannot add stream 'ORDERS': A stream with the same name already exists
#    Exception while preparing statement: NOPE does not exist.
#    🎓 add --ignore-errors when the failure is expected                                  <- exit 1

playground ksqldb sql --max-wait 20 << 'EOF'
SELECT * FROM ORDERS EMIT CHANGES;
EOF
# ⏱️ the ksql cli was stopped after 20s: a push query (EMIT CHANGES) never ends without a LIMIT
#    add LIMIT <n> to the query, set --query-timeout, or increase --max-wait              <- exit 1
```

```bash
playground stop
```

---

## 7. Recipes for support repros

| Customer symptom | Command |
| --- | --- |
| "my ksqlDB table / stream is empty" | `playground ksqldb wait --source <it>`: the warning `RUNNING but has not committed any offset after 20s` means the query started at the end of its topic: create it again with `SET 'auto.offset.reset' = 'earliest';` in the same call |
| "the query is RUNNING but some records are missing" | `playground ksqldb describe --source <input stream>` (`⚠️ Errors`, `consumer-failed-messages`), then the processing log query of [section 5](/deep-dive-ksqldb?id=_5-the-processing-log-the-records-a-query-skipped) with `ERRORMESSAGE`, `CAUSE` and `RECORDB64` |
| "`Error deserializing KAFKA message from topic`" | the key format doesn't match the producer: an `INT KEY` / `BIGINT KEY` read keys written as strings. `CAUSE` says `Size of data received by IntegerDeserializer is not 4`: use `VARCHAR KEY`, or the right `KEY_FORMAT` |
| "`Failed to deserialize value from topic`" | produce the customer's record next to valid ones with `playground topic produce -t <t> --value '<record>' --value-format raw` (or their Avro / Protobuf schema), then `describe` and the processing log |
| "the output of a windowed / timestamped query vanishes, the push query prints no row" | event times older than the retention: `playground container logs -c broker --no-follow \| grep "retention time"`, then `RETENTION_MS = -1` on the source stream ([section 3](/deep-dive-ksqldb?id=_3-pull-queries-push-queries-and-autooffsetreset)) |
| "the push query never returns" | it never does: `LIMIT <n>` or `--query-timeout`; for the current value, a pull query on a materialized table |
| "a pull query is refused on our table" (``The `X` table isn't queryable``) | the table is not materialized: `CREATE SOURCE TABLE`, or a `CREATE TABLE … AS SELECT` on top |
| "the deleted key is still in the table" | `playground topic produce -t <topic of the table> --tombstone --key <k>`, `ksqldb wait --source <table>`, then the pull query; for a `CREATE TABLE … AS SELECT`, see [`ksqldb/tombstone-propagated-table`](https://github.com/vdesabou/kafka-docker-playground/tree/master/ksqldb/tombstone-propagated-table) |
| "a query is in ERROR / keeps rebalancing" | `playground ksqldb list` (state), `playground ksqldb metrics`, `playground ksqldb describe --source <its sink>`, `playground container logs -c ksqldb-server --errors` |
| "it worked in ksqlDB X, not in Y" | the same statements with `playground run … --ksqldb-tag X`, then `--ksqldb-tag Y`; `playground cp-changelog --from X --to Y --component ksqldb` for the fixes in between |
| joins, windows, schema evolution, nested JSON | the 27 examples of [`ksqldb/`](https://github.com/vdesabou/kafka-docker-playground/tree/master/ksqldb): `playground find-example "ksqldb <words>"` |

In a repro model, assert on the output instead of reading it:

```bash
playground ksqldb wait --source ORDERS_BY_PRODUCT
output=$(playground ksqldb sql <<< "SELECT * FROM ORDERS_BY_PRODUCT WHERE PRODUCT = 'laptop';")
echo "$output" | grep -q -E '^\|laptop +\|3 +\|' || { logerror "❌ laptop should have 3 orders"; exit 1; }
[ "$(playground ksqldb list --json | jq '[.queries[] | select(.state != "RUNNING")] | length')" == "0" ] || { logerror "❌ a query is not RUNNING"; exit 1; }
```

---

## 8. Cheat sheet

```bash
playground run -f <example> --enable-ksqldb [--ksqldb-tag <version>]      # or ENABLE_KSQLDB=1
playground ksqldb sql [--file <file.sql> | << 'EOF' … EOF] [--query-timeout <s>] [--max-wait 120] [--ignore-errors] [--width <n>]
playground ksqldb wait [--source <name>]... [--max-wait 120]
playground ksqldb list [--json]
playground ksqldb describe --source <name> [--json]
playground ksqldb metrics [--json]
```

- `ksqldb-server` (REST API on `8088`, JMX on `10003`) and `ksqldb-cli`, in the `ksqldb` profile. From ksqlDB, Kafka is
  `broker:9092` and Schema Registry `http://schema-registry:8081`.
- One call = one cli session: `SET 'auto.offset.reset' = 'earliest';` at the top of every call that creates a query
  or runs a push query on existing records.
- Pull query = returns; push query (`EMIT CHANGES`) = `LIMIT` or `--query-timeout`; persistent query = `ksqldb wait`.
- Every statement runs, even after a failing one: exit 1 unless `--ignore-errors`.
- Skipped records: `describe` (`⚠️ Errors`), then `KSQL_PROCESSING_LOG` (one row per record and per query).
- Sources: [`ksqldb/sql.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/ksqldb/sql.sh),
  [`ksqldb/list.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/ksqldb/list.sh),
  [`ksqldb/describe.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/ksqldb/describe.sh),
  [`ksqldb/wait.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/ksqldb/wait.sh),
  helpers `get_ksqldb_url_and_security` / `ksqldb_rest_statement` in
  [`cli_function.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/lib/cli_function.sh).

---

**Links**

- 👉 Examples: the 27 examples of [`ksqldb/`](https://github.com/vdesabou/kafka-docker-playground/tree/master/ksqldb),
  in particular [`manage-deserialization-errors`](https://github.com/vdesabou/kafka-docker-playground/tree/master/ksqldb/manage-deserialization-errors)
  and [`tombstone-propagated-table`](https://github.com/vdesabou/kafka-docker-playground/tree/master/ksqldb/tombstone-propagated-table)
- 📖 [Enabling ksqlDB](/how-to-use?id=🚀-enabling-ksqldb) in How to use
- 🍪 Deep dives: [`topic produce`](/deep-dive-topic-produce.md) for the records the queries read (keys, tombstones,
  raw values), [`topic consume`](/deep-dive-topic-consume.md) to check what they write,
  [observability](/deep-dive-observability.md) for `ksqldb metrics`, [Flink SQL](/deep-dive-flink.md) for the other
  SQL engine, [Schema Registry](/deep-dive-schema.md) for Avro, Protobuf and JSON Schema streams
- 🧠 CLI reference: [playground ksqldb](/playground%20ksqldb), [playground ksqldb sql](/playground%20ksqldb%20sql),
  [playground ksqldb list](/playground%20ksqldb%20list), [playground ksqldb describe](/playground%20ksqldb%20describe),
  [playground ksqldb wait](/playground%20ksqldb%20wait), [playground ksqldb metrics](/playground%20ksqldb%20metrics)
