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
    az login -u "$AZ_USER" -p "$AZ_PASS"
else
    log "Logging to Azure using browser"
    az login
fi

AZURE_NAME=playground$USER$TRAVIS_JOB_NUMBER
AZURE_NAME=${AZURE_NAME//[-._]/}
AZURE_RESOURCE_GROUP=$AZURE_NAME
AZURE_SQL_NAME=$AZURE_NAME
AZURE_FIREWALL_RULL_NAME=$AZURE_NAME
AZURE_DATA_WAREHOUSE_NAME=$AZURE_NAME
AZURE_REGION=westeurope
AZURE_SQL_URL="jdbc:sqlserver://$AZURE_SQL_NAME.database.windows.net:1433"
PASSWORD="KoCCPcx>XmRuxM6qt3us"

set +e
az group delete --name $AZURE_RESOURCE_GROUP --yes
set -e

log "Creating Azure Resource Group $AZURE_RESOURCE_GROUP"
az group create \
    --name $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION
log "Creating SQL server instance $AZURE_SQL_NAME"
az sql server create \
    --name $AZURE_SQL_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION  \
    --admin-user myadmin \
    --admin-password $PASSWORD
log "Enable a server-level firewall rule"
MY_IP=$(curl https://ipinfo.io/ip)
if [ ! -z "$TRAVIS" ]
then
     # running with Travis
     # connect-azure-sql-data-warehouse-sink is failing #131
     MY_IP="0.0.0.0"
fi
az sql server firewall-rule create \
    --name $AZURE_FIREWALL_RULL_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --server $AZURE_SQL_NAME \
    --start-ip-address $MY_IP \
    --end-ip-address $MY_IP
log "Create a SQL Data Warehouse instance"
az sql dw create \
    --name $AZURE_DATA_WAREHOUSE_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --server $AZURE_SQL_NAME

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Sending messages to topic products"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic products --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"name","type":"string"},
{"name":"price", "type": "float"}, {"name":"quantity", "type": "int"}]}' << EOF
{"name": "scissors", "price": 2.75, "quantity": 3}
{"name": "tape", "price": 0.99, "quantity": 10}
{"name": "notebooks", "price": 1.99, "quantity": 5}
EOF

log "Creating Azure SQL Data Warehouse Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.azuresqldw.AzureSqlDwSinkConnector",
                    "tasks.max": "1",
                    "topics": "products",
                    "auto.create": "true",
                    "auto.evolve": "true",
                    "table.name.format": "kafka_${topic}",
                    "azure.sql.dw.url": "'"$AZURE_SQL_URL"'",
                    "azure.sql.dw.user": "myadmin",
                    "azure.sql.dw.password": "'"$PASSWORD"'",
                    "azure.sql.dw.database.name": "'"$AZURE_DATA_WAREHOUSE_NAME"'",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/azure-sql-dw-sink/config | jq .

sleep 5

log "Check Azure SQL Data Warehouse for Data"
docker run -i fabiang/sqlcmd -S "$AZURE_SQL_NAME.database.windows.net,1433" -I -U "myadmin" -P "$PASSWORD" -d "$AZURE_DATA_WAREHOUSE_NAME" -Q "select * from kafka_products;" -s"|"

log "Deleting resource group"
az group delete --name $AZURE_RESOURCE_GROUP --yes