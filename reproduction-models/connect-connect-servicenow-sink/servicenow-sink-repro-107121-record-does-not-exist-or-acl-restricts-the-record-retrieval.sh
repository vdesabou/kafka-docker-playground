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

function wait_for_end_of_hibernation () {
     MAX_WAIT=600
     CUR_WAIT=0
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

if [ ! -z "$CI" ]
then
     # this is github actions
     set +e
     log "Waking up servicenow instance..."
     docker run -e USERNAME="$SERVICENOW_DEVELOPER_USERNAME" -e PASSWORD="$SERVICENOW_DEVELOPER_PASSWORD" ruthless/servicenow-instance-wakeup:latest
     set -e
     wait_for_end_of_hibernation
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-107121-record-does-not-exist-or-acl-restricts-the-record-retrieval.yml"


log "Sending messages to topic test_table"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic test_table --property key.serializer=org.apache.kafka.common.serialization.StringSerializer --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"u_name","type":"string"},
{"name":"u_price", "type": "float"}, {"name":"u_quantity", "type": "int"}]}' --property parse.key=true --property key.separator="|" << EOF
id1|{"u_name": "scissors", "u_price": 2.75, "u_quantity": 3}
id2|{"u_name": "tape", "u_price": 0.99, "u_quantity": 10}
id3|{"u_name": "notebooks", "u_price": 1.1234567, "u_quantity": 5}
EOF

curl --request PUT \
  --url http://localhost:8083/admin/loggers/io.confluent.connect.servicenow \
  --header 'Accept: application/json' \
  --header 'Content-Type: application/json' \
  --data '{
 "level": "TRACE"
}'

curl --request PUT \
  --url http://localhost:8083/admin/loggers/org.apache.http.impl.execchain \
  --header 'Accept: application/json' \
  --header 'Content-Type: application/json' \
  --data '{
 "level": "DEBUG"
}'

log "Creating ServiceNow Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                    "connector.class": "io.confluent.connect.servicenow.ServiceNowSinkConnector",
                    "topics": "test_table",
                    "servicenow.url": "'"$SERVICENOW_URL"'",
                    "tasks.max": "1",
                    "servicenow.table": "u_test_table",
                    "servicenow.user": "admin",
                    "servicenow.password": "'"$SERVICENOW_PASSWORD"'",
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
          }' \
     http://localhost:8083/connectors/servicenow-sink/config | jq .


# repro:

# [2022-05-31 14:27:55,777] ERROR [servicenow-sink|task-0] WorkerSinkTask{id=servicenow-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:207)
# org.apache.kafka.connect.errors.ConnectException: Exiting WorkerSinkTask due to unrecoverable exception.
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:618)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:334)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:200)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:255)
#         at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
#         at java.util.concurrent.FutureTask.run(FutureTask.java:266)
#         at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
#         at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
#         at java.lang.Thread.run(Thread.java:750)
# Caused by: io.confluent.connect.utils.retry.RetryCountExceeded: Failed after 4 attempts to send request to ServiceNow: 404 Not Found
# {"error":{"message":"No Record found","detail":"Record doesn't exist or ACL restricts the record retrieval"},"status":"failure"}
#         at io.confluent.connect.utils.retry.RetryPolicy.callWith(RetryPolicy.java:429)
#         at io.confluent.connect.utils.retry.RetryPolicy.call(RetryPolicy.java:337)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.executeRequest(ServiceNowClientImpl.java:245)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.doRequest(ServiceNowClientImpl.java:241)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.put(ServiceNowClientImpl.java:176)
#         at io.confluent.connect.servicenow.ServiceNowSinkTask.put(ServiceNowSinkTask.java:58)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:584)
#         ... 10 more
# Caused by: com.google.api.client.http.HttpResponseException: 404 Not Found
# {"error":{"message":"No Record found","detail":"Record doesn't exist or ACL restricts the record retrieval"},"status":"failure"}
#         at com.google.api.client.http.HttpRequest.execute(HttpRequest.java:1097)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.lambda$executeRequest$2(ServiceNowClientImpl.java:246)
#         at io.confluent.connect.utils.retry.RetryPolicy.lambda$call$1(RetryPolicy.java:337)
#         at io.confluent.connect.utils.retry.RetryPolicy.callWith(RetryPolicy.java:417)
#         ... 16 more


# [2022-05-31 08:15:32,120] INFO [servicenow-sink|task-0] json is configured (io.confluent.connect.formatter.json.JsonFormatter:35)
# [2022-05-31 08:15:32,120] DEBUG [servicenow-sink|task-0] Launch HTTP request to following URL: /api/now/table/u_test_table (io.confluent.connect.servicenow.rest.ServiceNowClientImpl:175)
# [2022-05-31 08:15:32,121] DEBUG [servicenow-sink|task-0] Calling POST on https://dev71747.service-now.com/api/now/table/u_test_table (io.confluent.connect.servicenow.rest.ServiceNowClientImpl:228)
# May 31, 2022 8:15:32 AM com.google.api.client.http.HttpRequest execute
# CONFIG: -------------- REQUEST  --------------
# POST https://dev71747.service-now.com/api/now/table/u_test_table
# Accept-Encoding: gzip
# Content-Type: application/json
# User-Agent: Google-HTTP-Java-Client/1.32.1 (gzip)
# Content-Type: application/json
# Content-Length: 51

# May 31, 2022 8:15:32 AM com.google.api.client.http.HttpRequest execute
# CONFIG: curl -v --compressed -X POST -H 'Accept-Encoding: gzip' -H 'Content-Type: application/json' -H 'User-Agent: Google-HTTP-Java-Client/1.32.1 (gzip)' -H 'Content-Type: application/json' -d '@-' -- 'https://dev71747.service-now.com/api/now/table/u_test_table' << $$$
# [2022-05-31 08:15:32,128] DEBUG [servicenow-sink|task-0] Executing request POST /api/now/table/u_test_table HTTP/1.1 (org.apache.http.impl.execchain.MainClientExec:255)
# [2022-05-31 08:15:32,128] DEBUG [servicenow-sink|task-0] Target auth state: UNCHALLENGED (org.apache.http.impl.execchain.MainClientExec:260)
# [2022-05-31 08:15:32,128] DEBUG [servicenow-sink|task-0] Proxy auth state: UNCHALLENGED (org.apache.http.impl.execchain.MainClientExec:266)
# May 31, 2022 8:15:32 AM com.google.api.client.util.LoggingByteArrayOutputStream close
# CONFIG: Total: 51 bytes
# May 31, 2022 8:15:32 AM com.google.api.client.util.LoggingByteArrayOutputStream close
# CONFIG: {"u_name":"scissors","u_price":2.75,"u_quantity":3}
# [2022-05-31 08:15:32,319] DEBUG [servicenow-sink|task-0] Connection discarded (org.apache.http.impl.execchain.MainClientExec:129)
# May 31, 2022 8:15:32 AM com.google.api.client.http.HttpRequest execute
# CONFIG: -------------- REQUEST  --------------
# POST https://dev71747.service-now.com/api/now/table/u_test_table
# Accept-Encoding: gzip
# Content-Type: application/json
# User-Agent: Google-HTTP-Java-Client/1.32.1 (gzip)
# Content-Type: application/json
# Content-Length: 51

# May 31, 2022 8:15:32 AM com.google.api.client.http.HttpRequest execute
# CONFIG: curl -v --compressed -X POST -H 'Accept-Encoding: gzip' -H 'Content-Type: application/json' -H 'User-Agent: Google-HTTP-Java-Client/1.32.1 (gzip)' -H 'Content-Type: application/json' -d '@-' -- 'https://dev71747.service-now.com/api/now/table/u_test_table' << $$$
# [2022-05-31 08:15:32,326] DEBUG [servicenow-sink|task-0] Opening connection {s}->https://dev71747.service-now.com:443 (org.apache.http.impl.execchain.MainClientExec:234)
# [2022-05-31 08:15:32,984] DEBUG [servicenow-sink|task-0] Executing request POST /api/now/table/u_test_table HTTP/1.1 (org.apache.http.impl.execchain.MainClientExec:255)
# [2022-05-31 08:15:32,984] DEBUG [servicenow-sink|task-0] Target auth state: UNCHALLENGED (org.apache.http.impl.execchain.MainClientExec:260)
# [2022-05-31 08:15:32,984] DEBUG [servicenow-sink|task-0] Proxy auth state: UNCHALLENGED (org.apache.http.impl.execchain.MainClientExec:266)
# May 31, 2022 8:15:32 AM com.google.api.client.util.LoggingByteArrayOutputStream close
# CONFIG: Total: 51 bytes
# May 31, 2022 8:15:32 AM com.google.api.client.util.LoggingByteArrayOutputStream close
# CONFIG: {"u_name":"scissors","u_price":2.75,"u_quantity":3}
# May 31, 2022 8:15:33 AM com.google.api.client.http.HttpRequest execute
# CONFIG: -------------- REQUEST  --------------
# POST https://dev71747.service-now.com/api/now/table/u_test_table
# Accept-Encoding: gzip
# Content-Type: application/json
# User-Agent: Google-HTTP-Java-Client/1.32.1 (gzip)
# Content-Type: application/json
# Content-Length: 51

# May 31, 2022 8:15:33 AM com.google.api.client.http.HttpRequest execute
# CONFIG: curl -v --compressed -X POST -H 'Accept-Encoding: gzip' -H 'Content-Type: application/json' -H 'User-Agent: Google-HTTP-Java-Client/1.32.1 (gzip)' -H 'Content-Type: application/json' -d '@-' -- 'https://dev71747.service-now.com/api/now/table/u_test_table' << $$$
# [2022-05-31 08:15:33,156] DEBUG [servicenow-sink|task-0] Connection discarded (org.apache.http.impl.execchain.MainClientExec:129)
# [2022-05-31 08:15:33,158] DEBUG [servicenow-sink|task-0] Opening connection {s}->https://dev71747.service-now.com:443 (org.apache.http.impl.execchain.MainClientExec:234)
# [2022-05-31 08:15:33,788] DEBUG [servicenow-sink|task-0] Executing request POST /api/now/table/u_test_table HTTP/1.1 (org.apache.http.impl.execchain.MainClientExec:255)
# [2022-05-31 08:15:33,788] DEBUG [servicenow-sink|task-0] Target auth state: UNCHALLENGED (org.apache.http.impl.execchain.MainClientExec:260)
# [2022-05-31 08:15:33,788] DEBUG [servicenow-sink|task-0] Proxy auth state: UNCHALLENGED (org.apache.http.impl.execchain.MainClientExec:266)
# May 31, 2022 8:15:33 AM com.google.api.client.util.LoggingByteArrayOutputStream close
# CONFIG: Total: 51 bytes
# May 31, 2022 8:15:33 AM com.google.api.client.util.LoggingByteArrayOutputStream close
# CONFIG: {"u_name":"scissors","u_price":2.75,"u_quantity":3}
# [2022-05-31 08:15:33,961] DEBUG [servicenow-sink|task-0] Connection discarded (org.apache.http.impl.execchain.MainClientExec:129)
# May 31, 2022 8:15:33 AM com.google.api.client.http.HttpRequest execute
# CONFIG: -------------- REQUEST  --------------
# POST https://dev71747.service-now.com/api/now/table/u_test_table
# Accept-Encoding: gzip
# Content-Type: application/json
# User-Agent: Google-HTTP-Java-Client/1.32.1 (gzip)
# Content-Type: application/json
# Content-Length: 51

# May 31, 2022 8:15:33 AM com.google.api.client.http.HttpRequest execute
# CONFIG: curl -v --compressed -X POST -H 'Accept-Encoding: gzip' -H 'Content-Type: application/json' -H 'User-Agent: Google-HTTP-Java-Client/1.32.1 (gzip)' -H 'Content-Type: application/json' -d '@-' -- 'https://dev71747.service-now.com/api/now/table/u_test_table' << $$$
# [2022-05-31 08:15:33,964] DEBUG [servicenow-sink|task-0] Opening connection {s}->https://dev71747.service-now.com:443 (org.apache.http.impl.execchain.MainClientExec:234)
# [2022-05-31 08:15:34,592] DEBUG [servicenow-sink|task-0] Executing request POST /api/now/table/u_test_table HTTP/1.1 (org.apache.http.impl.execchain.MainClientExec:255)
# [2022-05-31 08:15:34,592] DEBUG [servicenow-sink|task-0] Target auth state: UNCHALLENGED (org.apache.http.impl.execchain.MainClientExec:260)
# [2022-05-31 08:15:34,592] DEBUG [servicenow-sink|task-0] Proxy auth state: UNCHALLENGED (org.apache.http.impl.execchain.MainClientExec:266)
# May 31, 2022 8:15:34 AM com.google.api.client.util.LoggingByteArrayOutputStream close
# CONFIG: Total: 51 bytes
# May 31, 2022 8:15:34 AM com.google.api.client.util.LoggingByteArrayOutputStream close
# CONFIG: {"u_name":"scissors","u_price":2.75,"u_quantity":3}
# [2022-05-31 08:15:34,759] DEBUG [servicenow-sink|task-0] Connection discarded (org.apache.http.impl.execchain.MainClientExec:129)
# [2022-05-31 08:15:34,761] ERROR [servicenow-sink|task-0] WorkerSinkTask{id=servicenow-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted. Error: Failed after 4 attempts to send request to ServiceNow: null (org.apache.kafka.connect.runtime.WorkerSinkTask:616)
# io.confluent.connect.utils.retry.RetryCountExceeded: Failed after 4 attempts to send request to ServiceNow: null
#         at io.confluent.connect.utils.retry.RetryPolicy.callWith(RetryPolicy.java:429)
#         at io.confluent.connect.utils.retry.RetryPolicy.call(RetryPolicy.java:337)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.executeRequest(ServiceNowClientImpl.java:245)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.doRequest(ServiceNowClientImpl.java:241)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.put(ServiceNowClientImpl.java:176)
#         at io.confluent.connect.servicenow.ServiceNowSinkTask.put(ServiceNowSinkTask.java:58)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:584)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:334)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:200)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:255)
#         at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
#         at java.util.concurrent.FutureTask.run(FutureTask.java:266)
#         at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
#         at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
#         at java.lang.Thread.run(Thread.java:750)
# Caused by: org.apache.http.client.ClientProtocolException
#         at org.apache.http.impl.client.InternalHttpClient.doExecute(InternalHttpClient.java:187)
#         at org.apache.http.impl.client.CloseableHttpClient.execute(CloseableHttpClient.java:83)
#         at org.apache.http.impl.client.CloseableHttpClient.execute(CloseableHttpClient.java:108)
#         at org.apache.http.impl.client.CloseableHttpClient.execute(CloseableHttpClient.java:56)
#         at com.google.api.client.http.apache.v2.ApacheHttpRequest.execute(ApacheHttpRequest.java:71)
#         at com.google.api.client.http.HttpRequest.execute(HttpRequest.java:996)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.lambda$executeRequest$2(ServiceNowClientImpl.java:246)
#         at io.confluent.connect.utils.retry.RetryPolicy.lambda$call$1(RetryPolicy.java:337)
#         at io.confluent.connect.utils.retry.RetryPolicy.callWith(RetryPolicy.java:417)
#         ... 16 more
# Caused by: org.apache.http.client.NonRepeatableRequestException: Cannot retry request with a non-repeatable request entity.
#         at org.apache.http.impl.execchain.MainClientExec.execute(MainClientExec.java:225)
#         at org.apache.http.impl.execchain.ProtocolExec.execute(ProtocolExec.java:186)
#         at org.apache.http.impl.execchain.RetryExec.execute(RetryExec.java:89)
#         at org.apache.http.impl.execchain.RedirectExec.execute(RedirectExec.java:110)
#         at org.apache.http.impl.client.InternalHttpClient.doExecute(InternalHttpClient.java:185)
#         ... 24 more
# [2022-05-31 08:15:34,763] ERROR [servicenow-sink|task-0] WorkerSinkTask{id=servicenow-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:207)
# org.apache.kafka.connect.errors.ConnectException: Exiting WorkerSinkTask due to unrecoverable exception.
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:618)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:334)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:200)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:255)
#         at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
#         at java.util.concurrent.FutureTask.run(FutureTask.java:266)
#         at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
#         at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
#         at java.lang.Thread.run(Thread.java:750)
# Caused by: io.confluent.connect.utils.retry.RetryCountExceeded: Failed after 4 attempts to send request to ServiceNow: null
#         at io.confluent.connect.utils.retry.RetryPolicy.callWith(RetryPolicy.java:429)
#         at io.confluent.connect.utils.retry.RetryPolicy.call(RetryPolicy.java:337)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.executeRequest(ServiceNowClientImpl.java:245)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.doRequest(ServiceNowClientImpl.java:241)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.put(ServiceNowClientImpl.java:176)
#         at io.confluent.connect.servicenow.ServiceNowSinkTask.put(ServiceNowSinkTask.java:58)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:584)
#         ... 10 more
# Caused by: org.apache.http.client.ClientProtocolException
#         at org.apache.http.impl.client.InternalHttpClient.doExecute(InternalHttpClient.java:187)
#         at org.apache.http.impl.client.CloseableHttpClient.execute(CloseableHttpClient.java:83)
#         at org.apache.http.impl.client.CloseableHttpClient.execute(CloseableHttpClient.java:108)
#         at org.apache.http.impl.client.CloseableHttpClient.execute(CloseableHttpClient.java:56)
#         at com.google.api.client.http.apache.v2.ApacheHttpRequest.execute(ApacheHttpRequest.java:71)
#         at com.google.api.client.http.HttpRequest.execute(HttpRequest.java:996)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.lambda$executeRequest$2(ServiceNowClientImpl.java:246)
#         at io.confluent.connect.utils.retry.RetryPolicy.lambda$call$1(RetryPolicy.java:337)
#         at io.confluent.connect.utils.retry.RetryPolicy.callWith(RetryPolicy.java:417)
#         ... 16 more
# Caused by: org.apache.http.client.NonRepeatableRequestException: Cannot retry request with a non-repeatable request entity.
#         at org.apache.http.impl.execchain.MainClientExec.execute(MainClientExec.java:225)
#         at org.apache.http.impl.execchain.ProtocolExec.execute(ProtocolExec.java:186)
#         at org.apache.http.impl.execchain.RetryExec.execute(RetryExec.java:89)
#         at org.apache.http.impl.execchain.RedirectExec.execute(RedirectExec.java:110)
#         at org.apache.http.impl.client.InternalHttpClient.doExecute(InternalHttpClient.java:185)
#         ... 24 more
# [2022-05-31 08:15:34,764] DEBUG [servicenow-sink|task-0] Stopping ServiceNow Sink Task... (io.confluent.connect.servicenow.ServiceNowSinkTask:115)
# [2022-05-31 08:15:34,764] INFO [servicenow-sink|task-0] [Producer clientId=producer-6] Closing the Kafka producer with timeoutMillis = 9223372036854775807 ms. (org.apache.kafka.clients.producer.KafkaProducer:1228)
# [2022-05-31 08:15:34,768] INFO [servicenow-sink|task-0] Metrics scheduler closed (org.apache.kafka.common.metrics.Metrics:676)
# [2022-05-31 08:15:34,768] INFO [servicenow-sink|task-0] Closing reporter org.apache.kafka.common.metrics.JmxReporter (org.apache.kafka.common.metrics.Metrics:680)
# [2022-05-31 08:15:34,768] INFO [servicenow-sink|task-0] Metrics reporters closed (org.apache.kafka.common.metrics.Metrics:686)
# [2022-05-31 08:15:34,768] INFO [servicenow-sink|task-0] App info kafka.producer for producer-6 unregistered (org.apache.kafka.common.utils.AppInfoParser:83)
# [2022-05-31 08:15:34,769] INFO [servicenow-sink|task-0] [Consumer clientId=connector-consumer-servicenow-sink-0, groupId=connect-servicenow-sink] Revoke previously assigned partitions test_table-0 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:310)
# [2022-05-31 08:15:34,769] INFO [servicenow-sink|task-0] [Consumer clientId=connector-consumer-servicenow-sink-0, groupId=connect-servicenow-sink] Member connector-consumer-servicenow-sink-0-659936d7-b557-493a-8f5a-29a9b30011c2 sending LeaveGroup request to coordinator broker:9092 (id: 2147483646 rack: null) due to the consumer is being closed (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1060)
# [2022-05-31 08:15:34,769] INFO [servicenow-sink|task-0] [Consumer clientId=connector-consumer-servicenow-sink-0, groupId=connect-servicenow-sink] Resetting generation due to: consumer pro-actively leaving the group (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:972)
# [2022-05-31 08:15:34,769] INFO [servicenow-sink|task-0] [Consumer clientId=connector-consumer-servicenow-sink-0, groupId=connect-servicenow-sink] Request joining group due to: consumer pro-actively leaving the group (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1000)
# [2022-05-31 08:15:34,771] INFO [servicenow-sink|task-0] Publish thread interrupted for client_id=connector-consumer-servicenow-sink-0 client_type=CONSUMER session= cluster=IM64Ip1_Q2aUaXXqoYjsWg group=connect-servicenow-sink (io.confluent.monitoring.clients.interceptor.MonitoringInterceptor:285)
# [2022-05-31 08:15:34,772] INFO [servicenow-sink|task-0] Publishing Monitoring Metrics stopped for client_id=connector-consumer-servicenow-sink-0 client_type=CONSUMER session= cluster=IM64Ip1_Q2aUaXXqoYjsWg group=connect-servicenow-sink (io.confluent.monitoring.clients.interceptor.MonitoringInterceptor:297)
# [2022-05-31 08:15:34,773] INFO [servicenow-sink|task-0] [Producer clientId=confluent.monitoring.interceptor.connector-consumer-servicenow-sink-0] Closing the Kafka producer with timeoutMillis = 9223372036854775807 ms. (org.apache.kafka.clients.producer.KafkaProducer:1228)
# [2022-05-31 08:15:34,779] INFO [servicenow-sink|task-0] Metrics scheduler closed (org.apache.kafka.common.metrics.Metrics:676)
# [2022-05-31 08:15:34,779] INFO [servicenow-sink|task-0] Closing reporter org.apache.kafka.common.metrics.JmxReporter (org.apache.kafka.common.metrics.Metrics:680)
# [2022-05-31 08:15:34,779] INFO [servicenow-sink|task-0] Metrics reporters closed (org.apache.kafka.common.metrics.Metrics:686)
# [2022-05-31 08:15:34,779] INFO [servicenow-sink|task-0] App info kafka.producer for confluent.monitoring.interceptor.connector-consumer-servicenow-sink-0 unregistered (org.apache.kafka.common.utils.AppInfoParser:83)
# [2022-05-31 08:15:34,779] INFO [servicenow-sink|task-0] Closed monitoring interceptor for client_id=connector-consumer-servicenow-sink-0 client_type=CONSUMER session= cluster=IM64Ip1_Q2aUaXXqoYjsWg group=connect-servicenow-sink (io.confluent.monitoring.clients.interceptor.MonitoringInterceptor:320)
# [2022-05-31 08:15:34,779] INFO [servicenow-sink|task-0] Metrics scheduler closed (org.apache.kafka.common.metrics.Metrics:676)
# [2022-05-31 08:15:34,779] INFO [servicenow-sink|task-0] Closing reporter org.apache.kafka.common.metrics.JmxReporter (org.apache.kafka.common.metrics.Metrics:680)
# [2022-05-31 08:15:34,779] INFO [servicenow-sink|task-0] Metrics reporters closed (org.apache.kafka.common.metrics.Metrics:686)
# [2022-05-31 08:15:34,781] INFO [servicenow-sink|task-0] App info kafka.consumer for connector-consumer-servicenow-sink-0 unregistered (org.apache.kafka.common.utils.AppInfoParser:83)
# [2022-05-31 08:16:11,272] INFO [AdminClient clientId=adminclient-8] Node -1 disconnected. (org.apache.kafka.clients.NetworkClient:1047)
# [2022-05-31 08:16:12,769] INFO [Worker clientId=connect-1, groupId=connect-cluster] Resetting the last seen epoch of partition test_table-0 to 0 since the associated topicId changed from null to w_eJXMNqSgelD-u3aXy6tA (org.apache.kafka.clients.Metadata:402)
# [2022-05-31 08:16:12,769] INFO [Worker clientId=connect-1, groupId=connect-cluster] Resetting the last seen epoch of partition test-error-0 to 0 since the associated topicId changed from null to UJ24w6OVR-2OD4S8Kve8Tw (org.apache.kafka.clients.Metadata:402)
# [2022-05-31 08:16:12,770] INFO [Worker clientId=connect-1, groupId=connect-cluster] Resetting the last seen epoch of partition _confluent-telemetry-metrics-0 to 0 since the associated topicId changed from null to ylt485PGTgyoVyL6y52Erw (org.apache.kafka.clients.Metadata:402)
# [2022-05-31 08:16:12,770] INFO [Worker clientId=connect-1, groupId=connect-cluster] Resetting the last seen epoch of partition _confluent-telemetry-metrics-5 to 0 since the associated topicId changed from null to ylt485PGTgyoVyL6y52Erw (org.apache.kafka.clients.Metadata:402)
# [2022-05-31 08:16:12,770] INFO [Worker clientId=connect-1, groupId=connect-cluster] Resetting the last seen epoch of partition _confluent-telemetry-metrics-10 to 0 since the associated topicId changed from null to ylt485PGTgyoVyL6y52Erw (org.apache.kafka.clients.Metadata:402)
# [2022-05-31 08:16:12,770] INFO [Worker clientId=connect-1, groupId=connect-cluster] Resetting the last seen epoch of partition _confluent-telemetry-metrics-8 to 0 since the associated topicId changed from null to ylt485PGTgyoVyL6y52Erw (org.apache.kafka.clients.Metadata:402)
# [2022-05-31 08:16:12,770] INFO [Worker clientId=connect-1, groupId=connect-cluster] Resetting the last seen epoch of partition _confluent-telemetry-metrics-2 to 0 since the associated topicId changed from null to ylt485PGTgyoVyL6y52Erw (org.apache.kafka.clients.Metadata:402)
# [2022-05-31 08:16:12,770] INFO [Worker clientId=connect-1, groupId=connect-cluster] Resetting the last seen epoch of partition _confluent-telemetry-metrics-9 to 0 since the associated topicId changed from null to ylt485PGTgyoVyL6y52Erw (org.apache.kafka.clients.Metadata:402)
# [2022-05-31 08:16:12,770] INFO [Worker clientId=connect-1, groupId=connect-cluster] Resetting the last seen epoch of partition _confluent-telemetry-metrics-11 to 0 since the associated topicId changed from null to ylt485PGTgyoVyL6y52Erw (org.apache.kafka.clients.Metadata:402)
# [2022-05-31 08:16:12,770] INFO [Worker clientId=connect-1, groupId=connect-cluster] Resetting the last seen epoch of partition _confluent-telemetry-metrics-4 to 0 since the associated topicId changed from null to ylt485PGTgyoVyL6y52Erw (org.apache.kafka.clients.Metadata:402)
# [2022-05-31 08:16:12,770] INFO [Worker clientId=connect-1, groupId=connect-cluster] Resetting the last seen epoch of partition _confluent-telemetry-metrics-1 to 0 since the associated topicId changed from null to ylt485PGTgyoVyL6y52Erw (org.apache.kafka.clients.Metadata:402)
# [2022-05-31 08:16:12,770] INFO [Worker clientId=connect-1, groupId=connect-cluster] Resetting the last seen epoch of partition _confluent-telemetry-metrics-6 to 0 since the associated topicId changed from null to ylt485PGTgyoVyL6y52Erw (org.apache.kafka.clients.Metadata:402)
# [2022-05-31 08:16:12,770] INFO [Worker clientId=connect-1, groupId=connect-cluster] Resetting the last seen epoch of partition _confluent-telemetry-metrics-7 to 0 since the associated topicId changed from null to ylt485PGTgyoVyL6y52Erw (org.apache.kafka.clients.Metadata:402)
# [2022-05-31 08:16:12,770] INFO [Worker clientId=connect-1, groupId=connect-cluster] Resetting the last seen epoch of partition _confluent-telemetry-metrics-3 to 0 since the associated topicId changed from null to ylt485PGTgyoVyL6y52Erw (org.apache.kafka.clients.Metadata:402)
# [2022-05-31 08:16:12,770] INFO [Worker clientId=connect-1, groupId=connect-cluster] Resetting the last seen epoch of partition test-result-0 to 0 since the associated topicId changed from null to 4UTCI_0tSymV7fuKEggo9Q (org.apache.kafka.clients.Metadata:402)
# [2022-05-31 08:16:12,770] INFO [Worker clientId=connect-1, groupId=connect-cluster] Resetting the last seen epoch of partition _confluent_balancer_api_state-0 to 0 since the associated topicId changed from null to CjCVbvOOTt2MQFR6N9xozw (org.apache.kafka.clients.Metadata:402)

# sleep 15

# log "Confirm that the messages were delivered to the ServiceNow table"
# docker exec -e SERVICENOW_URL="$SERVICENOW_URL" -e SERVICENOW_PASSWORD="$SERVICENOW_PASSWORD" connect \
#    curl -X GET \
#     "${SERVICENOW_URL}/api/now/table/u_test_table" \
#     --user admin:"$SERVICENOW_PASSWORD" \
#     -H 'Accept: application/json' \
#     -H 'Content-Type: application/json' \
#     -H 'cache-control: no-cache' | jq . > /tmp/result.log  2>&1
# cat /tmp/result.log
# grep "u_name" /tmp/result.log | grep "notebooks"

exit 0

docker exec -d --privileged --user root connect bash -c 'tcpdump -w /tmp/tcpdump.pcap -i eth0 -s 0 port 443'
