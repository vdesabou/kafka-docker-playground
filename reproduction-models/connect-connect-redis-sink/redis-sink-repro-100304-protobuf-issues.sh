#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

for component in producer-repro-100304
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

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-100304-protobuf-issues.yml"

log "✨ Run the protobuf java producer which produces to topic customer_protobuf"
docker exec producer-repro-100304 bash -c "java ${JAVA_OPTS} -jar producer-1.0.0-jar-with-dependencies.jar"

log "Creating Redis sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                "connector.class": "com.github.jcustenborder.kafka.connect.redis.RedisSinkConnector",
                "redis.hosts": "redis:6379",
                "tasks.max": "1",
                "key.converter":"org.apache.kafka.connect.storage.StringConverter",
                "value.converter": "io.confluent.connect.protobuf.ProtobufConverter",
                "value.converter.schema.registry.url": "http://schema-registry:8081",
                "topics": "customer_protobuf"
          }' \
     http://localhost:8083/connectors/redis-sink/config | jq .

sleep 10


# [2022-04-14 20:09:18,452] ERROR [redis-sink|task-0] WorkerSinkTask{id=redis-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:206)
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
# Caused by: org.apache.kafka.connect.errors.DataException: The value for the record must be String or Bytes. Consider using the ByteArrayConverter or StringConverter if the data is stored in Kafka in the format needed in Redis. Another option is to use a single message transformation to transform the data before it is written to Redis.
#         at com.github.jcustenborder.kafka.connect.redis.RedisSinkTask.toBytes(RedisSinkTask.java:120)
#         at com.github.jcustenborder.kafka.connect.redis.RedisSinkTask.put(RedisSinkTask.java:165)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:604)
#         ... 10 more

log "Verify data is in Redis"
docker exec -i redis redis-cli COMMAND GETKEYS "MSET" "key1" "value1" "key2" "value2" "key3" "value3"
docker exec -i redis redis-cli COMMAND GETKEYS "MSET" "__kafka.offset.customer_protobuf.0" "{\"topic\":\"customer_protobuf\",\"partition\":0,\"offset\":2}" > /tmp/result.log  2>&1
cat /tmp/result.log
grep "__kafka.offset.customer_protobuf.0" /tmp/result.log