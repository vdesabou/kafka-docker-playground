#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

create_or_get_oracle_image "LINUX.X64_193000_db_home.zip" "$(pwd)/ora-setup-scripts-cdb-table"

${DIR}/../../ccloud/environment/start.sh "${PWD}/docker-compose.plaintext.cdb-table.repro-106188-consumers-are-lagging-behind.yml"

if [ -f /tmp/delta_configs/env.delta ]
then
     source /tmp/delta_configs/env.delta
else
     logerror "ERROR: /tmp/delta_configs/env.delta has not been generated"
     exit 1
fi
#############

set +e
# delete subject as required
curl -X DELETE -u $SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO $SCHEMA_REGISTRY_URL/subjects/ORCLCDB.C__MYUSER.CUSTOMERS-key
curl -X DELETE -u $SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO $SCHEMA_REGISTRY_URL/subjects/ORCLCDB.C__MYUSER.CUSTOMERS-value
delete_topic ORCLCDB.C__MYUSER.CUSTOMERS
delete_topic redo-log-topic
for((i=2;i<50;i++)); do
curl -X DELETE -u $SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO $SCHEMA_REGISTRY_URL/subjects/ORCLCDB.C__MYUSER.CUSTOMERS$i-key
curl -X DELETE -u $SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO $SCHEMA_REGISTRY_URL/subjects/ORCLCDB.C__MYUSER.CUSTOMERS$i-value
delete_topic ORCLCDB.C__MYUSER.CUSTOMERS$i
done
set -e

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

log "Creating _confluent-monitoring topic in Confluent Cloud (auto.create.topics.enable=false)"
set +e
create_topic _confluent-monitoring
set -e

log "Creating Oracle source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.oracle.cdc.OracleCdcSourceConnector",
               "tasks.max":50,
               "key.converter" : "io.confluent.connect.avro.AvroConverter",
               "key.converter.schema.registry.url": "'"$SCHEMA_REGISTRY_URL"'",
               "key.converter.basic.auth.user.info": "${file:/data:schema.registry.basic.auth.user.info}",
               "key.converter.basic.auth.credentials.source": "USER_INFO",
               "value.converter" : "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "'"$SCHEMA_REGISTRY_URL"'",
               "value.converter.basic.auth.user.info": "${file:/data:schema.registry.basic.auth.user.info}",
               "value.converter.basic.auth.credentials.source": "USER_INFO",

               "confluent.topic.ssl.endpoint.identification.algorithm" : "https",
               "confluent.topic.sasl.mechanism" : "PLAIN",
               "confluent.topic.bootstrap.servers": "${file:/data:bootstrap.servers}",
               "confluent.topic.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"${file:/data:sasl.username}\" password=\"${file:/data:sasl.password}\";",
               "confluent.topic.security.protocol" : "SASL_SSL",
               "confluent.topic.replication.factor": "3",

               "topic.creation.groups":"redo",
               "topic.creation.redo.include":"redo-log-topic",
               "topic.creation.redo.replication.factor":3,
               "topic.creation.redo.partitions":1,
               "topic.creation.redo.cleanup.policy":"delete",
               "topic.creation.redo.retention.ms":1209600000,
               "topic.creation.default.replication.factor":3,
               "topic.creation.default.partitions":3,
               "topic.creation.default.cleanup.policy":"compact",

               "oracle.server": "oracle",
               "oracle.port": 1521,
               "oracle.sid": "ORCLCDB",
               "oracle.username": "C##MYUSER",
               "oracle.password": "mypassword",
               "start.from":"snapshot",

               "redo.log.topic.name": "redo-log-topic",
               "redo.log.consumer.bootstrap.servers": "${file:/data:bootstrap.servers}",
               "redo.log.consumer.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"${file:/data:sasl.username}\" password=\"${file:/data:sasl.password}\";",
               "redo.log.consumer.security.protocol":"SASL_SSL",
               "redo.log.consumer.sasl.mechanism":"PLAIN",
               "redo.log.consumer.fetch.min.bytes": "100000",
               "redo.log.consumer.max.poll.records": "5000",
               "table.inclusion.regex": "ORCLCDB[.]C##MYUSER[.](CUSTOMERS|CUSTOMERS2|CUSTOMERS3|CUSTOMERS4|CUSTOMERS5|CUSTOMERS6|CUSTOMERS7|CUSTOMERS8|CUSTOMERS9|CUSTOMERS10|CUSTOMERS11|CUSTOMERS12|CUSTOMERS13|CUSTOMERS14|CUSTOMERS15|CUSTOMERS16|CUSTOMERS17|CUSTOMERS18|CUSTOMERS19|CUSTOMERS20|CUSTOMERS21|CUSTOMERS22|CUSTOMERS23|CUSTOMERS24|CUSTOMERS25|CUSTOMERS26|CUSTOMERS27|CUSTOMERS28|CUSTOMERS29|CUSTOMERS30|CUSTOMERS31|CUSTOMERS32|CUSTOMERS33|CUSTOMERS34|CUSTOMERS35|CUSTOMERS36|CUSTOMERS37|CUSTOMERS38|CUSTOMERS39|CUSTOMERS40|CUSTOMERS41|CUSTOMERS42|CUSTOMERS43|CUSTOMERS44|CUSTOMERS45|CUSTOMERS46|CUSTOMERS47|CUSTOMERS48|CUSTOMERS49)",
               "table.topic.name.template": "${databaseName}.${schemaName}.${tableName}",
               "poll.linger.ms": "1000",
               "numeric.mapping": "best_fit",
               "connection.pool.max.size": 20,
               "redo.log.row.fetch.size":10000,
               "oracle.dictionary.mode": "auto"
          }' \
     http://localhost:8083/connectors/cdc-oracle-source-cdb-cloud/config | jq .

log "Waiting 20s for connector to read existing data"
sleep 20

log "Generating data for all tables"
./106188_generate_customers.sh  | grep Populating
log "Done"


# Note: seeing tasks failed with:

# [2022-05-23 15:47:09,397] ERROR [cdc-oracle-source-cdb-cloud|task-45|changeEvent] Exception in RecordQueue thread (io.confluent.connect.oracle.cdc.util.RecordQueue:467)
# org.apache.kafka.connect.errors.ConnectException: Exception converting redo to change event. SQL: 'insert into "C##MYUSER"."CUSTOMERS5"("ID","FIRST_NAME","LAST_NAME","EMAIL","GENDER","CLUB_STATUS","COMMENTS","CREATE_TS","UPDATE_TS") values ('1817','Syman','Frensche','sfrenschels@salon.com','Male','platinum','exploit open-source markets',TO_TIMESTAMP('2022-05-23 15:45:52.952'),TO_TIMESTAMP('2022-05-23 15:45:52.000'));' INFO: null
# 	at io.confluent.connect.oracle.cdc.record.OracleChangeEventSourceRecordConverter.convert(OracleChangeEventSourceRecordConverter.java:347)
# 	at io.confluent.connect.oracle.cdc.ChangeEventGenerator.processSingleRecord(ChangeEventGenerator.java:496)
# 	at io.confluent.connect.oracle.cdc.ChangeEventGenerator.lambda$doGenerateChangeEvent$2(ChangeEventGenerator.java:419)
# 	at java.base/java.util.stream.ReferencePipeline$3$1.accept(ReferencePipeline.java:195)
# 	at java.base/java.util.Spliterators$ArraySpliterator.forEachRemaining(Spliterators.java:948)
# 	at java.base/java.util.stream.AbstractPipeline.copyInto(AbstractPipeline.java:484)
# 	at java.base/java.util.stream.AbstractPipeline.wrapAndCopyInto(AbstractPipeline.java:474)
# 	at java.base/java.util.stream.ReduceOps$ReduceOp.evaluateSequential(ReduceOps.java:913)
# 	at java.base/java.util.stream.AbstractPipeline.evaluate(AbstractPipeline.java:234)
# 	at java.base/java.util.stream.ReferencePipeline.collect(ReferencePipeline.java:578)
# 	at io.confluent.connect.oracle.cdc.ChangeEventGenerator.doGenerateChangeEvent(ChangeEventGenerator.java:421)
# 	at io.confluent.connect.oracle.cdc.ChangeEventGenerator.execute(ChangeEventGenerator.java:221)
# 	at io.confluent.connect.oracle.cdc.util.RecordQueue.lambda$createLoggingSupplier$0(RecordQueue.java:465)
# 	at java.base/java.util.concurrent.CompletableFuture$AsyncSupply.run(CompletableFuture.java:1700)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.apache.kafka.connect.errors.ConnectException: Could not convert field UPDATE_TS value TO_TIMESTAMP('2022-05-23 15:45:52.000') to type INT64
# 	at io.confluent.connect.oracle.cdc.record.OracleChangeEventSourceRecordConverter.createRecord(OracleChangeEventSourceRecordConverter.java:433)
# 	at io.confluent.connect.oracle.cdc.record.OracleChangeEventSourceRecordConverter.convertInsert(OracleChangeEventSourceRecordConverter.java:515)
# 	at io.confluent.connect.oracle.cdc.record.OracleChangeEventSourceRecordConverter.convert(OracleChangeEventSourceRecordConverter.java:298)
# 	... 16 more