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

az extension add --name log-analytics

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

AZURE_LOG_ANALYTICS_WORKSPACE_RESOURCE_ID=$(az monitor log-analytics workspace show \
    --name $AZURE_LOGANALYTICS_WORKSPACE_NAME \
    --resource-group $AZURE_RESOURCE_GROUP | jq -r '.id')

AZURE_SUBSCRIPTION_ID=$(az account show | jq -r '.id')

AZURE_TENANT_ID=$(az account show | jq -r '.tenantId')
AZURE_APP_NAME=${AZURE_NAME}-fmla-v2-app
AZURE_CLIENT_ID=""
AZURE_CLIENT_SECRET=""
AZURE_LOGS_INGESTION_ENDPOINT=""
AZURE_DCR_RESOURCE_ID=""
AZURE_DCR_IMMUTABLE_ID=""
AZURE_TARGET_TABLE=log_analytics_topic_CL
AZURE_DCR_NAME=${AZURE_NAME}-dcr

log "Creating Log Analytics table $AZURE_TARGET_TABLE"
az rest \
    --method PUT \
    --url "https://management.azure.com${AZURE_LOG_ANALYTICS_WORKSPACE_RESOURCE_ID}/tables/${AZURE_TARGET_TABLE}?api-version=2022-10-01" \
    --body "{
        \"properties\": {
            \"schema\": {
                \"name\": \"${AZURE_TARGET_TABLE}\",
                \"columns\": [
                    {\"name\": \"TimeGenerated\", \"type\": \"DateTime\"},
                    {\"name\": \"count\", \"type\": \"Long\"},
                    {\"name\": \"first_name\", \"type\": \"String\"},
                    {\"name\": \"last_name\", \"type\": \"String\"},
                    {\"name\": \"address\", \"type\": \"String\"}
                ]
            }
        }
    }" > /dev/null

log "Creating Data Collection Rule $AZURE_DCR_NAME"
AZURE_DCR_RESOURCE_ID="/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${AZURE_RESOURCE_GROUP}/providers/Microsoft.Insights/dataCollectionRules/${AZURE_DCR_NAME}"
az rest \
    --method PUT \
    --url "https://management.azure.com${AZURE_DCR_RESOURCE_ID}?api-version=2023-03-11" \
    --body "{
        \"location\": \"${AZURE_REGION}\",
        \"kind\": \"Direct\",
        \"properties\": {
            \"streamDeclarations\": {
                \"Custom-${AZURE_TARGET_TABLE}\": {
                    \"columns\": [
                        {\"name\": \"count\", \"type\": \"long\"},
                        {\"name\": \"first_name\", \"type\": \"string\"},
                        {\"name\": \"last_name\", \"type\": \"string\"},
                        {\"name\": \"address\", \"type\": \"string\"}
                    ]
                }
            },
            \"destinations\": {
                \"logAnalytics\": [
                    {
                        \"workspaceResourceId\": \"${AZURE_LOG_ANALYTICS_WORKSPACE_RESOURCE_ID}\",
                        \"name\": \"laDestination\"
                    }
                ]
            },
            \"dataFlows\": [
                {
                    \"streams\": [\"Custom-${AZURE_TARGET_TABLE}\"],
                    \"destinations\": [\"laDestination\"],
                    \"transformKql\": \"source | extend TimeGenerated = now()\",
                    \"outputStream\": \"Custom-${AZURE_TARGET_TABLE}\"
                }
            ]
        }
    }" > /dev/null

log "Resolving DCR immutable ID from resource ID"
AZURE_DCR_IMMUTABLE_ID=$(az resource show --ids "$AZURE_DCR_RESOURCE_ID" --api-version 2023-03-11 --query 'properties.immutableId' -o tsv)

log "Resolving Logs Ingestion endpoint from DCR"
AZURE_LOGS_INGESTION_ENDPOINT=$(az resource show --ids "$AZURE_DCR_RESOURCE_ID" --api-version 2023-03-11 --query 'properties.endpoints.logsIngestion' -o tsv)
AZURE_LOGS_INGESTION_ENDPOINT=${AZURE_LOGS_INGESTION_ENDPOINT%/}

log "Creating Entra app/service principal $AZURE_APP_NAME"
AZURE_CLIENT_ID=$(az ad app create --display-name "$AZURE_APP_NAME" --query appId -o tsv)
az ad sp create --id "$AZURE_CLIENT_ID" > /dev/null
AZURE_CLIENT_SECRET=$(az ad app credential reset --id "$AZURE_CLIENT_ID" --append --query password -o tsv)

AZURE_SP_OBJECT_ID=$(az ad sp show --id "$AZURE_CLIENT_ID" --query id -o tsv)
log "Assigning Monitoring Metrics Publisher role on DCR"
set +e
az role assignment create \
    --assignee-object-id "$AZURE_SP_OBJECT_ID" \
    --assignee-principal-type ServicePrincipal \
    --role "Monitoring Metrics Publisher" \
    --scope "$AZURE_DCR_RESOURCE_ID" > /dev/null 2>&1
set -e

if [ -z "$AZURE_TENANT_ID" ] || [ -z "$AZURE_CLIENT_ID" ] || [ -z "$AZURE_CLIENT_SECRET" ] || [ -z "$AZURE_LOGS_INGESTION_ENDPOINT" ] || [ -z "$AZURE_DCR_IMMUTABLE_ID" ]
then
    log "Missing required Azure Logs Ingestion settings"
    log "Automatic provisioning failed for tenant/client credentials, ingestion endpoint or DCR immutable ID"
    exit 1
fi

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

connector_name="AzureLogAnalyticsSinkV2_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
    "connector.class": "AzureLogAnalyticsSinkV2",
    "name": "$connector_name",
    "kafka.auth.mode": "KAFKA_API_KEY",
    "kafka.api.key": "$CLOUD_KEY",
    "kafka.api.secret": "$CLOUD_SECRET",
    "topics": "log_analytics_topic",
    "input.data.format" : "AVRO",

    "azure.tenant.id": "$AZURE_TENANT_ID",
    "azure.client.id": "$AZURE_CLIENT_ID",
    "azure.client.secret": "$AZURE_CLIENT_SECRET",
    "azure.logs.ingestion.endpoint": "$AZURE_LOGS_INGESTION_ENDPOINT",
    "topic.to.table.map": "log_analytics_topic:$AZURE_TARGET_TABLE",
    "table.to.dcr.map": "$AZURE_TARGET_TABLE:$AZURE_DCR_IMMUTABLE_ID",
    "batch.size": "500",
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
        --analytics-query "$AZURE_TARGET_TABLE | limit 10" > /tmp/result.log  2>&1
    cat /tmp/result.log
    grep -E "first_name(_s)?" /tmp/result.log
fi

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name