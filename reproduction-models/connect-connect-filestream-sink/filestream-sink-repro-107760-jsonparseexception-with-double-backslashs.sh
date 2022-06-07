#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh


# for component in producer-repro-107760
# do
#     set +e
#     log "🏗 Building jar for ${component}"
#     docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${DIR}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
#     if [ $? != 0 ]
#     then
#         logerror "ERROR: failed to build java component "
#         tail -500 /tmp/result.log
#         exit 1
#     fi
#     set -e
# done

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-107760-jsonparseexception-with-double-backslashs.yml"

#log "✨ Run the avro java producer which produces to topic a-topic-1"
#docker exec producer-repro-107760 bash -c "java ${JAVA_OPTS} -jar producer-1.0.0-jar-with-dependencies.jar"

# log "produce with kafkajs in background"
# docker exec -i client-kafkajs node /usr/src/app/producer.js > /dev/null 2>&1 &

log "Sending messages to topic a-topic-1"
cat repro-107760-payload-1.json | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic a-topic-1

OUTPUT_FILE="${CONNECT_CONTAINER_HOME_DIR}/data/ouput/file.json"

log "Creating FileStream Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
               "connector.class": "FileStreamSink",
               "topics": "a-topic-1",
               "file": "/tmp/output.json",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.json.JsonConverter",
               "value.converter.schemas.enable": "false"
          }' \
     http://localhost:8083/connectors/a-topic-1-sink/config | jq .


sleep 5

log "Verify we have received the data in file"
docker exec connect cat /tmp/output.json

log "Verify data with kafka-console-consumer"
timeout 60 docker exec connect kafka-console-consumer --bootstrap-server broker:9092 --topic a-topic-1 --from-beginning --max-messages 1
# {"xpath":"href=\\#day"}

log "Verify data with kafkacat"
docker exec kafkacat kafkacat -b broker:9092 -t a-topic-1 -o 0 -p 0 -c 1 -C -f '\nKey (%K bytes): %k\t\nValue (%S bytes): %s\nTimestamp: %T\tPartition: %p\tOffset: %o\n--\n'
# Key (-1 bytes): 
# Value (23 bytes): {"xpath":"href=\\#day"}
# Timestamp: 1654588173008        Partition: 0    Offset: 0



log "Sending messages to topic a-topic-2"
cat repro-107760-payload-2.json | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic a-topic-2

OUTPUT_FILE="${CONNECT_CONTAINER_HOME_DIR}/data/ouput/file.json"

log "Creating FileStream Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
               "connector.class": "FileStreamSink",
               "topics": "a-topic-2",
               "file": "/tmp/output.json",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.json.JsonConverter",
               "value.converter.schemas.enable": "false"
          }' \
     http://localhost:8083/connectors/a-topic-2-sink/config | jq .


sleep 5

log "Verify we have received the data in file"
docker exec connect cat /tmp/output.json

log "Verify data with kafka-console-consumer"
timeout 60 docker exec connect kafka-console-consumer --bootstrap-server broker:9092 --topic a-topic-2 --from-beginning --max-messages 1
# {"xpath":"href=\#day"}

log "Verify data with kafkacat"
# Key (-1 bytes): 
# Value (25 bytes): {"xpath":"href=\#day"}
# Timestamp: 1654588876130        Partition: 0    Offset: 0

# [2022-06-07 09:06:40,754] ERROR [a-topic-2-sink|task-0] WorkerSinkTask{id=a-topic-2-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:206)
# org.apache.kafka.connect.errors.ConnectException: Tolerance exceeded in error handler
# 	at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndHandleError(RetryWithToleranceOperator.java:220)
# 	at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execute(RetryWithToleranceOperator.java:142)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.convertAndTransformRecord(WorkerSinkTask.java:519)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.convertMessages(WorkerSinkTask.java:494)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:333)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
# 	at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)
# 	at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)
# 	at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
# 	at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.apache.kafka.connect.errors.DataException: Converting byte[] to Kafka Connect data failed due to serialization error: 
# 	at org.apache.kafka.connect.json.JsonConverter.toConnectData(JsonConverter.java:324)
# 	at org.apache.kafka.connect.storage.Converter.toConnectData(Converter.java:87)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.convertValue(WorkerSinkTask.java:563)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.lambda$convertAndTransformRecord$5(WorkerSinkTask.java:519)
# 	at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndRetry(RetryWithToleranceOperator.java:166)
# 	at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndHandleError(RetryWithToleranceOperator.java:200)
# 	... 13 more
# Caused by: org.apache.kafka.common.errors.SerializationException: com.fasterxml.jackson.core.JsonParseException: Unrecognized character escape '#' (code 35)
#  at [Source: (byte[])"{"xpath":"href=\#day"}"; line: 1, column: 18]
# 	at org.apache.kafka.connect.json.JsonDeserializer.deserialize(JsonDeserializer.java:66)
# 	at org.apache.kafka.connect.json.JsonConverter.toConnectData(JsonConverter.java:322)
# 	... 18 more
# Caused by: com.fasterxml.jackson.core.JsonParseException: Unrecognized character escape '#' (code 35)
#  at [Source: (byte[])"{"xpath":"href=\#day"}"; line: 1, column: 18]
# 	at com.fasterxml.jackson.core.JsonParser._constructError(JsonParser.java:2337)
# 	at com.fasterxml.jackson.core.base.ParserMinimalBase._reportError(ParserMinimalBase.java:710)
# 	at com.fasterxml.jackson.core.base.ParserBase._handleUnrecognizedCharacterEscape(ParserBase.java:1078)
# 	at com.fasterxml.jackson.core.json.UTF8StreamJsonParser._decodeEscaped(UTF8StreamJsonParser.java:3310)
# 	at com.fasterxml.jackson.core.json.UTF8StreamJsonParser._finishString2(UTF8StreamJsonParser.java:2516)
# 	at com.fasterxml.jackson.core.json.UTF8StreamJsonParser._finishAndReturnString(UTF8StreamJsonParser.java:2471)
# 	at com.fasterxml.jackson.core.json.UTF8StreamJsonParser.getText(UTF8StreamJsonParser.java:302)
# 	at com.fasterxml.jackson.databind.deser.std.BaseNodeDeserializer.deserializeObject(JsonNodeDeserializer.java:286)
# 	at com.fasterxml.jackson.databind.deser.std.JsonNodeDeserializer.deserialize(JsonNodeDeserializer.java:69)
# 	at com.fasterxml.jackson.databind.deser.std.JsonNodeDeserializer.deserialize(JsonNodeDeserializer.java:16)
# 	at com.fasterxml.jackson.databind.deser.DefaultDeserializationContext.readRootValue(DefaultDeserializationContext.java:322)
# 	at com.fasterxml.jackson.databind.ObjectMapper._readTreeAndClose(ObjectMapper.java:4635)
# 	at com.fasterxml.jackson.databind.ObjectMapper.readTree(ObjectMapper.java:3056)
# 	at org.apache.kafka.connect.json.JsonDeserializer.deserialize(JsonDeserializer.java:64)
# 	... 19 more

     #  "tasks": [
     #    {
     #      "id": 0,
     #      "state": "FAILED",
     #      "worker_id": "connect:8083",
     #      "trace": "org.apache.kafka.connect.errors.ConnectException: Tolerance exceeded in error handler\n\tat org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndHandleError(RetryWithToleranceOperator.java:220)\n\tat org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execute(RetryWithToleranceOperator.java:142)\n\tat org.apache.kafka.connect.runtime.WorkerSinkTask.convertAndTransformRecord(WorkerSinkTask.java:519)\n\tat org.apache.kafka.connect.runtime.WorkerSinkTask.convertMessages(WorkerSinkTask.java:494)\n\tat org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:333)\n\tat org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)\n\tat org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)\n\tat org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)\n\tat org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)\n\tat java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)\n\tat java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)\n\tat java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)\n\tat java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)\n\tat java.base/java.lang.Thread.run(Thread.java:829)\nCaused by: org.apache.kafka.connect.errors.DataException: Converting byte[] to Kafka Connect data failed due to serialization error: \n\tat org.apache.kafka.connect.json.JsonConverter.toConnectData(JsonConverter.java:324)\n\tat org.apache.kafka.connect.storage.Converter.toConnectData(Converter.java:87)\n\tat org.apache.kafka.connect.runtime.WorkerSinkTask.convertValue(WorkerSinkTask.java:563)\n\tat org.apache.kafka.connect.runtime.WorkerSinkTask.lambda$convertAndTransformRecord$5(WorkerSinkTask.java:519)\n\tat org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndRetry(RetryWithToleranceOperator.java:166)\n\tat org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndHandleError(RetryWithToleranceOperator.java:200)\n\t... 13 more\nCaused by: org.apache.kafka.common.errors.SerializationException: com.fasterxml.jackson.core.JsonParseException: Unrecognized character escape '#' (code 35)\n at [Source: (byte[])\"{\"xpath\":\"href=\\#day\"}\"; line: 1, column: 18]\n\tat org.apache.kafka.connect.json.JsonDeserializer.deserialize(JsonDeserializer.java:66)\n\tat org.apache.kafka.connect.json.JsonConverter.toConnectData(JsonConverter.java:322)\n\t... 18 more\nCaused by: com.fasterxml.jackson.core.JsonParseException: Unrecognized character escape '#' (code 35)\n at [Source: (byte[])\"{\"xpath\":\"href=\\#day\"}\"; line: 1, column: 18]\n\tat com.fasterxml.jackson.core.JsonParser._constructError(JsonParser.java:2337)\n\tat com.fasterxml.jackson.core.base.ParserMinimalBase._reportError(ParserMinimalBase.java:710)\n\tat com.fasterxml.jackson.core.base.ParserBase._handleUnrecognizedCharacterEscape(ParserBase.java:1078)\n\tat com.fasterxml.jackson.core.json.UTF8StreamJsonParser._decodeEscaped(UTF8StreamJsonParser.java:3310)\n\tat com.fasterxml.jackson.core.json.UTF8StreamJsonParser._finishString2(UTF8StreamJsonParser.java:2516)\n\tat com.fasterxml.jackson.core.json.UTF8StreamJsonParser._finishAndReturnString(UTF8StreamJsonParser.java:2471)\n\tat com.fasterxml.jackson.core.json.UTF8StreamJsonParser.getText(UTF8StreamJsonParser.java:302)\n\tat com.fasterxml.jackson.databind.deser.std.BaseNodeDeserializer.deserializeObject(JsonNodeDeserializer.java:286)\n\tat com.fasterxml.jackson.databind.deser.std.JsonNodeDeserializer.deserialize(JsonNodeDeserializer.java:69)\n\tat com.fasterxml.jackson.databind.deser.std.JsonNodeDeserializer.deserialize(JsonNodeDeserializer.java:16)\n\tat com.fasterxml.jackson.databind.deser.DefaultDeserializationContext.readRootValue(DefaultDeserializationContext.java:322)\n\tat com.fasterxml.jackson.databind.ObjectMapper._readTreeAndClose(ObjectMapper.java:4635)\n\tat com.fasterxml.jackson.databind.ObjectMapper.readTree(ObjectMapper.java:3056)\n\tat org.apache.kafka.connect.json.JsonDeserializer.deserialize(JsonDeserializer.java:64)\n\t... 19 more\n"
     #    }
     #  ],

log "Sending messages to topic a-topic-3"
cat repro-107760-payload-3.json | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic a-topic-3

OUTPUT_FILE="${CONNECT_CONTAINER_HOME_DIR}/data/ouput/file.json"

log "Creating FileStream Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
               "connector.class": "FileStreamSink",
               "topics": "a-topic-3",
               "file": "/tmp/output.json",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.json.JsonConverter",
               "value.converter.schemas.enable": "false"
          }' \
     http://localhost:8083/connectors/a-topic-3-sink/config | jq .


sleep 5

log "Verify we have received the data in file"
docker exec connect cat /tmp/output.json

log "Verify data with kafka-console-consumer"
timeout 60 docker exec connect kafka-console-consumer --bootstrap-server broker:9092 --topic a-topic-3 --from-beginning --max-messages 1
# {"xpath":"href=\\#day}

log "Verify data with kafkacat"
docker exec kafkacat kafkacat -b broker:9092 -t a-topic-3 -o 0 -p 0 -c 1 -C -f '\nKey (%K bytes): %k\t\nValue (%S bytes): %s\nTimestamp: %T\tPartition: %p\tOffset: %o\n--\n'
# Key (-1 bytes): 
# Value (24 bytes): {"xpath":"href=\\#day}
# Timestamp: 1654588889732        Partition: 0    Offset: 0

# [2022-06-07 09:06:53,580] ERROR [a-topic-3-sink|task-0] WorkerSinkTask{id=a-topic-3-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:206)
# org.apache.kafka.connect.errors.ConnectException: Tolerance exceeded in error handler
# 	at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndHandleError(RetryWithToleranceOperator.java:220)
# 	at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execute(RetryWithToleranceOperator.java:142)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.convertAndTransformRecord(WorkerSinkTask.java:519)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.convertMessages(WorkerSinkTask.java:494)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:333)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
# 	at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)
# 	at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)
# 	at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
# 	at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.apache.kafka.connect.errors.DataException: Converting byte[] to Kafka Connect data failed due to serialization error: 
# 	at org.apache.kafka.connect.json.JsonConverter.toConnectData(JsonConverter.java:324)
# 	at org.apache.kafka.connect.storage.Converter.toConnectData(Converter.java:87)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.convertValue(WorkerSinkTask.java:563)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.lambda$convertAndTransformRecord$5(WorkerSinkTask.java:519)
# 	at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndRetry(RetryWithToleranceOperator.java:166)
# 	at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndHandleError(RetryWithToleranceOperator.java:200)
# 	... 13 more
# Caused by: org.apache.kafka.common.errors.SerializationException: com.fasterxml.jackson.core.io.JsonEOFException: Unexpected end-of-input in VALUE_STRING
#  at [Source: (byte[])"{"xpath":"href=\\#day}"; line: 1, column: 23]
# 	at org.apache.kafka.connect.json.JsonDeserializer.deserialize(JsonDeserializer.java:66)
# 	at org.apache.kafka.connect.json.JsonConverter.toConnectData(JsonConverter.java:322)
# 	... 18 more
# Caused by: com.fasterxml.jackson.core.io.JsonEOFException: Unexpected end-of-input in VALUE_STRING
#  at [Source: (byte[])"{"xpath":"href=\\#day}"; line: 1, column: 23]
# 	at com.fasterxml.jackson.core.base.ParserMinimalBase._reportInvalidEOF(ParserMinimalBase.java:662)
# 	at com.fasterxml.jackson.core.base.ParserMinimalBase._reportInvalidEOF(ParserMinimalBase.java:639)
# 	at com.fasterxml.jackson.core.json.UTF8StreamJsonParser._loadMoreGuaranteed(UTF8StreamJsonParser.java:2406)
# 	at com.fasterxml.jackson.core.json.UTF8StreamJsonParser._finishString2(UTF8StreamJsonParser.java:2491)
# 	at com.fasterxml.jackson.core.json.UTF8StreamJsonParser._finishAndReturnString(UTF8StreamJsonParser.java:2471)
# 	at com.fasterxml.jackson.core.json.UTF8StreamJsonParser.getText(UTF8StreamJsonParser.java:302)
# 	at com.fasterxml.jackson.databind.deser.std.BaseNodeDeserializer.deserializeObject(JsonNodeDeserializer.java:286)
# 	at com.fasterxml.jackson.databind.deser.std.JsonNodeDeserializer.deserialize(JsonNodeDeserializer.java:69)
# 	at com.fasterxml.jackson.databind.deser.std.JsonNodeDeserializer.deserialize(JsonNodeDeserializer.java:16)
# 	at com.fasterxml.jackson.databind.deser.DefaultDeserializationContext.readRootValue(DefaultDeserializationContext.java:322)
# 	at com.fasterxml.jackson.databind.ObjectMapper._readTreeAndClose(ObjectMapper.java:4635)
# 	at com.fasterxml.jackson.databind.ObjectMapper.readTree(ObjectMapper.java:3056)
# 	at org.apache.kafka.connect.json.JsonDeserializer.deserialize(JsonDeserializer.java:64)
# 	... 19 more

     #  "tasks": [
     #    {
     #      "id": 0,
     #      "state": "FAILED",
     #      "worker_id": "connect:8083",
     #      "trace": "org.apache.kafka.connect.errors.ConnectException: Tolerance exceeded in error handler\n\tat org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndHandleError(RetryWithToleranceOperator.java:220)\n\tat org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execute(RetryWithToleranceOperator.java:142)\n\tat org.apache.kafka.connect.runtime.WorkerSinkTask.convertAndTransformRecord(WorkerSinkTask.java:519)\n\tat org.apache.kafka.connect.runtime.WorkerSinkTask.convertMessages(WorkerSinkTask.java:494)\n\tat org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:333)\n\tat org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)\n\tat org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)\n\tat org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)\n\tat org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)\n\tat java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)\n\tat java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)\n\tat java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)\n\tat java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)\n\tat java.base/java.lang.Thread.run(Thread.java:829)\nCaused by: org.apache.kafka.connect.errors.DataException: Converting byte[] to Kafka Connect data failed due to serialization error: \n\tat org.apache.kafka.connect.json.JsonConverter.toConnectData(JsonConverter.java:324)\n\tat org.apache.kafka.connect.storage.Converter.toConnectData(Converter.java:87)\n\tat org.apache.kafka.connect.runtime.WorkerSinkTask.convertValue(WorkerSinkTask.java:563)\n\tat org.apache.kafka.connect.runtime.WorkerSinkTask.lambda$convertAndTransformRecord$5(WorkerSinkTask.java:519)\n\tat org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndRetry(RetryWithToleranceOperator.java:166)\n\tat org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndHandleError(RetryWithToleranceOperator.java:200)\n\t... 13 more\nCaused by: org.apache.kafka.common.errors.SerializationException: com.fasterxml.jackson.core.io.JsonEOFException: Unexpected end-of-input in VALUE_STRING\n at [Source: (byte[])\"{\"xpath\":\"href=\\\\#day}\"; line: 1, column: 23]\n\tat org.apache.kafka.connect.json.JsonDeserializer.deserialize(JsonDeserializer.java:66)\n\tat org.apache.kafka.connect.json.JsonConverter.toConnectData(JsonConverter.java:322)\n\t... 18 more\nCaused by: com.fasterxml.jackson.core.io.JsonEOFException: Unexpected end-of-input in VALUE_STRING\n at [Source: (byte[])\"{\"xpath\":\"href=\\\\#day}\"; line: 1, column: 23]\n\tat com.fasterxml.jackson.core.base.ParserMinimalBase._reportInvalidEOF(ParserMinimalBase.java:662)\n\tat com.fasterxml.jackson.core.base.ParserMinimalBase._reportInvalidEOF(ParserMinimalBase.java:639)\n\tat com.fasterxml.jackson.core.json.UTF8StreamJsonParser._loadMoreGuaranteed(UTF8StreamJsonParser.java:2406)\n\tat com.fasterxml.jackson.core.json.UTF8StreamJsonParser._finishString2(UTF8StreamJsonParser.java:2491)\n\tat com.fasterxml.jackson.core.json.UTF8StreamJsonParser._finishAndReturnString(UTF8StreamJsonParser.java:2471)\n\tat com.fasterxml.jackson.core.json.UTF8StreamJsonParser.getText(UTF8StreamJsonParser.java:302)\n\tat com.fasterxml.jackson.databind.deser.std.BaseNodeDeserializer.deserializeObject(JsonNodeDeserializer.java:286)\n\tat com.fasterxml.jackson.databind.deser.std.JsonNodeDeserializer.deserialize(JsonNodeDeserializer.java:69)\n\tat com.fasterxml.jackson.databind.deser.std.JsonNodeDeserializer.deserialize(JsonNodeDeserializer.java:16)\n\tat com.fasterxml.jackson.databind.deser.DefaultDeserializationContext.readRootValue(DefaultDeserializationContext.java:322)\n\tat com.fasterxml.jackson.databind.ObjectMapper._readTreeAndClose(ObjectMapper.java:4635)\n\tat com.fasterxml.jackson.databind.ObjectMapper.readTree(ObjectMapper.java:3056)\n\tat org.apache.kafka.connect.json.JsonDeserializer.deserialize(JsonDeserializer.java:64)\n\t... 19 more\n"
     #    }
     #  ],