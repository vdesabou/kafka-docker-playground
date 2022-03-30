#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PROJECT=${1:-vincent-de-saboulin-lab}

KEYFILE="${DIR}/keyfile.json"
if [ ! -f ${KEYFILE} ]
then
     logerror "ERROR: the file ${KEYFILE} file is not present!"
     exit 1
fi

DATASET=pg${USER}ds${GITHUB_RUN_NUMBER}${TAG}
DATASET=${DATASET//[-._]/}

log "Doing gsutil authentication"
set +e
docker rm -f gcloud-config
set -e
docker run -i -v ${KEYFILE}:/tmp/keyfile.json --name gcloud-config google/cloud-sdk:latest gcloud auth activate-service-account --project ${PROJECT} --key-file /tmp/keyfile.json

set +e
log "Drop dataset $DATASET, this might fail"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" rm -r -f -d "$DATASET"
set -e

log "Create dataset $PROJECT.$DATASET"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" mk --dataset --description "used by playground" "$DATASET"


for component in producer-repro-99159
do
    set +e
    log "🏗 Building jar for ${component}"
    docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${DIR}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
    if [ $? != 0 ]
    then
        logerror "ERROR: failed to build java component "
        tail -500 /tmp/result.log
        exit 1
    fi
    set -e
done

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-99159-illegalargumentexception.yml"

log "Creating GCP BigQuery Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "com.wepay.kafka.connect.bigquery.BigQuerySinkConnector",
               "tasks.max" : "1",
               "topics" : "customer_avro",
               "sanitizeTopics" : "true",
               "defaultDataset" : "'"$DATASET"'",
               "batch.size": 1,

               "autoCreateTables": "true",

               "bigQueryPartitionDecorator": "false",

               "allowNewBigQueryFields": "true",
               "project" : "'"$PROJECT"'",
               "keyfile" : "/tmp/keyfile.json",
               "transforms": "Cast,filterNaNRecords,Cast2",
               "transforms.Cast.type": "org.apache.kafka.connect.transforms.Cast$Value",
               "transforms.Cast.spec": "price:string",
               "transforms.filterNaNRecords.type": "io.confluent.connect.transforms.Filter$Value",
               "transforms.filterNaNRecords.filter.condition": "$[?(@.price == \"NaN\")]",
               "transforms.filterNaNRecords.filter.type": "exclude",
               "transforms.Cast2.type": "org.apache.kafka.connect.transforms.Cast$Value",
               "transforms.Cast2.spec": "price:float32"
          }' \
     http://localhost:8083/connectors/gcp-bigquery-sink/config | jq .


log "✨ Run the avro java producer which produces to topic customer_avro"
docker exec producer-repro-99159 bash -c "java ${JAVA_OPTS} -jar producer-1.0.0-jar-with-dependencies.jar"

log "Sleeping 125 seconds"
sleep 125

# [2022-03-29 19:19:02,825] ERROR [gcp-bigquery-sink|task-0] WorkerSinkTask{id=gcp-bigquery-sink-0} Commit of offsets threw an unexpected exception for sequence number 1: null (org.apache.kafka.connect.runtime.WorkerSinkTask:270)
# com.wepay.kafka.connect.bigquery.exception.BigQueryConnectException: Some write threads encountered unrecoverable errors: com.wepay.kafka.connect.bigquery.exception.BigQueryConnectException: Failed to write to table
# Caused by: java.lang.IllegalArgumentException, com.wepay.kafka.connect.bigquery.exception.BigQueryConnectException: Failed to write to table
# Caused by: java.lang.IllegalArgumentException; See logs for more detail
#         at com.wepay.kafka.connect.bigquery.write.batch.KCBQThreadPoolExecutor.maybeThrowEncounteredErrors(KCBQThreadPoolExecutor.java:108)
#         at com.wepay.kafka.connect.bigquery.write.batch.KCBQThreadPoolExecutor.awaitCurrentTasks(KCBQThreadPoolExecutor.java:96)
#         at com.wepay.kafka.connect.bigquery.BigQuerySinkTask.flush(BigQuerySinkTask.java:160)
#         at com.wepay.kafka.connect.bigquery.BigQuerySinkTask.preCommit(BigQuerySinkTask.java:176)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.commitOffsets(WorkerSinkTask.java:405)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.closePartitions(WorkerSinkTask.java:673)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.closeAllPartitions(WorkerSinkTask.java:668)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:205)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# [2022-03-29 19:19:02,825] ERROR [gcp-bigquery-sink|task-0] WorkerSinkTask{id=gcp-bigquery-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:206)
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
# Caused by: com.wepay.kafka.connect.bigquery.exception.BigQueryConnectException: Some write threads encountered unrecoverable errors: com.wepay.kafka.connect.bigquery.exception.BigQueryConnectException: Failed to write to table
# Caused by: java.lang.IllegalArgumentException, com.wepay.kafka.connect.bigquery.exception.BigQueryConnectException: Failed to write to table
# Caused by: java.lang.IllegalArgumentException; See logs for more detail
#         at com.wepay.kafka.connect.bigquery.write.batch.KCBQThreadPoolExecutor.maybeThrowEncounteredErrors(KCBQThreadPoolExecutor.java:108)
#         at com.wepay.kafka.connect.bigquery.BigQuerySinkTask.put(BigQuerySinkTask.java:233)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:604)
#         ... 10 more

# with NaN:

# [2022-03-30 10:00:13,261] ERROR WorkerSinkTask{id=gcp-bigquery-sink-0} Task threw an uncaught and unrecoverable exception (org.apache.kafka.connect.runtime.WorkerTask)
# org.apache.kafka.connect.errors.ConnectException: Exiting WorkerSinkTask due to unrecoverable exception.
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:562)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:323)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:225)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:197)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:177)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:227)
#         at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
#         at java.util.concurrent.FutureTask.run(FutureTask.java:266)
#         at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
#         at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
#         at java.lang.Thread.run(Thread.java:748)
# Caused by: com.wepay.kafka.connect.bigquery.exception.BigQueryConnectException: A write thread has failed with an unrecoverable error
# Caused by: Failed to write to table
#         at com.wepay.kafka.connect.bigquery.write.batch.KCBQThreadPoolExecutor.lambda$maybeThrowEncounteredError$0(KCBQThreadPoolExecutor.java:101)
#         at java.util.Optional.ifPresent(Optional.java:159)
#         at com.wepay.kafka.connect.bigquery.write.batch.KCBQThreadPoolExecutor.maybeThrowEncounteredError(KCBQThreadPoolExecutor.java:100)
#         at com.wepay.kafka.connect.bigquery.BigQuerySinkTask.put(BigQuerySinkTask.java:236)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:540)
#         ... 10 more
# Caused by: com.wepay.kafka.connect.bigquery.exception.BigQueryConnectException: Failed to write to table
# Caused by: java.lang.IllegalArgumentException
#         at com.wepay.kafka.connect.bigquery.write.batch.TableWriter.run(TableWriter.java:103)
#         ... 3 more
# Caused by: com.google.cloud.bigquery.BigQueryException: java.lang.IllegalArgumentException
#         at com.google.cloud.bigquery.BigQueryException.translateAndThrow(BigQueryException.java:100)
#         at com.google.cloud.bigquery.BigQueryImpl.insertAll(BigQueryImpl.java:989)
#         at com.wepay.kafka.connect.bigquery.write.row.AdaptiveBigQueryWriter.performWriteRequest(AdaptiveBigQueryWriter.java:93)
#         at com.wepay.kafka.connect.bigquery.write.row.BigQueryWriter.writeRows(BigQueryWriter.java:112)
#         at com.wepay.kafka.connect.bigquery.write.batch.TableWriter.run(TableWriter.java:93)
#         ... 3 more
# Caused by: java.lang.IllegalArgumentException
#         at com.google.common.base.Preconditions.checkArgument(Preconditions.java:128)
#         at com.google.api.client.util.Preconditions.checkArgument(Preconditions.java:35)
#         at com.google.api.client.json.JsonGenerator.serialize(JsonGenerator.java:134)
#         at com.google.api.client.json.JsonGenerator.serialize(JsonGenerator.java:173)
#         at com.google.api.client.json.JsonGenerator.serialize(JsonGenerator.java:173)
#         at com.google.api.client.json.JsonGenerator.serialize(JsonGenerator.java:146)
#         at com.google.api.client.json.JsonGenerator.serialize(JsonGenerator.java:173)
#         at com.google.api.client.json.JsonGenerator.serialize(JsonGenerator.java:105)
#         at com.google.api.client.http.json.JsonHttpContent.writeTo(JsonHttpContent.java:73)
#         at com.google.api.client.http.GZipEncoding.encode(GZipEncoding.java:50)
#         at com.google.api.client.http.HttpEncodingStreamingContent.writeTo(HttpEncodingStreamingContent.java:48)
#         at com.google.api.client.http.javanet.NetHttpRequest$DefaultOutputWriter.write(NetHttpRequest.java:76)
#         at com.google.api.client.http.javanet.NetHttpRequest.writeContentToOutputStream(NetHttpRequest.java:171)
#         at com.google.api.client.http.javanet.NetHttpRequest.execute(NetHttpRequest.java:117)
#         at com.google.api.client.http.javanet.NetHttpRequest.execute(NetHttpRequest.java:84)
#         at com.google.api.client.http.HttpRequest.execute(HttpRequest.java:1012)
#         at com.google.api.client.googleapis.services.AbstractGoogleClientRequest.executeUnparsed(AbstractGoogleClientRequest.java:541)
#         at com.google.api.client.googleapis.services.AbstractGoogleClientRequest.executeUnparsed(AbstractGoogleClientRequest.java:474)
#         at com.google.api.client.googleapis.services.AbstractGoogleClientRequest.execute(AbstractGoogleClientRequest.java:591)
#         at com.google.cloud.bigquery.spi.v2.HttpBigQueryRpc.insertAll(HttpBigQueryRpc.java:487)
#         at com.google.cloud.bigquery.BigQueryImpl$27.call(BigQueryImpl.java:981)
#         at com.google.cloud.bigquery.BigQueryImpl$27.call(BigQueryImpl.java:978)
#         at com.google.api.gax.retrying.DirectRetryingExecutor.submit(DirectRetryingExecutor.java:105)
#         at com.google.cloud.RetryHelper.run(RetryHelper.java:76)
#         at com.google.cloud.RetryHelper.runWithRetries(RetryHelper.java:50)
#         at com.google.cloud.bigquery.BigQueryImpl.insertAll(BigQueryImpl.java:977)
#         ... 6 more

# [2022-03-30 14:12:26,043] ERROR [gcp-bigquery-sink|task-0] WorkerSinkTask{id=gcp-bigquery-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:206)
# org.apache.kafka.connect.errors.ConnectException: Tolerance exceeded in error handler
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndHandleError(RetryWithToleranceOperator.java:220)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execute(RetryWithToleranceOperator.java:142)
#         at org.apache.kafka.connect.runtime.TransformationChain.transformRecord(TransformationChain.java:70)
#         at org.apache.kafka.connect.runtime.TransformationChain.apply(TransformationChain.java:50)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.convertAndTransformRecord(WorkerSinkTask.java:543)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.convertMessages(WorkerSinkTask.java:494)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:333)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: java.lang.NumberFormatException: Character I is neither a decimal digit number, decimal point, nor "e" notation exponential mark.
#         at java.base/java.math.BigDecimal.<init>(BigDecimal.java:518)
#         at java.base/java.math.BigDecimal.<init>(BigDecimal.java:401)
#         at java.base/java.math.BigDecimal.<init>(BigDecimal.java:834)
#         at com.jayway.jsonpath.internal.filter.ValueNodes$NumberNode.<init>(ValueNodes.java:287)
#         at com.jayway.jsonpath.internal.filter.ValueNode.createNumberNode(ValueNode.java:191)
#         at com.jayway.jsonpath.internal.filter.ValueNodes$PathNode.evaluate(ValueNodes.java:698)
#         at com.jayway.jsonpath.internal.filter.RelationalExpressionNode.apply(RelationalExpressionNode.java:37)
#         at com.jayway.jsonpath.internal.filter.FilterCompiler$CompiledFilter.apply(FilterCompiler.java:430)
#         at com.jayway.jsonpath.internal.path.PredicatePathToken.accept(PredicatePathToken.java:77)
#         at com.jayway.jsonpath.internal.path.PredicatePathToken.evaluate(PredicatePathToken.java:47)
#         at com.jayway.jsonpath.internal.path.RootPathToken.evaluate(RootPathToken.java:62)
#         at com.jayway.jsonpath.internal.path.CompiledPath.evaluate(CompiledPath.java:99)
#         at com.jayway.jsonpath.internal.path.CompiledPath.evaluate(CompiledPath.java:107)
#         at com.jayway.jsonpath.JsonPath.read(JsonPath.java:185)
#         at io.confluent.connect.transforms.Filter.shouldDrop(Filter.java:225)
#         at io.confluent.connect.transforms.Filter.apply(Filter.java:161)
#         at org.apache.kafka.connect.runtime.TransformationChain.lambda$transformRecord$0(TransformationChain.java:70)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndRetry(RetryWithToleranceOperator.java:166)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndHandleError(RetryWithToleranceOperator.java:200)
#         ... 15 more

log "Verify data is in GCP BigQuery:"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" query "SELECT * FROM $DATASET.customer_avro;" > /tmp/result.log  2>&1
cat /tmp/result.log
grep "value1" /tmp/result.log

# [2022-03-30 14:27:26,003] INFO [gcp-bigquery-sink|task-0] Attempting to create table `pgec2userds701`.`customer_avro` with schema Schema{fields=[Field{name=count, type=INTEGER, mode=REQUIRED, description=null, policyTags=null}, Field{name=first_name, type=STRING, mode=REQUIRED, description=null, policyTags=null}, Field{name=last_name, type=STRING, mode=REQUIRED, description=null, policyTags=null}, Field{name=address, type=STRING, mode=REQUIRED, description=null, policyTags=null}, Field{name=price, type=FLOAT, mode=REQUIRED, description=null, policyTags=null}]} (com.wepay.kafka.connect.bigquery.SchemaManager:241)

log "Drop dataset $DATASET"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" rm -r -f -d "$DATASET"

docker rm -f gcloud-config