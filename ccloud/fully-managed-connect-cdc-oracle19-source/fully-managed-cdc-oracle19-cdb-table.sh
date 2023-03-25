#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

NGROK_AUTH_TOKEN=${NGROK_AUTH_TOKEN:-$1}

if [ -z "$NGROK_AUTH_TOKEN" ]
then
     logerror "NGROK_AUTH_TOKEN is not set. Export it as environment variable or pass it as argument"
     logerror "Sign up at: https://dashboard.ngrok.com/signup"
     logerror "If you have already signed up, make sure your authtoken is installed."
     logerror "Your authtoken is available on your dashboard: https://dashboard.ngrok.com/get-started/your-authtoken"
     exit 1
fi

logwarn "🚨WARNING🚨"
logwarn "It is considered a security risk to run this example on your personal machine since you'll be exposing a TCP port over internet using Ngrok (https://ngrok.com)."
logwarn "It is strongly encouraged to run it on a AWS EC2 instance where you'll use Confluent Static Egress IP Addresses (https://docs.confluent.io/cloud/current/networking/static-egress-ip-addresses.html#use-static-egress-ip-addresses-with-ccloud) (only available for public endpoints on AWS) to allow traffic from your Confluent Cloud cluster to your EC2 instance using EC2 Security Group."
logwarn ""
logwarn "Example in order to set EC2 Security Group with Confluent Static Egress IP Addresses and port 1521:"
logwarn "group=\$(aws ec2 describe-instances --instance-id <\$ec2-instance-id> --output=json | jq '.Reservations[] | .Instances[] | {SecurityGroups: .SecurityGroups}' | jq -r '.SecurityGroups[] | .GroupName')"
logwarn "aws ec2 authorize-security-group-ingress --group-name "\$group" --protocol tcp --port 1521 --cidr 13.36.88.88/32"
logwarn "aws ec2 authorize-security-group-ingress --group-name "\$group" --protocol tcp --port 1521 --cidr 13.36.88.89/32"
logwarn "etc..."
check_if_continue

bootstrap_ccloud_environment

if [ -f /tmp/delta_configs/env.delta ]
then
     source /tmp/delta_configs/env.delta
else
     logerror "ERROR: /tmp/delta_configs/env.delta has not been generated"
     exit 1
fi

create_or_get_oracle_image "LINUX.X64_193000_db_home.zip" "../../ccloud/fully-managed-connect-cdc-oracle19-source/ora-setup-scripts-cdb-table"

set +e
delete_topic ORCLCDB.C__MYUSER.CUSTOMERS
delete_topic redo-log-topic
set -e

docker-compose build
docker-compose down -v --remove-orphans
docker-compose up -d

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
     GRANT EXECUTE ON SYS.DBMS_LOGMNR TO C##CDC_PRIVS;
     GRANT LOGMINING TO C##CDC_PRIVS;
     GRANT SELECT ON V_\$LOGMNR_CONTENTS TO C##CDC_PRIVS;
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

     -- Following privileges are required additionally for 19c compared to 12c.
     GRANT SELECT ON V_\$ARCHIVED_LOG TO C##CDC_PRIVS;
     GRANT SELECT ON V_\$LOG TO C##CDC_PRIVS;
     GRANT SELECT ON V_\$LOGFILE TO C##CDC_PRIVS;
     GRANT SELECT ON V_\$INSTANCE to C##CDC_PRIVS;

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

     insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments) values (1, 'Rica', 'Blaisdell', 'rblaisdell0@rambler.ru', 'Female', 'bronze', 'Universal optimal hierarchy');
     insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments) values (2, 'Ruthie', 'Brockherst', 'rbrockherst1@ow.ly', 'Female', 'platinum', 'Reverse-engineered tangible interface');
     insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments) values (3, 'Mariejeanne', 'Cocci', 'mcocci2@techcrunch.com', 'Female', 'bronze', 'Multi-tiered bandwidth-monitored capability');
     insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments) values (4, 'Hashim', 'Rumke', 'hrumke3@sohu.com', 'Male', 'platinum', 'Self-enabling 24/7 firmware');
     insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments) values (5, 'Hansiain', 'Coda', 'hcoda4@senate.gov', 'Male', 'platinum', 'Centralized full-range approach');
     exit;
EOF

log "Getting ngrok hostname and port"
NGROK_URL=$(curl --silent http://127.0.0.1:4551/api/tunnels | jq -r '.tunnels[0].public_url')
NGROK_HOSTNAME=$(echo $NGROK_URL | cut -d "/" -f3 | cut -d ":" -f 1)
NGROK_PORT=$(echo $NGROK_URL | cut -d "/" -f3 | cut -d ":" -f 2)

#confluent connect plugin describe IbmMQSource

cat << EOF > connector.json
{
     "connector.class": "OracleCdcSource",
     "name": "OracleCdcSource",
     "kafka.auth.mode": "KAFKA_API_KEY",
     "kafka.api.key": "$CLOUD_KEY",
     "kafka.api.secret": "$CLOUD_SECRET",
     "output.data.key.format": "AVRO",
     "output.data.value.format": "AVRO",
     "oracle.server": "$NGROK_HOSTNAME",
     "oracle.port": "$NGROK_PORT",
     "oracle.sid": "ORCLCDB",
     "oracle.username": "C##MYUSER",
     "oracle.password": "mypassword",
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

log "Connector configuration is:"
cat connector.json

set +e
log "Deleting fully managed connector, it might fail..."
delete_ccloud_connector connector.json
set -e

log "Creating fully managed connector"
create_ccloud_connector connector.json
wait_for_ccloud_connector_up connector.json 1800


log "Waiting 20s for connector to read existing data"
sleep 20

log "Running SQL scripts"
for script in ../../ccloud/fully-managed-connect-cdc-oracle19-source/sample-sql-scripts/*.sh
do
     $script "ORCLCDB"
done

log "Waiting 20s for connector to read new data"
sleep 20

log "Verifying topic ORCLCDB.C__MYUSER.CUSTOMERS: there should be 13 records"
set +e
timeout 60 docker run --rm -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SASL_JAAS_CONFIG="$SASL_JAAS_CONFIG" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" ${CP_CONNECT_IMAGE}:${CONNECT_TAG} kafka-avro-console-consumer --topic ORCLCDB.C__MYUSER.CUSTOMERS --bootstrap-server $BOOTSTRAP_SERVERS --consumer-property ssl.endpoint.identification.algorithm=https --consumer-property sasl.mechanism=PLAIN --consumer-property security.protocol=SASL_SSL --consumer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --from-beginning --max-messages 13 --property print.key=true > /tmp/result.log  2>&1
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
timeout 60 docker run --rm -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SASL_JAAS_CONFIG="$SASL_JAAS_CONFIG" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" ${CP_CONNECT_IMAGE}:${CONNECT_TAG} kafka-avro-console-consumer --topic redo-log-topic --bootstrap-server $BOOTSTRAP_SERVERS --consumer-property ssl.endpoint.identification.algorithm=https --consumer-property sasl.mechanism=PLAIN --consumer-property security.protocol=SASL_SSL --consumer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --from-beginning --max-messages 9 --property print.key=true

log "🚚 If you're planning to inject more data, have a look at https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-cdc-oracle19-source/README.md#note-on-redologrowfetchsize"


log "Do you want to delete the fully managed connector ?"
check_if_continue

log "Deleting fully managed connector"
delete_ccloud_connector connector.json