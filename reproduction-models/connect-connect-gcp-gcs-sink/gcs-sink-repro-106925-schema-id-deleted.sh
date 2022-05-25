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

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-106925-schema-id-deleted.yml"

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
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gsutil -m rm -r gs://$GCS_BUCKET_NAME/topics/gcs_topic
set -e

log "Sending messages to topic gcs_topic"
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic gcs_topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

log "SOFT Delete version 1"
curl --request DELETE \
  --url http://localhost:8081/subjects/gcs_topic-value/versions/1

log "HARD Delete version 1"
curl --request DELETE \
  --url http://localhost:8081/subjects/gcs_topic-value/versions/1?permanent=true

log "Show remaining version"
curl --request GET \
  --url http://localhost:8081/subjects/gcs_topic-value/versions 

log "Sending messages to topic gcs_topic"
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic gcs_topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string","doc": "toc"}]}'


log "Creating GCS Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.gcs.GcsSinkConnector",
               "tasks.max" : "1",
               "topics" : "gcs_topic",
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

               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "value.converter.auto.register.schemas" : "false",
               "value.converter.use.latest.version": "true"
          }' \
     http://localhost:8083/connectors/gcs-sink/config | jq .


# [2022-05-25 11:14:02,226] ERROR [gcs-sink2|task-0] WorkerSinkTask{id=gcs-sink2-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:207)
# org.apache.kafka.connect.errors.ConnectException: Tolerance exceeded in error handler
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndHandleError(RetryWithToleranceOperator.java:220)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execute(RetryWithToleranceOperator.java:142)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.convertAndTransformRecord(WorkerSinkTask.java:519)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.convertMessages(WorkerSinkTask.java:494)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:333)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:200)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:255)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.apache.kafka.connect.errors.DataException: Failed to deserialize data for topic gcs_topic to Avro: 
#         at io.confluent.connect.avro.AvroConverter.toConnectData(AvroConverter.java:124)
#         at org.apache.kafka.connect.storage.Converter.toConnectData(Converter.java:87)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.lambda$convertAndTransformRecord$5(WorkerSinkTask.java:519)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndRetry(RetryWithToleranceOperator.java:166)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndHandleError(RetryWithToleranceOperator.java:200)
#         ... 13 more
# Caused by: org.apache.kafka.common.errors.SerializationException: Error retrieving Avro value schema for id 1
#         at io.confluent.kafka.serializers.AbstractKafkaSchemaSerDe.toKafkaException(AbstractKafkaSchemaSerDe.java:259)
#         at io.confluent.kafka.serializers.AbstractKafkaAvroDeserializer$DeserializationContext.schemaForDeserialize(AbstractKafkaAvroDeserializer.java:360)
#         at io.confluent.kafka.serializers.AbstractKafkaAvroDeserializer.deserializeWithSchemaAndVersion(AbstractKafkaAvroDeserializer.java:164)
#         at io.confluent.connect.avro.AvroConverter$Deserializer.deserialize(AvroConverter.java:172)
#         at io.confluent.connect.avro.AvroConverter.toConnectData(AvroConverter.java:107)
#         ... 17 more
# Caused by: io.confluent.kafka.schemaregistry.client.rest.exceptions.RestClientException: Schema 1 not found; error code: 40403
#         at io.confluent.kafka.schemaregistry.client.rest.RestService.sendHttpRequest(RestService.java:297)
#         at io.confluent.kafka.schemaregistry.client.rest.RestService.httpRequest(RestService.java:367)
#         at io.confluent.kafka.schemaregistry.client.rest.RestService.getId(RestService.java:836)
#         at io.confluent.kafka.schemaregistry.client.rest.RestService.getId(RestService.java:809)
#         at io.confluent.kafka.schemaregistry.client.CachedSchemaRegistryClient.getSchemaByIdFromRegistry(CachedSchemaRegistryClient.java:277)
#         at io.confluent.kafka.schemaregistry.client.CachedSchemaRegistryClient.getSchemaBySubjectAndId(CachedSchemaRegistryClient.java:409)
#         at io.confluent.kafka.serializers.AbstractKafkaAvroDeserializer$DeserializationContext.schemaForDeserialize(AbstractKafkaAvroDeserializer.java:349)
#         ... 20 more

sleep 10

log "Listing objects of in GCS"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gsutil ls gs://$GCS_BUCKET_NAME/topics/gcs_topic/partition=0/

log "Getting one of the avro files locally and displaying content with avro-tools"
docker run -i --volumes-from gcloud-config -v /tmp:/tmp/ google/cloud-sdk:latest gsutil cp gs://$GCS_BUCKET_NAME/topics/gcs_topic/partition=0/gcs_topic+0+0000000000.avro /tmp/gcs_topic+0+0000000000.avro

docker run --rm -v /tmp:/tmp actions/avro-tools tojson /tmp/gcs_topic+0+0000000000.avro

docker rm -f gcloud-config