#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# https://github.com/Azure/azure-event-hubs/tree/master/samples/Java/Basic/SimpleSend
for component in simple-send
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
    
${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-102473-new-receiver-nil-with-higher-epoch.yml"

log "Creating Azure Event Hubs Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                "connector.class": "io.confluent.connect.azure.eventhubs.EventHubsSourceConnector",
                "kafka.topic": "event_hub_topic",
                "tasks.max": "1",
                "max.events": "1",
                "azure.eventhubs.sas.keyname": "RootManageSharedAccessKey",
                "azure.eventhubs.sas.key": "'"$AZURE_SAS_KEY"'",
                "azure.eventhubs.namespace": "'"$AZURE_EVENT_HUBS_NAMESPACE"'",
                "azure.eventhubs.hub.name": "'"$AZURE_EVENT_HUBS_NAME"'",
                "confluent.license": "",
                "confluent.topic.bootstrap.servers": "broker:9092",
                "confluent.topic.replication.factor": "1",
                "azure.eventhubs.consumer.group": "test1"
          }' \
     http://localhost:8083/connectors/azure-event-hubs-source/config | jq .


curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                "connector.class": "io.confluent.connect.azure.eventhubs.EventHubsSourceConnector",
                "kafka.topic": "event_hub_topic",
                "tasks.max": "1",
                "max.events": "1",
                "azure.eventhubs.sas.keyname": "RootManageSharedAccessKey",
                "azure.eventhubs.sas.key": "'"$AZURE_SAS_KEY"'",
                "azure.eventhubs.namespace": "'"$AZURE_EVENT_HUBS_NAMESPACE"'",
                "azure.eventhubs.hub.name": "'"$AZURE_EVENT_HUBS_NAME"'",
                "confluent.license": "",
                "confluent.topic.bootstrap.servers": "broker:9092",
                "confluent.topic.replication.factor": "1",
                "azure.eventhubs.consumer.group": "test1"
          }' \
     http://localhost:8083/connectors/azure-event-hubs-source2/config | jq .


# [2022-04-27 10:02:46,602] ERROR [azure-event-hubs-source|task-0] WorkerSourceTask{id=azure-event-hubs-source-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:207)
# org.apache.kafka.connect.errors.ConnectException: com.microsoft.azure.eventhubs.ReceiverDisconnectedException: New receiver 'nil' with higher epoch of '1651053761325' is created hence current receiver 'nil' with epoch '1651053087501' is getting disconnected. If you are recreating the receiver, make sure a higher epoch is used. TrackingId:54cb0cb2000190100040800d6269121f_G53_B49, SystemTracker:nspgec2usereh711:eventhub:hubpgec2usereh711~8191|test1, Timestamp:2022-04-27T10:02:46, errorContext[NS: nspgec2usereh711.servicebus.windows.net, PATH: hubpgec2usereh711/ConsumerGroups/test1/Partitions/0, REFERENCE_ID: LN_83ade1_1651053087723_49a_G53, PREFETCH_COUNT: 500, LINK_CREDIT: 500, PREFETCH_Q_LEN: 0]
#         at io.confluent.connect.azure.eventhubs.EventHubsSourceTask.poll(EventHubsSourceTask.java:196)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.poll(WorkerSourceTask.java:307)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.execute(WorkerSourceTask.java:263)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:200)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:255)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: com.microsoft.azure.eventhubs.ReceiverDisconnectedException: New receiver 'nil' with higher epoch of '1651053761325' is created hence current receiver 'nil' with epoch '1651053087501' is getting disconnected. If you are recreating the receiver, make sure a higher epoch is used. TrackingId:54cb0cb2000190100040800d6269121f_G53_B49, SystemTracker:nspgec2usereh711:eventhub:hubpgec2usereh711~8191|test1, Timestamp:2022-04-27T10:02:46, errorContext[NS: nspgec2usereh711.servicebus.windows.net, PATH: hubpgec2usereh711/ConsumerGroups/test1/Partitions/0, REFERENCE_ID: LN_83ade1_1651053087723_49a_G53, PREFETCH_COUNT: 500, LINK_CREDIT: 500, PREFETCH_Q_LEN: 0]
#         at com.microsoft.azure.eventhubs.impl.ExceptionUtil.toException(ExceptionUtil.java:43)
#         at com.microsoft.azure.eventhubs.impl.MessageReceiver.onClose(MessageReceiver.java:789)
#         at com.microsoft.azure.eventhubs.impl.BaseLinkHandler.processOnClose(BaseLinkHandler.java:73)
#         at com.microsoft.azure.eventhubs.impl.BaseLinkHandler.handleRemoteLinkClosed(BaseLinkHandler.java:109)
#         at com.microsoft.azure.eventhubs.impl.BaseLinkHandler.onLinkRemoteClose(BaseLinkHandler.java:51)
#         at org.apache.qpid.proton.engine.BaseHandler.handle(BaseHandler.java:176)
#         at org.apache.qpid.proton.engine.impl.EventImpl.dispatch(EventImpl.java:108)
#         at org.apache.qpid.proton.reactor.impl.ReactorImpl.dispatch(ReactorImpl.java:324)
#         at org.apache.qpid.proton.reactor.impl.ReactorImpl.process(ReactorImpl.java:291)
#         at com.microsoft.azure.eventhubs.impl.MessagingFactory$RunReactor.run(MessagingFactory.java:766)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ScheduledThreadPoolExecutor$ScheduledFutureTask.run(ScheduledThreadPoolExecutor.java:304)
#         ... 3 more

sleep 5

log "Inject data in Event Hubs, using simple-send java program"
docker exec -d -e AZURE_EVENT_HUBS_NAME="$AZURE_EVENT_HUBS_NAME" -e AZURE_EVENT_CONNECTION_STRING="$AZURE_EVENT_CONNECTION_STRING" simple-send bash -c "java -jar simplesend-1.0.0-jar-with-dependencies.jar"

sleep 5

log "Verifying topic event_hub_topic"
timeout 60 docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic event_hub_topic --from-beginning --property print.key=true --max-messages 2

log "Restarting task"
curl -X POST localhost:8083/connectors/azure-event-hubs-source/tasks/0/restart