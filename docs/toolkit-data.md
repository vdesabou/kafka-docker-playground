# 👉 Producing, consuming and SMTs

Put data in a topic, read it back, and check what a transform chain does to a record. Part of the [🧰 Reproduction toolkit](/reusables.md).

> [!TIP]
> For the details, see the deep dives on [producing](/deep-dive-topic-produce.md), [consuming](/deep-dive-topic-consume.md) and [testing SMTs](/deep-dive-connector-smt-test.md).

## 👉 Producing data

Use [playground topic produce](/playground%20topic%20produce): it creates the topic if needed, registers the schema (avro, json schema or protobuf) and generates realistic random data matching it. See the [command page](/playground%20topic%20produce) for all options.

> [!TIP]
> Pipe the schema or the payload with a quoted heredoc, `<< 'EOF'`, so that the `%g` placeholders survive the shell.

<!-- tabs:start -->

#### **String**

```bash
playground topic produce -t a-topic --nb-messages 10 --forced-value "This is a message %g"
```

#### **JSON**

```bash
playground topic produce -t a-topic --nb-messages 3 << 'EOF'
{"u_name": "scissors", "u_price": 2.75, "u_quantity": 3}
{"u_name": "tape", "u_price": 0.99, "u_quantity": 10}
{"u_name": "notebooks", "u_price": 1.99, "u_quantity": 5}
EOF
```

#### **Key and headers**

```bash
# key1, key2, etc.. (%g can also be used)
playground topic produce -t a-topic --nb-messages 3 --key "key1" --headers "header1:value1,header2:value2" << 'EOF'
{"u_name": "scissors", "u_price": 2.75, "u_quantity": 3}
{"u_name": "tape", "u_price": 0.99, "u_quantity": 10}
{"u_name": "notebooks", "u_price": 1.99, "u_quantity": 5}
EOF
```

#### **Avro**

```bash
playground topic produce -t a-topic --nb-messages 10 << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {"name": "u_name", "type": "string"},
    {"name": "u_price", "type": "float"},
    {"name": "u_quantity", "type": "int"}
  ]
}
EOF
```

#### **Avro with key**

```bash
playground topic produce -t a-topic --nb-messages 10 --key '
{
  "type": "record",
  "name": "myrecordkey",
  "fields": [
    {"name": "ID", "type": "long"}
  ]
}
' << 'EOF'
{
  "type": "record",
  "name": "myrecordvalue",
  "fields": [
    {"name": "ID", "type": "long"},
    {"name": "product", "type": "string"},
    {"name": "quantity", "type": "int"},
    {"name": "price", "type": "float"}
  ]
}
EOF
```

#### **Protobuf**

```bash
playground topic produce -t a-topic --nb-messages 10 << 'EOF'
syntax = "proto3";

message MyRecord {
    string f1 = 1;
}
EOF
```

#### **JSON Schema**

```bash
playground topic produce -t a-topic --nb-messages 10 << 'EOF'
{
  "type": "object",
  "properties": {
    "f1": {"type": "string"}
  }
}
EOF
```

#### **Exact payload**

Use `--generate-only` first to get the skeleton of a message, then `--forced-value` to send exactly the record you need:

```bash
playground topic produce -t a-topic --nb-messages 1 --forced-value '{"f1": "value1"}' << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {"name": "f1", "type": "string"}
  ]
}
EOF
```

#### **Schema file**

```bash
playground topic produce -t a-topic --nb-messages 10 < schema.avsc
```

#### **Tombstone**

```bash
playground topic produce -t a-topic --tombstone --key "mykey1"
```

#### **High volume**

```bash
playground topic produce -t a-topic --nb-messages 200000 --record-size 1000
```

#### **Steady flow**

A record every 100 ms until ctrl-c, for example to watch a connector catch up. The progress is logged every 10 seconds, and
after ctrl-c the number of records sent is exact:

```bash
playground topic produce -t a-topic --nb-messages -1 --throughput 10 --value '{"id": %g}'
```

To keep that flow while you inject a fault (a broker rolling restart, `playground debug block-traffic`…), produce in the
background, `--rate` being an alias of `--throughput`. The command returns, `--status` shows the records sent so far and
`--stop` ends it, with the exact number of records sent:

```bash
playground topic produce -t a-topic --value '{"id": %g}' --rate 100 --duration 10m --background
playground topic produce -t a-topic --status
playground topic produce -t a-topic --stop
```

#### **Force the format**

The format of `--value` (and `--key`) is detected from its content: a raw payload that contains `"_meta"`, `proto3`,
`"type": "object"`... would not be sent as is. Set it with `--value-format` (`avro`, `json-schema`, `protobuf`, `json`,
`sql`, `datagen`, `raw`):

```bash
playground topic produce -t a-topic --value-format raw --value '{"_meta": "not a datagen schema", "id": %g}'
```

<!-- tabs:end -->

> [!NOTE]
> The [Java producers](/legacy-java-producer) are deprecated: use them only if you have very specific requirements, such as setting the record timestamp.

## 👉 Consuming data

Use [playground topic consume](/playground%20topic%20consume): it reads the topic from the beginning and detects the format (avro, protobuf, json schema or plain) on its own. Every record is displayed with its timestamp, partition, offset, headers, key and schema ID (add `--print-schema` to also print the registered schemas). The consumer stops when no record arrives for 10 seconds (30 on Confluent Cloud).

<!-- tabs:start -->

#### **Simplest**

```bash
playground topic consume --topic a-topic
```

#### **All topics**

```bash
playground topic consume
```

#### **Assert content**

Wait up to `--timeout` seconds for at least 10 records, consume them, and fail if fewer could be consumed (records that cannot be deserialized are reported and do not count) or if none contains `value1`. This is how examples verify that data flowed:

```bash
playground topic consume --topic a-topic --min-expected-messages 10 --grep "value1" --timeout 60
```

#### **Last records**

The most recent records, sorted by timestamp across partitions (by default, the first `--max-messages` 100 are displayed):

```bash
playground topic consume --topic a-topic --last 10
```

#### **From a time**

The records from a date (local time, add `Z` for UTC), an epoch, or a duration ago (`30s`, `10m`, `2h`, `1d`):

```bash
playground topic consume --topic a-topic --from-timestamp 10m
playground topic consume --topic a-topic --from-timestamp "2026-10-22 10:30"
```

#### **One offset**

The record a connector is stuck on (`--offset` is a number, `earliest` or `latest`, and needs `--partition`):

```bash
playground topic consume --topic a-topic --partition 0 --offset 1234 --max-messages 1
```

#### **JSON**

One json object per record (key and value embedded as json when they are valid json), only the records on stdout:

```bash
playground topic consume --topic a-topic --json | jq -r '.value.u_name'
```

#### **Count**

The number of records (not offsets: transaction markers, compacted records and records that cannot be deserialized do not count), alone on stdout:

```bash
playground topic consume --topic a-topic --count
playground topic consume --topic a-topic --count --grep "scissors"
```

#### **Tail**

```bash
playground topic consume --topic a-topic --tail
```

#### **Open in editor**

```bash
playground topic consume --topic a-topic --open
```

<!-- tabs:end -->

## 🛢️ Databases

[playground db](/playground%20db) runs SQL in the database container of the running example, with its own client (`sqlplus`, `psql`, `mysql` / `mariadb`, `sqlcmd`, `db2`, `mongosh`), and waits for a sink connector to write rows. The container, the user, the password and the database are found from the container environment (`POSTGRES_USER`, `MYSQL_ROOT_PASSWORD`, `SA_PASSWORD`, `ORACLE_PWD`…), so most examples need no flag.

```bash
# statements in a heredoc (or --file): stops at the first failing statement and exits with code 1
playground db sql << 'EOF'
CREATE TABLE customers (id INT PRIMARY KEY, name VARCHAR(50));
INSERT INTO customers VALUES (1, 'alice');
EOF

# instead of a sleep: wait until the sink has written 10 rows (a table that does not exist yet counts as empty)
playground db wait-for-rows --table orders --min-expected-rows 10
playground db sql > /tmp/result.log 2>&1 << 'EOF'
select * from orders;
EOF
grep "foo" /tmp/result.log

# another user or database (Oracle: --database is the service name, ORCLPDB1 for the pluggable database)
playground db sql --database ORCLPDB1 --user C##MYUSER --password mypassword << 'EOF'
select count(*) from ORDERS;
EOF

# MongoDB: mongosh commands, --table is the collection and --where a filter document
playground db wait-for-rows --database inventory --table customers --where '{"name": "alice"}'
```

Before reading the logs of a CDC source that is RUNNING but produces nothing, check the database: `playground db cdc-check` prints one ✅ ❌ ⚠️ line per prerequisite (Oracle ARCHIVELOG, supplemental logging and XStream, PostgreSQL `wal_level` and slots, MySQL binlog, SQL Server Agent and CDC tables, MongoDB replica set) with the statement that fixes it, and exits with code 1 when one is missing:

```bash
playground db cdc-check --connector-user C##MYUSER --table C##MYUSER.CUSTOMERS
#    ✅ ARCHIVELOG mode                                      ARCHIVELOG
#    ✅ minimal supplemental logging                         YES
#    ✅ all columns supplemental logging                     YES (database level: every table)
#    ✅ connector user C##MYUSER                             exists, common user
#    ✅ LOGMINING of C##MYUSER (LogMiner)                    granted
#    ...
```

A heredoc with a quoted delimiter (`<< 'EOF'`) is the easiest to copy and paste, and to grow into a longer query: `$` and quotes are kept as is (use `<< EOF` to interpolate shell variables). `--sql "<statement>"` exists for a quick one-liner in a terminal. `--container` picks the database when several are running, `--engine` when the image name does not tell which database it is, and `--ignore-errors` runs every statement even after a failing one.

## 📨 Message brokers

[playground mq](/playground%20mq) sends messages to the broker of a source example, shows what a sink wrote, and waits for a queue to fill up or to be drained by the connector: IBM MQ (`amqsput`, `amqsbcg`, `runmqsc` in its container), RabbitMQ (`rabbitmqctl`, `rabbitmqadmin` of the management images, else the HTTP API of `rabbitmq_management`, enabled on the fly), MQTT with mosquitto, ActiveMQ classic (REST API, Jolokia) and Solace (REST messaging, SEMP). The container, the queue manager or vhost and the credentials are found from the container environment and the defaults of the examples.

```bash
# 10 messages, %g replaced by 1..10 (or one message per line from a heredoc or --file)
playground mq put --queue myqueue --message '{"id": %g, "product": "product%g"}' --nb-messages 10

# the messages of a queue, without removing them (a source connector reads the same queue)
playground mq get --queue DEV.QUEUE.1
playground mq get --queue myqueue --json

# instead of a sleep: wait for the messages, then for the connector to consume them all
playground mq wait --queue myqueue --min-expected-messages 10
playground mq wait --queue myqueue --max-expected-messages 0 --max-wait 60

# MQTT has no queue: put, get and wait use --topic (get and wait subscribe)
playground mq put --topic my-mqtt-topic --message sample-msg-1
```

`get` browses: IBM MQ and ActiveMQ browse the queue, RabbitMQ reads the messages and requeues them (marked redelivered), Solace lists the spooled messages through SEMP (id, size and time, not the body). Pass `--container` when several brokers run, `--broker` when the image name does not tell which broker it is.

## 🪣 Object stores

[playground storage](/playground%20storage) lists, reads and waits for the objects that a sink connector writes to an object store: Amazon S3, MinIO and other S3 compatible stores, Google Cloud Storage, Azure Blob Storage, ADLS Gen2, HDFS and SFTP, through one rclone container, so no `aws s3`, `gcloud storage`, `az storage` or helper container. The bucket, the folder (`topics.dir`) and the credentials come from the config of the connector (the only running one by default), self-managed or fully managed; `--url` reads any other location.

```bash
# instead of a sleep: wait until the sink has written 3 objects (a folder that does not exist yet counts as empty)
playground storage wait-for-objects --min-expected-objects 3

# objects, then one line per topic-partition (objects, size, first offset, start offset of the last object)
playground storage ls --topic s3-topic

# records of the objects, Avro / Parquet / JSON / CSV / gzip decoded, then the offsets covered per topic-partition
playground storage cat --max-objects 5
playground storage cat --records | jq -r .f1          # only the records, one json per line
playground storage cat --summary --max-objects 0      # only the continuity check, every object

# any location: s3:// (--endpoint for MinIO), gs://, az://<account>/<container>, hdfs://, sftp://user:password@host
playground storage ls --url s3://mybucket/topics --endpoint http://minio:9000
```

The summary of `storage cat` gives the offsets of each topic-partition covered by the objects (the start offset of the object name plus its number of records), and flags what a customer asks about:

```
topic-partition                           objects   records                offsets  continuity
t1-0                                            3         8                  0 → 9  🕳️ 1 gap(s)
t1-2                                            2         6                  0 → 4  🔁 1 overlap(s)
   🕳️ t1-0: offsets 6-7 are in no object (between t1+0+0000000003.avro and t1+0+0000000008.avro)
   🔁 t1-2: offset 2 is in two objects (t1+2+0000000000.avro and t1+2+0000000002.avro): duplicates
```

A gap is expected on a compacted topic, with transactions (the markers use offsets) or when an SMT dropped records; an overlap is a duplicate. To compare the objects with the topic record by record, `playground connector reconcile --connector <sink>` reads every object of the topic.

## 🧪 Testing SMTs

[playground connector smt test](https://kafka-docker-playground.io/#/playground%20connector%20smt%20test) runs a chain of Single Message Transforms (SMTs) on one record and shows what each transform does to it, in a few seconds: what changes (topic, key, headers, value field by field, schema), each predicate and its result, a dropped record, the transform that fails with its error, and where each transform class comes from. No topic or connector is created, and the connector is not updated. The chain runs inside the `connect` container, with the classes and versions of the worker.

```bash
# the transforms of a running connector, on a default record
playground connector smt test --connector filestream-sink

# the same transforms, on a real record of the topic (converted with the converters of the connector: avro, protobuf, json schema...)
playground connector smt test --connector filestream-sink --from-topic filestream --offset 0

# your own chain on stdin (a whole connector config works too: only transforms.*, predicates.* and the converters are used)
playground connector smt test --record '{"topic":"orders","key":"o-1","value":{"id":1}}' << 'EOF'
{
  "transforms": "route",
  "transforms.route.type": "org.apache.kafka.connect.transforms.RegexRouter",
  "transforms.route.regex": "(.*)",
  "transforms.route.replacement": "crm-$1"
}
EOF

# the transforms and the record in files
playground connector smt test --config @transforms.json --record @record.json
```

| You want | Add |
| --- | --- |
| a source record instead of a sink one | `--type source` |
| the same chain on other CP versions | `--cp-version 7.9.0 --cp-version 8.3.2` |
| an SMT that is not in the worker | `--smt-plugin confluentinc/connect-transforms:1.4.4` / `--smt-jar my-smt.jar` |
| the steps as data, for an assertion | `--json` |
| the stack trace of the failing step | `--verbose` |

An HTML report of the steps is written to `/tmp/playground-smt-test/`.

![playground connector smt test report](./images/report-smt-test.jpg)

> [!TIP]
> The [connect-testing-smt-filestream-sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-testing-smt-filestream-sink) example shows every way to use the command, with a ready-to-use record and chain: `playground run -f testing-smt.sh`

> [!TIP]
> The [🍪 deep dive on SMT testing](/deep-dive-connector-smt-test.md) has the rest: the [record format](/deep-dive-connector-smt-test?id=_2-the-chain-and-the-record) (schemaless or with a schema, headers, `--from-topic`), [how to read the output](/deep-dive-connector-smt-test?id=_3-reading-the-output) and the `--json` fields, [other CP versions and SMTs that are not in the worker](/deep-dive-connector-smt-test?id=_4-versions-and-plugins-cp-version-smt-plugin-smt-jar), a hands-on lab and recipes for support repros.

> [!NOTE]
> Self-managed connectors only: the transforms of a fully managed connector run in Confluent Cloud (give its config with `--config` for an indicative result on a self-managed worker). The cfk environment is not supported yet. The chain runs outside of a connector task, so `errors.tolerance` and the dead letter queue do not apply: a failing transform is reported as failing.
