#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
BUCKET_NAME=${1:-test-gcs-playground} 

# Generate keys and certificates used for SSL
echo -e "Generate keys and certificates used for SSL"
(cd ${DIR}/../scripts/security && ./certs-create.sh)

${DIR}/../scripts/reset-cluster-sasl-ssl.sh

echo "Removing existing objects in GCS, if applicable"
set +e
gsutil rm -r gs://$BUCKET_NAME/topics/gcs_topic-ssl
gsutil rm -r gs://$BUCKET_NAME/topics/gcs_topic-sasl-ssl
set -e


echo "########"
echo "##  SSL authentication"
echo "########"

echo "Sending messages to topic gcs_topic-ssl"
seq -f "{\"f1\": \"This is a message sent with SSL authentication %g\"}" 10 | docker container exec -i connect kafka-avro-console-producer --broker-list kafka1:9091 --topic gcs_topic-ssl --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}' --property schema.registry.url=https://schemaregistry:8085 --producer.config /etc/kafka/secrets/client_without_interceptors.config

echo "Creating GCS Sink connector with SSL authentication"
docker-compose exec -e BUCKET_NAME="$BUCKET_NAME" connect \
     curl -X POST \
     --cert /etc/kafka/secrets/connect.certificate.pem --key /etc/kafka/secrets/connect.key --tlsv1.2 --cacert /etc/kafka/secrets/snakeoil-ca-1.crt \
     -H "Content-Type: application/json" \
     --data '{
               "name": "gcs",
               "config": {
                    "connector.class": "io.confluent.connect.gcs.GcsSinkConnector",
                    "tasks.max" : "1",
                    "topics" : "gcs_topic-ssl",
                    "gcs.bucket.name" : "'"$BUCKET_NAME"'",
                    "gcs.part.size": "5242880",
                    "flush.size": "3",
                    "gcs.credentials.path": "/root/keyfile.json",
                    "storage.class": "io.confluent.connect.gcs.storage.GcsStorage",
                    "format.class": "io.confluent.connect.gcs.format.avro.AvroFormat",
                    "partitioner.class": "io.confluent.connect.storage.partitioner.DefaultPartitioner",
                    "schema.compatibility": "NONE",
                    "confluent.topic.bootstrap.servers": "kafka1:11091",
                    "confluent.topic.replication.factor": "2",
                    "confluent.topic.ssl.keystore.location" : "/etc/kafka/secrets/kafka.connect.keystore.jks",
                    "confluent.topic.ssl.keystore.password" : "confluent",
                    "confluent.topic.ssl.key.password" : "confluent",
                    "confluent.topic.ssl.truststore.location" : "/etc/kafka/secrets/kafka.connect.truststore.jks",
                    "confluent.topic.ssl.truststore.password" : "confluent",
                    "confluent.topic.ssl.keystore.type" : "JKS",
                    "confluent.topic.ssl.truststore.type" : "JKS",
                    "confluent.topic.security.protocol" : "SSL"
          }}' \
     https://localhost:8083/connectors | jq .


sleep 10

echo "Listing objects of in GCS"
gsutil ls gs://$BUCKET_NAME/topics/gcs_topic-ssl/partition=0/

echo "Doing gsutil authentication"
gcloud auth activate-service-account --key-file ./keyfile.json

echo "Getting one of the avro files locally and displaying content with avro-tools"
gsutil cp gs://$BUCKET_NAME/topics/gcs_topic-ssl/partition=0/gcs_topic-ssl+0+0000000000.avro /tmp/

# brew install avro-tools
avro-tools tojson /tmp/gcs_topic-ssl+0+0000000000.avro

echo "########"
echo "##  SASL_SSL authentication"
echo "########"

echo "Sending messages to topic gcs_topic-sasl-ssl"
seq -f "{\"f1\": \"This is a message sent with SASL_SSL authentication %g\"}" 10 | docker container exec -i connect kafka-avro-console-producer --broker-list kafka1:9091 --topic gcs_topic-sasl-ssl --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}' --property schema.registry.url=https://schemaregistry:8085 --producer.config /etc/kafka/secrets/client_without_interceptors.config

echo "Creating GCS Sink connector with SASL_SSL authentication"
docker-compose exec -e BUCKET_NAME="$BUCKET_NAME" connect \
     curl -X POST \
     --cert /etc/kafka/secrets/connect.certificate.pem --key /etc/kafka/secrets/connect.key --tlsv1.2 --cacert /etc/kafka/secrets/snakeoil-ca-1.crt \
     -H "Content-Type: application/json" \
     --data '{
               "name": "gcs-sink-sasl-ssl",
               "config": {
                    "connector.class": "io.confluent.connect.gcs.GcsSinkConnector",
                    "tasks.max" : "1",
                    "topics" : "gcs_topic-sasl-ssl",
                    "gcs.bucket.name" : "'"$BUCKET_NAME"'",
                    "gcs.part.size": "5242880",
                    "flush.size": "3",
                    "gcs.credentials.path": "/root/keyfile.json",
                    "storage.class": "io.confluent.connect.gcs.storage.GcsStorage",
                    "format.class": "io.confluent.connect.gcs.format.avro.AvroFormat",
                    "partitioner.class": "io.confluent.connect.storage.partitioner.DefaultPartitioner",
                    "schema.compatibility": "NONE",
                    "confluent.topic.bootstrap.servers": "kafka1:9091",
                    "confluent.topic.replication.factor": "2",
                    "confluent.topic.ssl.keystore.location" : "/etc/kafka/secrets/kafka.connect.keystore.jks",
                    "confluent.topic.ssl.keystore.password" : "confluent",
                    "confluent.topic.ssl.key.password" : "confluent",
                    "confluent.topic.ssl.truststore.location" : "/etc/kafka/secrets/kafka.connect.truststore.jks",
                    "confluent.topic.ssl.truststore.password" : "confluent",
                    "confluent.topic.security.protocol" : "SASL_SSL",
                    "confluent.topic.sasl.mechanism": "PLAIN",
                    "confluent.topic.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required  username=\"client\" password=\"client-secret\";"
          }}' \
     https://localhost:8083/connectors | jq .

sleep 10

echo "Listing objects of in GCS"
gsutil ls gs://$BUCKET_NAME/topics/gcs_topic-sasl-ssl/partition=0/

echo "Doing gsutil authentication"
gcloud auth activate-service-account --key-file ./keyfile.json

echo "Getting one of the avro files locally and displaying content with avro-tools"
gsutil cp gs://$BUCKET_NAME/topics/gcs_topic-sasl-ssl/partition=0/gcs_topic-sasl-ssl+0+0000000000.avro /tmp/

# brew install avro-tools
avro-tools tojson /tmp/gcs_topic-sasl-ssl+0+0000000000.avro
