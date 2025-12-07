#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

source ${DIR}/../../scripts/utils.sh

# https://confluentinc.atlassian.net/wiki/spaces/~62c938d4fa577c57c3b80d59/pages/4038003034/DRAFT+User+facing+documentation+Oracle+XStream+CDC+source+connector+Early+Access

create_or_get_oracle_image "LINUX.X64_193000_db_home.zip" "../../connect/connect-cdc-oracle19-source/ora-setup-scripts-cdb-table"

if [ ! -z "$SQL_DATAGEN" ]
then
     cd ../../connect/connect-cdc-xstream-oracle19-source
     log "🌪️ SQL_DATAGEN is set"
     for component in oracle-datagen
     do
     set +e
     log "🏗 Building jar for ${component}"
     docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${PWD}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "$PWD/../../scripts/settings.xml:/tmp/settings.xml" -v "${PWD}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.9.11-eclipse-temurin-11 mvn -s /tmp/settings.xml -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
     if [ $? != 0 ]
     then
          logerror "❌ failed to build java component "
          tail -500 /tmp/result.log
          exit 1
     fi
     set -e
     done
     cd -
else
     log "🛑 SQL_DATAGEN is not set"
fi

cd ../../connect/connect-cdc-xstream-oracle19-source
if [ ! -d "lib/instantclient" ]
then
     if [ -z "${ZIP_FILE}" ]
     then
          if [ `uname -m` = "arm64" ]
          then
               ZIP_FILE="instantclient_19_25_arm64.zip"
          else
               ZIP_FILE="instantclient_19_25_x86.zip"
          fi
          get_3rdparty_file "${ZIP_FILE}"
     fi

     if [ ! -f ${PWD}/${ZIP_FILE} ]
     then
          logerror "❌ ${PWD}/${ZIP_FILE} is missing. It must be downloaded manually in order to acknowledge user agreement"
          logerror "You can download it from https://www.oracle.com/in/database/technologies/instant-client/downloads.html"
          exit 1
     fi

     unzip ${ZIP_FILE} -d lib
     mv lib/instantclient_* lib/instantclient
fi
cd -


cd ../../connect/connect-cdc-xstream-oracle19-source

# Copy JAR files to confluent-hub
mkdir -p ../../confluent-hub/confluentinc-kafka-connect-oracle-xstream-cdc-source/lib/
cp ../../connect/connect-cdc-xstream-oracle19-source/lib/instantclient/ojdbc8.jar ../../confluent-hub/confluentinc-kafka-connect-oracle-xstream-cdc-source/lib/ojdbc8.jar
cp ../../connect/connect-cdc-xstream-oracle19-source/lib/instantclient/xstreams.jar ../../confluent-hub/confluentinc-kafka-connect-oracle-xstream-cdc-source/lib/xstreams.jar
cp ../../connect/connect-cdc-xstream-oracle19-source/lib/instantclient/ojdbc8.jar ../../confluent-hub/confluentinc-kafka-connect-oracle-xstream-cdc-source/lib/ojdbc8.jar
cp ../../connect/connect-cdc-xstream-oracle19-source/lib/instantclient/xstreams.jar ../../confluent-hub/confluentinc-kafka-connect-oracle-xstream-cdc-source/lib/xstreams.jar
cd -
PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

if ! (version_gt $CP_CONNECT_TAG "7.6.99")
then
     playground container change-jdk --version 17 --container connect
fi

# https://github.com/confluentinc/common-docker/pull/743 and https://github.com/adoptium/adoptium-support/issues/1285
set +e
playground container exec --root --command "sed -i "s/packages\.adoptium\.net/adoptium\.jfrog\.io/g" /etc/yum.repos.d/adoptium.repo"
set -e
playground container exec --root --command "microdnf -y install libaio"

if [ "$(uname -m)" = "arm64" ]
then
     :
else
     if version_gt $TAG_BASE "7.9.9"
     then
          playground container exec --root --command "microdnf -y install libnsl2"
          playground container exec --root --command "ln -s /usr/lib64/libnsl.so.3 /usr/lib64/libnsl.so.1"
     else
          playground container exec --root --command "ln -s /usr/lib64/libnsl.so.2 /usr/lib64/libnsl.so.1"
     fi
fi

playground container logs --container oracle --wait-for-log "DATABASE IS READY TO USE" --max-wait 600
log "Oracle DB has started!"

log "Enable Oracle XStream"
docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
     CONNECT sys/Admin123 AS SYSDBA

     ALTER SYSTEM SET enable_goldengate_replication=TRUE SCOPE=BOTH;

     SHOW PARAMETER GOLDEN;
EOF

log "Configure ARCHIVELOG mode"
docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
     SHUTDOWN IMMEDIATE;
     STARTUP MOUNT;
     ALTER DATABASE ARCHIVELOG;
     ALTER DATABASE OPEN;
EOF


log "Configure supplemental logging"
docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
     CONNECT sys/Admin123 AS SYSDBA

     ALTER SESSION SET CONTAINER = CDB\$ROOT;
     ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
     SELECT SUPPLEMENTAL_LOG_DATA_MIN, SUPPLEMENTAL_LOG_DATA_ALL FROM V\$DATABASE;
EOF


docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
     CONNECT sys/Admin123 AS SYSDBA

     -- Create tablespace for XStream admin in CDB
     CREATE TABLESPACE xstream_adm_tbs DATAFILE '/opt/oracle/oradata/ORCLCDB/xstream_adm_tbs.dbf'
     SIZE 25M REUSE AUTOEXTEND ON MAXSIZE UNLIMITED;

     -- Create tablespace for XStream user in CDB
     CREATE TABLESPACE xstream_tbs DATAFILE '/opt/oracle/oradata/ORCLCDB/xstream_tbs.dbf'
     SIZE 25M REUSE AUTOEXTEND ON MAXSIZE UNLIMITED;
EOF

docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
     CONNECT sys/Admin123 AS SYSDBA
     alter session set container=ORCLPDB1;

     -- Create tablespace for XStream admin in PDB
     CREATE TABLESPACE xstream_adm_tbs DATAFILE '/opt/oracle/oradata/ORCLCDB/ORCLPDB1/xstream_adm_tbs.dbf'
     SIZE 25M REUSE AUTOEXTEND ON MAXSIZE UNLIMITED;

     -- Create tablespace for XStream User in PDB
     CREATE TABLESPACE xstream_tbs DATAFILE '/opt/oracle/oradata/ORCLCDB/ORCLPDB1/xstream_tbs.dbf'
     SIZE 25M REUSE AUTOEXTEND ON MAXSIZE UNLIMITED;
EOF

log "Create a new common user for the XStream administrator"
docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
     CONNECT sys/Admin123 AS SYSDBA

     CREATE USER c##cfltadmin IDENTIFIED BY password
     DEFAULT TABLESPACE xstream_adm_tbs
     QUOTA UNLIMITED ON xstream_adm_tbs
     CONTAINER=ALL;

     GRANT CREATE SESSION, SET CONTAINER TO c##cfltadmin CONTAINER=ALL;

     BEGIN
     DBMS_XSTREAM_AUTH.GRANT_ADMIN_PRIVILEGE(
          grantee                 => 'c##cfltadmin',
          privilege_type          => 'CAPTURE',
          grant_select_privileges => TRUE,
          container               => 'ALL'
     );
     END;
     /
EOF

log "Create a new common user for the XStream connect user"
docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
     CONNECT sys/Admin123 AS SYSDBA

     CREATE USER c##cfltuser IDENTIFIED BY password
     DEFAULT TABLESPACE xstream_tbs
     QUOTA UNLIMITED ON xstream_tbs
     CONTAINER=ALL;

     GRANT CREATE SESSION, SET CONTAINER TO c##cfltuser CONTAINER=ALL;
     GRANT SELECT_CATALOG_ROLE TO c##cfltuser CONTAINER=ALL;

     GRANT CREATE TABLE TO c##cfltuser CONTAINER=ALL;
     GRANT CREATE SEQUENCE to c##cfltuser CONTAINER=ALL;
     GRANT CREATE TRIGGER TO c##cfltuser CONTAINER=ALL;

     GRANT FLASHBACK ANY TABLE TO c##cfltuser CONTAINER=ALL;
     GRANT SELECT ANY TABLE TO c##cfltuser CONTAINER=ALL;
     GRANT LOCK ANY TABLE TO c##cfltuser CONTAINER=ALL;
EOF

log "Creating XStream Out"
docker exec -i oracle sqlplus c\#\#cfltadmin/password@//localhost:1521/ORCLCDB << EOF

DECLARE
     tables  DBMS_UTILITY.UNCL_ARRAY;
     schemas DBMS_UTILITY.UNCL_ARRAY;
BEGIN
     tables(1)  := 'C##CFLTUSER.CUSTOMERS';
     tables(2)  := 'C##CFLTUSER.CFLT_SIGNALS';
     schemas(1) := NULL;
     DBMS_XSTREAM_ADM.CREATE_OUTBOUND(
          server_name     =>  'xout',
          table_names     =>  tables,
          schema_names    =>  schemas);
END;
/
EOF

docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
     CONNECT sys/Admin123 AS SYSDBA
BEGIN
     DBMS_XSTREAM_ADM.ALTER_OUTBOUND(
     server_name  => 'xout',
     connect_user => 'c##cfltuser');
END;
/
EOF
if [ ! -f orclcdc_readiness.sql ]
then
     log "Downloading orclcdc_readiness.sql"
     wget https://docs.confluent.io/kafka-connectors/oracle-xstream-cdc-source/current/_downloads/35f0e2f456c5dae965ee476492943e9e/orclcdc_readiness.sql
fi

log "Running orclcdc_readiness.sql, see https://docs.confluent.io/cloud/current/connectors/cc-oracle-xstream-cdc-source/prereqs-validation.html#validate-prerequisites-completion"
docker cp orclcdc_readiness.sql oracle:/orclcdc_readiness.sql
docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
     CONNECT sys/Admin123 AS SYSDBA
     @/orclcdc_readiness.sql C##CFLTADMIN C##CFLTUSER XOUT ''
END;
/
EOF

log "Create CUSTOMERS table and inserting initial data"
docker exec -i oracle sqlplus c\#\#cfltuser/password@//localhost:1521/ORCLCDB << EOF

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

log "Creating signal table"
docker exec -i oracle sqlplus c\#\#cfltuser/password@//localhost:1521/ORCLCDB << EOF

     CREATE TABLE CFLT_SIGNALS (
          id VARCHAR(42) PRIMARY KEY,
          type VARCHAR(32) NOT NULL,
          data VARCHAR(2048)
     );
     exit;
EOF

sleep 2

log "Creating Oracle Xstream CDC source connector"
playground connector create-or-update --connector cdc-xstream-oracle-source << EOF
{
    "connector.class": "io.confluent.connect.oracle.xstream.cdc.OracleXStreamSourceConnector",
    "database.dbname": "ORCLCDB",
    "database.hostname": "oracle",
    "database.os.timezone": "UTC",
    "database.out.server.name": "XOUT",
    "database.service.name": "ORCLCDB",
    "table.include.list": "C##CFLTUSER[.]CUSTOMERS",
    "database.password": "password",
    "database.port": "1521",
    "database.user": "c##cfltuser",
    "topic.prefix": "cflt",
    "schema.history.internal.kafka.bootstrap.servers": "broker:9092",
    "schema.history.internal.kafka.topic": "__orcl-schema-changes.cflt",
    "confluent.license": "",
    "confluent.topic.bootstrap.servers": "broker:9092",
    "confluent.topic.replication.factor": "1",
    "database.processor.licenses": "1",
    "signal.data.collection": "ORCLCDB.C##CFLTUSER.CFLT_SIGNALS",

    "_comment:": "remove _ to use ExtractNewRecordState smt",
    "_transforms": "unwrap",
    "_transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState"
}
EOF

docker exec -i oracle sqlplus c\#\#cfltuser/password@//localhost:1521/ORCLCDB << EOF
     insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments) values ('streaming', 'One', 'fkafka@confluent.io', 'Male', 'bronze', 'first streaming record');
     insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments) values ('Signal', 'One', 'fkafka@confluent.io', 'Male', 'bronze', 'first signal record');
     exit;
EOF

log "sleeping some time to capture post initial snapshot records"
sleep 30

log "we should now have 7 records"
playground topic consume --topic cflt.C__CFLTUSER.CUSTOMERS --min-expected-messages 7 --timeout 60

#log "how to snapshot specific record"
#docker exec -i oracle sqlplus c\#\#cfltuser/password@//localhost:1521/ORCLCDB << EOF
#INSERT INTO CFLT_SIGNALS (id, type, data) VALUES (
#  '8a474adc-caca-4cf4-85d7-2b42e056ef5c',
#  'execute-snapshot',
#  '{
#      "type": "blocking",
#      "data-collections": ["ORCLCDB.C##CFLTUSER.CUSTOMERS"],
#      "additional-conditions": [
#        {
#          "data-collection": "ORCLCDB.C##CFLTUSER.CUSTOMERS",
#          "filter": "SELECT * FROM C##CFLTUSER.CUSTOMERS WHERE id = <someID>"
#        }
#      ]
#    }'
#);
#exit;
#EOF

log "execute blocking snapshot to capture all records within ORCLCDB.C##CFLTUSER.CUSTOMERS table"
docker exec -i oracle sqlplus c\#\#cfltuser/password@//localhost:1521/ORCLCDB << EOF
INSERT INTO CFLT_SIGNALS(ID, TYPE, DATA) VALUES (
  '19640', 
  'execute-snapshot', 
  '{
      "type":"blocking", 
      "data-collections":["ORCLCDB.C##CFLTUSER.CUSTOMERS"]
  }'
);
EOF

sleep 10

log "verify snapshot command in signal table"
docker exec -i oracle sqlplus c\#\#cfltuser/password@//localhost:1521/ORCLCDB << EOF
SELECT * FROM CFLT_SIGNALS;
EOF

log "we should now have 14"
playground topic consume --topic cflt.C__CFLTUSER.CUSTOMERS --min-expected-messages 14 --timeout 60

if [ ! -z "$SQL_DATAGEN" ]
then
     DURATION=10
     log "Injecting data for $DURATION minutes"
     docker exec sql-datagen bash -c "java ${JAVA_OPTS} -jar sql-datagen-1.0-SNAPSHOT-jar-with-dependencies.jar --host oracle --username c##cfltuser --password password --sidOrServerName sid --sidOrServerNameVal ORCLCDB --maxPoolSize 10 --durationTimeMin $DURATION"
fi

log "⚙️ You can use <playground connector oracle-cdc-xstream generate-report> to generate oracle cdc xstream connector diagnostics report"
log "🐞 You can use <playground connector oracle-cdc-xstream debug> to execute various SQL commands to debug xstream components"