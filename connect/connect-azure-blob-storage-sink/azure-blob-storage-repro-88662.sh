#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

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

AZURE_NAME=pg${USER}bk${GITHUB_RUN_NUMBER}${TAG}
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

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Creating Azure Blob Storage Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.azure.blob.AzureBlobStorageSinkConnector",
                    "tasks.max": "1",
                    "topics": "blob_topic_json",
                    "flush.size": "3",
                    "azblob.account.name": "'"$AZURE_ACCOUNT_NAME"'",
                    "azblob.account.key": "'"$AZURE_ACCOUNT_KEY"'",
                    "azblob.container.name": "'"$AZURE_CONTAINER_NAME"'",
                    "value.converter" : "org.apache.kafka.connect.json.JsonConverter",
                    "format.class" : "io.confluent.connect.azure.blob.format.json.JsonFormat",
                    "value.converter.schemas.enable" : "false",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1",
                    "az.compression.type" : "gzip"
          }' \
     http://localhost:8083/connectors/azure-blob-sink-json/config | jq .


log "Sending messages to topic blob_topic_json"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic blob_topic_json << EOF
{"customer_name":"Ed", "complaint_type":"Dirty car", "trip_cost": 29.10, "new_customer": false, "number_of_rides": 22}
EOF

sleep 10

log "Listing objects of container ${AZURE_CONTAINER_NAME} in Azure Blob Storage"
az storage blob list --account-name "${AZURE_ACCOUNT_NAME}" --account-key "${AZURE_ACCOUNT_KEY}" --container-name "${AZURE_CONTAINER_NAME}" --output table

log "Getting one of the avro files locally and displaying content with avro-tools"
az storage blob download --account-name "${AZURE_ACCOUNT_NAME}" --account-key "${AZURE_ACCOUNT_KEY}" --container-name "${AZURE_CONTAINER_NAME}" --name topics/blob_topic_json/partition=0/blob_topic_json+0+0000000000.avro --file /tmp/blob_topic_json+0+0000000000.avro

docker run --rm -v /tmp:/tmp actions/avro-tools tojson /tmp/blob_topic_json+0+0000000000.avro

# [2022-01-18 10:00:35,515] ERROR [azure-blob-sink|task-0] Unexpected failure attempting to make request.
# Error message:'Flowable<ByteBuffer> emitted more bytes than the expected 343'
#  (com.microsoft.azure.storage.blob.LoggingFactory:335)
# [2022-01-18 10:00:35,515] ERROR [azure-blob-sink-json|task-0] Exception on topic partition blob_topic_json-0 (io.confluent.connect.azure.storage.AzureStorageSinkTask:146)
# org.apache.kafka.connect.errors.RetriableException: org.apache.kafka.connect.errors.ConnectException: Multipart upload failed to commitBlockList for bucket pgvsaboulinbk701 key topics/blob_topic_json/partition=0/blob_topic_json+0+0000000000.json.gz
#         at io.confluent.connect.azure.storage.TopicPartitionWriter.commitFiles(TopicPartitionWriter.java:393)
#         at io.confluent.connect.azure.storage.TopicPartitionWriter.executeState(TopicPartitionWriter.java:170)
#         at io.confluent.connect.azure.storage.TopicPartitionWriter.write(TopicPartitionWriter.java:133)
#         at io.confluent.connect.azure.storage.AzureStorageSinkTask.put(AzureStorageSinkTask.java:144)
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
# Caused by: org.apache.kafka.connect.errors.ConnectException: Multipart upload failed to commitBlockList for bucket pgvsaboulinbk701 key topics/blob_topic_json/partition=0/blob_topic_json+0+0000000000.json.gz
#         at io.confluent.connect.azure.blob.storage.BlobStorageOutputStream.commit(BlobStorageOutputStream.java:161)
#         at io.confluent.connect.azure.storage.AzureStorage.commit(AzureStorage.java:24)
#         at io.confluent.connect.azure.storage.format.json.JsonRecordWriterProvider$1.commit(JsonRecordWriterProvider.java:86)
#         at io.confluent.connect.azure.storage.TopicPartitionWriter.commitFile(TopicPartitionWriter.java:415)
#         at io.confluent.connect.azure.storage.TopicPartitionWriter.commitFiles(TopicPartitionWriter.java:389)
#         ... 14 more
# Caused by: org.apache.kafka.connect.errors.ConnectException: Failed to upload part topics/blob_topic_json/partition=0/blob_topic_json+0+0000000000.json.gz to bucket pgvsaboulinbk701
#         at io.confluent.connect.azure.blob.storage.BlobStorageOutputStream.lambda$uploadPart$0(BlobStorageOutputStream.java:138)
#         at io.reactivex.internal.operators.single.SingleResumeNext$ResumeMainSingleObserver.onError(SingleResumeNext.java:73)
#         at io.reactivex.internal.operators.single.SingleMap$MapSingleObserver.onError(SingleMap.java:69)
#         at io.reactivex.internal.observers.ResumeSingleObserver.onError(ResumeSingleObserver.java:51)
#         at io.reactivex.internal.disposables.EmptyDisposable.error(EmptyDisposable.java:78)
#         at io.reactivex.internal.operators.single.SingleError.subscribeActual(SingleError.java:42)
#         at io.reactivex.Single.subscribe(Single.java:3394)
#         at io.reactivex.internal.operators.single.SingleResumeNext$ResumeMainSingleObserver.onError(SingleResumeNext.java:80)
#         at io.reactivex.internal.operators.single.SingleFlatMap$SingleFlatMapCallback.onError(SingleFlatMap.java:90)
#         at io.reactivex.internal.operators.single.SingleFlatMap$SingleFlatMapCallback.onError(SingleFlatMap.java:90)
#         at io.reactivex.internal.observers.ResumeSingleObserver.onError(ResumeSingleObserver.java:51)
#         at io.reactivex.internal.disposables.EmptyDisposable.error(EmptyDisposable.java:78)
#         at io.reactivex.internal.operators.single.SingleError.subscribeActual(SingleError.java:42)
#         at io.reactivex.Single.subscribe(Single.java:3394)
#         at io.reactivex.internal.operators.single.SingleResumeNext$ResumeMainSingleObserver.onError(SingleResumeNext.java:80)
#         at io.reactivex.internal.operators.single.SingleFlatMap$SingleFlatMapCallback.onError(SingleFlatMap.java:90)
#         at io.reactivex.internal.observers.ResumeSingleObserver.onError(ResumeSingleObserver.java:51)
#         at io.reactivex.internal.operators.single.SingleTimeout$TimeoutMainObserver.onError(SingleTimeout.java:142)
#         at io.reactivex.internal.operators.single.SingleDoOnSuccess$DoOnSuccess.onError(SingleDoOnSuccess.java:64)
#         at io.reactivex.internal.operators.single.SingleMap$MapSingleObserver.onError(SingleMap.java:69)
#         at io.reactivex.internal.operators.single.SingleFlatMap$SingleFlatMapCallback.onError(SingleFlatMap.java:90)
#         at io.reactivex.internal.operators.single.SingleDoOnSuccess$DoOnSuccess.onError(SingleDoOnSuccess.java:64)
#         at io.reactivex.internal.operators.single.SingleDoOnError$DoOnError.onError(SingleDoOnError.java:63)
#         at io.reactivex.internal.operators.single.SingleCreate$Emitter.tryOnError(SingleCreate.java:95)
#         at io.reactivex.internal.operators.single.SingleCreate$Emitter.onError(SingleCreate.java:81)
#         at com.microsoft.rest.v2.http.NettyClient$AcquisitionListener.emitError(NettyClient.java:453)
#         at com.microsoft.rest.v2.http.NettyClient$AcquisitionListener$RequestSubscriber.onError(NettyClient.java:360)
#         at io.reactivex.internal.operators.flowable.FlowableDoOnEach$DoOnEachSubscriber.onError(FlowableDoOnEach.java:111)
#         at io.reactivex.internal.operators.flowable.FlowableDoOnEach$DoOnEachSubscriber.onError(FlowableDoOnEach.java:111)
#         at io.reactivex.internal.subscribers.BasicFuseableSubscriber.fail(BasicFuseableSubscriber.java:111)
#         at io.reactivex.internal.operators.flowable.FlowableDoOnEach$DoOnEachSubscriber.onNext(FlowableDoOnEach.java:88)
#         at io.reactivex.internal.operators.flowable.FlowableFlatMap$MergeSubscriber.tryEmitScalar(FlowableFlatMap.java:234)
#         at io.reactivex.internal.operators.flowable.FlowableFlatMap$MergeSubscriber.onNext(FlowableFlatMap.java:152)
#         at io.reactivex.internal.operators.flowable.FlowableMap$MapSubscriber.onNext(FlowableMap.java:69)
#         at io.reactivex.internal.subscriptions.ScalarSubscription.request(ScalarSubscription.java:55)
#         at io.reactivex.internal.subscribers.BasicFuseableSubscriber.request(BasicFuseableSubscriber.java:153)
#         at io.reactivex.internal.operators.flowable.FlowableFlatMap$MergeSubscriber.onSubscribe(FlowableFlatMap.java:117)
#         at io.reactivex.internal.subscribers.BasicFuseableSubscriber.onSubscribe(BasicFuseableSubscriber.java:67)
#         at io.reactivex.internal.operators.flowable.FlowableJust.subscribeActual(FlowableJust.java:34)
#         at io.reactivex.Flowable.subscribe(Flowable.java:14409)
#         at io.reactivex.internal.operators.flowable.FlowableMap.subscribeActual(FlowableMap.java:38)
#         at io.reactivex.Flowable.subscribe(Flowable.java:14409)
#         at io.reactivex.internal.operators.flowable.FlowableFlatMap.subscribeActual(FlowableFlatMap.java:53)
#         at io.reactivex.Flowable.subscribe(Flowable.java:14409)
#         at io.reactivex.internal.operators.flowable.FlowableDoOnEach.subscribeActual(FlowableDoOnEach.java:50)
#         at io.reactivex.Flowable.subscribe(Flowable.java:14409)
#         at io.reactivex.internal.operators.flowable.FlowableDoOnEach.subscribeActual(FlowableDoOnEach.java:50)
#         at io.reactivex.Flowable.subscribe(Flowable.java:14409)
#         at io.reactivex.Flowable.subscribe(Flowable.java:14356)
#         at io.reactivex.internal.operators.flowable.FlowableDefer.subscribeActual(FlowableDefer.java:41)
#         at io.reactivex.Flowable.subscribe(Flowable.java:14409)
#         at com.microsoft.rest.v2.http.NettyClient$AcquisitionListener.operationComplete(NettyClient.java:289)
#         at io.netty.util.concurrent.DefaultPromise.notifyListener0(DefaultPromise.java:578)
#         at io.netty.util.concurrent.DefaultPromise.notifyListenersNow(DefaultPromise.java:552)
#         at io.netty.util.concurrent.DefaultPromise.access$200(DefaultPromise.java:35)
#         at io.netty.util.concurrent.DefaultPromise$1.run(DefaultPromise.java:502)
#         at io.netty.util.concurrent.AbstractEventExecutor.safeExecute(AbstractEventExecutor.java:164)
#         at io.netty.util.concurrent.SingleThreadEventExecutor.runAllTasks(SingleThreadEventExecutor.java:469)
#         at io.netty.channel.nio.NioEventLoop.run(NioEventLoop.java:500)
#         at io.netty.util.concurrent.SingleThreadEventExecutor$4.run(SingleThreadEventExecutor.java:986)
#         at io.netty.util.internal.ThreadExecutorMap$2.run(ThreadExecutorMap.java:74)
#         at io.netty.util.concurrent.FastThreadLocalRunnable.run(FastThreadLocalRunnable.java:30)
#         ... 1 more
# Caused by: com.microsoft.rest.v2.http.UnexpectedLengthException: Flowable<ByteBuffer> emitted more bytes than the expected 343
#         at com.microsoft.rest.v2.util.FlowableUtil$1.lambda$call$0(FlowableUtil.java:88)
#         at io.reactivex.internal.operators.flowable.FlowableDoOnEach$DoOnEachSubscriber.onNext(FlowableDoOnEach.java:86)
#         ... 32 more