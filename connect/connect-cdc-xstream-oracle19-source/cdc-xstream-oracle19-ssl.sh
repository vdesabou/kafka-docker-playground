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

# required to make utils.sh script being able to work, do not remove:
# PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
#playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.ssl.yml"
log "Starting up oracle container to get generated cert from oracle server wallet"
docker compose -f ../../environment/plaintext/docker-compose.yml ${KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE} -f "${PWD}/docker-compose.plaintext.ssl.yml" up -d oracle


log "Setting up SSL on oracle server..."
# https://www.oracle.com/technetwork/topics/wp-oracle-jdbc-thin-ssl-130128.pdf
log "Create a wallet for the test CA"

docker exec oracle bash -c "orapki wallet create -wallet /tmp/root -pwd WalletPasswd123"
# Add a self-signed certificate to the wallet
docker exec oracle bash -c "orapki wallet add -wallet /tmp/root -dn CN=root_test,C=US -keysize 2048 -self_signed -validity 3650 -pwd WalletPasswd123"
# Export the certificate
docker exec oracle bash -c "orapki wallet export -wallet /tmp/root -dn CN=root_test,C=US -cert /tmp/root/b64certificate.txt -pwd WalletPasswd123"

log "Create a wallet for the Oracle server"

# Create an empty wallet with auto login enabled
docker exec oracle bash -c "orapki wallet create -wallet /tmp/server -pwd WalletPasswd123 -auto_login"
# Add a user In the wallet (a new pair of private/public keys is created)
docker exec oracle bash -c "orapki wallet add -wallet /tmp/server -dn CN=server,C=US -pwd WalletPasswd123 -keysize 2048"
# Export the certificate request to a file
docker exec oracle bash -c "orapki wallet export -wallet /tmp/server -dn CN=server,C=US -pwd WalletPasswd123 -request /tmp/server/creq.txt"
# Using the test CA, sign the certificate request
docker exec oracle bash -c "orapki cert create -wallet /tmp/root -request /tmp/server/creq.txt -cert /tmp/server/cert.txt -validity 3650 -pwd WalletPasswd123"
log "You now have the following files under the /tmp/server directory"
docker exec oracle ls /tmp/server
# View the signed certificate:
docker exec oracle bash -c "orapki cert display -cert /tmp/server/cert.txt -complete"
# Add the test CA's trusted certificate to the wallet
docker exec oracle bash -c "orapki wallet add -wallet /tmp/server -trusted_cert -cert /tmp/root/b64certificate.txt -pwd WalletPasswd123"
# add the user certificate to the wallet:
docker exec oracle bash -c "orapki wallet add -wallet /tmp/server -user_cert -cert /tmp/server/cert.txt -pwd WalletPasswd123"

cd ${DIR}/ssl
if [[ "$OSTYPE" == "darwin"* ]]
then
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # on CI, docker is run as runneradmin user, need to use sudo
    sudo chmod -R a+rw .
fi
cd ${DIR}

log "Update listener.ora, sqlnet.ora and tnsnames.ora"
docker cp ${PWD}/ssl/listener.ora oracle:/opt/oracle/oradata/dbconfig/ORCLCDB/listener.ora
docker cp ${PWD}/ssl/sqlnet.ora oracle:/opt/oracle/oradata/dbconfig/ORCLCDB/sqlnet.ora
docker cp ${PWD}/ssl/tnsnames.ora oracle:/opt/oracle/oradata/dbconfig/ORCLCDB/tnsnames.ora

docker exec -i oracle lsnrctl << EOF
reload
stop
start
EOF

log "Sleeping 60 seconds"
sleep 60

set_profiles
docker compose -f ../../environment/plaintext/docker-compose.yml ${KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE} -f "${PWD}/docker-compose.plaintext.ssl.yml" ${profile_control_center_command} ${profile_ksqldb_command} ${profile_zookeeper_command}  ${profile_grafana_command} ${profile_kcat_command} up -d --quiet-pull
command="source ${DIR}/../../scripts/utils.sh && docker compose -f ../../environment/plaintext/docker-compose.yml ${KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE} -f ${PWD}/docker-compose.plaintext.ssl.yml $${profile_control_center_command} ${profile_ksqldb_command} ${profile_zookeeper_command}  ${profile_grafana_command} ${profile_kcat_command} up -d"
playground state set run.docker_command "$command"
playground state set run.environment "plaintext"
log "✨ If you modify a docker-compose file and want to re-create the container(s), run cli command 'playground container recreate'"

wait_container_ready


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

log "Set connect default certificate store (common root certificate) with oracle trusted certificate"
cd ${DIR}/ssl
# https://confluentinc.atlassian.net/wiki/spaces/OAAC/pages/4192768158/Oracle+XStream+Connector+Connection+Encryption#One-way-TLS-without-client-wallet
docker cp oracle:/tmp/root/b64certificate.txt b64certificate.txt
docker cp b64certificate.txt connect:/etc/pki/ca-trust/source/anchors/
playground container exec --root --command "update-ca-trust" --container connect
cd ${DIR}

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
     "database.port": "1532",
     "database.user": "c##cfltuser",
     "database.tls.mode": "one-way",
     "topic.prefix": "cflt",
     "schema.history.internal.kafka.bootstrap.servers": "broker:9092",
     "schema.history.internal.kafka.topic": "__orcl-schema-changes.cflt",
     "confluent.license": "",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor": "1",

     "_comment:": "remove _ to use ExtractNewRecordState smt",
     "_transforms": "unwrap,RemoveDots",
     "_transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState"
}
EOF

sleep 5

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
playground topic consume --topic cflt.C__CFLTUSER.CUSTOMERS --min-expected-messages 14 --timeout 60

if [ ! -z "$SQL_DATAGEN" ]
then
     DURATION=10
     log "Injecting data for $DURATION minutes"
     docker exec sql-datagen bash -c "java ${JAVA_OPTS} -jar sql-datagen-1.0-SNAPSHOT-jar-with-dependencies.jar --host oracle --username c##cfltuser --password password --sidOrServerName sid --sidOrServerNameVal ORCLCDB --maxPoolSize 10 --durationTimeMin $DURATION"
fi

log "⚙️ You can use <playground connector oracle-cdc-xstream generate-report> to generate oracle cdc xstream connector diagnostics report"
log "🐞 You can use <playground connector oracle-cdc-xstream debug> to execute various SQL commands to debug xstream components"