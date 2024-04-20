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

bootstrap_ccloud_environment

set +e
playground topic delete --topic incidents
set -e

playground topic create --topic incidents

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


connector_name="PagerDutySink_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
  "connector.class": "PagerDutySink",
  "name": "$connector_name",
  "kafka.auth.mode": "KAFKA_API_KEY",
  "kafka.api.key": "$CLOUD_KEY",
  "kafka.api.secret": "$CLOUD_SECRET",
  "topics": "incidents",
  "pagerduty.api.key": "$PAGERDUTY_API_KEY",
  "input.data.format": "AVRO",
  "tasks.max": "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180


sleep 10

connectorId=$(get_ccloud_connector_lcc $connector_name)

log "Verifying topic success-$connectorId"
playground topic consume --topic success-$connectorId --min-expected-messages 3 --timeout 60

playground topic consume --topic error-$connectorId --min-expected-messages 0 --timeout 60

log "Confirm that the incidents were created"
curl --request GET \
  --url https://api.pagerduty.com/incidents \
  --header "accept: application/vnd.pagerduty+json;version=2" \
  --header "authorization: Token token=$PAGERDUTY_API_KEY" \
  --header "content-type: application/json" \
  --data '{"time_zone": "UTC"}' > /tmp/result.log  2>&1
cat /tmp/result.log
grep "Incident Title x 1" /tmp/result.log


log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name