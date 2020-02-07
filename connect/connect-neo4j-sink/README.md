# Neo4j Sink connector

![asciinema](asciinema.gif)

## Objective

Quickly test [Neo4j Sink](https://www.confluent.jp/blog/kafka-connect-neo4j-sink-plugin) connector.


## How to run

Simply run:

```
$ ./neo4j.sh
```

Neo4j UI is available at [127.0.0.1:7474](http://127.0.0.1:7474) `neo4j/connect`

## Details of what the script is doing

Sending 1000 messages to topic `my-topic`using [neo4j-streams-sink-tester](https://github.com/conker84/neo4j-streams-sink-tester)

```bash
$ docker exec connect java -jar /tmp/neo4j-streams-sink-tester-1.0.jar -f AVRO -e 1000 -Dkafka.bootstrap.server=broker:9092 -Dkafka.schema.registry.url=http://schema-registry:8081
```

Creating Neo4j Sink connector

```bash
$ docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data @/tmp/contrib.sink.avro.neo4j.json \
     http://localhost:8083/connectors | jq .
```

With `contrib.sink.avro.neo4j.json`:

```json
{
    "topics": "my-topic",
    "connector.class": "streams.kafka.connect.sink.Neo4jSinkConnector",
    "errors.retry.timeout": "-1",
    "errors.retry.delay.max.ms": "1000",
    "errors.tolerance": "all",
    "errors.log.enable": true,
    "errors.log.include.messages": true,
    "neo4j.server.uri": "bolt://neo4j:7687",
    "neo4j.authentication.basic.username": "neo4j",
    "neo4j.authentication.basic.password": "connect",
    "neo4j.encryption.enabled": false,
    "neo4j.topic.cypher.my-topic": "MERGE (p:Person{name: event.name, surname: event.surname, from: 'AVRO'}) MERGE (f:Family{name: event.surname}) MERGE (p)-[:BELONGS_TO]->(f)"
}
```

Verify data is present in Neo4j http://127.0.0.1:7474 (neo4j/connect)

```bash
$ open "http://neo4j:connect@127.0.0.1:7474/"
```

You should see:

![Neo4j](Screenshot1.png)

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
