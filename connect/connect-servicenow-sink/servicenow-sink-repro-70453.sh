#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

function wait_for_end_of_hibernation () {
     MAX_WAIT=1200
     CUR_WAIT=0
     log "Waiting up to $MAX_WAIT seconds for end of hibernation to happen (it can take several minutes)"
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

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-70453.yml"

export HTTP_PROXY=127.0.0.1:8888
export HTTPS_PROXY=127.0.0.1:8888
log "Verify forward proxy is working correctly"
curl --compressed -H 'Accept-Encoding: gzip' -H 'Content-Type: application/json' -H 'User-Agent: Google-HTTP-Java-Client/1.30.0 (gzip)' -v ${SERVICENOW_URL}api/now/table/incident?sysparm_limit=1 -u "admin:$SERVICENOW_PASSWORD" | jq .

docker exec -e SERVICENOW_URL=$SERVICENOW_URL -e SERVICENOW_PASSWORD=$SERVICENOW_PASSWORD connect bash -c "export HTTP_PROXY=nginx_proxy:8888 && export HTTPS_PROXY=nginx_proxy:8888 && curl --compressed -H 'Accept-Encoding: gzip' -H 'User-Agent: Google-HTTP-Java-Client/1.30.0 (gzip)' -v ${SERVICENOW_URL}api/now/table/incident?sysparm_limit=1 -u \"admin:$SERVICENOW_PASSWORD\""

log "Sending messages to topic test_table"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic test_table --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"u_name","type":"string"},
{"name":"u_price", "type": "float"}, {"name":"u_quantity", "type": "int"}]}' << EOF
{"u_name": "scissors", "u_price": 2.75, "u_quantity": 3}
{"u_name": "tape", "u_price": 0.99, "u_quantity": 10}
{"u_name": "notebooks", "u_price": 1.99, "u_quantity": 5}
EOF

log "Creating ServiceNow Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                    "connector.class": "io.confluent.connect.servicenow.ServiceNowSinkConnector",
                    "topics": "test_table",
                    "proxy.url": "nginx_proxy:8888",
                    "servicenow.url": "'"$SERVICENOW_URL"'",
                    "tasks.max": "1",
                    "servicenow.table": "u_test_table",
                    "servicenow.user": "admin",
                    "servicenow.password": "'"$SERVICENOW_PASSWORD"'",
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
          }' \
     http://localhost:8083/connectors/servicenow-sink/config | jq .

sleep 10


log "Confirm that the messages were delivered to the ServiceNow table"
docker exec -e SERVICENOW_URL="$SERVICENOW_URL" -e SERVICENOW_PASSWORD="$SERVICENOW_PASSWORD" connect bash -c "export HTTP_PROXY=nginx_proxy:8888 && export HTTPS_PROXY=nginx_proxy:8888 && \
   curl -X GET \
    "${SERVICENOW_URL}/api/now/table/u_test_table" \
    --user admin:"$SERVICENOW_PASSWORD" \
    -H 'Accept: application/json' \
    -H 'Content-Type: application/json' \
    -H 'cache-control: no-cache'" | jq . > /tmp/result.log  2>&1
cat /tmp/result.log
grep "u_name" /tmp/result.log | grep "notebooks"


log "Restart the proxy"
docker restart nginx_proxy &

sleep 3

log "Sending messages to topic test_table"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic test_table --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"u_name","type":"string"},
{"name":"u_price", "type": "float"}, {"name":"u_quantity", "type": "int"}]}' << EOF
{"u_name": "scissors", "u_price": 2.75, "u_quantity": 3}
{"u_name": "tape", "u_price": 0.99, "u_quantity": 10}
{"u_name": "notebooks", "u_price": 1.99, "u_quantity": 5}
EOF

# CONFIG: -------------- REQUEST  --------------
# POST https://dev71747.service-now.com//api/now/table/u_test_table
# Accept-Encoding: gzip
# Content-Type: application/json
# User-Agent: Google-HTTP-Java-Client/1.32.1 (gzip)
# Content-Type: application/json
# Content-Length: 51

# Sep 07, 2021 4:13:09 PM com.google.api.client.http.HttpRequest execute
# CONFIG: curl -v --compressed -X POST -H 'Accept-Encoding: gzip' -H 'Content-Type: application/json' -H 'User-Agent: Google-HTTP-Java-Client/1.32.1 (gzip)' -H 'Content-Type: application/json' -d '@-' -- 'https://dev71747.service-now.com//api/now/table/u_test_table' << $$$

# Sep 07, 2021 4:13:11 PM com.google.api.client.util.LoggingByteArrayOutputStream close
# CONFIG: Total: 51 bytes
# Sep 07, 2021 4:13:11 PM com.google.api.client.util.LoggingByteArrayOutputStream close
# CONFIG: {"u_name":"scissors","u_price":2.75,"u_quantity":3}
# Sep 07, 2021 4:13:12 PM com.google.api.client.http.HttpRequest execute
# CONFIG: -------------- REQUEST  --------------
# POST https://dev71747.service-now.com//api/now/table/u_test_table
# Accept-Encoding: gzip
# Content-Type: application/json
# User-Agent: Google-HTTP-Java-Client/1.32.1 (gzip)
# Content-Type: application/json
# Content-Length: 51

# Sep 07, 2021 4:13:12 PM com.google.api.client.http.HttpRequest execute
# CONFIG: curl -v --compressed -X POST -H 'Accept-Encoding: gzip' -H 'Content-Type: application/json' -H 'User-Agent: Google-HTTP-Java-Client/1.32.1 (gzip)' -H 'Content-Type: application/json' -d '@-' -- 'https://dev71747.service-now.com//api/now/table/u_test_table' << $$$
# Sep 07, 2021 4:13:13 PM com.google.api.client.util.LoggingByteArrayOutputStream close
# CONFIG: Total: 51 bytes
# Sep 07, 2021 4:13:13 PM com.google.api.client.util.LoggingByteArrayOutputStream close
# CONFIG: {"u_name":"scissors","u_price":2.75,"u_quantity":3}
# Sep 07, 2021 4:13:14 PM com.google.api.client.http.HttpRequest execute
# CONFIG: -------------- REQUEST  --------------
# POST https://dev71747.service-now.com//api/now/table/u_test_table
# Accept-Encoding: gzip
# Content-Type: application/json
# User-Agent: Google-HTTP-Java-Client/1.32.1 (gzip)
# Content-Type: application/json
# Content-Length: 51

# Sep 07, 2021 4:13:14 PM com.google.api.client.http.HttpRequest execute
# CONFIG: curl -v --compressed -X POST -H 'Accept-Encoding: gzip' -H 'Content-Type: application/json' -H 'User-Agent: Google-HTTP-Java-Client/1.32.1 (gzip)' -H 'Content-Type: application/json' -d '@-' -- 'https://dev71747.service-now.com//api/now/table/u_test_table' << $$$
# Sep 07, 2021 4:13:16 PM com.google.api.client.util.LoggingByteArrayOutputStream close
# CONFIG: Total: 51 bytes
# Sep 07, 2021 4:13:16 PM com.google.api.client.util.LoggingByteArrayOutputStream close
# CONFIG: {"u_name":"scissors","u_price":2.75,"u_quantity":3}
# Sep 07, 2021 4:13:16 PM com.google.api.client.http.HttpRequest execute
# CONFIG: -------------- REQUEST  --------------
# POST https://dev71747.service-now.com//api/now/table/u_test_table
# Accept-Encoding: gzip
# Content-Type: application/json
# User-Agent: Google-HTTP-Java-Client/1.32.1 (gzip)
# Content-Type: application/json
# Content-Length: 51

# Sep 07, 2021 4:13:16 PM com.google.api.client.http.HttpRequest execute
# CONFIG: curl -v --compressed -X POST -H 'Accept-Encoding: gzip' -H 'Content-Type: application/json' -H 'User-Agent: Google-HTTP-Java-Client/1.32.1 (gzip)' -H 'Content-Type: application/json' -d '@-' -- 'https://dev71747.service-now.com//api/now/table/u_test_table' << $$$
# Sep 07, 2021 4:13:18 PM com.google.api.client.util.LoggingByteArrayOutputStream close
# CONFIG: Total: 51 bytes
# Sep 07, 2021 4:13:18 PM com.google.api.client.util.LoggingByteArrayOutputStream close
# CONFIG: {"u_name":"scissors","u_price":2.75,"u_quantity":3}
# [2021-09-07 16:13:18,694] ERROR [servicenow-sink|task-0] WorkerSinkTask{id=servicenow-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted. Error: Failed after 4 attempts to send request to ServiceNow: null (org.apache.kafka.connect.runtime.WorkerSinkTask:607)
# io.confluent.connect.utils.retry.RetryCountExceeded: Failed after 4 attempts to send request to ServiceNow: null
#         at io.confluent.connect.utils.retry.RetryPolicy.callWith(RetryPolicy.java:429)
#         at io.confluent.connect.utils.retry.RetryPolicy.call(RetryPolicy.java:337)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.executeRequest(ServiceNowClientImpl.java:229)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.doRequest(ServiceNowClientImpl.java:225)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.put(ServiceNowClientImpl.java:166)
#         at io.confluent.connect.servicenow.ServiceNowSinkTask.put(ServiceNowSinkTask.java:58)
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
# Caused by: org.apache.http.client.ClientProtocolException
#         at org.apache.http.impl.client.InternalHttpClient.doExecute(InternalHttpClient.java:187)
#         at org.apache.http.impl.client.CloseableHttpClient.execute(CloseableHttpClient.java:83)
#         at org.apache.http.impl.client.CloseableHttpClient.execute(CloseableHttpClient.java:108)
#         at org.apache.http.impl.client.CloseableHttpClient.execute(CloseableHttpClient.java:56)
#         at com.google.api.client.http.apache.v2.ApacheHttpRequest.execute(ApacheHttpRequest.java:71)
#         at com.google.api.client.http.HttpRequest.execute(HttpRequest.java:996)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.lambda$executeRequest$2(ServiceNowClientImpl.java:230)
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
# [2021-09-07 16:13:18,697] ERROR [servicenow-sink|task-0] WorkerSinkTask{id=servicenow-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:184)
# org.apache.kafka.connect.errors.ConnectException: Exiting WorkerSinkTask due to unrecoverable exception.
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:609)
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
# Caused by: io.confluent.connect.utils.retry.RetryCountExceeded: Failed after 4 attempts to send request to ServiceNow: null
#         at io.confluent.connect.utils.retry.RetryPolicy.callWith(RetryPolicy.java:429)
#         at io.confluent.connect.utils.retry.RetryPolicy.call(RetryPolicy.java:337)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.executeRequest(ServiceNowClientImpl.java:229)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.doRequest(ServiceNowClientImpl.java:225)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.put(ServiceNowClientImpl.java:166)
#         at io.confluent.connect.servicenow.ServiceNowSinkTask.put(ServiceNowSinkTask.java:58)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:581)
#         ... 10 more
# Caused by: org.apache.http.client.ClientProtocolException
#         at org.apache.http.impl.client.InternalHttpClient.doExecute(InternalHttpClient.java:187)
#         at org.apache.http.impl.client.CloseableHttpClient.execute(CloseableHttpClient.java:83)
#         at org.apache.http.impl.client.CloseableHttpClient.execute(CloseableHttpClient.java:108)
#         at org.apache.http.impl.client.CloseableHttpClient.execute(CloseableHttpClient.java:56)
#         at com.google.api.client.http.apache.v2.ApacheHttpRequest.execute(ApacheHttpRequest.java:71)
#         at com.google.api.client.http.HttpRequest.execute(HttpRequest.java:996)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.lambda$executeRequest$2(ServiceNowClientImpl.java:230)
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
