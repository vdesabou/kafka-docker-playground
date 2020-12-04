#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PAGERDUTY_USER_EMAIL=${PAGERDUTY_USER_EMAIL:-$1}
PAGERDUTY_API_KEY=${PAGERDUTY_API_KEY:-$2}
PAGERDUTY_SERVICE_ID=${PAGERDUTY_SERVICE_ID:-$3}

if [ -z "$PAGERDUTY_USER_EMAIL" ]
then
     logerror "PAGERDUTY_USER_EMAIL is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$PAGERDUTY_API_KEY" ]
then
     logerror "PAGERDUTY_API_KEY is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$PAGERDUTY_SERVICE_ID" ]
then
     logerror "PAGERDUTY_SERVICE_ID is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$KSQLDB" ]
then
     ${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"
else
     ${DIR}/../../ksqldb/environment/start.sh "${PWD}/docker-compose.plaintext.yml"
fi

log "Sending messages to topic incidents"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic incidents --property value.schema='{"type":"record","name":"details","fields":[{"name":"fromEmail","type":"string"}, {"name":"serviceId","type":"string"},{"name":"incidentTitle","type":"string"}]}' << EOF
{"fromEmail":"$PAGERDUTY_USER_EMAIL", "serviceId":"$PAGERDUTY_SERVICE_ID", "incidentTitle":"Incident Title x 0"}
{"fromEmail":"$PAGERDUTY_USER_EMAIL", "serviceId":"$PAGERDUTY_SERVICE_ID", "incidentTitle":"Incident Title x 1"}
{"fromEmail":"$PAGERDUTY_USER_EMAIL", "serviceId":"$PAGERDUTY_SERVICE_ID", "incidentTitle":"Incident Title x 2"}
EOF

log "Creating PagerDuty Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                    "connector.class": "io.confluent.connect.pagerduty.PagerDutySinkConnector",
                    "topics": "incidents",
                    "pagerduty.api.key": "'"$PAGERDUTY_API_KEY"'",
                    "tasks.max": "1",
                    "behavior.on.error":"fail",
                    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "value.converter": "io.confluent.connect.avro.AvroConverter",
                    "value.converter.schema.registry.url": "http://schema-registry:8081",
                    "reporter.bootstrap.servers": "broker:9092",
                    "reporter.error.topic.replication.factor": 1,
                    "reporter.result.topic.replication.factor": 1,
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/pagerduty-sink/config | jq .


sleep 10

log "Confirm that the incidents were created"
curl --request GET \
  --url https://api.pagerduty.com/incidents \
  --header "accept: application/vnd.pagerduty+json;version=2" \
  --header "authorization: Token token=$PAGERDUTY_API_KEY" \
  --header "content-type: application/json" \
  --data '{"time_zone": "UTC"}'