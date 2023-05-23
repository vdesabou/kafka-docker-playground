#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh



SALESFORCE_USERNAME=${SALESFORCE_USERNAME:-$1}
SALESFORCE_PASSWORD=${SALESFORCE_PASSWORD:-$2}
SALESFORCE_CONSUMER_KEY=${SALESFORCE_CONSUMER_KEY:-$3}
SALESFORCE_CONSUMER_PASSWORD=${SALESFORCE_CONSUMER_PASSWORD:-$4}
SALESFORCE_SECURITY_TOKEN=${SALESFORCE_SECURITY_TOKEN:-$5}
SALESFORCE_INSTANCE=${SALESFORCE_INSTANCE:-"https://login.salesforce.com"}

# second account (for Bulk API sink)
SALESFORCE_USERNAME_ACCOUNT2=${SALESFORCE_USERNAME_ACCOUNT2:-$6}
SALESFORCE_PASSWORD_ACCOUNT2=${SALESFORCE_PASSWORD_ACCOUNT2:-$7}
SALESFORCE_SECURITY_TOKEN_ACCOUNT2=${SALESFORCE_SECURITY_TOKEN_ACCOUNT2:-$8}
SALESFORCE_INSTANCE_ACCOUNT2=${SALESFORCE_INSTANCE_ACCOUNT2:-"https://login.salesforce.com"}

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


if [ -z "$SALESFORCE_CONSUMER_KEY" ]
then
     logerror "SALESFORCE_CONSUMER_KEY is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$SALESFORCE_CONSUMER_PASSWORD" ]
then
     logerror "SALESFORCE_CONSUMER_PASSWORD is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$SALESFORCE_SECURITY_TOKEN" ]
then
     logerror "SALESFORCE_SECURITY_TOKEN is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$SALESFORCE_USERNAME_ACCOUNT2" ]
then
     logerror "SALESFORCE_USERNAME_ACCOUNT2 is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$SALESFORCE_PASSWORD_ACCOUNT2" ]
then
     logerror "SALESFORCE_PASSWORD_ACCOUNT2 is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$SALESFORCE_SECURITY_TOKEN_ACCOUNT2" ]
then
     logerror "SALESFORCE_SECURITY_TOKEN_ACCOUNT2 is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

PUSH_TOPICS_NAME=MyLeadPushTopics${TAG}
PUSH_TOPICS_NAME=${PUSH_TOPICS_NAME//[-._]/}

sed -e "s|:PUSH_TOPIC_NAME:|$PUSH_TOPICS_NAME|g" \
    ../../connect/connect-salesforce-bulkapi-sink/MyLeadPushTopics-template.apex > ../../connect/connect-salesforce-bulkapi-sink/MyLeadPushTopics.apex

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.proxy.yml"

log "Login with sfdx CLI"
docker exec sfdx-cli sh -c "sfdx sfpowerkit:auth:login -u \"$SALESFORCE_USERNAME\" -p \"$SALESFORCE_PASSWORD\" -r \"$SALESFORCE_INSTANCE\" -s \"$SALESFORCE_SECURITY_TOKEN\""

LEAD_FIRSTNAME=John_$RANDOM
LEAD_LASTNAME=Doe_$RANDOM
log "Add a Lead to Salesforce: $LEAD_FIRSTNAME $LEAD_LASTNAME"
docker exec sfdx-cli sh -c "sfdx data:create:record  --target-org \"$SALESFORCE_USERNAME\" -s Lead -v \"FirstName='$LEAD_FIRSTNAME' LastName='$LEAD_LASTNAME' Company=Confluent\""

DOMAIN=$(echo $SALESFORCE_INSTANCE | cut -d "/" -f 3)
IP=$(nslookup $DOMAIN | grep Address | grep -v "#" | cut -d " " -f 2 | tail -1)
log "Blocking $DOMAIN IP $IP to make sure proxy is used"
docker exec --privileged --user root connect bash -c "iptables -A INPUT -p tcp -s $IP -j DROP"

DOMAIN=$(echo $SALESFORCE_INSTANCE_ACCOUNT2 | cut -d "/" -f 3)
IP=$(nslookup $DOMAIN | grep Address | grep -v "#" | cut -d " " -f 2 | tail -1)
log "Blocking $DOMAIN IP $IP to make sure proxy is used"
docker exec --privileged --user root connect bash -c "iptables -A INPUT -p tcp -s $IP -j DROP"

log "Creating Salesforce Bulk API Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                    "connector.class": "io.confluent.connect.salesforce.SalesforceBulkApiSourceConnector",
                    "kafka.topic": "sfdc-bulkapi-leads",
                    "tasks.max": "1",
                    "curl.logging": "true",
                    "salesforce.object" : "Lead",
                    "salesforce.instance" : "'"$SALESFORCE_INSTANCE"'",
                    "salesforce.username" : "'"$SALESFORCE_USERNAME"'",
                    "salesforce.password" : "'"$SALESFORCE_PASSWORD"'",
                    "salesforce.password.token" : "'"$SALESFORCE_SECURITY_TOKEN"'",
                    "http.proxy": "nginx-proxy:8888",
                    "connection.max.message.size": "10048576",
                    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/salesforce-bulkapi-source/config | jq .



sleep 10

log "Verify we have received the data in sfdc-bulkapi-leads topic"
playground topic consume --topic sfdc-bulkapi-leads --expected-messages 1

log "Creating Salesforce Bulk API Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                    "connector.class": "io.confluent.connect.salesforce.SalesforceBulkApiSinkConnector",
                    "topics": "sfdc-bulkapi-leads",
                    "tasks.max": "1",
                    "curl.logging": "true",
                    "salesforce.object" : "Lead",
                    "salesforce.instance" : "'"$SALESFORCE_INSTANCE_ACCOUNT2"'",
                    "salesforce.username" : "'"$SALESFORCE_USERNAME_ACCOUNT2"'",
                    "salesforce.password" : "'"$SALESFORCE_PASSWORD_ACCOUNT2"'",
                    "salesforce.password.token" : "'"$SALESFORCE_SECURITY_TOKEN_ACCOUNT2"'",
                    "http.proxy": "nginx-proxy:8888",
                    "salesforce.ignore.fields" : "CleanStatus",
                    "salesforce.ignore.reference.fields" : "true",
                    "connection.max.message.size": "10048576",
                    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "reporter.bootstrap.servers": "broker:9092",
                    "reporter.error.topic.name": "error-responses",
                    "reporter.error.topic.replication.factor": 1,
                    "reporter.result.topic.name": "success-responses",
                    "reporter.result.topic.replication.factor": 1,
                    "transforms" : "InsertField",
                    "transforms.InsertField.type" : "org.apache.kafka.connect.transforms.InsertField$Value",
                    "transforms.InsertField.static.field" : "_EventType",
                    "transforms.InsertField.static.value" : "created",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/salesforce-bulkapi-sink/config | jq .



sleep 10

log "Verify topic success-responses"
playground topic consume --topic success-responses --expected-messages 1

# log "Verify topic error-responses"
playground topic consume --topic error-responses --expected-messages 1

log "Login with sfdx CLI on the account #2"
docker exec sfdx-cli sh -c "sfdx sfpowerkit:auth:login -u \"$SALESFORCE_USERNAME_ACCOUNT2\" -p \"$SALESFORCE_PASSWORD_ACCOUNT2\" -r \"$SALESFORCE_INSTANCE_ACCOUNT2\" -s \"$SALESFORCE_SECURITY_TOKEN_ACCOUNT2\""

log "Get the Lead created on account #2"
docker exec sfdx-cli sh -c "sfdx force:data:record:get  -u \"$SALESFORCE_USERNAME_ACCOUNT2\" -s Lead -w \"FirstName='$LEAD_FIRSTNAME' LastName='$LEAD_LASTNAME' Company=Confluent\"" > /tmp/result.log  2>&1
cat /tmp/result.log
grep "$LEAD_FIRSTNAME" /tmp/result.log
