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
    az login -u "$AZ_USER" -p "$AZ_PASS"
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
                    "topics": "blob_topic",
                    "flush.size": "3",
                    "azblob.account.name": "'"$AZURE_ACCOUNT_NAME"'",
                    "azblob.account.key": "'"$AZURE_ACCOUNT_KEY"'",
                    "azblob.container.name": "'"$AZURE_CONTAINER_NAME"'",
                    "retry.backoff.ms": "30000",
                    "format.class": "io.confluent.connect.azure.blob.format.avro.AvroFormat",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1",
                    "consumer.override.max.poll.interval.ms": "60000"
          }' \
     http://localhost:8083/connectors/azure-blob-sink/config | jq .

sleep 30

log "Block communication to Azure"
docker exec --privileged --user root connect bash -c "iptables -A OUTPUT -p tcp --dport 443 -j DROP"

log "Sending messages to topic blob_topic"
seq -f "{\"f1\": \"value%g\"}" 550 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic blob_topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

sleep 10

log "Listing objects of container ${AZURE_CONTAINER_NAME} in Azure Blob Storage"
az storage blob list --account-name "${AZURE_ACCOUNT_NAME}" --account-key "${AZURE_ACCOUNT_KEY}" --container-name "${AZURE_CONTAINER_NAME}" --output table

log "Getting one of the avro files locally and displaying content with avro-tools"
az storage blob download --account-name "${AZURE_ACCOUNT_NAME}" --account-key "${AZURE_ACCOUNT_KEY}" --container-name "${AZURE_CONTAINER_NAME}" --name topics/blob_topic/partition=0/blob_topic+0+0000000000.avro --file /tmp/blob_topic+0+0000000000.avro

docker run --rm -v /tmp:/tmp actions/avro-tools tojson /tmp/blob_topic+0+0000000000.avro

log "Deleting resource group"
az group delete --name $AZURE_RESOURCE_GROUP --yes --no-wait



# [2021-06-30 13:23:37,323] INFO Starting commit and rotation for topic partition blob_topic-0 with start offset {partition=0=30} (io.confluent.connect.azure.storage.TopicPartitionWriter)
# [2021-06-30 13:23:37,325] INFO 'https://pg.blob.core.windows.net/pg/topics%2Fblob_topic%2Fpartition%3D0%2Fblob_topic%2B0%2B0000000030.avro?blockid=MDY0NTRjZGMtN2Q3ZS00NjIzLTgyN2EtNmQwxxExYTc2xxDUy&comp=block'==> OUTGOING REQUEST (Try number='1')
#  (com.microsoft.azure.storage.blob.LoggingFactory)
# [2021-06-30 13:24:07,293] INFO 'https://pg.blob.core.windows.net/pg/topics%2Fblob_topic%2Fpartition%3D0%2Fblob_topic%2B0%2B0000000030.avro?blockid=MDY0NTRjZGMtN2Q3ZS00NjIzLTgyN2EtNmQwxxExYTc2xxDUy&comp=block'==> OUTGOING REQUEST (Try number='2')
#  (com.microsoft.azure.storage.blob.LoggingFactory)
# [2021-06-30 13:24:41,261] INFO 'https://pg.blob.core.windows.net/pg/topics%2Fblob_topic%2Fpartition%3D0%2Fblob_topic%2B0%2B0000000030.avro?blockid=MDY0NTRjZGMtN2Q3ZS00NjIzLTgyN2EtNmQwxxExYTc2xxDUy&comp=block'==> OUTGOING REQUEST (Try number='3')
#  (com.microsoft.azure.storage.blob.LoggingFactory)
# [2021-06-30 13:25:23,198] INFO 'https://pg.blob.core.windows.net/pg/topics%2Fblob_topic%2Fpartition%3D0%2Fblob_topic%2B0%2B0000000030.avro?blockid=MDY0NTRjZGMtN2Q3ZS00NjIzLTgyN2EtNmQwxxExYTc2xxDUy&comp=block'==> OUTGOING REQUEST (Try number='4')
#  (com.microsoft.azure.storage.blob.LoggingFactory)
# [2021-06-30 13:26:21,130] ERROR Exception on topic partition blob_topic-0 (io.confluent.connect.azure.storage.AzureStorageSinkTask)
# org.apache.kafka.connect.errors.RetriableException: org.apache.kafka.connect.errors.ConnectException: Multipart upload failed to commitBlockList for bucket pg key topics/blob_topic/partition=0/blob_topic+0+0000000030.avro
#         at io.confluent.connect.azure.storage.TopicPartitionWriter.commitFiles(TopicPartitionWriter.java:393)
#         at io.confluent.connect.azure.storage.TopicPartitionWriter.executeState(TopicPartitionWriter.java:170)
#         at io.confluent.connect.azure.storage.TopicPartitionWriter.write(TopicPartitionWriter.java:133)
#         at io.confluent.connect.azure.storage.AzureStorageSinkTask.put(AzureStorageSinkTask.java:144)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:581)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:329)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:232)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:201)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:182)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:231)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.apache.kafka.connect.errors.ConnectException: Multipart upload failed to commitBlockList for bucket pg key topics/blob_topic/partition=0/blob_topic+0+0000000030.avro
#         at io.confluent.connect.azure.blob.storage.BlobStorageOutputStream.commit(BlobStorageOutputStream.java:161)
#         at io.confluent.connect.azure.storage.AzureStorage.commit(AzureStorage.java:24)
#         at io.confluent.connect.azure.storage.format.avro.AvroRecordWriterProvider$1.commit(AvroRecordWriterProvider.java:87)
#         at io.confluent.connect.azure.storage.TopicPartitionWriter.commitFile(TopicPartitionWriter.java:415)
#         at io.confluent.connect.azure.storage.TopicPartitionWriter.commitFiles(TopicPartitionWriter.java:389)
#         ... 14 more
# Caused by: org.apache.kafka.connect.errors.ConnectException: Failed to upload part topics/blob_topic/partition=0/blob_topic+0+0000000030.avro to bucket pg
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
#         at io.reactivex.internal.observers.ResumeSingleObserver.onError(ResumeSingleObserver.java:51)
#         at io.reactivex.internal.observers.ResumeSingleObserver.onError(ResumeSingleObserver.java:51)
#         at io.reactivex.internal.observers.ResumeSingleObserver.onError(ResumeSingleObserver.java:51)
#         at io.reactivex.internal.disposables.EmptyDisposable.error(EmptyDisposable.java:78)
#         at io.reactivex.internal.operators.single.SingleError.subscribeActual(SingleError.java:42)
#         at io.reactivex.Single.subscribe(Single.java:3394)
#         at io.reactivex.internal.operators.single.SingleResumeNext$ResumeMainSingleObserver.onError(SingleResumeNext.java:80)
#         at io.reactivex.internal.operators.single.SingleFlatMap$SingleFlatMapCallback.onError(SingleFlatMap.java:90)
#         at io.reactivex.internal.observers.ResumeSingleObserver.onError(ResumeSingleObserver.java:51)
#         at io.reactivex.internal.operators.single.SingleTimeout$TimeoutMainObserver.run(SingleTimeout.java:115)
#         at io.reactivex.internal.schedulers.ScheduledDirectTask.call(ScheduledDirectTask.java:38)
#         at io.reactivex.internal.schedulers.ScheduledDirectTask.call(ScheduledDirectTask.java:26)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ScheduledThreadPoolExecutor$ScheduledFutureTask.run(ScheduledThreadPoolExecutor.java:304)
#         ... 3 more
# Caused by: java.util.concurrent.TimeoutException
#         ... 8 more
# [2021-06-30 13:26:21,133] INFO [Consumer clientId=connector-consumer-azure-blob-sink-0, groupId=connect-azure-blob-sink] Seeking to offset 30 for partition blob_topic-0 (org.apache.kafka.clients.consumer.KafkaConsumer)
# [2021-06-30 13:26:21,985] WARN Error emitted before channel is created. Message: Connection timed out: pg.blob.core.windows.net/52.166.80.100:443 (com.microsoft.rest.v2.http.NettyClient)
# [2021-06-30 13:26:21,985] INFO ---- com.microsoft.rest.v2.http.SharedChannelPool@3bb98c48: size 256, keep alive (sec) 60 ---- (com.microsoft.rest.v2.http.SharedChannelPool)
# [2021-06-30 13:26:21,985] INFO Channel  State   For     Age     URL (com.microsoft.rest.v2.http.SharedChannelPool)
# [2021-06-30 13:26:21,989] INFO 1cd84a1b LEASE   164s    203s    https://pg.blob.core.windows.net:443 (com.microsoft.rest.v2.http.SharedChannelPool)
# [2021-06-30 13:26:21,989] INFO Active channels: 3 Leaked or being initialized channels: 2 (com.microsoft.rest.v2.http.SharedChannelPool)
# [2021-06-30 13:26:26,140] INFO Opening record writer for: topics/blob_topic/partition=0/blob_topic+0+0000000030.avro (io.confluent.connect.azure.storage.format.avro.AvroRecordWriterProvider)
# [2021-06-30 13:26:26,146] INFO Starting commit and rotation for topic partition blob_topic-0 with start offset {partition=0=30} (io.confluent.connect.azure.storage.TopicPartitionWriter)
# [2021-06-30 13:26:26,148] INFO 'https://pg.blob.core.windows.net/pg/topics%2Fblob_topic%2Fpartition%3D0%2Fblob_topic%2B0%2B0000000030.avro?blockid=NjU0MjdhYjQtYzRkZC00OTg5LThiNmYtOTUxZDAyYjMzMGM4&comp=block'==> OUTGOING REQUEST (Try number='1')
#  (com.microsoft.azure.storage.blob.LoggingFactory)
# [2021-06-30 13:26:56,115] INFO 'https://pg.blob.core.windows.net/pg/topics%2Fblob_topic%2Fpartition%3D0%2Fblob_topic%2B0%2B0000000030.avro?blockid=NjU0MjdhYjQtYzRkZC00OTg5LThiNmYtOTUxZDAyYjMzMGM4&comp=block'==> OUTGOING REQUEST (Try number='2')
#  (com.microsoft.azure.storage.blob.LoggingFactory)
# [2021-06-30 13:27:02,911] WARN Error emitted before channel is created. Message: Connection timed out: pg.blob.core.windows.net/52.166.80.100:443 (com.microsoft.rest.v2.http.NettyClient)
# [2021-06-30 13:27:02,911] INFO ---- com.microsoft.rest.v2.http.SharedChannelPool@3bb98c48: size 256, keep alive (sec) 60 ---- (com.microsoft.rest.v2.http.SharedChannelPool)
# [2021-06-30 13:27:02,911] INFO Channel  State   For     Age     URL (com.microsoft.rest.v2.http.SharedChannelPool)
# [2021-06-30 13:27:02,912] INFO 1cd84a1b LEASE   205s    244s    https://pg.blob.core.windows.net:443 (com.microsoft.rest.v2.http.SharedChannelPool)
# [2021-06-30 13:27:02,912] INFO Active channels: 4 Leaked or being initialized channels: 3 (com.microsoft.rest.v2.http.SharedChannelPool)
# [2021-06-30 13:27:30,084] INFO 'https://pg.blob.core.windows.net/pg/topics%2Fblob_topic%2Fpartition%3D0%2Fblob_topic%2B0%2B0000000030.avro?blockid=NjU0MjdhYjQtYzRkZC00OTg5LThiNmYtOTUxZDAyYjMzMGM4&comp=block'==> OUTGOING REQUEST (Try number='3')
#  (com.microsoft.azure.storage.blob.LoggingFactory)
# [2021-06-30 13:28:00,186] WARN Error emitted before channel is created. Message: Connection timed out: pg.blob.core.windows.net/52.166.80.100:443 (com.microsoft.rest.v2.http.NettyClient)
# [2021-06-30 13:28:00,186] INFO ---- com.microsoft.rest.v2.http.SharedChannelPool@3bb98c48: size 256, keep alive (sec) 60 ---- (com.microsoft.rest.v2.http.SharedChannelPool)
# [2021-06-30 13:28:00,186] INFO Channel  State   For     Age     URL (com.microsoft.rest.v2.http.SharedChannelPool)
# [2021-06-30 13:28:00,186] INFO 1cd84a1b LEASE   262s    301s    https://pg.blob.core.windows.net:443 (com.microsoft.rest.v2.http.SharedChannelPool)
# [2021-06-30 13:28:00,186] INFO Active channels: 4 Leaked or being initialized channels: 3 (com.microsoft.rest.v2.http.SharedChannelPool)
# [2021-06-30 13:28:12,051] INFO 'https://pg.blob.core.windows.net/pg/topics%2Fblob_topic%2Fpartition%3D0%2Fblob_topic%2B0%2B0000000030.avro?blockid=NjU0MjdhYjQtYzRkZC00OTg5LThiNmYtOTUxZDAyYjMzMGM4&comp=block'==> OUTGOING REQUEST (Try number='4')
#  (com.microsoft.azure.storage.blob.LoggingFactory)
# [2021-06-30 13:28:37,015] WARN Error emitted before channel is created. Message: Connection timed out: pg.blob.core.windows.net/52.166.80.100:443 (com.microsoft.rest.v2.http.NettyClient)
# [2021-06-30 13:28:37,015] INFO ---- com.microsoft.rest.v2.http.SharedChannelPool@3bb98c48: size 256, keep alive (sec) 60 ---- (com.microsoft.rest.v2.http.SharedChannelPool)
# [2021-06-30 13:28:37,016] INFO Channel  State   For     Age     URL (com.microsoft.rest.v2.http.SharedChannelPool)
# [2021-06-30 13:28:37,016] INFO 1cd84a1b LEASE   299s    338s    https://pg.blob.core.windows.net:443 (com.microsoft.rest.v2.http.SharedChannelPool)
# [2021-06-30 13:28:37,016] INFO Active channels: 3 Leaked or being initialized channels: 2 (com.microsoft.rest.v2.http.SharedChannelPool)
# [2021-06-30 13:29:09,748] WARN Error emitted before channel is created. Message: Connection timed out: pg.blob.core.windows.net/52.166.80.100:443 (com.microsoft.rest.v2.http.NettyClient)
# [2021-06-30 13:29:09,749] INFO ---- com.microsoft.rest.v2.http.SharedChannelPool@3bb98c48: size 256, keep alive (sec) 60 ---- (com.microsoft.rest.v2.http.SharedChannelPool)
# [2021-06-30 13:29:09,749] INFO Channel  State   For     Age     URL (com.microsoft.rest.v2.http.SharedChannelPool)
# [2021-06-30 13:29:09,749] INFO 1cd84a1b LEASE   332s    371s    https://pg.blob.core.windows.net:443 (com.microsoft.rest.v2.http.SharedChannelPool)
# [2021-06-30 13:29:09,749] INFO Active channels: 3 Leaked or being initialized channels: 2 (com.microsoft.rest.v2.http.SharedChannelPool)
# [2021-06-30 13:29:09,987] ERROR Exception on topic partition blob_topic-0 (io.confluent.connect.azure.storage.AzureStorageSinkTask)
# org.apache.kafka.connect.errors.RetriableException: org.apache.kafka.connect.errors.ConnectException: Multipart upload failed to commitBlockList for bucket pg key topics/blob_topic/partition=0/blob_topic+0+0000000030.avro
#         at io.confluent.connect.azure.storage.TopicPartitionWriter.commitFiles(TopicPartitionWriter.java:393)
#         at io.confluent.connect.azure.storage.TopicPartitionWriter.executeState(TopicPartitionWriter.java:170)
#         at io.confluent.connect.azure.storage.TopicPartitionWriter.write(TopicPartitionWriter.java:133)
#         at io.confluent.connect.azure.storage.AzureStorageSinkTask.put(AzureStorageSinkTask.java:144)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:581)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:329)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:232)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:201)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:182)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:231)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.apache.kafka.connect.errors.ConnectException: Multipart upload failed to commitBlockList for bucket pg key topics/blob_topic/partition=0/blob_topic+0+0000000030.avro
#         at io.confluent.connect.azure.blob.storage.BlobStorageOutputStream.commit(BlobStorageOutputStream.java:161)
#         at io.confluent.connect.azure.storage.AzureStorage.commit(AzureStorage.java:24)
#         at io.confluent.connect.azure.storage.format.avro.AvroRecordWriterProvider$1.commit(AvroRecordWriterProvider.java:87)
#         at io.confluent.connect.azure.storage.TopicPartitionWriter.commitFile(TopicPartitionWriter.java:415)
#         at io.confluent.connect.azure.storage.TopicPartitionWriter.commitFiles(TopicPartitionWriter.java:389)
#         ... 14 more
# Caused by: org.apache.kafka.connect.errors.ConnectException: Failed to upload part topics/blob_topic/partition=0/blob_topic+0+0000000030.avro to bucket pg
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
#         at io.reactivex.internal.observers.ResumeSingleObserver.onError(ResumeSingleObserver.java:51)
#         at io.reactivex.internal.observers.ResumeSingleObserver.onError(ResumeSingleObserver.java:51)
#         at io.reactivex.internal.observers.ResumeSingleObserver.onError(ResumeSingleObserver.java:51)
#         at io.reactivex.internal.disposables.EmptyDisposable.error(EmptyDisposable.java:78)
#         at io.reactivex.internal.operators.single.SingleError.subscribeActual(SingleError.java:42)
#         at io.reactivex.Single.subscribe(Single.java:3394)
#         at io.reactivex.internal.operators.single.SingleResumeNext$ResumeMainSingleObserver.onError(SingleResumeNext.java:80)
#         at io.reactivex.internal.operators.single.SingleFlatMap$SingleFlatMapCallback.onError(SingleFlatMap.java:90)
#         at io.reactivex.internal.observers.ResumeSingleObserver.onError(ResumeSingleObserver.java:51)
#         at io.reactivex.internal.operators.single.SingleTimeout$TimeoutMainObserver.run(SingleTimeout.java:115)
#         at io.reactivex.internal.schedulers.ScheduledDirectTask.call(ScheduledDirectTask.java:38)
#         at io.reactivex.internal.schedulers.ScheduledDirectTask.call(ScheduledDirectTask.java:26)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ScheduledThreadPoolExecutor$ScheduledFutureTask.run(ScheduledThreadPoolExecutor.java:304)
#         ... 3 more
# Caused by: java.util.concurrent.TimeoutException
#         ... 8 more
# [2021-06-30 13:29:09,990] INFO [Consumer clientId=connector-consumer-azure-blob-sink-0, groupId=connect-azure-blob-sink] Seeking to offset 30 for partition blob_topic-0 (org.apache.kafka.clients.consumer.KafkaConsumer)
# [2021-06-30 13:29:14,997] INFO Opening record writer for: topics/blob_topic/partition=0/blob_topic+0+0000000030.avro (io.confluent.connect.azure.storage.format.avro.AvroRecordWriterProvider)
# [2021-06-30 13:29:15,000] INFO Starting commit and rotation for topic partition blob_topic-0 with start offset {partition=0=30} (io.confluent.connect.azure.storage.TopicPartitionWriter)
# [2021-06-30 13:29:15,002] INFO 'https://pg.blob.core.windows.net/pg/topics%2Fblob_topic%2Fpartition%3D0%2Fblob_topic%2B0%2B0000000030.avro?blockid=NTIwYTgwYmUtNmU0Yi00MTI0LTg3MWMtZDY5MDRmMWEyNjJj&comp=block'==> OUTGOING REQUEST (Try number='1')
#  (com.microsoft.azure.storage.blob.LoggingFactory)
# [2021-06-30 13:29:44,968] INFO 'https://pg.blob.core.windows.net/pg/topics%2Fblob_topic%2Fpartition%3D0%2Fblob_topic%2B0%2B0000000030.avro?blockid=NTIwYTgwYmUtNmU0Yi00MTI0LTg3MWMtZDY5MDRmMWEyNjJj&comp=block'==> OUTGOING REQUEST (Try number='2')
#  (com.microsoft.azure.storage.blob.LoggingFactory)