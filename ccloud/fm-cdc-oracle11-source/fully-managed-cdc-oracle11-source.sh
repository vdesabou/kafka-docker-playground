#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh


NGROK_AUTH_TOKEN=${NGROK_AUTH_TOKEN:-$1}

display_ngrok_warning

bootstrap_ccloud_environment



set +e
playground topic delete --topic XE.MYUSER.CUSTOMERS
playground topic delete --topic redo-log-topic
set -e

docker compose build
docker compose down -v --remove-orphans
docker compose up -d --quiet-pull

# Verify Oracle DB has started within MAX_WAIT seconds
MAX_WAIT=900
CUR_WAIT=0
log "⌛ Waiting up to $MAX_WAIT seconds for Oracle DB to start"
docker container logs oracle > /tmp/out.txt 2>&1
while [[ ! $(cat /tmp/out.txt) =~ "Grant succeeded." ]]; do
sleep 10
docker container logs oracle > /tmp/out.txt 2>&1
CUR_WAIT=$(( CUR_WAIT+10 ))
if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
     logerror "ERROR: The logs in oracle container do not show 'Grant succeeded.' after $MAX_WAIT seconds. Please troubleshoot with 'docker container ps' and 'docker container logs'.\n"
     exit 1
fi
done
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

connector_name="OracleCdcSource_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
     "connector.class": "OracleCdcSource",
     "name": "$connector_name",
     "kafka.auth.mode": "KAFKA_API_KEY",
     "kafka.api.key": "$CLOUD_KEY",
     "kafka.api.secret": "$CLOUD_SECRET",
     "output.data.key.format": "AVRO",
     "output.data.value.format": "AVRO",
     "oracle.server": "$NGROK_HOSTNAME",
     "oracle.port": "$NGROK_PORT",
     "oracle.sid": "XE",
     "oracle.username": "MYUSER",
     "oracle.password": "password",
     "table.inclusion.regex": ".*CUSTOMERS.*",
     "start.from": "snapshot",
     "query.timeout.ms": "60000",
     "redo.log.row.fetch.size": "1",
     "redo.log.topic.name": "redo-log-topic",
     "table.topic.name.template": "\${databaseName}.\${schemaName}.\${tableName}",
     "lob.topic.name.template":"\${databaseName}.\${schemaName}.\${tableName}.\${columnName}",
     "numeric.mapping": "best_fit_or_decimal",
     "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

log "Waiting 20s for connector to read existing data"
sleep 20

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

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name