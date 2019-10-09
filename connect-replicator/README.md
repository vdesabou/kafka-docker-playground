# Confluent Replicato

## Objective

Quickly test [Confluent Replicator](https://docs.confluent.io/5.3.1/connect/kafka-connect-replicator/index.html#crep-full) connector.

N.B: This is just to test security configurations with replicator. A more useful example is [MDC and single views](https://github.com/framiere/mdc-with-replicator-and-regexrouter)

## Pre-requisites

* `docker-compose` (example `brew cask install docker`)
* `jq` (example `brew install jq`)


## How to run

Simply run:

```
$ ./replicator.sh
```

## Details of what the script is doing

The connector is created with:

```bash
$ docker container exec connect \
      curl -X POST \
      -H "Content-Type: application/json" \
      --data '{
         "name": "duplicate-topic",
         "config": {
           "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
           "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
           "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
           "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
           "src.consumer.group.id": "duplicate-topic",
           "confluent.topic.replication.factor": 1,
           "provenance.header.enable": true,
           "topic.whitelist": "test-topic",
           "topic.rename.format": "test-topic-duplicate",
           "dest.kafka.bootstrap.servers": "broker:9092",
           "src.kafka.bootstrap.servers": "broker:9092"
           }}' \
      http://localhost:8083/connectors | jq .
```

Messages are sent to `test-topic` topic using:

```bash
$ seq 10 | docker container exec -i broker kafka-console-producer --broker-list broker:9092 --topic test-topic
```

Verify we have received the data in test-topic-duplicate topic

```bash
docker container exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic test-topic-duplicate --from-beginning --max-messages 10
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
