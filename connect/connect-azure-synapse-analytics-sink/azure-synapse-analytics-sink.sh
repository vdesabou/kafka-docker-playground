#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "1.0.9"
then
     logwarn "minimal supported connector version is 1.0.10 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.0.html#supported-connector-versions-in-cp-8-0"
     exit 111
fi

login_and_maybe_set_azure_subscription

AZURE_NAME=pg${USER}wh${GITHUB_RUN_NUMBER}${TAG}
AZURE_NAME=${AZURE_NAME//[-._]/}
if [ ${#AZURE_NAME} -gt 24 ]; then
  AZURE_NAME=${AZURE_NAME:0:24}
fi
AZURE_RESOURCE_GROUP=$AZURE_NAME
AZURE_SQL_NAME=$AZURE_NAME
AZURE_FIREWALL_RULL_NAME=$AZURE_NAME
AZURE_DATA_WAREHOUSE_NAME=$AZURE_NAME
AZURE_REGION=westeurope
AZURE_SQL_URL="jdbc:sqlserver://$AZURE_SQL_NAME.database.windows.net:1433"
PASSWORD=$(date +%s | cksum | base64 | head -c 32 ; echo)
PASSWORD="${PASSWORD}1"

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
log "Creating SQL server instance $AZURE_SQL_NAME"
# https://github.com/Azure/azure-cli/issues/17052 tags cannot be set
az sql server create \
    --name $AZURE_SQL_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION  \
    --admin-user myadmin \
    --admin-password $PASSWORD

if [ ! -z "$GITHUB_RUN_NUMBER" ]
then
    # running with CI
    # connect-azure-synapse-analytics-sink is failing #131
    # allow applications from Azure IP addresses to connect to your Azure Database for MySQL server, provide the IP address 0.0.0.0 as the Start IP and End IP
    az sql server firewall-rule create \
    --name $AZURE_FIREWALL_RULL_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --server $AZURE_SQL_NAME \
    --start-ip-address 0.0.0.0 \
    --end-ip-address 0.0.0.0
else
    log "Enable a server-level firewall rule"
    MY_IP=$(curl https://ipinfo.io/ip)
    az sql server firewall-rule create \
    --name $AZURE_FIREWALL_RULL_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --server $AZURE_SQL_NAME \
    --start-ip-address $MY_IP \
    --end-ip-address $MY_IP
fi

log "Create a SQL Data Warehouse instance"
az sql dw create \
    --name $AZURE_DATA_WAREHOUSE_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --server $AZURE_SQL_NAME \
    --tags cflt_managed_by=user cflt_managed_id="$USER"

# generate data file for externalizing secrets
sed -e "s|:AZURE_SQL_URL:|$AZURE_SQL_URL|g" \
    -e "s|:PASSWORD:|$PASSWORD|g" \
    -e "s|:AZURE_DATA_WAREHOUSE_NAME:|$AZURE_DATA_WAREHOUSE_NAME|g" \
    ../../connect/connect-azure-synapse-analytics-sink/data.template > ../../connect/connect-azure-synapse-analytics-sink/data

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Sending messages to topic products"
playground topic produce -t products --nb-messages 2 << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "name",
      "type": "string"
    },
    {
      "name": "price",
      "type": "float"
    },
    {
      "name": "quantity",
      "type": "int"
    }
  ]
}
EOF

playground topic produce -t products --nb-messages 1 --forced-value '{"name": "notebooks", "price": 1.99, "quantity": 5}' << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "name",
      "type": "string"
    },
    {
      "name": "price",
      "type": "float"
    },
    {
      "name": "quantity",
      "type": "int"
    }
  ]
}
EOF

log "Creating Azure Synapse Analytics Sink connector"
playground connector create-or-update --connector azure-sql-dw-sink  << EOF
{
    "connector.class": "io.confluent.connect.azuresqldw.AzureSqlDwSinkConnector",
    "tasks.max": "1",
    "topics": "products",
    "auto.create": "true",
    "auto.evolve": "true",
    "table.name.format": "kafka_\${topic}",
    "azure.sql.dw.url": "\${file:/data:AZURE_SQL_URL}",
    "azure.sql.dw.user": "myadmin",
    "azure.sql.dw.password": "\${file:/data:PASSWORD}",
    "azure.sql.dw.database.name": "\${file:/data:AZURE_DATA_WAREHOUSE_NAME}",
    "confluent.license": "",
    "confluent.topic.bootstrap.servers": "broker:9092",
    "confluent.topic.replication.factor": "1",
    "errors.tolerance": "all",
    "errors.log.enable": "true",
    "errors.log.include.messages": "true"
}
EOF

sleep 60

log "Check Azure Synapse Analytics for Data"
docker run -i fabiang/sqlcmd -S "$AZURE_SQL_NAME.database.windows.net,1433" -I -U "myadmin" -P "$PASSWORD" -d "$AZURE_DATA_WAREHOUSE_NAME" -Q "select * from kafka_products;" -s"|"  > /tmp/result.log  2>&1
cat /tmp/result.log
grep "notebooks" /tmp/result.log