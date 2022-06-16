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
docker exec connect kafka-topics --create --topic redo-log-topic --bootstrap-server broker:9092 --replication-factor 1 --partitions 1 --config cleanup.policy=delete --config retention.ms=120960000
log "redo-log-topic is created"
sleep 5

curl --request PUT \
  --url http://localhost:8083/admin/loggers/io.confluent.connect.oracle.cdc \
  --header 'Accept: application/json' \
  --header 'Content-Type: application/json' \
  --data '{
 "level": "TRACE"
}'

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


docker exec -i oracle sqlplus C\#\#MYUSER/mypassword@//localhost:1521/ORCLPDB1 << EOF
  insert into CUSTOMERS (RECID, XMLRECORD) values ('3',XMLType('<Warehouse whNo="100"> <Building>Owned</Building></Warehouse>'));
  exit;
EOF

docker exec -i oracle sqlplus C\#\#MYUSER/mypassword@//localhost:1521/ORCLPDB1 << EOF
  insert into CUSTOMERS (RECID, XMLRECORD) values ('4',XMLType('<Warehouse whNo="4"> <Building>Owned</Building></Warehouse>'));
  exit;
EOF

docker exec -i oracle sqlplus C\#\#MYUSER/mypassword@//localhost:1521/ORCLPDB1 << EOF
  insert into CUSTOMERS (RECID, XMLRECORD) values ('5',XMLType('<Warehouse whNo="5"> <Building>Owned</Building></Warehouse>'));
  exit;
EOF

docker exec -i oracle sqlplus C\#\#MYUSER/mypassword@//localhost:1521/ORCLPDB1 << EOF
  insert into CUSTOMERS (RECID, XMLRECORD) values ('6',XMLType('<Warehouse whNo="6"> <Building>Owned</Building></Warehouse>'));
  exit;
EOF

docker exec -i oracle sqlplus C\#\#MYUSER/mypassword@//localhost:1521/ORCLPDB1 << EOF
  insert into CUSTOMERS (RECID, XMLRECORD) values ('7',XMLType('<Warehouse whNo="7"> <Building>Owned</Building></Warehouse>'));
  exit;
EOF

docker exec -i oracle sqlplus C\#\#MYUSER/mypassword@//localhost:1521/ORCLPDB1 << EOF
  insert into CUSTOMERS (RECID, XMLRECORD) values ('9',XMLType('<Warehouse whNo="9"> <Building>Owned</Building></Warehouse>'));
  exit;
EOF

docker exec -i oracle sqlplus C\#\#MYUSER/mypassword@//localhost:1521/ORCLPDB1 << EOF
  insert into CUSTOMERS (RECID, XMLRECORD) values ('11',XMLType('<Warehouse whNo="10"> <Building>Owned</Building></Warehouse>'));
  exit;
EOF

set +e
timeout 20 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic ORCLPDB1.C__MYUSER.CUSTOMERS --from-beginning

log "Verifying topic redo-log-topic: there should be 9 records"
timeout 20 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic redo-log-topic --from-beginning

timeout 20 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic CUSTOMERS-XMLRECORD --from-beginning


exit 0

# https://confluent.slack.com/archives/C03KEUWN8EL/p1655376778232009
# curl -X POST localhost:8083/connectors/cdc-oracle-source-pdb/tasks/0/restart
# curl -X POST localhost:8083/connectors/cdc-oracle-source-pdb/tasks/1/restart

# After restart of tasks:

# [2022-06-16 10:32:37,276] TRACE [cdc-oracle-source-pdb|task-1|changeEvent] Received record from redo log (io.confluent.connect.oracle.cdc.ChangeEventGenerator:373)
# [2022-06-16 10:32:37,276] TRACE [cdc-oracle-source-pdb|task-1|changeEvent] Converting value of struct type (io.confluent.connect.oracle.cdc.ChangeEventGenerator:381)
# [2022-06-16 10:32:37,277] TRACE [cdc-oracle-source-pdb|task-1|changeEvent] Redo log record received: Struct{SCN=2173963,START_SCN=2173962,COMMIT_SCN=2173966,TIMESTAMP=Thu Jun 16 10:32:04 GMT 2022,START_TIMESTAMP=Thu Jun 16 10:32:04 GMT 2022,COMMIT_TIMESTAMP=Thu Jun 16 10:32:04 GMT 2022,XIDUSN=10,XIDSLT=2,XIDSQN=650,XID=java.nio.HeapByteBuffer[pos=0 lim=8 cap=8],PXIDUSN=10,PXIDSLT=2,PXIDSQN=650,PXID=java.nio.HeapByteBuffer[pos=0 lim=8 cap=8],OPERATION=XML DOC WRITE,OPERATION_CODE=70,ROLLBACK=false,SEG_OWNER=C##MYUSER,SEG_NAME=CUSTOMERS,TABLE_NAME=CUSTOMERS,SEG_TYPE=2,SEG_TYPE_NAME=TABLE,TABLE_SPACE=USERS,ROW_ID=AAAAAAAAAAAAAAAAAA,USERNAME=C##MYUSER,OS_USERNAME=oracle,MACHINE_NAME=oracle,AUDIT_SESSIONID=10014,SESSION_NUM=367,SERIAL_NUM=37507,SESSION_INFO=login_username=C##MYUSER client_info= OS_username=oracle Machine_name=oracle OS_terminal=pts/0 OS_process_id=1099 OS_program_name=sqlplus@oracle (TNS V1-V3),THREAD_NUM=1,SEQUENCE_NUM=4,RBASQN=7,RBABLK=35242,RBABYTE=312,UBAFIL=11,UBABLK=0,UBAREC=0,UBASQN=0,ABS_FILE_NUM=0,REL_FILE_NUM=0,DATA_BLK_NUM=0,DATA_OBJ_NUM=72994,DATA_OBJV_NUM=2,DATA_OBJD_NUM=0,SQL_REDO=XML_REDO := '<Warehouse whNo="8"> <Building>Owned</Building></Warehouse>'
#  amount: 59,RS_ID= 0x000007.000089aa.0138 ,SSN=0,CSF=false,INFO=XML sql_redo not re-executable,STATUS=2,REDO_VALUE=30,UNDO_VALUE=31,SAFE_RESUME_SCN=0,CSCN=2173966,SRC_CON_NAME=ORCLPDB1,SRC_CON_ID=3,SRC_CON_UID=280798746,SRC_CON_DBID=0,CON_ID=false} (io.confluent.connect.oracle.cdc.ChangeEventGenerator:394)
# [2022-06-16 10:32:37,277] TRACE [cdc-oracle-source-pdb|task-1|changeEvent] Record is self-contained, returning verbatim (io.confluent.connect.oracle.cdc.record.RedoLogRecordCombiner:151)
# [2022-06-16 10:32:37,277] TRACE [cdc-oracle-source-pdb|task-1|changeEvent] Processing combined multi-part record: Struct{SCN=2173963,START_SCN=2173962,COMMIT_SCN=2173966,TIMESTAMP=Thu Jun 16 10:32:04 GMT 2022,START_TIMESTAMP=Thu Jun 16 10:32:04 GMT 2022,COMMIT_TIMESTAMP=Thu Jun 16 10:32:04 GMT 2022,XIDUSN=10,XIDSLT=2,XIDSQN=650,XID=java.nio.HeapByteBuffer[pos=0 lim=8 cap=8],PXIDUSN=10,PXIDSLT=2,PXIDSQN=650,PXID=java.nio.HeapByteBuffer[pos=0 lim=8 cap=8],OPERATION=XML DOC WRITE,OPERATION_CODE=70,ROLLBACK=false,SEG_OWNER=C##MYUSER,SEG_NAME=CUSTOMERS,TABLE_NAME=CUSTOMERS,SEG_TYPE=2,SEG_TYPE_NAME=TABLE,TABLE_SPACE=USERS,ROW_ID=AAAAAAAAAAAAAAAAAA,USERNAME=C##MYUSER,OS_USERNAME=oracle,MACHINE_NAME=oracle,AUDIT_SESSIONID=10014,SESSION_NUM=367,SERIAL_NUM=37507,SESSION_INFO=login_username=C##MYUSER client_info= OS_username=oracle Machine_name=oracle OS_terminal=pts/0 OS_process_id=1099 OS_program_name=sqlplus@oracle (TNS V1-V3),THREAD_NUM=1,SEQUENCE_NUM=4,RBASQN=7,RBABLK=35242,RBABYTE=312,UBAFIL=11,UBABLK=0,UBAREC=0,UBASQN=0,ABS_FILE_NUM=0,REL_FILE_NUM=0,DATA_BLK_NUM=0,DATA_OBJ_NUM=72994,DATA_OBJV_NUM=2,DATA_OBJD_NUM=0,SQL_REDO=XML_REDO := '<Warehouse whNo="8"> <Building>Owned</Building></Warehouse>'
#  amount: 59,RS_ID= 0x000007.000089aa.0138 ,SSN=0,CSF=false,INFO=XML sql_redo not re-executable,STATUS=2,REDO_VALUE=30,UNDO_VALUE=31,SAFE_RESUME_SCN=0,CSCN=2173966,SRC_CON_NAME=ORCLPDB1,SRC_CON_ID=3,SRC_CON_UID=280798746,SRC_CON_DBID=0,CON_ID=false} (io.confluent.connect.oracle.cdc.ChangeEventGenerator:485)
# [2022-06-16 10:32:37,277] TRACE [cdc-oracle-source-pdb|task-1|changeEvent] Change event record convertor skipping XML records (io.confluent.connect.oracle.cdc.record.OracleChangeEventSourceRecordConverter:335)
# [2022-06-16 10:32:37,277] TRACE [cdc-oracle-source-pdb|task-1|changeEvent] Change event records: [] (io.confluent.connect.oracle.cdc.ChangeEventGenerator:506)
# [2022-06-16 10:32:37,277] TRACE [cdc-oracle-source-pdb|task-1|changeEvent] Table schema Schema{STRUCT} did not contain LOB fields, skipping LOB convertor for Struct{SCN=2173963,START_SCN=2173962,COMMIT_SCN=2173966,TIMESTAMP=Thu Jun 16 10:32:04 GMT 2022,START_TIMESTAMP=Thu Jun 16 10:32:04 GMT 2022,COMMIT_TIMESTAMP=Thu Jun 16 10:32:04 GMT 2022,XIDUSN=10,XIDSLT=2,XIDSQN=650,XID=java.nio.HeapByteBuffer[pos=0 lim=8 cap=8],PXIDUSN=10,PXIDSLT=2,PXIDSQN=650,PXID=java.nio.HeapByteBuffer[pos=0 lim=8 cap=8],OPERATION=XML DOC WRITE,OPERATION_CODE=70,ROLLBACK=false,SEG_OWNER=C##MYUSER,SEG_NAME=CUSTOMERS,TABLE_NAME=CUSTOMERS,SEG_TYPE=2,SEG_TYPE_NAME=TABLE,TABLE_SPACE=USERS,ROW_ID=AAAAAAAAAAAAAAAAAA,USERNAME=C##MYUSER,OS_USERNAME=oracle,MACHINE_NAME=oracle,AUDIT_SESSIONID=10014,SESSION_NUM=367,SERIAL_NUM=37507,SESSION_INFO=login_username=C##MYUSER client_info= OS_username=oracle Machine_name=oracle OS_terminal=pts/0 OS_process_id=1099 OS_program_name=sqlplus@oracle (TNS V1-V3),THREAD_NUM=1,SEQUENCE_NUM=4,RBASQN=7,RBABLK=35242,RBABYTE=312,UBAFIL=11,UBABLK=0,UBAREC=0,UBASQN=0,ABS_FILE_NUM=0,REL_FILE_NUM=0,DATA_BLK_NUM=0,DATA_OBJ_NUM=72994,DATA_OBJV_NUM=2,DATA_OBJD_NUM=0,SQL_REDO=XML_REDO := '<Warehouse whNo="8"> <Building>Owned</Building></Warehouse>'
#  amount: 59,RS_ID= 0x000007.000089aa.0138 ,SSN=0,CSF=false,INFO=XML sql_redo not re-executable,STATUS=2,REDO_VALUE=30,UNDO_VALUE=31,SAFE_RESUME_SCN=0,CSCN=2173966,SRC_CON_NAME=ORCLPDB1,SRC_CON_ID=3,SRC_CON_UID=280798746,SRC_CON_DBID=0,CON_ID=false} (io.confluent.connect.oracle.cdc.record.OracleLobRecordConverter:85)
# [2022-06-16 10:32:37,277] TRACE [cdc-oracle-source-pdb|task-1|changeEvent] LOB records: [] (io.confluent.connect.oracle.cdc.ChangeEventGenerator:513)