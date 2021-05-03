#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

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
     log "sleeping 240 seconds"
     sleep 240
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-proxy.yml"

export HTTP_PROXY=127.0.0.1:8888
export HTTPS_PROXY=127.0.0.1:8888
log "Verify forward proxy is working correctly"
curl --compressed -H 'Accept-Encoding: gzip' -H 'Content-Type: application/json' -H 'User-Agent: Google-HTTP-Java-Client/1.30.0 (gzip)' -v ${SERVICENOW_URL}api/now/table/incident?sysparm_limit=1 -u "admin:$SERVICENOW_PASSWORD" | jq .

docker exec -e SERVICENOW_URL=$SERVICENOW_URL -e SERVICENOW_PASSWORD=$SERVICENOW_PASSWORD connect bash -c "export HTTP_PROXY=nginx_proxy:8888 && export HTTPS_PROXY=nginx_proxy:8888 && curl --compressed -H 'Accept-Encoding: gzip' -H 'User-Agent: Google-HTTP-Java-Client/1.30.0 (gzip)' -v ${SERVICENOW_URL}api/now/table/incident?sysparm_limit=1 -u \"admin:$SERVICENOW_PASSWORD\""

# block
# echo "$SERVICENOW_URL" | cut -d "/" -f3
# ip=$(dig +short $(echo "$SERVICENOW_URL" | cut -d "/" -f3))
# log "Blocking serviceNow instance IP address $ip on connect, to make sure proxy is used"
# docker exec -i --privileged --user root connect bash -c "yum update -y && yum install iptables -y"
# docker exec -i --privileged --user root connect bash -c "iptables -A INPUT -s $ip -j REJECT"
# docker exec -i --privileged --user root connect bash -c "iptables -A INPUT -d $ip -j REJECT"
# docker exec -i --privileged --user root connect bash -c "iptables -A OUTPUT -s $ip -j REJECT"
# docker exec -i --privileged --user root connect bash -c "iptables -A OUTPUT -d $ip -j REJECT"
# docker exec -i --privileged --user root connect bash -c "iptables -L -n -v"

TODAY=$(date '+%Y-%m-%d')

log "Creating ServiceNow Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.servicenow.ServiceNowSourceConnector",
               "kafka.topic": "topic-servicenow",
               "proxy.url": "nginx_proxy:8888",
               "servicenow.url": "'"$SERVICENOW_URL"'",
               "tasks.max": "1",
               "servicenow.table": "incident",
               "servicenow.user": "admin",
               "servicenow.password": "'"$SERVICENOW_PASSWORD"'",
               "servicenow.since": "'"$TODAY"'",
               "retry.max.times": "100",
               "key.converter": "org.apache.kafka.connect.json.JsonConverter",
               "value.converter": "org.apache.kafka.connect.json.JsonConverter",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/servicenow-source/config | jq .


sleep 10

log "Create one record to ServiceNow using proxy"
docker exec -e SERVICENOW_URL="$SERVICENOW_URL" -e SERVICENOW_PASSWORD="$SERVICENOW_PASSWORD" connect bash -c "export HTTP_PROXY=nginx_proxy:8888 && export HTTPS_PROXY=nginx_proxy:8888 && \
   curl -X POST \
    \"${SERVICENOW_URL}api/now/table/incident\" \
    --user admin:\"$SERVICENOW_PASSWORD\" \
    -H 'Accept: application/json' \
    -H 'Content-Type: application/json' \
    -H 'cache-control: no-cache' \
    -d '{\"short_description\": \"This is test\"}'"

sleep 5

log "Verify we have received the data in topic-servicenow topic"
timeout 60 docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic topic-servicenow --from-beginning --max-messages 1