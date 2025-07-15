# Confluent Replicator

## Objective

Quickly test [Confluent Replicator](https://docs.confluent.io/5.3.2/connect/kafka-connect-replicator/index.html#crep-full) connector.

N.B: This is just to test security configurations with replicator. More useful examples are [MDC and single views](https://github.com/framiere/mdc-with-replicator-and-regexrouter) and [Replicator Tutorial on Docker](https://docs.confluent.io/current/installation/docker/installation/replicator.html)




## How to run

Simply run:

```
$ just use <playground run> command and search for replicator.sh in this folder
```

Or using SASL_SSL authentications:

```bash
$ just use <playground run> command and search for replicator-sasl-ssl.sh in this folder
```

Or using 2 way SSL authentications:

```bash
$ just use <playground run> command and search for replicator-2way-ssl.sh in this folder
```

## Details of what the script is doing

### With no security in place (PLAINTEXT):

The connector is created with:

```bash
$ curl -X PUT \
      -H "Content-Type: application/json" \
      --data '{
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
           }' \
      http://localhost:8083/connectors/duplicate-topic/config | jq .
```

Messages are sent to `test-topic` topic using:

```bash
$ seq 10 | docker exec -i broker kafka-console-producer --bootstrap-server broker:9092 --topic test-topic
```

Verify we have received the data in test-topic-duplicate topic

```bash
playground topic consume --topic test-topic-duplicate --min-expected-messages 10 --timeout 60
```

### With SSL authentication:

Sending messages to topic test-topic-ssl

```bash
$ seq 10 | docker exec -i broker kafka-console-producer --bootstrap-server broker:9092 --topic test-topic-ssl --producer.config /etc/kafka/secrets/client_without_interceptors.config
```

Creating Confluent Replicator connector with SSL authentication

```bash
$ curl -X PUT \
     --cert ../../environment/2way-ssl/security/connect.certificate.pem --key ../../environment/2way-ssl/security/connect.key --tlsv1.2 --cacert ../../environment/2way-ssl/security/snakeoil-ca-1.crt \
     -H "Content-Type: application/json" \
     --data '{
                    "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
                    "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
                    "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
                    "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
                    "src.consumer.group.id": "duplicate-topic",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1",
                    "confluent.topic.ssl.keystore.location" : "/etc/kafka/secrets/kafka.connect.keystore.jks",
                    "confluent.topic.ssl.keystore.password" : "confluent",
                    "confluent.topic.ssl.key.password" : "confluent",
                    "confluent.topic.ssl.truststore.location" : "/etc/kafka/secrets/kafka.connect.truststore.jks",
                    "confluent.topic.ssl.truststore.password" : "confluent",
                    "confluent.topic.ssl.keystore.type" : "JKS",
                    "confluent.topic.ssl.truststore.type" : "JKS",
                    "confluent.topic.security.protocol" : "SSL",
                    "provenance.header.enable": true,
                    "topic.whitelist": "test-topic-ssl",
                    "topic.rename.format": "test-topic-ssl-duplicate",
                    "dest.kafka.bootstrap.servers": "broker:9092",
                    "dest.kafka.ssl.keystore.location" : "/etc/kafka/secrets/kafka.connect.keystore.jks",
                    "dest.kafka.ssl.keystore.password" : "confluent",
                    "dest.kafka.ssl.key.password" : "confluent",
                    "dest.kafka.ssl.truststore.location" : "/etc/kafka/secrets/kafka.connect.truststore.jks",
                    "dest.kafka.ssl.truststore.password" : "confluent",
                    "dest.kafka.security.protocol" : "SSL",
                    "src.kafka.bootstrap.servers": "broker:9092",
                    "src.kafka.ssl.keystore.location" : "/etc/kafka/secrets/kafka.connect.keystore.jks",
                    "src.kafka.ssl.keystore.password" : "confluent",
                    "src.kafka.ssl.key.password" : "confluent",
                    "src.kafka.ssl.truststore.location" : "/etc/kafka/secrets/kafka.connect.truststore.jks",
                    "src.kafka.ssl.truststore.password" : "confluent",
                    "src.kafka.security.protocol" : "SSL"
          }' \
     https://localhost:8083/connectors/duplicate-topic-ssl/config | jq .
```

Verify we have received the data in test-topic-ssl-duplicate topic

```bash
playground topic consume --topic test-topic-ssl-duplicate --min-expected-messages 10 --timeout 60
```

### With SASL_SSL authentication:


Sending messages to topic test-topic-sasl-ssl

```bash
$ seq 10 | docker exec -i broker kafka-console-producer --bootstrap-server broker:9092 --topic test-topic-sasl-ssl --producer.config /etc/kafka/secrets/client_without_interceptors.config
```

Creating Confluent Replicator connector with SASL_SSL authentication

```bash
$ curl -X PUT \
     --cert ../../environment/sasl-ssl/security/connect.certificate.pem --key ../../environment/sasl-ssl/security/connect.key --tlsv1.2 --cacert ../../environment/sasl-ssl/security/snakeoil-ca-1.crt \
     -H "Content-Type: application/json" \
     --data '{
                    "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
                    "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
                    "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
                    "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
                    "src.consumer.group.id": "duplicate-topic",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1",
                    "confluent.topic.ssl.keystore.location" : "/etc/kafka/secrets/kafka.connect.keystore.jks",
                    "confluent.topic.ssl.keystore.password" : "confluent",
                    "confluent.topic.ssl.key.password" : "confluent",
                    "confluent.topic.security.protocol" : "SASL_SSL",
                    "confluent.topic.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required  username=\"client\" password=\"client-secret\";",
                    "confluent.topic.sasl.mechanism": "PLAIN",
                    "provenance.header.enable": true,
                    "topic.whitelist": "test-topic-sasl-ssl",
                    "topic.rename.format": "test-topic-sasl-ssl-duplicate",
                    "dest.kafka.bootstrap.servers": "broker:9092",
                    "dest.kafka.ssl.keystore.location" : "/etc/kafka/secrets/kafka.connect.keystore.jks",
                    "dest.kafka.ssl.keystore.password" : "confluent",
                    "dest.kafka.ssl.key.password" : "confluent",
                    "dest.kafka.security.protocol" : "SASL_SSL",
                    "dest.kafka.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required  username=\"client\" password=\"client-secret\";",
                    "dest.kafka.sasl.mechanism": "PLAIN",
                    "src.kafka.bootstrap.servers": "broker:9092",
                    "src.kafka.ssl.keystore.location" : "/etc/kafka/secrets/kafka.connect.keystore.jks",
                    "src.kafka.ssl.keystore.password" : "confluent",
                    "src.kafka.ssl.key.password" : "confluent",
                    "src.kafka.security.protocol" : "SASL_SSL",
                    "src.kafka.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required  username=\"client\" password=\"client-secret\";",
                    "src.kafka.sasl.mechanism": "PLAIN"
          }' \
     https://localhost:8083/connectors/replicator-sasl-ssl/config | jq .
```

Verify we have received the data in test-topic-sasl-ssl-duplicate topic

```bash
playground topic consume --topic test-topic-sasl-ssl-duplicate --min-expected-messages 10 --timeout 60
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
