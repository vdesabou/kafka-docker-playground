#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-94747-invalid-utf-8-character.yml"

docker exec sftp-server bash -c "
mkdir -p /chroot/home/foo/upload/input
mkdir -p /chroot/home/foo/upload/error
mkdir -p /chroot/home/foo/upload/finished

chown -R foo /chroot/home/foo/upload
"

docker cp repro-94747-invalid-utf-8-character.json sftp-server:/chroot/home/foo/upload/input/

log "Creating JSON (with schema) SFTP Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "topics": "test_sftp_sink",
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.sftp.SftpJsonSourceConnector",
               "cleanup.policy":"NONE",
               "behavior.on.error":"FAIL",
               "input.path": "/home/foo/upload/input",
               "error.path": "/home/foo/upload/error",
               "finished.path": "/home/foo/upload/finished",
               "input.file.pattern": "repro-94747-invalid-utf-8-character.json",
               "sftp.username":"foo",
               "sftp.password":"pass",
               "sftp.host":"sftp-server",
               "sftp.port":"22",
               "kafka.topic": "sftp-testing-topic",
               "key.schema": "{\"name\" : \"Key\",\"type\" : \"STRUCT\",\"isOptional\" : true,\"fieldSchemas\" : {\"id\":{\"type\":\"INT64\",\"isOptional\":true} }}",
               "value.schema": "{\"name\":\"bill\",\"type\":\"STRUCT\",\"isOptional\":true,\"fieldSchemas\":{\"ActionType\":{\"type\":\"STRING\",\"isOptional\":true},\"KeyRecord\":{\"type\":\"STRING\",\"isOptional\":true},\"InsuredName\":{\"type\":\"STRING\",\"isOptional\":true}}}"
          }' \
     http://localhost:8083/connectors/sftp-source/config | jq .

sleep 5

# [2022-03-02 16:38:37,545] ERROR [sftp-source|task-0] WorkerSourceTask{id=sftp-source-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:206)
# org.apache.kafka.connect.errors.ConnectException: Error occurred, throwing exception for behavior.on.error=FAIL : 
#         at io.confluent.connect.sftp.source.AbstractSftpSourceTask.read(AbstractSftpSourceTask.java:304)
#         at io.confluent.connect.sftp.source.AbstractSftpSourceTask.poll(AbstractSftpSourceTask.java:172)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.poll(WorkerSourceTask.java:308)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.execute(WorkerSourceTask.java:263)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: java.lang.RuntimeException: Invalid UTF-8 middle byte 0x20
#  at [Source: (com.jcraft.jsch.ChannelSftp$2); line: 2, column: 68]
#         at com.fasterxml.jackson.databind.MappingIterator._handleIOException(MappingIterator.java:417)
#         at com.fasterxml.jackson.databind.MappingIterator.next(MappingIterator.java:203)
#         at com.google.common.collect.ImmutableCollection$Builder.addAll(ImmutableCollection.java:467)
#         at com.google.common.collect.ImmutableList$Builder.addAll(ImmutableList.java:854)
#         at com.google.common.collect.ImmutableList.copyOf(ImmutableList.java:276)
#         at io.confluent.connect.sftp.source.SftpJsonSourceTask.configure(SftpJsonSourceTask.java:84)
#         at io.confluent.connect.sftp.source.AbstractSftpSourceTask.read(AbstractSftpSourceTask.java:265)
#         ... 10 more
# Caused by: com.fasterxml.jackson.core.JsonParseException: Invalid UTF-8 middle byte 0x20
#  at [Source: (com.jcraft.jsch.ChannelSftp$2); line: 2, column: 68]
#         at com.fasterxml.jackson.core.JsonParser._constructError(JsonParser.java:1840)
#         at com.fasterxml.jackson.core.base.ParserMinimalBase._reportError(ParserMinimalBase.java:712)
#         at com.fasterxml.jackson.core.json.UTF8StreamJsonParser._reportInvalidOther(UTF8StreamJsonParser.java:3577)
#         at com.fasterxml.jackson.core.json.UTF8StreamJsonParser._reportInvalidOther(UTF8StreamJsonParser.java:3584)
#         at com.fasterxml.jackson.core.json.UTF8StreamJsonParser._decodeUtf8_3fast(UTF8StreamJsonParser.java:3389)
#         at com.fasterxml.jackson.core.json.UTF8StreamJsonParser._finishString2(UTF8StreamJsonParser.java:2490)
#         at com.fasterxml.jackson.core.json.UTF8StreamJsonParser._finishAndReturnString(UTF8StreamJsonParser.java:2438)
#         at com.fasterxml.jackson.core.json.UTF8StreamJsonParser.getText(UTF8StreamJsonParser.java:294)
#         at com.fasterxml.jackson.databind.deser.std.BaseNodeDeserializer.deserializeObject(JsonNodeDeserializer.java:267)
#         at com.fasterxml.jackson.databind.deser.std.JsonNodeDeserializer.deserialize(JsonNodeDeserializer.java:68)
#         at com.fasterxml.jackson.databind.deser.std.JsonNodeDeserializer.deserialize(JsonNodeDeserializer.java:15)
#         at com.fasterxml.jackson.databind.MappingIterator.nextValue(MappingIterator.java:280)
#         at com.fasterxml.jackson.databind.MappingIterator.next(MappingIterator.java:199)
#         ... 15 more

log "Verifying topic sftp-testing-topic"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic sftp-testing-topic --from-beginning --max-messages 2