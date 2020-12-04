#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

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

if [ -z "$KSQLDB" ]
then
     ${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"
else
     ${DIR}/../../ksqldb/environment/start.sh "${PWD}/docker-compose.plaintext.yml"
fi

log "Login with sfdx CLI"
docker exec sfdx-cli sh -c "sfdx sfpowerkit:auth:login -u \"$SALESFORCE_USERNAME\" -p \"$SALESFORCE_PASSWORD\" -r \"$SALESFORCE_INSTANCE\" -s \"$SECURITY_TOKEN\""

# log "Send Platform Events"
# docker exec sfdx-cli sh -c "sfdx force:apex:execute  -u \"$SALESFORCE_USERNAME\" -f \"/tmp/event.apex\""

# log "Creating Salesforce Platform Events Source connector"
# curl -X PUT \
#      -H "Content-Type: application/json" \
#      --data '{
#                     "connector.class": "io.confluent.salesforce.SalesforcePlatformEventSourceConnector",
#                     "kafka.topic": "sfdc-platform-events",
#                     "tasks.max": "1",
#                     "curl.logging": "true",
#                     "salesforce.platform.event.name" : "MyPlatformEvent__e",
#                     "salesforce.instance" : "'"$SALESFORCE_INSTANCE"'",
#                     "salesforce.username" : "'"$SALESFORCE_USERNAME"'",
#                     "salesforce.password" : "'"$SALESFORCE_PASSWORD"'",
#                     "salesforce.password.token" : "'"$SECURITY_TOKEN"'",
#                     "salesforce.consumer.key" : "'"$CONSUMER_KEY"'",
#                     "salesforce.consumer.secret" : "'"$CONSUMER_PASSWORD"'",
#                     "salesforce.initial.start" : "all",
#                     "key.converter": "org.apache.kafka.connect.json.JsonConverter",
#                     "value.converter": "org.apache.kafka.connect.json.JsonConverter",
#                     "confluent.license": "",
#                     "confluent.topic.bootstrap.servers": "broker:9092",
#                     "confluent.topic.replication.factor": "1"
#           }' \
#      http://localhost:8083/connectors/salesforce-platform-events-source/config | jq .



# sleep 10

# log "Verify we have received the data in sfdc-platform-events topic"
# timeout 60 docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic sfdc-platform-events --from-beginning --max-messages 2

# this is the message if source connector is used
# {"schema":{"type":"struct","fields":[{"type":"string","optional":true,"field":"ReplayId"},{"type":"int64","optional":true,"name":"org.apache.kafka.connect.data.Timestamp","version":1,"field":"CreatedDate"},{"type":"string","optional":true,"field":"CreatedById"},{"type":"string","optional":true,"field":"Message__c"},{"type":"string","optional":true,"field":"_ObjectType"},{"type":"string","optional":true,"field":"_EventType"}],"optional":false,"name":"io.confluent.salesforce.MyPlatformEvent__e"},"payload":{"ReplayId":"2956549","CreatedDate":1596010416799,"CreatedById":"0052X00000AJGNCQA5","Message__c":"test message 1","_ObjectType":"MyPlatformEvent__e","_EventType":"ir4e6bGYBtJYSX5x2vc4DQ"}}

docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic sfdc-platform-events << EOF
{"schema":{"type":"struct","fields":[{"type":"string","optional":true,"field":"ReplayId"},{"type":"int64","optional":true,"name":"org.apache.kafka.connect.data.Timestamp","version":1,"field":"CreatedDate"},{"type":"string","optional":true,"field":"CreatedById"},{"type":"string","optional":true,"field":"Message__c"},{"type":"string","optional":true,"field":"_ObjectType"},{"type":"string","optional":true,"field":"_EventType"}],"optional":false,"name":"io.confluent.salesforce.MyPlatformEvent__e"},"payload":{"ReplayId":"2956549","CreatedDate":1596010416799,"CreatedById":"0052X00000AJGNCQA5","Message__c":"test message 1","_ObjectType":"MyPlatformEvent__e","_EventType":"ir4e6bGYBtJYSX5x2vc4DQ"}}
EOF

log "Creating Salesforce Platform Events Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                    "connector.class": "io.confluent.salesforce.SalesforcePlatformEventSinkConnector",
                    "topics": "sfdc-platform-events",
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
                    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
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
timeout 60 docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic success-responses --from-beginning --max-messages 2

# log "Verify topic error-responses"
# timeout 20 docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic error-responses --from-beginning --max-messages 1