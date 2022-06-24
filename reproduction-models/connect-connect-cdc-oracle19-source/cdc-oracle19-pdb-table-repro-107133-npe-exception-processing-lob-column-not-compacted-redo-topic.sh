#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh


if [ ! -z "$GITHUB_RUN_NUMBER" ]
then
     # running with github actions
     remove_cdb_oracle_image "LINUX.X64_193000_db_home.zip" "../../connect/connect-cdc-oracle19-source/ora-setup-scripts-cdb-table"
fi

create_or_get_oracle_image "LINUX.X64_193000_db_home.zip" "../../connect/connect-cdc-oracle19-source/ora-setup-scripts-pdb-table"

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.pdb-table.repro-107133-npe-exception-processing-lob-column.yml"


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

log "Grant select on CUSTOMERS table"
docker exec -i oracle sqlplus C\#\#MYUSER/mypassword@//localhost:1521/ORCLPDB1 << EOF
     ALTER SESSION SET CONTAINER=ORCLPDB1;
     GRANT select on CUSTOMERS TO C##MYUSER;
EOF

# Create a redo-log-topic. Please make sure you create a topic with the same name you will use for "redo.log.topic.name": "redo-log-topic"
# CC-13104

log "Creating the redo topic with delete mode"
docker exec connect kafka-topics --create --topic redo-log-topic --bootstrap-server broker:9092 --replication-factor 1 --partitions 1 --config cleanup.policy=delete --config retention.ms=120960000
log "redo-log-topic is created"
sleep 5

# curl --request PUT \
#   --url http://localhost:8083/admin/loggers/io.confluent.connect.oracle.cdc \
#   --header 'Accept: application/json' \
#   --header 'Content-Type: application/json' \
#   --data '{
#  "level": "INFO"
# }'

# curl --request PUT \
#   --url http://localhost:8083/admin/loggers/org.apache.kafka.connect.runtime.WorkerSourceTask \
#   --header 'Accept: application/json' \
#   --header 'Content-Type: application/json' \
#   --data '{
#  "level": "TRACE"
# }'


docker exec -i oracle bash -c "mkdir -p /home/oracle/db_recovery_file_dest;ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
CONNECT sys/Admin123 AS SYSDBA
select current_scn from v\$database;
exit;
EOF

# log "IMPLEMENT WORKAROUND"
# docker exec -i oracle sqlplus C\#\#MYUSER/mypassword@//localhost:1521/ORCLPDB1 << EOF
#   ALTER TABLE CUSTOMERS ADD UPDATED_AT TIMESTAMP;
#   CREATE OR REPLACE TRIGGER TRG_CUSTOMERS_UPD
#   BEFORE INSERT OR UPDATE ON CUSTOMERS
#   REFERENCING NEW AS NEW_ROW
#     FOR EACH ROW
#   BEGIN
#     SELECT SYSDATE
#           INTO :NEW_ROW.UPDATED_AT
#           FROM DUAL;
#   END;
#   /
#   exit;
# EOF

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
               "oracle.pdb.name": "ORCLPDB1",
               "oracle.username": "C##MYUSER",
               "oracle.password": "mypassword",
               "start.from":"current",
               "redo.log.topic.name": "redo-log-topic",
               "redo.log.consumer.bootstrap.servers":"broker:9092",
               "table.inclusion.regex": "ORCLPDB1[.].*[.]CUSTOMERS",
               "table.topic.name.template": "${databaseName}.${schemaName}.${tableName}",
               "numeric.mapping": "best_fit",
               "connection.pool.max.size": 20,
               "redo.log.row.fetch.size":1,
               "oracle.dictionary.mode": "auto",

               "behavior.on.dictionary.mismatch":"log",
               "behavior.on.unparsable.statement":"log",
               "lob.topic.name.template": "${tableName}-${columnName}",
               "redo.log.consumer.isolation.level": "read_committed",
               "enable.large.lob.object.support": "true",
               "error.deadletterqueue.topic.name": "dlq",
               "error.deadletterqueue.topic.replication.factor": "1",
               "errors.log.enable": "true",
               "errors.tolerance": "all",
               "record.buffer.mode": "database",
               "redo.log.corruption.topic": "redo-log-corruption"

          }' \
     http://localhost:8083/connectors/cdc-oracle-source-pdb/config | jq .


log "Waiting 20s for connector to read existing data"
sleep 20

log "update record id 1"
docker exec -i oracle sqlplus C\#\#MYUSER/mypassword@//localhost:1521/ORCLPDB1 << EOF
  update CUSTOMERS set XMLRECORD = XMLType('<Warehouse whNo="3"> <Building>Owned</Building></Warehouse>') where RECID = '1';
  exit;
EOF

# a workaround is to add a field UPDATED_AT
#   create table CUSTOMERS (
#           RECID VARCHAR2(255 BYTE),
#           XMLRECORD XMLTYPE,
#           UPDATED_AT timestamp DEFAULT CURRENT_TIMESTAMP
#   ) XMLTYPE XMLRECORD STORE AS BINARY XML;

#   ALTER TABLE "CUSTOMERS" ADD CONSTRAINT "PK_CUSTOMERS" PRIMARY KEY ("RECID");
#   ALTER TABLE "CUSTOMERS" MODIFY ("RECID" NOT NULL ENABLE);

#   CREATE OR REPLACE TRIGGER TRG_CUSTOMERS_UPD
#   BEFORE INSERT OR UPDATE ON CUSTOMERS
#   REFERENCING NEW AS NEW_ROW
#     FOR EACH ROW
#   BEGIN
#     SELECT SYSDATE
#           INTO :NEW_ROW.UPDATED_AT
#           FROM DUAL;
#   END;
#   /
# no NPE and LOG update received 14:02:55 ℹ️ Verifying lob topic CUSTOMERS-XMLRECORD: there should be 2 records
# "<Warehouse whNo=\"3\"> <Building>Owned</Building></Warehouse>"

# [2022-06-23 07:36:35,201] ERROR [cdc-oracle-source-pdb|task-1|changeEvent] Exception in RecordQueue thread (io.confluent.connect.oracle.cdc.util.RecordQueue:467)
# org.apache.kafka.connect.errors.ConnectException: Exception processing LOB column
# 	at io.confluent.connect.oracle.cdc.record.OracleLobRecordConverter.convert(OracleLobRecordConverter.java:201)
# 	at io.confluent.connect.oracle.cdc.ChangeEventGenerator.processSingleRecord(ChangeEventGenerator.java:511)
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
# Caused by: java.lang.NullPointerException
# 	at io.confluent.connect.oracle.cdc.util.StructUtils.clone(StructUtils.java:194)
# 	at io.confluent.connect.oracle.cdc.parser.SelLobLocatorVisitor.updateCurrentRow(SelLobLocatorVisitor.java:64)
# 	at io.confluent.connect.oracle.cdc.parser.SelLobLocatorVisitor.buildLobRecordKey(SelLobLocatorVisitor.java:49)
# 	at io.confluent.connect.oracle.cdc.schemas.LobRecordSchema.getKeyFromSelectStatement(LobRecordSchema.java:85)
# 	at io.confluent.connect.oracle.cdc.schemas.LobRecordSchema.getKeyFromXmlDocBeginStatement(LobRecordSchema.java:96)
# 	at io.confluent.connect.oracle.cdc.record.OracleLobRecordConverter.getKeyFromXmlDocBegin(OracleLobRecordConverter.java:252)
# 	at io.confluent.connect.oracle.cdc.record.OracleLobRecordConverter.convert(OracleLobRecordConverter.java:184)
# 	... 16 more

set +e
log "Verifying table topic ORCLPDB1.C__MYUSER.CUSTOMERS: there should be 1 record"
timeout 20 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic ORCLPDB1.C__MYUSER.CUSTOMERS --from-beginning  --max-messages 1

log "Verifying lob topic CUSTOMERS-XMLRECORD: there should be 1 records"
timeout 20 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic CUSTOMERS-XMLRECORD --from-beginning  --max-messages 1
# "<Warehouse whNo=\"3\"> <Building>Owned</Building></Warehouse>"
