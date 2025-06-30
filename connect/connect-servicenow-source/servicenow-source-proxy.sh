#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if version_gt $TAG_BASE "7.9.99" && ! version_gt $CONNECTOR_TAG "2.5.5"
then
     logwarn "minimal supported connector version is 2.5.6 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.0.html#supported-connector-versions-in-cp-8-0"
     exit 111
fi

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
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.nginx-proxy.yml"

export HTTP_PROXY=127.0.0.1:8888
export HTTPS_PROXY=127.0.0.1:8888
log "Verify forward proxy is working correctly"
curl --compressed -H 'Accept-Encoding: gzip' -H 'Content-Type: application/json' -H 'User-Agent: Google-HTTP-Java-Client/1.30.0 (gzip)' -v ${SERVICENOW_URL}api/now/table/incident?sysparm_limit=1 -u "admin:$SERVICENOW_PASSWORD" | jq .

docker exec -e SERVICENOW_URL=$SERVICENOW_URL -e SERVICENOW_PASSWORD=$SERVICENOW_PASSWORD connect bash -c "export HTTP_PROXY=nginx-proxy:8888 && export HTTPS_PROXY=nginx-proxy:8888 && curl --compressed -H 'Accept-Encoding: gzip' -H 'User-Agent: Google-HTTP-Java-Client/1.30.0 (gzip)' -v ${SERVICENOW_URL}api/now/table/incident?sysparm_limit=1 -u \"admin:$SERVICENOW_PASSWORD\""

# block
# echo "$SERVICENOW_URL" | cut -d "/" -f3
# ip=$(dig +short $(echo "$SERVICENOW_URL" | cut -d "/" -f3))
# log "Blocking serviceNow instance IP address $ip on connect, to make sure proxy is used"
# docker exec -i --privileged --user root connect bash -c "iptables -A INPUT -s $ip -j REJECT"
# docker exec -i --privileged --user root connect bash -c "iptables -L -n -v"

curl --request PUT \
  --url http://localhost:8083/admin/loggers/io.confluent.connect.servicenow \
  --header 'Accept: application/json' \
  --header 'Content-Type: application/json' \
  --data '{
	"level": "TRACE"
}'

TODAY=$(date -u '+%Y-%m-%d')

log "Creating ServiceNow Source connector"
playground connector create-or-update --connector servicenow-source  << EOF
{
               "connector.class": "io.confluent.connect.servicenow.ServiceNowSourceConnector",
               "kafka.topic": "topic-servicenow",
               "proxy.url": "nginx-proxy:8888",
               "servicenow.url": "$SERVICENOW_URL",
               "tasks.max": "1",
               "servicenow.table": "incident",
               "servicenow.user": "admin",
               "servicenow.password": "$SERVICENOW_PASSWORD",
               "servicenow.since": "$TODAY",
               "retry.max.times": "3",
               "key.converter": "org.apache.kafka.connect.json.JsonConverter",
               "value.converter": "org.apache.kafka.connect.json.JsonConverter",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }
EOF


sleep 10

log "Create one record to ServiceNow using proxy"
docker exec -e SERVICENOW_URL="$SERVICENOW_URL" -e SERVICENOW_PASSWORD="$SERVICENOW_PASSWORD" connect bash -c "export HTTP_PROXY=nginx-proxy:8888 && export HTTPS_PROXY=nginx-proxy:8888 && \
   curl -X POST \
    \"${SERVICENOW_URL}api/now/table/incident\" \
    --user admin:\"$SERVICENOW_PASSWORD\" \
    -H 'Accept: application/json' \
    -H 'Content-Type: application/json' \
    -H 'cache-control: no-cache' \
    -d '{\"short_description\": \"This is test\"}'"

sleep 5

log "Verify we have received the data in topic-servicenow topic"
playground topic consume --topic topic-servicenow --min-expected-messages 1 --timeout 60

log "starting tcpdump"
docker exec -d --privileged --user root connect bash -c 'tcpdump -w /tmp/tcpdump.pcap -i eth0 -s 0 port 8888'

# echo "$SERVICENOW_URL" | cut -d "/" -f3
# ip=$(dig +short $(echo "$SERVICENOW_URL" | cut -d "/" -f3))
# log "Blocking serviceNow response on nginx-proxy"
# docker exec -i --privileged --user root nginx-proxy bash -c "apt-get update -y && apt-get install iptables -y"
# docker exec -i --privileged --user root nginx-proxy bash -c "iptables -A INPUT -p tcp -s $ip -j DROP"


# [2021-09-30 09:01:29,490] ERROR [servicenow-source|task-0] WorkerSourceTask{id=servicenow-source-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:184)
# io.confluent.connect.utils.retry.RetryCountExceeded: Failed after 4 attempts to send request to ServiceNow: 504 Gateway Time-out
# <html>
# <head><title>504 Gateway Time-out</title></head>
# <body>
# <center><h1>504 Gateway Time-out</h1></center>
# <hr><center>nginx/1.18.0 (Ubuntu)</center>
# </body>
# </html>

#         at io.confluent.connect.utils.retry.RetryPolicy.callWith(RetryPolicy.java:429)
#         at io.confluent.connect.utils.retry.RetryPolicy.call(RetryPolicy.java:337)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.executeRequest(ServiceNowClientImpl.java:229)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.get(ServiceNowClientImpl.java:183)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.getObjects(ServiceNowClientImpl.java:146)
#         at io.confluent.connect.servicenow.ServiceNowSourceTask.fetchRecordFromServiceNow(ServiceNowSourceTask.java:183)
#         at io.confluent.connect.servicenow.ServiceNowSourceTask.poll(ServiceNowSourceTask.java:142)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.poll(WorkerSourceTask.java:268)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.execute(WorkerSourceTask.java:241)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:182)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:231)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: com.google.api.client.http.HttpResponseException: 504 Gateway Time-out
# <html>
# <head><title>504 Gateway Time-out</title></head>
# <body>
# <center><h1>504 Gateway Time-out</h1></center>
# <hr><center>nginx/1.18.0 (Ubuntu)</center>
# </body>
# </html>

#         at com.google.api.client.http.HttpRequest.execute(HttpRequest.java:1097)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.lambda$executeRequest$2(ServiceNowClientImpl.java:230)
#         at io.confluent.connect.utils.retry.RetryPolicy.lambda$call$1(RetryPolicy.java:337)
#         at io.confluent.connect.utils.retry.RetryPolicy.callWith(RetryPolicy.java:417)
#         ... 15 more
        