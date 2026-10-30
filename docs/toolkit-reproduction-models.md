# 🛠 Reproduction models

Bootstrap a reproduction model from an example, share it as a self-contained bundle, and the helper functions to use in its script. Part of the [🧰 Reproduction toolkit](/reusables.md).

> [!TIP]
> The [🍪 deep dive on reproduction models](/deep-dive-reproduction-models.md) explains what happens under the hood: the header, `repro assert`, `repro bisect`, `repro list`.

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
> The `--source` path is the absolute path of your checkout. When the model is shared with [`playground repro export`](/toolkit-reproduction-models?id=%f0%9f%93%a6-share-a-reproduction-model), `playground repro import` changes it into the path of the other machine.

And add the transform config to connector:

```json
  "transforms": "MyCustomSMT",
  "transforms.MyCustomSMT.type": "com.github.vdesabou.kafka.connect.transforms.MyCustomSMT",
```

> [!TIP]
> To try the SMT on a record without copying the jar and restarting the worker after each build, use [playground connector smt test](/toolkit-data?id=%f0%9f%a7%aa-testing-smts) with `--smt-jar`:
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
* changes the paths of the exporter's machine into yours, e.g. the jar path that [`--custom-smt`](/toolkit-reproduction-models?id=with-custom-smt-custom-smt) writes into the script;
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
