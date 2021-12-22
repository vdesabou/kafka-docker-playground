#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

function wait_for_repro () {
     MAX_WAIT=4200
     CUR_WAIT=0
     log "Waiting up to $MAX_WAIT seconds for error Invalid JWT Signature to happen"
     docker container logs connect > /tmp/out.txt 2>&1
     while ! grep "Invalid JWT Signature" /tmp/out.txt > /dev/null;
     do
          sleep 10
          docker container logs connect > /tmp/out.txt 2>&1
          CUR_WAIT=$(( CUR_WAIT+10 ))
          if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
               echo -e "\nERROR: The logs in all connect containers do not show 'Invalid JWT Signature' after $MAX_WAIT seconds. Please troubleshoot with 'docker container ps' and 'docker container logs'.\n"
               exit 1
          fi
     done
     log "The problem has been reproduced !"
}

for component in producer-v1
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

PROJECT=${1:-vincent-de-saboulin-lab}

KEYFILE="${DIR}/keyfile-rcca-5246.json"
if [ ! -f ${KEYFILE} ]
then
     logerror "ERROR: the file ${KEYFILE} file is not present!"
     log "it should be used with a service account with Service Account Admin and Service Account Key Admin roles !!!"
     exit 1
fi

GCS_BUCKET_NAME=kafka-docker-playground-bucket-${USER}-rcca-5246
GCS_BUCKET_NAME=${GCS_BUCKET_NAME//[-.]/}

log "Doing gsutil authentication"
set +e
docker rm -f gcloud-config
set -e
docker run -i -v ${KEYFILE}:/tmp/keyfile.json --name gcloud-config google/cloud-sdk:latest gcloud auth activate-service-account --project ${PROJECT} --key-file /tmp/keyfile.json

log "Creating bucket name <$GCS_BUCKET_NAME>, if required"
set +e
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gsutil mb -p $(cat ${KEYFILE} | jq -r .project_id) gs://$GCS_BUCKET_NAME
set -e

log "Removing existing objects in GCS, if applicable"
set +e
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gsutil -m rm -r gs://$GCS_BUCKET_NAME/topics/gcs_topic
set -e

log "Creating file keyfile-rcca-5246.json that will be used by connector"
KEYFILE_QUICKLY_EXPIRING="${DIR}/keyfile-rcca-5246-quickly-expiring-key.json"
cp $KEYFILE $KEYFILE_QUICKLY_EXPIRING

log "Creating certificate valid for 5 minutes"
go build create-quickly-expiring-certs-repro-rcca-5246.go && go run create-quickly-expiring-certs-repro-rcca-5246.go

iam_account=$(cat $KEYFILE | jq -r .client_email)
log "Uploading cert to GCP"
docker run -i --volumes-from gcloud-config -v ${DIR}/pem:/tmp/pem google/cloud-sdk:latest gcloud iam service-accounts keys upload /tmp/pem --iam-account=$iam_account > results.log 2>&1
cat results.log

PRIVATE_KEY_ID=$(grep "name:" results.log | cut -d "/" -f 6)
log "Adding the new key $PRIVATE_KEY_ID in $KEYFILE_QUICKLY_EXPIRING"
PRIVATE_KEY=$(awk '{printf "%s\n", $0}' key)
jq --arg variable "$PRIVATE_KEY" '.private_key = $variable' $KEYFILE_QUICKLY_EXPIRING > /tmp/tmp
cp /tmp/tmp $KEYFILE_QUICKLY_EXPIRING
jq --arg variable "$PRIVATE_KEY_ID" '.private_key_id = $variable' $KEYFILE_QUICKLY_EXPIRING > /tmp/tmp
cp /tmp/tmp $KEYFILE_QUICKLY_EXPIRING

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.rcca-5246.yml"

log "Run Java producer-v1 in background"
docker exec -d producer-v1 bash -c "java -jar producer-v1-1.0.0-jar-with-dependencies.jar"

log "Creating GCS Sink connector using keyfile-rcca-5246-quickly-expiring-key.json"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.gcs.GcsSinkConnector",
               "tasks.max" : "1",
               "topics" : "gcs_topic",
               "gcs.bucket.name" : "'"$GCS_BUCKET_NAME"'",
               "gcs.part.size": "5242880",
               "flush.size": "100000000",
               "gcs.credentials.path": "/tmp/keyfile-rcca-5246-quickly-expiring-key.json",
               "storage.class": "io.confluent.connect.gcs.storage.GcsStorage",
               "format.class": "io.confluent.connect.gcs.format.avro.AvroFormat",
               "partitioner.class": "io.confluent.connect.storage.partitioner.DailyPartitioner",
               "rotate.schedule.interval.ms": "60000",
               "locale": "en_US",
               "timezone": "UTC",
               "schema.compatibility": "NONE",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/gcs-sink-rcca-5246/config | jq .

log "It takes about one hour for token to expire"
wait_for_repro

# {
#   "name": "gcs-sink-rcca-5246",
#   "connector": {
#     "state": "RUNNING",
#     "worker_id": "connect:8083"
#   },
#   "tasks": [
#     {
#       "id": 0,
#       "state": "FAILED",
#       "worker_id": "connect:8083",
#       "trace": "org.apache.kafka.connect.errors.ConnectException: Exiting WorkerSinkTask due to unrecoverable exception.\n\tat org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:638)\n\tat org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:334)\n\tat org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)\n\tat org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)\n\tat org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)\n\tat org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)\n\tat java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)\n\tat java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)\n\tat java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)\n\tat java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)\n\tat java.base/java.lang.Thread.run(Thread.java:829)\nCaused by: org.apache.kafka.connect.errors.ConnectException: java.io.IOException: Multipart upload failed: \n\tat io.confluent.connect.gcs.format.avro.AvroRecordWriterProvider$1.write(AvroRecordWriterProvider.java:75)\n\tat io.confluent.connect.gcs.TopicPartitionWriter.writeRecord(TopicPartitionWriter.java:472)\n\tat io.confluent.connect.gcs.TopicPartitionWriter.checkRotationOrAppend(TopicPartitionWriter.java:254)\n\tat io.confluent.connect.gcs.TopicPartitionWriter.executeState(TopicPartitionWriter.java:199)\n\tat io.confluent.connect.gcs.TopicPartitionWriter.write(TopicPartitionWriter.java:168)\n\tat io.confluent.connect.gcs.GcsSinkTask.put(GcsSinkTask.java:175)\n\tat org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:604)\n\t... 10 more\nCaused by: java.io.IOException: Multipart upload failed: \n\tat io.confluent.connect.gcs.storage.GcsOutputStream.uploadPart(GcsOutputStream.java:121)\n\tat io.confluent.connect.gcs.storage.GcsOutputStream.write(GcsOutputStream.java:98)\n\tat org.apache.avro.file.DataFileWriter$BufferedFileOutputStream$PositionFilter.write(DataFileWriter.java:476)\n\tat java.base/java.io.BufferedOutputStream.write(BufferedOutputStream.java:123)\n\tat org.apache.avro.io.BufferedBinaryEncoder$OutputStreamSink.innerWrite(BufferedBinaryEncoder.java:227)\n\tat org.apache.avro.io.BufferedBinaryEncoder.writeFixed(BufferedBinaryEncoder.java:157)\n\tat org.apache.avro.file.DataFileStream$DataBlock.writeBlockTo(DataFileStream.java:393)\n\tat org.apache.avro.file.DataFileWriter.writeBlock(DataFileWriter.java:408)\n\tat org.apache.avro.file.DataFileWriter.writeIfBlockFull(DataFileWriter.java:351)\n\tat org.apache.avro.file.DataFileWriter.append(DataFileWriter.java:320)\n\tat io.confluent.connect.gcs.format.avro.AvroRecordWriterProvider$1.write(AvroRecordWriterProvider.java:73)\n\t... 16 more\nCaused by: java.io.IOException: Error getting access token for service account: 400 Bad Request\nPOST https://oauth2.googleapis.com/token\n{\"error\":\"invalid_grant\",\"error_description\":\"Invalid JWT Signature.\"}\n\tat com.google.auth.oauth2.ServiceAccountCredentials.refreshAccessToken(ServiceAccountCredentials.java:444)\n\tat com.google.auth.oauth2.OAuth2Credentials.refresh(OAuth2Credentials.java:157)\n\tat com.google.auth.oauth2.OAuth2Credentials.getRequestMetadata(OAuth2Credentials.java:145)\n\tat com.google.auth.oauth2.ServiceAccountCredentials.getRequestMetadata(ServiceAccountCredentials.java:603)\n\tat com.google.auth.http.HttpCredentialsAdapter.initialize(HttpCredentialsAdapter.java:91)\n\tat com.google.cloud.http.HttpTransportOptions$1.initialize(HttpTransportOptions.java:159)\n\tat com.google.cloud.http.CensusHttpModule$CensusHttpRequestInitializer.initialize(CensusHttpModule.java:109)\n\tat com.google.api.client.http.HttpRequestFactory.buildRequest(HttpRequestFactory.java:88)\n\tat com.google.api.client.googleapis.services.AbstractGoogleClientRequest.buildHttpRequest(AbstractGoogleClientRequest.java:422)\n\tat com.google.api.client.googleapis.services.AbstractGoogleClientRequest.buildHttpRequest(AbstractGoogleClientRequest.java:398)\n\tat com.google.cloud.storage.spi.v1.HttpStorageRpc.open(HttpStorageRpc.java:836)\n\tat com.google.cloud.storage.BlobWriteChannel$2.call(BlobWriteChannel.java:94)\n\tat com.google.cloud.storage.BlobWriteChannel$2.call(BlobWriteChannel.java:91)\n\tat com.google.api.gax.retrying.DirectRetryingExecutor.submit(DirectRetryingExecutor.java:105)\n\tat com.google.cloud.RetryHelper.run(RetryHelper.java:76)\n\tat com.google.cloud.RetryHelper.runWithRetries(RetryHelper.java:50)\n\tat com.google.cloud.storage.BlobWriteChannel.open(BlobWriteChannel.java:90)\n\tat com.google.cloud.storage.BlobWriteChannel.<init>(BlobWriteChannel.java:36)\n\tat com.google.cloud.storage.StorageImpl.writer(StorageImpl.java:701)\n\tat com.google.cloud.storage.StorageImpl.writer(StorageImpl.java:691)\n\tat com.google.cloud.storage.StorageImpl.writer(StorageImpl.java:98)\n\tat io.confluent.connect.gcs.storage.GcsOutputStream$MultipartUpload.uploadPart(GcsOutputStream.java:203)\n\tat io.confluent.connect.gcs.storage.GcsOutputStream.uploadPart(GcsOutputStream.java:116)\n\t... 26 more\nCaused by: com.google.api.client.http.HttpResponseException: 400 Bad Request\nPOST https://oauth2.googleapis.com/token\n{\"error\":\"invalid_grant\",\"error_description\":\"Invalid JWT Signature.\"}\n\tat com.google.api.client.http.HttpRequest.execute(HttpRequest.java:1113)\n\tat com.google.auth.oauth2.ServiceAccountCredentials.refreshAccessToken(ServiceAccountCredentials.java:441)\n\t... 48 more\n"
#     }
#   ],
#   "type": "sink"
# }

# [2021-12-22 10:40:00,095] ERROR [gcs-sink-rcca-5246|task-0] Failed to complete MultipartUpload for bucket 'kafkadockerplaygroundbucketvsaboulinrcca5246' key 'topics/gcs_topic/year=2021/month=12/day=22/gcs_topic+0+0000344366.avro', id 'BlobId{bucket=kafkadockerplaygroundbucketvsaboulinrcca5246, name=topics/gcs_topic/year=2021/month=12/day=22/gcs_topic+0+0000344366.avro, generation=null}' (io.confluent.connect.gcs.storage.GcsOutputStream:223)
# [2021-12-22 10:40:00,097] ERROR [gcs-sink-rcca-5246|task-0] Exception on topic partition gcs_topic-0:  (io.confluent.connect.gcs.GcsSinkTask:177)
# org.apache.kafka.connect.errors.RetriableException: org.apache.kafka.connect.errors.ConnectException: java.io.IOException: Resumable multiPartUpload failed to complete.
# 	at io.confluent.connect.gcs.TopicPartitionWriter.commitFiles(TopicPartitionWriter.java:484)
# 	at io.confluent.connect.gcs.TopicPartitionWriter.commitOnTimeIfNoData(TopicPartitionWriter.java:282)
# 	at io.confluent.connect.gcs.TopicPartitionWriter.write(TopicPartitionWriter.java:173)
# 	at io.confluent.connect.gcs.GcsSinkTask.put(GcsSinkTask.java:175)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:604)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:334)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
# 	at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)
# 	at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)
# 	at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
# 	at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.apache.kafka.connect.errors.ConnectException: java.io.IOException: Resumable multiPartUpload failed to complete.
# 	at io.confluent.connect.gcs.format.avro.AvroRecordWriterProvider$1.commit(AvroRecordWriterProvider.java:88)
# 	at io.confluent.connect.gcs.TopicPartitionWriter.commitFile(TopicPartitionWriter.java:504)
# 	at io.confluent.connect.gcs.TopicPartitionWriter.commitFiles(TopicPartitionWriter.java:480)
# 	... 14 more
# Caused by: java.io.IOException: Resumable multiPartUpload failed to complete.
# 	at io.confluent.connect.gcs.storage.GcsOutputStream$MultipartUpload.completeError(GcsOutputStream.java:224)
# 	at io.confluent.connect.gcs.storage.GcsOutputStream.commit(GcsOutputStream.java:143)
# 	at io.confluent.connect.gcs.format.avro.AvroRecordWriterProvider$1.commit(AvroRecordWriterProvider.java:85)
# 	... 16 more
# Caused by: com.google.cloud.storage.StorageException: Error getting access token for service account: 400 Bad Request
# POST https://oauth2.googleapis.com/token
# {"error":"invalid_grant","error_description":"Invalid JWT Signature."}
# 	at com.google.cloud.storage.spi.v1.HttpStorageRpc.translate(HttpStorageRpc.java:231)
# 	at com.google.cloud.storage.spi.v1.HttpStorageRpc.writeWithResponse(HttpStorageRpc.java:822)
# 	at com.google.cloud.storage.BlobWriteChannel$1.run(BlobWriteChannel.java:69)
# 	at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
# 	at com.google.api.gax.retrying.DirectRetryingExecutor.submit(DirectRetryingExecutor.java:105)
# 	at com.google.cloud.RetryHelper.run(RetryHelper.java:76)
# 	at com.google.cloud.RetryHelper.runWithRetries(RetryHelper.java:50)
# 	at com.google.cloud.storage.BlobWriteChannel.flushBuffer(BlobWriteChannel.java:61)
# 	at com.google.cloud.BaseWriteChannel.close(BaseWriteChannel.java:151)
# 	at io.confluent.connect.gcs.storage.GcsOutputStream$MultipartUpload.complete(GcsOutputStream.java:214)
# 	at io.confluent.connect.gcs.storage.GcsOutputStream.commit(GcsOutputStream.java:141)
# 	... 17 more
# Caused by: java.io.IOException: Error getting access token for service account: 400 Bad Request
# POST https://oauth2.googleapis.com/token
# {"error":"invalid_grant","error_description":"Invalid JWT Signature."}
# 	at com.google.auth.oauth2.ServiceAccountCredentials.refreshAccessToken(ServiceAccountCredentials.java:444)
# 	at com.google.auth.oauth2.OAuth2Credentials.refresh(OAuth2Credentials.java:157)
# 	at com.google.auth.oauth2.OAuth2Credentials.getRequestMetadata(OAuth2Credentials.java:145)
# 	at com.google.auth.oauth2.ServiceAccountCredentials.getRequestMetadata(ServiceAccountCredentials.java:603)
# 	at com.google.auth.http.HttpCredentialsAdapter.initialize(HttpCredentialsAdapter.java:91)
# 	at com.google.cloud.http.HttpTransportOptions$1.initialize(HttpTransportOptions.java:159)
# 	at com.google.cloud.http.CensusHttpModule$CensusHttpRequestInitializer.initialize(CensusHttpModule.java:109)
# 	at com.google.api.client.http.HttpRequestFactory.buildRequest(HttpRequestFactory.java:88)
# 	at com.google.api.client.http.HttpRequestFactory.buildPutRequest(HttpRequestFactory.java:139)
# 	at com.google.cloud.storage.spi.v1.HttpStorageRpc.writeWithResponse(HttpStorageRpc.java:769)
# 	... 26 more
# Caused by: com.google.api.client.http.HttpResponseException: 400 Bad Request
# POST https://oauth2.googleapis.com/token
# {"error":"invalid_grant","error_description":"Invalid JWT Signature."}
# 	at com.google.api.client.http.HttpRequest.execute(HttpRequest.java:1113)
# 	at com.google.auth.oauth2.ServiceAccountCredentials.refreshAccessToken(ServiceAccountCredentials.java:441)
# 	... 35 more
# [2021-12-22 10:40:00,143] ERROR [gcs-sink-rcca-5246|task-0] Failed to complete MultipartUpload for bucket 'kafkadockerplaygroundbucketvsaboulinrcca5246' key 'topics/gcs_topic/year=2021/month=12/day=22/gcs_topic+4+0000342480.avro', id 'BlobId{bucket=kafkadockerplaygroundbucketvsaboulinrcca5246, name=topics/gcs_topic/year=2021/month=12/day=22/gcs_topic+4+0000342480.avro, generation=null}' (io.confluent.connect.gcs.storage.GcsOutputStream:223)
# [2021-12-22 10:40:00,144] ERROR [gcs-sink-rcca-5246|task-0] Exception on topic partition gcs_topic-4:  (io.confluent.connect.gcs.GcsSinkTask:177)
# org.apache.kafka.connect.errors.RetriableException: org.apache.kafka.connect.errors.ConnectException: java.io.IOException: Resumable multiPartUpload failed to complete.
# 	at io.confluent.connect.gcs.TopicPartitionWriter.commitFiles(TopicPartitionWriter.java:484)
# 	at io.confluent.connect.gcs.TopicPartitionWriter.executeState(TopicPartitionWriter.java:210)
# 	at io.confluent.connect.gcs.TopicPartitionWriter.write(TopicPartitionWriter.java:168)
# 	at io.confluent.connect.gcs.GcsSinkTask.put(GcsSinkTask.java:175)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:604)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:334)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
# 	at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)
# 	at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)
# 	at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
# 	at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.apache.kafka.connect.errors.ConnectException: java.io.IOException: Resumable multiPartUpload failed to complete.
# 	at io.confluent.connect.gcs.format.avro.AvroRecordWriterProvider$1.commit(AvroRecordWriterProvider.java:88)
# 	at io.confluent.connect.gcs.TopicPartitionWriter.commitFile(TopicPartitionWriter.java:504)
# 	at io.confluent.connect.gcs.TopicPartitionWriter.commitFiles(TopicPartitionWriter.java:480)
# 	... 14 more
# Caused by: java.io.IOException: Resumable multiPartUpload failed to complete.
# 	at io.confluent.connect.gcs.storage.GcsOutputStream$MultipartUpload.completeError(GcsOutputStream.java:224)
# 	at io.confluent.connect.gcs.storage.GcsOutputStream.commit(GcsOutputStream.java:143)
# 	at io.confluent.connect.gcs.format.avro.AvroRecordWriterProvider$1.commit(AvroRecordWriterProvider.java:85)
# 	... 16 more
# Caused by: com.google.cloud.storage.StorageException: Error getting access token for service account: 400 Bad Request
# POST https://oauth2.googleapis.com/token
# {"error":"invalid_grant","error_description":"Invalid JWT Signature."}
# 	at com.google.cloud.storage.spi.v1.HttpStorageRpc.translate(HttpStorageRpc.java:231)
# 	at com.google.cloud.storage.spi.v1.HttpStorageRpc.writeWithResponse(HttpStorageRpc.java:822)
# 	at com.google.cloud.storage.BlobWriteChannel$1.run(BlobWriteChannel.java:69)
# 	at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
# 	at com.google.api.gax.retrying.DirectRetryingExecutor.submit(DirectRetryingExecutor.java:105)
# 	at com.google.cloud.RetryHelper.run(RetryHelper.java:76)
# 	at com.google.cloud.RetryHelper.runWithRetries(RetryHelper.java:50)
# 	at com.google.cloud.storage.BlobWriteChannel.flushBuffer(BlobWriteChannel.java:61)
# 	at com.google.cloud.BaseWriteChannel.close(BaseWriteChannel.java:151)
# 	at io.confluent.connect.gcs.storage.GcsOutputStream$MultipartUpload.complete(GcsOutputStream.java:214)
# 	at io.confluent.connect.gcs.storage.GcsOutputStream.commit(GcsOutputStream.java:141)
# 	... 17 more
# Caused by: java.io.IOException: Error getting access token for service account: 400 Bad Request
# POST https://oauth2.googleapis.com/token
# {"error":"invalid_grant","error_description":"Invalid JWT Signature."}
# 	at com.google.auth.oauth2.ServiceAccountCredentials.refreshAccessToken(ServiceAccountCredentials.java:444)
# 	at com.google.auth.oauth2.OAuth2Credentials.refresh(OAuth2Credentials.java:157)
# 	at com.google.auth.oauth2.OAuth2Credentials.getRequestMetadata(OAuth2Credentials.java:145)
# 	at com.google.auth.oauth2.ServiceAccountCredentials.getRequestMetadata(ServiceAccountCredentials.java:603)
# 	at com.google.auth.http.HttpCredentialsAdapter.initialize(HttpCredentialsAdapter.java:91)
# 	at com.google.cloud.http.HttpTransportOptions$1.initialize(HttpTransportOptions.java:159)
# 	at com.google.cloud.http.CensusHttpModule$CensusHttpRequestInitializer.initialize(CensusHttpModule.java:109)
# 	at com.google.api.client.http.HttpRequestFactory.buildRequest(HttpRequestFactory.java:88)
# 	at com.google.api.client.http.HttpRequestFactory.buildPutRequest(HttpRequestFactory.java:139)
# 	at com.google.cloud.storage.spi.v1.HttpStorageRpc.writeWithResponse(HttpStorageRpc.java:769)
# 	... 26 more
# Caused by: com.google.api.client.http.HttpResponseException: 400 Bad Request
# POST https://oauth2.googleapis.com/token
# {"error":"invalid_grant","error_description":"Invalid JWT Signature."}
# 	at com.google.api.client.http.HttpRequest.execute(HttpRequest.java:1113)
# 	at com.google.auth.oauth2.ServiceAccountCredentials.refreshAccessToken(ServiceAccountCredentials.java:441)
# 	... 35 more
# [2021-12-22 10:40:00,145] INFO [gcs-sink-rcca-5246|task-0] Committing files after waiting for rotateIntervalMs time but less than flush.size records available. (io.confluent.connect.gcs.TopicPartitionWriter:276)
# [2021-12-22 10:40:00,175] ERROR [gcs-sink-rcca-5246|task-0] Failed to complete MultipartUpload for bucket 'kafkadockerplaygroundbucketvsaboulinrcca5246' key 'topics/gcs_topic/year=2021/month=12/day=22/gcs_topic+3+0000343131.avro', id 'BlobId{bucket=kafkadockerplaygroundbucketvsaboulinrcca5246, name=topics/gcs_topic/year=2021/month=12/day=22/gcs_topic+3+0000343131.avro, generation=null}' (io.confluent.connect.gcs.storage.GcsOutputStream:223)
# [2021-12-22 10:40:00,175] ERROR [gcs-sink-rcca-5246|task-0] Exception on topic partition gcs_topic-3:  (io.confluent.connect.gcs.GcsSinkTask:177)
# org.apache.kafka.connect.errors.RetriableException: org.apache.kafka.connect.errors.ConnectException: java.io.IOException: Resumable multiPartUpload failed to complete.
# 	at io.confluent.connect.gcs.TopicPartitionWriter.commitFiles(TopicPartitionWriter.java:484)
# 	at io.confluent.connect.gcs.TopicPartitionWriter.commitOnTimeIfNoData(TopicPartitionWriter.java:282)
# 	at io.confluent.connect.gcs.TopicPartitionWriter.write(TopicPartitionWriter.java:173)
# 	at io.confluent.connect.gcs.GcsSinkTask.put(GcsSinkTask.java:175)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:604)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:334)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
# 	at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)
# 	at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)
# 	at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
# 	at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.apache.kafka.connect.errors.ConnectException: java.io.IOException: Resumable multiPartUpload failed to complete.
# 	at io.confluent.connect.gcs.format.avro.AvroRecordWriterProvider$1.commit(AvroRecordWriterProvider.java:88)
# 	at io.confluent.connect.gcs.TopicPartitionWriter.commitFile(TopicPartitionWriter.java:504)
# 	at io.confluent.connect.gcs.TopicPartitionWriter.commitFiles(TopicPartitionWriter.java:480)
# 	... 14 more
# Caused by: java.io.IOException: Resumable multiPartUpload failed to complete.
# 	at io.confluent.connect.gcs.storage.GcsOutputStream$MultipartUpload.completeError(GcsOutputStream.java:224)
# 	at io.confluent.connect.gcs.storage.GcsOutputStream.commit(GcsOutputStream.java:143)
# 	at io.confluent.connect.gcs.format.avro.AvroRecordWriterProvider$1.commit(AvroRecordWriterProvider.java:85)
# 	... 16 more
# Caused by: com.google.cloud.storage.StorageException: Error getting access token for service account: 400 Bad Request
# POST https://oauth2.googleapis.com/token
# {"error":"invalid_grant","error_description":"Invalid JWT Signature."}
# 	at com.google.cloud.storage.spi.v1.HttpStorageRpc.translate(HttpStorageRpc.java:231)
# 	at com.google.cloud.storage.spi.v1.HttpStorageRpc.writeWithResponse(HttpStorageRpc.java:822)
# 	at com.google.cloud.storage.BlobWriteChannel$1.run(BlobWriteChannel.java:69)
# 	at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
# 	at com.google.api.gax.retrying.DirectRetryingExecutor.submit(DirectRetryingExecutor.java:105)
# 	at com.google.cloud.RetryHelper.run(RetryHelper.java:76)
# 	at com.google.cloud.RetryHelper.runWithRetries(RetryHelper.java:50)
# 	at com.google.cloud.storage.BlobWriteChannel.flushBuffer(BlobWriteChannel.java:61)
# 	at com.google.cloud.BaseWriteChannel.close(BaseWriteChannel.java:151)
# 	at io.confluent.connect.gcs.storage.GcsOutputStream$MultipartUpload.complete(GcsOutputStream.java:214)
# 	at io.confluent.connect.gcs.storage.GcsOutputStream.commit(GcsOutputStream.java:141)
# 	... 17 more
# Caused by: java.io.IOException: Error getting access token for service account: 400 Bad Request
# POST https://oauth2.googleapis.com/token
# {"error":"invalid_grant","error_description":"Invalid JWT Signature."}
# 	at com.google.auth.oauth2.ServiceAccountCredentials.refreshAccessToken(ServiceAccountCredentials.java:444)
# 	at com.google.auth.oauth2.OAuth2Credentials.refresh(OAuth2Credentials.java:157)
# 	at com.google.auth.oauth2.OAuth2Credentials.getRequestMetadata(OAuth2Credentials.java:145)
# 	at com.google.auth.oauth2.ServiceAccountCredentials.getRequestMetadata(ServiceAccountCredentials.java:603)
# 	at com.google.auth.http.HttpCredentialsAdapter.initialize(HttpCredentialsAdapter.java:91)
# 	at com.google.cloud.http.HttpTransportOptions$1.initialize(HttpTransportOptions.java:159)
# 	at com.google.cloud.http.CensusHttpModule$CensusHttpRequestInitializer.initialize(CensusHttpModule.java:109)
# 	at com.google.api.client.http.HttpRequestFactory.buildRequest(HttpRequestFactory.java:88)
# 	at com.google.api.client.http.HttpRequestFactory.buildPutRequest(HttpRequestFactory.java:139)
# 	at com.google.cloud.storage.spi.v1.HttpStorageRpc.writeWithResponse(HttpStorageRpc.java:769)
# 	... 26 more
# Caused by: com.google.api.client.http.HttpResponseException: 400 Bad Request
# POST https://oauth2.googleapis.com/token
# {"error":"invalid_grant","error_description":"Invalid JWT Signature."}
# 	at com.google.api.client.http.HttpRequest.execute(HttpRequest.java:1113)
# 	at com.google.auth.oauth2.ServiceAccountCredentials.refreshAccessToken(ServiceAccountCredentials.java:441)
# 	... 35 more
# [2021-12-22 10:40:00,176] INFO [gcs-sink-rcca-5246|task-0] Committing files after waiting for rotateIntervalMs time but less than flush.size records available. (io.confluent.connect.gcs.TopicPartitionWriter:276)
# [2021-12-22 10:40:00,205] ERROR [gcs-sink-rcca-5246|task-0] Failed to complete MultipartUpload for bucket 'kafkadockerplaygroundbucketvsaboulinrcca5246' key 'topics/gcs_topic/year=2021/month=12/day=22/gcs_topic+2+0000342853.avro', id 'BlobId{bucket=kafkadockerplaygroundbucketvsaboulinrcca5246, name=topics/gcs_topic/year=2021/month=12/day=22/gcs_topic+2+0000342853.avro, generation=null}' (io.confluent.connect.gcs.storage.GcsOutputStream:223)
# [2021-12-22 10:40:00,205] ERROR [gcs-sink-rcca-5246|task-0] Exception on topic partition gcs_topic-2:  (io.confluent.connect.gcs.GcsSinkTask:177)
# org.apache.kafka.connect.errors.RetriableException: org.apache.kafka.connect.errors.ConnectException: java.io.IOException: Resumable multiPartUpload failed to complete.
# 	at io.confluent.connect.gcs.TopicPartitionWriter.commitFiles(TopicPartitionWriter.java:484)
# 	at io.confluent.connect.gcs.TopicPartitionWriter.commitOnTimeIfNoData(TopicPartitionWriter.java:282)
# 	at io.confluent.connect.gcs.TopicPartitionWriter.write(TopicPartitionWriter.java:173)
# 	at io.confluent.connect.gcs.GcsSinkTask.put(GcsSinkTask.java:175)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:604)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:334)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
# 	at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)
# 	at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)
# 	at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
# 	at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.apache.kafka.connect.errors.ConnectException: java.io.IOException: Resumable multiPartUpload failed to complete.
# 	at io.confluent.connect.gcs.format.avro.AvroRecordWriterProvider$1.commit(AvroRecordWriterProvider.java:88)
# 	at io.confluent.connect.gcs.TopicPartitionWriter.commitFile(TopicPartitionWriter.java:504)
# 	at io.confluent.connect.gcs.TopicPartitionWriter.commitFiles(TopicPartitionWriter.java:480)
# 	... 14 more
# Caused by: java.io.IOException: Resumable multiPartUpload failed to complete.
# 	at io.confluent.connect.gcs.storage.GcsOutputStream$MultipartUpload.completeError(GcsOutputStream.java:224)
# 	at io.confluent.connect.gcs.storage.GcsOutputStream.commit(GcsOutputStream.java:143)
# 	at io.confluent.connect.gcs.format.avro.AvroRecordWriterProvider$1.commit(AvroRecordWriterProvider.java:85)
# 	... 16 more
# Caused by: com.google.cloud.storage.StorageException: Error getting access token for service account: 400 Bad Request
# POST https://oauth2.googleapis.com/token
# {"error":"invalid_grant","error_description":"Invalid JWT Signature."}
# 	at com.google.cloud.storage.spi.v1.HttpStorageRpc.translate(HttpStorageRpc.java:231)
# 	at com.google.cloud.storage.spi.v1.HttpStorageRpc.writeWithResponse(HttpStorageRpc.java:822)
# 	at com.google.cloud.storage.BlobWriteChannel$1.run(BlobWriteChannel.java:69)
# 	at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
# 	at com.google.api.gax.retrying.DirectRetryingExecutor.submit(DirectRetryingExecutor.java:105)
# 	at com.google.cloud.RetryHelper.run(RetryHelper.java:76)
# 	at com.google.cloud.RetryHelper.runWithRetries(RetryHelper.java:50)
# 	at com.google.cloud.storage.BlobWriteChannel.flushBuffer(BlobWriteChannel.java:61)
# 	at com.google.cloud.BaseWriteChannel.close(BaseWriteChannel.java:151)
# 	at io.confluent.connect.gcs.storage.GcsOutputStream$MultipartUpload.complete(GcsOutputStream.java:214)
# 	at io.confluent.connect.gcs.storage.GcsOutputStream.commit(GcsOutputStream.java:141)
# 	... 17 more
# Caused by: java.io.IOException: Error getting access token for service account: 400 Bad Request
# POST https://oauth2.googleapis.com/token
# {"error":"invalid_grant","error_description":"Invalid JWT Signature."}
# 	at com.google.auth.oauth2.ServiceAccountCredentials.refreshAccessToken(ServiceAccountCredentials.java:444)
# 	at com.google.auth.oauth2.OAuth2Credentials.refresh(OAuth2Credentials.java:157)
# 	at com.google.auth.oauth2.OAuth2Credentials.getRequestMetadata(OAuth2Credentials.java:145)
# 	at com.google.auth.oauth2.ServiceAccountCredentials.getRequestMetadata(ServiceAccountCredentials.java:603)
# 	at com.google.auth.http.HttpCredentialsAdapter.initialize(HttpCredentialsAdapter.java:91)
# 	at com.google.cloud.http.HttpTransportOptions$1.initialize(HttpTransportOptions.java:159)
# 	at com.google.cloud.http.CensusHttpModule$CensusHttpRequestInitializer.initialize(CensusHttpModule.java:109)
# 	at com.google.api.client.http.HttpRequestFactory.buildRequest(HttpRequestFactory.java:88)
# 	at com.google.api.client.http.HttpRequestFactory.buildPutRequest(HttpRequestFactory.java:139)
# 	at com.google.cloud.storage.spi.v1.HttpStorageRpc.writeWithResponse(HttpStorageRpc.java:769)
# 	... 26 more
# Caused by: com.google.api.client.http.HttpResponseException: 400 Bad Request
# POST https://oauth2.googleapis.com/token
# {"error":"invalid_grant","error_description":"Invalid JWT Signature."}
# 	at com.google.api.client.http.HttpRequest.execute(HttpRequest.java:1113)
# 	at com.google.auth.oauth2.ServiceAccountCredentials.refreshAccessToken(ServiceAccountCredentials.java:441)
# 	... 35 more
# [2021-12-22 10:40:00,206] INFO [gcs-sink-rcca-5246|task-0] Committing files after waiting for rotateIntervalMs time but less than flush.size records available. (io.confluent.connect.gcs.TopicPartitionWriter:276)
# [2021-12-22 10:40:00,239] ERROR [gcs-sink-rcca-5246|task-0] Failed to complete MultipartUpload for bucket 'kafkadockerplaygroundbucketvsaboulinrcca5246' key 'topics/gcs_topic/year=2021/month=12/day=22/gcs_topic+1+0000342793.avro', id 'BlobId{bucket=kafkadockerplaygroundbucketvsaboulinrcca5246, name=topics/gcs_topic/year=2021/month=12/day=22/gcs_topic+1+0000342793.avro, generation=null}' (io.confluent.connect.gcs.storage.GcsOutputStream:223)
# [2021-12-22 10:40:00,239] ERROR [gcs-sink-rcca-5246|task-0] Exception on topic partition gcs_topic-1:  (io.confluent.connect.gcs.GcsSinkTask:177)
# org.apache.kafka.connect.errors.RetriableException: org.apache.kafka.connect.errors.ConnectException: java.io.IOException: Resumable multiPartUpload failed to complete.
# 	at io.confluent.connect.gcs.TopicPartitionWriter.commitFiles(TopicPartitionWriter.java:484)
# 	at io.confluent.connect.gcs.TopicPartitionWriter.commitOnTimeIfNoData(TopicPartitionWriter.java:282)
# 	at io.confluent.connect.gcs.TopicPartitionWriter.write(TopicPartitionWriter.java:173)
# 	at io.confluent.connect.gcs.GcsSinkTask.put(GcsSinkTask.java:175)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:604)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:334)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
# 	at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)
# 	at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)
# 	at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
# 	at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.apache.kafka.connect.errors.ConnectException: java.io.IOException: Resumable multiPartUpload failed to complete.
# 	at io.confluent.connect.gcs.format.avro.AvroRecordWriterProvider$1.commit(AvroRecordWriterProvider.java:88)
# 	at io.confluent.connect.gcs.TopicPartitionWriter.commitFile(TopicPartitionWriter.java:504)
# 	at io.confluent.connect.gcs.TopicPartitionWriter.commitFiles(TopicPartitionWriter.java:480)
# 	... 14 more
# Caused by: java.io.IOException: Resumable multiPartUpload failed to complete.
# 	at io.confluent.connect.gcs.storage.GcsOutputStream$MultipartUpload.completeError(GcsOutputStream.java:224)
# 	at io.confluent.connect.gcs.storage.GcsOutputStream.commit(GcsOutputStream.java:143)
# 	at io.confluent.connect.gcs.format.avro.AvroRecordWriterProvider$1.commit(AvroRecordWriterProvider.java:85)
# 	... 16 more
# Caused by: com.google.cloud.storage.StorageException: Error getting access token for service account: 400 Bad Request
# POST https://oauth2.googleapis.com/token
# {"error":"invalid_grant","error_description":"Invalid JWT Signature."}
# 	at com.google.cloud.storage.spi.v1.HttpStorageRpc.translate(HttpStorageRpc.java:231)
# 	at com.google.cloud.storage.spi.v1.HttpStorageRpc.writeWithResponse(HttpStorageRpc.java:822)
# 	at com.google.cloud.storage.BlobWriteChannel$1.run(BlobWriteChannel.java:69)
# 	at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
# 	at com.google.api.gax.retrying.DirectRetryingExecutor.submit(DirectRetryingExecutor.java:105)
# 	at com.google.cloud.RetryHelper.run(RetryHelper.java:76)
# 	at com.google.cloud.RetryHelper.runWithRetries(RetryHelper.java:50)
# 	at com.google.cloud.storage.BlobWriteChannel.flushBuffer(BlobWriteChannel.java:61)
# 	at com.google.cloud.BaseWriteChannel.close(BaseWriteChannel.java:151)
# 	at io.confluent.connect.gcs.storage.GcsOutputStream$MultipartUpload.complete(GcsOutputStream.java:214)
# 	at io.confluent.connect.gcs.storage.GcsOutputStream.commit(GcsOutputStream.java:141)
# 	... 17 more
# Caused by: java.io.IOException: Error getting access token for service account: 400 Bad Request
# POST https://oauth2.googleapis.com/token
# {"error":"invalid_grant","error_description":"Invalid JWT Signature."}
# 	at com.google.auth.oauth2.ServiceAccountCredentials.refreshAccessToken(ServiceAccountCredentials.java:444)
# 	at com.google.auth.oauth2.OAuth2Credentials.refresh(OAuth2Credentials.java:157)
# 	at com.google.auth.oauth2.OAuth2Credentials.getRequestMetadata(OAuth2Credentials.java:145)
# 	at com.google.auth.oauth2.ServiceAccountCredentials.getRequestMetadata(ServiceAccountCredentials.java:603)
# 	at com.google.auth.http.HttpCredentialsAdapter.initialize(HttpCredentialsAdapter.java:91)
# 	at com.google.cloud.http.HttpTransportOptions$1.initialize(HttpTransportOptions.java:159)
# 	at com.google.cloud.http.CensusHttpModule$CensusHttpRequestInitializer.initialize(CensusHttpModule.java:109)
# 	at com.google.api.client.http.HttpRequestFactory.buildRequest(HttpRequestFactory.java:88)
# 	at com.google.api.client.http.HttpRequestFactory.buildPutRequest(HttpRequestFactory.java:139)
# 	at com.google.cloud.storage.spi.v1.HttpStorageRpc.writeWithResponse(HttpStorageRpc.java:769)
# 	... 26 more
# Caused by: com.google.api.client.http.HttpResponseException: 400 Bad Request
# POST https://oauth2.googleapis.com/token
# {"error":"invalid_grant","error_description":"Invalid JWT Signature."}
# 	at com.google.api.client.http.HttpRequest.execute(HttpRequest.java:1113)
# 	at com.google.auth.oauth2.ServiceAccountCredentials.refreshAccessToken(ServiceAccountCredentials.java:441)
# 	... 35 more
# [2021-12-22 10:40:00,240] INFO [gcs-sink-rcca-5246|task-0] Committing files after waiting for rotateIntervalMs time but less than flush.size records available. (io.confluent.connect.gcs.TopicPartitionWriter:276)
# [2021-12-22 10:40:00,266] ERROR [gcs-sink-rcca-5246|task-0] Failed to complete MultipartUpload for bucket 'kafkadockerplaygroundbucketvsaboulinrcca5246' key 'topics/gcs_topic/year=2021/month=12/day=22/gcs_topic+5+0000343088.avro', id 'BlobId{bucket=kafkadockerplaygroundbucketvsaboulinrcca5246, name=topics/gcs_topic/year=2021/month=12/day=22/gcs_topic+5+0000343088.avro, generation=null}' (io.confluent.connect.gcs.storage.GcsOutputStream:223)
# [2021-12-22 10:40:00,266] ERROR [gcs-sink-rcca-5246|task-0] Exception on topic partition gcs_topic-5:  (io.confluent.connect.gcs.GcsSinkTask:177)
# org.apache.kafka.connect.errors.RetriableException: org.apache.kafka.connect.errors.ConnectException: java.io.IOException: Resumable multiPartUpload failed to complete.
# 	at io.confluent.connect.gcs.TopicPartitionWriter.commitFiles(TopicPartitionWriter.java:484)
# 	at io.confluent.connect.gcs.TopicPartitionWriter.commitOnTimeIfNoData(TopicPartitionWriter.java:282)
# 	at io.confluent.connect.gcs.TopicPartitionWriter.write(TopicPartitionWriter.java:173)
# 	at io.confluent.connect.gcs.GcsSinkTask.put(GcsSinkTask.java:175)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:604)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:334)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
# 	at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)
# 	at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)
# 	at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
# 	at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.apache.kafka.connect.errors.ConnectException: java.io.IOException: Resumable multiPartUpload failed to complete.
# 	at io.confluent.connect.gcs.format.avro.AvroRecordWriterProvider$1.commit(AvroRecordWriterProvider.java:88)
# 	at io.confluent.connect.gcs.TopicPartitionWriter.commitFile(TopicPartitionWriter.java:504)
# 	at io.confluent.connect.gcs.TopicPartitionWriter.commitFiles(TopicPartitionWriter.java:480)
# 	... 14 more
# Caused by: java.io.IOException: Resumable multiPartUpload failed to complete.
# 	at io.confluent.connect.gcs.storage.GcsOutputStream$MultipartUpload.completeError(GcsOutputStream.java:224)
# 	at io.confluent.connect.gcs.storage.GcsOutputStream.commit(GcsOutputStream.java:143)
# 	at io.confluent.connect.gcs.format.avro.AvroRecordWriterProvider$1.commit(AvroRecordWriterProvider.java:85)
# 	... 16 more
# Caused by: com.google.cloud.storage.StorageException: Error getting access token for service account: 400 Bad Request
# POST https://oauth2.googleapis.com/token
# {"error":"invalid_grant","error_description":"Invalid JWT Signature."}
# 	at com.google.cloud.storage.spi.v1.HttpStorageRpc.translate(HttpStorageRpc.java:231)
# 	at com.google.cloud.storage.spi.v1.HttpStorageRpc.writeWithResponse(HttpStorageRpc.java:822)
# 	at com.google.cloud.storage.BlobWriteChannel$1.run(BlobWriteChannel.java:69)
# 	at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
# 	at com.google.api.gax.retrying.DirectRetryingExecutor.submit(DirectRetryingExecutor.java:105)
# 	at com.google.cloud.RetryHelper.run(RetryHelper.java:76)
# 	at com.google.cloud.RetryHelper.runWithRetries(RetryHelper.java:50)
# 	at com.google.cloud.storage.BlobWriteChannel.flushBuffer(BlobWriteChannel.java:61)
# 	at com.google.cloud.BaseWriteChannel.close(BaseWriteChannel.java:151)
# 	at io.confluent.connect.gcs.storage.GcsOutputStream$MultipartUpload.complete(GcsOutputStream.java:214)
# 	at io.confluent.connect.gcs.storage.GcsOutputStream.commit(GcsOutputStream.java:141)
# 	... 17 more
# Caused by: java.io.IOException: Error getting access token for service account: 400 Bad Request
# POST https://oauth2.googleapis.com/token
# {"error":"invalid_grant","error_description":"Invalid JWT Signature."}
# 	at com.google.auth.oauth2.ServiceAccountCredentials.refreshAccessToken(ServiceAccountCredentials.java:444)
# 	at com.google.auth.oauth2.OAuth2Credentials.refresh(OAuth2Credentials.java:157)
# 	at com.google.auth.oauth2.OAuth2Credentials.getRequestMetadata(OAuth2Credentials.java:145)
# 	at com.google.auth.oauth2.ServiceAccountCredentials.getRequestMetadata(ServiceAccountCredentials.java:603)
# 	at com.google.auth.http.HttpCredentialsAdapter.initialize(HttpCredentialsAdapter.java:91)
# 	at com.google.cloud.http.HttpTransportOptions$1.initialize(HttpTransportOptions.java:159)
# 	at com.google.cloud.http.CensusHttpModule$CensusHttpRequestInitializer.initialize(CensusHttpModule.java:109)
# 	at com.google.api.client.http.HttpRequestFactory.buildRequest(HttpRequestFactory.java:88)
# 	at com.google.api.client.http.HttpRequestFactory.buildPutRequest(HttpRequestFactory.java:139)
# 	at com.google.cloud.storage.spi.v1.HttpStorageRpc.writeWithResponse(HttpStorageRpc.java:769)
# 	... 26 more
# Caused by: com.google.api.client.http.HttpResponseException: 400 Bad Request
# POST https://oauth2.googleapis.com/token
# {"error":"invalid_grant","error_description":"Invalid JWT Signature."}
# 	at com.google.api.client.http.HttpRequest.execute(HttpRequest.java:1113)
# 	at com.google.auth.oauth2.ServiceAccountCredentials.refreshAccessToken(ServiceAccountCredentials.java:441)
# 	... 35 more
# [2021-12-22 10:40:00,268] INFO [gcs-sink-rcca-5246|task-0] [Consumer clientId=connector-consumer-gcs-sink-rcca-5246-0, groupId=connect-gcs-sink-rcca-5246] Seeking to offset 344366 for partition gcs_topic-0 (org.apache.kafka.clients.consumer.KafkaConsumer:1583)
# [2021-12-22 10:40:00,269] INFO [gcs-sink-rcca-5246|task-0] [Consumer clientId=connector-consumer-gcs-sink-rcca-5246-0, groupId=connect-gcs-sink-rcca-5246] Seeking to offset 342480 for partition gcs_topic-4 (org.apache.kafka.clients.consumer.KafkaConsumer:1583)
# [2021-12-22 10:40:00,269] INFO [gcs-sink-rcca-5246|task-0] [Consumer clientId=connector-consumer-gcs-sink-rcca-5246-0, groupId=connect-gcs-sink-rcca-5246] Seeking to offset 343131 for partition gcs_topic-3 (org.apache.kafka.clients.consumer.KafkaConsumer:1583)
# [2021-12-22 10:40:00,270] INFO [gcs-sink-rcca-5246|task-0] [Consumer clientId=connector-consumer-gcs-sink-rcca-5246-0, groupId=connect-gcs-sink-rcca-5246] Seeking to offset 342853 for partition gcs_topic-2 (org.apache.kafka.clients.consumer.KafkaConsumer:1583)
# [2021-12-22 10:40:00,270] INFO [gcs-sink-rcca-5246|task-0] [Consumer clientId=connector-consumer-gcs-sink-rcca-5246-0, groupId=connect-gcs-sink-rcca-5246] Seeking to offset 342793 for partition gcs_topic-1 (org.apache.kafka.clients.consumer.KafkaConsumer:1583)
# [2021-12-22 10:40:00,270] INFO [gcs-sink-rcca-5246|task-0] [Consumer clientId=connector-consumer-gcs-sink-rcca-5246-0, groupId=connect-gcs-sink-rcca-5246] Seeking to offset 343088 for partition gcs_topic-5 (org.apache.kafka.clients.consumer.KafkaConsumer:1583)
# [2021-12-22 10:40:05,107] INFO [gcs-sink-rcca-5246|task-0] Opening record writer for: topics/gcs_topic/year=2021/month=12/day=22/gcs_topic+0+0000344366.avro (io.confluent.connect.gcs.format.avro.AvroRecordWriterProvider:56)
# [2021-12-22 10:40:05,447] ERROR [gcs-sink-rcca-5246|task-0] WorkerSinkTask{id=gcs-sink-rcca-5246-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted. Error: java.io.IOException: Multipart upload failed:  (org.apache.kafka.connect.runtime.WorkerSinkTask:636)
# org.apache.kafka.connect.errors.ConnectException: java.io.IOException: Multipart upload failed: 
# 	at io.confluent.connect.gcs.format.avro.AvroRecordWriterProvider$1.write(AvroRecordWriterProvider.java:75)
# 	at io.confluent.connect.gcs.TopicPartitionWriter.writeRecord(TopicPartitionWriter.java:472)
# 	at io.confluent.connect.gcs.TopicPartitionWriter.checkRotationOrAppend(TopicPartitionWriter.java:254)
# 	at io.confluent.connect.gcs.TopicPartitionWriter.executeState(TopicPartitionWriter.java:199)
# 	at io.confluent.connect.gcs.TopicPartitionWriter.write(TopicPartitionWriter.java:168)
# 	at io.confluent.connect.gcs.GcsSinkTask.put(GcsSinkTask.java:175)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:604)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:334)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
# 	at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)
# 	at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)
# 	at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
# 	at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: java.io.IOException: Multipart upload failed: 
# 	at io.confluent.connect.gcs.storage.GcsOutputStream.uploadPart(GcsOutputStream.java:121)
# 	at io.confluent.connect.gcs.storage.GcsOutputStream.write(GcsOutputStream.java:98)
# 	at org.apache.avro.file.DataFileWriter$BufferedFileOutputStream$PositionFilter.write(DataFileWriter.java:476)
# 	at java.base/java.io.BufferedOutputStream.write(BufferedOutputStream.java:123)
# 	at org.apache.avro.io.BufferedBinaryEncoder$OutputStreamSink.innerWrite(BufferedBinaryEncoder.java:227)
# 	at org.apache.avro.io.BufferedBinaryEncoder.writeFixed(BufferedBinaryEncoder.java:157)
# 	at org.apache.avro.file.DataFileStream$DataBlock.writeBlockTo(DataFileStream.java:393)
# 	at org.apache.avro.file.DataFileWriter.writeBlock(DataFileWriter.java:408)
# 	at org.apache.avro.file.DataFileWriter.writeIfBlockFull(DataFileWriter.java:351)
# 	at org.apache.avro.file.DataFileWriter.append(DataFileWriter.java:320)
# 	at io.confluent.connect.gcs.format.avro.AvroRecordWriterProvider$1.write(AvroRecordWriterProvider.java:73)
# 	... 16 more
# Caused by: java.io.IOException: Error getting access token for service account: 400 Bad Request
# POST https://oauth2.googleapis.com/token
# {"error":"invalid_grant","error_description":"Invalid JWT Signature."}
# 	at com.google.auth.oauth2.ServiceAccountCredentials.refreshAccessToken(ServiceAccountCredentials.java:444)
# 	at com.google.auth.oauth2.OAuth2Credentials.refresh(OAuth2Credentials.java:157)
# 	at com.google.auth.oauth2.OAuth2Credentials.getRequestMetadata(OAuth2Credentials.java:145)
# 	at com.google.auth.oauth2.ServiceAccountCredentials.getRequestMetadata(ServiceAccountCredentials.java:603)
# 	at com.google.auth.http.HttpCredentialsAdapter.initialize(HttpCredentialsAdapter.java:91)
# 	at com.google.cloud.http.HttpTransportOptions$1.initialize(HttpTransportOptions.java:159)
# 	at com.google.cloud.http.CensusHttpModule$CensusHttpRequestInitializer.initialize(CensusHttpModule.java:109)
# 	at com.google.api.client.http.HttpRequestFactory.buildRequest(HttpRequestFactory.java:88)
# 	at com.google.api.client.googleapis.services.AbstractGoogleClientRequest.buildHttpRequest(AbstractGoogleClientRequest.java:422)
# 	at com.google.api.client.googleapis.services.AbstractGoogleClientRequest.buildHttpRequest(AbstractGoogleClientRequest.java:398)
# 	at com.google.cloud.storage.spi.v1.HttpStorageRpc.open(HttpStorageRpc.java:836)
# 	at com.google.cloud.storage.BlobWriteChannel$2.call(BlobWriteChannel.java:94)
# 	at com.google.cloud.storage.BlobWriteChannel$2.call(BlobWriteChannel.java:91)
# 	at com.google.api.gax.retrying.DirectRetryingExecutor.submit(DirectRetryingExecutor.java:105)
# 	at com.google.cloud.RetryHelper.run(RetryHelper.java:76)
# 	at com.google.cloud.RetryHelper.runWithRetries(RetryHelper.java:50)
# 	at com.google.cloud.storage.BlobWriteChannel.open(BlobWriteChannel.java:90)
# 	at com.google.cloud.storage.BlobWriteChannel.<init>(BlobWriteChannel.java:36)
# 	at com.google.cloud.storage.StorageImpl.writer(StorageImpl.java:701)
# 	at com.google.cloud.storage.StorageImpl.writer(StorageImpl.java:691)
# 	at com.google.cloud.storage.StorageImpl.writer(StorageImpl.java:98)
# 	at io.confluent.connect.gcs.storage.GcsOutputStream$MultipartUpload.uploadPart(GcsOutputStream.java:203)
# 	at io.confluent.connect.gcs.storage.GcsOutputStream.uploadPart(GcsOutputStream.java:116)
# 	... 26 more
# Caused by: com.google.api.client.http.HttpResponseException: 400 Bad Request
# POST https://oauth2.googleapis.com/token
# {"error":"invalid_grant","error_description":"Invalid JWT Signature."}
# 	at com.google.api.client.http.HttpRequest.execute(HttpRequest.java:1113)
# 	at com.google.auth.oauth2.ServiceAccountCredentials.refreshAccessToken(ServiceAccountCredentials.java:441)
# 	... 48 more
# [2021-12-22 10:40:05,448] ERROR [gcs-sink-rcca-5246|task-0] WorkerSinkTask{id=gcs-sink-rcca-5246-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:206)
# org.apache.kafka.connect.errors.ConnectException: Exiting WorkerSinkTask due to unrecoverable exception.
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:638)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:334)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
# 	at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)
# 	at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)
# 	at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
# 	at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.apache.kafka.connect.errors.ConnectException: java.io.IOException: Multipart upload failed: 
# 	at io.confluent.connect.gcs.format.avro.AvroRecordWriterProvider$1.write(AvroRecordWriterProvider.java:75)
# 	at io.confluent.connect.gcs.TopicPartitionWriter.writeRecord(TopicPartitionWriter.java:472)
# 	at io.confluent.connect.gcs.TopicPartitionWriter.checkRotationOrAppend(TopicPartitionWriter.java:254)
# 	at io.confluent.connect.gcs.TopicPartitionWriter.executeState(TopicPartitionWriter.java:199)
# 	at io.confluent.connect.gcs.TopicPartitionWriter.write(TopicPartitionWriter.java:168)
# 	at io.confluent.connect.gcs.GcsSinkTask.put(GcsSinkTask.java:175)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:604)
# 	... 10 more
# Caused by: java.io.IOException: Multipart upload failed: 
# 	at io.confluent.connect.gcs.storage.GcsOutputStream.uploadPart(GcsOutputStream.java:121)
# 	at io.confluent.connect.gcs.storage.GcsOutputStream.write(GcsOutputStream.java:98)
# 	at org.apache.avro.file.DataFileWriter$BufferedFileOutputStream$PositionFilter.write(DataFileWriter.java:476)
# 	at java.base/java.io.BufferedOutputStream.write(BufferedOutputStream.java:123)
# 	at org.apache.avro.io.BufferedBinaryEncoder$OutputStreamSink.innerWrite(BufferedBinaryEncoder.java:227)
# 	at org.apache.avro.io.BufferedBinaryEncoder.writeFixed(BufferedBinaryEncoder.java:157)
# 	at org.apache.avro.file.DataFileStream$DataBlock.writeBlockTo(DataFileStream.java:393)
# 	at org.apache.avro.file.DataFileWriter.writeBlock(DataFileWriter.java:408)
# 	at org.apache.avro.file.DataFileWriter.writeIfBlockFull(DataFileWriter.java:351)
# 	at org.apache.avro.file.DataFileWriter.append(DataFileWriter.java:320)
# 	at io.confluent.connect.gcs.format.avro.AvroRecordWriterProvider$1.write(AvroRecordWriterProvider.java:73)
# 	... 16 more
# Caused by: java.io.IOException: Error getting access token for service account: 400 Bad Request
# POST https://oauth2.googleapis.com/token
# {"error":"invalid_grant","error_description":"Invalid JWT Signature."}
# 	at com.google.auth.oauth2.ServiceAccountCredentials.refreshAccessToken(ServiceAccountCredentials.java:444)
# 	at com.google.auth.oauth2.OAuth2Credentials.refresh(OAuth2Credentials.java:157)
# 	at com.google.auth.oauth2.OAuth2Credentials.getRequestMetadata(OAuth2Credentials.java:145)
# 	at com.google.auth.oauth2.ServiceAccountCredentials.getRequestMetadata(ServiceAccountCredentials.java:603)
# 	at com.google.auth.http.HttpCredentialsAdapter.initialize(HttpCredentialsAdapter.java:91)
# 	at com.google.cloud.http.HttpTransportOptions$1.initialize(HttpTransportOptions.java:159)
# 	at com.google.cloud.http.CensusHttpModule$CensusHttpRequestInitializer.initialize(CensusHttpModule.java:109)
# 	at com.google.api.client.http.HttpRequestFactory.buildRequest(HttpRequestFactory.java:88)
# 	at com.google.api.client.googleapis.services.AbstractGoogleClientRequest.buildHttpRequest(AbstractGoogleClientRequest.java:422)
# 	at com.google.api.client.googleapis.services.AbstractGoogleClientRequest.buildHttpRequest(AbstractGoogleClientRequest.java:398)
# 	at com.google.cloud.storage.spi.v1.HttpStorageRpc.open(HttpStorageRpc.java:836)
# 	at com.google.cloud.storage.BlobWriteChannel$2.call(BlobWriteChannel.java:94)
# 	at com.google.cloud.storage.BlobWriteChannel$2.call(BlobWriteChannel.java:91)
# 	at com.google.api.gax.retrying.DirectRetryingExecutor.submit(DirectRetryingExecutor.java:105)
# 	at com.google.cloud.RetryHelper.run(RetryHelper.java:76)
# 	at com.google.cloud.RetryHelper.runWithRetries(RetryHelper.java:50)
# 	at com.google.cloud.storage.BlobWriteChannel.open(BlobWriteChannel.java:90)
# 	at com.google.cloud.storage.BlobWriteChannel.<init>(BlobWriteChannel.java:36)
# 	at com.google.cloud.storage.StorageImpl.writer(StorageImpl.java:701)
# 	at com.google.cloud.storage.StorageImpl.writer(StorageImpl.java:691)
# 	at com.google.cloud.storage.StorageImpl.writer(StorageImpl.java:98)
# 	at io.confluent.connect.gcs.storage.GcsOutputStream$MultipartUpload.uploadPart(GcsOutputStream.java:203)
# 	at io.confluent.connect.gcs.storage.GcsOutputStream.uploadPart(GcsOutputStream.java:116)
# 	... 26 more
# Caused by: com.google.api.client.http.HttpResponseException: 400 Bad Request
# POST https://oauth2.googleapis.com/token
# {"error":"invalid_grant","error_description":"Invalid JWT Signature."}
# 	at com.google.api.client.http.HttpRequest.execute(HttpRequest.java:1113)
# 	at com.google.auth.oauth2.ServiceAccountCredentials.refreshAccessToken(ServiceAccountCredentials.java:441)
# 	... 48 more
# [2021-12-22 10:40:05,458] INFO [gcs-sink-rcca-5246|task-0] [Consumer clientId=connector-consumer-gcs-sink-rcca-5246-0, groupId=connect-gcs-sink-rcca-5246] Revoke previously assigned partitions gcs_topic-0, gcs_topic-4, gcs_topic-3, gcs_topic-2, gcs_topic-1, gcs_topic-5 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:310)
# [2021-12-22 10:40:05,459] INFO [gcs-sink-rcca-5246|task-0] [Consumer clientId=connector-consumer-gcs-sink-rcca-5246-0, groupId=connect-gcs-sink-rcca-5246] Member connector-consumer-gcs-sink-rcca-5246-0-07a6041c-4b54-48ca-bb62-04cbb5b3299c sending LeaveGroup request to coordinator broker:9092 (id: 2147483646 rack: null) due to the consumer is being closed (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1048)
# [2021-12-22 10:40:05,460] INFO [gcs-sink-rcca-5246|task-0] [Consumer clientId=connector-consumer-gcs-sink-rcca-5246-0, groupId=connect-gcs-sink-rcca-5246] Resetting generation due to: consumer pro-actively leaving the group (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:966)
# [2021-12-22 10:40:05,460] INFO [gcs-sink-rcca-5246|task-0] [Consumer clientId=connector-consumer-gcs-sink-rcca-5246-0, groupId=connect-gcs-sink-rcca-5246] Request joining group due to: consumer pro-actively leaving the group (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:988)
# [2021-12-22 10:40:05,504] INFO [gcs-sink-rcca-5246|task-0] Publish thread interrupted for client_id=connector-consumer-gcs-sink-rcca-5246-0 client_type=CONSUMER session= cluster=vONlGTe2Rya3csTpSgRJjg group=connect-gcs-sink-rcca-5246 (io.confluent.monitoring.clients.interceptor.MonitoringInterceptor:285)
# [2021-12-22 10:40:05,506] INFO [gcs-sink-rcca-5246|task-0] Publishing Monitoring Metrics stopped for client_id=connector-consumer-gcs-sink-rcca-5246-0 client_type=CONSUMER session= cluster=vONlGTe2Rya3csTpSgRJjg group=connect-gcs-sink-rcca-5246 (io.confluent.monitoring.clients.interceptor.MonitoringInterceptor:297)
# [2021-12-22 10:40:05,506] INFO [gcs-sink-rcca-5246|task-0] [Producer clientId=confluent.monitoring.interceptor.connector-consumer-gcs-sink-rcca-5246-0] Closing the Kafka producer with timeoutMillis = 9223372036854775807 ms. (org.apache.kafka.clients.producer.KafkaProducer:1208)
# [2021-12-22 10:40:05,513] INFO [gcs-sink-rcca-5246|task-0] Metrics scheduler closed (org.apache.kafka.common.metrics.Metrics:676)
# [2021-12-22 10:40:05,513] INFO [gcs-sink-rcca-5246|task-0] Closing reporter org.apache.kafka.common.metrics.JmxReporter (org.apache.kafka.common.metrics.Metrics:680)
# [2021-12-22 10:40:05,513] INFO [gcs-sink-rcca-5246|task-0] Metrics reporters closed (org.apache.kafka.common.metrics.Metrics:686)
# [2021-12-22 10:40:05,514] INFO [gcs-sink-rcca-5246|task-0] App info kafka.producer for confluent.monitoring.interceptor.connector-consumer-gcs-sink-rcca-5246-0 unregistered (org.apache.kafka.common.utils.AppInfoParser:83)
# [2021-12-22 10:40:05,514] INFO [gcs-sink-rcca-5246|task-0] Closed monitoring interceptor for client_id=connector-consumer-gcs-sink-rcca-5246-0 client_type=CONSUMER session= cluster=vONlGTe2Rya3csTpSgRJjg group=connect-gcs-sink-rcca-5246 (io.confluent.monitoring.clients.interceptor.MonitoringInterceptor:320)
# [2021-12-22 10:40:05,514] INFO [gcs-sink-rcca-5246|task-0] Metrics scheduler closed (org.apache.kafka.common.metrics.Metrics:676)
# [2021-12-22 10:40:05,514] INFO [gcs-sink-rcca-5246|task-0] Closing reporter org.apache.kafka.common.metrics.JmxReporter (org.apache.kafka.common.metrics.Metrics:680)
# [2021-12-22 10:40:05,515] INFO [gcs-sink-rcca-5246|task-0] Metrics reporters closed (org.apache.kafka.common.metrics.Metrics:686)
# [2021-12-22 10:40:05,516] INFO [gcs-sink-rcca-5246|task-0] App info kafka.consumer for connector-consumer-gcs-sink-rcca-5246-0 unregistered (org.apache.kafka.common.utils.AppInfoParser:83)
# [2021-12-22 10:43:02,073] INFO [Worker clientId=connect-1, groupId=connect-cluster] Session key updated (org.apache.kafka.connect.runtime.distributed.DistributedHerder:1721)
