#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

GCS_BUCKET_NAME=${GCS_BUCKET_NAME:-$1}

if [ -z "$GCS_BUCKET_NAME" ]
then
     logerror "GCS_BUCKET_NAME is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

KEYFILE="${DIR}/keyfile.json"
if [ ! -f ${KEYFILE} ]
then
     logerror "ERROR: the file ${KEYFILE} file is not present!"
     exit 1
fi

${DIR}/../../environment/rbac-sasl-plain/start.sh "${PWD}/docker-compose.rbac-sasl-plain.yml"

log "Doing gsutil authentication"
set +e
docker rm -f gcloud-config
set -e
docker run -ti -v ${KEYFILE}:/tmp/keyfile.json --name gcloud-config google/cloud-sdk:latest gcloud auth activate-service-account --key-file /tmp/keyfile.json

log "Creating bucket name <$GCS_BUCKET_NAME>, if required"
set +e
docker run -ti --volumes-from gcloud-config google/cloud-sdk:latest docker run -ti -v ${KEYFILE}:/tmp/keyfile.json --name gcloud-config google/cloud-sdk:latest gsutil mb gs://$GCS_BUCKET_NAME
set -e

log "Removing existing objects in GCS, if applicable"
set +e
docker run -ti --volumes-from gcloud-config google/cloud-sdk:latest gsutil rm -r gs://$GCS_BUCKET_NAME/topics/rbac_gcs_topic
set -e


log "Sending messages to topic rbac_gcs_topic"
seq -f "{\"f1\": \"This is a message sent with RBAC SASL/PLAIN authentication %g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic rbac_gcs_topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}' --property schema.registry.url=http://schema-registry:8081 --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info=clientAvroCli:clientAvroCli --producer.config /etc/kafka/secrets/client_sasl_plain.config

log "Checking messages from topic rbac_gcs_topic"
docker exec -i connect kafka-avro-console-consumer --bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic rbac_gcs_topic  --property schema.registry.url=http://schema-registry:8081 --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info=clientAvroCli:clientAvroCli --consumer.config /etc/kafka/secrets/client_sasl_plain.config --consumer-property group.id=clientAvro --from-beginning --max-messages 1

log "Creating GCS Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     -u connectorSubmitter:connectorSubmitter \
     --data '{
               "connector.class": "io.confluent.connect.gcs.GcsSinkConnector",
                    "tasks.max" : "1",
                    "topics" : "rbac_gcs_topic",
                    "gcs.bucket.name" : "'"$GCS_BUCKET_NAME"'",
                    "gcs.part.size": "5242880",
                    "flush.size": "3",
                    "gcs.credentials.path": "/root/keyfiles/keyfile.json",
                    "storage.class": "io.confluent.connect.gcs.storage.GcsStorage",
                    "format.class": "io.confluent.connect.gcs.format.avro.AvroFormat",
                    "partitioner.class": "io.confluent.connect.storage.partitioner.DefaultPartitioner",
                    "schema.compatibility": "NONE",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1",
                    "confluent.topic.sasl.mechanism": "PLAIN",
                    "confluent.topic.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"admin\" password=\"admin-secret\";",
                    "confluent.topic.security.protocol" : "SASL_PLAINTEXT",
                    "value.converter": "io.confluent.connect.avro.AvroConverter",
                    "value.converter.schema.registry.url": "http://schema-registry:8081",
                    "value.converter.basic.auth.credentials.source": "USER_INFO",
                    "value.converter.basic.auth.user.info": "connectorSA:connectorSA",
                    "consumer.override.sasl.jaas.config": "org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required username=\"connectorSA\" password=\"connectorSA\" metadataServerUrls=\"http://broker:8091\";"
          }' \
     http://localhost:8083/connectors/gcs-rbac-sink/config | jq .

sleep 10

log "Listing objects of in GCS"
docker run -ti --volumes-from gcloud-config google/cloud-sdk:latest gsutil ls gs://$GCS_BUCKET_NAME/topics/rbac_gcs_topic/partition=0/

log "Getting one of the avro files locally and displaying content with avro-tools"
docker run -ti --volumes-from gcloud-config -v /tmp:/tmp/ google/cloud-sdk:latest gsutil cp gs://$GCS_BUCKET_NAME/topics/rbac_gcs_topic/partition=0/rbac_gcs_topic+0+0000000000.avro /tmp/rbac_gcs_topic+0+0000000000.avro

docker run -v /tmp:/tmp actions/avro-tools tojson /tmp/rbac_gcs_topic+0+0000000000.avro

docker rm -f gcloud-config