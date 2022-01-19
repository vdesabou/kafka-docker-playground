#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

for component in producer-88620
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

if [ ! -f ${DIR}/mysql-connector-java-5.1.45.jar ]
then
     log "Downloading mysql-connector-java-5.1.45.jar"
     wget https://repo1.maven.org/maven2/mysql/mysql-connector-java/5.1.45/mysql-connector-java-5.1.45.jar
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-88620.yml"

log "Creating MySQL sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
               "tasks.max": "1",
               "connection.url": "jdbc:mysql://mysql:3306/db?user=user&password=password&useSSL=false",
               "topics": "customer-json-schema",
               "value.converter": "io.confluent.connect.json.JsonSchemaConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "auto.create": "true"
          }' \
     http://localhost:8083/connectors/mysql-sink/config | jq .


log "Sending messages to topic customer-json-schema"
log "Produce json-schema data using Java producer"
docker exec producer-88620 bash -c "java -jar producer-88620-1.0.0-jar-with-dependencies.jar"

sleep 5

# This is causing the issue:
#     "evtTime": {
#       "items": [
#         {
#           "type": "integer"
#         },
#         {
#           "type": "integer"
#         } 
#       ],
#       "type": "array"
#     },

# [2022-01-19 15:04:02,683] ERROR [mysql-sink|task-0] WorkerSinkTask{id=mysql-sink-0} Error converting message value in topic 'customer-json-schema' partition 0 at offset 0 and timestamp 1642604461150: Unsupported schema type org.everit.json.schema.EmptySchema (org.apache.kafka.connect.runtime.WorkerSinkTask:565)
# org.apache.kafka.connect.errors.DataException: Unsupported schema type org.everit.json.schema.EmptySchema
#         at io.confluent.connect.json.JsonSchemaData.toConnectSchema(JsonSchemaData.java:1025)
#         at io.confluent.connect.json.JsonSchemaData.toConnectSchema(JsonSchemaData.java:876)
#         at io.confluent.connect.json.JsonSchemaData.toConnectSchema(JsonSchemaData.java:871)
#         at io.confluent.connect.json.JsonSchemaData.toConnectSchema(JsonSchemaData.java:984)
#         at io.confluent.connect.json.JsonSchemaData.toConnectSchema(JsonSchemaData.java:957)
#         at io.confluent.connect.json.JsonSchemaData.toConnectSchema(JsonSchemaData.java:1012)
#         at io.confluent.connect.json.JsonSchemaData.toConnectSchema(JsonSchemaData.java:859)
#         at io.confluent.connect.json.JsonSchemaConverter.toConnectData(JsonSchemaConverter.java:115)
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

log "Describing the customer-json-schema table in DB 'db':"
docker exec mysql bash -c "mysql --user=root --password=password --database=db -e 'describe orders'"

log "Show content of customer-json-schema table:"
docker exec mysql bash -c "mysql --user=root --password=password --database=db -e 'select * from orders'" > /tmp/result.log  2>&1
cat /tmp/result.log



