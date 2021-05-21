#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

# schema
# {
#     "fields": [
#         {
#             "name": "field1",
#             "type": "string"
#         },
#         {
#             "default": {
#                 "Currency": "EUR",
#                 "Value": 0
#             },
#             "doc": "field with a default value",
#             "name": "field2",
#             "type": {
#                 "fields": [
#                     {
#                         "name": "Value",
#                         "type": "float"
#                     },
#                     {
#                         "name": "Currency",
#                         "type": {
#                             "avro.java.string": "String",
#                             "type": "string"
#                         }
#                     }
#                 ],
#                 "name": "subfield2",
#                 "type": "record"
#             }
#         }
#     ],
#     "name": "MyRecord",
#     "namespace": "mynamespace",
#     "type": "record",
#     "version": 1
# }


log "Send message to topic myavrotopic1"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic myavrotopic1 --property value.schema='{"fields":[{"name":"field1","type":"string"},{"default":{"Currency":"EUR","Value":0},"doc":"field with a default value","name":"field2","type":{"fields":[{"name":"Value","type":"float"},{"name":"Currency","type":{"avro.java.string":"String","type":"string"}}],"name":"subfield2","type":"record"}}],"name":"MyRecord","namespace":"mynamespace","type":"record","version":1}' << EOF
{"field1":"OOm","field2":{"Value":0.6223695,"Currency":"aa"}}
{"field1":"OOt"}
EOF

# for second message:

# org.apache.kafka.common.errors.SerializationException: Error deserializing json {"field1":"OOt"} to Avro of schema {"type":"record","name":"MyRecord","namespace":"mynamespace","fields":[{"name":"field1","type":"string"},{"name":"field2","type":{"type":"record","name":"subfield2","fields":[{"name":"Value","type":"float"},{"name":"Currency","type":{"type":"string","avro.java.string":"String"}}]},"doc":"field with a default value","default":{"Currency":"EUR","Value":0}}],"version":1}
# Caused by: org.apache.avro.AvroTypeException: Expected record-start. Got END_OBJECT
#         at org.apache.avro.io.JsonDecoder.error(JsonDecoder.java:514)
#         at org.apache.avro.io.JsonDecoder.doAction(JsonDecoder.java:489)
#         at org.apache.avro.io.parsing.Parser.advance(Parser.java:86)
#         at org.apache.avro.io.JsonDecoder.advance(JsonDecoder.java:135)
#         at org.apache.avro.io.JsonDecoder.readFloat(JsonDecoder.java:186)
#         at org.apache.avro.io.ResolvingDecoder.readFloat(ResolvingDecoder.java:183)
#         at org.apache.avro.generic.GenericDatumReader.readWithoutConversion(GenericDatumReader.java:199)
#         at org.apache.avro.generic.GenericDatumReader.read(GenericDatumReader.java:160)
#         at org.apache.avro.generic.GenericDatumReader.readField(GenericDatumReader.java:259)
#         at org.apache.avro.generic.GenericDatumReader.readRecord(GenericDatumReader.java:247)
#         at org.apache.avro.generic.GenericDatumReader.readWithoutConversion(GenericDatumReader.java:179)
#         at org.apache.avro.generic.GenericDatumReader.read(GenericDatumReader.java:160)
#         at org.apache.avro.generic.GenericDatumReader.readField(GenericDatumReader.java:259)
#         at org.apache.avro.generic.GenericDatumReader.readRecord(GenericDatumReader.java:247)
#         at org.apache.avro.generic.GenericDatumReader.readWithoutConversion(GenericDatumReader.java:179)
#         at org.apache.avro.generic.GenericDatumReader.read(GenericDatumReader.java:160)
#         at org.apache.avro.generic.GenericDatumReader.read(GenericDatumReader.java:153)
#         at io.confluent.kafka.schemaregistry.avro.AvroSchemaUtils.toObject(AvroSchemaUtils.java:178)
#         at io.confluent.kafka.formatter.AvroMessageReader.readFrom(AvroMessageReader.java:121)
#         at io.confluent.kafka.formatter.SchemaMessageReader.readMessage(SchemaMessageReader.java:316)
#         at kafka.tools.ConsoleProducer$.main(ConsoleProducer.scala:51)
#         at kafka.tools.ConsoleProducer.main(ConsoleProducer.scala)

curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "topics": "myavrotopic1",
          "tasks.max": "1",
          "connector.class": "io.confluent.connect.http.HttpSinkConnector",
          "key.converter": "org.apache.kafka.connect.storage.StringConverter",
          "value.converter": "io.confluent.connect.avro.AvroConverter",
          "value.converter.schema.registry.url": "http://schema-registry:8081",
          "value.converter.enhanced.avro.schema.support": "true",
          "confluent.topic.bootstrap.servers": "broker:9092",
          "confluent.topic.replication.factor": "1",
          "reporter.bootstrap.servers": "broker:9092",
          "reporter.error.topic.name": "error-responses",
          "reporter.error.topic.replication.factor": 1,
          "reporter.result.topic.name": "success-responses",
          "reporter.result.topic.replication.factor": 1,
          "http.api.url": "http://http-service-basic-auth:8080/api/messages",
          "request.body.format": "json",
          "auth.type": "BASIC",
          "connection.user": "admin",
          "connection.password": "password"
          }' \
     http://localhost:8083/connectors/http-sink-1/config | jq .

sleep 4

curl localhost:8083/connectors/http-sink-1/status | jq

# [2021-05-21 08:39:28,830] ERROR WorkerSinkTask{id=http-sink-1-0} Error converting message value in topic 'myavrotopic1' partition 0 at offset 0 and timestamp 1621586362911: Found null value for non-optional schema (org.apache.kafka.connect.runtime.WorkerSinkTask)
# org.apache.kafka.connect.errors.DataException: Found null value for non-optional schema
#         at io.confluent.connect.avro.AvroData.validateSchemaValue(AvroData.java:1177)
#         at io.confluent.connect.avro.AvroData.toConnectData(AvroData.java:1231)
#         at io.confluent.connect.avro.AvroData.toConnectData(AvroData.java:1226)
#         at io.confluent.connect.avro.AvroData.toConnectData(AvroData.java:1474)
#         at io.confluent.connect.avro.AvroData.defaultValueFromAvroWithoutLogical(AvroData.java:1902)
#         at io.confluent.connect.avro.AvroData.defaultValueFromAvro(AvroData.java:1885)
#         at io.confluent.connect.avro.AvroData.toConnectSchema(AvroData.java:1818)
#         at io.confluent.connect.avro.AvroData.toConnectSchema(AvroData.java:1562)
#         at io.confluent.connect.avro.AvroData.toConnectSchema(AvroData.java:1687)
#         at io.confluent.connect.avro.AvroData.toConnectSchema(AvroData.java:1538)
#         at io.confluent.connect.avro.AvroData.toConnectData(AvroData.java:1221)
#         at io.confluent.connect.avro.AvroConverter.toConnectData(AvroConverter.java:115)
#         at org.apache.kafka.connect.storage.Converter.toConnectData(Converter.java:87)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.convertValue(WorkerSinkTask.java:545)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.lambda$convertAndTransformRecord$1(WorkerSinkTask.java:501)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndRetry(RetryWithToleranceOperator.java:156)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndHandleError(RetryWithToleranceOperator.java:190)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execute(RetryWithToleranceOperator.java:132)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.convertAndTransformRecord(WorkerSinkTask.java:501)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.convertMessages(WorkerSinkTask.java:478)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:328)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:232)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:201)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:189)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:238)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
