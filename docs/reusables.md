# 🧰 Reproduction toolkit

Everything you need once an example runs: bootstrap a reproduction model from it, share it, produce and consume data, test SMTs, debug the JVM and the network, break the network on purpose, and measure throughput.

## 🛠 Bootstrap reproduction model

Execute [🧠 CLI](/cli) with `playground repro bootstrap` [command](/playground%20repro%20bootstrap). It will start in interactive mode.

Examples:

### Basic

Without `-f`, the command is interactive. With `-f` (absolute path of the example to start from) and `-d` (description, start it with the case number if there is one), it only generates the files:

<video src="videos/repro-bootstrap.mp4" autoplay loop muted playsinline controls width="100%"></video>

### Deprecated: Java producer (`--producer`)

> [!WARNING]
> Most of times, it's much simpler to use `playground topic produce` [CLI](/playground%20topic%20produce)
> 
> Use java producer only if you have very specific requirements such as specifying record timestamp
> See [here](/legacy-java-producer) for instructions


### With custom SMT (`--custom-smt`)

If you want to add a custom SMT, just add `--custom-smt` flag.

This will create the following files:

![file structure](./images/custom_smt.jpg)

This is a no-op custom SMT:

```java
    @Override
    public R apply(R record) {
        log.info("Applying no-op MyCustomSMT");
        // add your logic here
        return record.newRecord(
            record.topic(),
            record.kafkaPartition(),
            record.keySchema(),
            record.key(),
            record.valueSchema(),
            record.value(),
            record.timestamp()
        );
    }
```

It will also add the required steps to compile code:

```bash
for component in MyCustomSMT-000000
do
    set +e
    log "🏗 Building jar for ${component}"
    build_java_component_with_retry "${component}" docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${DIR}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "$PWD/../../scripts/settings.xml:/tmp/settings.xml" -v "${DIR}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.9.11-eclipse-temurin-17 mvn -s /tmp/settings.xml -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package
    set -e
done
```

It will copy the jar to the connector lib folder:

```bash
log "📂 Copying custom jar to connector folder /usr/share/confluent-hub-components/debezium-debezium-connector-sqlserver/lib/"
playground container cp --source /path/to/kafka-docker-playground/reproduction-models/connect-connect-debezium-sqlserver-source/MyCustomSMT-000000/target/MyCustomSMT-1.0.0-SNAPSHOT-jar-with-dependencies.jar --destination connect:/usr/share/confluent-hub-components/debezium-debezium-connector-sqlserver/lib/
log "📂 Copying custom jar to connector folder /usr/share/confluent-hub-components/confluentinc-connect-transforms/lib/"
playground container cp --source /path/to/kafka-docker-playground/reproduction-models/connect-connect-debezium-sqlserver-source/MyCustomSMT-000000/target/MyCustomSMT-1.0.0-SNAPSHOT-jar-with-dependencies.jar --destination connect:/usr/share/confluent-hub-components/confluentinc-connect-transforms/lib/
log "♻️ Restart connect worker to load"
playground container restart --container connect
```

> [!NOTE]
> The `--source` path is the absolute path of your checkout. When the model is shared with [`playground repro export`](/reusables?id=%f0%9f%93%a6-share-a-reproduction-model), `playground repro import` changes it into the path of the other machine.

And add the transform config to connector:

```json
  "transforms": "MyCustomSMT",
  "transforms.MyCustomSMT.type": "com.github.vdesabou.kafka.connect.transforms.MyCustomSMT",
```

> [!TIP]
> To try the SMT on a record without copying the jar and restarting the worker after each build, use [playground connector smt test](/reusables?id=%f0%9f%a7%aa-testing-smts) with `--smt-jar`:
> `playground connector smt test --connector <connector> --smt-jar MyCustomSMT-000000/target/MyCustomSMT-1.0.0-SNAPSHOT-jar-with-dependencies.jar`

### With pipeline (`--pipeline`)

All the steps to create a pipeline, i.e an example with source and sink connectors are automated:

Example:

<video src="videos/repro-pipeline.mp4" autoplay loop muted playsinline controls width="100%"></video>

It will automatically:

* Add sink example(s) (you can select multiple !) at the end of source example
* Modify sink converters (key and value) to use same as source example
* Use same kafka topic for all connectors
* Add all required containers for all sink and source
* Update `CONNECT_PLUGIN_PATH` to include all connectors

## 📦 Share a reproduction model

[`playground repro export`](/playground%20repro%20export) packs one or more reproduction models into a single `.tgz` bundle. Your colleague then runs [`playground repro import`](/playground%20repro%20import) to get them in their own `reproduction-models` folder, along with the exact `playground run` line to use.

```bash
# preview: what goes in, and what the scan finds
playground repro export --dry-run

# write the bundle (current reproduction model)
playground repro export
# 📤 Exported bundle is available: /path/to/playground_repro_s3-sink-repro-123456-dlq_2026-10-21.tgz (8.0K)

# on the other machine
playground repro import -f ~/Downloads/playground_repro_s3-sink-repro-123456-dlq_2026-10-21.tgz
```

> [!TIP]
> On macOS, the bundle is also copied to the clipboard **as a file**: press <kbd>Cmd</kbd>+<kbd>V</kbd> in a Slack conversation (or a Zendesk comment, a mail) to attach it. Use `--no-clipboard` to skip it.

### 📤 Export

Without `--file`, the current reproduction model (the last one you ran or bootstrapped) is exported. The model doesn't have to be uncommitted.

```bash
# a given model (repeat -f to put several in one bundle)
playground repro export -f $PWD/reproduction-models/connect-connect-aws-s3-sink/s3-sink-repro-123456-dlq.sh

# every new or modified model of the reproduction-models folder
playground repro export --all-uncommitted

# write the bundle somewhere else than the current folder
playground repro export --output ~/Desktop
```

The bundle contains what the model needs:

* the script;
* the files of its folder that the script, or a docker compose file it uses, mentions: the docker compose override, producer or custom SMT sources, SQL files…;
* the support files linked by `repro bootstrap`: `README.md`, `stop.sh`, `benchmark-load.bash`, `config-*`.

Symlinks are stored as their content, so the bundle does not depend on the version of the example on the other machine. Files ignored by git, build output (`target/`), heap dumps, flight recordings, logs and credential files (`keyfile.json`, `*.pem`, `*.key`) are left out.

A `repro-manifest.json` describes the bundle:

* the last `playground run` line of each model, taken from your run history (`--tag`, `--connector-tag`, `--environment`, `--enable-*`…);
* its case number, author and base example;
* the playground commit it was exported from;
* the names, never the values, of the credentials it uses;
* the sha256 of every file.

`--cluster-creds` / `--cluster-schema-registry-creds` are removed from the run line: whoever imports the model runs it with their own cluster.

#### 🕵️ Secrets and customer data scan

Before anything is written, and with `--dry-run` too, the bundle is scanned. The export stops when a file contains:

* the value of a credential known to your machine: the [`playground secrets`](/playground%20secrets) store, exported credential variables, `CLUSTER_CREDS` / `SCHEMA_REGISTRY_CREDS` of `playground.ini`, `~/.aws/credentials`;
* a well-known token format: AWS access key id, private key, GitHub or Slack token, Google API key, JWT (a Confluent license for example), Azure storage account key.

```text
🔐 connect-connect-aws-s3-sink/s3-sink-repro-123456-dlq.sh:42 contains the value of AWS_SECRET_ACCESS_KEY
❌ 1 secret finding(s): remove them (use ${VAR} instead of the value), or use --force if they are not real secrets
```

Email addresses, public IP addresses and hard-coded passwords that do not come from the base example are reported as possible customer data, without stopping the export. Values are never printed.

> [!WARNING]
> A reproduction model must never contain customer data. The scan is a safety net, not a review: check the findings, and anonymize the data (topic names, hostnames, records) before you share a bundle.

#### 📎 Files outside the repository (`--include-artifacts`)

Some models need files that are not in the repository:

* the connector zip or jar the model ran with (`--connector-zip`, `--connector-jar`);
* a file the script reads by absolute path, like `~/Downloads/customer-config.json`.

By default, export only lists them:

```text
📎 connect-connect-aws-s3-sink/s3-sink-repro-123456-dlq.sh uses /Users/me/Downloads/kafka-connect-s3-10.6.0-SNAPSHOT.zip, which is outside the repository and not in the bundle: use --include-artifacts to add it
```

With `--include-artifacts`, they are packed under `<model folder>/artifacts/` and scanned like the other files. On import, the run line, the script and the compose files are changed to point to the imported copies. Your hidden home folders (`~/.aws`, `~/.ssh`…) and `/tmp` files are never packed.

### 📥 Import

```bash
# what would be imported, and what would conflict with your files
playground repro import -f ~/Downloads/playground_repro_s3-sink-repro-123456-dlq_2026-10-21.tgz --dry-run

playground repro import -f ~/Downloads/playground_repro_s3-sink-repro-123456-dlq_2026-10-21.tgz
```

Any file name works (`playground_repro_export (1).tgz` too), and <kbd>Tab</kbd> completion lists the bundles found in your `folder_zip_or_jar` folders. The import:

* extracts the bundle in a temporary folder first, and refuses it if it contains absolute paths, `..`, special files, or a file whose sha256 does not match the manifest;
* restores the symlinks to the example when your copy of the example file is identical;
* changes the paths of the exporter's machine into yours, e.g. the jar path that [`--custom-smt`](/reusables?id=with-custom-smt-custom-smt) writes into the script;
* makes the model the current one;
* prints the `playground run` line to use, and the credentials missing from your [`playground secrets`](/playground%20secrets) profile:

```text
▶️  playground run -f /path/to/kafka-docker-playground/reproduction-models/connect-connect-aws-s3-sink/s3-sink-repro-123456-dlq.sh --tag=8.1.0 --connector-tag=10.6.0
   🔑 calls handle_aws_credentials, make sure the matching credentials are set up
```

Files identical to yours are skipped. When a file differs from your copy, nothing is imported unless you choose with `--on-conflict`:

| `--on-conflict` | what happens |
| --- | --- |
| `abort` (default) | nothing is imported, the differing files are listed |
| `rename` | the differing files are imported with an `-imported-<date>` suffix and yours are kept; the imported script refers to the renamed files |
| `overwrite` | your copy is replaced |

> [!TIP]
> Bundles created by older versions of the playground (`playground_repro_export.tgz`, without manifest) can still be imported: they have no run line and their files cannot be verified.

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

## 🧪 Testing SMTs

[playground connector smt test](https://kafka-docker-playground.io/#/playground%20connector%20smt%20test) runs a chain of Single Message Transforms (SMTs) on one record and shows what each transform does to it, in a few seconds. No topic or connector is created, and the connector is not updated. You see, step by step:

* what changes: topic, partition, timestamp, key, headers (with their types), the value field by field, and the schema
* each predicate and its result, including `negate`: a skipped transform is shown as skipped
* a dropped record (a transform returned `null`, for example `Filter`)
* the transform that fails, with its config and its error (`--verbose` adds the stack trace)
* where each transform class comes from (`from`): the plugin and its version, or the Kafka version of the worker. A warning appears when another copy of the class is on the plugin path

The chain runs in a small harness inside the `connect` container, with the classpath and the `plugin.path` of the worker. The transforms, predicates and converters are the same classes and versions as in the worker.

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

> [!TIP]
> The [connect-testing-smt-filestream-sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-testing-smt-filestream-sink) example shows every way to use the command, with a ready-to-use record and chain: `playground run -f testing-smt.sh`

### The record

`--record` is a JSON object (or `@file`), all fields optional. Without it, the record is `{"topic": <first topic of the connector or test-topic>, "key": "k1", "value": {"id": 1, "name": "foo"}}`.

| Field | Content |
| --- | --- |
| `topic`, `partition`, `offset`, `timestamp` | where the record comes from |
| `key`, `value` | schemaless JSON, `null` for a tombstone, or the `{"schema": ..., "payload": ...}` envelope of the `JsonConverter` for a value with a schema (a `Struct`) |
| `headers` | an object (`{"source": "crm", "retries": 3}`), or an array to repeat a key (`[{"key": "trace", "value": "a"}, {"key": "trace", "value": "b"}]`). Types follow the JSON value: `STRING`, `BOOLEAN`, `INT64`, `FLOAT64`, schemaless for an object |

A value with a schema:

```json
{
  "topic": "customers",
  "key": "c-42",
  "value": {
    "schema": {
      "type": "struct",
      "name": "Customer",
      "fields": [
        { "field": "customer_id", "type": "string" },
        { "field": "email", "type": "string" }
      ]
    },
    "payload": { "customer_id": "42", "email": "john@example.com" }
  },
  "headers": { "source": "crm" }
}
```

To test a real record instead, use `--from-topic <topic> --offset <n> [--partition <p>]`. The record is read from Kafka and converted with the key, value and header converters of the connector (or of the worker), with Schema Registry when they use it.

The record is a `SinkRecord` by default. Use `--type source` for the transforms of a source connector: some transforms only accept one kind of record. For example, `InsertField` with `offset.field` fails on a source record with `Only SinkRecord supported for [field insertion]`, as in a real source connector.

### The result

The terminal shows one block per step (✅ applied, ⏭️ skipped by its predicate, ➖ no change, 🗑️ dropped, ❌ failed), then the final record. An HTML report is also written to `/tmp/playground-smt-test/`, and opened in the browser when the command runs in an interactive terminal (`--no-open` to only write it). The report contains:

* the chain at the top, one badge per step
* one card per step: class, origin, config, predicate, then the topic, key, header and value changes (added, changed, removed), and the schema diff
* the error and its stack trace for a failing step
* a final record card: what the sink connector receives, or what the source connector sends to Kafka

![playground connector smt test report](./images/report-smt-test.jpg)

With `--json`, the steps are printed as JSON for scripts. The command exits with `1` when a transform fails (a dropped record is not an error):

```bash
playground connector smt test --json --config @transforms.json --record @record.json \
  | jq -e '[.steps[] | select(.record)] | last | .record.value | fromjson | .email_address == "john@example.com"'
```

### Another CP version

`--cp-version` (repeat the flag) runs the same chain in throwaway `cp-server-connect` containers of those versions, to see whether an upgrade changes what the transforms do. The summary and the report compare the final record of each version. It also works without a running example, with `--config`:

```bash
playground connector smt test --connector filestream-sink --from-topic filestream --offset 0 --cp-version 7.9.0 --cp-version 8.3.2
```

![playground connector smt test report comparing CP versions](./images/report-smt-test-cp-versions.jpg)

### SMTs that are not in the worker

The SMTs shipped with Kafka and the plugins on the `plugin.path` of the worker are available. To test others, without changing the worker:

```bash
# a Confluent Hub plugin (or another version than the one installed), installed for the test only and cached in ~/.playground-smt-tester
playground connector smt test --connector my-sink --smt-plugin confluentinc/connect-transforms:1.4.4

# your own build: repeat --smt-jar for the jars it depends on, they are loaded together as one plugin
playground connector smt test --config @transforms.json --smt-jar target/my-smt-1.0.0.jar --smt-jar lib/its-dependency.jar
```

These plugins take precedence over a copy of the same transform on the plugin path of the worker.

> [!NOTE]
> Self-managed connectors only: the transforms of a fully managed connector run in Confluent Cloud (give its config with `--config` for an indicative result on a self-managed worker). The cfk environment is not supported yet. The chain runs outside of a connector task, so `errors.tolerance` and the dead letter queue do not apply: a failing transform is reported as failing.

## 🧙 How to install other connectors

Simplest option is to create a reproduction model with `playground repro bootstrap` [command](/playground%20repro%20bootstrap) and then select "🔌 Add connector plugin" (you can call it multiple times to add multiple connector plugins/SMT) 

<img width="774" height="285" alt="CleanShot 2026-01-13 at 14 42 46" src="https://github.com/user-attachments/assets/e1489b80-8d01-48c2-906a-b359230104e8" />

it has interactive selection from confluent hub:

<img width="966" height="512" alt="CleanShot 2026-01-13 at 14 43 09" src="https://github.com/user-attachments/assets/a36e909a-4104-47c7-9637-31a902976141" />

It will automatically add the plugin(s) to the list of `CONNECT_PLUGIN_PATH`:

Example with S3 source and S3 sink:

```yml
services:
  connect:
    environment:
      CONNECT_PLUGIN_PATH: /usr/share/confluent-hub-components/confluentinc-kafka-connect-s3-source,/usr/share/confluent-hub-components/confluentinc-kafka-connect-s3
```

Example with [confluentinc/connect-transforms](https://www.confluent.io/hub/confluentinc/connect-transforms) SMT:

```yml
services:
  connect:
    environment:
      CONNECT_PLUGIN_PATH: /usr/share/confluent-hub-components/confluentinc-kafka-connect-s3-source,/usr/share/confluent-hub-components/confluentinc-connect-transforms
```

It can also be done non-interactively with `--connector-plugin` (repeatable):

```bash
playground repro bootstrap -f s3-sink<tab> --description "s3 sink with transforms" --connector-plugin confluentinc/connect-transforms
```

> [!TIP]
> You can also specify versions when specifying multiple connector/SMT, see [here](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%94%97-for-connectors).


## 🐛 Debugging tools

### ✨ Remote debugging

Java Remote debugging is the perfect tool for troubleshooting Kafka connectors for example.

> [!TIP]
> Following are instructions for [Visual Studio Code ](https://code.visualstudio.com/docs/java/java-debugging), but it is exactly the same principle for [IntelliJ IDEA](https://www.jetbrains.com/help/idea/tutorial-remote-debug.html#436b3b68).

#### ☑️ Prerequisites

Make sure you have already the required Visual Studio code extensions by following [this](https://code.visualstudio.com/docs/java/java-debugging#_install).

#### 💫 Full example

Here is a full example using [HDFS 2 sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-hdfs2-sink) connector and [Visual Studio Code ](https://code.visualstudio.com/docs/java/java-debugging):

1. Launch the example as usual, i.e start `./hdfs2-sink.sh`.

2. Clone and open [`confluentinc/kafka-connect-hdfs`](https://github.com/confluentinc/kafka-connect-hdfs) repository in Visual Studio Code.

3. Switch to the branch corresponding to the connector version you're going to run. 
 
In this example, the connector version is `10.1.1`, so switch to branch tag `v10.1.1` (use the version you are actually running, see `playground connector versions`):

![remote_debugging](./images/remote_debugging2.jpg)

4. Remote debugging is enabled by default on the `connect` container (port `5005`), so there is nothing to do for connectors.

For other containers (for example `broker` or `schema-registry`), use [🧠 CLI](/cli) with `enable-remote-debugging` [command](/playground%20debug%20enable-remote-debugging):

```bash
$ playground debug enable-remote-debugging -c broker
```

It sets `KAFKA_DEBUG` and `JAVA_DEBUG_OPTS` environment variables on the container (using `playground container set-environment-variables`) and displays the configuration to add in `.vscode/launch.json`.

5. [Configure](https://code.visualstudio.com/docs/java/java-debugging#_configure) remote debugging by clicking on menu `Run`->`Add Configuration...`:

![remote_debugging](./images/remote_debugging1.jpg)

Then copy/paste the following entry:

```json
{
    "type": "java",
    "name": "Debug connect container",
    "request": "attach",
    "hostName": "127.0.0.1",
    "port": 5005,
    "timeout": 30000
}
```

Note: you can also directly edit file `.vscode/launch.json`:

```json
{
    "version": "0.2.0",
    "configurations": [
    
        {
            "type": "java",
            "name": "Debug connect container",
            "request": "attach",
            "hostName": "127.0.0.1",
            "port": 5005,
            "timeout": 30000
        }
    ]
}
```

*Example:*

![remote_debugging](./images/remote_debugging3.jpg)

6. Go in `Run and Debug` and make sure to select the `Debug connect container` config:

![remote_debugging](./images/remote_debugging5.jpg)

7. Click on the green play button

![remote_debugging](./images/remote_debugging6.jpg)

8. Add breakpoint(s) where you want, for example [here](https://github.com/confluentinc/kafka-connect-hdfs/blob/9a5e68d7294a79c40050efd7b51d7428c7f7c4d5/src/main/java/io/confluent/connect/hdfs/TopicPartitionWriter.java#L894):

![remote_debugging](./images/remote_debugging4.jpg)

9. Process some messages:

```bash
playground topic produce -t test_hdfs --nb-messages 10 << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {"name": "f1", "type": "string"}
  ]
}
EOF
```

10. See results 🍿:

![remote_debugging](./images/remote_debugging7.jpg)

![remote_debugging](https://github.com/vdesabou/gifs/raw/master/docs/images/remote_debugging.gif)


Note (*for Confluent employees because control center code is proprietary*): for `control-center`, you can use following override (note the `5006` port in order to avoid clash with `connect` port):

```yml
  control-center:
    ports:
      - "9021:9021"
      - "5006:5006"
    environment:
      CONTROL_CENTER_OPTS: "-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=0.0.0.0:5006"
```

### 🔗 Connectors

In order to enable `TRACE`(or `DEBUG`) logs for connectors, use the `admin/loggers` endpoint (see docs [here](https://docs.confluent.io/platform/current/connect/logging.html#change-the-log-level-for-a-specific-logger)):

*Example:*

```bash
curl --request PUT \
  --url http://localhost:8083/admin/loggers/io.confluent.connect.oracle.cdc \
  --header 'Accept: application/json' \
  --header 'Content-Type: application/json' \
  --data '{
	"level": "TRACE"
}'
```

> [!WARNING]
> Make sure to update `io.confluent.connect.oracle.cdc` above with the package you want to troubleshoot.

Useful packages:

* `io.confluent.kafka.schemaregistry.client.rest.RestService`: to track schema registry requests
* `org.apache.kafka.connect.runtime.TransformationChain`: to see records before, during and after SMT

Or just use [CLI](/playground%20connector%20log-level) `playground connector log-level` 

To have the levels set before the example creates its connector (so that the first lines are already at `TRACE`), use `--connect-log-level` option of [playground run](/playground%20run), with the same syntax as `CONNECT_LOG4J_LOGGERS` (levels `INFO`, `WARN`, `DEBUG` or `TRACE`). In the menu, 🔊 Connect log level(s) suggests the packages of the example's connector:

```bash
playground run -f s3-sink<tab> --connect-log-level "io.confluent.connect.s3=TRACE,org.apache.kafka.connect.runtime.WorkerSinkTask=DEBUG"
```

Example:

```bash
playground connector log-level --level TRACE
```

### 🔑 SSL debug

> [!NOTE]
> The default `connect` service already sets `KAFKA_OPTS: -Ddynamic.worker.config.file=/dev/null` (see [`environment/plaintext/docker-compose.yml`](https://github.com/vdesabou/kafka-docker-playground/blob/master/environment/plaintext/docker-compose.yml)), so keep it when you override `KAFKA_OPTS` in the snippets below.

Add `-Djavax.net.debug=all` in your `docker-compose` file:

*Example:*

```yml
  connect:
    environment:
      KAFKA_OPTS: -Ddynamic.worker.config.file=/dev/null -Djavax.net.debug=all
```

Use `-Djavax.net.debug=ssl:handshake` instead of `-Djavax.net.debug=all` to only see the handshake.

Or just use [CLI](/playground%20debug%20java-debug) `playground debug java-debug` with `--type ssl_all` or `--type ssl_handshake`.

### 🔒 Kerberos debug

Add `-Dsun.security.krb5.debug=true` in your `docker-compose` file:

*Example:*

```yml
  connect:
    environment:
      KAFKA_OPTS: -Ddynamic.worker.config.file=/dev/null -Dsun.security.krb5.debug=true
```

Or just use [CLI](/playground%20debug%20java-debug) `playground debug java-debug` with `--type kerberos`.

### 🔬 Class loading

Add `-verbose:class` in your `docker-compose` file to troubleshoot a `ClassNotFoundException` for example:

*Example:*

```yml
  connect:
    environment:
      KAFKA_OPTS: -Ddynamic.worker.config.file=/dev/null -verbose:class
```

Or just use [CLI](/playground%20debug%20java-debug) `playground debug java-debug` with `--type class_loading`.

In logs, you'll see:

```log
[Loaded org.apache.kafka.connect.runtime.isolation.DelegatingClassLoader$$Lambda$20/1007251739 from org.apache.kafka.connect.runtime.isolation.DelegatingClassLoader]
[Loaded java.lang.invoke.LambdaForm$MH/1556595366 from java.lang.invoke.LambdaForm]
[Loaded org.reflections.util.ConfigurationBuilder from file:/usr/share/java/kafka/reflections-0.9.12.jar]
[Loaded org.reflections.serializers.Serializer from file:/usr/share/java/kafka/reflections-0.9.12.jar]
[Loaded org.reflections.adapters.MetadataAdapter from file:/usr/share/java/kafka/reflections-0.9.12.jar]
[Loaded org.reflections.scanners.Scanner from file:/usr/share/java/kafka/reflections-0.9.12.jar]
[Loaded org.reflections.scanners.AbstractScanner from file:/usr/share/java/kafka/reflections-0.9.12.jar]
[Loaded org.reflections.scanners.TypeAnnotationsScanner from file:/usr/share/java/kafka/reflections-0.9.12.jar]
[Loaded org.reflections.scanners.AbstractScanner$$Lambda$21/1725097945 from org.reflections.scanners.AbstractScanner]
[Loaded org.reflections.scanners.SubTypesScanner from file:/usr/share/java/kafka/reflections-0.9.12.jar]
[Loaded org.reflections.util.FilterBuilder from file:/usr/share/java/kafka/reflections-0.9.12.jar]
[Loaded org.reflections.util.FilterBuilder$Matcher from file:/usr/share/java/kafka/reflections-0.9.12.jar]
```

### 🕸️ Debug ServiceNow or Salesforce

Those connectors use low level [com.google.api.client.http](https://developers.google.com/api-client-library/java) library.

In order to activate debug logs to see requests/responses, you can just add the `volumes` mount with existing `../../connect/connect-servicenow-source/nginx-proxy/logging.properties` file and add `KAFKA_OPTS: -Djava.util.logging.config.file=/tmp/logging.properties`:

Example:

```yml
  connect:
    volumes:
      - ../../connect/connect-servicenow-source/nginx-proxy/logging.properties:/tmp/logging.properties
    environment:
      KAFKA_OPTS: -Ddynamic.worker.config.file=/dev/null -Djava.util.logging.config.file=/tmp/logging.properties
```

This is how the `logging.properties` looks like:

```bash
$ cat /tmp/logging.properties
handlers=java.util.logging.ConsoleHandler
java.util.logging.ConsoleHandler.level=ALL
com.google.api.client.http.level=ALL
```

### 🌍 Debug HTTP sink

This connector uses low level [Apache HTTP client](https://hc.apache.org/httpcomponents-client-5.2.x/) library.

In order to activate debug logs to see requests/responses, you can add `jcl-over-slf4j-2.0.7.jar` to the connector `lib` folder before starting the environment.

Example (from [`http_basic_auth.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-http-sink/http_basic_auth.sh)):

```bash
cd ../../connect/connect-http-sink/
if [ ! -f jcl-over-slf4j-2.0.7.jar ]
then
     wget -q https://repo1.maven.org/maven2/org/slf4j/jcl-over-slf4j/2.0.7/jcl-over-slf4j-2.0.7.jar
fi
mkdir -p ../../confluent-hub/confluentinc-kafka-connect-http/lib/
cp jcl-over-slf4j-2.0.7.jar ../../confluent-hub/confluentinc-kafka-connect-http/lib/jcl-over-slf4j-2.0.7.jar
cd -
```

> [!NOTE]
> It is already set in all HTTP sink examples.

Then you can enable TRACE logs on `org.apache.http`:

```bash
$ playground debug log-level set --package "org.apache.http" --level TRACE
```

### 🕵️‍♂️ See TLS traffic with mitmproxy

[mitmproxy](https://github.com/mitmproxy/mitmproxy) 

1. Add `mitmproxy` container in your `docker-compose` file:

```yml
  mitmproxy:
    image: mitmproxy/mitmproxy
    hostname: mitmproxy
    container_name: mitmproxy
    command: mitmdump --flow-detail 4
    ports:
      - "8080:8080"
    volumes:
      - $HOME/.mitmproxy:/home/mitmproxy/.mitmproxy
```

2. Add in your script after all containers are started:

```bash
playground container cp --source $HOME/.mitmproxy/mitmproxy-ca-cert.pem --destination connect:/tmp/mitmproxy-ca-cert.pem
playground container exec -c connect --root --command "cat /tmp/mitmproxy-ca-cert.pem >> /etc/ssl/certs/ca-bundle.crt"
playground container exec -c connect --root --command "keytool -importcert --cacerts -storepass changeit -noprompt -alias mitmproxy -file /tmp/mitmproxy-ca-cert.pem"
```

3. Use mitmproxy proxy in your connector config:

Example:

```json
"proxy.url": "mitmproxy:8080"
```

4. Check TLS traffic in clear text by checking logs of `mitmproxy` container

```bash
playground container logs -c mitmproxy

or

playground container logs --open --container mitmproxy
```

### 🕵 TCP Dump

When logs are not enough to understand a connectivity problem (connection resets, timeouts, TLS handshake failures, a client talking to the wrong host or port, unexpected retries…), capturing the network traffic of a container shows exactly what goes over the wire.

Just use [CLI](/playground%20debug%20tcp-dump) `playground debug tcp-dump`. It runs `tcpdump` from the `nicolaka/netshoot` image in the network namespace of the container (nothing is installed in the container, so it works with any image), captures the traffic for `--duration` (default 30s, all ports unless `--port` or `--filter` is set), copies the `.pcap` file to `--output-dir` (default: current folder), analyzes it with [`playground analyze tcp-dump`](/playground%20analyze%20tcp-dump) (refused and reset connections, retransmissions, TLS alerts, DNS errors, Kafka and HTTP errors and response times, the bodies of the HTTP error responses, with container names instead of ip addresses, in a text digest and an HTML report), then opens it with [Wireshark](https://www.wireshark.org/) if it is installed. Start it, then reproduce the issue while the capture is running: Ctrl+C stops it earlier and keeps the capture.

With several `--container`, the captures run at the same time, so both sides of a connection can be compared. For a window of any length, use `--action start`, reproduce, then `--action stop`.

> [!NOTE]
> On an encrypted listener (SSL, SASL_SSL) you will see the TCP connections and the TLS handshake, but not the content of the requests. To read HTTPS traffic in clear text, use [mitmproxy](/reusables?id=%f0%9f%95%b5%ef%b8%8f%e2%99%82%ef%b8%8f-see-tls-traffic-with-mitmproxy) instead.

```bash
playground debug tcp-dump --container control-center --port 9021 --duration 60
playground debug tcp-dump -c connect -c broker --port 9092 --duration 2m
playground debug tcp-dump -c connect --filter "host postgres" --action start
playground debug tcp-dump -c connect --action stop
playground analyze tcp-dump -f customer.pcapng          # a capture a customer sent
```

### 👻 Heap Dump

A [heap dump](https://www.baeldung.com/java-heap-dump-capture) is a snapshot of all the objects in the JVM memory. Take one when a component uses more and more memory, spends its time in garbage collection or fails with `java.lang.OutOfMemoryError`, to find which objects (and which connector, task or client) hold the memory.

Just use [CLI](/playground%20debug%20heap-dump) `playground debug heap-dump`. It saves output to a `.hprof` file that can be read with [VisualVM](https://visualvm.github.io/) or [MAT](https://www.eclipse.org/mat/), or analyzed with [`playground analyze heap-dump`](/playground%20analyze%20heap-dump) (Eclipse MAT leak suspects and an HTML report, see [Analyze what you collected](/reusables?id=%f0%9f%94%8e-analyze-what-you-collected)).

```bash
playground debug heap-dump
playground debug heap-dump -c connect -c broker
playground debug heap-dump --container schema-registry --live
```

You can also set `-XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/tmp` to generate heap dump automatically when hitting OOM:

Example:

```yml
  connect:
    environment:
      KAFKA_OPTS: -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/tmp
      KAFKA_HEAP_OPTS: " -Xms2G -Xmx4G"
```

### 🎯 Thread Dump

A [Java thread dump](https://www.baeldung.com/java-thread-dump) shows what every thread of the JVM is doing at that moment, with its stack trace and the locks it holds or waits for. Take one when a connector or task looks stuck (no progress, no error in the logs), when a rebalance or shutdown never completes, or when a container uses a lot of CPU. Take several a few seconds apart: a thread that stays on the same stack is the one to look at.

Just use [CLI](/playground%20debug%20thread-dump) `playground debug thread-dump`. It saves output to a file and opens it with the editor set with `playground config editor`.

```bash
playground debug thread-dump
playground debug thread-dump -c connect -c broker
```
Analyze the dumps with [`playground analyze thread-dump`](/playground%20analyze%20thread-dump): deadlocks, lock contention, stuck and CPU-hungry threads (it can also take the dumps itself with `--container`).

### 🛩️ Flight Recorder

[Java Flight Recorder](https://www.baeldung.com/java-flight-recorder-monitoring) (JFR) records what happens in the JVM over a period of time with a low overhead: CPU usage per method, memory allocations, garbage collections, lock contention, file and socket I/O. Use it for performance problems (slow throughput, latency spikes, high CPU) where a single thread or heap dump is not enough.

Just use [CLI](/playground%20debug%20flight-recorder) `playground debug flight-recorder`: start the recording, reproduce the issue, then stop it. Stopping copies the `.jfr` file to the current directory (or `--output-dir`) and analyzes it with [`playground analyze flight-recorder`](/playground%20analyze%20flight-recorder): where the time of the connector tasks goes, with findings (see [Analyze what you collected](/reusables?id=%f0%9f%94%8e-analyze-what-you-collected)). Open the `.jfr` with [JDK Mission Control](https://jdk.java.net/jmc/) for the details.

```bash
playground debug flight-recorder --action start
# reproduce the issue
playground debug flight-recorder --action status
playground debug flight-recorder --action stop                     # copies the .jfr and analyzes it (--no-analyze to skip)
playground debug flight-recorder -c connect -c connect2 --action start --settings profile
```

The recording is driven over JMX (`FlightRecorderMXBean`): the Confluent images ship a JRE without `jcmd`, and nothing is installed or restarted. `jcmd` is only used for containers without a JMX port (cfk pods), when the image has it.

`--settings` chooses what is recorded:

| Settings | Records | Overhead |
|---|---|---|
| `playground` (default) | what `playground analyze flight-recorder` needs: CPU per thread every second, execution and native samples, socket, file, lock and park events of 1 ms or more, allocation samples, GC, exceptions | low |
| `profile` / `default` | the settings shipped with the JDK | about 2% / 1% |
| `all` | every event, with no threshold, for a deep dive in JDK Mission Control | high |

> [!TIP]
> To record for a fixed time and analyze in one command: `playground analyze flight-recorder -c connect --duration 2m`. On JDK 25+ (cp 8.3.2), `--trace-method <Class::method>` also records every call of a method with its duration and caller. During a benchmark, [playground connector benchmark](/reusables?id=%e2%8f%b1%ef%b8%8f-benchmark-a-connector) records the workers on its own.

### 🧰 More debug commands

| Command | Description |
|---|---|
| [`playground debug java-debug`](/playground%20debug%20java-debug) | 🤎 JVM arguments for SSL, Kerberos or Class Loading |
| [`playground debug generate-diagnostics`](/playground%20debug%20generate-diagnostics) | ⛑️ Generate a diagnostic bundle with Diagnostics Bundle Tool |
| [`playground debug jscissors`](/playground%20debug%20jscissors) | ✂️ Trace the calls of any method of a running JVM, without restart: arguments, return values, durations, exceptions, call tree, analyzed on `--action stop` (see the [deep dive](/deep-dive-jvm-diagnostics?id=_6-jscissors-what-the-code-does-call-by-call)) |
| [`playground debug testssl`](/playground%20debug%20testssl) | 🔐 Test TLS/SSL encryption using [testssl.sh](https://testssl.sh/) |
| [`playground debug disable-remote-debugging`](/playground%20debug%20disable-remote-debugging) | Disable java remote debugging for a container |

## 🔎 Analyze what you collected

The [`playground analyze`](/playground%20analyze) commands turn a dump, a log, a bundle or a report (yours, or one a
customer sent) into findings: what is wrong, with the evidence, and what to do. They all work offline, and
**`--sample <name>`** runs them on the samples shipped with the playground, to see what they report before using them on
real data.

| Command | Analyzes | Try it |
|---|---|---|
| [`playground analyze thread-dump`](/playground%20analyze%20thread-dump) | 🧵 thread dumps: deadlocks, lock contention, stuck and CPU-hungry threads | `--sample deadlock_jdk21` |
| [`playground analyze gc-logs`](/playground%20analyze%20gc-logs) | 📈 GC logs: pauses, failures, live set, leak trend | `--sample jdk21_g1_kafka_real` |
| [`playground analyze heap-dump`](/playground%20analyze%20heap-dump) | 🔬 heap dumps with Eclipse MAT: leak suspects, retained sizes, growth between two dumps, Kafka-aware hints (producer and fetch buffers, records held by the tasks…) | `--sample leak_growth` |
| [`playground analyze logs`](/playground%20analyze%20logs) | 🔥 ERROR/FATAL digest of log files, folders, zip / tar bundles: known causes, timeline, root causes, every distinct record | `--sample support_bundle` |
| [`playground analyze oracle-xstream-report`](/playground%20analyze%20oracle-xstream-report) | 🅾️ Oracle XStream CDC diagnostics reports (`orclcdc_diag.sql`) | `--sample synthetic_failures` |
| [`playground analyze cfk-bundle`](/playground%20analyze%20cfk-bundle) | 📦 CFK support bundles: pods, events, custom resources, logs | `--sample synthetic` |
| [`playground analyze flight-recorder`](/playground%20analyze%20flight-recorder) | 🛩️ Java Flight Recorder recordings: where the time of the connector tasks goes (network I/O by remote, Kafka client, locks, CPU by layer, hot methods) | `--sample jdbc_postgres_sink` |
| [`playground analyze jscissors`](/playground%20analyze%20jscissors) | ✂️ traces of `playground debug jscissors`: methods by total time, exceptions with the arguments of the failing call, calls still running (hangs), slowest calls, call trees | `--sample filestream_sink_bad_json` |
| [`playground analyze tcp-dump`](/playground%20analyze%20tcp-dump) | 🦈 network captures (`.pcap`, `.pcapng`): refused and reset connections, retransmissions, TLS alerts, DNS errors, Kafka and HTTP errors and response times, with the bodies of the HTTP error responses | `--sample kafka_and_network_errors`, `--sample http_errors` |

```bash
playground analyze thread-dump --sample deadlock_jdk21
playground analyze thread-dump --container connect                 # 3 dumps of the running connect worker
playground analyze logs --file ./customer-logs.zip
playground analyze heap-dump --file heap-dump-connect-2026-10-14.hprof
playground analyze flight-recorder --container connect --duration 60s --connector my-sink   # records connect over JMX, then analyzes
```

Besides the text digest, they write a self-contained HTML report to share in a case (opened in your browser), and most
of them accept `--json` for scripts and agents. Each report starts with a one-line verdict (🚨 critical findings and
where to start, ⚠️ things to look at, or ✅ nothing alarming), followed by the findings with their severity (🔴 critical,
🟠 high, 🟡 medium, 🟢 low, ℹ️ info).

The reports of the samples:

<!-- tabs:start -->

#### **🧵 thread-dump**

```bash
playground analyze thread-dump --sample deadlock_jdk21
```

![playground analyze thread-dump report](./images/report-thread-dump.jpg)

#### **📈 gc-logs**

```bash
playground analyze gc-logs --sample jdk21_g1_kafka_real
```

![playground analyze gc-logs report](./images/report-gc-logs.jpg)

#### **🔬 heap-dump**

```bash
playground analyze heap-dump --sample leak_growth
```

![playground analyze heap-dump report](./images/report-heap-dump.jpg)

#### **🅾️ oracle-xstream-report**

```bash
playground analyze oracle-xstream-report --sample synthetic_failures
```

![playground analyze oracle-xstream-report report](./images/report-oracle-xstream-report.jpg)

#### **📦 cfk-bundle**

```bash
playground analyze cfk-bundle --sample synthetic
```

![playground analyze cfk-bundle report](./images/report-cfk-bundle.jpg)

#### **🛩️ flight-recorder**

```bash
playground analyze flight-recorder --sample jdbc_postgres_sink
```

![playground analyze flight-recorder report](./images/report-flight-recorder.jpg)

#### **🦈 tcp-dump**

```bash
playground analyze tcp-dump --sample kafka_and_network_errors
playground analyze tcp-dump --sample http_errors
```

![playground analyze tcp-dump report](./images/report-tcp-dump.jpg)

<!-- tabs:end -->

#### 🛩️ What `analyze flight-recorder` reports

It reads `.jfr` files of JDK 11+ JVMs with the flight recorder API of the JDK, run in an `eclipse-temurin:25-jdk`
container (pulled the first time), and looks at the Kafka Connect task threads (`task-thread-*`, `--connector` for one
connector, `--threads` for any regex; every thread when none matches):

| Section | Content |
|---|---|
| Findings | one sentence, a number and a next step: the tasks wait on a remote system, on the Kafka consumer fetch or the producer, on a lock, sleep; they are CPU bound; conversion, logging or SMTs take the CPU; the JVM was still compiling code (JIT); allocation, exceptions, long GC pauses |
| Task thread time, by state | share of the recording each task thread spent running, blocked on network I/O, in the Kafka client, on locks, waiting, on file I/O |
| CPU of the task threads, by layer | execution samples classified by their first frame outside the JDK: connector, converters (serialization), SMTs, Kafka client, connect framework, libraries (drivers, SDKs), logging, JDK |
| Hot methods | the methods the task threads run, with a link to the source of the connector when its manifest has one |
| Network I/O, allocation, locks and waits, busiest threads | by remote host, class, site and thread |

Recordings made with the `playground` settings (benchmark, `debug flight-recorder`, `analyze flight-recorder
--container`) give the most details; a recording made with the JDK settings works too, with throttled socket events and
10 or 20 ms thresholds.

## 👤 Fully managed connectors with a service account

By default the fully managed connector examples (`ccloud/fm-*`) use `"kafka.auth.mode": "KAFKA_API_KEY"`, with an API key that can do anything on the cluster. Customers often run them with a [service account](https://docs.confluent.io/cloud/current/connectors/service-account.html) and the least ACLs instead, and that is where a missing ACL or a missing Assigner role shows up.

The `--ccloud-service-account` option of [playground run](/playground%20run) (also a toggle in the run menu) runs any fully managed or custom connector example that way, without changing the example:

```bash
playground run -f ccloud/fm-datagen-source/fully-managed-datagen-source.sh --ccloud-service-account
```

For each connector, [playground connector create-or-update](/playground%20connector%20create-or-update):

* creates a service account `pg-<user>-conn-<connector>-<n>`
* creates the ACLs listed in the documentation, derived from the connector config: `DESCRIBE` on the cluster, the topics of a sink and its `connect-lcc-` consumer group, the dead letter queue, the success and error topics (HTTP, Lambda, Azure Functions…), the output topics or topic prefix of a source, and the internal topics of the JDBC, Debezium (legacy and v2), Oracle CDC and XStream connectors, plus the exactly-once ones when it is enabled
* grants the Assigner role on the service account to the owner of `CONFLUENT_CLOUD_API_KEY` (the principal creating the connector must hold it)
* replaces `kafka.api.key` / `kafka.api.secret` with `"kafka.auth.mode": "SERVICE_ACCOUNT"` and `"kafka.service.account.id"`

Each `confluent` command is logged, ready to be copied, for example:

```
💻 confluent kafka acl create --service-account sa-o2k1pno --operations create,write --allow --topic datagen_pageviews --environment env-519yzz --cluster lkc-ng7qn3
```

The service account and its ACLs are deleted with the connector (`playground connector delete`, the cleanup at the end of the run, [playground cleanup-cloud-resources](/playground%20cleanup-cloud-resources)).

| Option (run menu entry) | What it does |
| --- | --- |
| `--ccloud-service-account-acls docs` (🚦 Service account ACLs) | the ACLs of the documentation (default) |
| `--ccloud-service-account-acls full` | every operation on every topic, group and transactional id: for a connector whose internal topics are not known, or to check that the ACLs are the problem |
| `--ccloud-service-account-acls none` | no ACL at all, add them one by one |
| `--ccloud-service-account-id sa-xxxxx` (🪪 Existing service account) | use an existing service account (for example one set up like the customer's), as is: no ACL created nor deleted |
| `PG_CCLOUD_SERVICE_ACCOUNT_ACL_EXCLUDE="<regex>"` | do not create the ACLs matching the regex, matched on `<OPERATION> <ResourceType>:<name> [prefix]` (e.g. `"READ Group:"`) |

In the run menu, tick *👤 Connector service account* in the options:

![playground run menu: Connector service account toggle](./images/run_menu_ccloud_service_account.png)

Two entries then appear in the confluent cloud section, to pick the ACLs and an existing service account:

![playground run menu: service account entries](./images/run_menu_ccloud_service_account_entries.png)

![playground run menu: service account ACLs](./images/run_menu_ccloud_service_account_acls.png)

### 🚦 Reproduce an authorization error

Once the connector runs, [playground rbac acl](/playground%20rbac%20acl) changes the ACLs of its service account: on a Confluent Cloud run it manages the ACLs of the Confluent Cloud cluster, and `--connector` uses the service account of the connector as principal. Delete an ACL, or add a `--deny` one (deleting it restores the setup), then restart the connector:

```bash
playground rbac acl list   --connector DatagenSource_$USER
playground rbac acl delete --connector DatagenSource_$USER --operation WRITE --resource Topic:datagen_pageviews
playground rbac acl create --connector DatagenSource_$USER --operation DESCRIBE --resource Cluster:kafka-cluster --deny
playground connector restart --connector DatagenSource_$USER
```

The connector fails like the customer's:

```
DatagenSource_vsaboulin        ❌ FAILED   0:💪 USER_ACTIONABLE_ERROR   connector: Your kafka API key does not have the permissions required to access the configured topic
kafka.topic: Missing write permission on topic(s) "datagen_pageviews".
```

[playground connector diagnose](/playground%20connector%20diagnose) compares the ACLs of the service account with the ones of the documentation, and gives the commands to fix them:

```
🚦 service account sa-o2k1pno: ACLs of the documentation (https://docs.confluent.io/cloud/current/connectors/service-account.html)
❌ missing: WRITE Topic:datagen_pageviews
⛔ denied: DESCRIBE Cluster:kafka-cluster
   🔧 to create the missing ACLs:
   playground rbac acl create --connector DatagenSource_vsaboulin --operation WRITE --resource Topic:datagen_pageviews
   🔧 to delete the DENY ACLs:
   playground rbac acl delete --connector DatagenSource_vsaboulin --deny --operation DESCRIBE --resource Cluster:kafka-cluster
```

> An ACL change takes up to a minute to be applied in Confluent Cloud: if the connector still fails right after a fix, restart it again. Resources are `Topic:<name>`, `Group:<name>`, `TransactionalId:<name>` (add `--prefix` for a prefix) and `Cluster:kafka-cluster`.

In a reproduction model, set the variables after the `source ${DIR}/../../scripts/utils.sh` line, so that the model always runs with the customer's setup:

```bash
export PG_CCLOUD_SERVICE_ACCOUNT=true
# the customer did not grant the schema history consumer group
export PG_CCLOUD_SERVICE_ACCOUNT_ACL_EXCLUDE="READ Group:.*-schemahistory"
```

🎬 Bite size session: [A fully managed connector with a service account loses an ACL](/sessions?id=👤-a-fully-managed-connector-with-a-service-account-loses-an-acl)

## 🏗️ Fully managed connectors with Terraform

Customers often manage their fully managed connectors with Terraform. Add `--terraform` to [playground connector create-or-update](/playground%20connector%20create-or-update) to deploy the connector of any fully managed or custom connector example that way. The JSON config stays as is: it is converted to HCL for the [confluentinc/confluent](https://registry.terraform.io/providers/confluentinc/confluent/latest/docs/resources/confluent_connector) provider, then `terraform init`, `plan` and `apply` run.

```bash
playground connector create-or-update -c DatagenSource_$USER --terraform --wait << EOF
{
  "connector.class": "DatagenSource",
  "kafka.auth.mode": "KAFKA_API_KEY",
  "kafka.api.key": "$CLOUD_KEY",
  "kafka.api.secret": "$CLOUD_SECRET",
  "kafka.topic": "datagen_pageviews",
  "output.data.format": "JSON",
  "quickstart": "PAGEVIEWS",
  "tasks.max": "1"
}
EOF
```

* The keys that look like secrets (`*.secret`, `*.password`, `*.key`, `sasl.jaas.config`...) go to `config_sensitive`. Their values are masked in the output, and Terraform shows `(sensitive value)`.
* The folder of the connector (`.terraform-playground/<connector>-*`, with `connector.tf` and the state) is kept. Running the command again updates the connector in place (the plan shows what changes, for example `~ "max.interval" = "10000" -> "1000"`). A connector created without `--terraform` is imported into the state the first time.
* [playground connector delete](/playground%20connector%20delete) runs `terraform destroy` for a connector deployed with Terraform.
* `connector.tf` is plain HCL: a starting point to reproduce a customer's Terraform code.

> [!NOTE]
> It needs [terraform](https://developer.hashicorp.com/terraform/install) (`brew install hashicorp/tap/terraform`) and a Cloud API key (`CONFLUENT_CLOUD_API_KEY`, `CONFLUENT_CLOUD_API_SECRET`). `--level`, `--offsets` and `--initial-state` are not supported with `--terraform`.

🎬 Bite size session: [Deploy a fully managed connector with Terraform](/sessions?id=🏗️-deploy-a-fully-managed-connector-with-terraform)

## 🚫 Blocking traffic

To reproduce what happens when a component cannot reach another one (a broker, Schema Registry, a database or an external API going down, a firewall dropping packets), a reproduction model can block the traffic between containers or to an external host, then unblock it to check how the connector or client recovers.

Just use [CLI](/playground%20debug%20block-traffic) `playground debug block-traffic`. It uses `iptables` (installed in the container if needed) to drop the traffic from one or more containers to a destination (container name, host name or IP address), optionally on a single `--port`. Run it again with `--action stop` to restore the traffic.

```bash
playground debug block-traffic --destination google.com --action start
playground debug block-traffic --container schema-registry --destination broker --port 9092 --action start
playground debug block-traffic -c connect -c ksqldb-server --destination schema-registry --action stop
```

<a id="🐌-add-latency-packet-loss-or-corruption"></a>

## 🐌 Degrade traffic - Add latency, packet loss or corruption

Some issues only happen on a slow or unreliable network: request timeouts, retries, rebalances, producer or consumer errors. A reproduction model, or you on a running environment, can simulate them by making the traffic of a container slow or lossy, then putting it back to normal to check how the connector or client recovers.

Just use [CLI](/playground%20debug%20degrade-traffic) `playground debug degrade-traffic`. It applies [`tc netem`](https://man7.org/linux/man-pages/man8/tc-netem.8.html) to the traffic from one or more containers, to a destination (container name, host name or IP address, optionally a single `--port`), or to all their traffic when there is no `--destination`. Several effects can be combined in one call:

| Flag | Effect | Example |
| --- | --- | --- |
| `--latency` | added latency | `100ms`, `1s` |
| `--jitter` | random variation of the latency (needs `--latency`) | `20ms` |
| `--loss` | packets dropped | `1%` |
| `--corruption` | packets corrupted | `1%` |
| `--duplicate` | packets duplicated | `1%` |
| `--rate` | bandwidth limit | `1mbit`, `500kbit` |

```bash
# 100ms (± 20ms) from connect to the broker
playground debug degrade-traffic --container connect --destination broker --latency 100ms --jitter 20ms --action start

# latency and packet loss, on two containers, only for the traffic to port 9092 of the broker
playground debug degrade-traffic -c connect -c ksqldb-server --destination broker --port 9092 --latency 50ms --loss 1% --action start

# a bandwidth limit on all the traffic of connect
playground debug degrade-traffic -c connect --rate 1mbit --action start

# what is applied, and the round trip measured from connect
playground debug degrade-traffic -c connect --destination broker --action status

# back to normal
playground debug degrade-traffic -c connect --action stop
```

After `start`, `stop` and `status`, the command measures the effect from the container: the average of 4 pings, or the time of a TCP connection when `--port` is set (only that TCP traffic is degraded, not ping):

```text
🐌 Applying 100ms ± 10ms latency on container connect to broker (172.27.0.2)
⏱️ round trip from connect to broker: 101.563 ms (average of 4 pings)
```

`tc` runs from the [`nicolaka/netshoot`](https://github.com/nicolaka/netshoot) image (pulled the first time) in the network namespace of the container, or in an ephemeral container of the pod with the `cfk` environment. Nothing is installed in the container, so this works with any image: connect, broker, Schema Registry, databases…

> [!NOTE]
> * `tc` only slows down the packets a container **sends**: with `--latency 100ms` from connect to the broker, the round trip between them grows by 100ms. To degrade the other direction as well, run the command on the destination too.
> * A new `--action start` replaces what was applied before on the container: to combine effects, pass them all in one call.
> * A restart of the container (e.g. `playground container restart`) removes the degradation.

> [!TIP]
> A complete example is available [here](https://github.com/vdesabou/kafka-docker-playground/blob/master/other/monitoring-sink-latency/start.sh).

## 🧰 Useful functions for reproduction models

All examples source [`scripts/utils.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/utils.sh), which loads the functions from [`scripts/cli/src/lib/utils_function.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/lib/utils_function.sh). The most useful ones:

| Function | Usage |
|---|---|
| `wait_for_log` | `wait_for_log "<message>" [container, default connect] [max wait in seconds, default 600]`: wait until a message appears in container logs. Prefer this over `sleep`. CLI equivalent: `playground container logs -c connect --wait-for-log "<message>" --max-wait 120` |
| `playground connector create-or-update --wait` | not a function but a flag: wait until the connector and all its tasks are RUNNING after creating it, and fail with the stack trace otherwise. Prefer this over `sleep` after creating a connector. Also `playground connector wait --connector <c>` and `playground topic wait-for-records --topic <t> --min-expected-messages N` |
| `wait_for_datagen_connector_to_inject_data` | `wait_for_datagen_connector_to_inject_data <connector name> <nb tasks>`: wait until a datagen connector has produced its configured number of messages |
| `retrycmd` | `retrycmd <max attempts> <sleep interval in seconds> <command>`: run a command until it succeeds, e.g. `retrycmd 10 5 check_my_condition` |
| `block_host` / `remove_partition` | `block_host <container> <ip>...` drops all traffic from a container to the given IPs, `remove_partition <container>...` removes it |
| `version_gt` | `if version_gt $TAG_BASE "7.9.99"; then ... fi`: compare versions |
| `connect_cp_version_greater_than_8` | `if connect_cp_version_greater_than_8; then ... fi`: true when the Connect image is CP 8.x or later |
| `get_3rdparty_file` | `get_3rdparty_file <file>`: download a third-party file (driver, jar...) if it is not already present |
| `install_connector_with_retry` | `install_connector_with_retry "<install command>"`: install a connector, with retries (`CONNECTOR_INSTALL_MAX_RETRIES`, default 5) |
| `create_topic` / `delete_topic` | `create_topic <topic>`: create or delete a topic on Confluent Cloud (uses the `confluent` CLI, for `ccloud` examples) |

## 🏚 Simulate TCP connections problems

[emicklei/zazkia](https://github.com/emicklei/zazkia) is a nice tool to simulate a TCP connection issues (reset,delay,throttle,corrupt).

Just use [CLI](/playground%20tcp-proxy) `playground tcp-proxy`.

Main commands (see [CLI](/playground%20tcp-proxy) for the full list):

| Command | Description |
|---|---|
| [`start`](/playground%20tcp-proxy%20start) | 💗 Start the TCP proxy and automatically replace connector config with zazkia hostname and port 49998 |
| [`open-ui`](/playground%20tcp-proxy%20open-ui) | 🌐 Open the Zazkia UI |
| [`get-connections`](/playground%20tcp-proxy%20get-connections) | 🧲 Get Zazkia active TCP connections config and stats |
| [`delay`](/playground%20tcp-proxy%20delay) | ⏲️ Add milliseconds delay to service response |
| [`break`](/playground%20tcp-proxy%20break) | 💔 Break sending the response to the client |
| [`close-connection`](/playground%20tcp-proxy%20close-connection) | ❌ Close the Zazkia active TCP connections |
| [`close-all-connection-with-error`](/playground%20tcp-proxy%20close-all-connection-with-error) | 🧹 Close all Zazkia TCP connections which are in error state |
| [`toggle-accept-connections`](/playground%20tcp-proxy%20toggle-accept-connections) | 🙅‍♂️ Change whether new connections can be accepted |
| [`toggle-reads-client`](/playground%20tcp-proxy%20toggle-reads-client) / [`toggle-reads-service`](/playground%20tcp-proxy%20toggle-reads-service) | ✅ Change whether reading data from the client / service is enabled |
| [`toggle-writes-client`](/playground%20tcp-proxy%20toggle-writes-client) / [`toggle-writes-service`](/playground%20tcp-proxy%20toggle-writes-service) | ✅ Change whether writing data to the client / service is enabled |

## 🌐 Using HTTPS proxy

There are several connector examples which include HTTPS proxy (check for `also with 🌐 proxy` in the **[Content](/content.md)** section).

> [!TIP]
> A complete example is available [here](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-aws-s3-sink/s3-sink-proxy.sh). 

Here are the steps to follow:

1. Copy [`connect/connect-aws-s3-sink/nginx-proxy`](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-aws-s3-sink/nginx-proxy) directory into your test directory.

2. Update [`connect/connect-aws-s3-sink/nginx-proxy/nginx_whitelist.conf`](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-aws-s3-sink/nginx-proxy/nginx_whitelist.conf) with the domain name required for your needs.

*Example:*

```conf
        server_name  service-now.com;
        server_name  *.service-now.com;
```

> [!TIP]
> If you need a proxy to reach another docker container, as opposed to a domain, use following example, where `schema-registry` is the name of the container:

```nginx
http {
    access_log /var/log/nginx_access.log;
    error_log /var/log/nginx_errors.log;

    upstream docker-schema-registry {
        server schema-registry:8081;
    }

    server {
        listen       8888;
        location / {
            proxy_pass         http://docker-schema-registry;
            proxy_redirect     off;
            proxy_set_header   Host $host;
            proxy_set_header   X-Real-IP $remote_addr;
            proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header   X-Forwarded-Host $server_name;
        }
    }
}
```

3. Add this in your `docker-compose` file:

```yml
  nginx-proxy:
    image: reiz/nginx_proxy:latest
    hostname: nginx-proxy
    container_name: nginx-proxy
    ports:
      - "8888:8888"
    volumes:
      - ../../connect/connect-aws-s3-sink/nginx-proxy/nginx_whitelist.conf:/usr/local/nginx/conf/nginx.conf
```

> [!WARNING]
> Make sure to update `../../connect/connect-aws-s3-sink` above with the right path.

4. [Optional] In order to make sure the proxy is used, you can set `dns: 0.0.0.0` in the connect instance, so that there is no internet connectivity.

```yml
  connect:
    <snip>
    environment:
      <snip>
    dns: 0.0.0.0
```

5. In your connector configuration, update the proxy configuration parameter with `http://nginx-proxy:8888`.

*Example:*

```json
"s3.proxy.url": "http://nginx-proxy:8888"
```

> [!NOTE]
> If your proxy requires HTTP2 support, there is a full example available in this example: [GCP Pub/Sub Source connector](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-gcp-pubsub-source/gcp-pubsub-source-nginx-proxy.sh)

### 🔐 Proxy with BASIC authentication

If you want to setup BASIC authentication, you can use [ubuntu/squid](https://hub.docker.com/r/ubuntu/squid) image.

> [!TIP]
> Some complete examples are available [here](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-aws-s3-sink/s3-sink-proxy-basic-auth.sh) and [there](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-salesforce-platform-events-sink/salesforce-platform-events-sink-proxy-basic-auth.sh)

* in your `docker-compose`, add `squid` as below:


```yml
  squid:
    image: ubuntu/squid
    hostname: squid
    container_name: squid
    ports:
      - "8888:8888"
    volumes:
      - ../../connect/connect-aws-s3-sink/squid/passwords:/etc/squid/passwords
      - ../../connect/connect-aws-s3-sink/squid/squid.conf:/etc/squid/squid.conf
```

Proxy details:

* container: squid
* port: 8888
* user: admin
* password: 1234

Example with S3 sink:

```json
  "s3.proxy.url": "http://squid:8888",
  "s3.proxy.user": "admin",
  "s3.proxy.password": "1234",
```

Example with Salesforce:

```json
  "http.proxy": "squid:8888",
  "http.proxy.auth.scheme": "BASIC",
  "http.proxy.user": "admin",
  "http.proxy.password": "1234",
```

## ♨️ Using specific JDK

Some issues depend on the Java version or vendor (TLS protocols and cipher suites, a JVM bug, a library that needs a more recent Java, a difference seen only with the customer's JDK). To reproduce them, you can replace the JDK installed in a container image (connect, broker, control-center…) with another version or vendor.

Here are some examples:

### 🌀 Azul Zulu JDK

Just use [playground container change-jdk](/playground%20container%20change-jdk) CLI command !

Example:

```bash
$ playground container change-jdk --version 21 --container control-center 
17:03:25 ℹ️ 🤎 Installing Azul JDK 21 on container control-center /usr/lib/jvm/java-11-zulu-openjdk/bin/java
17:03:25 ℹ️ Executing command as root in container control-center with bash
Last metadata expiration check: 0:26:16 ago on Fri May 24 14:37:10 2024.
zulu-repo-1.0.0-1.noarch.rpm                    4.4 kB/s | 3.0 kB     00:00    
Package zulu-repo-1.0.0-1.noarch is already installed.
Dependencies resolved.
Nothing to do.
Complete!
Last metadata expiration check: 0:26:17 ago on Fri May 24 14:37:10 2024.
Dependencies resolved.
================================================================================
 Package                     Architecture Version       Repository         Size
================================================================================
Installing:
 zulu21-jdk                  aarch64      21.0.3-1      zulu-openjdk      4.3 k
Installing dependencies:
 zulu21-ca-doc               aarch64      21.0.3-1      zulu-openjdk      232 k
 zulu21-ca-jdk               aarch64      21.0.3-1      zulu-openjdk       23 k
 zulu21-ca-jdk-headless      aarch64      21.0.3-1      zulu-openjdk       81 M
 zulu21-ca-jre               aarch64      21.0.3-1      zulu-openjdk      354 k
 zulu21-ca-jre-headless      aarch64      21.0.3-1      zulu-openjdk       47 M
 zulu21-doc                  aarch64      21.0.3-1      zulu-openjdk      4.2 k
 zulu21-jdk-headless         aarch64      21.0.3-1      zulu-openjdk      4.3 k
 zulu21-jre                  aarch64      21.0.3-1      zulu-openjdk      4.2 k
 zulu21-jre-headless         aarch64      21.0.3-1      zulu-openjdk      4.2 k

Transaction Summary
================================================================================
Install  10 Packages

Total download size: 128 M
Installed size: 295 M
Downloading Packages:
(1/10): zulu21-ca-jdk-21.0.3-1.aarch64.rpm      180 kB/s |  23 kB     00:00    
(2/10): zulu21-ca-doc-21.0.3-1.aarch64.rpm      1.2 MB/s | 232 kB     00:00    
(3/10): zulu21-ca-jre-21.0.3-1.aarch64.rpm      1.5 MB/s | 354 kB     00:00    
(4/10): zulu21-doc-21.0.3-1.aarch64.rpm          36 kB/s | 4.2 kB     00:00    
(5/10): zulu21-jdk-21.0.3-1.aarch64.rpm          66 kB/s | 4.3 kB     00:00    
(6/10): zulu21-jdk-headless-21.0.3-1.aarch64.rp  36 kB/s | 4.3 kB     00:00    
(7/10): zulu21-jre-21.0.3-1.aarch64.rpm          76 kB/s | 4.2 kB     00:00    
(8/10): zulu21-jre-headless-21.0.3-1.aarch64.rp 100 kB/s | 4.2 kB     00:00    
(9/10): zulu21-ca-jre-headless-21.0.3-1.aarch64 3.2 MB/s |  47 MB     00:14    
(10/10): zulu21-ca-jdk-headless-21.0.3-1.aarch6 5.3 MB/s |  81 MB     00:15    
--------------------------------------------------------------------------------
Total                                           8.4 MB/s | 128 MB     00:15     
Running transaction check
Transaction check succeeded.
Running transaction test
Transaction test succeeded.
Running transaction
  Running scriptlet: zulu21-ca-jre-headless-21.0.3-1.aarch64                1/1 
  Running scriptlet: zulu21-ca-jdk-headless-21.0.3-1.aarch64                1/1 
  Running scriptlet: zulu21-ca-jre-21.0.3-1.aarch64                         1/1 
  Running scriptlet: zulu21-jre-headless-21.0.3-1.aarch64                   1/1 
  Running scriptlet: zulu21-ca-doc-21.0.3-1.aarch64                         1/1 
  Running scriptlet: zulu21-ca-jdk-21.0.3-1.aarch64                         1/1 
  Running scriptlet: zulu21-doc-21.0.3-1.aarch64                            1/1 
  Running scriptlet: zulu21-jdk-headless-21.0.3-1.aarch64                   1/1 
  Running scriptlet: zulu21-jre-21.0.3-1.aarch64                            1/1 
  Running scriptlet: zulu21-jdk-21.0.3-1.aarch64                            1/1 
  Preparing        :                                                        1/1 
  Installing       : zulu21-ca-jre-headless-21.0.3-1.aarch64               1/10 
  Running scriptlet: zulu21-ca-jre-headless-21.0.3-1.aarch64               1/10 
  Installing       : zulu21-ca-jdk-headless-21.0.3-1.aarch64               2/10 
  Running scriptlet: zulu21-ca-jdk-headless-21.0.3-1.aarch64               2/10 
  Installing       : zulu21-ca-jre-21.0.3-1.aarch64                        3/10 
  Running scriptlet: zulu21-ca-jre-21.0.3-1.aarch64                        3/10 
  Installing       : zulu21-jre-headless-21.0.3-1.aarch64                  4/10 
  Running scriptlet: zulu21-jre-headless-21.0.3-1.aarch64                  4/10 
  Installing       : zulu21-ca-doc-21.0.3-1.aarch64                        5/10 
  Running scriptlet: zulu21-ca-doc-21.0.3-1.aarch64                        5/10 
  Installing       : zulu21-ca-jdk-21.0.3-1.aarch64                        6/10 
  Running scriptlet: zulu21-ca-jdk-21.0.3-1.aarch64                        6/10 
  Installing       : zulu21-doc-21.0.3-1.aarch64                           7/10 
  Running scriptlet: zulu21-doc-21.0.3-1.aarch64                           7/10 
  Installing       : zulu21-jdk-headless-21.0.3-1.aarch64                  8/10 
  Running scriptlet: zulu21-jdk-headless-21.0.3-1.aarch64                  8/10 
  Installing       : zulu21-jre-21.0.3-1.aarch64                           9/10 
  Running scriptlet: zulu21-jre-21.0.3-1.aarch64                           9/10 
  Installing       : zulu21-jdk-21.0.3-1.aarch64                          10/10 
  Running scriptlet: zulu21-jdk-21.0.3-1.aarch64                          10/10 
  Running scriptlet: zulu21-ca-jre-headless-21.0.3-1.aarch64              10/10 
  Running scriptlet: zulu21-ca-jdk-headless-21.0.3-1.aarch64              10/10 
  Running scriptlet: zulu21-ca-jre-21.0.3-1.aarch64                       10/10 
  Running scriptlet: zulu21-jre-headless-21.0.3-1.aarch64                 10/10 
  Running scriptlet: zulu21-ca-doc-21.0.3-1.aarch64                       10/10 
  Running scriptlet: zulu21-ca-jdk-21.0.3-1.aarch64                       10/10 
  Running scriptlet: zulu21-doc-21.0.3-1.aarch64                          10/10 
  Running scriptlet: zulu21-jdk-headless-21.0.3-1.aarch64                 10/10 
  Running scriptlet: zulu21-jre-21.0.3-1.aarch64                          10/10 
  Running scriptlet: zulu21-jdk-21.0.3-1.aarch64                          10/10 
  Verifying        : zulu21-ca-doc-21.0.3-1.aarch64                        1/10 
  Verifying        : zulu21-ca-jdk-21.0.3-1.aarch64                        2/10 
  Verifying        : zulu21-ca-jdk-headless-21.0.3-1.aarch64               3/10 
  Verifying        : zulu21-ca-jre-21.0.3-1.aarch64                        4/10 
  Verifying        : zulu21-ca-jre-headless-21.0.3-1.aarch64               5/10 
  Verifying        : zulu21-doc-21.0.3-1.aarch64                           6/10 
  Verifying        : zulu21-jdk-21.0.3-1.aarch64                           7/10 
  Verifying        : zulu21-jdk-headless-21.0.3-1.aarch64                  8/10 
  Verifying        : zulu21-jre-21.0.3-1.aarch64                           9/10 
  Verifying        : zulu21-jre-headless-21.0.3-1.aarch64                 10/10 

Installed:
  zulu21-ca-doc-21.0.3-1.aarch64           zulu21-ca-jdk-21.0.3-1.aarch64       
  zulu21-ca-jdk-headless-21.0.3-1.aarch64  zulu21-ca-jre-21.0.3-1.aarch64       
  zulu21-ca-jre-headless-21.0.3-1.aarch64  zulu21-doc-21.0.3-1.aarch64          
  zulu21-jdk-21.0.3-1.aarch64              zulu21-jdk-headless-21.0.3-1.aarch64 
  zulu21-jre-21.0.3-1.aarch64              zulu21-jre-headless-21.0.3-1.aarch64 

Complete!
17:03:54 ℹ️ Executing command as root in container control-center with bash
17:03:54 ℹ️ Restarting docker container control-center
control-center
17:04:02 ℹ️ Executing command in container control-center with bash
openjdk version "21.0.3" 2024-04-16 LTS
OpenJDK Runtime Environment Zulu21.34+19-CA (build 21.0.3+9-LTS)
OpenJDK 64-Bit Server VM Zulu21.34+19-CA (build 21.0.3+9-LTS, mixed mode, sharing)
```

### ⭕️ Oracle JDK

Here are the steps to follow:

1. Get the Oracle JDK `.rpm` version link you want to install from the [website](https://www.oracle.com/java/technologies/downloads/). In our example, that will be `jdk-21_linux-x64_bin.rpm`

> [!NOTE]
> CP 8.x requires Java 17 or later, so pick a JDK 17+ build. CP images are based on UBI minimal, which ships `microdnf` and not `yum`: the `Dockerfile` below installs `yum` first.

2. Add this in your `docker-compose` file:

```yml
  connect:
    build:
      context: ../../connect/connect-filestream-sink/
      args:
        CP_CONNECT_IMAGE: ${CP_CONNECT_IMAGE}
        CP_CONNECT_TAG: ${CP_CONNECT_TAG}
```
> [!WARNING]
> Make sure to update `context` above with the right path.

3. Create a `Dockerfile` file in `context` directory above (`../../connect/connect-filestream-sink/`).

```dockerfile
ARG CP_CONNECT_IMAGE
ARG CP_CONNECT_TAG
FROM ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG}
COPY jdk-21_linux-x64_bin.rpm /tmp/
USER root
RUN if command -v microdnf >/dev/null 2>&1; then microdnf -y install yum; fi \
 && yum -y install /tmp/jdk-21_linux-x64_bin.rpm \
 && alternatives --set java /usr/lib/jvm/jdk-21-oracle-x64/bin/java \
 && rm /tmp/jdk-21_linux-x64_bin.rpm
USER appuser
```

> [!WARNING]
> Make sure to update `alternatives --set java` above with the right path.

4. Verify the correct JDK version is installed once your test is started:

```bash
playground container exec -c connect --command "java -version"
```

## 🏎️ Performance testing

[playground connector benchmark](https://kafka-docker-playground.io/#/playground%20connector%20benchmark) is the way to do performance testing with the playground. On a running example or reproduction model, self managed or [fully managed](/reusables?id=%e2%98%81%ef%b8%8f-fully-managed-connectors), it loads the data, measures the throughput of the connector, tells whether the connector is really the bottleneck, records where its time goes, compares with the previous run or with other versions of the connector, and writes an HTML report to share.

| I want to | Use |
|---|---|
| measure a connector | `playground connector benchmark`: the load comes with the example (the `playground topic produce` of a sink example is replayed, a source example has a `benchmark-load.bash`) |
| compare connector versions | `playground connector benchmark --connector-tag A --connector-tag B` |
| use my own data | [your own load](/reusables?id=your-own-load) (`--load-command`, or a load script, like the Salesforce source example below) |
| load a table of my own in a reproduction model | [a table of your own](/reusables?id=a-table-of-your-own-reproduction-models) (`BENCHMARK_LOAD_SCRIPT`) |
| see the broker, the JVM, the connector dashboards | start the example with [JMX Grafana](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%93%8a-enabling-jmx-grafana) (`--enable-jmx-grafana`): the benchmark [annotates its measure](/reusables?id=%f0%9f%93%8a-grafana) |
| benchmark a fully managed connector | run its `ccloud/fm-*` example, keep the connector, then `playground connector benchmark`: see [fully managed connectors](/reusables?id=%e2%98%81%ef%b8%8f-fully-managed-connectors) |
| keep a database busy while I watch | [`--enable-sql-datagen`](/reusables?id=%f0%9f%8c%aa%ef%b8%8f-databases-keep-a-load-running-with-enable-sql-datagen) |

### ⏱️ Benchmark a connector

[playground connector benchmark](https://kafka-docker-playground.io/#/playground%20connector%20benchmark) measures the throughput of a running connector, self managed or fully managed, so that you can compare two runs: another `--connector-tag`, another config, another number of tasks, or the numbers of a customer.

<video src="videos/benchmark.mp4" autoplay loop muted playsinline controls width="100%"></video>

By default (`--mode drain`), it pauses the connector, loads a backlog of `--nb-records`, resumes the connector and measures the time it takes to process it. This is the most reproducible number, since it does not depend on how fast the load is generated. `--mode steady` measures the throughput during `--duration` while a load runs in the background.

```bash
# sink: the 'playground topic produce' of the example script is replayed with 3M records
playground connector benchmark --nb-records 3000000

# source: rows inserted in the source database by the benchmark-load.bash of the example
playground connector benchmark --nb-records 1000000 --shape bulk
playground connector benchmark --nb-records 100000 --shape small-txn
playground connector benchmark --nb-records 1000000 --shape update
playground connector benchmark --nb-records 1000000 --shape delete

# insert, update, then delete the same rows: one drain per phase, compared
playground connector benchmark --nb-records 2000000 --shape bulk,update,delete

# throughput during 5 minutes, with a load running in the background
playground connector benchmark --mode steady --duration 5m

# source: the load in 5 parallel sessions (concurrent transactions)
playground connector benchmark --nb-records 1000000 --shape small-txn --sessions 5
```

`--sessions <n>` runs the `benchmark-load.bash` of the example in `n` parallel sessions: a drain splits `--nb-records` between them, steady mode gives each session batches of `--nb-records`. Concurrent transactions are what a busy database looks like to a CDC connector (interleaved transactions in the redo log or the WAL, several open transactions).

The load comes from the example:

* **sink connectors**: the `playground topic produce` of the example script that feeds the connector is replayed with `--nb-messages <n>` (same schema, key and headers), so it works with almost every sink example
* **source connectors**: `benchmark-load.bash` next to the example script, called with `--check` first so that an unsupported combination fails before the connector is paused:
  * JDBC and Debezium PostgreSQL, Debezium MySQL, JDBC and Debezium SQL Server, Oracle CDC, Oracle XStream, Debezium Oracle and JDBC Oracle: rows in the `CUSTOMERS` table (`dbo.customers` for SQL Server), in one transaction (`--shape bulk`), one transaction per row (`--shape small-txn`) as updates (`--shape update`, refused for a JDBC source in `incrementing` mode, which does not capture updates), or as deletes (`--shape delete`, refused for a JDBC source, which does not capture deletes)
  * TimescaleDB (Debezium), CockroachDB and SingleStore (JDBC): rows in the table of the example (the `conditions` hypertable, `drivers`, `application`), `--shape bulk` or `small-txn`
  * MongoDB and Debezium MongoDB: documents in the collection of the connector, with the shape of an existing document so that the schema inferred by the connector stays compatible (`bulk`: insertMany, `small-txn`: insertOne, `update`)
  * IBM MQ (Confluent and ibm-messaging connectors): messages put in the queue of the connector with `amqsput` (the max depth of the queue is raised first)
  * MQTT: messages published with `mosquitto_pub`, **steady mode only**: a paused MQTT source stays subscribed, so the messages published while it is paused go to its in-memory buffer or are dropped by the broker
  * ActiveMQ, WebLogic, TIBCO EMS (and their JMS source variants, Lenses JMS included): messages sent with `BenchmarkJmsProducer` (`tools/benchmark-jms`), a small JMS producer run with the client jars of the broker and the JNDI settings of the connector (`--shape bulk`: transactions of 1000 messages, `--shape small-txn`: one send per message, `BENCHMARK_JMS_JSON=<template>` for JSON messages). A topic destination is measured with `--mode steady` only
  * SQS, Kinesis, Pub/Sub (Confluent and Google connectors) and CloudWatch Logs: messages sent with `tools/benchmark-python/benchmark_producer.py` (boto3, google-cloud-pubsub) in a small image built the first time, in batches (10 messages for SQS, 500 records for Kinesis, 1000 messages for Pub/Sub, 10000 events for CloudWatch Logs), or one per request with `--shape small-txn`
  * RabbitMQ: messages published with the `producer.py` of the example
  * Solace (and JMS Solace): messages sent through the REST messaging port of the broker
  * Splunk: events sent to the HTTP event collector of the connector, **steady mode only** (the connector keeps the events received while it is paused in memory)
  * Files: JSON or CSV files of `BENCHMARK_FILE_RECORDS` records (10000, one record per file with `--shape small-txn`), written so that the connector never reads a file being written: spool dir, SFTP and FTPS (in the format of the connector class and its `input.file.pattern`), FilePulse (CSV rows of `csv.sh`), HDFS 2 and HDFS 3 (Avro files in the layout of the HDFS sink), and the generalized mode of the S3, GCS and Azure Blob Storage sources (names that sort after the files already read). FileStream: lines appended to the file of the connector. The cloud storage and HDFS sources reconfigure their task at each poll interval: the benchmark then counts the records in the topics, and says so
  * Salesforce Bulk API source: Leads created in Salesforce with one Bulk API job (`--shape bulk` drain only, see [the example below](/reusables?id=a-real-life-example-the-salesforce-bulk-api-source))
* or your own command with `--load-command` (drain) / `--stream-load-command` (steady), for example in a reproduction model (see below)

#### Your own load

Both commands run with `bash -c`, from the current directory. The examples below use a predefined schema of the CLI (`--value @predefined-schemas/avro/customer.avsc`): use the schema of the records your connector expects.

**Drain** (`--load-command`): the command runs while the connector is paused, creates the records and returns. `--nb-records` is the number of records the connector should then process, unless the command prints a line `BENCHMARK_RECORDS=<n>`:

```bash
# sink: 1M records in the topic of the connector
playground connector benchmark --nb-records 1000000 \
  --load-command "playground topic produce -t my-topic --nb-messages 1000000 --value @predefined-schemas/avro/customer.avsc"

# source: your own script, which inserts the rows and prints BENCHMARK_RECORDS=<n>
playground connector benchmark --load-command "./load-my-table.sh 500000"
```

**Steady** (`--stream-load-command`): the command runs in the background. At the end of the measure, the file named by the `BENCHMARK_STOP_FILE` environment variable is created: stop at the end of the current batch when it exists. The command is killed after 120s otherwise, and killing a producer in the middle of a batch can send a truncated record to the topic. Print `BENCHMARK_BATCH=<records> <epoch seconds>` after each batch, so that the summary can tell when the connector only kept up with the load:

```bash
playground connector benchmark --mode steady --duration 2m \
  --stream-load-command 'while [ ! -f "$BENCHMARK_STOP_FILE" ]; do playground topic produce -t my-topic --nb-messages 10000 --value @predefined-schemas/avro/customer.avsc; echo "BENCHMARK_BATCH=10000 $(date +%s)"; done'
```

##### A real-life example: the Salesforce Bulk API source

The [Salesforce Bulk API source example](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-salesforce-bulkapi-source) reads Leads from a Salesforce org. To benchmark it, the load must create Leads **in Salesforce**, so that the connector picks them up like in production. Creating them one by one (`sfdx data:create:record`) would take one API call per Lead: [its `benchmark-load.bash`](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-salesforce-bulkapi-source/benchmark-load.bash) creates them with **one Bulk API job**:

```bash
# the Salesforce user of the connector: the connect REST API shows it (only passwords are masked),
# and the sfdx-cli container of the example is already logged in with it
username=$(benchmark_connector_config_value salesforce.username)

# <records> Leads in one Bulk API job: an upsert on Id with an empty Id inserts every row
awk -v n="$records" -v run="$(date +%s)" 'BEGIN {
  print "Id,FirstName,LastName,Company"
  for (i = 1; i <= n; i++) printf ",Lead%d,benchmark-%s-%d,playground-benchmark\n", i, run, i
}' | playground container exec --container sfdx-cli --command "cat > /tmp/benchmark-leads.csv"
playground container exec --container sfdx-cli --command "sfdx force:data:bulk:upsert --target-org '$username' -s Lead -f /tmp/benchmark-leads.csv -i Id -w 30 --json"

# one record per Lead in the topic of the connector
echo "BENCHMARK_RECORDS=$records"
```

It also deletes the Leads of the previous runs first (a developer org holds about 2500 Leads, 5 MB of data storage), and refuses anything else than a drain with `--shape bulk` in its `--check`. Then:

```bash
playground run -f connect/connect-salesforce-bulkapi-source/salesforce-bulkapi-source.sh
playground connector benchmark --connector salesforce-bulkapi-source --nb-records 1000
```

On a developer org, the 1000 Leads were created in 25 s (one Bulk API job), and the connector wrote them to `sfdc-bulkapi-leads` in 13 s, about 76 records/s. They arrived in bursts, each time a Bulk API query job of the connector completed: with a few thousand Leads, this mostly measures the latency of the query jobs of the org, which is exactly what a customer sees too.

The same pattern works for any source system: create the data **at the source** with its own bulk tools, wait for nothing (the connector is paused), print `BENCHMARK_RECORDS=<n>`.

#### A table of your own (reproduction models)

The loads shipped with the examples always write the `CUSTOMERS` table of the example (`dbo.customers` for SQL Server). When a reproduction model reads another table, the one of the customer for example, give it a load script of its own, **named after its ticket**, next to the reproduction model script, and select it with `BENCHMARK_LOAD_SCRIPT`:

```bash
BENCHMARK_LOAD_SCRIPT=benchmark-load-123456.bash playground connector benchmark --nb-records 500000
```

`BENCHMARK_LOAD_SCRIPT` is a file name in the folder of the script that was run (or an absolute path): several reproduction models of the same folder can each have their load. Without it, the benchmark uses the `benchmark-load.bash` of the folder. `--enable-sql-datagen` uses it too, and the summary and the report work as with the examples: `--check` before the connector is paused, the drain, steady mode, the warnings, plus a warning when the previous run used another load script.

The public example [`connect/connect-jdbc-postgresql-source/postgres-orders.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-jdbc-postgresql-source/postgres-orders.sh) does exactly that: it creates an `orders` table with a JDBC source connector on it, next to `postgres.sh` and the `CUSTOMERS` load of the folder, and its load is [`benchmark-load-orders.bash`](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-jdbc-postgresql-source/benchmark-load-orders.bash):

```bash
playground run -f connect/connect-jdbc-postgresql-source/postgres-orders.sh
BENCHMARK_LOAD_SCRIPT=benchmark-load-orders.bash playground connector benchmark --nb-records 1000000
BENCHMARK_LOAD_SCRIPT=benchmark-load-orders.bash playground connector benchmark --nb-records 100000 --shape small-txn --sessions 4
BENCHMARK_LOAD_SCRIPT=benchmark-load-orders.bash playground connector benchmark --mode steady --duration 2m --nb-records 2000   # batches of 2000 rows
```

`playground repro bootstrap` links the `benchmark-load.bash` of the example into the folder of the reproduction model, so the `CUSTOMERS` load works out of the box. Don't edit it: it is a link to the file of the example. Write `benchmark-load-<ticket>.bash` instead.

> [!NOTE]
> Reproduction models created before the link existed have no load: link the one of their example (`ln -s ../../connect/<example>/benchmark-load.bash .` in their folder), or write their own.

The load script of `postgres-orders.sh`, a template for yours (copy it as `benchmark-load-<ticket>.bash` and change the table, the SQL and the client):

```bash
#!/bin/bash
# load for 'playground connector benchmark' (BENCHMARK_LOAD_SCRIPT=benchmark-load-orders.bash) and --enable-sql-datagen:
# rows in the orders table of postgres-orders.sh, a table of your own (see "A table of your own" in the documentation)
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# only the functions: sourcing scripts/utils.sh would record this script as the example being run
source ${DIR}/../../scripts/cli/src/lib/utils_function.sh

# --records <n> --mode preload|stream --shape bulk|small-txn|update [--check]
benchmark_load_args "$@"
records="$BENCHMARK_LOAD_RECORDS"

# --check: called before the connector is paused, refuse what this load cannot do
if [ -n "$BENCHMARK_LOAD_CHECK" ]
then
  if [ "$BENCHMARK_LOAD_SHAPE" == "update" ]
  then
    # the connector of postgres-orders.sh is in incrementing mode: it only captures new rows
    logerror "❌ this load only inserts rows (the connector is in incrementing mode): use --shape bulk or small-txn"
    exit 1
  fi
  exit 0
fi

case "$BENCHMARK_LOAD_SHAPE" in
  bulk)
    # one transaction with all the rows
    sql="INSERT INTO orders (customer_id, product, quantity, price) SELECT i % 1000, 'product ' || (i % 50), 1 + i % 5, round((random() * 100)::numeric, 2) FROM generate_series(1, $records) AS i;"
  ;;
  small-txn)
    # one transaction per row
    sql="DO \$\$ BEGIN FOR i IN 1..$records LOOP INSERT INTO orders (customer_id, product, quantity, price) VALUES (i % 1000, 'product ' || (i % 50), 1 + i % 5, round((random() * 100)::numeric, 2)); COMMIT; END LOOP; END \$\$;"
  ;;
esac

function load_batch () {
  echo "$sql" | playground container exec --container postgres --command "psql -U myuser -d postgres" > /dev/null
}

if [ "$BENCHMARK_LOAD_MODE" == "stream" ]
then
  # steady mode: batches of <records> rows until the benchmark creates $BENCHMARK_STOP_FILE
  benchmark_stream_batches "$records" load_batch
else
  # drain: load the backlog, and tell the benchmark how many records the connector should write
  load_batch
  echo "BENCHMARK_RECORDS=$records"
fi
```

What the benchmark expects from the script:

| | |
|---|---|
| arguments | `--records <n> --mode preload\|stream --shape bulk\|small-txn\|update\|delete`, parsed by `benchmark_load_args`, and `--check` first, before the connector is paused: exit with an error for a combination the load cannot do |
| drain (`preload`) | load the rows and return, printing `BENCHMARK_RECORDS=<n>`: the number of records the connector should write (2 per row for Oracle CDC with a redo log topic, for example) |
| steady (`stream`) | repeat batches until the file `$BENCHMARK_STOP_FILE` exists, printing `BENCHMARK_BATCH=<records> <epoch>` after each batch: `benchmark_stream_batches <records> <command>` does both, and never stops a batch in the middle |
| environment | `BENCHMARK_TEST_FILE` (the script that was run: when several reproduction models share the folder, branch on it), `BENCHMARK_CONNECTOR`, `BENCHMARK_CONNECTOR_CONFIG` (a json file with the connector config) |
| source | `scripts/cli/src/lib/utils_function.sh`, not `scripts/utils.sh`, which would record the load script as the example being run |

The same works with MySQL (`mysql -u ... -p...`), Oracle (`sqlplus`, see `benchmark_oracle_client_from_example`) or SQL Server (`sqlcmd`): only the SQL and the client change. For a one-off measure, `--load-command "./load-orders.sh 500000"` (see above) is enough.

#### Is the connector the bottleneck?

A benchmark is only meaningful when the connector is what limits the throughput. The summary and the report warn when it isn't:

| Warning | Meaning |
| --- | --- |
| the connector kept up with the load | steady mode: the load generated about as many records as the connector processed (or the consumer lag of a sink stayed below one sample of records). This is the speed of the load: use `--mode drain`, or compare the end-to-end latency of a source (below) |
| the connector or its tasks were not RUNNING at N status checks | paused, restarting or rebalancing during the measure |
| the connect worker is CPU bound / spent X% of the time in gc pauses | ≥ 90% of the CPUs available to the worker, or > 10% of the time in GC pauses: the result reflects the docker host or the heap size (`KAFKA_HEAP_OPTS`) |
| the records are not spread across the tasks | an idle task, or one task doing most of the work: `tasks.max` greater than the number of partitions, key skew, or a connector that does not parallelize this load |
| N records went to the dead letter queue / were dropped by errors.tolerance=all | failing records are counted in the throughput |
| the load generated N records but the connector processed only M | steady mode: a backlog builds up in the source system, or a publish/subscribe broker (MQTT) drops the messages it cannot deliver |

At the end, it prints a summary (throughput with p50 / p95 / min per sample, put or poll batch time, running ratio, connect CPU), writes the samples (csv) and the result (json, also with `--json`) to `--output-dir`, and opens an HTML report with the charts. Each result is appended to a `benchmark-history` file, and compared with the previous benchmark of the same connector in the same example, mode and shape.

![playground connector benchmark report](./images/report-benchmark.jpg)

#### ⏱️ End-to-end latency of a source

With `--mode steady`, the benchmark of a source connector also measures the end-to-end latency of its records: the Kafka record timestamp minus the time of the change in the source system. After the measure, it reads the records written to the topics of the connector during it (all of them up to 100000, a sample spread over the measure otherwise). It gives p50 / p95 / p99 / max in the summary and the result json. The report shows the latency over time, its distribution and the slowest records, and adds a latency column to the comparable runs and to the `--connector-tag` comparisons. When the connector simply keeps up with the load, this is the number to compare.

```bash
# JDBC source: kafka timestamp - create_ts, the column the load fills with the time of the insert
playground connector benchmark --mode steady --duration 2m --nb-records 1000 --shape small-txn

# another field of the records: a dotted path for a nested one
playground connector benchmark --mode steady --duration 2m --latency-field after.create_ts
```

```
   end-to-end latency     p50 2529.5 ms  p95 4761.0 ms  p99 4916.0 ms  max 4943.0 ms   (create_ts, 33200 records)
```

The field is `--latency-field`, otherwise the field the `benchmark-load.bash` of the example writes the time of the change to (`create_ts` of the `CUSTOMERS` table, `update_ts` with `--shape update`; a load of your own prints `BENCHMARK_LATENCY_FIELD=<field>`), otherwise `source.ts_ms` of a CDC envelope (commit time in the database), or `wallTime` / `clusterTime` of a MongoDB change event. `--no-latency` disables it.

> [!TIP]
> * Use `--shape small-txn`: with `--shape bulk`, a default `CURRENT_TIMESTAMP` is the start of the transaction of the whole batch.
> * The summary warns about negative latencies (the clocks of the source system and of connect are not in sync), a timestamp with a precision of one second (a MySQL `TIMESTAMP` without milliseconds), and latencies that are all 0 ms (the connector sets the record timestamp from the source).
> * It is not measured in a drain: the latency of a record is then the time it waited in the backlog.

#### Insert, update, then delete the same rows

A CDC connector does not handle every change at the same cost: an update carries the before and after images of the row, a delete can also give a tombstone. `--shape` takes a list of shapes: one drain per shape, on the same rows, and the summary and the report compare the phases:

```bash
playground connector benchmark --nb-records 2000000 --shape bulk,update,delete
```

```
   phase  shape   records  seconds  records/s
   1      bulk    2000000  19.1     104712
   2      update  2000000  13.8     144927.5
   3      delete  4000000  19.2     208333.3
```

With Debezium PostgreSQL above, the delete phase has twice as many records: each deleted row gives a delete event and a tombstone. The benchmark reads it from the connector config, so that it waits for the right number of records:

| Connector | Records per deleted row |
|---|---|
| Debezium (PostgreSQL, MySQL, SQL Server, Oracle), Oracle XStream | 2 by default: the delete event and a tombstone (`tombstones.on.delete=true`); 1 with `tombstones.on.delete=false` |
| Oracle CDC | 1, plus a tombstone with `emit.tombstone.on.delete=true` (default `false`) |
| JDBC source | `--shape delete` is refused: a query-based connector does not see deletes |

![playground connector benchmark report comparing the phases of a sequence](./images/report-benchmark-sequence.jpg)

The report shows one bar per phase, the fastest phase, and with the flight recorder, where the time goes by phase (for example, less waiting and more CPU during the updates). A sequence is a series of drains of the load of a source connector: not with `--connector-tag`, `--mode steady` or a sink connector. `--shape delete` alone deletes rows that a previous run inserted (drain only).

#### Compare connector versions

`--connector-tag` (repeat the flag) benchmarks several versions of the connector plugin one after the other. For each version: [playground update-version](https://kafka-docker-playground.io/#/playground%20update-version) `--connector-tag` (only the connect container is restarted, the connector and its offsets are kept), a check that the connector runs the requested version, an untimed warm-up drain (the worker JVM was restarted), then the benchmark. The original version is restored at the end, and the summary and the report compare the versions (one color per version, mean / min / max, delta with the first version). `--rounds 2` alternates the versions (A B A B), which shows a drift from one run to the next:

```bash
playground connector benchmark --nb-records 5000000 --connector-tag 10.9.7 --connector-tag 10.9.9 --rounds 2
```

![playground connector benchmark report comparing connector versions](./images/report-benchmark-versions.jpg)

With the flight recorder (see below), the comparison report also shows where the time goes for each version: CPU by
layer and task time by state, with the change in points, and a finding that names what changed when a version is 5% or
more slower or faster.

![playground connector benchmark report comparing where the time goes by version](./images/report-benchmark-versions-flight-recorder.jpg)

> [!WARNING]
> A downgrade or a major version change can be incompatible with the offsets or the config of the connector: the comparison stops at the first FAILED state.

Each result also records the setup it ran on, shown in the **Setup** section of the report: host (OS, CPU model, CPUs, memory), container engine and the resources given to it, connect image and whether it runs **emulated** (an amd64 image on an arm64 host is much slower), connect JVM and maximum heap, number of workers and brokers, environment, connector plugin version, and the connector configuration with secrets masked. The summary warns when the previous run was on a different setup, and the history chart shows runs of another setup faded. The report also links to the example on GitHub, at the commit it ran with and on the default branch (repro models link to the private repository of the `reproduction-models` submodule), and to the documentation of the connector (from the manifest of its plugin).

#### 🛩️ Where the time goes

The connect workers are recorded with [Java Flight Recorder](/reusables?id=%f0%9f%9b%a9%ef%b8%8f-flight-recorder) during the measure (the drain, or the steady measure after the warm-up). The recording runs over JMX: the Confluent images have no `jcmd`, and nothing is restarted. The summary lists the findings, and the report gets a **Where the time goes** section, the same analysis as [`playground analyze flight-recorder`](/playground%20analyze%20flight-recorder): is it the connector, the system behind it, Kafka, a lock? Which part of the pipeline uses the CPU?

```
   flight recorder        🔴 The tasks wait on postgres:5432.
                          ℹ️  Most of the CPU goes to conversion.
                          ℹ️  Allocation is high.
```

![playground connector benchmark report: where the time goes](./images/report-benchmark-flight-recorder.jpg)

The `.jfr` files are kept in `--output-dir`, to open with JDK Mission Control or `playground analyze flight-recorder -f`. The recording costs a few % of throughput: `--no-flight-recorder` disables it, and the summary warns when the previous run was not recorded the same way.

#### 📊 Grafana

When the example runs with [Grafana](/how-to-use?id=%f0%9f%93%8a-enabling-jmx-grafana) (`--enable-jmx-grafana`, also enabled by `--enable-sql-datagen`), the benchmark marks the measure on the dashboards, so that you see the broker side, the JVM and the connector dashboards during the run:

* a region annotation over the window of the measure, with the throughput (`🏎️ benchmark of postgres-source (10.9.9): drain of 3000000 records, 225563.9 records/s`, tags `playground-benchmark`, the connector and its version), on the **Kafka Connect cluster** dashboard, the dashboard of the connector when there is one (**Debezium**, **Oracle CDC**, **Oracle XStream CDC**, **Mongo**), and the **Kafka cluster** dashboard. With `--connector-tag`, each version annotates its own run
* links to those dashboards at the time of the run in the summary and in the header of the HTML report (`📊 Grafana: Kafka Connect cluster · Kafka cluster`)

```
   grafana                http://localhost:3000/d/AEaSQ97mz?orgId=1&from=1792145306949&to=1792145491358
                          measure annotated on 2 dashboard(s): Kafka Connect cluster, Kafka cluster
```

![a playground connector benchmark annotated on the Kafka Connect cluster dashboard](./images/grafana-benchmark-annotation.jpg)

The benchmark does not start Grafana: start the example with it. Prometheus scrapes every 15 s, so a measure needs to last at least 45 s to show on the dashboards; the summary warns when it is shorter (`grafana has only N sample(s) during it`): increase `--nb-records`, or use `--mode steady --duration 2m`. The JMX exporter and the Grafana containers use some CPU: the summary also warns when the previous run was not measured the same way.

#### ☁️ Fully managed connectors

The benchmark also measures the fully managed connectors of the `ccloud/fm-*` examples. Run the example and answer `n` when it asks to delete the connector, then run the benchmark as usual:

```bash
# source: rows in the CUSTOMERS table of the local Postgres, read by the connector through ngrok
playground run -f ccloud/fm-jdbc-postgresql-source/fully-managed-jdbc-postgres-source.sh
playground connector benchmark --nb-records 500000

# sink: the 'playground topic produce' of the example is replayed; 1M records for about 10 offset commits
playground run -f ccloud/fm-jdbc-postgresql-sink/fully-managed-jdbc-postgres-sink.sh
playground connector benchmark --nb-records 1000000 --max-wait 1800
```

The load is the same as for the self managed examples. The 26 `ccloud/fm-*-source` examples that have a self managed equivalent with a benchmark load ship its `benchmark-load.bash`: same local database or broker, reached by the connector through ngrok. A sink replays the `playground topic produce` of its example.

Confluent Cloud gives no JMX, so the records are counted differently:

| | Sources | Sinks |
|---|---|---|
| progress during the measure | end offsets of the topics of the connector, every `--interval` (`kafka.topic`, `topic.prefix`, the topics consumed by the example; `--topic` to choose them) | offsets committed by the consumer group of the connector (`connect-<lcc id>`) |
| resolution | per sample (5 s) | one step per offset commit, about every minute |
| start of a drain | the first records seen after the resume: Confluent Cloud takes 10 to 20 s to restart the tasks | same |

After the measure, the benchmark reads the per minute metrics of the connector in the [Confluent Cloud Metrics API](https://docs.confluent.io/cloud/current/monitoring/metrics-api.html) (`sent_records` / `received_records`). They are exact counts, published about 30 s into each minute. The median of the full minutes of the measure gives the steady throughput, which does not depend on when a sink commits its offsets; a drain needs 3 minutes or more to have a full minute. The put batch time, the batch size and the dead letter queue records come from the same API, and the report shows the records per minute instead of the CPU chart:

```text
🏁 benchmark of 🌤️🤖fully managed connector PostgresSink_vsaboulin (sink, 1 task(s), PostgresSink fully managed, CP ccloud)
   mode                   drain of 971000 records (shape bulk, loaded in 23.9s)
   duration               534.6s
   throughput             1816.3 records/s   (per offset commit, every ~59s: p50 1944.5  p95 2238.5  min 102.8)
   metrics api            2008.3 records/s steady (median of 8 full minute(s) of received_records)
   put batch avg          258.6 ms (450.0 records per batch)
```

For a sink, the end of a drain is only seen at the offset commit that follows it, so the main throughput is conservative by up to one commit interval: the `metrics api` line is the closer figure. A drain that sees less than 5 commits is reported as a lower bound (`≥`), and the summary gives the `--nb-records` of a drain of 10 commits.

> [!NOTE]
> There is no running ratio, cpu, gc, flight recorder nor `--connector-tag` for a fully managed connector: Confluent Cloud runs it, in the version it chooses. The throughput includes the network between the docker host and Confluent Cloud (ngrok tunnel). The Metrics API uses the Cloud API key (`CONFLUENT_CLOUD_API_KEY`) and does not answer for a deleted connector: benchmark before deleting it.

> [!NOTE]
> Everything runs on one docker host: the numbers are relative, compare runs on the same machine only. When the backlog is processed before the first sample, the throughput is only a lower bound (`≥`): increase `--nb-records` 10x. The cfk environment is not supported yet.

### 🌪️ Databases: keep a load running with `--enable-sql-datagen`

For the JDBC, Debezium, Oracle CDC and XStream source examples (Oracle, MySQL, MariaDB, PostgreSQL, SQL Server, self-managed and fully managed), `--enable-sql-datagen` keeps rows coming into the database once the example is done, while you watch the connector (Grafana is enabled with it):

```bash
playground run -f postgres.sh --enable-sql-datagen
SQL_DATAGEN_DURATION=30 SQL_DATAGEN_SESSIONS=10 playground run -f cdc-oracle19-pdb-table.sh --enable-sql-datagen
```

After the example succeeded, `playground run` starts the `benchmark-load.bash` of the example (the load of [playground connector benchmark](/reusables?id=%e2%8f%b1%ef%b8%8f-benchmark-a-connector), on the table its connector reads: `CUSTOMERS` for most examples) in stream mode, one row per transaction, in `SQL_DATAGEN_SESSIONS` parallel sessions (default 5: concurrent transactions, as on a busy database), for `SQL_DATAGEN_DURATION` minutes (default 10). It logs the rows inserted every 30 seconds, then stops the sessions at the end of their current batch:

```
🌪️ injecting rows with benchmark-load.bash for 1 minute(s): 5 session(s), one row per transaction
🌪️ 29500 rows inserted in 31s (951 rows/s)
🌪️ 63000 rows inserted in 61s (1032 rows/s)
🌪️ done: 63600 rows inserted in 61s by 5 session(s)
```

A reproduction model gets the load of its example from `playground repro bootstrap`, and can use a table of its own: see [A table of your own](/reusables?id=a-table-of-your-own-reproduction-models).

> [!TIP]
> To measure the connector rather than keep it busy, use [playground connector benchmark](/reusables?id=%e2%8f%b1%ef%b8%8f-benchmark-a-connector): same loads, with `--sessions` for parallel sessions.

