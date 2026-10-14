# HTTP Sink used with Elasticsearch v9

## Objective

Quickly test the HTTP Sink connector writing to Elasticsearch v9, as described in [How to migrate to HTTP Sink Connector from Elasticsearch Sink connector for 9.0 versions](https://support.confluent.io/hc/en-us/articles/46240881943316-How-to-migrated-to-HTTP-Sink-Connector-from-Elasticsearch-Sink-connector-for-9-0-Versions).

## Prerequisites

With CP 8.0+, HTTP Sink connector version 1.7.10 or later is required (the script exits with code 111 otherwise).

## How to run

```bash
playground run -f http-elasticsearchv9-sink.sh
```

| Script | Description |
| --- | --- |
| `http-elasticsearchv9-sink.sh` | HTTP Sink posting JSON documents to the Elasticsearch `_doc` API |

## What the script does

1. Downloads `jcl-over-slf4j-2.0.7.jar` and copies it into the HTTP connector `lib` folder.
2. Starts the environment with an Elasticsearch container.
3. Produces 10 Avro records (`{"f1":"valueN"}`) to topic `mytopic`.
4. Creates the `http-elasticsearchv9-sink` connector with `http.api.url=http://elasticsearch:9200/myindex/_doc`, `request.body.format=json` and `batch.json.as.array=false`; responses go to `success-responses` / `error-responses`.
5. Queries `myindex/_search` from inside the Elasticsearch container and checks that `value1` and `value10` are present.
