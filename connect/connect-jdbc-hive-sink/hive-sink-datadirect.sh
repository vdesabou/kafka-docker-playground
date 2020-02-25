#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/hive.jar ]
then
     log "hive.jar is missing. Follow https://documentation.progress.com/output/DataDirect/jdbcquickstarts/hivejdbc_quickstart/index.html#page/jdbchivequick%2Fquick-start-3a-progress-datadirect-for-jdbc-for-ap.html%23 to install it"
     exit 1
fi

# https://documentation.progress.com/output/DataDirect/jdbcquickstarts/hivejdbc_quickstart/index.html#page/jdbchivequick%2Fdownloading-the-driver.html%23wwID0EB2AG
# https://documentation.progress.com/output/DataDirect/jdbchivehelp/index.html#page/jdbchive%2Fwelcome-to-the-progress-datadirect-for-jdbc-for.html%23

if [ ! -f ${DIR}/presto.jar ]
then
     log "Getting presto-cli-0.183-executable.jar"
     wget https://repo1.maven.org/maven2/com/facebook/presto/presto-cli/0.183/presto-cli-0.183-executable.jar
     mv presto-cli-0.183-executable.jar presto.jar
     chmod +x presto.jar
fi


${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.datadirect.yml"

sleep 30

log "Create table in hive"
docker exec -i hive-server /opt/hive/bin/beeline -u jdbc:hive2://localhost:10000 << EOF
CREATE TABLE pokes (foo INT, bar STRING);
EOF


docker exec -i hive-server /opt/hive/bin/beeline -u jdbc:hive2://localhost:10000 << EOF
show databases
EOF

log "Sending messages to topic pokes"
seq -f "{\"foo\": %g,\"bar\": \"a string\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic pokes --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"foo","type":"int"},{"name":"bar","type":"string"}]}'

log "Creating JDBC Hive (with Datadirect) sink connector"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class" : "io.confluent.connect.jdbc.JdbcSinkConnector",
               "tasks.max" : "1",
               "connection.url": "jdbc:datadirect:hive://hive-server:10000;DatabaseName=default;User=hive;Password=hive;TransactionMode=ignore",
               "auto.create": "true",
               "auto.evolve": "true",
               "topics": "pokes",
               "pk.mode": "record_value",
               "pk.fields": "foo",
               "table.name.format": "default.${topic}"
          }' \
     http://localhost:8083/connectors/jdbc-hive-sink/config | jq .

sleep 10

log "Check data is in hive"
${DIR}/presto.jar --server localhost:18080 --catalog hive --schema default << EOF
select * from pokes;
EOF
