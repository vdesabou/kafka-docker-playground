#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

verify_installed "gcloud"

BUCKET_NAME=${1:-test-gcs-playground}

KEYFILE="${DIR}/keyfile.json"
if [ ! -f ${KEYFILE} ]
then
     log "ERROR: the file ${KEYFILE} file is not present!"
     exit 1
fi

${DIR}/../../environment/sasl-ssl/start.sh "${PWD}/docker-compose.sasl-ssl.yml"


log "Removing existing objects in GCS, if applicable"
set +e
gsutil rm -r gs://$BUCKET_NAME/topics/gcs_topic-ssl
gsutil rm -r gs://$BUCKET_NAME/topics/gcs_topic-sasl-ssl
set -e

log "########"
log "##  SASL_SSL authentication"
log "########"

log "Sending messages to topic gcs_topic-sasl-ssl"
seq -f "{\"f1\": \"This is a message sent with SASL_SSL authentication %g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9091 --topic gcs_topic-sasl-ssl --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}' --property schema.registry.url=https://schema-registry:8085 --producer.config /etc/kafka/secrets/client_without_interceptors.config

log "Creating GCS Sink connector with SASL_SSL authentication"
docker exec -e BUCKET_NAME="$BUCKET_NAME" connect \
     curl -X PUT \
     --cert /etc/kafka/secrets/connect.certificate.pem --key /etc/kafka/secrets/connect.key --tlsv1.2 --cacert /etc/kafka/secrets/snakeoil-ca-1.crt \
     -H "Content-Type: application/json" \
     --data '{
                    "connector.class": "io.confluent.connect.gcs.GcsSinkConnector",
                    "tasks.max" : "1",
                    "topics" : "gcs_topic-sasl-ssl",
                    "gcs.bucket.name" : "'"$BUCKET_NAME"'",
                    "gcs.part.size": "5242880",
                    "flush.size": "3",
                    "gcs.credentials.path": "/root/keyfiles/keyfile.json",
                    "storage.class": "io.confluent.connect.gcs.storage.GcsStorage",
                    "format.class": "io.confluent.connect.gcs.format.avro.AvroFormat",
                    "partitioner.class": "io.confluent.connect.storage.partitioner.DefaultPartitioner",
                    "schema.compatibility": "NONE",
                    "confluent.topic.bootstrap.servers": "broker:9091",
                    "confluent.topic.replication.factor": "1",
                    "confluent.topic.ssl.keystore.location" : "/etc/kafka/secrets/kafka.connect.keystore.jks",
                    "confluent.topic.ssl.keystore.password" : "confluent",
                    "confluent.topic.ssl.key.password" : "confluent",
                    "confluent.topic.security.protocol" : "SASL_SSL",
                    "confluent.topic.sasl.mechanism": "PLAIN",
                    "confluent.topic.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required  username=\"client\" password=\"client-secret\";"
          }' \
     https://localhost:8083/connectors/gcs-sink/config | jq_docker_cli .

sleep 10

log "Doing gsutil authentication"
gcloud auth activate-service-account --key-file ${KEYFILE}

log "Listing objects of in GCS"
gsutil ls gs://$BUCKET_NAME/topics/gcs_topic-sasl-ssl/partition=0/

log "Getting one of the avro files locally and displaying content with avro-tools"
gsutil cp gs://$BUCKET_NAME/topics/gcs_topic-sasl-ssl/partition=0/gcs_topic-sasl-ssl+0+0000000000.avro /tmp/


docker run -v /tmp:/tmp actions/avro-tools tojson /tmp/gcs_topic-sasl-ssl+0+0000000000.avro
