#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PROJECT=${1:-vincent-de-saboulin-lab}

KEYFILE="${DIR}/keyfile.json"
if [ ! -f ${KEYFILE} ]
then
     logerror "ERROR: the file ${KEYFILE} file is not present!"
     exit 1
fi

for component in producer-repro-100661
do
    set +e
    log "🏗 Building jar for ${component}"
    docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${DIR}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
    if [ $? != 0 ]
    then
        logerror "ERROR: failed to build java component "
        tail -500 /tmp/result.log
        exit 1
    fi
    set -e
done

${DIR}/../../environment/2way-ssl/start.sh "${PWD}/docker-compose.2way-ssl.repro-100661-overriding-connector-to-use-topicrecordnamestrategy.yml"

GCS_BUCKET_NAME=kafka-docker-playground-bucket-${USER}${TAG}
GCS_BUCKET_NAME=${GCS_BUCKET_NAME//[-.]/}

log "Doing gsutil authentication"
set +e
docker rm -f gcloud-config
set -e
docker run -i -v ${KEYFILE}:/tmp/keyfile.json --name gcloud-config google/cloud-sdk:latest gcloud auth activate-service-account --project ${PROJECT} --key-file /tmp/keyfile.json

log "Creating bucket name <$GCS_BUCKET_NAME>, if required"
set +e
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gsutil mb -p $(cat ${KEYFILE} | jq -r .project_id) gs://$GCS_BUCKET_NAME
set -e

log "Removing existing objects in GCS, if applicable"
set +e
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gsutil -m rm -r gs://$GCS_BUCKET_NAME/topics/customer_avro
set -e


log "########"
log "##  SSL authentication"
log "########"

log "✨ Run the avro java producer which produces to topic customer_avro"
docker exec producer-repro-100661 bash -c "java ${JAVA_OPTS} -jar producer-1.0.0-jar-with-dependencies.jar"

log "Creating GCS Sink connector with SSL authentication"
curl -X PUT \
     --cert ../../environment/2way-ssl/security/connect.certificate.pem --key ../../environment/2way-ssl/security/connect.key --tlsv1.2 --cacert ../../environment/2way-ssl/security/snakeoil-ca-1.crt \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.gcs.GcsSinkConnector",
               "tasks.max" : "1",
               "topics" : "customer_avro",
               "gcs.bucket.name" : "'"$GCS_BUCKET_NAME"'",
               "gcs.part.size": "5242880",
               "flush.size": "3",
               "gcs.credentials.path": "/tmp/keyfile.json",
               "storage.class": "io.confluent.connect.gcs.storage.GcsStorage",
               "format.class": "io.confluent.connect.gcs.format.avro.AvroFormat",
               "partitioner.class": "io.confluent.connect.storage.partitioner.DefaultPartitioner",
               "schema.compatibility": "NONE",
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
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.value.subject.name.strategy": "io.confluent.kafka.serializers.subject.TopicRecordNameStrategy",
               "value.converter.schema.registry.url": "https://schema-registry:8081",
               "value.converter.basic.auth.credentials.source": "USER_INFO",
               "value.converter.basic.auth.user.info": "admin:admin"

          }' \
     https://localhost:8083/connectors/gcs-sink/config | jq .


sleep 10

log "Listing objects of in GCS"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gsutil ls gs://$GCS_BUCKET_NAME/topics/customer_avro/partition=0/

log "Getting one of the avro files locally and displaying content with avro-tools"
docker run -i --volumes-from gcloud-config -v /tmp:/tmp/ google/cloud-sdk:latest gsutil cp gs://$GCS_BUCKET_NAME/topics/customer_avro/partition=0/customer_avro+0+0000000000.avro /tmp/customer_avro+0+0000000000.avro

docker run --rm -v /tmp:/tmp actions/avro-tools tojson /tmp/customer_avro+0+0000000000.avro

docker rm -f gcloud-config