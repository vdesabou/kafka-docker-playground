#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

bootstrap_ccloud_environment

# https://docs.confluent.io/cloud/current/connectors/cc-webhook-source.html#prerequisites
if [ "$CLUSTER_CLOUD" != "aws" ]
then
    logwarn "⏭️ the Webhook Source connector requires a Dedicated cluster on AWS, cluster $CLUSTER_NAME is on $CLUSTER_CLOUD"
    exit 111
fi
cluster_type=$(confluent kafka cluster describe -o json | jq -r '.type // empty')
if [ "$cluster_type" != "DEDICATED" ]
then
    # connector creation fails with "403 access denied to connect" otherwise
    logwarn "⏭️ the Webhook Source connector requires a Dedicated cluster on AWS, cluster $CLUSTER_NAME is $cluster_type"
    logwarn "   to use an existing Dedicated cluster, set CLUSTER_NAME, ENVIRONMENT, CLUSTER_CLOUD, CLUSTER_REGION and CLUSTER_CREDS"
    exit 111
fi

connector_name="WebhookSource_$USER"
topic="webhook-topic"
service_account=""
webhook_api_key=""

function cleanup_cloud_resources {
    set +e
    if [ -n "$service_account" ]
    then
        playground connector delete --connector $connector_name > /dev/null 2>&1
        if [ -n "$webhook_api_key" ]
        then
            log "❌ deleting webhook API key $webhook_api_key"
            confluent api-key delete "$webhook_api_key" --force > /dev/null 2>&1
        fi
        log "❌ deleting ACLs and service account $service_account"
        playground rbac acl delete --principal "User:$service_account" --operation DESCRIBE --resource Cluster:kafka-cluster > /dev/null 2>&1
        playground rbac acl delete --principal "User:$service_account" --operation CREATE --operation WRITE --resource "Topic:$topic" > /dev/null 2>&1
        playground rbac acl delete --principal "User:$service_account" --operation CREATE --operation WRITE --resource "Topic:error-lcc-" --prefix > /dev/null 2>&1
        confluent iam service-account delete "$service_account" --force > /dev/null 2>&1
    fi
}
trap cleanup_cloud_resources EXIT

set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
playground topic delete --topic $topic
sleep 3
playground topic create --topic $topic --nb-partitions 1
set -e

# the connector only supports kafka.auth.mode=SERVICE_ACCOUNT, and the endpoint is secured with a Global API key of that service account
service_account_name="pg-${USER}-webhook-${GITHUB_RUN_NUMBER}${TAG_BASE}-$RANDOM"
log "👤 creating service account $service_account_name"
service_account=$(confluent iam service-account create "$service_account_name" --description "Service account of fully managed connector $connector_name, created by kafka-docker-playground" -o json | jq -r '.id')
log "👤 service account is $service_account"

# the principal creating a connector with a service account must hold the Assigner role on it (OrgAdmin does)
set +e
owner=$(confluent api-key describe "$CONFLUENT_CLOUD_API_KEY" -o json 2>/dev/null | jq -r '(if type == "array" then .[0] else . end).owner // empty' 2>/dev/null)
if [ -n "$owner" ]
then
    confluent iam rbac role-binding create --principal "User:$owner" --role Assigner --resource "ServiceAccount:$service_account" > /dev/null 2>&1 || logwarn "🎩 could not grant Assigner role on $service_account to User:$owner"
fi
set -e

# https://docs.confluent.io/cloud/current/connectors/service-account.html (source connector), plus the error topic error-<lcc-id>
log "🚦 creating the ACLs of service account $service_account"
playground rbac acl create --principal "User:$service_account" --operation DESCRIBE --resource Cluster:kafka-cluster
playground rbac acl create --principal "User:$service_account" --operation CREATE --operation WRITE --resource "Topic:$topic"
playground rbac acl create --principal "User:$service_account" --operation CREATE --operation WRITE --resource "Topic:error-lcc-" --prefix

log "🔑 creating a Global API key for service account $service_account, used for HTTP Basic authentication on the webhook endpoint"
confluent api-key create --resource global --service-account "$service_account" --description "Webhook API key of $connector_name, created by kafka-docker-playground" -o json > /tmp/webhook-api-key.json
webhook_api_key=$(jq -r '.api_key' /tmp/webhook-api-key.json)
webhook_api_secret=$(jq -r '.api_secret' /tmp/webhook-api-key.json)
rm -f /tmp/webhook-api-key.json

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
  "connector.class": "WebhookSource",
  "name": "$connector_name",
  "kafka.auth.mode": "SERVICE_ACCOUNT",
  "kafka.service.account.id": "$service_account",
  "kafka.topic": "$topic",
  "webhook.topic.routing.mode": "NONE",
  "webhook.auth.mode": "API_KEY_SECRET",
  "webhook.api.key": "$webhook_api_key",
  "webhook.api.secret": "$webhook_api_secret",
  "output.data.format": "JSON_SR",
  "schema.enforcement.mode": "EVOLVE",
  "tasks.max": "2"
}
EOF
wait_for_ccloud_connector_up $connector_name 600

connector_id=$(confluent connect cluster list -o json | jq -r --arg name "$connector_name" '.[] | select(.name == $name) | .id')
log "🔎 getting the webhook endpoint URL of connector $connector_name ($connector_id)"
confluent connect cluster describe "$connector_id" -o json > /tmp/webhook-describe.json
webhook_url=$(jq -r '[.. | strings | select(test("^https://") and (test("confluent.cloud/connect/v1") | not))] | first // empty' /tmp/webhook-describe.json)
if [ -z "$webhook_url" ]
then
    jq . /tmp/webhook-describe.json
    logerror "❌ could not find the webhook endpoint URL of connector $connector_name"
    exit 1
fi
log "🪝 webhook endpoint URL is $webhook_url"

log "📨 sending one record to the webhook endpoint"
curl -s --fail-with-body -X POST "$webhook_url" \
    -u "$webhook_api_key:$webhook_api_secret" \
    -H "Content-Type: application/json" \
    -d '{"id": 1, "event": "order_created", "amount": 10.5}' | jq .

log "📨 sending a batch of two records, the second one with a new field (schema.enforcement.mode EVOLVE adds it as optional)"
curl -s --fail-with-body -X POST "$webhook_url" \
    -u "$webhook_api_key:$webhook_api_secret" \
    -H "Content-Type: application/json" \
    -d '[{"id": 2, "event": "order_updated", "amount": 12.0}, {"id": 3, "event": "order_shipped", "amount": 12.0, "carrier": "ups"}]' | jq .

log "Verify we have received the data in $topic topic"
playground topic consume --topic $topic --min-expected-messages 3 --timeout 60

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name
