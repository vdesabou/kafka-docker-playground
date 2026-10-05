#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

MARKETO_ENDPOINT_URL=${MARKETO_ENDPOINT_URL:-$1}
MARKETO_CLIENT_ID=${MARKETO_CLIENT_ID:-$2}
MARKETO_CLIENT_SECRET=${MARKETO_CLIENT_SECRET:-$3}

if [ -z "$MARKETO_ENDPOINT_URL" ]
then
     logerror "MARKETO_ENDPOINT_URL is not set. Export it as environment variable or pass it as argument. Example: https://<munchkin-id>.mktorest.com"
     exit 1
fi

if [ -z "$MARKETO_CLIENT_ID" ]
then
     logerror "MARKETO_CLIENT_ID is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$MARKETO_CLIENT_SECRET" ]
then
     logerror "MARKETO_CLIENT_SECRET is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

MARKETO_ENDPOINT_URL=${MARKETO_ENDPOINT_URL%/}
MARKETO_ENDPOINT_URL=${MARKETO_ENDPOINT_URL%/rest}
# https://123-ABC-456.mktorest.com -> 123-ABC-456
MARKETO_MUNCHKIN_ID=$(echo "$MARKETO_ENDPOINT_URL" | sed -E 's#https?://([^.]*)\..*#\1#')
log "Marketo Munchkin ID is $MARKETO_MUNCHKIN_ID"

function marketo_access_token {
    curl -s --fail-with-body "$MARKETO_ENDPOINT_URL/identity/oauth/token?grant_type=client_credentials&client_id=$MARKETO_CLIENT_ID&client_secret=$MARKETO_CLIENT_SECRET" | jq -r '.access_token'
}

LEAD_PREFIX="playground-${USER}-${GITHUB_RUN_NUMBER}${TAG_BASE}-$RANDOM"
LEAD_EMAILS="$LEAD_PREFIX-1@example.com,$LEAD_PREFIX-2@example.com,$LEAD_PREFIX-3@example.com"

function cleanup_cloud_resources {
    set +e
    log "Deleting leads $LEAD_EMAILS"
    access_token=$(marketo_access_token)
    ids=$(curl -s "$MARKETO_ENDPOINT_URL/rest/v1/leads.json?filterType=email&filterValues=$LEAD_EMAILS&fields=id" -H "Authorization: Bearer $access_token" | jq -c '[.result[]? | {id}]')
    if [ "$ids" != "[]" ] && [ -n "$ids" ]
    then
        curl -s -X POST "$MARKETO_ENDPOINT_URL/rest/v1/leads/delete.json" -H "Authorization: Bearer $access_token" -H "Content-Type: application/json" -d "{\"input\": $ids}"
        echo ""
    fi
}
trap cleanup_cloud_resources EXIT

bootstrap_ccloud_environment

set +e
playground topic delete --topic marketo-leads
sleep 3
playground topic create --topic marketo-leads --nb-partitions 1
set -e

# each record must contain the operation, and the lead fields in data
log "Sending 3 upsert_lead records to topic marketo-leads"
playground topic produce -t marketo-leads --nb-messages 3 << EOF
{"operation": "upsert_lead", "data": {"lookupField": "email", "email": "$LEAD_PREFIX-1@example.com", "firstName": "John", "lastName": "Doe1"}}
{"operation": "upsert_lead", "data": {"lookupField": "email", "email": "$LEAD_PREFIX-2@example.com", "firstName": "John", "lastName": "Doe2"}}
{"operation": "upsert_lead", "data": {"lookupField": "email", "email": "$LEAD_PREFIX-3@example.com", "firstName": "John", "lastName": "Doe3"}}
EOF

connector_name="MarketoSink_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
  "connector.class": "MarketoSink",
  "name": "$connector_name",
  "kafka.auth.mode": "KAFKA_API_KEY",
  "kafka.api.key": "$CLOUD_KEY",
  "kafka.api.secret": "$CLOUD_SECRET",
  "topics": "marketo-leads",
  "input.data.format": "JSON",
  "marketo.munchkin.id": "$MARKETO_MUNCHKIN_ID",
  "marketo.client.id": "$MARKETO_CLIENT_ID",
  "marketo.client.secret": "$MARKETO_CLIENT_SECRET",
  "marketo.operation": "upsert_lead",
  "marketo.flush.interval.ms": "5000",
  "tasks.max": "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

sleep 30

playground connector show-lag --connector $connector_name

log "Verify leads are in Marketo"
MAX_WAIT=300
CUR_WAIT=0
nb_leads=0
while [ "$nb_leads" -lt 3 ]
do
    access_token=$(marketo_access_token)
    curl -s "$MARKETO_ENDPOINT_URL/rest/v1/leads.json?filterType=email&filterValues=$LEAD_EMAILS&fields=id,email,firstName,lastName" -H "Authorization: Bearer $access_token" > /tmp/result.log
    nb_leads=$(jq -r '.result | length' /tmp/result.log 2>/dev/null)
    if ! [[ "$nb_leads" =~ ^[0-9]+$ ]]
    then
        nb_leads=0
    fi
    log "⏳ $nb_leads/3 leads found in Marketo"
    if [ "$nb_leads" -ge 3 ]
    then
        break
    fi
    sleep 20
    CUR_WAIT=$(( CUR_WAIT+20 ))
    if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]
    then
        cat /tmp/result.log
        logerror "❌ leads were not found in Marketo after $MAX_WAIT seconds"
        exit 1
    fi
done
jq . /tmp/result.log

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name
