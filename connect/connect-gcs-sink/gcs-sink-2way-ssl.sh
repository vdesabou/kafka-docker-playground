#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

verify_installed "gcloud"

BUCKET_NAME=${1:-test-gcs-playground}

KEYFILE="${DIR}/keyfile.json"
if [ ! -f ${KEYFILE} ]
then
     echo -e "\033[0;33mERROR: the file ${KEYFILE} file is not present!\033[0m"
     exit 1
fi

${DIR}/../../environment/2way-ssl/start.sh "${PWD}/docker-compose.2way-ssl.yml"


echo -e "\033[0;33mRemoving existing objects in GCS, if applicable\033[0m"
set +e
gsutil rm -r gs://$BUCKET_NAME/topics/gcs_topic-ssl
set -e


echo -e "\033[0;33m########\033[0m"
echo -e "\033[0;33m##  SSL authentication\033[0m"
echo -e "\033[0;33m########\033[0m"

echo -e "\033[0;33mSending messages to topic gcs_topic-ssl\033[0m"
seq -f "{\"f1\": \"This is a message sent with SSL authentication %g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:11091 --topic gcs_topic-ssl --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}' --property schema.registry.url=https://schema-registry:8085 --producer.config /etc/kafka/secrets/client_without_interceptors_2way_ssl.config

echo -e "\033[0;33mCreating GCS Sink connector with SSL authentication\033[0m"
docker exec -e BUCKET_NAME="$BUCKET_NAME" connect \
     curl -X PUT \
     --cert /etc/kafka/secrets/connect.certificate.pem --key /etc/kafka/secrets/connect.key --tlsv1.2 --cacert /etc/kafka/secrets/snakeoil-ca-1.crt \
     -H "Content-Type: application/json" \
     --data '{
                    "connector.class": "io.confluent.connect.gcs.GcsSinkConnector",
                    "tasks.max" : "1",
                    "topics" : "gcs_topic-ssl",
                    "gcs.bucket.name" : "'"$BUCKET_NAME"'",
                    "gcs.part.size": "5242880",
                    "flush.size": "3",
                    "gcs.credentials.path": "/root/keyfiles/keyfile.json",
                    "storage.class": "io.confluent.connect.gcs.storage.GcsStorage",
                    "format.class": "io.confluent.connect.gcs.format.avro.AvroFormat",
                    "partitioner.class": "io.confluent.connect.storage.partitioner.DefaultPartitioner",
                    "schema.compatibility": "NONE",
                    "confluent.topic.bootstrap.servers": "broker:11091",
                    "confluent.topic.replication.factor": "1",
                    "confluent.topic.ssl.keystore.location" : "/etc/kafka/secrets/kafka.connect.keystore.jks",
                    "confluent.topic.ssl.keystore.password" : "confluent",
                    "confluent.topic.ssl.key.password" : "confluent",
                    "confluent.topic.ssl.truststore.location" : "/etc/kafka/secrets/kafka.connect.truststore.jks",
                    "confluent.topic.ssl.truststore.password" : "confluent",
                    "confluent.topic.ssl.keystore.type" : "JKS",
                    "confluent.topic.ssl.truststore.type" : "JKS",
                    "confluent.topic.security.protocol" : "SSL"
          }' \
     https://localhost:8083/connectors/gcs-sink/config | jq .


sleep 10

echo -e "\033[0;33mListing objects of in GCS\033[0m"
gsutil ls gs://$BUCKET_NAME/topics/gcs_topic-ssl/partition=0/

echo -e "\033[0;33mDoing gsutil authentication\033[0m"
gcloud auth activate-service-account --key-file ${KEYFILE}

echo -e "\033[0;33mGetting one of the avro files locally and displaying content with avro-tools\033[0m"
gsutil cp gs://$BUCKET_NAME/topics/gcs_topic-ssl/partition=0/gcs_topic-ssl+0+0000000000.avro /tmp/


docker run -v /tmp:/tmp actions/avro-tools tojson /tmp/gcs_topic-ssl+0+0000000000.avro
