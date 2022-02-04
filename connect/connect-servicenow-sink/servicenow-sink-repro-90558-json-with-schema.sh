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

# if [ ! -z "$CI" ]
# then
#      # this is github actions
#      set +e
#      log "Waking up servicenow instance..."
#      docker run -e USERNAME="$SERVICENOW_DEVELOPER_USERNAME" -e PASSWORD="$SERVICENOW_DEVELOPER_PASSWORD" ruthless/servicenow-instance-wakeup:latest
#      set -e
#      wait_for_end_of_hibernation
# fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-90558-json-with-schema.yml"

#  Using JSON with schema (and key):
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic test_table --property parse.key=true --property key.separator=, << EOF
1,{"payload":{"u_price":2.75,"u_quantity":3,"u_name":"scissors"},"schema":{"fields":[{"field":"u_name","optional":false,"type":"string"},{"field":"u_price","optional":false,"type":"float"},{"field":"u_quantity","optional":false,"type":"int32"}],"type":"struct"}}
EOF

curl --request PUT \
  --url http://localhost:8083/admin/loggers/io.confluent.connect.servicenow. \
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
                    "servicenow.url": "'"$SERVICENOW_URL"'",
                    "tasks.max": "1",
                    "servicenow.table": "u_test_table",
                    "servicenow.user": "admin",
                    "servicenow.password": "'"$SERVICENOW_PASSWORD"'",
                    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "key.converter.schema.registry.url": "http://schema-registry:8081",
                    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "value.converter.schemas.enable": "true",
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
     http://localhost:8083/connectors/servicenow-sink2/config | jq .

# with "field":"u_quantity","optional":false,"type":"number"
# docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic test_table --property parse.key=true --property key.separator=, << EOF
# 1,{"payload":{"u_price":2.75,"u_quantity":3,"u_name":"scissors"},"schema":{"fields":[{"field":"u_name","optional":false,"type":"string"},{"field":"u_price","optional":false,"type":"float"},{"field":"u_quantity","optional":false,"type":"number"}],"type":"struct"}}
# EOF

# [2022-02-04 11:48:25,200] ERROR [servicenow-sink|task-0] WorkerSinkTask{id=servicenow-sink-0} Error converting message value in topic 'test_table' partition 0 at offset 0 and timestamp 1643975283347: Unknown schema type: number (org.apache.kafka.connect.runtime.WorkerSinkTask:565)
# org.apache.kafka.connect.errors.DataException: Unknown schema type: number
#         at org.apache.kafka.connect.json.JsonConverter.asConnectSchema(JsonConverter.java:497)
#         at org.apache.kafka.connect.json.JsonConverter.asConnectSchema(JsonConverter.java:493)
#         at org.apache.kafka.connect.json.JsonConverter.toConnectData(JsonConverter.java:340)
#         at org.apache.kafka.connect.storage.Converter.toConnectData(Converter.java:87)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.convertValue(WorkerSinkTask.java:563)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.lambda$convertAndTransformRecord$5(WorkerSinkTask.java:519)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndRetry(RetryWithToleranceOperator.java:166)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndHandleError(RetryWithToleranceOperator.java:200)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execute(RetryWithToleranceOperator.java:142)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.convertAndTransformRecord(WorkerSinkTask.java:519)
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