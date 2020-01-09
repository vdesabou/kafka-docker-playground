#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../../environment/mdc-kerberos/start.sh

echo "Sending sales in Europe cluster"
seq -f "european_sale_%g ${RANDOM}" 10 | docker container exec -i client bash -c 'kinit -k -t /var/lib/secret/kafka-client.key kafka_producer && kafka-console-producer --broker-list broker-europe:9092 --topic sales_EUROPE --producer.config /etc/kafka/producer-europe.properties'

echo "Sending sales in US cluster"
seq -f "us_sale_%g ${RANDOM}" 10 | docker container exec -i client bash -c 'kinit -k -t /var/lib/secret/kafka-client.key kafka_producer && kafka-console-producer --broker-list broker-us:9092 --topic sales_US --producer.config /etc/kafka/producer-us.properties'

echo Consolidating all sales in the US

docker container exec -i connect-us bash -c 'kinit -k -t /var/lib/secret/kafka-connect.key connect'
docker container exec connect-us \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
          "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "src.consumer.group.id": "replicate-europe-to-us",
          "src.kafka.bootstrap.servers": "broker-europe:9092",
          "src.kafka.security.protocol" : "SASL_PLAINTEXT",
          "src.kafka.sasl.jaas.config": "com.sun.security.auth.module.Krb5LoginModule required useKeyTab=true storeKey=true keyTab=\"/var/lib/secret/kafka-connect.key\" principal=\"connect@TEST.CONFLUENT.IO\";",
          "src.kafka.sasl.mechanism": "GSSAPI",
          "src.kafka.sasl.kerberos.service.name": "kafka",
          "dest.kafka.bootstrap.servers": "broker-us:9092",
          "dest.kafka.security.protocol" : "SASL_PLAINTEXT",
          "dest.kafka.sasl.jaas.config": "com.sun.security.auth.module.Krb5LoginModule required useKeyTab=true storeKey=true keyTab=\"/var/lib/secret/kafka-connect.key\" principal=\"connect@TEST.CONFLUENT.IO\";",
          "dest.kafka.sasl.mechanism": "GSSAPI",
          "dest.kafka.sasl.kerberos.service.name": "kafka",
          "confluent.topic.bootstrap.servers": "broker-us:9092",
          "confluent.topic.replication.factor": 1,
          "confluent.topic.security.protocol" : "SASL_PLAINTEXT",
          "confluent.topic.sasl.jaas.config": "com.sun.security.auth.module.Krb5LoginModule required useKeyTab=true storeKey=true keyTab=\"/var/lib/secret/kafka-connect.key\" principal=\"connect@TEST.CONFLUENT.IO\";",
          "confluent.topic.sasl.mechanism": "GSSAPI",
          "confluent.topic.sasl.kerberos.service.name": "kafka",
          "provenance.header.enable": true,
          "topic.whitelist": "sales_EUROPE"
          }' \
     http://localhost:8083/connectors/replicate-europe-to-us/config | jq .


echo Consolidating all sales in Europe

docker container exec -i connect-europe bash -c 'kinit -k -t /var/lib/secret/kafka-connect.key connect'
docker container exec connect-europe \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
          "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "src.consumer.group.id": "replicate-us-to-europe",
          "src.kafka.bootstrap.servers": "broker-us:9092",
          "src.kafka.security.protocol" : "SASL_PLAINTEXT",
          "src.kafka.sasl.jaas.config": "com.sun.security.auth.module.Krb5LoginModule required useKeyTab=true storeKey=true keyTab=\"/var/lib/secret/kafka-connect.key\" principal=\"connect@TEST.CONFLUENT.IO\";",
          "src.kafka.sasl.mechanism": "GSSAPI",
          "src.kafka.sasl.kerberos.service.name": "kafka",
          "dest.kafka.bootstrap.servers": "broker-europe:9092",
          "dest.kafka.security.protocol" : "SASL_PLAINTEXT",
          "dest.kafka.sasl.jaas.config": "com.sun.security.auth.module.Krb5LoginModule required useKeyTab=true storeKey=true keyTab=\"/var/lib/secret/kafka-connect.key\" principal=\"connect@TEST.CONFLUENT.IO\";",
          "dest.kafka.sasl.mechanism": "GSSAPI",
          "dest.kafka.sasl.kerberos.service.name": "kafka",
          "confluent.topic.bootstrap.servers": "broker-europe:9092",
          "confluent.topic.replication.factor": 1,
          "confluent.topic.security.protocol" : "SASL_PLAINTEXT",
          "confluent.topic.sasl.jaas.config": "com.sun.security.auth.module.Krb5LoginModule required useKeyTab=true storeKey=true keyTab=\"/var/lib/secret/kafka-connect.key\" principal=\"connect@TEST.CONFLUENT.IO\";",
          "confluent.topic.sasl.mechanism": "GSSAPI",
          "confluent.topic.sasl.kerberos.service.name": "kafka",
          "provenance.header.enable": true,
          "topic.whitelist": "sales_US"
          }' \
     http://localhost:8083/connectors/replicate-us-to-europe/config | jq .

sleep 10

echo "Verify we have received the data in all the sales_ topics in EUROPE"
docker container exec -i client bash -c 'kinit -k -t /var/lib/secret/kafka-client.key kafka_consumer && kafka-console-consumer --bootstrap-server broker-europe:9092 --whitelist "sales_.*" --from-beginning --max-messages 20 --property metadata.max.age.ms 30000 --consumer.config /etc/kafka/consumer-europe.properties'

echo "Verify we have received the data in all the sales_ topics in the US"
docker container exec -i client bash -c 'kinit -k -t /var/lib/secret/kafka-client.key kafka_consumer && kafka-console-consumer --bootstrap-server broker-us:9092 --whitelist "sales_.*" --from-beginning --max-messages 20 --property metadata.max.age.ms 30000 --consumer.config /etc/kafka/consumer-us.properties'