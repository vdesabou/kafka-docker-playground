#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -z "$SQL_DATAGEN" ]
then
     cd ../../connect/connect-cdc-oracle11-source
     log "🌪️ SQL_DATAGEN is set, make sure to increase redo.log.row.fetch.size, have a look at https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-cdc-oracle19-source/README.md#note-on-redologrowfetchsize"
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

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

playground --output-level WARN container logs --container oracle --wait-for-log "Grant succeeded." --max-wait 900
log "Oracle DB has started!"

log "create table"
docker exec -i oracle bash -c "ORACLE_SID=XE;export ORACLE_SID;export ORACLE_HOME=/u01/app/oracle/product/11.2.0/xe;/u01/app/oracle/product/11.2.0/xe/bin/sqlplus MYUSER/password@//localhost:1521/XE" << EOF
create table CUSTOMERS (
        id NUMBER(10) NOT NULL PRIMARY KEY,
        first_name VARCHAR(50),
        last_name VARCHAR(50),
        email VARCHAR(50),
        gender VARCHAR(50),
        club_status VARCHAR(20),
        comments VARCHAR(4000),
        create_ts timestamp DEFAULT CURRENT_TIMESTAMP,
        update_ts timestamp
);

CREATE SEQUENCE CUSTOMERS_SEQ START WITH 1;

CREATE OR REPLACE TRIGGER CUSTOMERS_TRIGGER_ID
BEFORE INSERT ON CUSTOMERS
FOR EACH ROW

BEGIN
  SELECT CUSTOMERS_SEQ.NEXTVAL
  INTO   :new.id
  FROM   dual;
END;
/

CREATE OR REPLACE TRIGGER CUSTOMERS_TRIGGER_TS
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
EOF

log "Creating Oracle source connector"
playground connector create-or-update --connector cdc-oracle11-source --package "io.confluent.connect.oracle.cdc.util.metrics.MetricsReporter" --level DEBUG  << EOF
{
     "connector.class": "io.confluent.connect.oracle.cdc.OracleCdcSourceConnector",
     "tasks.max": 2,
     "key.converter": "io.confluent.connect.avro.AvroConverter",
     "key.converter.schema.registry.url": "http://schema-registry:8081",
     "value.converter": "io.confluent.connect.avro.AvroConverter",
     "value.converter.schema.registry.url": "http://schema-registry:8081",
     "confluent.license": "",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor": "1",
     "oracle.server": "oracle",
     "oracle.port": 1521,
     "oracle.sid": "XE",
     "oracle.username": "MYUSER",
     "oracle.password": "password",
     "start.from":"snapshot",
     "enable.metrics.collection": "true",
     "redo.log.topic.name": "redo-log-topic",
     "redo.log.consumer.bootstrap.servers":"broker:9092",
     "table.inclusion.regex": ".*CUSTOMERS.*",
     "table.topic.name.template": "\${databaseName}.\${schemaName}.\${tableName}",
     "numeric.mapping": "best_fit",
     "connection.pool.max.size": 20,
     "redo.log.row.fetch.size": 1,
     "topic.creation.groups": "redo",
     "topic.creation.redo.include": "redo-log-topic",
     "topic.creation.redo.replication.factor": 1,
     "topic.creation.redo.partitions": 1,
     "topic.creation.redo.cleanup.policy": "delete",
     "topic.creation.redo.retention.ms": 1209600000,
     "topic.creation.default.replication.factor": 1,
     "topic.creation.default.partitions": 1,
     "topic.creation.default.cleanup.policy": "delete"
}
EOF

log "Waiting 10s for connector to read existing data"
sleep 10

log "Insert 2 customers in CUSTOMERS table"
docker exec -i oracle bash -c "export ORACLE_HOME=/u01/app/oracle/product/11.2.0/xe && /u01/app/oracle/product/11.2.0/xe/bin/sqlplus MYUSER/password@//localhost:1521/XE" << EOF
     insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments) values ('Frantz', 'Kafka', 'fkafka@confluent.io', 'Male', 'bronze', 'Evil is whatever distracts');
     insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments) values ('Gregor', 'Samsa', 'gsamsa@confluent.io', 'Male', 'platinium', 'How about if I sleep a little bit longer and forget all this nonsense');
     exit;
EOF

log "Update CUSTOMERS with email=fkafka@confluent.io"
docker exec -i oracle bash -c "export ORACLE_HOME=/u01/app/oracle/product/11.2.0/xe && /u01/app/oracle/product/11.2.0/xe/bin/sqlplus MYUSER/password@//localhost:1521/XE" << EOF
     update CUSTOMERS set club_status = 'gold' where email = 'fkafka@confluent.io';
     exit;
EOF

log "Deleting CUSTOMERS with email=fkafka@confluent.io"
docker exec -i oracle bash -c "export ORACLE_HOME=/u01/app/oracle/product/11.2.0/xe && /u01/app/oracle/product/11.2.0/xe/bin/sqlplus MYUSER/password@//localhost:1521/XE" << EOF
     delete from CUSTOMERS where email = 'fkafka@confluent.io';
     exit;
EOF

log "Altering CUSTOMERS table with an optional column"
docker exec -i oracle bash -c "export ORACLE_HOME=/u01/app/oracle/product/11.2.0/xe && /u01/app/oracle/product/11.2.0/xe/bin/sqlplus MYUSER/password@//localhost:1521/XE" << EOF
     alter table CUSTOMERS add (
          country VARCHAR(50)
     );
     exit;
EOF

log "Populating CUSTOMERS table after altering the structure"
docker exec -i oracle bash -c "export ORACLE_HOME=/u01/app/oracle/product/11.2.0/xe && /u01/app/oracle/product/11.2.0/xe/bin/sqlplus MYUSER/password@//localhost:1521/XE" << EOF
     insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments, country) values ('Josef', 'K', 'jk@confluent.io', 'Male', 'bronze', 'How is it even possible for someone to be guilty', 'Poland');
     update CUSTOMERS set club_status = 'silver' where email = 'gsamsa@confluent.io';
     update CUSTOMERS set club_status = 'gold' where email = 'gsamsa@confluent.io';
     update CUSTOMERS set club_status = 'gold' where email = 'jk@confluent.io';
     commit;
     exit;
EOF

log "Waiting 20s for connector to read new data"
sleep 20

log "Verifying topic XE.MYUSER.CUSTOMERS: there should be 13 records"
playground topic consume --topic XE.MYUSER.CUSTOMERS --min-expected-messages 13 --timeout 60

log "Verifying topic redo-log-topic: there should be 14 records"
playground topic consume --topic redo-log-topic --min-expected-messages 14 --timeout 60

if [ ! -z "$SQL_DATAGEN" ]
then
     DURATION=10
     log "Injecting data for $DURATION minutes"
     docker exec -d sql-datagen bash -c "java ${JAVA_OPTS} -jar sql-datagen-1.0-SNAPSHOT-jar-with-dependencies.jar --host oracle --username MYUSER --password password --sidOrServerName sid --sidOrServerNameVal XE --maxPoolSize 10 --durationTimeMin $DURATION"
fi