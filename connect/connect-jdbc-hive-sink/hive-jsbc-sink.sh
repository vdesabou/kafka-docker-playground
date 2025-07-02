#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -z "$TAG_BASE" ] && version_gt $TAG_BASE "7.9.99" && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "10.7.99"
then
     logwarn "minimal supported connector version is 10.8.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.0.html#supported-connector-versions-in-cp-8-0"
     exit 111
fi

logerror "addBatch() method is not implemented on Hive"

if [ ! -f ${DIR}/hive-jdbc-3.1.2-standalone.jar ]
then
     log "Getting hive-jdbc-3.1.2-standalone.jar"
     wget -q https://repo1.maven.org/maven2/org/apache/hive/hive-jdbc/3.1.2/hive-jdbc-3.1.2-standalone.jar
fi

if [ ! -f ${DIR}/presto.jar ]
then
     log "Getting presto-cli-0.183-executable.jar"
     wget -q https://repo1.maven.org/maven2/com/facebook/presto/presto-cli/0.183/presto-cli-0.183-executable.jar
     mv presto-cli-0.183-executable.jar presto.jar
     chmod +x presto.jar
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

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

log "Creating JDBC Hive sink connector"
playground connector create-or-update --connector jdbc-hive-sink  << EOF
{
     "connector.class" : "io.confluent.connect.jdbc.JdbcSinkConnector",
     "tasks.max" : "1",
     "connection.url": "jdbc:hive2://hive-server:10000/default",
     "auto.create": "true",
     "auto.evolve": "true",
     "topics": "pokes",
     "pk.mode": "record_value",
     "pk.fields": "foo",
     "table.name.format": "default.\${topic}"
}
EOF

# [2023-10-09 11:13:45,400] WARN [jdbc-hive-sink|task-0] Write of 10 records failed, remainingRetries=8 (io.confluent.connect.jdbc.sink.JdbcSinkTask:101)
# java.sql.SQLFeatureNotSupportedException: Method not supported
#         at org.apache.hive.jdbc.HivePreparedStatement.addBatch(HivePreparedStatement.java:78)
#         at io.confluent.connect.jdbc.sink.PreparedStatementBinder.bindRecord(PreparedStatementBinder.java:115)
#         at io.confluent.connect.jdbc.sink.BufferedRecords.flush(BufferedRecords.java:183)
#         at io.confluent.connect.jdbc.sink.JdbcDbWriter.write(JdbcDbWriter.java:80)
#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:90)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:593)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:340)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:238)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:207)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:229)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:284)
#         at org.apache.kafka.connect.runtime.isolation.Plugins.lambda$withClassLoader$1(Plugins.java:181)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
#         Suppressed: java.sql.SQLFeatureNotSupportedException: Method not supported
#                 at org.apache.hive.jdbc.HiveConnection.rollback(HiveConnection.java:1340)
#                 at io.confluent.connect.jdbc.sink.JdbcDbWriter.write(JdbcDbWriter.java:86)
#                 ... 13 more

sleep 10

log "Check data is in hive"
${DIR}/presto.jar --server localhost:18080 --catalog hive --schema default > /tmp/result.log  2>&1 <<-EOF
select * from pokes;
EOF
cat /tmp/result.log
grep "foo" /tmp/result.log
