#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

create_or_get_oracle_image "LINUX.X64_213000_db_home.zip" "../../connect/connect-cdc-oracle21-source/ora-setup-scripts-cdb-table"

# required to make utils.sh script being able to work, do not remove:
# ${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


docker-compose -f ../../environment/plaintext/docker-compose.yml -f "${PWD}/docker-compose.plaintext.yml" down -v --remove-orphans
log "Starting up oracle container to get ojdbc8.jar and aqapi.jar"
docker-compose -f ../../environment/plaintext/docker-compose.yml -f "${PWD}/docker-compose.plaintext.yml" up -d oracle


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
     CREATE USER C##MYUSER IDENTIFIED BY mypassword DEFAULT TABLESPACE USERS;
     ALTER USER C##MYUSER QUOTA UNLIMITED ON USERS;
     exit;
EOF

if [ ! -f aqapi.jar ]
then
     docker cp oracle:/opt/oracle/product/21c/dbhome_1/rdbms/jlib/aqapi.jar aqapi.jar
fi
if [ ! -f ojdbc8.jar ]
then
     docker cp oracle:/opt/oracle/product/21c/dbhome_1/jdbc/lib/ojdbc8.jar ojdbc8.jar
fi
if [ ! -f jta-1.1.jar ]
then
     # NoClassDefFoundError: javax/transaction/Synchronization
     wget https://repo1.maven.org/maven2/javax/transaction/jta/1.1/jta-1.1.jar
fi

if [[ "$OSTYPE" == "darwin"* ]]
then
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # on CI, docker is run as runneradmin user, need to use sudo
    ls -lrt
    sudo chmod -R a+rw .
    ls -lrt
fi

docker-compose -f ../../environment/plaintext/docker-compose.yml -f "${PWD}/docker-compose.plaintext.yml" up -d

../../scripts/wait-for-connect-and-controlcenter.sh


# https://github.com/monodot/oracle-aq-demo
log "Grant all permissions to C##MYUSER"
docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
CONNECT sys/Admin123 AS SYSDBA

GRANT EXECUTE ON SYS.DBMS_AQ to C##MYUSER;
GRANT RESOURCE TO C##MYUSER;
GRANT CONNECT TO C##MYUSER;
GRANT EXECUTE ANY PROCEDURE TO C##MYUSER;
GRANT aq_administrator_role TO C##MYUSER;
GRANT aq_user_role TO C##MYUSER;
GRANT EXECUTE ON dbms_aqadm TO C##MYUSER;
GRANT EXECUTE ON dbms_aq TO C##MYUSER;
GRANT EXECUTE ON dbms_aqin TO C##MYUSER;

  exit;
EOF

log "Create JMS QUEUE called PLAYGROUND"
docker exec -i oracle sqlplus C\#\#MYUSER/mypassword@//localhost:1521/ORCLCDB << EOF

EXEC dbms_aqadm.create_queue_table('PLAYGROUNDTABLE', 'SYS.AQ\$_JMS_TEXT_MESSAGE')
EXEC dbms_aqadm.create_queue('PLAYGROUND','PLAYGROUNDTABLE')
EXEC dbms_aqadm.start_queue('PLAYGROUND')


set serverout on
DECLARE
enqueue_options DBMS_AQ.ENQUEUE_OPTIONS_T;
message_properties DBMS_AQ.MESSAGE_PROPERTIES_T;
message_handle RAW (16);
msg SYS.AQ\$_JMS_TEXT_MESSAGE;
BEGIN
msg := SYS.AQ\$_JMS_TEXT_MESSAGE.construct;
msg.set_text('HELLO PLSQL WORLD !');
DBMS_AQ.ENQUEUE (
queue_name => 'PLAYGROUND',
enqueue_options => enqueue_options,
message_properties => message_properties,
payload => msg,
msgid => message_handle);
COMMIT;
END;
/

  exit;
EOF

log "Check Queues"
docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
CONNECT sys/Admin123 AS SYSDBA


select owner, table_name from dba_all_tables where table_name = 'QT';
select owner, table_name from dba_all_tables where table_name = 'FOOQUEUETABLE';

  exit;
EOF

log "Creating JMS Oracle AQ source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jms.JmsSourceConnector",
               "tasks.max": "1",
               "kafka.topic": "jms-oracle-topic",

               "db_url": "jdbc:oracle:thin:@oracle:1521/ORCLCDB",
               "java.naming.factory.initial": "oracle.jms.AQjmsInitialContextFactory",
               "java.naming.provider.url": "jdbc:oracle:thin:@oracle:1521/ORCLCDB",
               "java.naming.security.credentials": "mypassword",
               "java.naming.security.principal": "C##MYUSER",
               "jms.destination.name": "PLAYGROUND",
               "jms.destination.type": "queue",
               "jms.message.format": "bytes",
               "jndi.connection.factory": "javax.jms.XAQueueConnectionFactory",

               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/jms-oracle-source/config | jq .


sleep 10

log "Verifying topic jms-oracle-topic"
playground topic consume --topic jms-oracle-topic --expected-messages 1

# {
#     "bytes": null,
#     "correlationID": null,
#     "deliveryMode": 2,
#     "destination": {
#         "io.confluent.connect.jms.Destination": {
#             "destinationType": "queue",
#             "name": "PLAYGROUND"
#         }
#     },
#     "expiration": 0,
#     "map": null,
#     "messageID": "ID:E088787E36F30226E053020018AC3EF1",
#     "messageType": "text",
#     "priority": 1,
#     "properties": {
#         "JMSXAppID": {
#             "boolean": null,
#             "byte": null,
#             "bytes": null,
#             "double": null,
#             "float": null,
#             "integer": null,
#             "long": null,
#             "propertyType": "null-value",
#             "short": null,
#             "string": null
#         },
#         "JMSXDeliveryCount": {
#             "boolean": null,
#             "byte": null,
#             "bytes": null,
#             "double": null,
#             "float": null,
#             "integer": {
#                 "int": 1
#             },
#             "long": null,
#             "propertyType": "integer",
#             "short": null,
#             "string": null
#         },
#         "JMSXGroupID": {
#             "boolean": null,
#             "byte": null,
#             "bytes": null,
#             "double": null,
#             "float": null,
#             "integer": null,
#             "long": null,
#             "propertyType": "null-value",
#             "short": null,
#             "string": null
#         },
#         "JMSXGroupSeq": {
#             "boolean": null,
#             "byte": null,
#             "bytes": null,
#             "double": null,
#             "float": null,
#             "integer": null,
#             "long": null,
#             "propertyType": "null-value",
#             "short": null,
#             "string": null
#         },
#         "JMSXRcvTimestamp": {
#             "boolean": null,
#             "byte": null,
#             "bytes": null,
#             "double": null,
#             "float": null,
#             "integer": null,
#             "long": {
#                 "long": 1654247333944
#             },
#             "propertyType": "long",
#             "short": null,
#             "string": null
#         },
#         "JMSXState": {
#             "boolean": null,
#             "byte": null,
#             "bytes": null,
#             "double": null,
#             "float": null,
#             "integer": {
#                 "int": 0
#             },
#             "long": null,
#             "propertyType": "integer",
#             "short": null,
#             "string": null
#         },
#         "JMSXUserID": {
#             "boolean": null,
#             "byte": null,
#             "bytes": null,
#             "double": null,
#             "float": null,
#             "integer": null,
#             "long": null,
#             "propertyType": "null-value",
#             "short": null,
#             "string": null
#         },
#         "JMS_OracleConnectionID": {
#             "boolean": null,
#             "byte": null,
#             "bytes": null,
#             "double": null,
#             "float": null,
#             "integer": null,
#             "long": null,
#             "propertyType": "null-value",
#             "short": null,
#             "string": null
#         },
#         "JMS_OracleDelay": {
#             "boolean": null,
#             "byte": null,
#             "bytes": null,
#             "double": null,
#             "float": null,
#             "integer": null,
#             "long": {
#                 "long": 0
#             },
#             "propertyType": "long",
#             "short": null,
#             "string": null
#         },
#         "JMS_OracleDeliveryMode": {
#             "boolean": null,
#             "byte": null,
#             "bytes": null,
#             "double": null,
#             "float": null,
#             "integer": null,
#             "long": null,
#             "propertyType": "null-value",
#             "short": null,
#             "string": null
#         },
#         "JMS_OracleExcpQ": {
#             "boolean": null,
#             "byte": null,
#             "bytes": null,
#             "double": null,
#             "float": null,
#             "integer": null,
#             "long": null,
#             "propertyType": "null-value",
#             "short": null,
#             "string": null
#         },
#         "JMS_OracleHeaderOnly": {
#             "boolean": null,
#             "byte": null,
#             "bytes": null,
#             "double": null,
#             "float": null,
#             "integer": null,
#             "long": null,
#             "propertyType": "null-value",
#             "short": null,
#             "string": null
#         },
#         "JMS_OracleOriginalMessageID": {
#             "boolean": null,
#             "byte": null,
#             "bytes": null,
#             "double": null,
#             "float": null,
#             "integer": null,
#             "long": null,
#             "propertyType": "null-value",
#             "short": null,
#             "string": null
#         },
#         "JMS_OracleTimestamp": {
#             "boolean": null,
#             "byte": null,
#             "bytes": null,
#             "double": null,
#             "float": null,
#             "integer": null,
#             "long": null,
#             "propertyType": "null-value",
#             "short": null,
#             "string": null
#         }
#     },
#     "redelivered": false,
#     "replyTo": null,
#     "text": {
#         "string": "HELLO PLSQL WORLD !"
#     },
#     "timestamp": 1654247330000,
#     "type": null
# }

