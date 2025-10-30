#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

source ${DIR}/../../scripts/utils.sh

NGROK_AUTH_TOKEN=${NGROK_AUTH_TOKEN:-$1}

display_ngrok_warning

bootstrap_ccloud_environment

create_or_get_oracle_image "LINUX.X64_193000_db_home.zip" "../../connect/connect-cdc-oracle19-source/ora-setup-scripts-cdb-table"

if [ ! -z "$SQL_DATAGEN" ]
then
     cd ../../ccloud/fm-cdc-xstream-oracle19-source
     log "🌪️ SQL_DATAGEN is set"
     for component in oracle-datagen
     do
     set +e
     log "🏗 Building jar for ${component}"
     docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${PWD}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "$PWD/../../scripts/settings.xml:/tmp/settings.xml" -v "${PWD}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.9.1-eclipse-temurin-11 mvn -s /tmp/settings.xml -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
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

set +e
playground topic delete --topic cflt.C__CFLTUSER.CUSTOMERS
set -e

set_profiles
docker compose build
docker compose ${profile_sql_datagen_command} down -v --remove-orphans
docker compose ${profile_sql_datagen_command} up -d --quiet-pull

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



log "Waiting for ngrok to start"
while true
do
  container_id=$(docker ps -q -f name=ngrok)
  if [ -n "$container_id" ]
  then
    status=$(docker inspect --format '{{.State.Status}}' $container_id)
    if [ "$status" = "running" ]
    then
      log "Getting ngrok hostname and port"
      NGROK_URL=$(curl --silent http://127.0.0.1:4040/api/tunnels | jq -r '.tunnels[0].public_url')
      NGROK_HOSTNAME=$(echo $NGROK_URL | cut -d "/" -f3 | cut -d ":" -f 1)
      NGROK_PORT=$(echo $NGROK_URL | cut -d "/" -f3 | cut -d ":" -f 2)

      if ! [[ $NGROK_PORT =~ ^[0-9]+$ ]]
      then
        log "NGROK_PORT is not a valid number, keep retrying..."
        continue
      else 
        break
      fi
    fi
  fi
  log "Waiting for container ngrok to start..."
  sleep 5
done

connector_name="OracleXStreamSource_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
     "connector.class": "OracleXStreamSource",
     "name": "$connector_name",
     "kafka.auth.mode": "KAFKA_API_KEY",
     "kafka.api.key": "$CLOUD_KEY",
     "kafka.api.secret": "$CLOUD_SECRET",
     "output.data.key.format": "AVRO",
     "output.data.value.format": "AVRO",
     "database.dbname": "ORCLCDB",
     "database.hostname": "$NGROK_HOSTNAME",
     "database.port": "$NGROK_PORT",
     "database.os.timezone": "UTC",
     "database.out.server.name": "XOUT",
     "database.service.name": "ORCLCDB",
     "database.processor.licenses": "1",
     "table.include.list": "C##CFLTUSER[.]CUSTOMERS",
     "database.password": "password",
     "database.user": "c##cfltuser",
     "topic.prefix": "cflt",
     "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

sleep 10

log "Insert 2 customers in CUSTOMERS table"
docker exec -i oracle sqlplus c\#\#cfltuser/password@//localhost:1521/ORCLCDB << EOF
     insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments) values ('Frantz', 'Kafka', 'fkafka@confluent.io', 'Male', 'bronze', 'Evil is whatever distracts');
     insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments) values ('Gregor', 'Samsa', 'gsamsa@confluent.io', 'Male', 'platinium', 'How about if I sleep a little bit longer and forget all this nonsense');
     exit;
EOF

log "Update CUSTOMERS with email=fkafka@confluent.io"
docker exec -i oracle sqlplus c\#\#cfltuser/password@//localhost:1521/ORCLCDB << EOF
     update CUSTOMERS set club_status = 'gold' where email = 'fkafka@confluent.io';
     exit;
EOF

log "Deleting CUSTOMERS with email=fkafka@confluent.io"
docker exec -i oracle sqlplus c\#\#cfltuser/password@//localhost:1521/ORCLCDB << EOF
     delete from CUSTOMERS where email = 'fkafka@confluent.io';
     exit;
EOF

sleep 10

log "Altering CUSTOMERS table with an optional column"
docker exec -i oracle sqlplus c\#\#cfltuser/password@//localhost:1521/ORCLCDB << EOF
     alter table CUSTOMERS add (country VARCHAR(50));
     exit;
EOF

sleep 1

log "Populating CUSTOMERS table after altering the structure"
docker exec -i oracle sqlplus c\#\#cfltuser/password@//localhost:1521/ORCLCDB << EOF
     insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments, country) values ('Josef', 'K', 'jk@confluent.io', 'Male', 'bronze', 'How is it even possible for someone to be guilty', 'Poland');
     update CUSTOMERS set club_status = 'silver' where email = 'gsamsa@confluent.io';
     update CUSTOMERS set club_status = 'gold' where email = 'gsamsa@confluent.io';
     update CUSTOMERS set club_status = 'gold' where email = 'jk@confluent.io';
     commit;
     exit;
EOF

log "Verifying topic cflt.C__CFLTUSER.CUSTOMERS: there should be 14 records"
playground topic consume --topic cflt.C__CFLTUSER.CUSTOMERS --min-expected-messages 14 --timeout 120

if [ ! -z "$SQL_DATAGEN" ]
then
     DURATION=10
     log "Injecting data for $DURATION minutes"
     docker exec sql-datagen bash -c "java ${JAVA_OPTS} -jar sql-datagen-1.0-SNAPSHOT-jar-with-dependencies.jar --host oracle --username c##cfltuser --password password --sidOrServerName sid --sidOrServerNameVal ORCLCDB --maxPoolSize 10 --durationTimeMin $DURATION"
fi

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name

log "⚙️ You can use <playground connector oracle-cdc-xstream generate-report> to generate oracle cdc xstream connector diagnostics report"
log "🐞 You can use <playground connector oracle-cdc-xstream debug> to execute various SQL commands to debug xstream components"