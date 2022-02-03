#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/sqljdbc_7.4/enu/mssql-jdbc-7.4.1.jre8.jar ]
then
     log "Downloading Microsoft JDBC driver mssql-jdbc-7.4.1.jre8.jar"
     wget https://download.microsoft.com/download/6/9/9/699205CA-F1F1-4DE9-9335-18546C5C8CBD/sqljdbc_7.4.1.0_enu.tar.gz
     tar xvfz sqljdbc_7.4.1.0_enu.tar.gz
     rm -f sqljdbc_7.4.1.0_enu.tar.gz
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.microsoft.yml"

# Removed pre-installed JTDS driver
docker exec connect rm -f /usr/share/confluent-hub-components/confluentinc-kafka-connect-jdbc/lib/jtds-1.3.1.jar
docker container restart connect

log "sleeping 60 seconds"
sleep 60

log "Load inventory-repro-89155.sql to SQL Server"
cat inventory-repro-89155.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'

log "activate TRACE for io.confluent.connect.jdbc"
curl --request PUT \
  --url http://localhost:8083/admin/loggers/io.confluent.connect.jdbc \
  --header 'Accept: application/json' \
  --header 'Content-Type: application/json' \
  --data '{
	"level": "TRACE"
}'

log "activate DEBUG for org.apache.kafka.connect.runtime.WorkerSinkTask"
curl --request PUT \
  --url http://localhost:8083/admin/loggers/org.apache.kafka.connect.runtime.WorkerSinkTask \
  --header 'Accept: application/json' \
  --header 'Content-Type: application/json' \
  --data '{
	"level": "DEBUG"
}'

log "Creating JDBC SQL Server (with Microsoft driver) sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
               "tasks.max": "1",
               "connection.url": "jdbc:sqlserver://sqlserver:1433;databaseName=testDB",
               "connection.user": "sa",
               "connection.password": "Password!",
               "topics": "customers",
               "auto.create": "false",
               "errors.tolerance": "all",
               "errors.deadletterqueue.topic.name": "dlq",
               "errors.deadletterqueue.topic.replication.factor": "1",
               "errors.deadletterqueue.context.headers.enable": "true",
               "errors.log.enable": "true",
               "errors.log.include.messages": "true",
               "errors.retry.delay.max.ms": "60000",
               "errors.retry.timeout": "0",
               "max.retries": "0"
          }' \
     http://localhost:8083/connectors/sqlserver-sink/config | jq .

log "Sending messages to topic customers, valid record"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic customers --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"first_name", "type": "string"}]}' << EOF
{"first_name": "vincent"}
EOF

sleep 85

set +e
log "check __consumer_offsets"
timeout 30 docker container exec -i connect bash -c 'kafka-console-consumer \
     --bootstrap-server broker:9092 \
     --topic __consumer_offsets \
     --from-beginning \
     --formatter "kafka.coordinator.group.GroupMetadataManager\$OffsetsMessageFormatter"' | grep sqlserver-sink

# [connect-sqlserver-sink,customers,0]::OffsetAndMetadata(offset=1, leaderEpoch=Optional.empty, metadata=, commitTimestamp=1642764490472, expireTimestamp=None)

log "Sending messages to topic customers, it goes to DLQ"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic customers --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"first_name", "type": "string"}]}' << EOF
{"first_name": "fooccccvvfjnvdkjnbjkdgnbjfgnbkjfgnbkjfngjkbnfgbjfg"}
EOF

sleep 65

log "check __consumer_offsets"
timeout 30 docker container exec -i connect bash -c 'kafka-console-consumer \
     --bootstrap-server broker:9092 \
     --topic __consumer_offsets \
     --from-beginning \
     --formatter "kafka.coordinator.group.GroupMetadataManager\$OffsetsMessageFormatter"' | grep sqlserver-sink

# repro: no commit
# [connect-sqlserver-sink,customers,0]::OffsetAndMetadata(offset=1, leaderEpoch=Optional.empty, metadata=, commitTimestamp=1642764490472, expireTimestamp=None)

# log "Show content of customers table:"
# docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! > /tmp/result.log  2>&1 <<-EOF
# select * from customers
# GO
# EOF
# cat /tmp/result.log
# grep "foo" /tmp/result.log


log "Now re-creating same connector, it will reprocess bad record"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
               "tasks.max": "2",
               "connection.url": "jdbc:sqlserver://sqlserver:1433;databaseName=testDB",
               "connection.user": "sa",
               "connection.password": "Password!",
               "topics": "customers",
               "auto.create": "false",
               "errors.tolerance": "all",
               "errors.deadletterqueue.topic.name": "dlq",
               "errors.deadletterqueue.topic.replication.factor": "1",
               "errors.deadletterqueue.context.headers.enable": "true"
          }' \
     http://localhost:8083/connectors/sqlserver-sink/config | jq .

# [2022-01-21 11:34:07,518] WARN [sqlserver-sink|task-0] Write of 2 records failed, remainingRetries=0 (io.confluent.connect.jdbc.sink.JdbcSinkTask:92)
# java.sql.BatchUpdateException: String or binary data would be truncated in table 'testDB.dbo.customers', column 'first_name'. Truncated value: 'fooccccvvfjnvdkjnbjk'.
#         at com.microsoft.sqlserver.jdbc.SQLServerPreparedStatement.executeBatch(SQLServerPreparedStatement.java:2085)
#         at io.confluent.connect.jdbc.sink.BufferedRecords.executeUpdates(BufferedRecords.java:221)
#         at io.confluent.connect.jdbc.sink.BufferedRecords.flush(BufferedRecords.java:187)
#         at io.confluent.connect.jdbc.sink.JdbcDbWriter.write(JdbcDbWriter.java:80)
#         at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:84)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:604)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:334)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)

log "show DLQ has 2 duplicate records !"
timeout 60 docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic dlq --from-beginning --max-messages 2
