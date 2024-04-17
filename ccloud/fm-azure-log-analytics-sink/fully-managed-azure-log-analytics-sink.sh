#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -z "$AZ_USER" ] && [ ! -z "$AZ_PASS" ]
then
    log "Logging to Azure using environment variables AZ_USER and AZ_PASS"
    set +e
    az logout
    set -e
    az login -u "$AZ_USER" -p "$AZ_PASS" > /dev/null 2>&1
else
    log "Logging to Azure using browser"
    az login
fi

# when AZURE_SUBSCRIPTION_NAME env var is set, we need to set the correct subscription
maybe_set_azure_subscription

AZURE_NAME=pg${USER}la${GITHUB_RUN_NUMBER}${TAG}
AZURE_NAME=${AZURE_NAME//[-._]/}
AZURE_RESOURCE_GROUP=$AZURE_NAME

AZURE_LOGANALYTICS_WORKSPACE_NAME=$AZURE_NAME
AZURE_REGION=westeurope

set +e
az group delete --name $AZURE_RESOURCE_GROUP --yes
set -e

log "Creating Azure Resource Group $AZURE_RESOURCE_GROUP"
az group create \
    --name $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION \
    --tags owner_email=$AZ_USER


# https://learn.microsoft.com/en-us/cli/azure/monitor/log-analytics/cluster?view=azure-cli-latest#az-monitor-log-analytics-cluster-create
log "Creating Azure Log Analytics workspace $AZURE_LOGANALYTICS_WORKSPACE_NAME"
az monitor log-analytics workspace create \
    --name $AZURE_LOGANALYTICS_WORKSPACE_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION

AZURE_LOG_ANALYTICS_WORKSPACE_ID=$(az monitor log-analytics workspace show \
    --name $AZURE_LOGANALYTICS_WORKSPACE_NAME \
    --resource-group $AZURE_RESOURCE_GROUP | jq -r '.customerId')

AZURE_LOG_ANALYTICS_SHARED_KEY=$(az monitor log-analytics workspace get-shared-keys \
    --name $AZURE_LOGANALYTICS_WORKSPACE_NAME \
    --resource-group $AZURE_RESOURCE_GROUP | jq -r '.primarySharedKey')

bootstrap_ccloud_environment

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
wait_for_ccloud_connector_up $connector_name 600

sleep 10

playground connector show-lag --connector $connector_name

az extension add --name log-analytics
az monitor log-analytics query \
    --workspace $AZURE_LOG_ANALYTICS_WORKSPACE_ID \
    --analytics-query 'log_analytics_topic_CL | limit 10' > /tmp/result.log  2>&1
cat /tmp/result.log
grep "first_name_s" /tmp/result.log

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name

log "Deleting resource group"
check_if_continue
az group delete --name $AZURE_RESOURCE_GROUP --yes --no-wait
