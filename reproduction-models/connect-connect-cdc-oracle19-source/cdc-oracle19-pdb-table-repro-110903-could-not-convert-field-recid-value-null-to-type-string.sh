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

curl --request PUT \
  --url http://localhost:8083/admin/loggers/io.confluent.connect.oracle.cdc \
  --header 'Accept: application/json' \
  --header 'Content-Type: application/json' \
  --data '{
 "level": "INFO"
}'

curl --request PUT \
  --url http://localhost:8083/admin/loggers/org.apache.kafka.connect.runtime.WorkerSourceTask \
  --header 'Accept: application/json' \
  --header 'Content-Type: application/json' \
  --data '{
 "level": "TRACE"
}'


docker exec -i oracle bash -c "mkdir -p /home/oracle/db_recovery_file_dest;ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
CONNECT sys/Admin123 AS SYSDBA
select current_scn from v\$database;
exit;
EOF

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
               "start.from":"snapshot",
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

log "delete record id 1"
docker exec -i oracle sqlplus C\#\#MYUSER/mypassword@//localhost:1521/ORCLPDB1 << EOF
  delete from CUSTOMERS where RECID = '1';
  exit;
EOF


set +e
log "Verifying table topic ORCLPDB1.C__MYUSER.CUSTOMERS: there should be 3 record"
timeout 20 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic ORCLPDB1.C__MYUSER.CUSTOMERS --from-beginning  --max-messages 3

# {"RECID":"1","table":{"string":"ORCLPDB1.C##MYUSER.CUSTOMERS"},"scn":{"string":"2172798"},"op_type":{"string":"R"},"op_ts":null,"current_ts":{"string":"1655974737314"},"row_id":null,"username":null}
# {"RECID":"2","table":{"string":"ORCLPDB1.C##MYUSER.CUSTOMERS"},"scn":{"string":"2172798"},"op_type":{"string":"R"},"op_ts":null,"current_ts":{"string":"1655974737320"},"row_id":null,"username":null}
# {"RECID":"1","table":{"string":"ORCLPDB1.C##MYUSER.CUSTOMERS"},"scn":{"string":"2172853"},"op_type":{"string":"D"},"op_ts":{"string":"1655974754000"},"current_ts":{"string":"1655974761362"},"row_id":{"string":"AAAR1AAAMAAAACFAAA"},"username":{"string":"C##MYUSER"}}

log "Verifying lob topic CUSTOMERS-XMLRECORD: there should be 3 records"
timeout 20 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic CUSTOMERS-XMLRECORD --from-beginning  --max-messages 3
# "<Warehouse whNo=\"3\"> <Building>Owned</Building></Warehouse>"
# "<Warehouse whNo=\"4\"> <Building>Owned</Building></Warehouse>"
# null


log "Verifying topic redo-log-topic: there should be 2 records"
timeout 20 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic redo-log-topic --from-beginning --max-messages 2


# {"SCN":{"long":2172853},"START_SCN":{"long":2172853},"COMMIT_SCN":{"long":2172854},"TIMESTAMP":{"long":1655974754000},"START_TIMESTAMP":{"long":1655974754000},"COMMIT_TIMESTAMP":{"long":1655974754000},"XIDUSN":{"long":3},"XIDSLT":{"long":14},"XIDSQN":{"long":716},"XID":{"bytes":"\u0003\u0000\u000E\u0000Ì\u0002\u0000\u0000"},"PXIDUSN":{"long":3},"PXIDSLT":{"long":14},"PXIDSQN":{"long":716},"PXID":{"bytes":"\u0003\u0000\u000E\u0000Ì\u0002\u0000\u0000"},"TX_NAME":null,"OPERATION":{"string":"DELETE"},"OPERATION_CODE":{"int":2},"ROLLBACK":{"boolean":false},"SEG_OWNER":{"string":"C##MYUSER"},"SEG_NAME":{"string":"CUSTOMERS"},"TABLE_NAME":{"string":"CUSTOMERS"},"SEG_TYPE":{"int":2},"SEG_TYPE_NAME":{"string":"TABLE"},"TABLE_SPACE":{"string":"USERS"},"ROW_ID":{"string":"AAAR1AAAMAAAACFAAA"},"USERNAME":{"string":"C##MYUSER"},"OS_USERNAME":{"string":"UNKNOWN"},"MACHINE_NAME":{"string":"UNKNOWN"},"AUDIT_SESSIONID":{"long":40001},"SESSION_NUM":{"long":501},"SERIAL_NUM":{"long":47243},"SESSION_INFO":{"string":"UNKNOWN"},"THREAD_NUM":{"long":1},"SEQUENCE_NUM":{"long":2},"RBASQN":{"long":7},"RBABLK":{"long":141495},"RBABYTE":{"long":16},"UBAFIL":{"long":11},"UBABLK":{"long":0},"UBAREC":{"long":0},"UBASQN":{"long":0},"ABS_FILE_NUM":{"long":11},"REL_FILE_NUM":{"long":12},"DATA_BLK_NUM":{"long":133},"DATA_OBJ_NUM":{"long":73024},"DATA_OBJV_NUM":{"long":2},"DATA_OBJD_NUM":{"long":73024},"SQL_REDO":{"string":"delete from \"C##MYUSER\".\"CUSTOMERS\" a where a.\"RECID\" = '1' and a.ROWID = 'AAAR1AAAMAAAACFAAA';"},"SQL_UNDO":{"string":"insert into \"C##MYUSER\".\"CUSTOMERS\"(\"RECID\") values ('1');"},"RS_ID":{"string":" 0x000007.000228b7.0010 "},"SSN":{"long":0},"CSF":{"boolean":false},"INFO":null,"STATUS":{"int":0},"REDO_VALUE":{"long":2},"UNDO_VALUE":{"long":3},"SAFE_RESUME_SCN":{"long":0},"CSCN":{"long":2172854},"OBJECT_ID":null,"EDITION_NAME":null,"CLIENT_ID":{"string":"UNKNOWN"},"SRC_CON_NAME":{"string":"ORCLPDB1"},"SRC_CON_ID":{"long":3},"SRC_CON_UID":{"long":2068062479},"SRC_CON_DBID":{"long":0},"SRC_CON_GUID":null,"CON_ID":{"boolean":false}}

# {"SCN":{"long":2172854},"START_SCN":{"long":2172853},"COMMIT_SCN":{"long":2172854},"TIMESTAMP":{"long":1655974754000},"START_TIMESTAMP":{"long":1655974754000},"COMMIT_TIMESTAMP":{"long":1655974754000},"XIDUSN":{"long":3},"XIDSLT":{"long":14},"XIDSQN":{"long":716},"XID":{"bytes":"\u0003\u0000\u000E\u0000Ì\u0002\u0000\u0000"},"PXIDUSN":{"long":3},"PXIDSLT":{"long":14},"PXIDSQN":{"long":716},"PXID":{"bytes":"\u0003\u0000\u000E\u0000Ì\u0002\u0000\u0000"},"TX_NAME":null,"OPERATION":{"string":"COMMIT"},"OPERATION_CODE":{"int":7},"ROLLBACK":{"boolean":false},"SEG_OWNER":null,"SEG_NAME":null,"TABLE_NAME":null,"SEG_TYPE":{"int":0},"SEG_TYPE_NAME":null,"TABLE_SPACE":null,"ROW_ID":{"string":"AAAAAAAAAAAAAAAAAA"},"USERNAME":{"string":"C##MYUSER"},"OS_USERNAME":{"string":"UNKNOWN"},"MACHINE_NAME":{"string":"UNKNOWN"},"AUDIT_SESSIONID":{"long":40001},"SESSION_NUM":{"long":501},"SERIAL_NUM":{"long":47243},"SESSION_INFO":{"string":"UNKNOWN"},"THREAD_NUM":{"long":1},"SEQUENCE_NUM":{"long":3},"RBASQN":{"long":7},"RBABLK":{"long":141497},"RBABYTE":{"long":16},"UBAFIL":{"long":11},"UBABLK":{"long":0},"UBAREC":{"long":0},"UBASQN":{"long":0},"ABS_FILE_NUM":{"long":11},"REL_FILE_NUM":{"long":0},"DATA_BLK_NUM":{"long":0},"DATA_OBJ_NUM":{"long":0},"DATA_OBJV_NUM":{"long":0},"DATA_OBJD_NUM":{"long":0},"SQL_REDO":{"string":"commit;"},"SQL_UNDO":null,"RS_ID":{"string":" 0x000007.000228b9.0010 "},"SSN":{"long":0},"CSF":{"boolean":false},"INFO":null,"STATUS":{"int":0},"REDO_VALUE":{"long":4},"UNDO_VALUE":{"long":5},"SAFE_RESUME_SCN":{"long":2172854},"CSCN":{"long":2172854},"OBJECT_ID":null,"EDITION_NAME":null,"CLIENT_ID":{"string":"UNKNOWN"},"SRC_CON_NAME":{"string":"ORCLPDB1"},"SRC_CON_ID":{"long":3},"SRC_CON_UID":{"long":2068062479},"SRC_CON_DBID":{"long":0},"SRC_CON_GUID":null,"CON_ID":{"boolean":false}}

# "SQL_REDO":{"string":"delete from \"C##MYUSER\".\"CUSTOMERS\" a where a.\"RECID\" = '1' and a.ROWID = 'AAAR1AAAMAAAACFAAA';"}