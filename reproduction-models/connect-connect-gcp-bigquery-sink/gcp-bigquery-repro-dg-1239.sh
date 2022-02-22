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

# schema
# {
#     "fields": [
#         {
#             "default": null,
#             "name": "userType",
#             "type": [
#                 "null",
#                 {
#                     "type": "string",
#                     "avro.java.string": "String"
#                 },
#                 {
#                     "name": "UserType",
#                     "symbols": [
#                         "ANONYMOUS",
#                         "REGISTERED"
#                     ],
#                     "type": "enum"
#                 }
#             ]
#         }
#     ],
#     "name": "EnumStringUnion",
#     "namespace": "com.connect.avro",
#     "type": "record"
# }
log "Send userType as string to topic myavrotopic1"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic myavrotopic1 --property value.schema='{"fields":[{"default":null,"name":"userType","type":["null",{"type":"string","avro.java.string":"String"},{"name":"UserType","symbols":["ANONYMOUS","REGISTERED"],"type":"enum"}]}],"name":"EnumStringUnion","namespace":"com.connect.avro","type":"record"}' << EOF
{"userType":{"string":"anystring"}}
EOF

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
               "value.converter.enhanced.avro.schema.support": "true",
               "defaultDataset" : "'"$DATASET"'",
               "mergeIntervalMs": "5000",
               "bufferSize": "100000",
               "maxWriteSize": "10000",
               "tableWriteWait": "1000",
               "project" : "'"$PROJECT"'",
               "keyfile" : "/tmp/keyfile.json"
          }' \
     http://localhost:8083/connectors/gcp-bigquery-sink-1/config | jq .

sleep 4

curl localhost:8083/connectors/gcp-bigquery-sink-1/status | jq

log "Send userType as enum to topic myavrotopic2"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic myavrotopic2 --property value.schema='{"fields":[{"default":null,"name":"userType","type":["null",{"type":"string","avro.java.string":"String"},{"name":"UserType","symbols":["ANONYMOUS","REGISTERED"],"type":"enum"}]}],"name":"EnumStringUnion","namespace":"com.connect.avro","type":"record"}' << EOF
{"userType":{"com.connect.avro.UserType":"ANONYMOUS"}}
EOF

log "Creating GCP BigQuery Sink connector gcp-bigquery-sink-2"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "com.wepay.kafka.connect.bigquery.BigQuerySinkConnector",
               "tasks.max" : "1",
               "topics" : "myavrotopic2",
               "sanitizeTopics" : "true",
               "autoCreateTables" : "true",
               "autoUpdateSchemas" : "true",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "value.converter.enhanced.avro.schema.support": "true",
               "defaultDataset" : "'"$DATASET"'",
               "mergeIntervalMs": "5000",
               "bufferSize": "100000",
               "maxWriteSize": "10000",
               "tableWriteWait": "1000",
               "project" : "'"$PROJECT"'",
               "keyfile" : "/tmp/keyfile.json"
          }' \
     http://localhost:8083/connectors/gcp-bigquery-sink-2/config | jq .

sleep 4

curl localhost:8083/connectors/gcp-bigquery-sink-2/status | jq

log "Send userType as null to topic myavrotopic3"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic myavrotopic3 --property value.schema='{"fields":[{"default":null,"name":"userType","type":["null",{"type":"string","avro.java.string":"String"},{"name":"UserType","symbols":["ANONYMOUS","REGISTERED"],"type":"enum"}]}],"name":"EnumStringUnion","namespace":"com.connect.avro","type":"record"}' << EOF
{"userType":null}
EOF

log "Creating GCP BigQuery Sink connector gcp-bigquery-sink-3"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "com.wepay.kafka.connect.bigquery.BigQuerySinkConnector",
               "tasks.max" : "1",
               "topics" : "myavrotopic3",
               "sanitizeTopics" : "true",
               "autoCreateTables" : "true",
               "autoUpdateSchemas" : "true",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "value.converter.enhanced.avro.schema.support": "true",
               "defaultDataset" : "'"$DATASET"'",
               "mergeIntervalMs": "5000",
               "bufferSize": "100000",
               "maxWriteSize": "10000",
               "tableWriteWait": "1000",
               "project" : "'"$PROJECT"'",
               "keyfile" : "/tmp/keyfile.json"
          }' \
     http://localhost:8083/connectors/gcp-bigquery-sink-3/config | jq .

sleep 4

curl localhost:8083/connectors/gcp-bigquery-sink-3/status | jq