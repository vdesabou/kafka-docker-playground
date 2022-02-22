#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh


for component in JsonFieldToKey
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

if ! version_gt $TAG_BASE "5.9.99" && version_gt $CONNECTOR_TAG "1.9.9"
then
    logwarn "WARN: connector version >= 2.0.0 do not support CP versions < 6.0.0"
    exit 111
fi

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

AZURE_NAME=pg${USER}bs${GITHUB_RUN_NUMBER}${TAG}
AZURE_NAME=${AZURE_NAME//[-._]/}
AZURE_RESOURCE_GROUP=$AZURE_NAME
AZURE_ACCOUNT_NAME=$AZURE_NAME
AZURE_CONTAINER_NAME=$AZURE_NAME
AZURE_REGION=westeurope

set +e
az group delete --name $AZURE_RESOURCE_GROUP --yes
set -e

log "Creating Azure Resource Group $AZURE_RESOURCE_GROUP"
az group create \
    --name $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION
log "Creating Azure Storage Account $AZURE_ACCOUNT_NAME"
az storage account create \
    --name $AZURE_ACCOUNT_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION \
    --sku Standard_LRS \
    --encryption-services blob
AZURE_ACCOUNT_KEY=$(az storage account keys list \
    --account-name $AZURE_ACCOUNT_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --query "[0].value" | sed -e 's/^"//' -e 's/"$//')
log "Creating Azure Storage Container $AZURE_CONTAINER_NAME"
az storage container create \
    --account-name $AZURE_ACCOUNT_NAME \
    --account-key $AZURE_ACCOUNT_KEY \
    --name $AZURE_CONTAINER_NAME


${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-92778-valuetokey-smt.yml"

log "Creating Azure Blob Storage Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.azure.blob.AzureBlobStorageSinkConnector",
                "tasks.max": "1",
                "topics": "blob_topic",
                "flush.size": "1",
                "azblob.account.name": "'"$AZURE_ACCOUNT_NAME"'",
                "azblob.account.key": "'"$AZURE_ACCOUNT_KEY"'",
                "azblob.container.name": "'"$AZURE_CONTAINER_NAME"'",
                "confluent.license": "",
                "confluent.topic.bootstrap.servers": "broker:9092",
                "confluent.topic.replication.factor": "1",

                "behavior.on.error": "log",
                "errors.log.enable": "true",
                "errors.log.include.messages": "true",
                "format.class" : "io.confluent.connect.azure.blob.format.json.JsonFormat",
                "key.converter.schemas.enable": "false",
                "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                "value.converter.schemas.enable": "false",
                "value.converter": "org.apache.kafka.connect.json.JsonConverter"
          }' \
     http://localhost:8083/connectors/azure-blob-sink/config | jq .

log "Sending messages to topic blob_topic"

# {
#     "ERSS": {
#         "Episode": {
#             "ServiceRequest": {
#                 "ClientSystem": "MyClient",
#                 "ListOfServiceRequests": [
#                     {
#                         "ServiceRequestKey": "MyServiceRequestKey"
#                     }
#                 ]
#             }
#         }
#     }
# }
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic blob_topic << EOF
{"ERSS":{"Episode":{"ServiceRequest":{"ClientSystem":"MyClient","ListOfServiceRequests":[{"ServiceRequestKey":"MyServiceRequestKey"}]}}}}
{"ERSS":{"Episode":{"ServiceRequest":{"ClientSystem":"MyClient2","ListOfServiceRequests":[{"ServiceRequestKey":"MyServiceRequestKey2"}]}}}}
{"ERSS":{"Episode":{"ServiceRequest":{"ClientSystem":"MyClient3","ListOfServiceRequests":[{"ServiceRequestKey":"MyServiceRequestKey3"}]}}}}
EOF

sleep 10

log "Listing objects of container ${AZURE_CONTAINER_NAME} in Azure Blob Storage"
az storage blob list --account-name "${AZURE_ACCOUNT_NAME}" --account-key "${AZURE_ACCOUNT_KEY}" --container-name "${AZURE_CONTAINER_NAME}" --output table

log "Getting one of the avro files locally and displaying content with avro-tools"
az storage blob download --account-name "${AZURE_ACCOUNT_NAME}" --account-key "${AZURE_ACCOUNT_KEY}" --container-name "${AZURE_CONTAINER_NAME}" --name topics/blob_topic/partition=0/blob_topic+0+0000000000.json --file /tmp/blob_topic+0+0000000000.json

cat /tmp/blob_topic+0+0000000000.json


log "Creating Azure Blob Storage Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                "connector.class": "io.confluent.connect.azure.blob.storage.AzureBlobStorageSourceConnector",
                "tasks.max": "1",
                "azblob.account.name": "'"$AZURE_ACCOUNT_NAME"'",
                "azblob.account.key": "'"$AZURE_ACCOUNT_KEY"'",
                "azblob.container.name": "'"$AZURE_CONTAINER_NAME"'",
                "confluent.license": "",
                "confluent.topic.bootstrap.servers": "broker:9092",
                "confluent.topic.replication.factor": "1",

                "behavior.on.error": "log",
                "errors.log.enable": "true",
                "errors.log.include.messages": "true",
                "format.class": "io.confluent.connect.azure.blob.storage.format.json.JsonFormat",
                "key.converter.schemas.enable": "false",
                "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                "value.converter.schemas.enable": "false",
                "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                "transforms" : "AddPrefix,JsonFieldToKey",
                "transforms.AddPrefix.type" : "org.apache.kafka.connect.transforms.RegexRouter",
                "transforms.AddPrefix.regex" : ".*",
                "transforms.AddPrefix.replacement" : "copy_of_$0",
                "transforms.JsonFieldToKey.type": "com.github.vdesabou.kafka.connect.transforms.JsonFieldToKey",
                "transforms.JsonFieldToKey.field": "$.concat($.ERSS.Episode.ServiceRequest.ListOfServiceRequests[0].ServiceRequestKey,\"_\",$.ERSS.Episode.ServiceRequest.ClientSystem)"
          }' \
     http://localhost:8083/connectors/azure-blob-source6/config | jq .

sleep 5

log "Verifying topic copy_of_blob_topic"
timeout 60 docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic copy_of_blob_topic --property print.key=true --property key.separator=, --from-beginning --max-messages 3

# MyServiceRequestKey_MyClient,{"ERSS":{"Episode":{"ServiceRequest":{"ListOfServiceRequests":[{"ServiceRequestKey":"MyServiceRequestKey"}],"ClientSystem":"MyClient"}}}}
# MyServiceRequestKey2_MyClient2,{"ERSS":{"Episode":{"ServiceRequest":{"ListOfServiceRequests":[{"ServiceRequestKey":"MyServiceRequestKey2"}],"ClientSystem":"MyClient2"}}}}
# MyServiceRequestKey3_MyClient3,{"ERSS":{"Episode":{"ServiceRequest":{"ListOfServiceRequests":[{"ServiceRequestKey":"MyServiceRequestKey3"}],"ClientSystem":"MyClient3"}}}}

#log "Deleting resource group"
#az group delete --name $AZURE_RESOURCE_GROUP --yes --no-wait

