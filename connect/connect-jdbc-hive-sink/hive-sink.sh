#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/hive-jdbc-3.1.2-standalone.jar ]
then
     log "Getting hive-jdbc-3.1.2-standalone.jar"
     wget https://repo1.maven.org/maven2/org/apache/hive/hive-jdbc/3.1.2/hive-jdbc-3.1.2-standalone.jar
fi

if [ ! -f ${DIR}/presto.jar ]
then
     log "Getting presto-cli-0.183-executable.jar"
     wget https://repo1.maven.org/maven2/com/facebook/presto/presto-cli/0.183/presto-cli-0.183-executable.jar
     mv presto-cli-0.183-executable.jar presto.jar
     chmod +x presto.jar
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

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

log "Creating JDBC Hive sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class" : "io.confluent.connect.jdbc.JdbcSinkConnector",
               "tasks.max" : "1",
               "connection.url": "jdbc:hive2://hive-server:10000/default",
               "auto.create": "true",
               "auto.evolve": "true",
               "topics": "pokes",
               "pk.mode": "record_value",
               "pk.fields": "foo",
               "table.name.format": "default.${topic}"
          }' \
     http://localhost:8083/connectors/jdbc-hive-sink/config | jq .

#

sleep 10

log "Check data is in hive"
${DIR}/presto.jar --server localhost:18080 --catalog hive --schema default > /tmp/result.log <<-EOF
select * from pokes;
EOF
cat /tmp/result.log
grep "foo" /tmp/result.log
