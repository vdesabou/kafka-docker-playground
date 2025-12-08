#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

login_and_maybe_set_azure_subscription

AZURE_NAME=pg${USER}fmla${GITHUB_RUN_NUMBER}${TAG_BASE}
AZURE_NAME=${AZURE_NAME//[-._]/}
if [ ${#AZURE_NAME} -gt 24 ]; then
  AZURE_NAME=${AZURE_NAME:0:24}
fi
AZURE_RESOURCE_GROUP=$AZURE_NAME

AZURE_LOGANALYTICS_WORKSPACE_NAME=$AZURE_NAME
AZURE_REGION=${AZURE_REGION:-westeurope}

set +e
az group delete --name $AZURE_RESOURCE_GROUP --yes
set -e

log "Creating Azure Resource Group $AZURE_RESOURCE_GROUP"
az group create \
    --name $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION \
    --tags owner_email=$AZ_USER cflt_managed_by=user cflt_managed_id="$USER"

function cleanup_cloud_resources {
    set +e
    log "Deleting resource group $AZURE_RESOURCE_GROUP"
    check_if_continue
    az group delete --name $AZURE_RESOURCE_GROUP --yes --no-wait
}
trap cleanup_cloud_resources EXIT

# https://learn.microsoft.com/en-us/cli/azure/monitor/log-analytics/cluster?view=azure-cli-latest#az-monitor-log-analytics-cluster-create
log "Creating Azure Log Analytics workspace $AZURE_LOGANALYTICS_WORKSPACE_NAME"
az monitor log-analytics workspace create \
    --name $AZURE_LOGANALYTICS_WORKSPACE_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION \
    --tags cflt_managed_by=user cflt_managed_id="$USER"

AZURE_LOG_ANALYTICS_WORKSPACE_ID=$(az monitor log-analytics workspace show \
    --name $AZURE_LOGANALYTICS_WORKSPACE_NAME \
    --resource-group $AZURE_RESOURCE_GROUP | jq -r '.customerId')

AZURE_LOG_ANALYTICS_SHARED_KEY=$(az monitor log-analytics workspace get-shared-keys \
    --name $AZURE_LOGANALYTICS_WORKSPACE_NAME \
    --resource-group $AZURE_RESOURCE_GROUP | jq -r '.primarySharedKey')

bootstrap_ccloud_environment "azure" "$AZURE_REGION"

set +e
playground topic delete --topic log_analytics_topic
sleep 3
playground topic create --topic log_analytics_topic --nb-partitions 1
set -e

log "Sending messages to topic log_analytics_topic"
playground topic produce -t log_analytics_topic --nb-messages 10 << 'EOF'
{
    "type": "record",
    "namespace": "com.github.vdesabou",
    "name": "Customer",
    "version": "1",
    "fields": [
        {
            "name": "count",
            "type": "long",
            "doc": "count"
        },
        {
            "name": "first_name",
            "type": "string",
            "doc": "First Name of Customer"
        },
        {
            "name": "last_name",
            "type": "string",
            "doc": "Last Name of Customer"
        },
        {
            "name": "address",
            "type": "string",
            "doc": "Address of Customer"
        }
    ]
}
EOF

connector_name="AzureLogAnalyticsSink_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
    "connector.class": "AzureLogAnalyticsSink",
    "name": "$connector_name",
    "kafka.auth.mode": "KAFKA_API_KEY",
    "kafka.api.key": "$CLOUD_KEY",
    "kafka.api.secret": "$CLOUD_SECRET",
    "topics": "log_analytics_topic",
    "input.data.format" : "AVRO",
    "azure.loganalytics.workspace.id": "$AZURE_LOG_ANALYTICS_WORKSPACE_ID",
    "azure.loganalytics.shared.key": "$AZURE_LOG_ANALYTICS_SHARED_KEY",
    "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

sleep 10

playground connector show-lag --connector $connector_name

if [ -z "$GITHUB_RUN_NUMBER" ]
then
    # do not test in CI, only rely on lag

    # https://learn.microsoft.com/en-us/azure/azure-monitor/logs/data-ingestion-time#checking-ingestion-time
    # there is known latency: "The average latency to ingest log data is between 20 seconds and 3 minutes."

    sleep 180

    az extension add --name log-analytics
    az monitor log-analytics query \
        --workspace $AZURE_LOG_ANALYTICS_WORKSPACE_ID \
        --analytics-query 'log_analytics_topic_CL | limit 10' > /tmp/result.log  2>&1
    cat /tmp/result.log
    grep "first_name_s" /tmp/result.log
fi

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name