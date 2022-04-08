#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

create_or_get_oracle_image "LINUX.X64_193000_db_home.zip" "../../connect/connect-cdc-oracle19-source/ora-setup-scripts-cdb-table"

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.cdb-table.repro-100067-oracle-cdc-connector-not-processing-data-with-special-characters.yml"


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

docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
CONNECT sys/Admin123 AS SYSDBA
GRANT CREATE ANY DIRECTORY TO C##MYUSER container=all;
exit;
EOF

docker exec -i oracle sqlplus C\#\#MYUSER/mypassword@//localhost:1521/ORCLCDB << EOF
  create directory DATA_TEST as '/tmp';
  exit;
EOF

if [ ! -f member_billing.dmp ]
then
     get_3rdparty_file member_billing.dmp
fi
docker cp member_billing.dmp oracle:/tmp/
docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;impdp C##MYUSER@ORCLCDB DIRECTORY=DATA_TEST DUMPFILE=member_billing.dmp REMAP_SCHEMA=WWNA:C##MYUSER REMAP_TABLESPACE=WW_COM_SCRATCH:USERS
 TABLES=WWNA.MEMBER_BILLING_ORA_CDC logfile=member_billing_import.log" << EOF
mypassword
EOF

docker exec -i oracle sqlplus C\#\#MYUSER/mypassword@//localhost:1521/ORCLCDB << EOF
  select count(*) from MEMBER_BILLING_ORA_CDC;
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
               "oracle.username": "C##MYUSER",
               "oracle.password": "mypassword",
               "start.from":"snapshot",
               "redo.log.topic.name": "redo-log-topic",
               "redo.log.consumer.bootstrap.servers":"broker:9092",
               "table.inclusion.regex": ".*MEMBER_BILLING_ORA_CDC.*",
               "table.topic.name.template": "${databaseName}.${schemaName}.${tableName}",
               "numeric.mapping": "best_fit",
               "connection.pool.max.size": 20,
               "redo.log.row.fetch.size":1,
               "oracle.dictionary.mode": "auto",
               "behavior.on.dictionary.mismatch": "log",
               "behavior.on.unparsable.statement": "log",
               "lob.topic.name.template": "${tableName}-${columnName}-testing-new",
               "enable.large.lob.object.support": "true",
               "sanitize.field.name": "true",
               "db.timezone": "America/New_York",
               "numeric.mapping": "best_fit_or_decimal"
          }' \
     http://localhost:8083/connectors/cdc-oracle-source-cdb/config | jq .

log "Waiting 20s for connector to read existing data"
sleep 20

log "Verifying topic ORCLCDB.C__MYUSER.MEMBER_BILLING_ORA_CDC: there should be 2 records"
set +e
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic ORCLCDB.C__MYUSER.MEMBER_BILLING_ORA_CDC --from-beginning --max-messages 2 > /tmp/result.log  2>&1
set -e
cat /tmp/result.log

log "Verifying topic redo-log-topic: there should be 2 records"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic redo-log-topic --from-beginning --max-messages 2

log "inject problematic record"
docker exec -i oracle sqlplus C\#\#MYUSER/mypassword@//localhost:1521/ORCLCDB << EOF
  insert into MEMBER_BILLING_ORA_CDC select member_no,charge_date,credit_card_no from MEMBER_BILLING_ORA_CDC where member_no='457693638' and rownum=1;
  exit;
EOF

wait_for_log "Encountered unparsable statement"

# [2022-04-08 08:29:09,820] WARN [cdc-oracle-source-cdb|task-1|changeEvent] Encountered unparsable statement: insert into "C##MYUSER"."MEMBER_BILLING_ORA_CDC"("MEMBER_NO","CHARGE_DATE","CREDIT_CARD_NO") values ('457693638',TO_DATE('2022-04-01 00:00:00', 'YYYY-MM-DD HH24:MI:SS'),'kZ*8~�
#               ���g�nM��f�K=Ie�g#Ta�'');. Logging and continuing (io.confluent.connect.oracle.cdc.record.OracleChangeEventSourceRecordConverter:341)



exit 0


# docker exec -i oracle sqlplus C\#\#MYUSER/mypassword@//localhost:1521/ORCLCDB << EOF
#   create table C##MYUSER.MEMBER_BILLING_ORA_CDC
#   (
#     MEMBER_NO       VARCHAR2(20 BYTE)  NOT NULL,
#     CHARGE_DATE     DATE,
#     CREDIT_CARD_NO  VARCHAR2(500 BYTE)
#   );
#   exit;
# EOF

# log "insert row with special characters"
# docker exec -i oracle sqlplus C\#\#MYUSER/mypassword@//localhost:1521/ORCLCDB << EOF
#   insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments, CREDIT_CARD_NO) values ('Hansiain', 'Coda', 'hcoda4@senate.gov', 'Male', 'platinum', 'Centralized full-range approach', 'kZ*8~?????nM??f?K=Ie?Ta?');
#   exit;
# EOF

# log "insert row with special characters"
# docker exec -i oracle sqlplus C\#\#MYUSER/mypassword@//localhost:1521/ORCLCDB << EOF
#     insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments, CREDIT_CARD_NO) values ('Hansiain', 'Coda', 'hcoda4@senate.gov', 'Male', 'platinum', 'Centralized full-range approach', '?#*a?H??Q????D9????o?;?|j?P?{??');
#   exit;
# EOF

# docker exec -i oracle sqlplus C\#\#MYUSER/mypassword@//localhost:1521/ORCLCDB << EOF
#     insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments, CREDIT_CARD_NO) values ('Hansiain', 'Coda', 'hcoda4@senate.gov', 'Male', 'platinum', 'Centralized full-range approach', '?va?''
# U K??W?2v3?(x*8??_2?M');
#   exit;
# EOF

# docker exec -i oracle sqlplus C\#\#MYUSER/mypassword@//localhost:1521/ORCLCDB << EOF
#     insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments, CREDIT_CARD_NO) values ('Hansiain', 'Coda', 'hcoda4@senate.gov', 'Male', 'platinum', 'Centralized full-range approach', 'kZ*8~?????nM??f?K=Ie?Ta?');
#   exit;
# EOF

# docker exec -i oracle sqlplus C\#\#MYUSER/mypassword@//localhost:1521/ORCLCDB << EOF
#     insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments, CREDIT_CARD_NO) values ('Hansiain', 'Coda', 'hcoda4@senate.gov', 'Male', 'platinum', 'Centralized full-range approach', 'k^^Z*8~?^\^K????nM??f?K=Ie?Ta^_?');
#   exit;
# EOF


# docker exec -i oracle sqlplus C\#\#MYUSER/mypassword@//localhost:1521/ORCLCDB << EOF
#     insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments, CREDIT_CARD_NO) values ('Hansiain', 'Coda', 'hcoda4@senate.gov', 'Male', 'platinum', 'Centralized full-range approach', 'kZ*8~?????nM??f?K=Ie?Ta?');
#     insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments, CREDIT_CARD_NO) values ('Hansiain', 'Coda', 'hcoda4@senate.gov', 'Male', 'platinum', 'Centralized full-range approach', '?#*a?H??Q????D9????o?;?|j?P?{??');
#     insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments, CREDIT_CARD_NO) values ('Hansiain', 'Coda', 'hcoda4@senate.gov', 'Male', 'platinum', 'Centralized full-range approach', '?va?''
# U K??W?2v3?(x*8??_2?M');
#     insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments, CREDIT_CARD_NO) values ('Hansiain', 'Coda', 'hcoda4@senate.gov', 'Male', 'platinum', 'Centralized full-range approach', 'kZ*8~?????nM??f?K=Ie?Ta?');
#     COMMIT;
#   exit;
# EOF
