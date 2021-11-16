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

log "Make sure to execute steps in https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-servicenow-source/repro-connector-not-progressing/repro-connector-not-progressing.md before running this test"

log "Once done, type to continue"
check_if_continue


${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-proxy.yml"

export HTTP_PROXY=127.0.0.1:8888
export HTTPS_PROXY=127.0.0.1:8888
log "Verify forward proxy is working correctly"
curl --compressed -H 'Accept-Encoding: gzip' -H 'Content-Type: application/json' -H 'User-Agent: Google-HTTP-Java-Client/1.30.0 (gzip)' -v ${SERVICENOW_URL}api/now/table/incident?sysparm_limit=1 -u "admin:$SERVICENOW_PASSWORD" | jq .

docker exec -e SERVICENOW_URL=$SERVICENOW_URL -e SERVICENOW_PASSWORD=$SERVICENOW_PASSWORD connect bash -c "export HTTP_PROXY=nginx-proxy:8888 && export HTTPS_PROXY=nginx-proxy:8888 && curl --compressed -H 'Accept-Encoding: gzip' -H 'User-Agent: Google-HTTP-Java-Client/1.30.0 (gzip)' -v ${SERVICENOW_URL}api/now/table/incident?sysparm_limit=1 -u \"admin:$SERVICENOW_PASSWORD\""

curl --request PUT \
  --url http://localhost:8083/admin/loggers/io.confluent.connect.servicenow \
  --header 'Accept: application/json' \
  --header 'Content-Type: application/json' \
  --data '{
	"level": "TRACE"
}'

TODAY=$(date '+%Y-%m-%d')
log "Creating ServiceNow Source connector, with batch.max.rows=10"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                    "connector.class": "io.confluent.connect.servicenow.ServiceNowSourceConnector",
                    "kafka.topic": "topic-servicenow",
                    "proxy.url": "nginx-proxy:8888",
                    "servicenow.url": "'"$SERVICENOW_URL"'",
                    "tasks.max": "1",
                    "servicenow.table": "incident",
                    "servicenow.user": "admin",
                    "servicenow.password": "'"$SERVICENOW_PASSWORD"'",
                    "servicenow.since": "'"$TODAY"'",
                    "batch.max.rows": 10,
                    "retry.max.times": "5",
                    "poll.interval.s": "60",
                    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/servicenow-source2/config | jq .


log "Verify we have received the data in topic-servicenow topic"
timeout 60 docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic topic-servicenow