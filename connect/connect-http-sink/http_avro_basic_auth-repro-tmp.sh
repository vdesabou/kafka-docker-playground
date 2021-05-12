#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

# {
#     "fields": [
#         {
#             "default": null,
#             "name": "userType",
#             "type": [
#                 "null",
#                 {
#                     "fields": [
#                         {
#                             "name": "isStoreStockAvailable",
#                             "type": [
#                                 "null",
#                                 "boolean"
#                             ]
#                         }
#                     ],
#                     "name": "StandardProductData",
#                     "type": "record"
#                 }
#             ]
#         }
#     ],
#     "name": "EnumStringUnion",
#     "namespace": "com.connect.avro",
#     "type": "record"
# }

log "Send userType as string to topic myavrotopicrepro2"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic myavrotopicrepro2 --property value.schema='{"fields":[{"default":null,"name":"userType","type":["null",{"fields":[{"name":"isStoreStockAvailable","type":["null","boolean"]}],"name":"StandardProductData","type":"record"}]}],"name":"EnumStringUnion","namespace":"com.connect.avro","type":"record"}' << EOF
{"userType":{"com.connect.avro.StandardProductData":{"isStoreStockAvailable":{"boolean": false}}}}
EOF

curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "topics": "myavrotopicrepro2",
          "tasks.max": "1",
          "connector.class": "io.confluent.connect.http.HttpSinkConnector",
          "key.converter": "org.apache.kafka.connect.storage.StringConverter",
          "value.converter": "io.confluent.connect.avro.AvroConverter",
          "value.converter.schema.registry.url": "http://schema-registry:8081",
          "value.converter.enhanced.avro.schema.support": "true",
          "confluent.topic.bootstrap.servers": "broker:9092",
          "confluent.topic.replication.factor": "1",
          "reporter.bootstrap.servers": "broker:9092",
          "reporter.error.topic.name": "error-responses",
          "reporter.error.topic.replication.factor": 1,
          "reporter.result.topic.name": "success-responses",
          "reporter.result.topic.replication.factor": 1,
          "http.api.url": "http://http-service-basic-auth:8080/api/messages",
          "request.body.format": "json",
          "auth.type": "BASIC",
          "connection.user": "admin",
          "connection.password": "password"
          }' \
     http://localhost:8083/connectors/myavrotopicrepro2/config | jq .

sleep 4

curl localhost:8083/connectors/myavrotopicrepro2/status | jq
