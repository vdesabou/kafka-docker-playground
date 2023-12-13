# Neo4j Sink connector



## Objective

Quickly test [Neo4j Sink](https://neo4j.com/labs/kafka/4.0/kafka-connect/) connector.


## How to run

Simply run:

```
$ playground run -f neo4j<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or relative path>
```

Neo4j UI is available at [127.0.0.1:7474](http://127.0.0.1:7474) `neo4j/connect`

## Details of what the script is doing

Sending 1000 messages to topic `my-topic`using [neo4j-streams-sink-tester](https://github.com/conker84/neo4j-streams-sink-tester)

```bash
$ docker exec connect java -jar /tmp/neo4j-streams-sink-tester-1.0.jar -f AVRO -e 1000 -Dkafka.bootstrap.server=broker:9092 -Dkafka.schema.registry.url=http://schema-registry:8081
```

Creating Neo4j Sink connector

```bash
$ curl -X PUT \
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
    "errors.deadletterqueue.topic.name": "test-error-topic",
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

With `cypher-shell` CLI:

```bash
$ docker exec -i neo4j cypher-shell -u neo4j -p connect << EOF
MATCH (n) RETURN n;
EOF
```

Results:

```
(:Person {name: "Name -196952286", from: "AVRO", surname: "Surname A"})
(:Person {name: "Name -1950152848", from: "AVRO", surname: "Surname C"})
(:Person {name: "Name 1062585389", from: "AVRO", surname: "Surname C"})
(:Person {name: "Name -2126769236", from: "AVRO", surname: "Surname B"})
(:Person {name: "Name 1974372360", from: "AVRO", surname: "Surname B"})
(:Person {name: "Name -1285319995", from: "AVRO", surname: "Surname B"})
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
