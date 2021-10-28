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

function wait_for_repro () {
     MAX_WAIT=600
     CUR_WAIT=0
     log "Waiting up to $MAX_WAIT seconds for error Cannot retry request with a non-repeatable request entity to happen"
     docker container logs connect > /tmp/out.txt 2>&1
     while ! grep "Cannot retry request with a non-repeatable request entity" /tmp/out.txt > /dev/null;
     do
          sleep 10
          docker container logs connect > /tmp/out.txt 2>&1
          CUR_WAIT=$(( CUR_WAIT+10 ))
          if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
               echo -e "\nERROR: The logs in all connect containers do not show 'Cannot retry request with a non-repeatable request entity' after $MAX_WAIT seconds. Please troubleshoot with 'docker container ps' and 'docker container logs'.\n"
               exit 1
          fi
     done
     log "The problem has been reproduced !"
}

function wait_for_end_of_hibernation () {
     MAX_WAIT=360
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

log "Doing a tcpdump"
docker exec -d --privileged --user root connect bash -c 'tcpdump -w tcpdump.pcap -i eth0 -s 0 port 8888'

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

curl --request PUT \
  --url http://localhost:8083/admin/loggers/io.confluent.connect.servicenow \
  --header 'Accept: application/json' \
  --header 'Content-Type: application/json' \
  --data '{
	"level": "TRACE"
}'

curl --request PUT \
  --url http://localhost:8083/admin/loggers/io.confluent.connect.utils.retry \
  --header 'Accept: application/json' \
  --header 'Content-Type: application/json' \
  --data '{
	"level": "TRACE"
}'

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
                    "retry.max.times": "2000",
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


log "Now simulate a 502 BAD Gateway by setting up a wrong NGINX config"
cp ${DIR}/repro-70453/nginx_whitelist.conf /tmp/
cp ${DIR}/repro-70453/nginx_whitelist_bad_gateway.conf ${DIR}/repro-70453/nginx_whitelist.conf
log "Restart the proxy"
docker restart nginx_proxy

log "Sending messages to topic test_table"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic test_table --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"u_name","type":"string"},
{"name":"u_price", "type": "float"}, {"name":"u_quantity", "type": "int"}]}' << EOF
{"u_name": "scissors", "u_price": 2.75, "u_quantity": 3}
{"u_name": "tape", "u_price": 0.99, "u_quantity": 10}
{"u_name": "notebooks", "u_price": 1.99, "u_quantity": 5}
EOF

log "The connector is now in a loop with 502 bad gateway, sleep 10 seconds"
sleep 10

log "Now set back the original working NGINX config"
cp /tmp/nginx_whitelist.conf ${DIR}/repro-70453/nginx_whitelist.conf
log "Restart the proxy"
docker restart nginx_proxy

log "Sending messages to topic test_table"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic test_table --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"u_name","type":"string"},
{"name":"u_price", "type": "float"}, {"name":"u_quantity", "type": "int"}]}' << EOF
{"u_name": "scissors", "u_price": 2.75, "u_quantity": 3}
{"u_name": "tape", "u_price": 0.99, "u_quantity": 10}
{"u_name": "notebooks", "u_price": 1.99, "u_quantity": 5}
EOF

wait_for_repro

log "The connector is now in a loop with Cannot retry request with a non-repeatable request entity"

# [2021-09-14 15:01:05,411] TRACE [servicenow-sink|task-0] Create resources for send request to ServiceNow (attempt 270 of 2001) (io.confluent.connect.utils.retry.RetryPolicy:404)
# [2021-09-14 15:01:05,411] TRACE [servicenow-sink|task-0] Try send request to ServiceNow (attempt 270 of 2001) (io.confluent.connect.utils.retry.RetryPolicy:411)
# [2021-09-14 15:01:06,237] TRACE [servicenow-sink|task-0] Waiting before retrying to send request to ServiceNow (attempt 270 of 2001) (io.confluent.connect.utils.retry.RetryPolicy:440)
# [2021-09-14 15:01:06,237] DEBUG [servicenow-sink|task-0] Start exponential (0-300 ms) backoff of 00:00:00.123 before another attempt (io.confluent.connect.utils.retry.RetryCounter:361)
# [2021-09-14 15:01:06,238] TRACE [servicenow-sink|task-0] Sleeping for 00:00:00.123ms, 123ms remaining (io.confluent.connect.utils.retry.RetryCounter:412)
# [2021-09-14 15:01:06,362] DEBUG [servicenow-sink|task-0] Completed exponential (0-300 ms) backoff of 00:00:00.123 (io.confluent.connect.utils.retry.RetryCounter:373)
# [2021-09-14 15:01:06,362] DEBUG [servicenow-sink|task-0] Retrying to send request to ServiceNow (attempt 270 of 2001) after previous retriable error: null (io.confluent.connect.utils.retry.RetryPolicy:448)
# org.apache.http.client.ClientProtocolException
#         at org.apache.http.impl.client.InternalHttpClient.doExecute(InternalHttpClient.java:187)
#         at org.apache.http.impl.client.CloseableHttpClient.execute(CloseableHttpClient.java:83)
#         at org.apache.http.impl.client.CloseableHttpClient.execute(CloseableHttpClient.java:108)
#         at org.apache.http.impl.client.CloseableHttpClient.execute(CloseableHttpClient.java:56)
#         at com.google.api.client.http.apache.v2.ApacheHttpRequest.execute(ApacheHttpRequest.java:71)
#         at com.google.api.client.http.HttpRequest.execute(HttpRequest.java:996)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.lambda$executeRequest$2(ServiceNowClientImpl.java:230)
#         at io.confluent.connect.utils.retry.RetryPolicy.lambda$call$1(RetryPolicy.java:337)
#         at io.confluent.connect.utils.retry.RetryPolicy.callWith(RetryPolicy.java:417)
#         at io.confluent.connect.utils.retry.RetryPolicy.call(RetryPolicy.java:337)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.executeRequest(ServiceNowClientImpl.java:229)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.doRequest(ServiceNowClientImpl.java:225)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.put(ServiceNowClientImpl.java:166)
#         at io.confluent.connect.servicenow.ServiceNowSinkTask.put(ServiceNowSinkTask.java:58)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:560)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:323)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:226)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:198)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:185)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:235)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:834)
# Caused by: org.apache.http.client.NonRepeatableRequestException: Cannot retry request with a non-repeatable request entity.
#         at org.apache.http.impl.execchain.MainClientExec.execute(MainClientExec.java:225)
#         at org.apache.http.impl.execchain.ProtocolExec.execute(ProtocolExec.java:186)
#         at org.apache.http.impl.execchain.RetryExec.execute(RetryExec.java:89)
#         at org.apache.http.impl.execchain.RedirectExec.execute(RedirectExec.java:110)
#         at org.apache.http.impl.client.InternalHttpClient.doExecute(InternalHttpClient.java:185)
#         ... 24 more
# [2021-09-14 15:01:06,362] TRACE [servicenow-sink|task-0] Create resources for send request to ServiceNow (attempt 271 of 2001) (io.confluent.connect.utils.retry.RetryPolicy:404)
# [2021-09-14 15:01:06,362] TRACE [servicenow-sink|task-0] Try send request to ServiceNow (attempt 271 of 2001) (io.confluent.connect.utils.retry.RetryPolicy:411)
# [2021-09-14 15:01:07,186] TRACE [servicenow-sink|task-0] Waiting before retrying to send request to ServiceNow (attempt 271 of 2001) (io.confluent.connect.utils.retry.RetryPolicy:440)
# [2021-09-14 15:01:07,186] DEBUG [servicenow-sink|task-0] Start exponential (0-300 ms) backoff of 00:00:00.025 before another attempt (io.confluent.connect.utils.retry.RetryCounter:361)
# [2021-09-14 15:01:07,186] TRACE [servicenow-sink|task-0] Sleeping for 00:00:00.025ms, 25ms remaining (io.confluent.connect.utils.retry.RetryCounter:412)
# [2021-09-14 15:01:07,211] DEBUG [servicenow-sink|task-0] Completed exponential (0-300 ms) backoff of 00:00:00.025 (io.confluent.connect.utils.retry.RetryCounter:373)
# [2021-09-14 15:01:07,212] DEBUG [servicenow-sink|task-0] Retrying to send request to ServiceNow (attempt 271 of 2001) after previous retriable error: null (io.confluent.connect.utils.retry.RetryPolicy:448)
# org.apache.http.client.ClientProtocolException
#         at org.apache.http.impl.client.InternalHttpClient.doExecute(InternalHttpClient.java:187)
#         at org.apache.http.impl.client.CloseableHttpClient.execute(CloseableHttpClient.java:83)
#         at org.apache.http.impl.client.CloseableHttpClient.execute(CloseableHttpClient.java:108)
#         at org.apache.http.impl.client.CloseableHttpClient.execute(CloseableHttpClient.java:56)
#         at com.google.api.client.http.apache.v2.ApacheHttpRequest.execute(ApacheHttpRequest.java:71)
#         at com.google.api.client.http.HttpRequest.execute(HttpRequest.java:996)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.lambda$executeRequest$2(ServiceNowClientImpl.java:230)
#         at io.confluent.connect.utils.retry.RetryPolicy.lambda$call$1(RetryPolicy.java:337)
#         at io.confluent.connect.utils.retry.RetryPolicy.callWith(RetryPolicy.java:417)
#         at io.confluent.connect.utils.retry.RetryPolicy.call(RetryPolicy.java:337)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.executeRequest(ServiceNowClientImpl.java:229)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.doRequest(ServiceNowClientImpl.java:225)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.put(ServiceNowClientImpl.java:166)
#         at io.confluent.connect.servicenow.ServiceNowSinkTask.put(ServiceNowSinkTask.java:58)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:560)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:323)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:226)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:198)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:185)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:235)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:834)
# Caused by: org.apache.http.client.NonRepeatableRequestException: Cannot retry request with a non-repeatable request entity.
#         at org.apache.http.impl.execchain.MainClientExec.execute(MainClientExec.java:225)
#         at org.apache.http.impl.execchain.ProtocolExec.execute(ProtocolExec.java:186)
#         at org.apache.http.impl.execchain.RetryExec.execute(RetryExec.java:89)
#         at org.apache.http.impl.execchain.RedirectExec.execute(RedirectExec.java:110)
#         at org.apache.http.impl.client.InternalHttpClient.doExecute(InternalHttpClient.java:185)
#         ... 24 more
# [2021-09-14 15:01:07,212] TRACE [servicenow-sink|task-0] Create resources for send request to ServiceNow (attempt 272 of 2001) (io.confluent.connect.utils.retry.RetryPolicy:404)
# [2021-09-14 15:01:07,212] TRACE [servicenow-sink|task-0] Try send request to ServiceNow (attempt 272 of 2001) (io.confluent.connect.utils.retry.RetryPolicy:411)
# [2021-09-14 15:01:08,029] TRACE [servicenow-sink|task-0] Waiting before retrying to send request to ServiceNow (attempt 272 of 2001) (io.confluent.connect.utils.retry.RetryPolicy:440)
# [2021-09-14 15:01:08,029] DEBUG [servicenow-sink|task-0] Start exponential (0-300 ms) backoff of 00:00:00.167 before another attempt (io.confluent.connect.utils.retry.RetryCounter:361)
# [2021-09-14 15:01:08,030] TRACE [servicenow-sink|task-0] Sleeping for 00:00:00.167ms, 167ms remaining (io.confluent.connect.utils.retry.RetryCounter:412)
# [2021-09-14 15:01:08,198] DEBUG [servicenow-sink|task-0] Completed exponential (0-300 ms) backoff of 00:00:00.167 (io.confluent.connect.utils.retry.RetryCounter:373)
# [2021-09-14 15:01:08,198] DEBUG [servicenow-sink|task-0] Retrying to send request to ServiceNow (attempt 272 of 2001) after previous retriable error: null (io.confluent.connect.utils.retry.RetryPolicy:448)
# org.apache.http.client.ClientProtocolException
#         at org.apache.http.impl.client.InternalHttpClient.doExecute(InternalHttpClient.java:187)
#         at org.apache.http.impl.client.CloseableHttpClient.execute(CloseableHttpClient.java:83)
#         at org.apache.http.impl.client.CloseableHttpClient.execute(CloseableHttpClient.java:108)
#         at org.apache.http.impl.client.CloseableHttpClient.execute(CloseableHttpClient.java:56)
#         at com.google.api.client.http.apache.v2.ApacheHttpRequest.execute(ApacheHttpRequest.java:71)
#         at com.google.api.client.http.HttpRequest.execute(HttpRequest.java:996)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.lambda$executeRequest$2(ServiceNowClientImpl.java:230)
#         at io.confluent.connect.utils.retry.RetryPolicy.lambda$call$1(RetryPolicy.java:337)
#         at io.confluent.connect.utils.retry.RetryPolicy.callWith(RetryPolicy.java:417)
#         at io.confluent.connect.utils.retry.RetryPolicy.call(RetryPolicy.java:337)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.executeRequest(ServiceNowClientImpl.java:229)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.doRequest(ServiceNowClientImpl.java:225)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.put(ServiceNowClientImpl.java:166)
#         at io.confluent.connect.servicenow.ServiceNowSinkTask.put(ServiceNowSinkTask.java:58)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:560)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:323)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:226)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:198)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:185)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:235)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:834)
# Caused by: org.apache.http.client.NonRepeatableRequestException: Cannot retry request with a non-repeatable request entity.
#         at org.apache.http.impl.execchain.MainClientExec.execute(MainClientExec.java:225)
#         at org.apache.http.impl.execchain.ProtocolExec.execute(ProtocolExec.java:186)
#         at org.apache.http.impl.execchain.RetryExec.execute(RetryExec.java:89)
#         at org.apache.http.impl.execchain.RedirectExec.execute(RedirectExec.java:110)
#         at org.apache.http.impl.client.InternalHttpClient.doExecute(InternalHttpClient.java:185)
#         ... 24 more
# [2021-09-14 15:01:08,198] TRACE [servicenow-sink|task-0] Create resources for send request to ServiceNow (attempt 273 of 2001) (io.confluent.connect.utils.retry.RetryPolicy:404)
# [2021-09-14 15:01:08,198] TRACE [servicenow-sink|task-0] Try send request to ServiceNow (attempt 273 of 2001) (io.confluent.connect.utils.retry.RetryPolicy:411)
# [2021-09-14 15:01:09,024] TRACE [servicenow-sink|task-0] Waiting before retrying to send request to ServiceNow (attempt 273 of 2001) (io.confluent.connect.utils.retry.RetryPolicy:440)
# [2021-09-14 15:01:09,025] DEBUG [servicenow-sink|task-0] Start exponential (0-300 ms) backoff of 00:00:00.129 before another attempt (io.confluent.connect.utils.retry.RetryCounter:361)
# [2021-09-14 15:01:09,025] TRACE [servicenow-sink|task-0] Sleeping for 00:00:00.129ms, 129ms remaining (io.confluent.connect.utils.retry.RetryCounter:412)
# [2021-09-14 15:01:09,154] DEBUG [servicenow-sink|task-0] Completed exponential (0-300 ms) backoff of 00:00:00.129 (io.confluent.connect.utils.retry.RetryCounter:373)
# [2021-09-14 15:01:09,155] DEBUG [servicenow-sink|task-0] Retrying to send request to ServiceNow (attempt 273 of 2001) after previous retriable error: null (io.confluent.connect.utils.retry.RetryPolicy:448)
# org.apache.http.client.ClientProtocolException
#         at org.apache.http.impl.client.InternalHttpClient.doExecute(InternalHttpClient.java:187)
#         at org.apache.http.impl.client.CloseableHttpClient.execute(CloseableHttpClient.java:83)
#         at org.apache.http.impl.client.CloseableHttpClient.execute(CloseableHttpClient.java:108)
#         at org.apache.http.impl.client.CloseableHttpClient.execute(CloseableHttpClient.java:56)
#         at com.google.api.client.http.apache.v2.ApacheHttpRequest.execute(ApacheHttpRequest.java:71)
#         at com.google.api.client.http.HttpRequest.execute(HttpRequest.java:996)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.lambda$executeRequest$2(ServiceNowClientImpl.java:230)
#         at io.confluent.connect.utils.retry.RetryPolicy.lambda$call$1(RetryPolicy.java:337)
#         at io.confluent.connect.utils.retry.RetryPolicy.callWith(RetryPolicy.java:417)
#         at io.confluent.connect.utils.retry.RetryPolicy.call(RetryPolicy.java:337)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.executeRequest(ServiceNowClientImpl.java:229)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.doRequest(ServiceNowClientImpl.java:225)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.put(ServiceNowClientImpl.java:166)
#         at io.confluent.connect.servicenow.ServiceNowSinkTask.put(ServiceNowSinkTask.java:58)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:560)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:323)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:226)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:198)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:185)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:235)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:834)
# Caused by: org.apache.http.client.NonRepeatableRequestException: Cannot retry request with a non-repeatable request entity.
#         at org.apache.http.impl.execchain.MainClientExec.execute(MainClientExec.java:225)
#         at org.apache.http.impl.execchain.ProtocolExec.execute(ProtocolExec.java:186)
#         at org.apache.http.impl.execchain.RetryExec.execute(RetryExec.java:89)
#         at org.apache.http.impl.execchain.RedirectExec.execute(RedirectExec.java:110)
#         at org.apache.http.impl.client.InternalHttpClient.doExecute(InternalHttpClient.java:185)
#         ... 24 more
# [2021-09-14 15:01:09,155] TRACE [servicenow-sink|task-0] Create resources for send request to ServiceNow (attempt 274 of 2001) (io.confluent.connect.utils.retry.RetryPolicy:404)
# [2021-09-14 15:01:09,155] TRACE [servicenow-sink|task-0] Try send request to ServiceNow (attempt 274 of 2001) (io.confluent.connect.utils.retry.RetryPolicy:411)
# [2021-09-14 15:01:09,998] TRACE [servicenow-sink|task-0] Waiting before retrying to send request to ServiceNow (attempt 274 of 2001) (io.confluent.connect.utils.retry.RetryPolicy:440)
# [2021-09-14 15:01:09,998] DEBUG [servicenow-sink|task-0] Start exponential (0-300 ms) backoff of 00:00:00.150 before another attempt (io.confluent.connect.utils.retry.RetryCounter:361)
# [2021-09-14 15:01:09,999] TRACE [servicenow-sink|task-0] Sleeping for 00:00:00.150ms, 150ms remaining (io.confluent.connect.utils.retry.RetryCounter:412)
# [2021-09-14 15:01:10,149] DEBUG [servicenow-sink|task-0] Completed exponential (0-300 ms) backoff of 00:00:00.150 (io.confluent.connect.utils.retry.RetryCounter:373)
# [2021-09-14 15:01:10,149] DEBUG [servicenow-sink|task-0] Retrying to send request to ServiceNow (attempt 274 of 2001) after previous retriable error: null (io.confluent.connect.utils.retry.RetryPolicy:448)
# org.apache.http.client.ClientProtocolException
#         at org.apache.http.impl.client.InternalHttpClient.doExecute(InternalHttpClient.java:187)
#         at org.apache.http.impl.client.CloseableHttpClient.execute(CloseableHttpClient.java:83)
#         at org.apache.http.impl.client.CloseableHttpClient.execute(CloseableHttpClient.java:108)
#         at org.apache.http.impl.client.CloseableHttpClient.execute(CloseableHttpClient.java:56)
#         at com.google.api.client.http.apache.v2.ApacheHttpRequest.execute(ApacheHttpRequest.java:71)
#         at com.google.api.client.http.HttpRequest.execute(HttpRequest.java:996)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.lambda$executeRequest$2(ServiceNowClientImpl.java:230)
#         at io.confluent.connect.utils.retry.RetryPolicy.lambda$call$1(RetryPolicy.java:337)
#         at io.confluent.connect.utils.retry.RetryPolicy.callWith(RetryPolicy.java:417)
#         at io.confluent.connect.utils.retry.RetryPolicy.call(RetryPolicy.java:337)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.executeRequest(ServiceNowClientImpl.java:229)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.doRequest(ServiceNowClientImpl.java:225)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.put(ServiceNowClientImpl.java:166)
#         at io.confluent.connect.servicenow.ServiceNowSinkTask.put(ServiceNowSinkTask.java:58)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:560)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:323)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:226)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:198)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:185)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:235)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:834)
# Caused by: org.apache.http.client.NonRepeatableRequestException: Cannot retry request with a non-repeatable request entity.
#         at org.apache.http.impl.execchain.MainClientExec.execute(MainClientExec.java:225)
#         at org.apache.http.impl.execchain.ProtocolExec.execute(ProtocolExec.java:186)
#         at org.apache.http.impl.execchain.RetryExec.execute(RetryExec.java:89)
#         at org.apache.http.impl.execchain.RedirectExec.execute(RedirectExec.java:110)
#         at org.apache.http.impl.client.InternalHttpClient.doExecute(InternalHttpClient.java:185)
#         ... 24 more
# [2021-09-14 15:01:10,150] TRACE [servicenow-sink|task-0] Create resources for send request to ServiceNow (attempt 275 of 2001) (io.confluent.connect.utils.retry.RetryPolicy:404)
# [2021-09-14 15:01:10,150] TRACE [servicenow-sink|task-0] Try send request to ServiceNow (attempt 275 of 2001) (io.confluent.connect.utils.retry.RetryPolicy:411)
# [2021-09-14 15:01:10,992] TRACE [servicenow-sink|task-0] Waiting before retrying to send request to ServiceNow (attempt 275 of 2001) (io.confluent.connect.utils.retry.RetryPolicy:440)
# [2021-09-14 15:01:10,993] DEBUG [servicenow-sink|task-0] Start exponential (0-300 ms) backoff of 00:00:00.284 before another attempt (io.confluent.connect.utils.retry.RetryCounter:361)
# [2021-09-14 15:01:10,993] TRACE [servicenow-sink|task-0] Sleeping for 00:00:00.284ms, 284ms remaining (io.confluent.connect.utils.retry.RetryCounter:412)
# [2021-09-14 15:01:11,278] DEBUG [servicenow-sink|task-0] Completed exponential (0-300 ms) backoff of 00:00:00.284 (io.confluent.connect.utils.retry.RetryCounter:373)
# [2021-09-14 15:01:11,278] DEBUG [servicenow-sink|task-0] Retrying to send request to ServiceNow (attempt 275 of 2001) after previous retriable error: null (io.confluent.connect.utils.retry.RetryPolicy:448)
# org.apache.http.client.ClientProtocolException
#         at org.apache.http.impl.client.InternalHttpClient.doExecute(InternalHttpClient.java:187)
#         at org.apache.http.impl.client.CloseableHttpClient.execute(CloseableHttpClient.java:83)
#         at org.apache.http.impl.client.CloseableHttpClient.execute(CloseableHttpClient.java:108)
#         at org.apache.http.impl.client.CloseableHttpClient.execute(CloseableHttpClient.java:56)
#         at com.google.api.client.http.apache.v2.ApacheHttpRequest.execute(ApacheHttpRequest.java:71)
#         at com.google.api.client.http.HttpRequest.execute(HttpRequest.java:996)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.lambda$executeRequest$2(ServiceNowClientImpl.java:230)
#         at io.confluent.connect.utils.retry.RetryPolicy.lambda$call$1(RetryPolicy.java:337)
#         at io.confluent.connect.utils.retry.RetryPolicy.callWith(RetryPolicy.java:417)
#         at io.confluent.connect.utils.retry.RetryPolicy.call(RetryPolicy.java:337)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.executeRequest(ServiceNowClientImpl.java:229)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.doRequest(ServiceNowClientImpl.java:225)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.put(ServiceNowClientImpl.java:166)
#         at io.confluent.connect.servicenow.ServiceNowSinkTask.put(ServiceNowSinkTask.java:58)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:560)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:323)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:226)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:198)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:185)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:235)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:834)
# Caused by: org.apache.http.client.NonRepeatableRequestException: Cannot retry request with a non-repeatable request entity.
#         at org.apache.http.impl.execchain.MainClientExec.execute(MainClientExec.java:225)
#         at org.apache.http.impl.execchain.ProtocolExec.execute(ProtocolExec.java:186)
#         at org.apache.http.impl.execchain.RetryExec.execute(RetryExec.java:89)
#         at org.apache.http.impl.execchain.RedirectExec.execute(RedirectExec.java:110)
#         at org.apache.http.impl.client.InternalHttpClient.doExecute(InternalHttpClient.java:185)
#         ... 24 more
# [2021-09-14 15:01:11,278] TRACE [servicenow-sink|task-0] Create resources for send request to ServiceNow (attempt 276 of 2001) (io.confluent.connect.utils.retry.RetryPolicy:404)
# [2021-09-14 15:01:11,278] TRACE [servicenow-sink|task-0] Try send request to ServiceNow (attempt 276 of 2001) (io.confluent.connect.utils.retry.RetryPolicy:411)
# [2021-09-14 15:01:12,112] TRACE [servicenow-sink|task-0] Waiting before retrying to send request to ServiceNow (attempt 276 of 2001) (io.confluent.connect.utils.retry.RetryPolicy:440)
# [2021-09-14 15:01:12,113] DEBUG [servicenow-sink|task-0] Start exponential (0-300 ms) backoff of 00:00:00.244 before another attempt (io.confluent.connect.utils.retry.RetryCounter:361)
# [2021-09-14 15:01:12,113] TRACE [servicenow-sink|task-0] Sleeping for 00:00:00.244ms, 244ms remaining (io.confluent.connect.utils.retry.RetryCounter:412)
# [2021-09-14 15:01:12,358] DEBUG [servicenow-sink|task-0] Completed exponential (0-300 ms) backoff of 00:00:00.244 (io.confluent.connect.utils.retry.RetryCounter:373)
# [2021-09-14 15:01:12,358] DEBUG [servicenow-sink|task-0] Retrying to send request to ServiceNow (attempt 276 of 2001) after previous retriable error: null (io.confluent.connect.utils.retry.RetryPolicy:448)
# org.apache.http.client.ClientProtocolException
#         at org.apache.http.impl.client.InternalHttpClient.doExecute(InternalHttpClient.java:187)
#         at org.apache.http.impl.client.CloseableHttpClient.execute(CloseableHttpClient.java:83)
#         at org.apache.http.impl.client.CloseableHttpClient.execute(CloseableHttpClient.java:108)
#         at org.apache.http.impl.client.CloseableHttpClient.execute(CloseableHttpClient.java:56)
#         at com.google.api.client.http.apache.v2.ApacheHttpRequest.execute(ApacheHttpRequest.java:71)
#         at com.google.api.client.http.HttpRequest.execute(HttpRequest.java:996)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.lambda$executeRequest$2(ServiceNowClientImpl.java:230)
#         at io.confluent.connect.utils.retry.RetryPolicy.lambda$call$1(RetryPolicy.java:337)
#         at io.confluent.connect.utils.retry.RetryPolicy.callWith(RetryPolicy.java:417)
#         at io.confluent.connect.utils.retry.RetryPolicy.call(RetryPolicy.java:337)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.executeRequest(ServiceNowClientImpl.java:229)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.doRequest(ServiceNowClientImpl.java:225)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.put(ServiceNowClientImpl.java:166)
#         at io.confluent.connect.servicenow.ServiceNowSinkTask.put(ServiceNowSinkTask.java:58)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:560)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:323)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:226)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:198)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:185)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:235)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:834)
# Caused by: org.apache.http.client.NonRepeatableRequestException: Cannot retry request with a non-repeatable request entity.
#         at org.apache.http.impl.execchain.MainClientExec.execute(MainClientExec.java:225)
#         at org.apache.http.impl.execchain.ProtocolExec.execute(ProtocolExec.java:186)
#         at org.apache.http.impl.execchain.RetryExec.execute(RetryExec.java:89)
#         at org.apache.http.impl.execchain.RedirectExec.execute(RedirectExec.java:110)
#         at org.apache.http.impl.client.InternalHttpClient.doExecute(InternalHttpClient.java:185)
#         ... 24 more


# and at the end..

# [2021-09-14 15:29:34,370] ERROR [servicenow-sink|task-0] WorkerSinkTask{id=servicenow-sink-0} Task threw an uncaught and unrecoverable exception (org.apache.kafka.connect.runtime.WorkerTask:187)
# org.apache.kafka.connect.errors.ConnectException: Exiting WorkerSinkTask due to unrecoverable exception.
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:588)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:323)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:226)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:198)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:185)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:235)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:834)
# Caused by: io.confluent.connect.utils.retry.RetryCountExceeded: Failed after 2001 attempts to send request to ServiceNow: null
#         at io.confluent.connect.utils.retry.RetryPolicy.callWith(RetryPolicy.java:429)
#         at io.confluent.connect.utils.retry.RetryPolicy.call(RetryPolicy.java:337)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.executeRequest(ServiceNowClientImpl.java:229)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.doRequest(ServiceNowClientImpl.java:225)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.put(ServiceNowClientImpl.java:166)
#         at io.confluent.connect.servicenow.ServiceNowSinkTask.put(ServiceNowSinkTask.java:58)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:560)
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
# [2021-09-14 15:29:34,370] ERROR [servicenow-sink|task-0] WorkerSinkTask{id=servicenow-sink-0} Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:188)
# [2021-09-14 15:29:34,370] DEBUG [servicenow-sink|task-0] Stopping ServiceNow Sink Task... (io.confluent.connect.servicenow.ServiceNowSinkTask:115)
# [2021-09-14 15:29:34,372] INFO [servicenow-sink|task-0] [Producer clientId=producer-4] Closing the Kafka producer with timeoutMillis = 9223372036854775807 ms. (org.apache.kafka.clients.producer.KafkaProducer:1189)
# [2021-09-14 15:29:34,390] INFO [servicenow-sink|task-0] [Consumer clientId=connector-consumer-servicenow-sink-0, groupId=connect-servicenow-sink] Lost previously assigned partitions test_table-0 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:326)
# [2021-09-14 15:29:34,402] INFO [servicenow-sink|task-0] Publish thread interrupted for client_id=connector-consumer-servicenow-sink-0 client_type=CONSUMER session= cluster=p06BOwJ8SGmz9PrF3GsiBQ group=connect-servicenow-sink (io.confluent.monitoring.clients.interceptor.MonitoringInterceptor:285)
# [2021-09-14 15:29:34,403] INFO [servicenow-sink|task-0] Publishing Monitoring Metrics stopped for client_id=connector-consumer-servicenow-sink-0 client_type=CONSUMER session= cluster=p06BOwJ8SGmz9PrF3GsiBQ group=connect-servicenow-sink (io.confluent.monitoring.clients.interceptor.MonitoringInterceptor:297)
# [2021-09-14 15:29:34,403] INFO [servicenow-sink|task-0] [Producer clientId=confluent.monitoring.interceptor.connector-consumer-servicenow-sink-0] Closing the Kafka producer with timeoutMillis = 9223372036854775807 ms. (org.apache.kafka.clients.producer.KafkaProducer:1189)
# [2021-09-14 15:29:34,410] INFO [servicenow-sink|task-0] Closed monitoring interceptor for client_id=connector-consumer-servicenow-sink-0 client_type=CONSUMER session= cluster=p06BOwJ8SGmz9PrF3GsiBQ group=connect-servicenow-sink (io.confluent.monitoring.clients.interceptor.MonitoringInterceptor:320)
# [2021-09-14 15:54:10,467] INFO [Worker clientId=connect-1, groupId=connect-cluster] Session key updated (org.apache.kafka.connect.runtime.distributed.DistributedHerder:1570)

# 360fd6523852   plaintext_nginx_proxy                             "/bin/sh -c /usr/loc…"   3 minutes ago   Up 38 seconds   0.0.0.0:8888->8888/tcp, :::8888->8888/tcp                                                                                                 nginx_proxy
