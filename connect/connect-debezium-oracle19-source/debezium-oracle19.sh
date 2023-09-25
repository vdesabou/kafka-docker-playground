#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

create_or_get_oracle_image "LINUX.X64_193000_db_home.zip" "../../connect/connect-debezium-oracle19-source/ora-setup-scripts-cdb-table"

if [ ! -z "$SQL_DATAGEN" ]
then
     cd ../../connect/connect-debezium-oracle19-source
     log "🌪️ SQL_DATAGEN is set, make sure to increase redo.log.row.fetch.size, have a look at https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-debezium-oracle19-source/README.md#note-on-redologrowfetchsize"
     for component in oracle-datagen
     do
     set +e
     log "🏗 Building jar for ${component}"
     docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${PWD}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "$PWD/../../scripts/settings.xml:/tmp/settings.xml" -v "${PWD}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -s /tmp/settings.xml -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
     if [ $? != 0 ]
     then
          logerror "ERROR: failed to build java component "
          tail -500 /tmp/result.log
          exit 1
     fi
     set -e
     done
     cd -
else
     log "🛑 SQL_DATAGEN is not set"
fi

if [ -z "$CONNECTOR_TAG" ]
then
    CONNECTOR_TAG=2.3.4
fi

if [ ! -f debezium-connector-oracle-${CONNECTOR_TAG}.tar.gz ]
then
    curl -L -o debezium-connector-oracle-${CONNECTOR_TAG}.tar.gz https://repo1.maven.org/maven2/io/debezium/debezium-connector-oracle/${CONNECTOR_TAG}.Final/debezium-connector-oracle-${CONNECTOR_TAG}.Final-plugin.tar.gz
    tar xvfz debezium-connector-oracle-${CONNECTOR_TAG}.tar.gz
fi


VERSION=$CONNECTOR_TAG
unset CONNECTOR_TAG

cd ../../connect/connect-debezium-oracle19-source
get_3rdparty_file "ojdbc8.jar"
if [ ! -f ${PWD}/ojdbc8.jar ]
then
     logerror "ERROR: ${PWD}/ojdbc8.jar is missing. It must be downloaded manually in order to acknowledge user agreement"
     exit 1
fi
cd -

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


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
     CREATE ROLE C##CDC_PRIVS;
     GRANT CREATE SESSION TO C##CDC_PRIVS;
     GRANT LOGMINING TO C##CDC_PRIVS;
     GRANT SELECT ON V_\$DATABASE TO C##CDC_PRIVS;
     GRANT SELECT ON V_\$THREAD TO C##CDC_PRIVS;
     GRANT SELECT ON V_\$PARAMETER TO C##CDC_PRIVS;
     GRANT SELECT ON V_\$NLS_PARAMETERS TO C##CDC_PRIVS;
     GRANT SELECT ON V_\$TIMEZONE_NAMES TO C##CDC_PRIVS;
   --  GRANT SELECT ON ALL_INDEXES TO C##CDC_PRIVS;
   --  GRANT SELECT ON ALL_OBJECTS TO C##CDC_PRIVS;
   --  GRANT SELECT ON ALL_USERS TO C##CDC_PRIVS;
   --  GRANT SELECT ON ALL_CATALOG TO C##CDC_PRIVS;
   --  GRANT SELECT ON ALL_CONSTRAINTS TO C##CDC_PRIVS;
   --  GRANT SELECT ON ALL_CONS_COLUMNS TO C##CDC_PRIVS;
   --  GRANT SELECT ON ALL_TAB_COLS TO C##CDC_PRIVS;
   --  GRANT SELECT ON ALL_IND_COLUMNS TO C##CDC_PRIVS;
   --  GRANT SELECT ON ALL_ENCRYPTED_COLUMNS TO C##CDC_PRIVS;
   --  GRANT SELECT ON ALL_LOG_GROUPS TO C##CDC_PRIVS;
   --  GRANT SELECT ON ALL_TAB_PARTITIONS TO C##CDC_PRIVS;
   --  GRANT SELECT ON SYS.DBA_REGISTRY TO C##CDC_PRIVS;
     GRANT SELECT ON SYS.OBJ\$ TO C##CDC_PRIVS;
   --  GRANT SELECT ON DBA_TABLESPACES TO C##CDC_PRIVS;
   --  GRANT SELECT ON DBA_OBJECTS TO C##CDC_PRIVS;
   --  GRANT SELECT ON SYS.ENC\$ TO C##CDC_PRIVS;
     GRANT SELECT ANY TABLE TO C##CDC_PRIVS;
     


     GRANT SELECT_CATALOG_ROLE TO C##CDC_PRIVS;
     GRANT EXECUTE_CATALOG_ROLE TO C##CDC_PRIVS;
     GRANT SELECT ANY TRANSACTION TO C##CDC_PRIVS;

     GRANT EXECUTE ON SYS.DBMS_LOGMNR TO C##CDC_PRIVS;
     GRANT EXECUTE ON SYS.DBMS_LOGMNR_D TO C##CDC_PRIVS;

     GRANT SELECT ON V_\$LOG TO C##CDC_PRIVS;
     GRANT SELECT ON V_\$LOG_HISTORY TO C##CDC_PRIVS;
     GRANT SELECT ON V_\$LOGMNR_LOGS TO C##CDC_PRIVS;
     GRANT SELECT ON V_\$LOGMNR_CONTENTS TO C##CDC_PRIVS;
     GRANT SELECT ON V_\$LOGMNR_PARAMETERS TO C##CDC_PRIVS;
     GRANT SELECT ON V_\$LOGFILE TO C##CDC_PRIVS;
     GRANT SELECT ON V_\$ARCHIVED_LOG TO C##CDC_PRIVS;
     GRANT SELECT ON V_\$ARCHIVE_DEST_STATUS TO C##CDC_PRIVS;
     GRANT SELECT ON V_\$TRANSACTION TO C##CDC_PRIVS;

     GRANT SELECT ON V_\$MYSTAT TO C##CDC_PRIVS;
     GRANT SELECT ON V_\$STATNAME TO C##CDC_PRIVS;

     CREATE USER C##MYUSER IDENTIFIED BY mypassword DEFAULT TABLESPACE USERS;
     ALTER USER C##MYUSER QUOTA UNLIMITED ON USERS;

     GRANT C##CDC_PRIVS to C##MYUSER;

     GRANT CREATE TABLE TO C##MYUSER container=all;
     GRANT CREATE SEQUENCE TO C##MYUSER container=all;
     GRANT CREATE TRIGGER TO C##MYUSER container=all;
     GRANT FLASHBACK ANY TABLE TO C##MYUSER container=all;
     GRANT EXECUTE ON SYS.DBMS_LOGMNR TO C##CDC_PRIVS;
     GRANT EXECUTE ON SYS.DBMS_LOGMNR_D TO C##CDC_PRIVS;
     GRANT EXECUTE ON SYS.DBMS_LOGMNR_LOGREP_DICT TO C##CDC_PRIVS;
     ;
     
     -- Enable Supplemental Logging for All Columns
     ALTER SESSION SET CONTAINER=cdb\$root;
     ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;
     ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
     exit;
EOF

log "Inserting initial data"
docker exec -i oracle sqlplus C\#\#MYUSER/mypassword@//localhost:1521/ORCLCDB << EOF

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

     insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments) values ('Rica', 'Blaisdell', 'rblaisdell0@rambler.ru', 'Female', 'bronze', 'Universal optimal hierarchy');
     insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments) values ('Ruthie', 'Brockherst', 'rbrockherst1@ow.ly', 'Female', 'platinum', 'Reverse-engineered tangible interface');
     insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments) values ('Mariejeanne', 'Cocci', 'mcocci2@techcrunch.com', 'Female', 'bronze', 'Multi-tiered bandwidth-monitored capability');
     insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments) values ('Hashim', 'Rumke', 'hrumke3@sohu.com', 'Male', 'platinum', 'Self-enabling 24/7 firmware');
     insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments) values ('Hansiain', 'Coda', 'hcoda4@senate.gov', 'Male', 'platinum', 'Centralized full-range approach');
     exit;
EOF

log "Creating Debezium Oracle source connector"
playground connector create-or-update --connector debezium-oracle-source << EOF
{
  "connector.class": "io.debezium.connector.oracle.OracleConnector",
  "tasks.max": "1",
  "database.hostname": "oracle",
  "database.port": "1521",
  "database.user": "C##MYUSER",
  "database.password": "mypassword",
  "database.dbname" : "ORCLCDB",

  "_database.pdb.name" : "ORCLCDB",
  
  "database.encrypt": "false",
  "topic.prefix": "C__MYUSER",
  "schema.history.internal.kafka.bootstrap.servers": "broker:9092",
  "schema.history.internal.kafka.topic": "schema-changes.inventory",
  "table.include.list": ".*CUSTOMERS.*",

  "_comment:": "remove _ to use ExtractNewRecordState smt",
  "_transforms": "unwrap",
  "_transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState"
}
EOF

log "Waiting 20s for connector to read existing data"
sleep 20

log "Running SQL scripts"
for script in ../../connect/connect-cdc-oracle19-source/sample-sql-scripts/*.sh
do
     $script "ORCLCDB"
done

log "Waiting 20s for connector to read new data"
sleep 20

log "Verifying topic C__MYUSER.C__MYUSER.CUSTOMERS"
playground topic consume --topic C__MYUSER.C__MYUSER.CUSTOMERS --min-expected-messages 10 --timeout 60

log "Verifying topic C__MYUSER"
playground topic consume --topic C__MYUSER --min-expected-messages 15 --timeout 60

# FIXTHIS getting Caused by: java.sql.SQLException: ORA-01332: internal Logminer Dictionary error


if [ ! -z "$SQL_DATAGEN" ]
then
     DURATION=10
     log "Injecting data for $DURATION minutes"
     docker exec -d sql-datagen bash -c "java ${JAVA_OPTS} -jar sql-datagen-1.0-SNAPSHOT-jar-with-dependencies.jar --host oracle --username C##MYUSER --password mypassword --sidOrServerName sid --sidOrServerNameVal ORCLCDB --maxPoolSize 10 --durationTimeMin $DURATION"
fi