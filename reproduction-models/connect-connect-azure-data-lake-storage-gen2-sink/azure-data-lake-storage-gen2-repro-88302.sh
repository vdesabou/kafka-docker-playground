#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

for component in producer-88302
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

AZURE_NAME=pg${USER}dl${GITHUB_RUN_NUMBER}${TAG}
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
AZURE_DATALAKE_CLIENT_ID=$(az ad app create --display-name "$AZURE_AD_APP_NAME" --is-fallback-public-client false --sign-in-audience PersonalMicrosoftAccount --query appId -o tsv)
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

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-88302.yml"

echo "AZURE_DATALAKE_CLIENT_ID=$AZURE_DATALAKE_CLIENT_ID"
echo "AZURE_DATALAKE_ACCOUNT_NAME=$AZURE_DATALAKE_ACCOUNT_NAME"
echo "AZURE_DATALAKE_TOKEN_ENDPOINT=$AZURE_DATALAKE_TOKEN_ENDPOINT"

log "Creating Data Lake Storage Gen2 Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.azure.datalake.gen2.AzureDataLakeGen2SinkConnector",
                    "tasks.max": "1",
                    "topics": "customer-protobuf",
                    "flush.size": "3",
                    "azure.datalake.gen2.client.id": "'"$AZURE_DATALAKE_CLIENT_ID"'",
                    "azure.datalake.gen2.client.key": "'"$AZURE_DATALAKE_CLIENT_PASSWORD"'",,
                    "azure.datalake.gen2.account.name": "'"$AZURE_DATALAKE_ACCOUNT_NAME"'",
                    "azure.datalake.gen2.token.endpoint": "'"$AZURE_DATALAKE_TOKEN_ENDPOINT"'",
                    "format.class":"io.confluent.connect.azure.storage.format.avro.AvroFormat",
                    "value.converter": "io.confluent.connect.protobuf.ProtobufConverter",
                    "connect.meta.data": "false",
                    "enhanced.avro.schema.support": "true",
                    "value.converter.enhanced.protobuf.schema.support": "true",
                    "value.converter.schema.registry.url": "http://schema-registry:8081",
                    "value.converter.schemas.enable": "false",
                    "value.converter.auto.register.schemas":"false",
                    "errors.retry.timeout":"3600000",
                    "errors.retry.delay.max.ms":"60000",
                    "errors.tolerance": "all",
                    "errors.log.enable":"true",
                    "errors.log.include.messages":"true",
                    "timestamp.extractor": "Record",
                    "schema.compatibility": "FULL",
                    "behavior.on.null.values": "ignore",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/azure-datalake-gen2-sink-proto/config | jq .


log "Sending messages to topic customer-protobuf"
log "Run the Java producer"
docker exec producer-88302 bash -c "java -jar producer-88302-1.0.0-jar-with-dependencies.jar"

sleep 20

log "Listing ${AZURE_DATALAKE_ACCOUNT_NAME} in Azure Data Lake"
az storage blob list --account-name "${AZURE_DATALAKE_ACCOUNT_NAME}" --container-name topics

log "Getting one of the avro files locally and displaying content with avro-tools"
az storage blob download  --container-name topics --name customer-protobuf/partition=0/customer-protobuf+0+0000000000.avro --file /tmp/customer-protobuf+0+0000000000.avro --account-name "${AZURE_DATALAKE_ACCOUNT_NAME}"

docker run --rm -v /tmp:/tmp actions/avro-tools tojson /tmp/customer-protobuf+0+0000000000.avro

# {"price":{"com.github.vdesabou.Customer.Price":{"open_price":{"com.github.vdesabou.instrumentprice.InstrumentPrice":{"price":{"long":-5106534569952410475}}}}},"fx_option":{"com.github.vdesabou.openpositionfxoption.OpenPositionFxOption":{"price":{"com.github.vdesabou.openpositionfxoption.OpenPositionFxOption.Price":{"price":{"long":-167885730524958550}}}}}}
# {"price":{"com.github.vdesabou.Customer.Price":{"open_price":{"com.github.vdesabou.instrumentprice.InstrumentPrice":{"price":{"long":4672433029010564658}}}}},"fx_option":{"com.github.vdesabou.openpositionfxoption.OpenPositionFxOption":{"price":{"com.github.vdesabou.openpositionfxoption.OpenPositionFxOption.Price":{"price":{"long":-7216359497931550918}}}}}}
# {"price":{"com.github.vdesabou.Customer.Price":{"open_price":{"com.github.vdesabou.instrumentprice.InstrumentPrice":{"price":{"long":-3581075550420886390}}}}},"fx_option":{"com.github.vdesabou.openpositionfxoption.OpenPositionFxOption":{"price":{"com.github.vdesabou.openpositionfxoption.OpenPositionFxOption.Price":{"price":{"long":-2298228485105199876}}}}}}

# without "value.converter.enhanced.protobuf.schema.support": "true", we get:
# [2022-01-19 13:01:03,897] ERROR [azure-datalake-gen2-sink-proto|task-0] WorkerSinkTask{id=azure-datalake-gen2-sink-proto-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:206)
# org.apache.kafka.connect.errors.ConnectException: Exiting WorkerSinkTask due to unrecoverable exception.
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:638)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:334)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.apache.avro.SchemaParseException: Can't redefine: Price
#         at org.apache.avro.Schema$Names.put(Schema.java:1511)
#         at org.apache.avro.Schema$NamedSchema.writeNameRef(Schema.java:782)
#         at org.apache.avro.Schema$RecordSchema.toJson(Schema.java:943)
#         at org.apache.avro.Schema$UnionSchema.toJson(Schema.java:1203)
#         at org.apache.avro.Schema$RecordSchema.fieldsToJson(Schema.java:971)
#         at org.apache.avro.Schema$RecordSchema.toJson(Schema.java:955)
#         at org.apache.avro.Schema$UnionSchema.toJson(Schema.java:1203)
#         at org.apache.avro.Schema$RecordSchema.fieldsToJson(Schema.java:971)
#         at org.apache.avro.Schema$RecordSchema.toJson(Schema.java:955)
#         at org.apache.avro.Schema$UnionSchema.toJson(Schema.java:1203)
#         at org.apache.avro.Schema$RecordSchema.fieldsToJson(Schema.java:971)
#         at org.apache.avro.Schema$RecordSchema.toJson(Schema.java:955)
#         at org.apache.avro.Schema.toString(Schema.java:396)
#         at org.apache.avro.Schema.toString(Schema.java:382)
#         at org.apache.avro.file.DataFileWriter.create(DataFileWriter.java:153)
#         at org.apache.avro.file.DataFileWriter.create(DataFileWriter.java:145)
#         at io.confluent.connect.azure.storage.format.avro.AvroRecordWriterProvider$1.write(AvroRecordWriterProvider.java:61)
#         at io.confluent.connect.azure.storage.TopicPartitionWriter.writeRecord(TopicPartitionWriter.java:381)
#         at io.confluent.connect.azure.storage.TopicPartitionWriter.checkRotationOrAppend(TopicPartitionWriter.java:201)
#         at io.confluent.connect.azure.storage.TopicPartitionWriter.executeState(TopicPartitionWriter.java:164)
#         at io.confluent.connect.azure.storage.TopicPartitionWriter.write(TopicPartitionWriter.java:133)
#         at io.confluent.connect.azure.storage.AzureStorageSinkTask.put(AzureStorageSinkTask.java:144)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:604)
#         ... 10 more
