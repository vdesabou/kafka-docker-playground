#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

login_and_maybe_set_azure_subscription

AZURE_NAME=pg${USER}fmkusto${GITHUB_RUN_NUMBER}${TAG_BASE}
AZURE_NAME=${AZURE_NAME//[-._]/}
# kusto cluster name: 4 to 22 lowercase letters and numbers
if [ ${#AZURE_NAME} -gt 22 ]; then
  AZURE_NAME=${AZURE_NAME:0:22}
fi
AZURE_RESOURCE_GROUP=$AZURE_NAME
AZURE_KUSTO_CLUSTER_NAME=$AZURE_NAME
AZURE_KUSTO_DATABASE=playground_db
AZURE_KUSTO_TABLE=kusto_topic
AZURE_KUSTO_MAPPING=kusto_topic_json_mapping
AZURE_REGION=${AZURE_REGION:-westeurope}

set +e
az group delete --name $AZURE_RESOURCE_GROUP --yes
set -e

log "Creating Azure Resource Group $AZURE_RESOURCE_GROUP"
az group create \
    --name $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION \
    --tags owner_email=$AZ_USER cflt_managed_by=user cflt_managed_id="$USER"

AZURE_TENANT_ID=$(az account show | jq -r '.tenantId')

if [ -z "$GITHUB_RUN_NUMBER" ]
then
    # not running with CI
    AZURE_APP_NAME=${AZURE_NAME}-kusto-app
    log "Creating Entra app/service principal $AZURE_APP_NAME"
    AZURE_KUSTO_CLIENT_ID=$(az ad app create --display-name "$AZURE_APP_NAME" --query appId -o tsv)
    az ad sp create --id "$AZURE_KUSTO_CLIENT_ID" > /dev/null
    AZURE_KUSTO_CLIENT_SECRET=$(az ad app credential reset --id "$AZURE_KUSTO_CLIENT_ID" --append --query password -o tsv)
else
    log "🚀 GitHub Action detected: Using pre-created Service Principal"
    AZURE_KUSTO_CLIENT_ID=$AZURE_LOGS_CLIENT_ID
    AZURE_KUSTO_CLIENT_SECRET=$AZURE_LOGS_CLIENT_SECRET
fi

if [ -z "$AZURE_TENANT_ID" ] || [ -z "$AZURE_KUSTO_CLIENT_ID" ] || [ -z "$AZURE_KUSTO_CLIENT_SECRET" ]
then
    logerror "❌ Missing tenant id, client id or client secret for the service principal"
    exit 1
fi

function cleanup_cloud_resources {
    set +e
    log "Deleting resource group $AZURE_RESOURCE_GROUP"
    check_if_continue
    az group delete --name $AZURE_RESOURCE_GROUP --yes --no-wait
    if [ -z "$GITHUB_RUN_NUMBER" ]
    then
        log "Deleting Entra app $AZURE_KUSTO_CLIENT_ID"
        az ad app delete --id "$AZURE_KUSTO_CLIENT_ID"
    fi
}
trap cleanup_cloud_resources EXIT

az extension add --name kusto

log "Creating Azure Data Explorer cluster $AZURE_KUSTO_CLUSTER_NAME (Dev SKU), this takes around 15 minutes"
az kusto cluster create \
    --cluster-name $AZURE_KUSTO_CLUSTER_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION \
    --sku name="Dev(No SLA)_Standard_E2a_v4" tier="Basic" capacity=1 \
    --tags cflt_managed_by=user cflt_managed_id="$USER" > /dev/null

AZURE_KUSTO_QUERY_URL=$(az kusto cluster show --cluster-name $AZURE_KUSTO_CLUSTER_NAME --resource-group $AZURE_RESOURCE_GROUP --query uri -o tsv)
AZURE_KUSTO_INGESTION_URL=$(az kusto cluster show --cluster-name $AZURE_KUSTO_CLUSTER_NAME --resource-group $AZURE_RESOURCE_GROUP --query dataIngestionUri -o tsv)

log "Creating database $AZURE_KUSTO_DATABASE"
az kusto database create \
    --cluster-name $AZURE_KUSTO_CLUSTER_NAME \
    --database-name $AZURE_KUSTO_DATABASE \
    --resource-group $AZURE_RESOURCE_GROUP \
    --read-write-database location=$AZURE_REGION soft-delete-period=P1D hot-cache-period=P1D > /dev/null

# run a KQL management command (endpoint /v1/rest/mgmt) or query (endpoint /v1/rest/query) against the database
function kusto_cmd {
    endpoint="$1"
    csl="$2"
    token=$(az account get-access-token --resource "$AZURE_KUSTO_QUERY_URL" --query accessToken -o tsv)
    jq -n --arg db "$AZURE_KUSTO_DATABASE" --arg csl "$csl" '{db: $db, csl: $csl}' | curl -s --fail-with-body -X POST "$AZURE_KUSTO_QUERY_URL/v1/rest/$endpoint" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json; charset=utf-8" \
        -d @-
}

log "Creating table $AZURE_KUSTO_TABLE"
kusto_cmd mgmt ".create table $AZURE_KUSTO_TABLE (id: long, first_name: string, last_name: string, address: string)" > /dev/null

log "Creating JSON ingestion mapping $AZURE_KUSTO_MAPPING"
kusto_cmd mgmt ".create table $AZURE_KUSTO_TABLE ingestion json mapping '$AZURE_KUSTO_MAPPING' '[{\"column\":\"id\",\"path\":\"$.id\",\"datatype\":\"long\"},{\"column\":\"first_name\",\"path\":\"$.first_name\",\"datatype\":\"string\"},{\"column\":\"last_name\",\"path\":\"$.last_name\",\"datatype\":\"string\"},{\"column\":\"address\",\"path\":\"$.address\",\"datatype\":\"string\"}]'" > /dev/null

log "Setting ingestion batching policy to 10 seconds (default is 5 minutes)"
kusto_cmd mgmt ".alter table $AZURE_KUSTO_TABLE policy ingestionbatching '{\"MaximumBatchingTimeSpan\":\"00:00:10\",\"MaximumNumberOfItems\":500,\"MaximumRawDataSizeMB\":1024}'" > /dev/null

log "Granting Database Ingestor and Database Viewer roles to service principal $AZURE_KUSTO_CLIENT_ID"
kusto_cmd mgmt ".add database $AZURE_KUSTO_DATABASE ingestors ('aadapp=$AZURE_KUSTO_CLIENT_ID;$AZURE_TENANT_ID')" > /dev/null
kusto_cmd mgmt ".add database $AZURE_KUSTO_DATABASE viewers ('aadapp=$AZURE_KUSTO_CLIENT_ID;$AZURE_TENANT_ID')" > /dev/null

bootstrap_ccloud_environment "azure" "$AZURE_REGION"

set +e
playground topic delete --topic kusto_topic
sleep 3
playground topic create --topic kusto_topic --nb-partitions 1
set -e

log "Sending messages to topic kusto_topic"
playground topic produce -t kusto_topic --nb-messages 10 << 'EOF'
{
    "type": "record",
    "namespace": "com.github.vdesabou",
    "name": "Customer",
    "version": "1",
    "fields": [
        {
            "name": "id",
            "type": "long",
            "doc": "id"
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

connector_name="AzureDataExplorerKustoSink_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
    "connector.class": "AzureDataExplorerKustoSink",
    "name": "$connector_name",
    "kafka.auth.mode": "KAFKA_API_KEY",
    "kafka.api.key": "$CLOUD_KEY",
    "kafka.api.secret": "$CLOUD_SECRET",
    "topics": "kusto_topic",
    "input.data.format": "AVRO",
    "kusto.ingestion.url": "$AZURE_KUSTO_INGESTION_URL",
    "kusto.query.url": "$AZURE_KUSTO_QUERY_URL",
    "authentication.method": "Service Principal",
    "aad.auth.authority": "$AZURE_TENANT_ID",
    "aad.auth.appid": "$AZURE_KUSTO_CLIENT_ID",
    "aad.auth.appkey": "$AZURE_KUSTO_CLIENT_SECRET",
    "kusto.tables.topics.mapping": "[{'topic':'kusto_topic','db':'$AZURE_KUSTO_DATABASE','table':'$AZURE_KUSTO_TABLE','format':'json','mapping':'$AZURE_KUSTO_MAPPING','streaming':'false'}]",
    "flush.interval.ms": "10000",
    "tasks.max": "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

playground connector show-lag --connector $connector_name

log "Verify data is in Azure Data Explorer table $AZURE_KUSTO_TABLE (queued ingestion can take a few minutes)"
MAX_WAIT=600
CUR_WAIT=0
nb_rows=0
while [ $nb_rows -lt 10 ]
do
    sleep 20
    CUR_WAIT=$(( CUR_WAIT+20 ))
    nb_rows=$(kusto_cmd query "$AZURE_KUSTO_TABLE | count" | jq -r '.Tables[0].Rows[0][0]')
    if ! [[ "$nb_rows" =~ ^[0-9]+$ ]]
    then
        nb_rows=0
    fi
    log "⏳ $nb_rows rows in table $AZURE_KUSTO_TABLE"
    if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]
    then
        logerror "❌ the table $AZURE_KUSTO_TABLE does not contain 10 rows after $MAX_WAIT seconds"
        exit 1
    fi
done

kusto_cmd query "$AZURE_KUSTO_TABLE | take 10" | jq -c '.Tables[0].Rows[]'

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name
