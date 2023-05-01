#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -z "$SQL_DATAGEN" ]
then
     log "🌪️ SQL_DATAGEN is set"
     for component in oracle-datagen
     do
     set +e
     log "🏗 Building jar for ${component}"
     docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${DIR}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "$PWD/../../scripts/settings.xml:/tmp/settings.xml" -v "${DIR}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -s /tmp/settings.xml -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
     if [ $? != 0 ]
     then
          logerror "ERROR: failed to build java component "
          tail -500 /tmp/result.log
          exit 1
     fi
     set -e
     done
else
     log "🛑 SQL_DATAGEN is not set"
fi

if [ ! -z "$CONNECTOR_TAG" ]
then
     JDBC_CONNECTOR_VERSION=$CONNECTOR_TAG
else
     JDBC_CONNECTOR_VERSION=$(docker run ${CP_CONNECT_IMAGE}:${CONNECT_TAG} cat /usr/share/confluent-hub-components/confluentinc-kafka-connect-jdbc/manifest.json | jq -r '.version')
fi
log "JDBC Connector version is $JDBC_CONNECTOR_VERSION"
if ! version_gt $JDBC_CONNECTOR_VERSION "9.9.9"; then
     get_3rdparty_file "ojdbc6.jar"
     if [ ! -f ${DIR}/ojdbc6.jar ]
     then
          logerror "ERROR: ${DIR}/ojdbc6.jar is missing. It must be downloaded manually in order to acknowledge user agreement"
          exit 1
     fi
     ${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"
else
     log "ojdbc jar is shipped with connector (starting with 10.0.0)"
     ${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.no-ojdbc.yml"
fi

log "create table"
docker exec -i oracle bash -c "ORACLE_SID=XE;export ORACLE_SID;export ORACLE_HOME=/u01/app/oracle/product/11.2.0/xe;/u01/app/oracle/product/11.2.0/xe/bin/sqlplus myuser/mypassword@//localhost:1521/XE" << EOF
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
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class":"io.confluent.connect.jdbc.JdbcSourceConnector",
               "tasks.max":"1",
               "connection.user": "myuser",
               "connection.password": "mypassword",
               "connection.url": "jdbc:oracle:thin:@oracle:1521/XE",
               "numeric.mapping":"best_fit",
               "mode":"timestamp",
               "poll.interval.ms":"1000",
               "validate.non.null":"false",
               "table.whitelist":"CUSTOMERS",
               "timestamp.column.name":"UPDATE_TS",
               "topic.prefix":"oracle-",
               "schema.pattern":"MYUSER"
          }' \
     http://localhost:8083/connectors/oracle-source/config | jq .

sleep 5

log "Verifying topic oracle-CUSTOMERS"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic oracle-CUSTOMERS --from-beginning --max-messages 1

if [ ! -z "$SQL_DATAGEN" ]
then
     DURATION=10
     log "Injecting data for $DURATION minutes"
     docker exec sql-datagen bash -c "java ${JAVA_OPTS} -jar sql-datagen-1.0-SNAPSHOT-jar-with-dependencies.jar --host oracle --username myuser --password mypassword --sidOrServerName sid --sidOrServerNameVal XE --maxPoolSize 10 --durationTimeMin $DURATION"
fi
