#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

create_or_get_oracle_image "LINUX.X64_193000_db_home.zip" "../../connect/connect-jdbc-oracle19-source/ora-setup-scripts"

if [ ! -z "$CONNECTOR_TAG" ]
then
     JDBC_CONNECTOR_VERSION=$CONNECTOR_TAG
else
     JDBC_CONNECTOR_VERSION=$(docker run vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} cat /usr/share/confluent-hub-components/confluentinc-kafka-connect-jdbc/manifest.json | jq -r '.version')
fi
log "JDBC Connector version is $JDBC_CONNECTOR_VERSION"
if ! version_gt $JDBC_CONNECTOR_VERSION "9.9.9"; then
     get_3rdparty_file "ojdbc8.jar"
     if [ ! -f ${DIR}/ojdbc8.jar ]
     then
          logerror "ERROR: ${DIR}/ojdbc8.jar is missing. It must be downloaded manually in order to acknowledge user agreement"
          exit 1
     fi
     ${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"
else
     log "ojdbc jar is shipped with connector (starting with 10.0.0)"
     ${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.no-ojdbc.repro-100178-jdbc-source-connectors-do-not-destroy-sessions-when-restarted.yml"
fi

# Verify Oracle DB has started within MAX_WAIT seconds
MAX_WAIT=2500
CUR_WAIT=0
log "⌛ Waiting up to $MAX_WAIT seconds for Oracle DB to start"
docker container logs oracle > /tmp/out.txt 2>&1
while [[ ! $(cat /tmp/out.txt) =~ "DONE: Executing user defined scripts" ]]; do
sleep 10
docker container logs oracle > /tmp/out.txt 2>&1
CUR_WAIT=$(( CUR_WAIT+10 ))
if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
     logerror "ERROR: The logs in oracle container do not show 'DONE: Executing user defined scripts' after $MAX_WAIT seconds. Please troubleshoot with 'docker container ps' and 'docker container logs'.\n"
     exit 1
fi
done
log "Oracle DB has started!"

# curl --request PUT \
#   --url http://localhost:8083/admin/loggers/io.confluent.connect.jdbc \
#   --header 'Accept: application/json' \
#   --header 'Content-Type: application/json' \
#   --data '{
#  "level": "DEBUG"
# }'

# log "Show content of ORDERS table:"
# docker exec oracle bash -c "echo 'select * from ORDERS;' | sqlplus myuser/mypassword@//localhost:1521/ORCLPDB1" > /tmp/result.log  2>&1
# cat /tmp/result.log
# grep "foo" /tmp/result.log

# using dbVizualizer
# docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
# CONNECT sys/Admin123 AS SYSDBA

# CREATE OR REPLACE FUNCTION "MYUSER"."NAME_OF_ORACLE_FUNCTION"
# RETURN VARCHAR2
# AS
# PRAGMA AUTONOMOUS_TRANSACTION;

# BEGIN
#     EXECUTE IMMEDIATE '
#             DELETE FROM MYUSER.CUSTOMERS
#             WHERE id < 10
#         ';
#     COMMIT;
         
#     RETURN 'here we go !';
# END;
# /

# BEGIN
#     EXECUTE IMMEDIATE
#         'GRANT EXECUTE ON MYUSER.NAME_OF_ORACLE_FUNCTION TO MYUSER';
# END;
# /

# exit;
# EOF



log "Creating Oracle source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class":"io.confluent.connect.jdbc.JdbcSourceConnector",
               "tasks.max":"1",
               "connection.user": "myuser",
               "connection.password": "mypassword",
               "connection.url": "jdbc:oracle:thin:@oracle:1521/ORCLPDB1",
               "numeric.mapping":"best_fit",
               "mode":"bulk",
               "query": "SELECT MYUSER.NAME_OF_ORACLE_FUNCTION FROM DUAL",
               "poll.interval.ms": "259200000",
               "validate.non.null":"false",
               "topic.prefix":"oracle-output",
               "errors.log.enable": "true",
               "errors.log.include.messages": "true",

               "connection.attempts": "360",
               "connection.backoff.ms": "10000",
               "db.timezone": "Europe/Paris",
               "schema.pattern":"MYUSER",
               "transforms.SetSchemaName.schema.name": "NAME_OF_ORACLE_FUNCTION",
               "transforms.SetSchemaName.type": "org.apache.kafka.connect.transforms.SetSchemaMetadata$Value",
               "transforms": "SetSchemaName"
          }' \
     http://localhost:8083/connectors/oracle-source/config | jq .

sleep 5

log "Verifying topic oracle-output"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic oracle-output --from-beginning --max-messages 2


# the problem is present with 10.0.2 (not latest 10.4)
for((i=0;i<10;i++))
do
     log "Restarting task"
     curl -X POST localhost:8083/connectors/oracle-source/tasks/0/restart

     sleep 5

     log "getting resources"
docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
CONNECT sys/Admin123 AS SYSDBA
SELECT RESOURCE_NAME,LIMIT_VALUE,CURRENT_UTILIZATION,MAX_UTILIZATION FROM v\$resource_limit where RESOURCE_NAME IN ('processes','sessions');
exit;
EOF

     log "getting sesions"
docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
CONNECT sys/Admin123 AS SYSDBA
SELECT MACHINE, OSUSER, USERNAME, COUNT(*) AS SESSIONS_COUNT FROM "V\$SESSION" WHERE MACHINE LIKE 'connec%' GROUP BY MACHINE, OSUSER, USERNAME;
exit;
EOF
done
