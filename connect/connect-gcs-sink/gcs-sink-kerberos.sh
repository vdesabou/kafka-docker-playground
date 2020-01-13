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

${DIR}/../../environment/kerberos/start.sh "${PWD}/docker-compose.kerberos.yml"


log "Removing existing objects in GCS, if applicable"
set +e
gsutil rm -r gs://$BUCKET_NAME/topics/gcs_topic-kerberos
set -e


log "########"
log "##  Kerberos GSSAPI authentication"
log "########"

log "Sending messages to topic gcs_topic-kerberos"
docker exec -i client kinit -k -t /var/lib/secret/kafka-client.key kafka_producer
seq -f "{\"f1\": \"This is a message sent with Kerberos GSSAPI authentication %g\"}" 10 | docker exec -i client kafka-avro-console-producer --broker-list broker:9092 --topic gcs_topic-kerberos --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}' --property schema.registry.url=http://schema-registry:8081 --producer.config /etc/kafka/producer.properties

log "Creating GCS Sink connector with Kerberos GSSAPI authentication"
docker exec -e BUCKET_NAME="$BUCKET_NAME" connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.gcs.GcsSinkConnector",
                    "tasks.max" : "1",
                    "topics" : "gcs_topic-kerberos",
                    "gcs.bucket.name" : "'"$BUCKET_NAME"'",
                    "gcs.part.size": "5242880",
                    "flush.size": "3",
                    "gcs.credentials.path": "/root/keyfiles/keyfile.json",
                    "storage.class": "io.confluent.connect.gcs.storage.GcsStorage",
                    "format.class": "io.confluent.connect.gcs.format.avro.AvroFormat",
                    "partitioner.class": "io.confluent.connect.storage.partitioner.DefaultPartitioner",
                    "schema.compatibility": "NONE",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1",
                    "confluent.topic.sasl.mechanism": "GSSAPI",
                    "confluent.topic.sasl.kerberos.service.name": "kafka",
                    "confluent.topic.sasl.jaas.config" : "com.sun.security.auth.module.Krb5LoginModule required useKeyTab=true storeKey=true keyTab=\"/var/lib/secret/kafka-connect.key\" principal=\"connect@TEST.CONFLUENT.IO\";",
                    "confluent.topic.security.protocol" : "SASL_PLAINTEXT"
          }' \
     http://localhost:8083/connectors/gcs-sink/config | jq_docker_cli .

sleep 10

log "Doing gsutil authentication"
gcloud auth activate-service-account --key-file ${KEYFILE}

log "Listing objects of in GCS"
gsutil ls gs://$BUCKET_NAME/topics/gcs_topic-kerberos/partition=0/

log "Getting one of the avro files locally and displaying content with avro-tools"
gsutil cp gs://$BUCKET_NAME/topics/gcs_topic-kerberos/partition=0/gcs_topic-kerberos+0+0000000000.avro /tmp/


docker run -v /tmp:/tmp actions/avro-tools tojson /tmp/gcs_topic-kerberos+0+0000000000.avro

