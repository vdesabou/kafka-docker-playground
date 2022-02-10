#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -z "$CI" ]
then
     # running with github actions
     if [ ! -f ../../secrets.properties ]
     then
          logerror "../../secrets.properties is not present!"
          exit 1
     fi
     source ../../secrets.properties > /dev/null 2>&1
fi

SALESFORCE_USERNAME=${SALESFORCE_USERNAME:-$1}
SALESFORCE_PASSWORD=${SALESFORCE_PASSWORD:-$2}
CONSUMER_KEY=${CONSUMER_KEY:-$3}
CONSUMER_PASSWORD=${CONSUMER_PASSWORD:-$4}
SECURITY_TOKEN=${SECURITY_TOKEN:-$5}
SALESFORCE_INSTANCE=${SALESFORCE_INSTANCE:-"https://login.salesforce.com"}

if [ -z "$SALESFORCE_USERNAME" ]
then
     logerror "SALESFORCE_USERNAME is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$SALESFORCE_PASSWORD" ]
then
     logerror "SALESFORCE_PASSWORD is not set. Export it as environment variable or pass it as argument"
     exit 1
fi


if [ -z "$CONSUMER_KEY" ]
then
     logerror "CONSUMER_KEY is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$CONSUMER_PASSWORD" ]
then
     logerror "CONSUMER_PASSWORD is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$SECURITY_TOKEN" ]
then
     logerror "SECURITY_TOKEN is not set. Export it as environment variable or pass it as argument"
     exit 1
fi


${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-91796-json-schema.yml"

# {
#   "properties": {
#     "CreatedById": {
#       "connect.index": 2,
#       "oneOf": [
#         {
#           "type": "null"
#         },
#         {
#           "type": "string"
#         }
#       ]
#     },
#     "CreatedDate": {
#       "connect.index": 1,
#       "oneOf": [
#         {
#           "type": "null"
#         },
#         {
#           "connect.type": "int64",
#           "connect.version": 1,
#           "title": "org.apache.kafka.connect.data.Timestamp",
#           "type": "integer"
#         }
#       ]
#     },
#     "EventUuid": {
#       "connect.index": 3,
#       "oneOf": [
#         {
#           "type": "null"
#         },
#         {
#           "type": "string"
#         }
#       ]
#     },
#     "Message__c": {
#       "connect.index": 4,
#       "oneOf": [
#         {
#           "type": "null"
#         },
#         {
#           "type": "string"
#         }
#       ]
#     },
#     "ReplayId": {
#       "connect.index": 0,
#       "oneOf": [
#         {
#           "type": "null"
#         },
#         {
#           "type": "string"
#         }
#       ]
#     },
#     "_EventType": {
#       "connect.index": 6,
#       "oneOf": [
#         {
#           "type": "null"
#         },
#         {
#           "type": "string"
#         }
#       ]
#     },
#     "_ObjectType": {
#       "connect.index": 5,
#       "oneOf": [
#         {
#           "type": "null"
#         },
#         {
#           "type": "string"
#         }
#       ]
#     }
#   },
#   "title": "io.confluent.salesforce.MyPlatformEvent__e",
#   "type": "object"
# }

# {"ReplayId":"9004013","CreatedDate":1644345809665,"CreatedById":"0053a00000L9RsbAAF","EventUuid":"a870010c-2fda-4057-b95d-e14db56a6af1","Message__c":"","_ObjectType":"MyPlatformEvent__e","_EventType":"ir4e6bGYBtJYSX5x2vc4DQ"},"__confluent_index":59}

docker exec -i connect kafka-json-schema-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic a-topic --property value.schema='{"type":"object","properties":{"EventUuid":{"connect.index":3,"oneOf":[{"type":"null"},{"type":"string"}]},"_ObjectType":{"connect.index":5,"oneOf":[{"type":"null"},{"type":"string"}]},"ReplayId":{"connect.index":0,"oneOf":[{"type":"null"},{"type":"string"}]},"CreatedById":{"connect.index":2,"oneOf":[{"type":"null"},{"type":"string"}]},"CreatedDate":{"connect.index":1,"oneOf":[{"type":"null"},{"type":"integer","connect.version":1,"connect.type":"int64","title":"org.apache.kafka.connect.data.Timestamp"}]},"Message__c":{"connect.index":4,"oneOf":[{"type":"null"},{"type":"string"}]},"_EventType":{"connect.index":6,"oneOf":[{"type":"null"},{"type":"string"}]}},"title":"io.confluent.salesforce.MyPlatformEvent__e"}' << EOF
{"ReplayId":"9004013","CreatedDate":1644345809665,"CreatedById":"0053a00000L9RsbAAF","EventUuid":"a870010c-2fda-4057-b95d-e14db56a6af1","Message__c":"","_ObjectType":"MyPlatformEvent__e","_EventType":"ir4e6bGYBtJYSX5x2vc4DQ"},"__confluent_index":59}
EOF


log "Verify we have received the data in a-topic topic"
timeout 60 docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic a-topic --from-beginning --max-messages 1

log "Creating Salesforce Platform Events Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                    "connector.class": "io.confluent.salesforce.SalesforcePlatformEventSinkConnector",
                    "topics": "a-topic",
                    "tasks.max": "1",
                    "curl.logging": "true",
                    "salesforce.platform.event.name" : "MyPlatformEvent__e",
                    "salesforce.instance" : "'"$SALESFORCE_INSTANCE"'",
                    "salesforce.username" : "'"$SALESFORCE_USERNAME"'",
                    "salesforce.password" : "'"$SALESFORCE_PASSWORD"'",
                    "salesforce.password.token" : "'"$SECURITY_TOKEN"'",
                    "salesforce.consumer.key" : "'"$CONSUMER_KEY"'",
                    "salesforce.consumer.secret" : "'"$CONSUMER_PASSWORD"'",
                    "salesforce.initial.start" : "all",
                    "connection.max.message.size": "10048576",
                    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "value.converter": "io.confluent.connect.json.JsonSchemaConverter",
                    "value.converter.schema.registry.url": "http://schema-registry:8081",
                    "reporter.bootstrap.servers": "broker:9092",
                    "reporter.error.topic.name": "error-responses",
                    "reporter.error.topic.replication.factor": 1,
                    "reporter.result.topic.name": "success-responses",
                    "reporter.result.topic.replication.factor": 1,
                    "transforms": "MaskField",
                    "transforms.MaskField.type": "org.apache.kafka.connect.transforms.MaskField$Value",
                    "transforms.MaskField.fields": "Message__c",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/salesforce-platform-events-sink/config | jq .

sleep 10

log "Verify topic success-responses"
timeout 60 docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic success-responses --from-beginning --max-messages 1

# log "Verify topic error-responses"
# timeout 20 docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic error-responses --from-beginning --max-messages 1