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


${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-98298-value-too-long-for-field.yml"

# this is the topic when source connector is used
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

# example of message
# {"ReplayId":"9004013","CreatedDate":1644345809665,"CreatedById":"0053a00000L9RsbAAF","EventUuid":"a870010c-2fda-4057-b95d-e14db56a6af1","Message__c":"","_ObjectType":"MyPlatformEvent__e","_EventType":"ir4e6bGYBtJYSX5x2vc4DQ"},"__confluent_index":59}

# EventUuid is Text(36)
# Message__c	Text(255)
docker exec -i connect kafka-json-schema-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic a-topic-ok --property value.schema='{"type":"object","properties":{"EventUuid":{"connect.index":3,"oneOf":[{"type":"null"},{"type":"string"}]},"_ObjectType":{"connect.index":5,"oneOf":[{"type":"null"},{"type":"string"}]},"ReplayId":{"connect.index":0,"oneOf":[{"type":"null"},{"type":"string"}]},"CreatedById":{"connect.index":2,"oneOf":[{"type":"null"},{"type":"string"}]},"CreatedDate":{"connect.index":1,"oneOf":[{"type":"null"},{"type":"integer","connect.version":1,"connect.type":"int64","title":"org.apache.kafka.connect.data.Timestamp"}]},"Message__c":{"connect.index":4,"oneOf":[{"type":"null"},{"type":"string"}]},"_EventType":{"connect.index":6,"oneOf":[{"type":"null"},{"type":"string"}]}},"title":"io.confluent.salesforce.MyPlatformEvent__e"}' << EOF
{"ReplayId":"9004013","CreatedDate":1644345809665,"CreatedById":"0053a00000L9RsbAAF","EventUuid":"a870010c-2fda-4057-b95d-e14db56a6af1a870010ca870010c-2fda-4057-b95d-e14db56a6af1a870010c","Message__c":"a870010c-2fda-4057-b95d-e14db56a6af1a870010ca870010c-2fda-4057-b95d-e14db56a6af1a870010ca870010c-2fda-4057-b95d-e14db56a6af1a870010ca870010c-2fda-4057-b95d-e14db56a6af1a870010ca870010c-2fda-4057-b95d-e14db56a6af1a870010ca870010c-2fda-4057-b95d-e14db56a6af1a870010ca870010c-2fda-4057-b95d-e14db56a6af1a870010ca870010c-2fda-4057-b95d-e14db56a6af1a870010ca870010c-2fda-4057-b95d-e14db56a6af1a870010ca870010c-2fda-4057-b95d-e14db56a6af1a870010ca870010c-2fda-4057-b95d-e14db56a6af1a870010ca870010c-2fda-4057-b95d-e14db56a6af1a870010c","_ObjectType":"MyPlatformEvent__e","_EventType":"ir4e6bGYBtJYSX5x2vc4DQ","_ObjectType":"MyPlatformEvent__e","_EventType":"ir4e6bGYBtJYSX5x2vc4DQ"},"__confluent_index":59}
EOF

curl --request PUT \
  --url http://localhost:8083/admin/loggers/io.confluent.salesforce \
  --header 'Accept: application/json' \
  --header 'Content-Type: application/json' \
  --data '{
	"level": "TRACE"
}'

log "Creating Salesforce Platform Events Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                    "connector.class": "io.confluent.salesforce.SalesforcePlatformEventSinkConnector",
                    "topics": "a-topic-ok",
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
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1",
                    "behavior.on.api.errors": "log"
          }' \
     http://localhost:8083/connectors/salesforce-platform-events-sink/config | jq .

sleep 10

# It will retry for 15 minutes by default: request.max.retries.time.ms = 900000:
# [2022-03-23 17:36:06,146] DEBUG [salesforce-platform-events-sink|task-0] Failed on initial attempt to write record to Salesforce (io.confluent.salesforce.platformevent.SalesforcePlatformEventSinkTask:65)
# org.apache.kafka.connect.errors.ConnectException: Exception encountered while calling salesforce
#         at io.confluent.salesforce.rest.SalesforceHttpClientUtil.postAndParse(SalesforceHttpClientUtil.java:122)
#         at io.confluent.salesforce.rest.SalesforceRestClientImpl.publishPlatformEvent(SalesforceRestClientImpl.java:413)
#         at io.confluent.salesforce.platformevent.SalesforcePlatformEventSinkTask.publishEvent(SalesforcePlatformEventSinkTask.java:95)
#         at io.confluent.salesforce.platformevent.SalesforcePlatformEventSinkTask.lambda$put$2(SalesforcePlatformEventSinkTask.java:55)
#         at java.base/java.util.ArrayList.forEach(ArrayList.java:1541)
#         at io.confluent.salesforce.platformevent.SalesforcePlatformEventSinkTask.put(SalesforcePlatformEventSinkTask.java:53)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:604)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:334)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: com.google.api.client.http.HttpResponseException: 400 Bad Request
# [{"message":"Value too long for field","errorCode":"STRING_TOO_LONG","fields":["Message__c"]}]
#         at com.google.api.client.http.HttpRequest.execute(HttpRequest.java:1097)
#         at io.confluent.salesforce.rest.SalesforceHttpClientUtil.executeAndParse(SalesforceHttpClientUtil.java:98)
#         at io.confluent.salesforce.rest.SalesforceHttpClientUtil.postAndParse(SalesforceHttpClientUtil.java:120)
#         ... 16 more

docker exec -i connect kafka-json-schema-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic a-topic-ok --property value.schema='{"type":"object","properties":{"EventUuid":{"connect.index":3,"oneOf":[{"type":"null"},{"type":"string"}]},"_ObjectType":{"connect.index":5,"oneOf":[{"type":"null"},{"type":"string"}]},"ReplayId":{"connect.index":0,"oneOf":[{"type":"null"},{"type":"string"}]},"CreatedById":{"connect.index":2,"oneOf":[{"type":"null"},{"type":"string"}]},"CreatedDate":{"connect.index":1,"oneOf":[{"type":"null"},{"type":"integer","connect.version":1,"connect.type":"int64","title":"org.apache.kafka.connect.data.Timestamp"}]},"Message__c":{"connect.index":4,"oneOf":[{"type":"null"},{"type":"string"}]},"_EventType":{"connect.index":6,"oneOf":[{"type":"null"},{"type":"string"}]}},"title":"io.confluent.salesforce.MyPlatformEvent__e"}' << EOF
{"ReplayId":"9004015","CreatedDate":1644345809665,"CreatedById":"0053a00000L9RsbAAF","EventUuid":"a870010c-2fda-4057-b95d-e14db56a6af1","Message__c":"Vincent after","_ObjectType":"MyPlatformEvent__e","_EventType":"ir4e6bGYBtJYSX5x2vc4DQ"},"__confluent_index":59}
EOF

log "Verify topic success-responses"
timeout 60 docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic success-responses --from-beginning --max-messages 2

# log "Verify topic error-responses"
# timeout 20 docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic error-responses --from-beginning --max-messages 1


# with "request.max.retries.time.ms": "1000":

# [2022-03-24 08:44:58,299] ERROR [salesforce-platform-events-sink|task-0] Retry timeout reached. No more retries. (io.confluent.salesforce.platformevent.SalesforcePlatformEventSinkTask:113)
# [2022-03-24 08:44:58,313] INFO [salesforce-platform-events-sink|task-0] Skipping Bad record.  Kafka Record info topic: a-topic-ok, partition number: 0, offset: 0 (io.confluent.salesforce.platformevent.SalesforcePlatformEventSinkTask:77)
# org.apache.kafka.connect.errors.ConnectException: Exception encountered while calling salesforce
#         at io.confluent.salesforce.rest.SalesforceHttpClientUtil.postAndParse(SalesforceHttpClientUtil.java:122)
#         at io.confluent.salesforce.rest.SalesforceRestClientImpl.publishPlatformEvent(SalesforceRestClientImpl.java:413)
#         at io.confluent.salesforce.platformevent.SalesforcePlatformEventSinkTask.publishEvent(SalesforcePlatformEventSinkTask.java:95)
#         at io.confluent.salesforce.platformevent.SalesforcePlatformEventSinkTask.lambda$put$2(SalesforcePlatformEventSinkTask.java:55)
#         at java.base/java.util.ArrayList.forEach(ArrayList.java:1541)
#         at io.confluent.salesforce.platformevent.SalesforcePlatformEventSinkTask.put(SalesforcePlatformEventSinkTask.java:53)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:604)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:334)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: com.google.api.client.http.HttpResponseException: 400 Bad Request
# [{"message":"Value too long for field","errorCode":"STRING_TOO_LONG","fields":["Message__c"]}]
#         at com.google.api.client.http.HttpRequest.execute(HttpRequest.java:1097)
#         at io.confluent.salesforce.rest.SalesforceHttpClientUtil.executeAndParse(SalesforceHttpClientUtil.java:98)
#         at io.confluent.salesforce.rest.SalesforceHttpClientUtil.postAndParse(SalesforceHttpClientUtil.java:120)
#         ... 16 more