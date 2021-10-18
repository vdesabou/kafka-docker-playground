# 👷‍♂️ Reusables

Below is a collection of *how to* that you can re-use when you build your own reproduction models.

## 👉 Producing data

### 🔤 [kafka-console-producer](https://docs.confluent.io/platform/current/tutorials/examples/clients/docs/kafka-commands.html#produce-records)

* 1️⃣ Using `seq`

```bash
seq -f "This is a message %g" 10 | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic a-topic
```

* 2️⃣ Using [`Heredoc`](https://www.google.fr/url?sa=t&rct=j&q=&esrc=s&source=web&cd=&cad=rja&uact=8&ved=2ahUKEwjHrNGg8tPzAhVIOBoKHVsLA3wQFnoECAMQAw&url=https%3A%2F%2Flinuxize.com%2Fpost%2Fbash-heredoc%2F&usg=AOvVaw2Fsus1FqR5phtsBikk2-B6)

```bash
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic a-topic << EOF
This is my message 1
This is my message 2
EOF
```

* 3️⃣ Using a key:

```bash
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic a-topic --property parse.key=true --property key.separator=, << EOF
key1,value1
key1,value2
key2,value1
EOF
```

* 4️⃣ Using JSON with schema (and key):

```bash
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic a-topic --property parse.key=true --property key.separator=, << EOF
1,{"schema":{"type":"struct","fields":[{"type":"string","optional":false,"field":"record"}]},"payload":{"record":"record1"}}
2,{"schema":{"type":"struct","fields":[{"type":"string","optional":false,"field":"record"}]},"payload":{"record":"record2"}}
3,{"schema":{"type":"struct","fields":[{"type":"string","optional":false,"field":"record"}]},"payload":{"record":"record3"}}
EOF
```

### 🔣 [kafka-avro-console-producer](https://docs.confluent.io/platform/current/tutorials/examples/clients/docs/kafka-commands.html#produce-avro-records)

* 1️⃣ Using `seq`

```
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic a-topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'
```

* 2️⃣ Using [`Heredoc`](https://www.google.fr/url?sa=t&rct=j&q=&esrc=s&source=web&cd=&cad=rja&uact=8&ved=2ahUKEwjHrNGg8tPzAhVIOBoKHVsLA3wQFnoECAMQAw&url=https%3A%2F%2Flinuxize.com%2Fpost%2Fbash-heredoc%2F&usg=AOvVaw2Fsus1FqR5phtsBikk2-B6)

```bash
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic a-topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"u_name","type":"string"},
{"name":"u_price", "type": "float"}, {"name":"u_quantity", "type": "int"}]}' << EOF
{"u_name": "scissors", "u_price": 2.75, "u_quantity": 3}
{"u_name": "tape", "u_price": 0.99, "u_quantity": 10}
{"u_name": "notebooks", "u_price": 1.99, "u_quantity": 5}
EOF
```

* 3️⃣ Using a key:

```bash
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic a-topic --property key.schema='{"type":"record","namespace": "io.confluent.connect.avro","name":"myrecordkey","fields":[{"name":"ID","type":"long"}]}' --property value.schema='{"type":"record","name":"myrecordvalue","fields":[{"name":"ID","type":"long"},{"name":"product", "type": "string"}, {"name":"quantity", "type": "int"}, {"name":"price",
"type": "float"}]}'  --property parse.key=true --property key.separator="|" << EOF
{"ID": 111}|{"ID": 111,"product": "foo", "quantity": 100, "price": 50}
{"ID": 222}|{"ID": 222,"product": "bar", "quantity": 100, "price": 50}
EOF
```

* 4️⃣ Using `value.schema.file` and message as separate file

This can be useful if schema is complex.

```bash
docker cp schema.avsc connect:/tmp/
docker cp message.json connect:/tmp/
docker exec -i connect bash -c "kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic a-topic --property value.schema.file=/tmp/schema.avsc < /tmp/message.json"
```

Here are examples of [`schema.avsc`](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-http-sink/schema.avsc) and [`message.json`](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-http-sink/message.json)

> [!TIP]
> If Avro schema is very complex, it is better to use [♨️ Avro Java producer](/reusables?id=♨%EF%B8%8F-avro-java-producer) below.

### 🌪 kafka-producer-perf-test

```bash
docker exec broker kafka-producer-perf-test --topic a-topic --num-records 200000 --record-size 1000 --throughput 100000 --producer-props bootstrap.servers=broker:9092
```

### ♨️ Avro Java producer

If you want to send a complex AVRO message, the easiest way is to use an Avro JAVA producer which creates a Specific Record using Maven plugin and populate it using [j-easy/easy-random](https://github.com/j-easy/easy-random).

> [!TIP]
> A complete example is available [here](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-gcp-bigquery-sink/gcp-bigquery-repro-66277.sh).

Here are the steps to follow:

1. Copy [`connect/connect-gcp-bigquery-sink/producer-v1`](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-gcp-bigquery-sink/producer-v1) directory into your test directory.

2. Update [`connect/connect-gcp-bigquery-sink/producer-v1/src/main/resources/avro/customer-v1.avsc`](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-gcp-bigquery-sink/producer-v1/src/main/resources/avro/customer-v1.avsc) with your AVRO schema but be careful, you need to keep `Customer` for the name and `com.github.vdesabou` for the namespace:

```json
    "name": "Customer",
    "namespace": "com.github.vdesabou",
```

3. In your script, and *before* `${DIR}/../../environment/plaintext/start.sh`, add this:

```bash
for component in producer-v1
do
  log "Building jar for ${component}"
  docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${DIR}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package
done
```

4. Add this in your `docker-compose` file:

```yml
  producer-v1:
    build:
      context: ../../connect/connect-gcp-bigquery-sink/producer-v1/
    hostname: producer-v1
    container_name: producer-v1
    environment:
      KAFKA_BOOTSTRAP_SERVERS: broker:9092
      TOPIC: "customer-avro"
      REPLICATION_FACTOR: 1
      NUMBER_OF_PARTITIONS: 1
      MESSAGE_BACKOFF: 1000 # Frequency of message injection
      KAFKA_ACKS: "all" # default: "1"
      KAFKA_REQUEST_TIMEOUT_MS: 20000
      KAFKA_RETRY_BACKOFF_MS: 500
      KAFKA_CLIENT_ID: "my-java-producer-v1"
      KAFKA_SCHEMA_REGISTRY_URL: "http://schema-registry:8081"
```

You can change the environment values to your needs (for example `TOPIC`).

> [!WARNING]
> Make sure to update `context` above with the right path.

5. You can then invoke the Java producer by executing:

```bash
log "Run the Java producer-v1"
docker exec producer-v1 bash -c "java -jar producer-v1-1.0.0-jar-with-dependencies.jar"
```

## 👈 Consuming data

🚧 TODO 

## 🌐 Using proxy

🚧 TODO 


## ☕ Using specific JDK

🚧 TODO 

https://www.azul.com/downloads

```yml
  connect:
    build:
      context: ../../connect/connect-cdc-oracle12-source/
      args:
        TAG: ${TAG}
```

```yml
ARG TAG
FROM vdesabou/kafka-docker-playground-connect:${TAG}
USER root
RUN wget https://cdn.azul.com/zulu/bin/zulu11.48.21-ca-jdk11.0.11-linux.x86_64.rpm && yum install -y zulu11.48.21-ca-jdk11.0.11-linux.x86_64.rpm && alternatives --remove java /usr/lib/jvm/zulu11/bin/java
USER appuser
```