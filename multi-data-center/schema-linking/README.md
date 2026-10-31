# Schema Linking

## Objective

Quickly test [Schema Linking on Confluent Platform](https://docs.confluent.io/platform/current/schema-registry/schema-linking-cp.html) between the two clusters of the `mdc-plaintext` environment, together with Cluster Linking, and show why the consumers of the destination need the schemas in the right context.

The script:

1. produces Avro records to topic `orders` in `europe` (the schema is registered in `schema-registry-europe`)
2. mirrors `orders` to `us` with Cluster Linking: the records keep their schema id
3. creates an exporter into the context `.europe` of `schema-registry-us` (`playground schema exporter create --destination-context europe`): the schema id only resolves in that context (`playground schema get --id <id> --cluster us` fails with `40403`, `--context europe` works), so a consumer of `us` using the default context can't decode the records
4. the fix: an exporter into the default context (`--context-type NONE`). The destination must not have subjects in any context, or the exporter stops with `42205 Cannot import since found existing subjects`: the script deletes the first exporter and the subjects of `.europe` first. Then `playground schema compare --from europe --to us` reports the same subjects and ids, and `playground topic consume --cluster us` decodes the mirrored records
5. pauses and deletes the exporter

The override `docker-compose.mdc-plaintext.yml` enables Cluster Linking on `broker-us` and the exporter extension on `schema-registry-europe` (`resource.extension.class`, `kafkastore.update.handlers`, `password.encoder.secret`).

See the [Schema Registry deep dive](https://kafka-docker-playground.io/#/deep-dive-schema) for the `playground schema exporter`, `contexts`, `compare` and `--context` commands.

## How to run

Simply run:

```
$ playground run -f start-plaintext.sh
```
