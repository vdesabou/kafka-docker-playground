#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh


for component in producer-88601
do
    set +e
    log "🏗 Building jar for ${component}"
    docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${DIR}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
    if [ $? != 0 ]
    then
        logerror "ERROR: failed to build java component $component"
        tail -500 /tmp/result.log
        exit 1
    fi
    set -e
done

if [ ! -z "$CI" ]
then
     # running with github actions
     if [ ! -f ../../secrets.properties ]
     then
          logerror "../../secrets.properties is not present!"
          exit 1
     fi
     source ../../secrets.properties > /dev/null 2>&1
fi

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

AZURE_TENANT_NAME=${AZURE_TENANT_NAME:-$1}

if [ -z "$AZURE_TENANT_NAME" ]
then
     logerror "AZURE_TENANT_NAME is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

AZURE_NAME=pgrepro88601
AZURE_NAME=${AZURE_NAME//[-._]/}
AZURE_RESOURCE_GROUP=$AZURE_NAME
AZURE_DATALAKE_ACCOUNT_NAME=$AZURE_NAME
AZURE_AD_APP_NAME=$AZURE_NAME
AZURE_REGION=westeurope

set +e
az group delete --name $AZURE_RESOURCE_GROUP --yes
AZURE_DATALAKE_CLIENT_ID=$(az ad app create --display-name "$AZURE_AD_APP_NAME" --is-fallback-public-client false --sign-in-audience AzureADandPersonalMicrosoftAccount --query appId -o tsv)
az ad app delete --id $AZURE_DATALAKE_CLIENT_ID
set -e

log "Add the CLI extension for Azure Data Lake Gen 2"
az extension add --name storage-preview

log "Creating resource $AZURE_RESOURCE_GROUP in $AZURE_REGION"
az group create \
    --name $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION

log "Registering active directory App $AZURE_AD_APP_NAME"
AZURE_DATALAKE_CLIENT_ID=$(az ad app create --display-name "$AZURE_AD_APP_NAME" --is-fallback-public-client false --sign-in-audience AzureADandPersonalMicrosoftAccount --query appId -o tsv)
AZURE_DATALAKE_CLIENT_PASSWORD=$(az ad app credential reset --id $AZURE_DATALAKE_CLIENT_ID | jq -r '.password')

log "Creating Service Principal associated to the App"
SERVICE_PRINCIPAL_ID=$(az ad sp create --id $AZURE_DATALAKE_CLIENT_ID | jq -r '.id')

AZURE_TENANT_ID=$(az account list --query "[?name=='$AZURE_TENANT_NAME']" | jq -r '.[].tenantId')
AZURE_DATALAKE_TOKEN_ENDPOINT="https://login.microsoftonline.com/$AZURE_TENANT_ID/oauth2/token"

log "Creating data lake $AZURE_DATALAKE_ACCOUNT_NAME in resource $AZURE_RESOURCE_GROUP"
az storage account create \
    --name $AZURE_DATALAKE_ACCOUNT_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION \
    --sku Standard_LRS \
    --kind StorageV2 \
    --hns true

sleep 20

log "Assigning Storage Blob Data Owner role to Service Principal $SERVICE_PRINCIPAL_ID"
az role assignment create --assignee $SERVICE_PRINCIPAL_ID --role "Storage Blob Data Owner"

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-88601.yml"

echo "AZURE_DATALAKE_CLIENT_ID=$AZURE_DATALAKE_CLIENT_ID"
echo "AZURE_DATALAKE_ACCOUNT_NAME=$AZURE_DATALAKE_ACCOUNT_NAME"
echo "AZURE_DATALAKE_TOKEN_ENDPOINT=$AZURE_DATALAKE_TOKEN_ENDPOINT"

log "Creating Data Lake Storage Gen2 Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.azure.datalake.gen2.AzureDataLakeGen2SinkConnector",
                    "tasks.max": "1",
                    "topics": "customer-avro",
                    "flush.size": "3",
                    "azure.datalake.gen2.client.id": "'"$AZURE_DATALAKE_CLIENT_ID"'",
                    "azure.datalake.gen2.client.key": "'"$AZURE_DATALAKE_CLIENT_PASSWORD"'",
                    "azure.datalake.gen2.account.name": "'"$AZURE_DATALAKE_ACCOUNT_NAME"'",
                    "azure.datalake.gen2.token.endpoint": "'"$AZURE_DATALAKE_TOKEN_ENDPOINT"'",
                    "format.class": "io.confluent.connect.azure.storage.format.avro.AvroFormat",
                    "transforms":"Archive",
                    "transforms.Archive.type":"com.github.jcustenborder.kafka.connect.archive.Archive",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/azure-datalake-gen2-sink-archive/config | jq .


log "Produce avro data using Java producer"
docker exec producer-88601 bash -c "java -jar producer-88601-1.0.0-jar-with-dependencies.jar"

sleep 20

log "Listing ${AZURE_DATALAKE_ACCOUNT_NAME} in Azure Data Lake"
az storage blob list --account-name "${AZURE_DATALAKE_ACCOUNT_NAME}" --container-name topics

log "Getting one of the avro files locally and displaying content with avro-tools"
az storage blob download  --container-name topics --name customer-avro/partition=0/customer-avro+0+0000000000.avro --file /tmp/customer-avro+0+0000000000.avro --account-name "${AZURE_DATALAKE_ACCOUNT_NAME}"

docker run --rm -v /tmp:/tmp actions/avro-tools tojson /tmp/customer-avro+0+0000000000.avro


