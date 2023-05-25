#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.9.99"
then
    logwarn "WARN: this example does not support CP versions < 6.0.0 as JDK 11 was used to create keystore (error would be Invalid keystore format)"
    exit 111
fi

SALESFORCE_USERNAME=${SALESFORCE_USERNAME:-$1}
SALESFORCE_PASSWORD=${SALESFORCE_PASSWORD:-$2}
SALESFORCE_CONSUMER_KEY=${SALESFORCE_CONSUMER_KEY:-$3}
SALESFORCE_CONSUMER_PASSWORD=${SALESFORCE_CONSUMER_PASSWORD:-$4}
SALESFORCE_SECURITY_TOKEN=${SALESFORCE_SECURITY_TOKEN:-$5}
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


if [ -z "$SALESFORCE_CONSUMER_KEY_WITH_JWT" ]
then
     logerror "SALESFORCE_CONSUMER_KEY_WITH_JWT is not set. Export it as environment variable or pass it as argument. Check README !"
     exit 1
fi

if [ -z "$SALESFORCE_CONSUMER_PASSWORD_WITH_JWT" ]
then
     logerror "SALESFORCE_CONSUMER_PASSWORD_WITH_JWT is not set. Export it as environment variable or pass it as argument. Check README !"
     exit 1
fi

if [ -z "$SALESFORCE_SECURITY_TOKEN" ]
then
     logerror "SALESFORCE_SECURITY_TOKEN is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ ! -f ${PWD}/salesforce-confluent.keystore.jks ]
then
     get_3rdparty_file "salesforce-confluent.keystore.jks"
fi

if [ ! -f ${PWD}/salesforce-confluent.keystore.jks ]
then
     # not running with github actions
     logerror "ERROR: ${PWD}/salesforce-confluent.keystore.jks is missing. Check README !"
     exit 1
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.jwt-flow.yml"

log "Creating Salesforce CDC Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                    "connector.class": "io.confluent.salesforce.SalesforceCdcSourceConnector",
                    "kafka.topic": "sfdc-cdc-contacts",
                    "tasks.max": "1",
                    "curl.logging": "true",
                    "salesforce.instance" : "'"$SALESFORCE_INSTANCE"'",
                    "salesforce.cdc.name" : "ContactChangeEvent",
                    "__comment" : "from 2.0.0 salesforce.cdc.name is renamed salesforce.cdc.channel",
                    "salesforce.cdc.channel" : "ContactChangeEvent",
                    "salesforce.username" : "'"$SALESFORCE_USERNAME"'",
                    "salesforce.password" : "'"$SALESFORCE_PASSWORD"'",
                    "salesforce.password.token" : "'"$SALESFORCE_SECURITY_TOKEN"'",
                    "salesforce.initial.start" : "latest",
                    "connection.max.message.size": "10048576",
                    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1",

                    "salesforce.consumer.key" : "'"$SALESFORCE_CONSUMER_KEY_WITH_JWT"'",
                    "salesforce.consumer.secret" : "'"$SALESFORCE_CONSUMER_PASSWORD_WITH_JWT"'",
                    "salesforce.jwt.keystore.path": "/tmp/salesforce-confluent.keystore.jks",
                    "salesforce.jwt.keystore.password": "confluent"
          }' \
     http://localhost:8083/connectors/salesforce-cdc-source/config | jq .

sleep 5

log "Login with sfdx CLI"
docker exec sfdx-cli sh -c "sfdx sfpowerkit:auth:login -u \"$SALESFORCE_USERNAME\" -p \"$SALESFORCE_PASSWORD\" -r \"$SALESFORCE_INSTANCE\" -s \"$SALESFORCE_SECURITY_TOKEN\""

log "Add a Contact to Salesforce"
docker exec sfdx-cli sh -c "sfdx data:create:record  --target-org \"$SALESFORCE_USERNAME\" -s Contact -v \"FirstName='John_$RANDOM' LastName='Doe_$RANDOM'\""

sleep 10

log "Verify we have received the data in sfdc-cdc-contacts topic"
playground topic consume --topic sfdc-cdc-contacts --min-expected-messages 1 --timeout 60