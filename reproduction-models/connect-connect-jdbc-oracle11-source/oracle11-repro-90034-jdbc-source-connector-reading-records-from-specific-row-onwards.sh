#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -z "$CONNECTOR_TAG" ]
then
     JDBC_CONNECTOR_VERSION=$CONNECTOR_TAG
else
     JDBC_CONNECTOR_VERSION=$(docker run vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} cat /usr/share/confluent-hub-components/confluentinc-kafka-connect-jdbc/manifest.json | jq -r '.version')
fi
log "JDBC Connector version is $JDBC_CONNECTOR_VERSION"
if ! version_gt $JDBC_CONNECTOR_VERSION "9.9.9"; then
     get_3rdparty_file "ojdbc6.jar"
     if [ ! -f ${DIR}/ojdbc6.jar ]
     then
          logerror "ERROR: ${DIR}/ojdbc6.jar is missing. It must be downloaded manually in order to acknowledge user agreement"
          exit 1
     fi
     ${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-90034-jdbc-source-connector-reading-records-from-specific-row-onwards.yml"
else
     log "ojdbc jar is shipped with connector (starting with 10.0.0)"
     ${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-90034-jdbc-source-connector-reading-records-from-specific-row-onwards.yml"
fi

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
               "mode": "incrementing",
               "incrementing.column.name": "ID",
               "query": "SELECT * FROM (SELECT * FROM MYTABLE WHERE ID>1)",
               "topic.prefix": "MY_TABLE_TOPIC",
               "poll.interval.ms":"1000",
               "validate.non.null":"false",
               "schema.pattern":"MYUSER",
               "errors.log.enable": "true",
               "errors.log.include.messages": "true"
          }' \
     http://localhost:8083/connectors/oracle-source/config | jq .

sleep 5

log "Verifying topic MY_TABLE_TOPIC"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic MY_TABLE_TOPIC --from-beginning --max-messages 2

# {"ID":2,"DESCRIPTION":"kafka2","UPDATE_TS":{"long":1643288347000}}
# {"ID":3,"DESCRIPTION":"kafka3","UPDATE_TS":{"long":1643288347000}}