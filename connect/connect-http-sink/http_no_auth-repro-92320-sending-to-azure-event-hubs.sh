#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

get_sas_token() {
    local EVENTHUB_URI=$1
    local SHARED_ACCESS_KEY_NAME=$2
    local SHARED_ACCESS_KEY=$3
    local EXPIRY=${EXPIRY:=$((60 * 60 * 24))} # Default token expiry is 1 day

    local ENCODED_URI=$(echo -n $EVENTHUB_URI | jq -s -R -r @uri)
    local TTL=$(($(date +%s) + $EXPIRY))
    local UTF8_SIGNATURE=$(printf "%s\n%s" $ENCODED_URI $TTL | iconv -t utf8)

    local HASH=$(echo -n "$UTF8_SIGNATURE" | openssl sha256 -hmac $SHARED_ACCESS_KEY -binary | base64)
    local ENCODED_HASH=$(echo -n $HASH | jq -s -R -r @uri)

    echo -n "SharedAccessSignature sr=$ENCODED_URI&sig=$ENCODED_HASH&se=$TTL&skn=$SHARED_ACCESS_KEY_NAME"
}


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

AZURE_NAME=pg${USER}eh${GITHUB_RUN_NUMBER}${TAG}
AZURE_NAME=${AZURE_NAME//[-._]/}
AZURE_RESOURCE_GROUP=$AZURE_NAME
AZURE_EVENT_HUBS_NAMESPACE=ns$AZURE_NAME
AZURE_EVENT_HUBS_NAME=hub$AZURE_NAME
AZURE_REGION=westeurope

set +e
az group delete --name $AZURE_RESOURCE_GROUP --yes
set -e

log "Creating Azure Resource Group $AZURE_RESOURCE_GROUP"
az group create \
    --name $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION
log "Creating Azure Event Hubs namespace"
az eventhubs namespace create \
    --name $AZURE_EVENT_HUBS_NAMESPACE \
    --resource-group $AZURE_RESOURCE_GROUP \
    --enable-kafka true
log "Creating Azure Event Hubs"
az eventhubs eventhub create \
    --name $AZURE_EVENT_HUBS_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --namespace-name $AZURE_EVENT_HUBS_NAMESPACE
log "Get SAS key for RootManageSharedAccessKey"
AZURE_SAS_KEY=$(az eventhubs namespace authorization-rule keys list \
    --resource-group $AZURE_RESOURCE_GROUP \
    --namespace-name $AZURE_EVENT_HUBS_NAMESPACE \
    --name "RootManageSharedAccessKey" | jq -r '.primaryKey')

log "Get Connection String for SimpleSend client"
AZURE_EVENT_CONNECTION_STRING=$(az eventhubs namespace authorization-rule keys list \
    --resource-group $AZURE_RESOURCE_GROUP \
    --namespace-name $AZURE_EVENT_HUBS_NAMESPACE \
    --name "RootManageSharedAccessKey" | jq -r '.primaryConnectionString')

# https://docs.microsoft.com/en-us/rest/api/eventhub/generate-sas-token#bash
SAS_TOKEN=$(get_sas_token "$AZURE_EVENT_HUBS_NAMESPACE.servicebus.windows.net" "RootManageSharedAccessKey" "$AZURE_SAS_KEY")
# https://docs.microsoft.com/en-us/rest/api/eventhub/send-event
HTTP_API_URL="https://$AZURE_EVENT_HUBS_NAMESPACE.servicebus.windows.net/$AZURE_EVENT_HUBS_NAME/messages?timeout=60&api-version=2014-01"
HEADERS="Authorization: $SAS_TOKEN|Content-Type: application/atom+xml;type=entry;charset=utf-8"


log "AZURE_EVENT_HUBS_NAME=$AZURE_EVENT_HUBS_NAME"
log "AZURE_EVENT_HUBS_NAMESPACE=$AZURE_EVENT_HUBS_NAMESPACE"
log "AZURE_SAS_KEY=$AZURE_SAS_KEY"
log "AZURE_EVENT_CONNECTION_STRING=$AZURE_EVENT_CONNECTION_STRING"
log "SAS_TOKEN=$SAS_TOKEN"
log "HTTP_API_URL=$HTTP_API_URL"
log "HEADERS=$HEADERS"

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-92320-sending-to-azure-event-hubs.yml"

log "Sending messages to topic mytopic"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic mytopic << EOF
{ "DeviceId":"dev-01", "Temperature":"37.0" }
EOF

# curl --request PUT \
#   --url http://localhost:8083/admin/loggers/io.confluent.connect.http \
#   --header 'Accept: application/json' \
#   --header 'Content-Type: application/json' \
#   --data '{
# 	"level": "TRACE"
# }'

log "Creating http-sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "topics": "mytopic",
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.http.HttpSinkConnector",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter.schemas.enable": "false",
               "value.converter": "org.apache.kafka.connect.json.JsonConverter",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "reporter.bootstrap.servers": "broker:9092",
               "reporter.error.topic.name": "error-responses",
               "reporter.error.topic.replication.factor": 1,
               "reporter.result.topic.name": "success-responses",
               "reporter.result.topic.replication.factor": 1,
               "http.api.url": "'"$HTTP_API_URL"'",
               "request.method": "POST",
               "headers": "'"$HEADERS"'",
               "header.separator": "|",
               "https.ssl.protocol": "TLSv1.2"
          }' \
     http://localhost:8083/connectors/http-sink/config | jq .

# [2022-02-16 11:06:25,363] DEBUG [http-sink5|task-0] Backing off after failing to execute HTTP request for 1 records (io.confluent.connect.http.writer.HttpWriterImpl:316)
# Error while processing HTTP request with Url : https://xxx.servicebus.windows.net/xxx/messages?timeout=60&api-version=2014-01, Error Message : Exception while processing HTTP request for a batch of 1 records., Exception : java.net.SocketException: Connection reset
#         at io.confluent.connect.http.writer.HttpWriterImpl.executeBatchRequest(HttpWriterImpl.java:384)
#         at io.confluent.connect.http.writer.HttpWriterImpl.executeRequestWithBackOff(HttpWriterImpl.java:303)
#         at io.confluent.connect.http.writer.HttpWriterImpl.sendBatch(HttpWriterImpl.java:277)
#         at io.confluent.connect.http.writer.HttpWriterImpl.write(HttpWriterImpl.java:179)
#         at io.confluent.connect.http.HttpSinkTask.put(HttpSinkTask.java:62)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:604)
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

sleep 10

log "Confirm that the data was sent to the HTTP endpoint."
curl localhost:8080/api/messages | jq . > /tmp/result.log  2>&1
cat /tmp/result.log
grep "10" /tmp/result.log

timeout 60 docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic success-responses --from-beginning --max-messages 1