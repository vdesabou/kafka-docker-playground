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
docker exec broker kafka-topics --create --topic redo-log-topic --bootstrap-server broker:9092 --replication-factor 1 --partitions 1 --config cleanup.policy=delete --config retention.ms=120960000
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

log "Insert record id 3"
docker exec -i oracle sqlplus C\#\#MYUSER/mypassword@//localhost:1521/ORCLPDB1 << EOF
  insert into CUSTOMERS (RECID, XMLRECORD) values ('3',XMLType('<Warehouse whNo="3"> <Building>Owned</Building></Warehouse>'));
  exit;
EOF

log "Insert record id 4"
docker exec -i oracle sqlplus C\#\#MYUSER/mypassword@//localhost:1521/ORCLPDB1 << EOF
  insert into CUSTOMERS (RECID, XMLRECORD) values ('4',XMLType('<Warehouse whNo="4"> <Building>Owned</Building></Warehouse>'));
  exit;
EOF

set +e
log "Verifying table topic ORCLPDB1.C__MYUSER.CUSTOMERS: there should be 2 records"
timeout 20 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic ORCLPDB1.C__MYUSER.CUSTOMERS --from-beginning  --max-messages 2

# {"RECID":"3","table":{"string":"ORCLPDB1.C##MYUSER.CUSTOMERS"},"scn":{"string":"2167694"},"op_type":{"string":"I"},"op_ts":{"string":"1655381241000"},"current_ts":{"string":"1655381242810"},"row_id":{"string":"AAAAAAAAAAAAAAAAAA"},"username":{"string":"C##MYUSER"}}
# {"RECID":"4","table":{"string":"ORCLPDB1.C##MYUSER.CUSTOMERS"},"scn":{"string":"2167711"},"op_type":{"string":"I"},"op_ts":{"string":"1655381242000"},"current_ts":{"string":"1655381247593"},"row_id":{"string":"AAAAAAAAAAAAAAAAAA"},"username":{"string":"C##MYUSER"}

# {
#   "fields": [
#     {
#       "name": "RECID",
#       "type": "string"
#     },
#     {
#       "default": null,
#       "name": "table",
#       "type": [
#         "null",
#         "string"
#       ]
#     },
#     {
#       "default": null,
#       "name": "scn",
#       "type": [
#         "null",
#         "string"
#       ]
#     },
#     {
#       "default": null,
#       "name": "op_type",
#       "type": [
#         "null",
#         "string"
#       ]
#     },
#     {
#       "default": null,
#       "name": "op_ts",
#       "type": [
#         "null",
#         "string"
#       ]
#     },
#     {
#       "default": null,
#       "name": "current_ts",
#       "type": [
#         "null",
#         "string"
#       ]
#     },
#     {
#       "default": null,
#       "name": "row_id",
#       "type": [
#         "null",
#         "string"
#       ]
#     },
#     {
#       "default": null,
#       "name": "username",
#       "type": [
#         "null",
#         "string"
#       ]
#     }
#   ],
#   "name": "ConnectDefault",
#   "namespace": "io.confluent.connect.avro",
#   "type": "record"
# }

log "Verifying topic redo-log-topic: there should be 10 records"
timeout 20 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic redo-log-topic --from-beginning --max-messages 10
 
# {"SCN":{"long":2167694},"START_SCN":{"long":2167694},"COMMIT_SCN":{"long":2167698},"TIMESTAMP":{"long":1655381241000},"START_TIMESTAMP":{"long":1655381241000},"COMMIT_TIMESTAMP":{"long":1655381241000},"XIDUSN":{"long":10},"XIDSLT":{"long":19},"XIDSQN":{"long":648},"XID":{"bytes":"\n\u0000\u0013\u0000\u0002\u0000\u0000"},"PXIDUSN":{"long":10},"PXIDSLT":{"long":19},"PXIDSQN":{"long":648},"PXID":{"bytes":"\n\u0000\u0013\u0000\u0002\u0000\u0000"},"TX_NAME":null,"OPERATION":{"string":"INSERT"},"OPERATION_CODE":{"int":1},"ROLLBACK":{"boolean":false},"SEG_OWNER":{"string":"C##MYUSER"},"SEG_NAME":{"string":"CUSTOMERS"},"TABLE_NAME":{"string":"CUSTOMERS"},"SEG_TYPE":{"int":2},"SEG_TYPE_NAME":{"string":"TABLE"},"TABLE_SPACE":{"string":"USERS"},"ROW_ID":{"string":"AAAAAAAAAAAAAAAAAA"},"USERNAME":{"string":"C##MYUSER"},"OS_USERNAME":{"string":"oracle"},"MACHINE_NAME":{"string":"oracle"},"AUDIT_SESSIONID":{"long":29},"SESSION_NUM":{"long":186},"SERIAL_NUM":{"long":64715},"SESSION_INFO":{"string":"login_username=C##MYUSER client_info= OS_username=oracle Machine_name=oracle OS_terminal=pts/0 OS_process_id=548 OS_program_name=sqlplus@oracle (TNS V1-V3)"},"THREAD_NUM":{"long":1},"SEQUENCE_NUM":{"long":2},"RBASQN":{"long":7},"RBABLK":{"long":8907},"RBABYTE":{"long":384},"UBAFIL":{"long":11},"UBABLK":{"long":0},"UBAREC":{"long":0},"UBASQN":{"long":0},"ABS_FILE_NUM":{"long":0},"REL_FILE_NUM":{"long":0},"DATA_BLK_NUM":{"long":0},"DATA_OBJ_NUM":{"long":72994},"DATA_OBJV_NUM":{"long":2},"DATA_OBJD_NUM":{"long":0},"SQL_REDO":{"string":"insert into \"C##MYUSER\".\"CUSTOMERS\"(\"RECID\") values ('3');"},"SQL_UNDO":{"string":"delete from \"C##MYUSER\".\"CUSTOMERS\" a where a.\"RECID\" = '3' and a.ROWID = 'AAAAAAAAAAAAAAAAAA';"},"RS_ID":{"string":" 0x000007.000022cb.0180 "},"SSN":{"long":0},"CSF":{"boolean":false},"INFO":null,"STATUS":{"int":0},"REDO_VALUE":{"long":20},"UNDO_VALUE":{"long":21},"SAFE_RESUME_SCN":{"long":0},"CSCN":{"long":2167698},"OBJECT_ID":null,"EDITION_NAME":null,"CLIENT_ID":null,"SRC_CON_NAME":{"string":"ORCLPDB1"},"SRC_CON_ID":{"long":3},"SRC_CON_UID":{"long":280798746},"SRC_CON_DBID":{"long":0},"SRC_CON_GUID":null,"CON_ID":{"boolean":false}}
# {"SCN":{"long":2167695},"START_SCN":{"long":2167694},"COMMIT_SCN":{"long":2167698},"TIMESTAMP":{"long":1655381241000},"START_TIMESTAMP":{"long":1655381241000},"COMMIT_TIMESTAMP":{"long":1655381241000},"XIDUSN":{"long":10},"XIDSLT":{"long":19},"XIDSQN":{"long":648},"XID":{"bytes":"\n\u0000\u0013\u0000\u0002\u0000\u0000"},"PXIDUSN":{"long":10},"PXIDSLT":{"long":19},"PXIDSQN":{"long":648},"PXID":{"bytes":"\n\u0000\u0013\u0000\u0002\u0000\u0000"},"TX_NAME":null,"OPERATION":{"string":"XML DOC BEGIN"},"OPERATION_CODE":{"int":68},"ROLLBACK":{"boolean":false},"SEG_OWNER":{"string":"C##MYUSER"},"SEG_NAME":{"string":"CUSTOMERS"},"TABLE_NAME":{"string":"CUSTOMERS"},"SEG_TYPE":{"int":2},"SEG_TYPE_NAME":{"string":"TABLE"},"TABLE_SPACE":{"string":"USERS"},"ROW_ID":{"string":"AAAAAAAAAAAAAAAAAA"},"USERNAME":{"string":"C##MYUSER"},"OS_USERNAME":{"string":"oracle"},"MACHINE_NAME":{"string":"oracle"},"AUDIT_SESSIONID":{"long":29},"SESSION_NUM":{"long":186},"SERIAL_NUM":{"long":64715},"SESSION_INFO":{"string":"login_username=C##MYUSER client_info= OS_username=oracle Machine_name=oracle OS_terminal=pts/0 OS_process_id=548 OS_program_name=sqlplus@oracle (TNS V1-V3)"},"THREAD_NUM":{"long":1},"SEQUENCE_NUM":{"long":3},"RBASQN":{"long":7},"RBABLK":{"long":8910},"RBABYTE":{"long":312},"UBAFIL":{"long":11},"UBABLK":{"long":0},"UBAREC":{"long":0},"UBASQN":{"long":0},"ABS_FILE_NUM":{"long":0},"REL_FILE_NUM":{"long":0},"DATA_BLK_NUM":{"long":0},"DATA_OBJ_NUM":{"long":72994},"DATA_OBJV_NUM":{"long":2},"DATA_OBJD_NUM":{"long":0},"SQL_REDO":{"string":"XML DOC BEGIN:  select \"XMLRECORD\" from \"C##MYUSER\".\"CUSTOMERS\" where \"RECID\" = '3'"},"SQL_UNDO":null,"RS_ID":{"string":" 0x000007.000022ce.0138 "},"SSN":{"long":0},"CSF":{"boolean":false},"INFO":{"string":"XML sql_redo not re-executable"},"STATUS":{"int":2},"REDO_VALUE":{"long":22},"UNDO_VALUE":{"long":23},"SAFE_RESUME_SCN":{"long":0},"CSCN":{"long":2167698},"OBJECT_ID":null,"EDITION_NAME":null,"CLIENT_ID":null,"SRC_CON_NAME":{"string":"ORCLPDB1"},"SRC_CON_ID":{"long":3},"SRC_CON_UID":{"long":280798746},"SRC_CON_DBID":{"long":0},"SRC_CON_GUID":null,"CON_ID":{"boolean":false}}
# {"SCN":{"long":2167695},"START_SCN":{"long":2167694},"COMMIT_SCN":{"long":2167698},"TIMESTAMP":{"long":1655381241000},"START_TIMESTAMP":{"long":1655381241000},"COMMIT_TIMESTAMP":{"long":1655381241000},"XIDUSN":{"long":10},"XIDSLT":{"long":19},"XIDSQN":{"long":648},"XID":{"bytes":"\n\u0000\u0013\u0000\u0002\u0000\u0000"},"PXIDUSN":{"long":10},"PXIDSLT":{"long":19},"PXIDSQN":{"long":648},"PXID":{"bytes":"\n\u0000\u0013\u0000\u0002\u0000\u0000"},"TX_NAME":null,"OPERATION":{"string":"XML DOC WRITE"},"OPERATION_CODE":{"int":70},"ROLLBACK":{"boolean":false},"SEG_OWNER":{"string":"C##MYUSER"},"SEG_NAME":{"string":"CUSTOMERS"},"TABLE_NAME":{"string":"CUSTOMERS"},"SEG_TYPE":{"int":2},"SEG_TYPE_NAME":{"string":"TABLE"},"TABLE_SPACE":{"string":"USERS"},"ROW_ID":{"string":"AAAAAAAAAAAAAAAAAA"},"USERNAME":{"string":"C##MYUSER"},"OS_USERNAME":{"string":"oracle"},"MACHINE_NAME":{"string":"oracle"},"AUDIT_SESSIONID":{"long":29},"SESSION_NUM":{"long":186},"SERIAL_NUM":{"long":64715},"SESSION_INFO":{"string":"login_username=C##MYUSER client_info= OS_username=oracle Machine_name=oracle OS_terminal=pts/0 OS_process_id=548 OS_program_name=sqlplus@oracle (TNS V1-V3)"},"THREAD_NUM":{"long":1},"SEQUENCE_NUM":{"long":4},"RBASQN":{"long":7},"RBABLK":{"long":8910},"RBABYTE":{"long":312},"UBAFIL":{"long":11},"UBABLK":{"long":0},"UBAREC":{"long":0},"UBASQN":{"long":0},"ABS_FILE_NUM":{"long":0},"REL_FILE_NUM":{"long":0},"DATA_BLK_NUM":{"long":0},"DATA_OBJ_NUM":{"long":72994},"DATA_OBJV_NUM":{"long":2},"DATA_OBJD_NUM":{"long":0},"SQL_REDO":{"string":"XML_REDO := '<Warehouse whNo=\"3\"> <Building>Owned</Building></Warehouse>'\n amount: 59"},"SQL_UNDO":null,"RS_ID":{"string":" 0x000007.000022ce.0138 "},"SSN":{"long":0},"CSF":{"boolean":false},"INFO":{"string":"XML sql_redo not re-executable"},"STATUS":{"int":2},"REDO_VALUE":{"long":24},"UNDO_VALUE":{"long":25},"SAFE_RESUME_SCN":{"long":0},"CSCN":{"long":2167698},"OBJECT_ID":null,"EDITION_NAME":null,"CLIENT_ID":null,"SRC_CON_NAME":{"string":"ORCLPDB1"},"SRC_CON_ID":{"long":3},"SRC_CON_UID":{"long":280798746},"SRC_CON_DBID":{"long":0},"SRC_CON_GUID":null,"CON_ID":{"boolean":false}}
# {"SCN":{"long":2167695},"START_SCN":{"long":2167694},"COMMIT_SCN":{"long":2167698},"TIMESTAMP":{"long":1655381241000},"START_TIMESTAMP":{"long":1655381241000},"COMMIT_TIMESTAMP":{"long":1655381241000},"XIDUSN":{"long":10},"XIDSLT":{"long":19},"XIDSQN":{"long":648},"XID":{"bytes":"\n\u0000\u0013\u0000\u0002\u0000\u0000"},"PXIDUSN":{"long":10},"PXIDSLT":{"long":19},"PXIDSQN":{"long":648},"PXID":{"bytes":"\n\u0000\u0013\u0000\u0002\u0000\u0000"},"TX_NAME":null,"OPERATION":{"string":"XML DOC END"},"OPERATION_CODE":{"int":71},"ROLLBACK":{"boolean":false},"SEG_OWNER":{"string":"C##MYUSER"},"SEG_NAME":{"string":"CUSTOMERS"},"TABLE_NAME":{"string":"CUSTOMERS"},"SEG_TYPE":{"int":2},"SEG_TYPE_NAME":{"string":"TABLE"},"TABLE_SPACE":{"string":"USERS"},"ROW_ID":{"string":"AAAAAAAAAAAAAAAAAA"},"USERNAME":{"string":"C##MYUSER"},"OS_USERNAME":{"string":"oracle"},"MACHINE_NAME":{"string":"oracle"},"AUDIT_SESSIONID":{"long":29},"SESSION_NUM":{"long":186},"SERIAL_NUM":{"long":64715},"SESSION_INFO":{"string":"login_username=C##MYUSER client_info= OS_username=oracle Machine_name=oracle OS_terminal=pts/0 OS_process_id=548 OS_program_name=sqlplus@oracle (TNS V1-V3)"},"THREAD_NUM":{"long":1},"SEQUENCE_NUM":{"long":5},"RBASQN":{"long":7},"RBABLK":{"long":8910},"RBABYTE":{"long":312},"UBAFIL":{"long":11},"UBABLK":{"long":0},"UBAREC":{"long":0},"UBASQN":{"long":0},"ABS_FILE_NUM":{"long":0},"REL_FILE_NUM":{"long":0},"DATA_BLK_NUM":{"long":0},"DATA_OBJ_NUM":{"long":72994},"DATA_OBJV_NUM":{"long":2},"DATA_OBJD_NUM":{"long":0},"SQL_REDO":null,"SQL_UNDO":null,"RS_ID":{"string":" 0x000007.000022ce.0138 "},"SSN":{"long":0},"CSF":{"boolean":false},"INFO":null,"STATUS":{"int":0},"REDO_VALUE":{"long":26},"UNDO_VALUE":{"long":27},"SAFE_RESUME_SCN":{"long":0},"CSCN":{"long":2167698},"OBJECT_ID":null,"EDITION_NAME":null,"CLIENT_ID":null,"SRC_CON_NAME":{"string":"ORCLPDB1"},"SRC_CON_ID":{"long":3},"SRC_CON_UID":{"long":280798746},"SRC_CON_DBID":{"long":0},"SRC_CON_GUID":null,"CON_ID":{"boolean":false}}
# {"SCN":{"long":2167698},"START_SCN":{"long":2167694},"COMMIT_SCN":{"long":2167698},"TIMESTAMP":{"long":1655381241000},"START_TIMESTAMP":{"long":1655381241000},"COMMIT_TIMESTAMP":{"long":1655381241000},"XIDUSN":{"long":10},"XIDSLT":{"long":19},"XIDSQN":{"long":648},"XID":{"bytes":"\n\u0000\u0013\u0000\u0002\u0000\u0000"},"PXIDUSN":{"long":10},"PXIDSLT":{"long":19},"PXIDSQN":{"long":648},"PXID":{"bytes":"\n\u0000\u0013\u0000\u0002\u0000\u0000"},"TX_NAME":null,"OPERATION":{"string":"COMMIT"},"OPERATION_CODE":{"int":7},"ROLLBACK":{"boolean":false},"SEG_OWNER":null,"SEG_NAME":null,"TABLE_NAME":null,"SEG_TYPE":{"int":0},"SEG_TYPE_NAME":null,"TABLE_SPACE":null,"ROW_ID":{"string":"AAAAAAAAAAAAAAAAAA"},"USERNAME":{"string":"C##MYUSER"},"OS_USERNAME":{"string":"oracle"},"MACHINE_NAME":{"string":"oracle"},"AUDIT_SESSIONID":{"long":29},"SESSION_NUM":{"long":186},"SERIAL_NUM":{"long":64715},"SESSION_INFO":{"string":"login_username=C##MYUSER client_info= OS_username=oracle Machine_name=oracle OS_terminal=pts/0 OS_process_id=548 OS_program_name=sqlplus@oracle (TNS V1-V3)"},"THREAD_NUM":{"long":1},"SEQUENCE_NUM":{"long":7},"RBASQN":{"long":7},"RBABLK":{"long":8912},"RBABYTE":{"long":276},"UBAFIL":{"long":11},"UBABLK":{"long":0},"UBAREC":{"long":0},"UBASQN":{"long":0},"ABS_FILE_NUM":{"long":11},"REL_FILE_NUM":{"long":0},"DATA_BLK_NUM":{"long":0},"DATA_OBJ_NUM":{"long":0},"DATA_OBJV_NUM":{"long":0},"DATA_OBJD_NUM":{"long":0},"SQL_REDO":{"string":"commit;"},"SQL_UNDO":null,"RS_ID":{"string":" 0x000007.000022d0.0114 "},"SSN":{"long":0},"CSF":{"boolean":false},"INFO":null,"STATUS":{"int":0},"REDO_VALUE":{"long":30},"UNDO_VALUE":{"long":31},"SAFE_RESUME_SCN":{"long":2167698},"CSCN":{"long":2167698},"OBJECT_ID":null,"EDITION_NAME":null,"CLIENT_ID":null,"SRC_CON_NAME":{"string":"ORCLPDB1"},"SRC_CON_ID":{"long":3},"SRC_CON_UID":{"long":280798746},"SRC_CON_DBID":{"long":0},"SRC_CON_GUID":null,"CON_ID":{"boolean":false}}
# {"SCN":{"long":2167711},"START_SCN":{"long":2167711},"COMMIT_SCN":{"long":2167714},"TIMESTAMP":{"long":1655381242000},"START_TIMESTAMP":{"long":1655381242000},"COMMIT_TIMESTAMP":{"long":1655381242000},"XIDUSN":{"long":10},"XIDSLT":{"long":21},"XIDSQN":{"long":648},"XID":{"bytes":"\n\u0000\u0015\u0000\u0002\u0000\u0000"},"PXIDUSN":{"long":10},"PXIDSLT":{"long":21},"PXIDSQN":{"long":648},"PXID":{"bytes":"\n\u0000\u0015\u0000\u0002\u0000\u0000"},"TX_NAME":null,"OPERATION":{"string":"INSERT"},"OPERATION_CODE":{"int":1},"ROLLBACK":{"boolean":false},"SEG_OWNER":{"string":"C##MYUSER"},"SEG_NAME":{"string":"CUSTOMERS"},"TABLE_NAME":{"string":"CUSTOMERS"},"SEG_TYPE":{"int":2},"SEG_TYPE_NAME":{"string":"TABLE"},"TABLE_SPACE":{"string":"USERS"},"ROW_ID":{"string":"AAAAAAAAAAAAAAAAAA"},"USERNAME":{"string":"C##MYUSER"},"OS_USERNAME":{"string":"oracle"},"MACHINE_NAME":{"string":"oracle"},"AUDIT_SESSIONID":{"long":30},"SESSION_NUM":{"long":186},"SERIAL_NUM":{"long":7500},"SESSION_INFO":{"string":"login_username=C##MYUSER client_info= OS_username=oracle Machine_name=oracle OS_terminal=pts/0 OS_process_id=557 OS_program_name=sqlplus@oracle (TNS V1-V3)"},"THREAD_NUM":{"long":1},"SEQUENCE_NUM":{"long":2},"RBASQN":{"long":7},"RBABLK":{"long":8920},"RBABYTE":{"long":384},"UBAFIL":{"long":11},"UBABLK":{"long":0},"UBAREC":{"long":0},"UBASQN":{"long":0},"ABS_FILE_NUM":{"long":0},"REL_FILE_NUM":{"long":0},"DATA_BLK_NUM":{"long":0},"DATA_OBJ_NUM":{"long":72994},"DATA_OBJV_NUM":{"long":2},"DATA_OBJD_NUM":{"long":0},"SQL_REDO":{"string":"insert into \"C##MYUSER\".\"CUSTOMERS\"(\"RECID\") values ('4');"},"SQL_UNDO":{"string":"delete from \"C##MYUSER\".\"CUSTOMERS\" a where a.\"RECID\" = '4' and a.ROWID = 'AAAAAAAAAAAAAAAAAA';"},"RS_ID":{"string":" 0x000007.000022d8.0180 "},"SSN":{"long":0},"CSF":{"boolean":false},"INFO":null,"STATUS":{"int":0},"REDO_VALUE":{"long":14},"UNDO_VALUE":{"long":15},"SAFE_RESUME_SCN":{"long":0},"CSCN":{"long":2167714},"OBJECT_ID":null,"EDITION_NAME":null,"CLIENT_ID":null,"SRC_CON_NAME":{"string":"ORCLPDB1"},"SRC_CON_ID":{"long":3},"SRC_CON_UID":{"long":280798746},"SRC_CON_DBID":{"long":0},"SRC_CON_GUID":null,"CON_ID":{"boolean":false}}
# {"SCN":{"long":2167711},"START_SCN":{"long":2167711},"COMMIT_SCN":{"long":2167714},"TIMESTAMP":{"long":1655381242000},"START_TIMESTAMP":{"long":1655381242000},"COMMIT_TIMESTAMP":{"long":1655381242000},"XIDUSN":{"long":10},"XIDSLT":{"long":21},"XIDSQN":{"long":648},"XID":{"bytes":"\n\u0000\u0015\u0000\u0002\u0000\u0000"},"PXIDUSN":{"long":10},"PXIDSLT":{"long":21},"PXIDSQN":{"long":648},"PXID":{"bytes":"\n\u0000\u0015\u0000\u0002\u0000\u0000"},"TX_NAME":null,"OPERATION":{"string":"XML DOC BEGIN"},"OPERATION_CODE":{"int":68},"ROLLBACK":{"boolean":false},"SEG_OWNER":{"string":"C##MYUSER"},"SEG_NAME":{"string":"CUSTOMERS"},"TABLE_NAME":{"string":"CUSTOMERS"},"SEG_TYPE":{"int":2},"SEG_TYPE_NAME":{"string":"TABLE"},"TABLE_SPACE":{"string":"USERS"},"ROW_ID":{"string":"AAAAAAAAAAAAAAAAAA"},"USERNAME":{"string":"C##MYUSER"},"OS_USERNAME":{"string":"oracle"},"MACHINE_NAME":{"string":"oracle"},"AUDIT_SESSIONID":{"long":30},"SESSION_NUM":{"long":186},"SERIAL_NUM":{"long":7500},"SESSION_INFO":{"string":"login_username=C##MYUSER client_info= OS_username=oracle Machine_name=oracle OS_terminal=pts/0 OS_process_id=557 OS_program_name=sqlplus@oracle (TNS V1-V3)"},"THREAD_NUM":{"long":1},"SEQUENCE_NUM":{"long":3},"RBASQN":{"long":7},"RBABLK":{"long":8921},"RBABYTE":{"long":352},"UBAFIL":{"long":11},"UBABLK":{"long":0},"UBAREC":{"long":0},"UBASQN":{"long":0},"ABS_FILE_NUM":{"long":0},"REL_FILE_NUM":{"long":0},"DATA_BLK_NUM":{"long":0},"DATA_OBJ_NUM":{"long":72994},"DATA_OBJV_NUM":{"long":2},"DATA_OBJD_NUM":{"long":0},"SQL_REDO":{"string":"XML DOC BEGIN:  select \"XMLRECORD\" from \"C##MYUSER\".\"CUSTOMERS\" where \"RECID\" = '4'"},"SQL_UNDO":null,"RS_ID":{"string":" 0x000007.000022d9.0160 "},"SSN":{"long":0},"CSF":{"boolean":false},"INFO":{"string":"XML sql_redo not re-executable"},"STATUS":{"int":2},"REDO_VALUE":{"long":16},"UNDO_VALUE":{"long":17},"SAFE_RESUME_SCN":{"long":0},"CSCN":{"long":2167714},"OBJECT_ID":null,"EDITION_NAME":null,"CLIENT_ID":null,"SRC_CON_NAME":{"string":"ORCLPDB1"},"SRC_CON_ID":{"long":3},"SRC_CON_UID":{"long":280798746},"SRC_CON_DBID":{"long":0},"SRC_CON_GUID":null,"CON_ID":{"boolean":false}}
# {"SCN":{"long":2167711},"START_SCN":{"long":2167711},"COMMIT_SCN":{"long":2167714},"TIMESTAMP":{"long":1655381242000},"START_TIMESTAMP":{"long":1655381242000},"COMMIT_TIMESTAMP":{"long":1655381242000},"XIDUSN":{"long":10},"XIDSLT":{"long":21},"XIDSQN":{"long":648},"XID":{"bytes":"\n\u0000\u0015\u0000\u0002\u0000\u0000"},"PXIDUSN":{"long":10},"PXIDSLT":{"long":21},"PXIDSQN":{"long":648},"PXID":{"bytes":"\n\u0000\u0015\u0000\u0002\u0000\u0000"},"TX_NAME":null,"OPERATION":{"string":"XML DOC WRITE"},"OPERATION_CODE":{"int":70},"ROLLBACK":{"boolean":false},"SEG_OWNER":{"string":"C##MYUSER"},"SEG_NAME":{"string":"CUSTOMERS"},"TABLE_NAME":{"string":"CUSTOMERS"},"SEG_TYPE":{"int":2},"SEG_TYPE_NAME":{"string":"TABLE"},"TABLE_SPACE":{"string":"USERS"},"ROW_ID":{"string":"AAAAAAAAAAAAAAAAAA"},"USERNAME":{"string":"C##MYUSER"},"OS_USERNAME":{"string":"oracle"},"MACHINE_NAME":{"string":"oracle"},"AUDIT_SESSIONID":{"long":30},"SESSION_NUM":{"long":186},"SERIAL_NUM":{"long":7500},"SESSION_INFO":{"string":"login_username=C##MYUSER client_info= OS_username=oracle Machine_name=oracle OS_terminal=pts/0 OS_process_id=557 OS_program_name=sqlplus@oracle (TNS V1-V3)"},"THREAD_NUM":{"long":1},"SEQUENCE_NUM":{"long":4},"RBASQN":{"long":7},"RBABLK":{"long":8921},"RBABYTE":{"long":352},"UBAFIL":{"long":11},"UBABLK":{"long":0},"UBAREC":{"long":0},"UBASQN":{"long":0},"ABS_FILE_NUM":{"long":0},"REL_FILE_NUM":{"long":0},"DATA_BLK_NUM":{"long":0},"DATA_OBJ_NUM":{"long":72994},"DATA_OBJV_NUM":{"long":2},"DATA_OBJD_NUM":{"long":0},"SQL_REDO":{"string":"XML_REDO := '<Warehouse whNo=\"4\"> <Building>Owned</Building></Warehouse>'\n amount: 59"},"SQL_UNDO":null,"RS_ID":{"string":" 0x000007.000022d9.0160 "},"SSN":{"long":0},"CSF":{"boolean":false},"INFO":{"string":"XML sql_redo not re-executable"},"STATUS":{"int":2},"REDO_VALUE":{"long":18},"UNDO_VALUE":{"long":19},"SAFE_RESUME_SCN":{"long":0},"CSCN":{"long":2167714},"OBJECT_ID":null,"EDITION_NAME":null,"CLIENT_ID":null,"SRC_CON_NAME":{"string":"ORCLPDB1"},"SRC_CON_ID":{"long":3},"SRC_CON_UID":{"long":280798746},"SRC_CON_DBID":{"long":0},"SRC_CON_GUID":null,"CON_ID":{"boolean":false}}
# {"SCN":{"long":2167711},"START_SCN":{"long":2167711},"COMMIT_SCN":{"long":2167714},"TIMESTAMP":{"long":1655381242000},"START_TIMESTAMP":{"long":1655381242000},"COMMIT_TIMESTAMP":{"long":1655381242000},"XIDUSN":{"long":10},"XIDSLT":{"long":21},"XIDSQN":{"long":648},"XID":{"bytes":"\n\u0000\u0015\u0000\u0002\u0000\u0000"},"PXIDUSN":{"long":10},"PXIDSLT":{"long":21},"PXIDSQN":{"long":648},"PXID":{"bytes":"\n\u0000\u0015\u0000\u0002\u0000\u0000"},"TX_NAME":null,"OPERATION":{"string":"XML DOC END"},"OPERATION_CODE":{"int":71},"ROLLBACK":{"boolean":false},"SEG_OWNER":{"string":"C##MYUSER"},"SEG_NAME":{"string":"CUSTOMERS"},"TABLE_NAME":{"string":"CUSTOMERS"},"SEG_TYPE":{"int":2},"SEG_TYPE_NAME":{"string":"TABLE"},"TABLE_SPACE":{"string":"USERS"},"ROW_ID":{"string":"AAAAAAAAAAAAAAAAAA"},"USERNAME":{"string":"C##MYUSER"},"OS_USERNAME":{"string":"oracle"},"MACHINE_NAME":{"string":"oracle"},"AUDIT_SESSIONID":{"long":30},"SESSION_NUM":{"long":186},"SERIAL_NUM":{"long":7500},"SESSION_INFO":{"string":"login_username=C##MYUSER client_info= OS_username=oracle Machine_name=oracle OS_terminal=pts/0 OS_process_id=557 OS_program_name=sqlplus@oracle (TNS V1-V3)"},"THREAD_NUM":{"long":1},"SEQUENCE_NUM":{"long":5},"RBASQN":{"long":7},"RBABLK":{"long":8921},"RBABYTE":{"long":352},"UBAFIL":{"long":11},"UBABLK":{"long":0},"UBAREC":{"long":0},"UBASQN":{"long":0},"ABS_FILE_NUM":{"long":0},"REL_FILE_NUM":{"long":0},"DATA_BLK_NUM":{"long":0},"DATA_OBJ_NUM":{"long":72994},"DATA_OBJV_NUM":{"long":2},"DATA_OBJD_NUM":{"long":0},"SQL_REDO":null,"SQL_UNDO":null,"RS_ID":{"string":" 0x000007.000022d9.0160 "},"SSN":{"long":0},"CSF":{"boolean":false},"INFO":null,"STATUS":{"int":0},"REDO_VALUE":{"long":20},"UNDO_VALUE":{"long":21},"SAFE_RESUME_SCN":{"long":0},"CSCN":{"long":2167714},"OBJECT_ID":null,"EDITION_NAME":null,"CLIENT_ID":null,"SRC_CON_NAME":{"string":"ORCLPDB1"},"SRC_CON_ID":{"long":3},"SRC_CON_UID":{"long":280798746},"SRC_CON_DBID":{"long":0},"SRC_CON_GUID":null,"CON_ID":{"boolean":false}}
# {"SCN":{"long":2167714},"START_SCN":{"long":2167711},"COMMIT_SCN":{"long":2167714},"TIMESTAMP":{"long":1655381242000},"START_TIMESTAMP":{"long":1655381242000},"COMMIT_TIMESTAMP":{"long":1655381242000},"XIDUSN":{"long":10},"XIDSLT":{"long":21},"XIDSQN":{"long":648},"XID":{"bytes":"\n\u0000\u0015\u0000\u0002\u0000\u0000"},"PXIDUSN":{"long":10},"PXIDSLT":{"long":21},"PXIDSQN":{"long":648},"PXID":{"bytes":"\n\u0000\u0015\u0000\u0002\u0000\u0000"},"TX_NAME":null,"OPERATION":{"string":"COMMIT"},"OPERATION_CODE":{"int":7},"ROLLBACK":{"boolean":false},"SEG_OWNER":null,"SEG_NAME":null,"TABLE_NAME":null,"SEG_TYPE":{"int":0},"SEG_TYPE_NAME":null,"TABLE_SPACE":null,"ROW_ID":{"string":"AAAAAAAAAAAAAAAAAA"},"USERNAME":{"string":"C##MYUSER"},"OS_USERNAME":{"string":"oracle"},"MACHINE_NAME":{"string":"oracle"},"AUDIT_SESSIONID":{"long":30},"SESSION_NUM":{"long":186},"SERIAL_NUM":{"long":7500},"SESSION_INFO":{"string":"login_username=C##MYUSER client_info= OS_username=oracle Machine_name=oracle OS_terminal=pts/0 OS_process_id=557 OS_program_name=sqlplus@oracle (TNS V1-V3)"},"THREAD_NUM":{"long":1},"SEQUENCE_NUM":{"long":7},"RBASQN":{"long":7},"RBABLK":{"long":8924},"RBABYTE":{"long":276},"UBAFIL":{"long":11},"UBABLK":{"long":0},"UBAREC":{"long":0},"UBASQN":{"long":0},"ABS_FILE_NUM":{"long":11},"REL_FILE_NUM":{"long":0},"DATA_BLK_NUM":{"long":0},"DATA_OBJ_NUM":{"long":0},"DATA_OBJV_NUM":{"long":0},"DATA_OBJD_NUM":{"long":0},"SQL_REDO":{"string":"commit;"},"SQL_UNDO":null,"RS_ID":{"string":" 0x000007.000022dc.0114 "},"SSN":{"long":0},"CSF":{"boolean":false},"INFO":null,"STATUS":{"int":0},"REDO_VALUE":{"long":24},"UNDO_VALUE":{"long":25},"SAFE_RESUME_SCN":{"long":2167714},"CSCN":{"long":2167714},"OBJECT_ID":null,"EDITION_NAME":null,"CLIENT_ID":null,"SRC_CON_NAME":{"string":"ORCLPDB1"},"SRC_CON_ID":{"long":3},"SRC_CON_UID":{"long":280798746},"SRC_CON_DBID":{"long":0},"SRC_CON_GUID":null,"CON_ID":{"boolean":false}}

log "Verifying lob topic CUSTOMERS-XMLRECORD: there should be 2 records"
timeout 20 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic CUSTOMERS-XMLRECORD --from-beginning  --max-messages 2
# "<Warehouse whNo=\"3\"> <Building>Owned</Building></Warehouse>"
# "<Warehouse whNo=\"4\"> <Building>Owned</Building></Warehouse>"

log "Now restart the tasks"
# https://confluent.slack.com/archives/C03KEUWN8EL/p1655376778232009
curl -X POST localhost:8083/connectors/cdc-oracle-source-pdb/tasks/0/restart
curl -X POST localhost:8083/connectors/cdc-oracle-source-pdb/tasks/1/restart

sleep 60

log "Insert record id 5"
docker exec -i oracle sqlplus C\#\#MYUSER/mypassword@//localhost:1521/ORCLPDB1 << EOF
  insert into CUSTOMERS (RECID, XMLRECORD) values ('5',XMLType('<Warehouse whNo="5"> <Building>Owned</Building></Warehouse>'));
  exit;
EOF

# After restart of tasks:

# [2022-06-16 12:15:43,129] TRACE [cdc-oracle-source-pdb|task-1|changeEvent] LOB records: [] (io.confluent.connect.oracle.cdc.ChangeEventGenerator:513)
# [2022-06-16 12:15:43,130] TRACE [cdc-oracle-source-pdb|task-1|changeEvent] Table schema Schema{STRUCT} did not contain LOB fields, skipping LOB convertor for Struct{SCN=2169566,START_SCN=2169562,COMMIT_SCN=2169566,TIMESTAMP=Thu Jun 16 12:15:38 GMT 2022,START_TIMESTAMP=Thu Jun 16 12:15:38 GMT 2022,COMMIT_TIMESTAMP=Thu Jun 16 12:15:38 GMT 2022,XIDUSN=9,XIDSLT=5,XIDSQN=634,XID=java.nio.HeapByteBuffer[pos=0 lim=8 cap=8],PXIDUSN=9,PXIDSLT=5,PXIDSQN=634,PXID=java.nio.HeapByteBuffer[pos=0 lim=8 cap=8],OPERATION=COMMIT,OPERATION_CODE=7,ROLLBACK=false,SEG_TYPE=0,ROW_ID=AAAAAAAAAAAAAAAAAA,USERNAME=C##MYUSER,OS_USERNAME=oracle,MACHINE_NAME=oracle,AUDIT_SESSIONID=31,SESSION_NUM=185,SERIAL_NUM=55285,SESSION_INFO=login_username=C##MYUSER client_info= OS_username=oracle Machine_name=oracle OS_terminal=pts/0 OS_process_id=818 OS_program_name=sqlplus@oracle (TNS V1-V3),THREAD_NUM=1,SEQUENCE_NUM=7,RBASQN=7,RBABLK=10118,RBABYTE=276,UBAFIL=11,UBABLK=0,UBAREC=0,UBASQN=0,ABS_FILE_NUM=11,REL_FILE_NUM=0,DATA_BLK_NUM=0,DATA_OBJ_NUM=0,DATA_OBJV_NUM=0,DATA_OBJD_NUM=0,SQL_REDO=commit;,RS_ID= 0x000007.00002786.0114 ,SSN=0,CSF=false,STATUS=0,REDO_VALUE=30,UNDO_VALUE=31,SAFE_RESUME_SCN=2169566,CSCN=2169566,SRC_CON_NAME=ORCLPDB1,SRC_CON_ID=3,SRC_CON_UID=280798746,SRC_CON_DBID=0,CON_ID=false} (io.confluent.connect.oracle.cdc.record.OracleLobRecordConverter:85)


log "Verifying table topic ORCLPDB1.C__MYUSER.CUSTOMERS: there should be 3 records"
timeout 20 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic ORCLPDB1.C__MYUSER.CUSTOMERS --from-beginning  --max-messages 3

# "XMLRECORD":null !!
# {"RECID":"5","XMLRECORD":null,"table":{"string":"ORCLPDB1.C##MYUSER.CUSTOMERS"},"scn":{"string":"2169562"},"op_type":{"string":"I"},"op_ts":{"string":"1655381738000"},"current_ts":{"string":"1655381743114"},"row_id":{"string":"AAAAAAAAAAAAAAAAAA"},"username":{"string":"C##MYUSER"}

# schema is updated with XMLRECORD:

# {
#   "fields": [
#     {
#       "name": "RECID",
#       "type": "string"
#     },
#     {
#       "default": null,
#       "name": "XMLRECORD",
#       "type": [
#         "null",
#         "bytes"
#       ]
#     },
#     {
#       "default": null,
#       "name": "table",
#       "type": [
#         "null",
#         "string"
#       ]
#     },
#     {
#       "default": null,
#       "name": "scn",
#       "type": [
#         "null",
#         "string"
#       ]
#     },
#     {
#       "default": null,
#       "name": "op_type",
#       "type": [
#         "null",
#         "string"
#       ]
#     },
#     {
#       "default": null,
#       "name": "op_ts",
#       "type": [
#         "null",
#         "string"
#       ]
#     },
#     {
#       "default": null,
#       "name": "current_ts",
#       "type": [
#         "null",
#         "string"
#       ]
#     },
#     {
#       "default": null,
#       "name": "row_id",
#       "type": [
#         "null",
#         "string"
#       ]
#     },
#     {
#       "default": null,
#       "name": "username",
#       "type": [
#         "null",
#         "string"
#       ]
#     }
#   ],
#   "name": "ConnectDefault",
#   "namespace": "io.confluent.connect.avro",
#   "type": "record"
# }

log "Verifying lob topic CUSTOMERS-XMLRECORD: there should be 3 records, but there is only 2 !!"
timeout 20 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic CUSTOMERS-XMLRECORD --from-beginning  --max-messages 3
# "<Warehouse whNo=\"3\"> <Building>Owned</Building></Warehouse>"
# "<Warehouse whNo=\"4\"> <Building>Owned</Building></Warehouse>"


log "Verifying topic redo-log-topic: there should be 15 records"
timeout 20 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic redo-log-topic --from-beginning --max-messages 15

# {"SCN":{"long":2167694},"START_SCN":{"long":2167694},"COMMIT_SCN":{"long":2167698},"TIMESTAMP":{"long":1655381241000},"START_TIMESTAMP":{"long":1655381241000},"COMMIT_TIMESTAMP":{"long":1655381241000},"XIDUSN":{"long":10},"XIDSLT":{"long":19},"XIDSQN":{"long":648},"XID":{"bytes":"\n\u0000\u0013\u0000\u0002\u0000\u0000"},"PXIDUSN":{"long":10},"PXIDSLT":{"long":19},"PXIDSQN":{"long":648},"PXID":{"bytes":"\n\u0000\u0013\u0000\u0002\u0000\u0000"},"TX_NAME":null,"OPERATION":{"string":"INSERT"},"OPERATION_CODE":{"int":1},"ROLLBACK":{"boolean":false},"SEG_OWNER":{"string":"C##MYUSER"},"SEG_NAME":{"string":"CUSTOMERS"},"TABLE_NAME":{"string":"CUSTOMERS"},"SEG_TYPE":{"int":2},"SEG_TYPE_NAME":{"string":"TABLE"},"TABLE_SPACE":{"string":"USERS"},"ROW_ID":{"string":"AAAAAAAAAAAAAAAAAA"},"USERNAME":{"string":"C##MYUSER"},"OS_USERNAME":{"string":"oracle"},"MACHINE_NAME":{"string":"oracle"},"AUDIT_SESSIONID":{"long":29},"SESSION_NUM":{"long":186},"SERIAL_NUM":{"long":64715},"SESSION_INFO":{"string":"login_username=C##MYUSER client_info= OS_username=oracle Machine_name=oracle OS_terminal=pts/0 OS_process_id=548 OS_program_name=sqlplus@oracle (TNS V1-V3)"},"THREAD_NUM":{"long":1},"SEQUENCE_NUM":{"long":2},"RBASQN":{"long":7},"RBABLK":{"long":8907},"RBABYTE":{"long":384},"UBAFIL":{"long":11},"UBABLK":{"long":0},"UBAREC":{"long":0},"UBASQN":{"long":0},"ABS_FILE_NUM":{"long":0},"REL_FILE_NUM":{"long":0},"DATA_BLK_NUM":{"long":0},"DATA_OBJ_NUM":{"long":72994},"DATA_OBJV_NUM":{"long":2},"DATA_OBJD_NUM":{"long":0},"SQL_REDO":{"string":"insert into \"C##MYUSER\".\"CUSTOMERS\"(\"RECID\") values ('3');"},"SQL_UNDO":{"string":"delete from \"C##MYUSER\".\"CUSTOMERS\" a where a.\"RECID\" = '3' and a.ROWID = 'AAAAAAAAAAAAAAAAAA';"},"RS_ID":{"string":" 0x000007.000022cb.0180 "},"SSN":{"long":0},"CSF":{"boolean":false},"INFO":null,"STATUS":{"int":0},"REDO_VALUE":{"long":20},"UNDO_VALUE":{"long":21},"SAFE_RESUME_SCN":{"long":0},"CSCN":{"long":2167698},"OBJECT_ID":null,"EDITION_NAME":null,"CLIENT_ID":null,"SRC_CON_NAME":{"string":"ORCLPDB1"},"SRC_CON_ID":{"long":3},"SRC_CON_UID":{"long":280798746},"SRC_CON_DBID":{"long":0},"SRC_CON_GUID":null,"CON_ID":{"boolean":false}}
# {"SCN":{"long":2167695},"START_SCN":{"long":2167694},"COMMIT_SCN":{"long":2167698},"TIMESTAMP":{"long":1655381241000},"START_TIMESTAMP":{"long":1655381241000},"COMMIT_TIMESTAMP":{"long":1655381241000},"XIDUSN":{"long":10},"XIDSLT":{"long":19},"XIDSQN":{"long":648},"XID":{"bytes":"\n\u0000\u0013\u0000\u0002\u0000\u0000"},"PXIDUSN":{"long":10},"PXIDSLT":{"long":19},"PXIDSQN":{"long":648},"PXID":{"bytes":"\n\u0000\u0013\u0000\u0002\u0000\u0000"},"TX_NAME":null,"OPERATION":{"string":"XML DOC BEGIN"},"OPERATION_CODE":{"int":68},"ROLLBACK":{"boolean":false},"SEG_OWNER":{"string":"C##MYUSER"},"SEG_NAME":{"string":"CUSTOMERS"},"TABLE_NAME":{"string":"CUSTOMERS"},"SEG_TYPE":{"int":2},"SEG_TYPE_NAME":{"string":"TABLE"},"TABLE_SPACE":{"string":"USERS"},"ROW_ID":{"string":"AAAAAAAAAAAAAAAAAA"},"USERNAME":{"string":"C##MYUSER"},"OS_USERNAME":{"string":"oracle"},"MACHINE_NAME":{"string":"oracle"},"AUDIT_SESSIONID":{"long":29},"SESSION_NUM":{"long":186},"SERIAL_NUM":{"long":64715},"SESSION_INFO":{"string":"login_username=C##MYUSER client_info= OS_username=oracle Machine_name=oracle OS_terminal=pts/0 OS_process_id=548 OS_program_name=sqlplus@oracle (TNS V1-V3)"},"THREAD_NUM":{"long":1},"SEQUENCE_NUM":{"long":3},"RBASQN":{"long":7},"RBABLK":{"long":8910},"RBABYTE":{"long":312},"UBAFIL":{"long":11},"UBABLK":{"long":0},"UBAREC":{"long":0},"UBASQN":{"long":0},"ABS_FILE_NUM":{"long":0},"REL_FILE_NUM":{"long":0},"DATA_BLK_NUM":{"long":0},"DATA_OBJ_NUM":{"long":72994},"DATA_OBJV_NUM":{"long":2},"DATA_OBJD_NUM":{"long":0},"SQL_REDO":{"string":"XML DOC BEGIN:  select \"XMLRECORD\" from \"C##MYUSER\".\"CUSTOMERS\" where \"RECID\" = '3'"},"SQL_UNDO":null,"RS_ID":{"string":" 0x000007.000022ce.0138 "},"SSN":{"long":0},"CSF":{"boolean":false},"INFO":{"string":"XML sql_redo not re-executable"},"STATUS":{"int":2},"REDO_VALUE":{"long":22},"UNDO_VALUE":{"long":23},"SAFE_RESUME_SCN":{"long":0},"CSCN":{"long":2167698},"OBJECT_ID":null,"EDITION_NAME":null,"CLIENT_ID":null,"SRC_CON_NAME":{"string":"ORCLPDB1"},"SRC_CON_ID":{"long":3},"SRC_CON_UID":{"long":280798746},"SRC_CON_DBID":{"long":0},"SRC_CON_GUID":null,"CON_ID":{"boolean":false}}
# {"SCN":{"long":2167695},"START_SCN":{"long":2167694},"COMMIT_SCN":{"long":2167698},"TIMESTAMP":{"long":1655381241000},"START_TIMESTAMP":{"long":1655381241000},"COMMIT_TIMESTAMP":{"long":1655381241000},"XIDUSN":{"long":10},"XIDSLT":{"long":19},"XIDSQN":{"long":648},"XID":{"bytes":"\n\u0000\u0013\u0000\u0002\u0000\u0000"},"PXIDUSN":{"long":10},"PXIDSLT":{"long":19},"PXIDSQN":{"long":648},"PXID":{"bytes":"\n\u0000\u0013\u0000\u0002\u0000\u0000"},"TX_NAME":null,"OPERATION":{"string":"XML DOC WRITE"},"OPERATION_CODE":{"int":70},"ROLLBACK":{"boolean":false},"SEG_OWNER":{"string":"C##MYUSER"},"SEG_NAME":{"string":"CUSTOMERS"},"TABLE_NAME":{"string":"CUSTOMERS"},"SEG_TYPE":{"int":2},"SEG_TYPE_NAME":{"string":"TABLE"},"TABLE_SPACE":{"string":"USERS"},"ROW_ID":{"string":"AAAAAAAAAAAAAAAAAA"},"USERNAME":{"string":"C##MYUSER"},"OS_USERNAME":{"string":"oracle"},"MACHINE_NAME":{"string":"oracle"},"AUDIT_SESSIONID":{"long":29},"SESSION_NUM":{"long":186},"SERIAL_NUM":{"long":64715},"SESSION_INFO":{"string":"login_username=C##MYUSER client_info= OS_username=oracle Machine_name=oracle OS_terminal=pts/0 OS_process_id=548 OS_program_name=sqlplus@oracle (TNS V1-V3)"},"THREAD_NUM":{"long":1},"SEQUENCE_NUM":{"long":4},"RBASQN":{"long":7},"RBABLK":{"long":8910},"RBABYTE":{"long":312},"UBAFIL":{"long":11},"UBABLK":{"long":0},"UBAREC":{"long":0},"UBASQN":{"long":0},"ABS_FILE_NUM":{"long":0},"REL_FILE_NUM":{"long":0},"DATA_BLK_NUM":{"long":0},"DATA_OBJ_NUM":{"long":72994},"DATA_OBJV_NUM":{"long":2},"DATA_OBJD_NUM":{"long":0},"SQL_REDO":{"string":"XML_REDO := '<Warehouse whNo=\"3\"> <Building>Owned</Building></Warehouse>'\n amount: 59"},"SQL_UNDO":null,"RS_ID":{"string":" 0x000007.000022ce.0138 "},"SSN":{"long":0},"CSF":{"boolean":false},"INFO":{"string":"XML sql_redo not re-executable"},"STATUS":{"int":2},"REDO_VALUE":{"long":24},"UNDO_VALUE":{"long":25},"SAFE_RESUME_SCN":{"long":0},"CSCN":{"long":2167698},"OBJECT_ID":null,"EDITION_NAME":null,"CLIENT_ID":null,"SRC_CON_NAME":{"string":"ORCLPDB1"},"SRC_CON_ID":{"long":3},"SRC_CON_UID":{"long":280798746},"SRC_CON_DBID":{"long":0},"SRC_CON_GUID":null,"CON_ID":{"boolean":false}}
# {"SCN":{"long":2167695},"START_SCN":{"long":2167694},"COMMIT_SCN":{"long":2167698},"TIMESTAMP":{"long":1655381241000},"START_TIMESTAMP":{"long":1655381241000},"COMMIT_TIMESTAMP":{"long":1655381241000},"XIDUSN":{"long":10},"XIDSLT":{"long":19},"XIDSQN":{"long":648},"XID":{"bytes":"\n\u0000\u0013\u0000\u0002\u0000\u0000"},"PXIDUSN":{"long":10},"PXIDSLT":{"long":19},"PXIDSQN":{"long":648},"PXID":{"bytes":"\n\u0000\u0013\u0000\u0002\u0000\u0000"},"TX_NAME":null,"OPERATION":{"string":"XML DOC END"},"OPERATION_CODE":{"int":71},"ROLLBACK":{"boolean":false},"SEG_OWNER":{"string":"C##MYUSER"},"SEG_NAME":{"string":"CUSTOMERS"},"TABLE_NAME":{"string":"CUSTOMERS"},"SEG_TYPE":{"int":2},"SEG_TYPE_NAME":{"string":"TABLE"},"TABLE_SPACE":{"string":"USERS"},"ROW_ID":{"string":"AAAAAAAAAAAAAAAAAA"},"USERNAME":{"string":"C##MYUSER"},"OS_USERNAME":{"string":"oracle"},"MACHINE_NAME":{"string":"oracle"},"AUDIT_SESSIONID":{"long":29},"SESSION_NUM":{"long":186},"SERIAL_NUM":{"long":64715},"SESSION_INFO":{"string":"login_username=C##MYUSER client_info= OS_username=oracle Machine_name=oracle OS_terminal=pts/0 OS_process_id=548 OS_program_name=sqlplus@oracle (TNS V1-V3)"},"THREAD_NUM":{"long":1},"SEQUENCE_NUM":{"long":5},"RBASQN":{"long":7},"RBABLK":{"long":8910},"RBABYTE":{"long":312},"UBAFIL":{"long":11},"UBABLK":{"long":0},"UBAREC":{"long":0},"UBASQN":{"long":0},"ABS_FILE_NUM":{"long":0},"REL_FILE_NUM":{"long":0},"DATA_BLK_NUM":{"long":0},"DATA_OBJ_NUM":{"long":72994},"DATA_OBJV_NUM":{"long":2},"DATA_OBJD_NUM":{"long":0},"SQL_REDO":null,"SQL_UNDO":null,"RS_ID":{"string":" 0x000007.000022ce.0138 "},"SSN":{"long":0},"CSF":{"boolean":false},"INFO":null,"STATUS":{"int":0},"REDO_VALUE":{"long":26},"UNDO_VALUE":{"long":27},"SAFE_RESUME_SCN":{"long":0},"CSCN":{"long":2167698},"OBJECT_ID":null,"EDITION_NAME":null,"CLIENT_ID":null,"SRC_CON_NAME":{"string":"ORCLPDB1"},"SRC_CON_ID":{"long":3},"SRC_CON_UID":{"long":280798746},"SRC_CON_DBID":{"long":0},"SRC_CON_GUID":null,"CON_ID":{"boolean":false}}
# {"SCN":{"long":2167698},"START_SCN":{"long":2167694},"COMMIT_SCN":{"long":2167698},"TIMESTAMP":{"long":1655381241000},"START_TIMESTAMP":{"long":1655381241000},"COMMIT_TIMESTAMP":{"long":1655381241000},"XIDUSN":{"long":10},"XIDSLT":{"long":19},"XIDSQN":{"long":648},"XID":{"bytes":"\n\u0000\u0013\u0000\u0002\u0000\u0000"},"PXIDUSN":{"long":10},"PXIDSLT":{"long":19},"PXIDSQN":{"long":648},"PXID":{"bytes":"\n\u0000\u0013\u0000\u0002\u0000\u0000"},"TX_NAME":null,"OPERATION":{"string":"COMMIT"},"OPERATION_CODE":{"int":7},"ROLLBACK":{"boolean":false},"SEG_OWNER":null,"SEG_NAME":null,"TABLE_NAME":null,"SEG_TYPE":{"int":0},"SEG_TYPE_NAME":null,"TABLE_SPACE":null,"ROW_ID":{"string":"AAAAAAAAAAAAAAAAAA"},"USERNAME":{"string":"C##MYUSER"},"OS_USERNAME":{"string":"oracle"},"MACHINE_NAME":{"string":"oracle"},"AUDIT_SESSIONID":{"long":29},"SESSION_NUM":{"long":186},"SERIAL_NUM":{"long":64715},"SESSION_INFO":{"string":"login_username=C##MYUSER client_info= OS_username=oracle Machine_name=oracle OS_terminal=pts/0 OS_process_id=548 OS_program_name=sqlplus@oracle (TNS V1-V3)"},"THREAD_NUM":{"long":1},"SEQUENCE_NUM":{"long":7},"RBASQN":{"long":7},"RBABLK":{"long":8912},"RBABYTE":{"long":276},"UBAFIL":{"long":11},"UBABLK":{"long":0},"UBAREC":{"long":0},"UBASQN":{"long":0},"ABS_FILE_NUM":{"long":11},"REL_FILE_NUM":{"long":0},"DATA_BLK_NUM":{"long":0},"DATA_OBJ_NUM":{"long":0},"DATA_OBJV_NUM":{"long":0},"DATA_OBJD_NUM":{"long":0},"SQL_REDO":{"string":"commit;"},"SQL_UNDO":null,"RS_ID":{"string":" 0x000007.000022d0.0114 "},"SSN":{"long":0},"CSF":{"boolean":false},"INFO":null,"STATUS":{"int":0},"REDO_VALUE":{"long":30},"UNDO_VALUE":{"long":31},"SAFE_RESUME_SCN":{"long":2167698},"CSCN":{"long":2167698},"OBJECT_ID":null,"EDITION_NAME":null,"CLIENT_ID":null,"SRC_CON_NAME":{"string":"ORCLPDB1"},"SRC_CON_ID":{"long":3},"SRC_CON_UID":{"long":280798746},"SRC_CON_DBID":{"long":0},"SRC_CON_GUID":null,"CON_ID":{"boolean":false}}
# {"SCN":{"long":2167711},"START_SCN":{"long":2167711},"COMMIT_SCN":{"long":2167714},"TIMESTAMP":{"long":1655381242000},"START_TIMESTAMP":{"long":1655381242000},"COMMIT_TIMESTAMP":{"long":1655381242000},"XIDUSN":{"long":10},"XIDSLT":{"long":21},"XIDSQN":{"long":648},"XID":{"bytes":"\n\u0000\u0015\u0000\u0002\u0000\u0000"},"PXIDUSN":{"long":10},"PXIDSLT":{"long":21},"PXIDSQN":{"long":648},"PXID":{"bytes":"\n\u0000\u0015\u0000\u0002\u0000\u0000"},"TX_NAME":null,"OPERATION":{"string":"INSERT"},"OPERATION_CODE":{"int":1},"ROLLBACK":{"boolean":false},"SEG_OWNER":{"string":"C##MYUSER"},"SEG_NAME":{"string":"CUSTOMERS"},"TABLE_NAME":{"string":"CUSTOMERS"},"SEG_TYPE":{"int":2},"SEG_TYPE_NAME":{"string":"TABLE"},"TABLE_SPACE":{"string":"USERS"},"ROW_ID":{"string":"AAAAAAAAAAAAAAAAAA"},"USERNAME":{"string":"C##MYUSER"},"OS_USERNAME":{"string":"oracle"},"MACHINE_NAME":{"string":"oracle"},"AUDIT_SESSIONID":{"long":30},"SESSION_NUM":{"long":186},"SERIAL_NUM":{"long":7500},"SESSION_INFO":{"string":"login_username=C##MYUSER client_info= OS_username=oracle Machine_name=oracle OS_terminal=pts/0 OS_process_id=557 OS_program_name=sqlplus@oracle (TNS V1-V3)"},"THREAD_NUM":{"long":1},"SEQUENCE_NUM":{"long":2},"RBASQN":{"long":7},"RBABLK":{"long":8920},"RBABYTE":{"long":384},"UBAFIL":{"long":11},"UBABLK":{"long":0},"UBAREC":{"long":0},"UBASQN":{"long":0},"ABS_FILE_NUM":{"long":0},"REL_FILE_NUM":{"long":0},"DATA_BLK_NUM":{"long":0},"DATA_OBJ_NUM":{"long":72994},"DATA_OBJV_NUM":{"long":2},"DATA_OBJD_NUM":{"long":0},"SQL_REDO":{"string":"insert into \"C##MYUSER\".\"CUSTOMERS\"(\"RECID\") values ('4');"},"SQL_UNDO":{"string":"delete from \"C##MYUSER\".\"CUSTOMERS\" a where a.\"RECID\" = '4' and a.ROWID = 'AAAAAAAAAAAAAAAAAA';"},"RS_ID":{"string":" 0x000007.000022d8.0180 "},"SSN":{"long":0},"CSF":{"boolean":false},"INFO":null,"STATUS":{"int":0},"REDO_VALUE":{"long":14},"UNDO_VALUE":{"long":15},"SAFE_RESUME_SCN":{"long":0},"CSCN":{"long":2167714},"OBJECT_ID":null,"EDITION_NAME":null,"CLIENT_ID":null,"SRC_CON_NAME":{"string":"ORCLPDB1"},"SRC_CON_ID":{"long":3},"SRC_CON_UID":{"long":280798746},"SRC_CON_DBID":{"long":0},"SRC_CON_GUID":null,"CON_ID":{"boolean":false}}
# {"SCN":{"long":2167711},"START_SCN":{"long":2167711},"COMMIT_SCN":{"long":2167714},"TIMESTAMP":{"long":1655381242000},"START_TIMESTAMP":{"long":1655381242000},"COMMIT_TIMESTAMP":{"long":1655381242000},"XIDUSN":{"long":10},"XIDSLT":{"long":21},"XIDSQN":{"long":648},"XID":{"bytes":"\n\u0000\u0015\u0000\u0002\u0000\u0000"},"PXIDUSN":{"long":10},"PXIDSLT":{"long":21},"PXIDSQN":{"long":648},"PXID":{"bytes":"\n\u0000\u0015\u0000\u0002\u0000\u0000"},"TX_NAME":null,"OPERATION":{"string":"XML DOC BEGIN"},"OPERATION_CODE":{"int":68},"ROLLBACK":{"boolean":false},"SEG_OWNER":{"string":"C##MYUSER"},"SEG_NAME":{"string":"CUSTOMERS"},"TABLE_NAME":{"string":"CUSTOMERS"},"SEG_TYPE":{"int":2},"SEG_TYPE_NAME":{"string":"TABLE"},"TABLE_SPACE":{"string":"USERS"},"ROW_ID":{"string":"AAAAAAAAAAAAAAAAAA"},"USERNAME":{"string":"C##MYUSER"},"OS_USERNAME":{"string":"oracle"},"MACHINE_NAME":{"string":"oracle"},"AUDIT_SESSIONID":{"long":30},"SESSION_NUM":{"long":186},"SERIAL_NUM":{"long":7500},"SESSION_INFO":{"string":"login_username=C##MYUSER client_info= OS_username=oracle Machine_name=oracle OS_terminal=pts/0 OS_process_id=557 OS_program_name=sqlplus@oracle (TNS V1-V3)"},"THREAD_NUM":{"long":1},"SEQUENCE_NUM":{"long":3},"RBASQN":{"long":7},"RBABLK":{"long":8921},"RBABYTE":{"long":352},"UBAFIL":{"long":11},"UBABLK":{"long":0},"UBAREC":{"long":0},"UBASQN":{"long":0},"ABS_FILE_NUM":{"long":0},"REL_FILE_NUM":{"long":0},"DATA_BLK_NUM":{"long":0},"DATA_OBJ_NUM":{"long":72994},"DATA_OBJV_NUM":{"long":2},"DATA_OBJD_NUM":{"long":0},"SQL_REDO":{"string":"XML DOC BEGIN:  select \"XMLRECORD\" from \"C##MYUSER\".\"CUSTOMERS\" where \"RECID\" = '4'"},"SQL_UNDO":null,"RS_ID":{"string":" 0x000007.000022d9.0160 "},"SSN":{"long":0},"CSF":{"boolean":false},"INFO":{"string":"XML sql_redo not re-executable"},"STATUS":{"int":2},"REDO_VALUE":{"long":16},"UNDO_VALUE":{"long":17},"SAFE_RESUME_SCN":{"long":0},"CSCN":{"long":2167714},"OBJECT_ID":null,"EDITION_NAME":null,"CLIENT_ID":null,"SRC_CON_NAME":{"string":"ORCLPDB1"},"SRC_CON_ID":{"long":3},"SRC_CON_UID":{"long":280798746},"SRC_CON_DBID":{"long":0},"SRC_CON_GUID":null,"CON_ID":{"boolean":false}}
# {"SCN":{"long":2167711},"START_SCN":{"long":2167711},"COMMIT_SCN":{"long":2167714},"TIMESTAMP":{"long":1655381242000},"START_TIMESTAMP":{"long":1655381242000},"COMMIT_TIMESTAMP":{"long":1655381242000},"XIDUSN":{"long":10},"XIDSLT":{"long":21},"XIDSQN":{"long":648},"XID":{"bytes":"\n\u0000\u0015\u0000\u0002\u0000\u0000"},"PXIDUSN":{"long":10},"PXIDSLT":{"long":21},"PXIDSQN":{"long":648},"PXID":{"bytes":"\n\u0000\u0015\u0000\u0002\u0000\u0000"},"TX_NAME":null,"OPERATION":{"string":"XML DOC WRITE"},"OPERATION_CODE":{"int":70},"ROLLBACK":{"boolean":false},"SEG_OWNER":{"string":"C##MYUSER"},"SEG_NAME":{"string":"CUSTOMERS"},"TABLE_NAME":{"string":"CUSTOMERS"},"SEG_TYPE":{"int":2},"SEG_TYPE_NAME":{"string":"TABLE"},"TABLE_SPACE":{"string":"USERS"},"ROW_ID":{"string":"AAAAAAAAAAAAAAAAAA"},"USERNAME":{"string":"C##MYUSER"},"OS_USERNAME":{"string":"oracle"},"MACHINE_NAME":{"string":"oracle"},"AUDIT_SESSIONID":{"long":30},"SESSION_NUM":{"long":186},"SERIAL_NUM":{"long":7500},"SESSION_INFO":{"string":"login_username=C##MYUSER client_info= OS_username=oracle Machine_name=oracle OS_terminal=pts/0 OS_process_id=557 OS_program_name=sqlplus@oracle (TNS V1-V3)"},"THREAD_NUM":{"long":1},"SEQUENCE_NUM":{"long":4},"RBASQN":{"long":7},"RBABLK":{"long":8921},"RBABYTE":{"long":352},"UBAFIL":{"long":11},"UBABLK":{"long":0},"UBAREC":{"long":0},"UBASQN":{"long":0},"ABS_FILE_NUM":{"long":0},"REL_FILE_NUM":{"long":0},"DATA_BLK_NUM":{"long":0},"DATA_OBJ_NUM":{"long":72994},"DATA_OBJV_NUM":{"long":2},"DATA_OBJD_NUM":{"long":0},"SQL_REDO":{"string":"XML_REDO := '<Warehouse whNo=\"4\"> <Building>Owned</Building></Warehouse>'\n amount: 59"},"SQL_UNDO":null,"RS_ID":{"string":" 0x000007.000022d9.0160 "},"SSN":{"long":0},"CSF":{"boolean":false},"INFO":{"string":"XML sql_redo not re-executable"},"STATUS":{"int":2},"REDO_VALUE":{"long":18},"UNDO_VALUE":{"long":19},"SAFE_RESUME_SCN":{"long":0},"CSCN":{"long":2167714},"OBJECT_ID":null,"EDITION_NAME":null,"CLIENT_ID":null,"SRC_CON_NAME":{"string":"ORCLPDB1"},"SRC_CON_ID":{"long":3},"SRC_CON_UID":{"long":280798746},"SRC_CON_DBID":{"long":0},"SRC_CON_GUID":null,"CON_ID":{"boolean":false}}
# {"SCN":{"long":2167711},"START_SCN":{"long":2167711},"COMMIT_SCN":{"long":2167714},"TIMESTAMP":{"long":1655381242000},"START_TIMESTAMP":{"long":1655381242000},"COMMIT_TIMESTAMP":{"long":1655381242000},"XIDUSN":{"long":10},"XIDSLT":{"long":21},"XIDSQN":{"long":648},"XID":{"bytes":"\n\u0000\u0015\u0000\u0002\u0000\u0000"},"PXIDUSN":{"long":10},"PXIDSLT":{"long":21},"PXIDSQN":{"long":648},"PXID":{"bytes":"\n\u0000\u0015\u0000\u0002\u0000\u0000"},"TX_NAME":null,"OPERATION":{"string":"XML DOC END"},"OPERATION_CODE":{"int":71},"ROLLBACK":{"boolean":false},"SEG_OWNER":{"string":"C##MYUSER"},"SEG_NAME":{"string":"CUSTOMERS"},"TABLE_NAME":{"string":"CUSTOMERS"},"SEG_TYPE":{"int":2},"SEG_TYPE_NAME":{"string":"TABLE"},"TABLE_SPACE":{"string":"USERS"},"ROW_ID":{"string":"AAAAAAAAAAAAAAAAAA"},"USERNAME":{"string":"C##MYUSER"},"OS_USERNAME":{"string":"oracle"},"MACHINE_NAME":{"string":"oracle"},"AUDIT_SESSIONID":{"long":30},"SESSION_NUM":{"long":186},"SERIAL_NUM":{"long":7500},"SESSION_INFO":{"string":"login_username=C##MYUSER client_info= OS_username=oracle Machine_name=oracle OS_terminal=pts/0 OS_process_id=557 OS_program_name=sqlplus@oracle (TNS V1-V3)"},"THREAD_NUM":{"long":1},"SEQUENCE_NUM":{"long":5},"RBASQN":{"long":7},"RBABLK":{"long":8921},"RBABYTE":{"long":352},"UBAFIL":{"long":11},"UBABLK":{"long":0},"UBAREC":{"long":0},"UBASQN":{"long":0},"ABS_FILE_NUM":{"long":0},"REL_FILE_NUM":{"long":0},"DATA_BLK_NUM":{"long":0},"DATA_OBJ_NUM":{"long":72994},"DATA_OBJV_NUM":{"long":2},"DATA_OBJD_NUM":{"long":0},"SQL_REDO":null,"SQL_UNDO":null,"RS_ID":{"string":" 0x000007.000022d9.0160 "},"SSN":{"long":0},"CSF":{"boolean":false},"INFO":null,"STATUS":{"int":0},"REDO_VALUE":{"long":20},"UNDO_VALUE":{"long":21},"SAFE_RESUME_SCN":{"long":0},"CSCN":{"long":2167714},"OBJECT_ID":null,"EDITION_NAME":null,"CLIENT_ID":null,"SRC_CON_NAME":{"string":"ORCLPDB1"},"SRC_CON_ID":{"long":3},"SRC_CON_UID":{"long":280798746},"SRC_CON_DBID":{"long":0},"SRC_CON_GUID":null,"CON_ID":{"boolean":false}}
# {"SCN":{"long":2167714},"START_SCN":{"long":2167711},"COMMIT_SCN":{"long":2167714},"TIMESTAMP":{"long":1655381242000},"START_TIMESTAMP":{"long":1655381242000},"COMMIT_TIMESTAMP":{"long":1655381242000},"XIDUSN":{"long":10},"XIDSLT":{"long":21},"XIDSQN":{"long":648},"XID":{"bytes":"\n\u0000\u0015\u0000\u0002\u0000\u0000"},"PXIDUSN":{"long":10},"PXIDSLT":{"long":21},"PXIDSQN":{"long":648},"PXID":{"bytes":"\n\u0000\u0015\u0000\u0002\u0000\u0000"},"TX_NAME":null,"OPERATION":{"string":"COMMIT"},"OPERATION_CODE":{"int":7},"ROLLBACK":{"boolean":false},"SEG_OWNER":null,"SEG_NAME":null,"TABLE_NAME":null,"SEG_TYPE":{"int":0},"SEG_TYPE_NAME":null,"TABLE_SPACE":null,"ROW_ID":{"string":"AAAAAAAAAAAAAAAAAA"},"USERNAME":{"string":"C##MYUSER"},"OS_USERNAME":{"string":"oracle"},"MACHINE_NAME":{"string":"oracle"},"AUDIT_SESSIONID":{"long":30},"SESSION_NUM":{"long":186},"SERIAL_NUM":{"long":7500},"SESSION_INFO":{"string":"login_username=C##MYUSER client_info= OS_username=oracle Machine_name=oracle OS_terminal=pts/0 OS_process_id=557 OS_program_name=sqlplus@oracle (TNS V1-V3)"},"THREAD_NUM":{"long":1},"SEQUENCE_NUM":{"long":7},"RBASQN":{"long":7},"RBABLK":{"long":8924},"RBABYTE":{"long":276},"UBAFIL":{"long":11},"UBABLK":{"long":0},"UBAREC":{"long":0},"UBASQN":{"long":0},"ABS_FILE_NUM":{"long":11},"REL_FILE_NUM":{"long":0},"DATA_BLK_NUM":{"long":0},"DATA_OBJ_NUM":{"long":0},"DATA_OBJV_NUM":{"long":0},"DATA_OBJD_NUM":{"long":0},"SQL_REDO":{"string":"commit;"},"SQL_UNDO":null,"RS_ID":{"string":" 0x000007.000022dc.0114 "},"SSN":{"long":0},"CSF":{"boolean":false},"INFO":null,"STATUS":{"int":0},"REDO_VALUE":{"long":24},"UNDO_VALUE":{"long":25},"SAFE_RESUME_SCN":{"long":2167714},"CSCN":{"long":2167714},"OBJECT_ID":null,"EDITION_NAME":null,"CLIENT_ID":null,"SRC_CON_NAME":{"string":"ORCLPDB1"},"SRC_CON_ID":{"long":3},"SRC_CON_UID":{"long":280798746},"SRC_CON_DBID":{"long":0},"SRC_CON_GUID":null,"CON_ID":{"boolean":false}}
# {"SCN":{"long":2169562},"START_SCN":{"long":2169562},"COMMIT_SCN":{"long":2169566},"TIMESTAMP":{"long":1655381738000},"START_TIMESTAMP":{"long":1655381738000},"COMMIT_TIMESTAMP":{"long":1655381738000},"XIDUSN":{"long":9},"XIDSLT":{"long":5},"XIDSQN":{"long":634},"XID":{"bytes":"\t\u0000\u0005\u0000z\u0002\u0000\u0000"},"PXIDUSN":{"long":9},"PXIDSLT":{"long":5},"PXIDSQN":{"long":634},"PXID":{"bytes":"\t\u0000\u0005\u0000z\u0002\u0000\u0000"},"TX_NAME":null,"OPERATION":{"string":"INSERT"},"OPERATION_CODE":{"int":1},"ROLLBACK":{"boolean":false},"SEG_OWNER":{"string":"C##MYUSER"},"SEG_NAME":{"string":"CUSTOMERS"},"TABLE_NAME":{"string":"CUSTOMERS"},"SEG_TYPE":{"int":2},"SEG_TYPE_NAME":{"string":"TABLE"},"TABLE_SPACE":{"string":"USERS"},"ROW_ID":{"string":"AAAAAAAAAAAAAAAAAA"},"USERNAME":{"string":"C##MYUSER"},"OS_USERNAME":{"string":"oracle"},"MACHINE_NAME":{"string":"oracle"},"AUDIT_SESSIONID":{"long":31},"SESSION_NUM":{"long":185},"SERIAL_NUM":{"long":55285},"SESSION_INFO":{"string":"login_username=C##MYUSER client_info= OS_username=oracle Machine_name=oracle OS_terminal=pts/0 OS_process_id=818 OS_program_name=sqlplus@oracle (TNS V1-V3)"},"THREAD_NUM":{"long":1},"SEQUENCE_NUM":{"long":2},"RBASQN":{"long":7},"RBABLK":{"long":10112},"RBABYTE":{"long":384},"UBAFIL":{"long":11},"UBABLK":{"long":0},"UBAREC":{"long":0},"UBASQN":{"long":0},"ABS_FILE_NUM":{"long":0},"REL_FILE_NUM":{"long":0},"DATA_BLK_NUM":{"long":0},"DATA_OBJ_NUM":{"long":72994},"DATA_OBJV_NUM":{"long":2},"DATA_OBJD_NUM":{"long":0},"SQL_REDO":{"string":"insert into \"C##MYUSER\".\"CUSTOMERS\"(\"RECID\") values ('5');"},"SQL_UNDO":{"string":"delete from \"C##MYUSER\".\"CUSTOMERS\" a where a.\"RECID\" = '5' and a.ROWID = 'AAAAAAAAAAAAAAAAAA';"},"RS_ID":{"string":" 0x000007.00002780.0180 "},"SSN":{"long":0},"CSF":{"boolean":false},"INFO":null,"STATUS":{"int":0},"REDO_VALUE":{"long":20},"UNDO_VALUE":{"long":21},"SAFE_RESUME_SCN":{"long":0},"CSCN":{"long":2169566},"OBJECT_ID":null,"EDITION_NAME":null,"CLIENT_ID":null,"SRC_CON_NAME":{"string":"ORCLPDB1"},"SRC_CON_ID":{"long":3},"SRC_CON_UID":{"long":280798746},"SRC_CON_DBID":{"long":0},"SRC_CON_GUID":null,"CON_ID":{"boolean":false}}
# {"SCN":{"long":2169563},"START_SCN":{"long":2169562},"COMMIT_SCN":{"long":2169566},"TIMESTAMP":{"long":1655381738000},"START_TIMESTAMP":{"long":1655381738000},"COMMIT_TIMESTAMP":{"long":1655381738000},"XIDUSN":{"long":9},"XIDSLT":{"long":5},"XIDSQN":{"long":634},"XID":{"bytes":"\t\u0000\u0005\u0000z\u0002\u0000\u0000"},"PXIDUSN":{"long":9},"PXIDSLT":{"long":5},"PXIDSQN":{"long":634},"PXID":{"bytes":"\t\u0000\u0005\u0000z\u0002\u0000\u0000"},"TX_NAME":null,"OPERATION":{"string":"XML DOC BEGIN"},"OPERATION_CODE":{"int":68},"ROLLBACK":{"boolean":false},"SEG_OWNER":{"string":"C##MYUSER"},"SEG_NAME":{"string":"CUSTOMERS"},"TABLE_NAME":{"string":"CUSTOMERS"},"SEG_TYPE":{"int":2},"SEG_TYPE_NAME":{"string":"TABLE"},"TABLE_SPACE":{"string":"USERS"},"ROW_ID":{"string":"AAAAAAAAAAAAAAAAAA"},"USERNAME":{"string":"C##MYUSER"},"OS_USERNAME":{"string":"oracle"},"MACHINE_NAME":{"string":"oracle"},"AUDIT_SESSIONID":{"long":31},"SESSION_NUM":{"long":185},"SERIAL_NUM":{"long":55285},"SESSION_INFO":{"string":"login_username=C##MYUSER client_info= OS_username=oracle Machine_name=oracle OS_terminal=pts/0 OS_process_id=818 OS_program_name=sqlplus@oracle (TNS V1-V3)"},"THREAD_NUM":{"long":1},"SEQUENCE_NUM":{"long":3},"RBASQN":{"long":7},"RBABLK":{"long":10115},"RBABYTE":{"long":360},"UBAFIL":{"long":11},"UBABLK":{"long":0},"UBAREC":{"long":0},"UBASQN":{"long":0},"ABS_FILE_NUM":{"long":0},"REL_FILE_NUM":{"long":0},"DATA_BLK_NUM":{"long":0},"DATA_OBJ_NUM":{"long":72994},"DATA_OBJV_NUM":{"long":2},"DATA_OBJD_NUM":{"long":0},"SQL_REDO":{"string":"XML DOC BEGIN:  select \"XMLRECORD\" from \"C##MYUSER\".\"CUSTOMERS\" where \"RECID\" = '5'"},"SQL_UNDO":null,"RS_ID":{"string":" 0x000007.00002783.0168 "},"SSN":{"long":0},"CSF":{"boolean":false},"INFO":{"string":"XML sql_redo not re-executable"},"STATUS":{"int":2},"REDO_VALUE":{"long":22},"UNDO_VALUE":{"long":23},"SAFE_RESUME_SCN":{"long":0},"CSCN":{"long":2169566},"OBJECT_ID":null,"EDITION_NAME":null,"CLIENT_ID":null,"SRC_CON_NAME":{"string":"ORCLPDB1"},"SRC_CON_ID":{"long":3},"SRC_CON_UID":{"long":280798746},"SRC_CON_DBID":{"long":0},"SRC_CON_GUID":null,"CON_ID":{"boolean":false}}
# {"SCN":{"long":2169563},"START_SCN":{"long":2169562},"COMMIT_SCN":{"long":2169566},"TIMESTAMP":{"long":1655381738000},"START_TIMESTAMP":{"long":1655381738000},"COMMIT_TIMESTAMP":{"long":1655381738000},"XIDUSN":{"long":9},"XIDSLT":{"long":5},"XIDSQN":{"long":634},"XID":{"bytes":"\t\u0000\u0005\u0000z\u0002\u0000\u0000"},"PXIDUSN":{"long":9},"PXIDSLT":{"long":5},"PXIDSQN":{"long":634},"PXID":{"bytes":"\t\u0000\u0005\u0000z\u0002\u0000\u0000"},"TX_NAME":null,"OPERATION":{"string":"XML DOC WRITE"},"OPERATION_CODE":{"int":70},"ROLLBACK":{"boolean":false},"SEG_OWNER":{"string":"C##MYUSER"},"SEG_NAME":{"string":"CUSTOMERS"},"TABLE_NAME":{"string":"CUSTOMERS"},"SEG_TYPE":{"int":2},"SEG_TYPE_NAME":{"string":"TABLE"},"TABLE_SPACE":{"string":"USERS"},"ROW_ID":{"string":"AAAAAAAAAAAAAAAAAA"},"USERNAME":{"string":"C##MYUSER"},"OS_USERNAME":{"string":"oracle"},"MACHINE_NAME":{"string":"oracle"},"AUDIT_SESSIONID":{"long":31},"SESSION_NUM":{"long":185},"SERIAL_NUM":{"long":55285},"SESSION_INFO":{"string":"login_username=C##MYUSER client_info= OS_username=oracle Machine_name=oracle OS_terminal=pts/0 OS_process_id=818 OS_program_name=sqlplus@oracle (TNS V1-V3)"},"THREAD_NUM":{"long":1},"SEQUENCE_NUM":{"long":4},"RBASQN":{"long":7},"RBABLK":{"long":10115},"RBABYTE":{"long":360},"UBAFIL":{"long":11},"UBABLK":{"long":0},"UBAREC":{"long":0},"UBASQN":{"long":0},"ABS_FILE_NUM":{"long":0},"REL_FILE_NUM":{"long":0},"DATA_BLK_NUM":{"long":0},"DATA_OBJ_NUM":{"long":72994},"DATA_OBJV_NUM":{"long":2},"DATA_OBJD_NUM":{"long":0},"SQL_REDO":{"string":"XML_REDO := '<Warehouse whNo=\"5\"> <Building>Owned</Building></Warehouse>'\n amount: 59"},"SQL_UNDO":null,"RS_ID":{"string":" 0x000007.00002783.0168 "},"SSN":{"long":0},"CSF":{"boolean":false},"INFO":{"string":"XML sql_redo not re-executable"},"STATUS":{"int":2},"REDO_VALUE":{"long":24},"UNDO_VALUE":{"long":25},"SAFE_RESUME_SCN":{"long":0},"CSCN":{"long":2169566},"OBJECT_ID":null,"EDITION_NAME":null,"CLIENT_ID":null,"SRC_CON_NAME":{"string":"ORCLPDB1"},"SRC_CON_ID":{"long":3},"SRC_CON_UID":{"long":280798746},"SRC_CON_DBID":{"long":0},"SRC_CON_GUID":null,"CON_ID":{"boolean":false}}
# {"SCN":{"long":2169563},"START_SCN":{"long":2169562},"COMMIT_SCN":{"long":2169566},"TIMESTAMP":{"long":1655381738000},"START_TIMESTAMP":{"long":1655381738000},"COMMIT_TIMESTAMP":{"long":1655381738000},"XIDUSN":{"long":9},"XIDSLT":{"long":5},"XIDSQN":{"long":634},"XID":{"bytes":"\t\u0000\u0005\u0000z\u0002\u0000\u0000"},"PXIDUSN":{"long":9},"PXIDSLT":{"long":5},"PXIDSQN":{"long":634},"PXID":{"bytes":"\t\u0000\u0005\u0000z\u0002\u0000\u0000"},"TX_NAME":null,"OPERATION":{"string":"XML DOC END"},"OPERATION_CODE":{"int":71},"ROLLBACK":{"boolean":false},"SEG_OWNER":{"string":"C##MYUSER"},"SEG_NAME":{"string":"CUSTOMERS"},"TABLE_NAME":{"string":"CUSTOMERS"},"SEG_TYPE":{"int":2},"SEG_TYPE_NAME":{"string":"TABLE"},"TABLE_SPACE":{"string":"USERS"},"ROW_ID":{"string":"AAAAAAAAAAAAAAAAAA"},"USERNAME":{"string":"C##MYUSER"},"OS_USERNAME":{"string":"oracle"},"MACHINE_NAME":{"string":"oracle"},"AUDIT_SESSIONID":{"long":31},"SESSION_NUM":{"long":185},"SERIAL_NUM":{"long":55285},"SESSION_INFO":{"string":"login_username=C##MYUSER client_info= OS_username=oracle Machine_name=oracle OS_terminal=pts/0 OS_process_id=818 OS_program_name=sqlplus@oracle (TNS V1-V3)"},"THREAD_NUM":{"long":1},"SEQUENCE_NUM":{"long":5},"RBASQN":{"long":7},"RBABLK":{"long":10115},"RBABYTE":{"long":360},"UBAFIL":{"long":11},"UBABLK":{"long":0},"UBAREC":{"long":0},"UBASQN":{"long":0},"ABS_FILE_NUM":{"long":0},"REL_FILE_NUM":{"long":0},"DATA_BLK_NUM":{"long":0},"DATA_OBJ_NUM":{"long":72994},"DATA_OBJV_NUM":{"long":2},"DATA_OBJD_NUM":{"long":0},"SQL_REDO":null,"SQL_UNDO":null,"RS_ID":{"string":" 0x000007.00002783.0168 "},"SSN":{"long":0},"CSF":{"boolean":false},"INFO":null,"STATUS":{"int":0},"REDO_VALUE":{"long":26},"UNDO_VALUE":{"long":27},"SAFE_RESUME_SCN":{"long":0},"CSCN":{"long":2169566},"OBJECT_ID":null,"EDITION_NAME":null,"CLIENT_ID":null,"SRC_CON_NAME":{"string":"ORCLPDB1"},"SRC_CON_ID":{"long":3},"SRC_CON_UID":{"long":280798746},"SRC_CON_DBID":{"long":0},"SRC_CON_GUID":null,"CON_ID":{"boolean":false}}
# {"SCN":{"long":2169566},"START_SCN":{"long":2169562},"COMMIT_SCN":{"long":2169566},"TIMESTAMP":{"long":1655381738000},"START_TIMESTAMP":{"long":1655381738000},"COMMIT_TIMESTAMP":{"long":1655381738000},"XIDUSN":{"long":9},"XIDSLT":{"long":5},"XIDSQN":{"long":634},"XID":{"bytes":"\t\u0000\u0005\u0000z\u0002\u0000\u0000"},"PXIDUSN":{"long":9},"PXIDSLT":{"long":5},"PXIDSQN":{"long":634},"PXID":{"bytes":"\t\u0000\u0005\u0000z\u0002\u0000\u0000"},"TX_NAME":null,"OPERATION":{"string":"COMMIT"},"OPERATION_CODE":{"int":7},"ROLLBACK":{"boolean":false},"SEG_OWNER":null,"SEG_NAME":null,"TABLE_NAME":null,"SEG_TYPE":{"int":0},"SEG_TYPE_NAME":null,"TABLE_SPACE":null,"ROW_ID":{"string":"AAAAAAAAAAAAAAAAAA"},"USERNAME":{"string":"C##MYUSER"},"OS_USERNAME":{"string":"oracle"},"MACHINE_NAME":{"string":"oracle"},"AUDIT_SESSIONID":{"long":31},"SESSION_NUM":{"long":185},"SERIAL_NUM":{"long":55285},"SESSION_INFO":{"string":"login_username=C##MYUSER client_info= OS_username=oracle Machine_name=oracle OS_terminal=pts/0 OS_process_id=818 OS_program_name=sqlplus@oracle (TNS V1-V3)"},"THREAD_NUM":{"long":1},"SEQUENCE_NUM":{"long":7},"RBASQN":{"long":7},"RBABLK":{"long":10118},"RBABYTE":{"long":276},"UBAFIL":{"long":11},"UBABLK":{"long":0},"UBAREC":{"long":0},"UBASQN":{"long":0},"ABS_FILE_NUM":{"long":11},"REL_FILE_NUM":{"long":0},"DATA_BLK_NUM":{"long":0},"DATA_OBJ_NUM":{"long":0},"DATA_OBJV_NUM":{"long":0},"DATA_OBJD_NUM":{"long":0},"SQL_REDO":{"string":"commit;"},"SQL_UNDO":null,"RS_ID":{"string":" 0x000007.00002786.0114 "},"SSN":{"long":0},"CSF":{"boolean":false},"INFO":null,"STATUS":{"int":0},"REDO_VALUE":{"long":30},"UNDO_VALUE":{"long":31},"SAFE_RESUME_SCN":{"long":2169566},"CSCN":{"long":2169566},"OBJECT_ID":null,"EDITION_NAME":null,"CLIENT_ID":null,"SRC_CON_NAME":{"string":"ORCLPDB1"},"SRC_CON_ID":{"long":3},"SRC_CON_UID":{"long":280798746},"SRC_CON_DBID":{"long":0},"SRC_CON_GUID":null,"CON_ID":{"boolean":false}}
# Processed a total of 15 messages