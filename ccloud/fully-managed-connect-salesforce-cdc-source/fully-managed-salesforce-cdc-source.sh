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

bootstrap_ccloud_environment

if [ -f /tmp/delta_configs/env.delta ]
then
     source /tmp/delta_configs/env.delta
else
     logerror "ERROR: /tmp/delta_configs/env.delta has not been generated"
     exit 1
fi

set +e
delete_topic sfdc-cdc-contacts
sleep 3
create_topic sfdc-cdc-contacts
set -e

docker-compose build
docker-compose down -v --remove-orphans
docker-compose up -d

log "Login with sfdx CLI"
docker exec sfdx-cli sh -c "sfdx sfpowerkit:auth:login -u \"$SALESFORCE_USERNAME\" -p \"$SALESFORCE_PASSWORD\" -r \"$SALESFORCE_INSTANCE\" -s \"$SALESFORCE_SECURITY_TOKEN\""

log "Add a Contact to Salesforce"
docker exec sfdx-cli sh -c "sfdx data:create:record  --target-org \"$SALESFORCE_USERNAME\" -s Contact -v \"FirstName='John_$RANDOM' LastName='Doe_$RANDOM'\""

cat << EOF > connector.json
{
     "connector.class": "SalesforceCdcSource",
     "name": "SalesforceCdcSource",
     "kafka.auth.mode": "KAFKA_API_KEY",
     "kafka.api.key": "$CLOUD_KEY",
     "kafka.api.secret": "$CLOUD_SECRET",
     "kafka.topic": "sfdc-cdc-contacts",
     "salesforce.instance" : "$SALESFORCE_INSTANCE",
     "salesforce.username": "$SALESFORCE_USERNAME",
     "salesforce.password": "$SALESFORCE_PASSWORD",
     "salesforce.password.token": "$SALESFORCE_SECURITY_TOKEN",
     "salesforce.consumer.key": "$SALESFORCE_CONSUMER_KEY",
     "salesforce.consumer.secret": "$SALESFORCE_CONSUMER_PASSWORD",
     "salesforce.cdc.name": "ContactChangeEvent",
     "output.data.format": "JSON",
     "tasks.max": "1"
}
EOF

log "Connector configuration is:"
cat connector.json

set +e
log "Deleting fully managed connector, it might fail..."
delete_ccloud_connector connector.json
set -e

log "Creating fully managed connector"
create_ccloud_connector connector.json
wait_for_ccloud_connector_up connector.json 300

sleep 60

log "Verify we have received the data in sfdc-cdc-contacts topic"
timeout 60 docker run --rm -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SASL_JAAS_CONFIG="$SASL_JAAS_CONFIG" vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} kafka-console-consumer --topic sfdc-cdc-contacts --bootstrap-server $BOOTSTRAP_SERVERS --consumer-property ssl.endpoint.identification.algorithm=https --consumer-property sasl.mechanism=PLAIN --consumer-property security.protocol=SASL_SSL --consumer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=USER_INFO --property print.key=true --from-beginning --max-messages 1
