#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

logerror "getCatalogName() method is not implemented on Hive, see https://issues.apache.org/jira/browse/HIVE-3175"

if [ ! -f ${DIR}/hive-jdbc-3.1.2-standalone.jar ]
then
     log "Getting hive-jdbc-3.1.2-standalone.jar"
     wget https://repo1.maven.org/maven2/org/apache/hive/hive-jdbc/4.0.0-beta-1/hive-jdbc-4.0.0-beta-1.jar
fi

if [ ! -f ${DIR}/presto.jar ]
then
     log "Getting presto-cli-0.183-executable.jar"
     wget https://repo1.maven.org/maven2/com/facebook/presto/presto-cli/0.183/presto-cli-0.183-executable.jar
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

log "insert a row"
${DIR}/presto.jar --server localhost:18080 --catalog hive --schema default << EOF
insert into pokes (foo, bar) values (1,'test');
EOF

log "Creating JDBC Hive source connector"
playground connector create-or-update --connector jdbc-hive-source  << EOF
{
  "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
  "tasks.max": "1",
  "connection.url": "jdbc:hive2://hive-server:10000/default",
  "mode": "bulk",
  "topic.prefix": "hive-",
  "errors.log.enable": "true",
  "errors.log.include.messages": "true"
}
EOF

# jdbc-hive-source               ✅ RUNNING  0:🛑 FAILED[connect]          tasks: org.apache.kafka.connect.errors.ConnectException: java.sql.SQLFeatureNotSupportedException: Method not supported
#         at io.confluent.connect.jdbc.source.JdbcSourceTask.poll(JdbcSourceTask.java:475)
#         at org.apache.kafka.connect.runtime.AbstractWorkerSourceTask.poll(AbstractWorkerSourceTask.java:481)
#         at org.apache.kafka.connect.runtime.AbstractWorkerSourceTask.execute(AbstractWorkerSourceTask.java:354)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:229)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:284)
#         at org.apache.kafka.connect.runtime.AbstractWorkerSourceTask.run(AbstractWorkerSourceTask.java:78)
#         at org.apache.kafka.connect.runtime.isolation.Plugins.lambda$withClassLoader$1(Plugins.java:181)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: java.sql.SQLFeatureNotSupportedException: Method not supported
#         at org.apache.hive.jdbc.HiveResultSetMetaData.getCatalogName(HiveResultSetMetaData.java:46)
#         at io.confluent.connect.jdbc.dialect.GenericDatabaseDialect.describeColumn(GenericDatabaseDialect.java:773)
#         at io.confluent.connect.jdbc.dialect.GenericDatabaseDialect.describeColumns(GenericDatabaseDialect.java:755)
#         at io.confluent.connect.jdbc.source.SchemaMapping.create(SchemaMapping.java:63)
#         at io.confluent.connect.jdbc.source.TableQuerier.maybeStartQuery(TableQuerier.java:103)
#         at io.confluent.connect.jdbc.source.BulkTableQuerier.maybeStartQuery(BulkTableQuerier.java:39)
#         at io.confluent.connect.jdbc.source.JdbcSourceTask.poll(JdbcSourceTask.java:436)
#         ... 11 more
