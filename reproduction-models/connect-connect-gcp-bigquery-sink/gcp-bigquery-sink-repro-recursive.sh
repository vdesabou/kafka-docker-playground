#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

PROJECT=${1:-vincent-de-saboulin-lab}

KEYFILE="${DIR}/keyfile.json"
if [ ! -f ${KEYFILE} ]
then
     logerror "ERROR: the file ${KEYFILE} file is not present!"
     exit 1
fi

DATASET=pg${USER}ds${GITHUB_RUN_NUMBER}${TAG}
DATASET=${DATASET//[-._]/}

log "Doing gsutil authentication"
set +e
docker rm -f gcloud-config
set -e
docker run -i -v ${KEYFILE}:/tmp/keyfile.json --name gcloud-config google/cloud-sdk:latest gcloud auth activate-service-account --project ${PROJECT} --key-file /tmp/keyfile.json

set +e
log "Drop dataset $DATASET, this might fail"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" rm -r -f -d "$DATASET"
set -e

log "Create dataset $PROJECT.$DATASET"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" mk --dataset --description "used by playground" "$DATASET"

# {
#     "fields": [
#         {
#             "default": null,
#             "name": "UnionField",
#             "type": [
#                 "null",
#                 {
#                     "fields": [
#                         {
#                             "default": false,
#                             "name": "InnerField",
#                             "type": [
#                                 "boolean",
#                                 "null"
#                             ]
#                         },
#                         {
# 							"default": null,
#                             "name": "InnerStructRecursive",
#                             "type": [
#                                 "null",
#                                 "InnerStruct"
#                             ]
#                         }
#                     ],
#                     "name": "InnerStruct",
#                     "type": "record"
#                 },
#                 {
#                     "fields": [
#                         {
#                             "default": false,
#                             "name": "InnerField",
#                             "type": [
#                                 "boolean",
#                                 "null"
#                             ]
#                         }
#                     ],
#                     "name": "InnerStruct2",
#                     "type": "record"
#                 }
#             ]
#         }
#     ],
#     "name": "OuterStruct",
#     "namespace": "com.example",
#     "type": "record"
# }

log "Send message with recursive definition (see field InnerStructRecursive) "
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic myavrotopic1 --property value.schema='{"fields":[{"default":null,"type":["null",{"fields":[{"default":false,"type":["boolean","null"],"name":"InnerField"},{"default":null,"type":["null","InnerStruct"],"name":"InnerStructRecursive"}],"type":"record","name":"InnerStruct"},{"fields":[{"default":false,"type":["boolean","null"],"name":"InnerField"}],"type":"record","name":"InnerStruct2"}],"name":"UnionField"}],"namespace":"com.example","name":"OuterStruct","type":"record"}' << EOF
{"UnionField":{"com.example.InnerStruct2":{"InnerField":{"boolean":true}}}}
EOF

if version_gt $CONNECTOR_TAG "1.9.9"
then
     log "Creating GCP BigQuery Sink connector gcp-bigquery-sink-1"
     curl -X PUT \
          -H "Content-Type: application/json" \
          --data '{
                    "connector.class": "com.wepay.kafka.connect.bigquery.BigQuerySinkConnector",
                    "tasks.max" : "1",
                    "topics" : "myavrotopic1",
                    "sanitizeTopics" : "true",
                    "autoCreateTables" : "true",
                    "autoUpdateSchemas" : "true",
                    "value.converter": "io.confluent.connect.avro.AvroConverter",
                    "value.converter.schema.registry.url": "http://schema-registry:8081",
                    "defaultDataset" : "'"$DATASET"'",
                    "mergeIntervalMs": "5000",
                    "bufferSize": "100000",
                    "maxWriteSize": "10000",
                    "tableWriteWait": "1000",
                    "sanitizeFieldNames": "true",
                    "project" : "'"$PROJECT"'",
                    "keyfile" : "/tmp/keyfile.json"
               }' \
          http://localhost:8083/connectors/gcp-bigquery-sink-1/config | jq .
else
     log "Creating GCP BigQuery Sink connector gcp-bigquery-sink-1"
     curl -X PUT \
          -H "Content-Type: application/json" \
          --data '{
                    "connector.class": "com.wepay.kafka.connect.bigquery.BigQuerySinkConnector",
                    "tasks.max" : "1",
                    "topics" : "myavrotopic1",
                    "sanitizeTopics" : "true",
                    "autoCreateTables" : "true",
                    "autoUpdateSchemas" : "true",
                    "schemaRetriever" : "com.wepay.kafka.connect.bigquery.schemaregistry.schemaretriever.SchemaRegistrySchemaRetriever",
                    "schemaRegistryLocation": "http://schema-registry:8081",
                    "value.converter": "io.confluent.connect.avro.AvroConverter",
                    "value.converter.schema.registry.url": "http://schema-registry:8081",
                    "mergeIntervalMs": "5000",
                    "bufferSize": "100000",
                    "maxWriteSize": "10000",
                    "tableWriteWait": "1000",
                    "sanitizeFieldNames": "true",
                    "datasets" : ".*='"$DATASET"'",
                    "project" : "'"$PROJECT"'",
                    "keyfile" : "/tmp/keyfile.json"
               }' \
          http://localhost:8083/connectors/gcp-bigquery-sink-1/config | jq .
fi

# with connector version 2.1.3:
# [2021-06-05 15:40:12,152] ERROR Task failed with com.wepay.kafka.connect.bigquery.exception.ConversionConnectException error: Kafka Connect schema contains cycle (com.wepay.kafka.connect.bigquery.write.batch.KCBQThreadPoolExecutor)
# Exception in thread "pool-5-thread-1" com.wepay.kafka.connect.bigquery.exception.ConversionConnectException: Kafka Connect schema contains cycle
#         at com.wepay.kafka.connect.bigquery.convert.BigQuerySchemaConverter.throwOnCycle(BigQuerySchemaConverter.java:129)
#         at com.wepay.kafka.connect.bigquery.convert.BigQuerySchemaConverter.lambda$throwOnCycle$1(BigQuerySchemaConverter.java:142)
#         at java.base/java.util.ArrayList.forEach(ArrayList.java:1541)
#         at com.wepay.kafka.connect.bigquery.convert.BigQuerySchemaConverter.throwOnCycle(BigQuerySchemaConverter.java:142)
#         at com.wepay.kafka.connect.bigquery.convert.BigQuerySchemaConverter.lambda$throwOnCycle$1(BigQuerySchemaConverter.java:142)
#         at java.base/java.util.ArrayList.forEach(ArrayList.java:1541)
#         at java.base/java.util.Collections$UnmodifiableCollection.forEach(Collections.java:1085)
#         at com.wepay.kafka.connect.bigquery.convert.BigQuerySchemaConverter.throwOnCycle(BigQuerySchemaConverter.java:142)
#         at com.wepay.kafka.connect.bigquery.convert.BigQuerySchemaConverter.lambda$throwOnCycle$1(BigQuerySchemaConverter.java:142)
#         at java.base/java.util.ArrayList.forEach(ArrayList.java:1541)
#         at java.base/java.util.Collections$UnmodifiableCollection.forEach(Collections.java:1085)
#         at com.wepay.kafka.connect.bigquery.convert.BigQuerySchemaConverter.throwOnCycle(BigQuerySchemaConverter.java:142)
#         at com.wepay.kafka.connect.bigquery.convert.BigQuerySchemaConverter.lambda$throwOnCycle$1(BigQuerySchemaConverter.java:142)
#         at java.base/java.util.ArrayList.forEach(ArrayList.java:1541)
#         at java.base/java.util.Collections$UnmodifiableCollection.forEach(Collections.java:1085)
#         at com.wepay.kafka.connect.bigquery.convert.BigQuerySchemaConverter.throwOnCycle(BigQuerySchemaConverter.java:142)
#         at com.wepay.kafka.connect.bigquery.convert.BigQuerySchemaConverter.convertSchema(BigQuerySchemaConverter.java:109)
#         at com.wepay.kafka.connect.bigquery.convert.BigQuerySchemaConverter.convertSchema(BigQuerySchemaConverter.java:46)
#         at com.wepay.kafka.connect.bigquery.SchemaManager.getBigQuerySchema(SchemaManager.java:507)
#         at com.wepay.kafka.connect.bigquery.SchemaManager.convertRecordSchema(SchemaManager.java:323)
#         at com.wepay.kafka.connect.bigquery.SchemaManager.getAndValidateProposedSchema(SchemaManager.java:294)
#         at com.wepay.kafka.connect.bigquery.SchemaManager.getTableInfo(SchemaManager.java:277)
#         at com.wepay.kafka.connect.bigquery.SchemaManager.createTable(SchemaManager.java:223)
#         at com.wepay.kafka.connect.bigquery.write.row.AdaptiveBigQueryWriter.attemptTableCreate(AdaptiveBigQueryWriter.java:168)
#         at com.wepay.kafka.connect.bigquery.write.row.AdaptiveBigQueryWriter.performWriteRequest(AdaptiveBigQueryWriter.java:115)
#         at com.wepay.kafka.connect.bigquery.write.row.BigQueryWriter.writeRows(BigQueryWriter.java:118)
#         at com.wepay.kafka.connect.bigquery.write.batch.TableWriter.run(TableWriter.java:96)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)


# with connector version 1.5.2 and 1.6.1:

# [2021-06-05 15:54:20,566] INFO Putting 1 records in the sink. (com.wepay.kafka.connect.bigquery.BigQuerySinkTask)
# [2021-06-05 15:54:21,735] ERROR Task failed with java.lang.StackOverflowError error: null (com.wepay.kafka.connect.bigquery.write.batch.KCBQThreadPoolExecutor)
# Exception in thread "pool-4-thread-1" java.lang.StackOverflowError
#         at com.wepay.kafka.connect.bigquery.convert.BigQuerySchemaConverter.convertField(BigQuerySchemaConverter.java:120)