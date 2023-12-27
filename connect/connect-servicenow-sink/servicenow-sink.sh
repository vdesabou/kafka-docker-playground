#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh



function wait_for_end_of_hibernation () {
     MAX_WAIT=600
     CUR_WAIT=0
     set +e
     log "⌛ Waiting up to $MAX_WAIT seconds for end of hibernation to happen (it can take several minutes)"
     curl -X POST "${SERVICENOW_URL}/api/now/table/incident" --user admin:"$SERVICENOW_PASSWORD" -H 'Accept: application/json' -H 'Content-Type: application/json' -H 'cache-control: no-cache' -d '{"short_description": "This is test"}' > /tmp/out.txt 2>&1
     while [[ $(cat /tmp/out.txt) =~ "Sign in to the site to wake your instance" ]]
     do
          sleep 10
          curl -X POST "${SERVICENOW_URL}/api/now/table/incident" --user admin:"$SERVICENOW_PASSWORD" -H 'Accept: application/json' -H 'Content-Type: application/json' -H 'cache-control: no-cache' -d '{"short_description": "This is test"}' > /tmp/out.txt 2>&1
          CUR_WAIT=$(( CUR_WAIT+10 ))
          if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
               echo -e "\nERROR: The logs still show 'Sign in to the site to wake your instance' after $MAX_WAIT seconds.\n"
               exit 1
          fi
     done
     log "The instance is ready !"
     set -e
}

SERVICENOW_URL=${SERVICENOW_URL:-$1}
SERVICENOW_PASSWORD=${SERVICENOW_PASSWORD:-$2}

if [ -z "$SERVICENOW_URL" ]
then
     logerror "SERVICENOW_URL is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [[ "$SERVICENOW_URL" != */ ]]
then
    logerror "SERVICENOW_URL does not end with "/" Example: https://dev12345.service-now.com/ "
    exit 1
fi

if [ -z "$SERVICENOW_PASSWORD" ]
then
     logerror "SERVICENOW_PASSWORD is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ ! -z "$GITHUB_RUN_NUMBER" ]
then
     # this is github actions
     set +e
     log "Waking up servicenow instance..."
     docker run -e USERNAME="$SERVICENOW_DEVELOPER_USERNAME" -e PASSWORD="$SERVICENOW_DEVELOPER_PASSWORD" vdesabou/servicenowinstancewakeup:latest
     set -e
     wait_for_end_of_hibernation
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Sending messages to topic test_table"
playground topic produce -t test_table --nb-messages 3 << 'EOF'
{
  "fields": [
    {
      "name": "u_name",
      "type": "string"
    },
    {
      "name": "u_price",
      "type": "float"
    },
    {
      "name": "u_quantity",
      "type": "int"
    }
  ],
  "name": "myrecord",
  "type": "record"
}
EOF

log "Creating ServiceNow Sink connector"
playground connector create-or-update --connector servicenow-sink  << EOF
{
     "connector.class": "io.confluent.connect.servicenow.ServiceNowSinkConnector",
     "topics": "test_table",
     "servicenow.url": "$SERVICENOW_URL",
     "tasks.max": "1",
     "servicenow.table": "u_test_table",
     "servicenow.user": "admin",
     "servicenow.password": "$SERVICENOW_PASSWORD",
     "key.converter": "io.confluent.connect.avro.AvroConverter",
     "key.converter.schema.registry.url": "http://schema-registry:8081",
     "value.converter": "io.confluent.connect.avro.AvroConverter",
     "value.converter.schema.registry.url": "http://schema-registry:8081",
     "reporter.bootstrap.servers": "broker:9092",
     "reporter.error.topic.name": "test-error",
     "reporter.error.topic.replication.factor": 1,
     "reporter.error.topic.key.format": "string",
     "reporter.error.topic.value.format": "string",
     "reporter.result.topic.name": "test-result",
     "reporter.result.topic.key.format": "string",
     "reporter.result.topic.value.format": "string",
     "reporter.result.topic.replication.factor": 1,
     "confluent.license": "",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor": "1"
}
EOF


# [2023-12-27 16:48:03,273] ERROR [servicenow-sink|task-0] WorkerSinkTask{id=servicenow-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted. Error: Failed on attempt 1 of 4 to send request to ServiceNow: class com.google.api.client.util.LoggingStreamingContent cannot be cast to class com.google.api.client.http.HttpContent (com.google.api.client.util.LoggingStreamingContent and com.google.api.client.http.HttpContent are in unnamed module of loader org.apache.kafka.connect.runtime.isolation.PluginClassLoader @31e3250d) (org.apache.kafka.connect.runtime.WorkerSinkTask:626)
# org.apache.kafka.connect.errors.ConnectException: Failed on attempt 1 of 4 to send request to ServiceNow: class com.google.api.client.util.LoggingStreamingContent cannot be cast to class com.google.api.client.http.HttpContent (com.google.api.client.util.LoggingStreamingContent and com.google.api.client.http.HttpContent are in unnamed module of loader org.apache.kafka.connect.runtime.isolation.PluginClassLoader @31e3250d)
# 	at io.confluent.connect.utils.retry.RetryPolicy.callWith(RetryPolicy.java:423)
# 	at io.confluent.connect.utils.retry.RetryPolicy.call(RetryPolicy.java:337)
# 	at io.confluent.connect.servicenow.rest.ServiceNowClient.executeRequest(ServiceNowClient.java:260)
# 	at io.confluent.connect.servicenow.rest.ServiceNowClient.doRequest(ServiceNowClient.java:256)
# 	at io.confluent.connect.servicenow.rest.ServiceNowClient.put(ServiceNowClient.java:191)
# 	at io.confluent.connect.servicenow.ServiceNowSinkTask.put(ServiceNowSinkTask.java:58)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:593)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:340)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:238)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:207)
# 	at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:229)
# 	at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:284)
# 	at org.apache.kafka.connect.runtime.isolation.Plugins.lambda$withClassLoader$1(Plugins.java:181)
# 	at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
# 	at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: java.lang.ClassCastException: class com.google.api.client.util.LoggingStreamingContent cannot be cast to class com.google.api.client.http.HttpContent (com.google.api.client.util.LoggingStreamingContent and com.google.api.client.http.HttpContent are in unnamed module of loader org.apache.kafka.connect.runtime.isolation.PluginClassLoader @31e3250d)
# 	at io.confluent.connect.servicenow.rest.RepeatableContentEntity.isRepeatable(RepeatableContentEntity.java:33)
# 	at org.apache.http.impl.execchain.RequestEntityProxy.enhance(RequestEntityProxy.java:47)
# 	at org.apache.http.impl.execchain.MainClientExec.execute(MainClientExec.java:171)
# 	at org.apache.http.impl.execchain.ProtocolExec.execute(ProtocolExec.java:186)
# 	at org.apache.http.impl.execchain.RetryExec.execute(RetryExec.java:89)
# 	at org.apache.http.impl.execchain.RedirectExec.execute(RedirectExec.java:110)
# 	at org.apache.http.impl.client.InternalHttpClient.doExecute(InternalHttpClient.java:185)
# 	at org.apache.http.impl.client.CloseableHttpClient.execute(CloseableHttpClient.java:83)
# 	at org.apache.http.impl.client.CloseableHttpClient.execute(CloseableHttpClient.java:108)
# 	at org.apache.http.impl.client.CloseableHttpClient.execute(CloseableHttpClient.java:56)
# 	at io.confluent.connect.servicenow.rest.RepeatableApacheHttpRequest.execute(RepeatableApacheHttpRequest.java:53)
# 	at com.google.api.client.http.HttpRequest.execute(HttpRequest.java:1012)
# 	at io.confluent.connect.servicenow.rest.ServiceNowClient.lambda$executeRequest$2(ServiceNowClient.java:262)
# 	at io.confluent.connect.utils.retry.RetryPolicy.lambda$call$1(RetryPolicy.java:337)
# 	at io.confluent.connect.utils.retry.RetryPolicy.callWith(RetryPolicy.java:417)
# 	... 17 more


sleep 15

log "Confirm that the messages were delivered to the ServiceNow table"
docker exec -e SERVICENOW_URL="$SERVICENOW_URL" -e SERVICENOW_PASSWORD="$SERVICENOW_PASSWORD" connect \
   curl -X GET \
    "${SERVICENOW_URL}/api/now/table/u_test_table" \
    --user admin:"$SERVICENOW_PASSWORD" \
    -H 'Accept: application/json' \
    -H 'Content-Type: application/json' \
    -H 'cache-control: no-cache' | jq . > /tmp/result.log  2>&1
cat /tmp/result.log
grep "u_name" /tmp/result.log | grep "notebooks"