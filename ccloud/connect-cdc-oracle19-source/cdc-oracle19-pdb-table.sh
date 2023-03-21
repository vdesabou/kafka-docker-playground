#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -z "$GITHUB_RUN_NUMBER" ]
then
     # running with github actions
     remove_cdb_oracle_image "LINUX.X64_193000_db_home.zip" "$(pwd)/ora-setup-scripts-cdb-table"
fi


create_or_get_oracle_image "LINUX.X64_193000_db_home.zip" "../../connect/connect-cdc-oracle19-source/ora-setup-scripts-cdb-table"

${DIR}/../../ccloud/environment/start.sh "${PWD}/docker-compose.plaintext.pdb-table.yml"

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
set -e

# Verify Oracle DB has started within MAX_WAIT seconds
MAX_WAIT=2500
CUR_WAIT=0
log "⌛ Waiting up to $MAX_WAIT seconds for Oracle DB to start"
docker container logs oracle > /tmp/out.txt 2>&1
while [[ ! $(cat /tmp/out.txt) =~ "DATABASE IS READY TO USE" ]]; do
sleep 10
docker container logs oracle > /tmp/out.txt 2>&1
CUR_WAIT=$(( CUR_WAIT+10 ))
if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
     logerror "ERROR: The logs in oracle container do not show 'DATABASE IS READY TO USE' after $MAX_WAIT seconds. Please troubleshoot with 'docker container ps' and 'docker container logs'.\n"
     exit 1
fi
done
log "Oracle DB has started!"
log "Setting up Oracle Database Prerequisites"
docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
     CONNECT sys/Admin123 AS SYSDBA
     ALTER SESSION SET CONTAINER=CDB\$ROOT;
     CREATE ROLE C##CDC_PRIVS;
     CREATE USER C##MYUSER IDENTIFIED BY mypassword CONTAINER=ALL;
     ALTER USER C##MYUSER QUOTA UNLIMITED ON USERS;
     ALTER USER C##MYUSER SET CONTAINER_DATA = (CDB\$ROOT, ORCLPDB1) CONTAINER=CURRENT;
     GRANT C##CDC_PRIVS to C##MYUSER CONTAINER=ALL;

     GRANT CREATE SESSION TO C##CDC_PRIVS CONTAINER=ALL;
     GRANT EXECUTE ON SYS.DBMS_LOGMNR TO C##CDC_PRIVS CONTAINER=ALL;
     GRANT LOGMINING TO C##CDC_PRIVS CONTAINER=ALL;
     GRANT SELECT ON V_\$LOGMNR_CONTENTS TO C##CDC_PRIVS CONTAINER=ALL;
     GRANT SELECT ON V_\$DATABASE TO C##CDC_PRIVS CONTAINER=ALL;
     GRANT SELECT ON V_\$THREAD TO C##CDC_PRIVS CONTAINER=ALL;
     GRANT SELECT ON V_\$PARAMETER TO C##CDC_PRIVS CONTAINER=ALL;
     GRANT SELECT ON V_\$NLS_PARAMETERS TO C##CDC_PRIVS CONTAINER=ALL;
     GRANT SELECT ON V_\$TIMEZONE_NAMES TO C##CDC_PRIVS CONTAINER=ALL;
     GRANT SELECT ON ALL_INDEXES TO C##CDC_PRIVS CONTAINER=ALL;
     GRANT SELECT ON ALL_OBJECTS TO C##CDC_PRIVS CONTAINER=ALL;
     GRANT SELECT ON ALL_USERS TO C##CDC_PRIVS CONTAINER=ALL;
     GRANT SELECT ON ALL_CATALOG TO C##CDC_PRIVS CONTAINER=ALL;
     GRANT SELECT ON ALL_CONSTRAINTS TO C##CDC_PRIVS CONTAINER=ALL;
     GRANT SELECT ON ALL_CONS_COLUMNS TO C##CDC_PRIVS CONTAINER=ALL;
     GRANT SELECT ON ALL_TAB_COLS TO C##CDC_PRIVS CONTAINER=ALL;
     GRANT SELECT ON ALL_IND_COLUMNS TO C##CDC_PRIVS CONTAINER=ALL;
     GRANT SELECT ON ALL_ENCRYPTED_COLUMNS TO C##CDC_PRIVS CONTAINER=ALL;
     GRANT SELECT ON ALL_LOG_GROUPS TO C##CDC_PRIVS CONTAINER=ALL;
     GRANT SELECT ON ALL_TAB_PARTITIONS TO C##CDC_PRIVS CONTAINER=ALL;
     GRANT SELECT ON SYS.DBA_REGISTRY TO C##CDC_PRIVS CONTAINER=ALL;
     GRANT SELECT ON SYS.OBJ$ TO C##CDC_PRIVS CONTAINER=ALL;
     GRANT SELECT ON DBA_TABLESPACES TO C##CDC_PRIVS CONTAINER=ALL;
     GRANT SELECT ON DBA_OBJECTS TO C##CDC_PRIVS CONTAINER=ALL;
     GRANT SELECT ON SYS.ENC$ TO C##CDC_PRIVS CONTAINER=ALL;
     GRANT CONNECT TO C##CDC_PRIVS CONTAINER=ALL;
     GRANT SELECT ON DBA_PDBS TO C##CDC_PRIVS CONTAINER=ALL;
     GRANT SELECT ON CDB_TABLES TO C##CDC_PRIVS CONTAINER=ALL;

     GRANT CREATE TABLE TO C##MYUSER container=all;
     GRANT CREATE SEQUENCE TO C##MYUSER container=all;
     GRANT CREATE TRIGGER TO C##MYUSER container=all;
     GRANT FLASHBACK ANY TABLE TO C##MYUSER container=all;

     -- The following privileges are required additionally for 19c compared to 12c.
     GRANT SELECT ON V_\$ARCHIVED_LOG TO C##CDC_PRIVS CONTAINER=ALL;
     GRANT SELECT ON V_\$LOG TO C##CDC_PRIVS CONTAINER=ALL;
     GRANT SELECT ON V_\$LOGFILE TO C##CDC_PRIVS CONTAINER=ALL;
     GRANT SELECT ON V_\$INSTANCE to C##CDC_PRIVS CONTAINER=ALL;
     GRANT EXECUTE ON SYS.DBMS_LOGMNR TO C##CDC_PRIVS;
     GRANT EXECUTE ON SYS.DBMS_LOGMNR_D TO C##CDC_PRIVS;
     GRANT EXECUTE ON SYS.DBMS_LOGMNR_LOGREP_DICT TO C##CDC_PRIVS;
     ;
     
     -- Enable Supplemental Logging for All Columns
     ALTER SESSION SET CONTAINER=cdb\$root;
     ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;
     ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;

     -- Check Database Instance Version
     GRANT SELECT ON V_\$INSTANCE to C##CDC_PRIVS;
EOF

log "Inserting initial data"
docker exec -i oracle sqlplus C\#\#MYUSER/mypassword@//localhost:1521/ORCLPDB1 << EOF

     create table CUSTOMERS (
          id NUMBER(10) GENERATED BY DEFAULT ON NULL AS IDENTITY (START WITH 42) NOT NULL PRIMARY KEY,
          first_name VARCHAR(50),
          last_name VARCHAR(50),
          email VARCHAR(50),
          gender VARCHAR(50),
          club_status VARCHAR(20),
          comments VARCHAR(90),
          create_ts timestamp DEFAULT CURRENT_TIMESTAMP ,
          update_ts timestamp
     );

     CREATE OR REPLACE TRIGGER TRG_CUSTOMERS_UPD
     BEFORE INSERT OR UPDATE ON CUSTOMERS
     REFERENCING NEW AS NEW_ROW
     FOR EACH ROW
     BEGIN
     SELECT SYSDATE
          INTO :NEW_ROW.UPDATE_TS
          FROM DUAL;
     END;
     /

     insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments) values (1, 'Rica', 'Blaisdell', 'rblaisdell0@rambler.ru', 'Female', 'bronze', 'Universal optimal hierarchy');
     insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments) values (2, 'Ruthie', 'Brockherst', 'rbrockherst1@ow.ly', 'Female', 'platinum', 'Reverse-engineered tangible interface');
     insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments) values (3, 'Mariejeanne', 'Cocci', 'mcocci2@techcrunch.com', 'Female', 'bronze', 'Multi-tiered bandwidth-monitored capability');
     insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments) values (4, 'Hashim', 'Rumke', 'hrumke3@sohu.com', 'Male', 'platinum', 'Self-enabling 24/7 firmware');
     insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments) values (5, 'Hansiain', 'Coda', 'hcoda4@senate.gov', 'Male', 'platinum', 'Centralized full-range approach');
     exit;
EOF

log "Creating _confluent-monitoring topic in Confluent Cloud (auto.create.topics.enable=false)"
set +e
create_topic _confluent-monitoring
set -e

log "Grant select on CUSTOMERS table"
docker exec -i oracle sqlplus C\#\#MYUSER/mypassword@//localhost:1521/ORCLPDB1 << EOF
     ALTER SESSION SET CONTAINER=ORCLPDB1;
     GRANT select on CUSTOMERS TO C##MYUSER;
EOF

log "Creating Oracle source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.oracle.cdc.OracleCdcSourceConnector",
               "tasks.max":2,
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
               "oracle.pdb.name": "ORCLPDB1",
               "oracle.username": "C##MYUSER",
               "oracle.password": "mypassword",
               "start.from":"snapshot",

               "redo.log.topic.name": "redo-log-topic",
               "redo.log.consumer.bootstrap.servers": "${file:/data:bootstrap.servers}",
               "redo.log.consumer.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"${file:/data:sasl.username}\" password=\"${file:/data:sasl.password}\";",
               "redo.log.consumer.security.protocol":"SASL_SSL",
               "redo.log.consumer.sasl.mechanism":"PLAIN",

               "table.inclusion.regex": "ORCLPDB1[.].*[.]CUSTOMERS",
               "table.topic.name.template": "${databaseName}.${schemaName}.${tableName}",
               "numeric.mapping": "best_fit",
               "connection.pool.max.size": 20,
               "redo.log.row.fetch.size":1,
               "oracle.dictionary.mode": "auto"
          }' \
     http://localhost:8083/connectors/cdc-oracle-source-pdb-cloud/config | jq .

log "Waiting 20s for connector to read existing data"
sleep 20

log "Running SQL scripts"
for script in ../../ccloud/connect-cdc-oracle19-source/sample-sql-scripts/*.sh
do
     $script "ORCLPDB1"
done

log "Waiting 20s for connector to read new data"
sleep 20

log "Verifying topic ORCLPDB1.C__MYUSER.CUSTOMERS: there should be 13 records"
set +e
timeout 60 docker exec -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SASL_JAAS_CONFIG="$SASL_JAAS_CONFIG" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" connect bash -c 'kafka-avro-console-consumer --topic ORCLPDB1.C__MYUSER.CUSTOMERS --bootstrap-server $BOOTSTRAP_SERVERS --consumer-property ssl.endpoint.identification.algorithm=https --consumer-property sasl.mechanism=PLAIN --consumer-property security.protocol=SASL_SSL --consumer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --from-beginning --max-messages 13' > /tmp/result.log  2>&1
set -e
cat /tmp/result.log
log "Check there is 5 snapshots events"
if [ $(grep -c "op_type\":{\"string\":\"R\"}" /tmp/result.log) -ne 5 ]
then
     logerror "Did not get expected results"
     exit 1
fi
log "Check there is 3 insert events"
if [ $(grep -c "op_type\":{\"string\":\"I\"}" /tmp/result.log) -ne 3 ]
then
     logerror "Did not get expected results"
     exit 1
fi
log "Check there is 4 update events"
if [ $(grep -c "op_type\":{\"string\":\"U\"}" /tmp/result.log) -ne 4 ]
then
     logerror "Did not get expected results"
     exit 1
fi
log "Check there is 1 delete events"
if [ $(grep -c "op_type\":{\"string\":\"D\"}" /tmp/result.log) -ne 1 ]
then
     logerror "Did not get expected results"
     exit 1
fi

log "Verifying topic redo-log-topic: there should be 9 records"
timeout 60 docker exec -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SASL_JAAS_CONFIG="$SASL_JAAS_CONFIG" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" connect bash -c 'kafka-avro-console-consumer --topic redo-log-topic --bootstrap-server $BOOTSTRAP_SERVERS --consumer-property ssl.endpoint.identification.algorithm=https --consumer-property sasl.mechanism=PLAIN --consumer-property security.protocol=SASL_SSL --consumer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --from-beginning --max-messages 9 --property print.key=true'

log "🚚 If you're planning to inject more data, have a look at https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-cdc-oracle19-source/README.md#note-on-redologrowfetchsize"

