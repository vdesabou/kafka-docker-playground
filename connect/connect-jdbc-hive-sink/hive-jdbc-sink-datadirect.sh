#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "10.7.99"
then
     logwarn "minimal supported connector version is 10.8.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.1.html#supported-connector-versions-in-cp-8-1"
     exit 111
fi

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
     wget -q https://repo1.maven.org/maven2/com/facebook/presto/presto-cli/0.183/presto-cli-0.183-executable.jar
     mv presto-cli-0.183-executable.jar presto.jar
     chmod +x presto.jar
fi



cd ../../connect/connect-jdbc-hive-sink

# Copy JAR files to confluent-hub
mkdir -p ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/
cp ../../connect/connect-jdbc-hive-sink/hive.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/hive.jar
cp ../../connect/connect-jdbc-hive-sink/hive-jdbc-3.1.2-standalone.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/hive-jdbc-3.1.2-standalone.jar
cd -
PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.datadirect.yml"

sleep 30

log "Create table in hive"
docker exec -i hive-server /opt/hive/bin/beeline -u jdbc:hive2://localhost:10000 << EOF
CREATE TABLE pokes (foo INT, bar STRING);
EOF


docker exec -i hive-server /opt/hive/bin/beeline -u jdbc:hive2://localhost:10000 << EOF
show databases
EOF

log "Sending messages to topic pokes"
playground topic produce -t pokes --nb-messages 10 --forced-value "{\"foo\": %g,\"bar\": \"a string\"}" << 'EOF'
{
  "fields": [
    {
      "name": "foo",
      "type": "int"
    },
    {
      "name": "bar",
      "type": "string"
    }
  ],
  "name": "myrecord",
  "type": "record"
}
EOF

log "Creating JDBC Hive (with Datadirect) sink connector"
playground connector create-or-update --connector jdbc-hive-sink  << EOF
{
     "connector.class" : "io.confluent.connect.jdbc.JdbcSinkConnector",
     "tasks.max" : "1",
     "connection.url": "jdbc:datadirect:hive://hive-server:10000;DatabaseName=default;User=hive;Password=hive;TransactionMode=ignore",
     "auto.create": "true",
     "auto.evolve": "true",
     "topics": "pokes",
     "pk.mode": "record_value",
     "pk.fields": "foo",
     "table.name.format": "default.\${topic}"
}
EOF

sleep 10

log "Check data is in hive"
${DIR}/presto.jar --server localhost:18080 --catalog hive --schema default > /tmp/result.log  2>&1 <<-EOF
select * from pokes;
EOF
cat /tmp/result.log
grep "foo" /tmp/result.log
