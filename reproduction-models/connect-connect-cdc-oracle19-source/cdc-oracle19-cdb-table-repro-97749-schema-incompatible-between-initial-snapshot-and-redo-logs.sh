#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

create_or_get_oracle_image "LINUX.X64_193000_db_home.zip" "../../connect/connect-cdc-oracle19-source/ora-setup-scripts-cdb-table"

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.cdb-table.repro-97749-schema-incompatible-between-initial-snapshot-and-redo-logs.yml"


# Verify Oracle DB has started within MAX_WAIT seconds
MAX_WAIT=2500
CUR_WAIT=0
log "⌛ Waiting up to $MAX_WAIT seconds for Oracle DB to start"
docker container logs oracle > /tmp/out.txt 2>&1
while [[ ! $(cat /tmp/out.txt) =~ "DONE: Executing user defined scripts" ]]; do
sleep 10
docker container logs oracle > /tmp/out.txt 2>&1
CUR_WAIT=$(( CUR_WAIT+10 ))
if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
     logerror "ERROR: The logs in oracle container do not show 'DONE: Executing user defined scripts' after $MAX_WAIT seconds. Please troubleshoot with 'docker container ps' and 'docker container logs'.\n"
     exit 1
fi
done
log "Oracle DB has started!"
sleep 10

# Create a redo-log-topic. Please make sure you create a topic with the same name you will use for "redo.log.topic.name": "redo-log-topic"
# CC-13104
docker exec connect kafka-topics --create --topic redo-log-topic --bootstrap-server broker:9092 --replication-factor 1 --partitions 1 --config cleanup.policy=delete --config retention.ms=120960000
log "redo-log-topic is created"
sleep 5

# log "workaround: set compatibility to NONE"
# curl -X PUT -H "Content-Type: application/vnd.schemaregistry.v1+json" --data '{"compatibility": "NONE"}' http://localhost:8081/config/ORCLCDB.C__MYUSER.CUSTOMERS-value

log "Creating Oracle source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.oracle.cdc.OracleCdcSourceConnector",
               "tasks.max":2,
               "key.converter": "io.confluent.connect.avro.AvroConverter",
               "key.converter.schema.registry.url": "http://schema-registry:8081",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "oracle.server": "oracle",
               "oracle.port": 1521,
               "oracle.sid": "ORCLCDB",
               "oracle.username": "C##MYUSER",
               "oracle.password": "mypassword",
               "start.from":"snapshot",
               "redo.log.topic.name": "redo-log-topic",
               "redo.log.consumer.bootstrap.servers":"broker:9092",
               "table.inclusion.regex": ".*CUSTOMERS.*",
               "table.topic.name.template": "${databaseName}.${schemaName}.${tableName}",
               "numeric.mapping": "best_fit",
               "connection.pool.max.size": 20,
               "redo.log.row.fetch.size":1,
               "oracle.dictionary.mode": "auto",
               "output.op.ts.field": "",
               "output.current.ts.field": ""
          }' \
     http://localhost:8083/connectors/cdc-oracle-source-cdb/config | jq .

log "Waiting 20s for connector to read existing data"
sleep 20

docker exec -i oracle sqlplus C\#\#MYUSER/mypassword@//localhost:1521/ORCLCDB << EOF
  insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments, TATXA1, TAITM, TAEFDJ) values ('Rica2', 'Blaisdel2', 'rblaisdell20@rambler.ru', 'Female2', 'bronze2', 'Universal optimal hierarchy2', 'TATXA12', 2, 3);
  exit;
EOF

# [2022-03-22 10:02:37,589] ERROR [cdc-oracle-source-cdb|task-1] WorkerSourceTask{id=cdc-oracle-source-cdb-1} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:206)
# org.apache.kafka.connect.errors.ConnectException: Tolerance exceeded in error handler
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndHandleError(RetryWithToleranceOperator.java:220)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execute(RetryWithToleranceOperator.java:142)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.convertTransformedRecord(WorkerSourceTask.java:333)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.sendRecords(WorkerSourceTask.java:359)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.execute(WorkerSourceTask.java:272)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.apache.kafka.connect.errors.DataException: Failed to serialize Avro data from topic ORCLCDB.C__MYUSER.CUSTOMERS :
#         at io.confluent.connect.avro.AvroConverter.fromConnectData(AvroConverter.java:93)
#         at org.apache.kafka.connect.storage.Converter.fromConnectData(Converter.java:63)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.lambda$convertTransformedRecord$4(WorkerSourceTask.java:333)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndRetry(RetryWithToleranceOperator.java:166)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndHandleError(RetryWithToleranceOperator.java:200)
#         ... 11 more
# Caused by: org.apache.kafka.common.errors.SerializationException: Error registering Avro schema{"type":"record","name":"ConnectDefault","namespace":"io.confluent.connect.avro","fields":[{"name":"TATXA1","type":"string"},{"name":"TAITM","type":"double"},{"name":"TAEFDJ","type":"int"},{"name":"FIRST_NAME","type":["null","string"],"default":null},{"name":"LAST_NAME","type":["null","string"],"default":null},{"name":"EMAIL","type":["null","string"],"default":null},{"name":"GENDER","type":["null","string"],"default":null},{"name":"CLUB_STATUS","type":["null","string"],"default":null},{"name":"COMMENTS","type":["null","string"],"default":null},{"name":"CREATE_TS","type":["null",{"type":"long","connect.version":1,"connect.name":"org.apache.kafka.connect.data.Timestamp","logicalType":"timestamp-millis"}],"default":null},{"name":"UPDATE_TS","type":["null",{"type":"long","connect.version":1,"connect.name":"org.apache.kafka.connect.data.Timestamp","logicalType":"timestamp-millis"}],"default":null},{"name":"table","type":["null","string"],"default":null},{"name":"scn","type":["null","string"],"default":null},{"name":"op_type","type":["null","string"],"default":null},{"name":"op_ts","type":["null","string"],"default":null},{"name":"current_ts","type":["null","string"],"default":null},{"name":"row_id","type":["null","string"],"default":null},{"name":"username","type":["null","string"],"default":null}]}
#         at io.confluent.kafka.serializers.AbstractKafkaSchemaSerDe.toKafkaException(AbstractKafkaSchemaSerDe.java:259)
#         at io.confluent.kafka.serializers.AbstractKafkaAvroSerializer.serializeImpl(AbstractKafkaAvroSerializer.java:156)
#         at io.confluent.connect.avro.AvroConverter$Serializer.serialize(AvroConverter.java:153)
#         at io.confluent.connect.avro.AvroConverter.fromConnectData(AvroConverter.java:86)
#         ... 15 more
# Caused by: io.confluent.kafka.schemaregistry.client.rest.exceptions.RestClientException: Schema being registered is incompatible with an earlier schema for subject "ORCLCDB.C__MYUSER.CUSTOMERS-value"; error code: 409
#         at io.confluent.kafka.schemaregistry.client.rest.RestService.sendHttpRequest(RestService.java:297)
#         at io.confluent.kafka.schemaregistry.client.rest.RestService.httpRequest(RestService.java:367)
#         at io.confluent.kafka.schemaregistry.client.rest.RestService.registerSchema(RestService.java:544)
#         at io.confluent.kafka.schemaregistry.client.rest.RestService.registerSchema(RestService.java:532)
#         at io.confluent.kafka.schemaregistry.client.rest.RestService.registerSchema(RestService.java:490)
#         at io.confluent.kafka.schemaregistry.client.CachedSchemaRegistryClient.registerAndGetId(CachedSchemaRegistryClient.java:257)
#         at io.confluent.kafka.schemaregistry.client.CachedSchemaRegistryClient.register(CachedSchemaRegistryClient.java:366)
#         at io.confluent.kafka.schemaregistry.client.CachedSchemaRegistryClient.register(CachedSchemaRegistryClient.java:337)
#         at io.confluent.kafka.serializers.AbstractKafkaAvroSerializer.serializeImpl(AbstractKafkaAvroSerializer.java:115)
#         ... 17 more

log "Waiting 20s for connector to read new data"
sleep 20

log "Verifying topic ORCLCDB.C__MYUSER.CUSTOMERS: there should be 2 records"
set +e
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic ORCLCDB.C__MYUSER.CUSTOMERS --from-beginning --max-messages 2 > /tmp/result.log  2>&1
cat /tmp/result.log

log "Verifying topic redo-log-topic: there should be 2 records"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic redo-log-topic --from-beginning --max-messages 2
