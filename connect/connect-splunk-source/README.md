# Splunk Source connector

## Objective

Quickly test [Splunk Source](https://docs.confluent.io/current/connect/kafka-connect-splunk/splunk-source/index.html#quick-start) connector.

## Pre-requisites

* `docker-compose` (example `brew cask install docker`)



## How to run

Simply run:

```
$ ./splunk.sh
```

## Details of what the script is doing

Creating Splunk sink connector

```bash
$ docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.SplunkHttpSourceConnector",
                    "tasks.max": "1",
                    "kafka.topic": "splunk-source",
                    "splunk.collector.index.default": "default-index",
                    "splunk.port": "8889",
                    "splunk.ssl.key.store.path": "/tmp/keystore.jks",
                    "splunk.ssl.key.store.password": "confluent",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/splunk-sink/config | jq .
```

Simulate an application sending data to the connector

```bash
$ curl -k -X POST https://localhost:8889/services/collector/event -d '{"event":"from curl"}'
```

Verifying topic `splunk-source`

```bash
$ docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic splunk-source --from-beginning --max-messages 1
```

Results:

```json
{
    "event": {
        "string": "from curl"
    },
    "host": {
        "string": "172.20.0.1"
    },
    "index": {
        "string": "default-index"
    },
    "source": null,
    "sourcetype": null,
    "time": {
        "long": 1571932581452
    }
}
```


N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
