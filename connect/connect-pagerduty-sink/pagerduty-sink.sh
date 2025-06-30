#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if version_gt $TAG_BASE "7.9.99" && ! version_gt $CONNECTOR_TAG "0.0.99"
then
     logwarn "minimal supported connector version is 1.0.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.0.html#supported-connector-versions-in-cp-8-0"
     exit 111
fi

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

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Sending messages to topic incidents"
playground topic produce -t incidents --nb-messages 3 --forced-value "{\"fromEmail\":\"$PAGERDUTY_USER_EMAIL\", \"serviceId\":\"$PAGERDUTY_SERVICE_ID\", \"incidentTitle\":\"Incident Title x %g\"}" << 'EOF'
{
  "fields": [
    {
      "name": "fromEmail",
      "type": "string"
    },
    {
      "name": "serviceId",
      "type": "string"
    },
    {
      "name": "incidentTitle",
      "type": "string"
    }
  ],
  "name": "details",
  "type": "record"
}
EOF

log "Creating PagerDuty Sink connector"
playground connector create-or-update --connector pagerduty-sink  << EOF
{
  "connector.class": "io.confluent.connect.pagerduty.PagerDutySinkConnector",
  "topics": "incidents",
  "pagerduty.api.key": "$PAGERDUTY_API_KEY",
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
}
EOF


sleep 10

log "Confirm that the incidents were created"
curl --request GET \
  --url https://api.pagerduty.com/incidents \
  --header "accept: application/vnd.pagerduty+json;version=2" \
  --header "authorization: Token token=$PAGERDUTY_API_KEY" \
  --header "content-type: application/json" \
  --data '{"time_zone": "UTC"}' > /tmp/result.log  2>&1
cat /tmp/result.log
grep "Incident Title x 1" /tmp/result.log