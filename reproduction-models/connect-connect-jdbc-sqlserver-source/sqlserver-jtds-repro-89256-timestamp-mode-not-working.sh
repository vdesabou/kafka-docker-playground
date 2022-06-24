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


${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.jtds.repro-89256-timestamp-mode-not-working.yml"



log "Load inventory.sql to SQL Server"
cat inventory-repro-89256-timestamp-mode-not-working.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'


log "Creating JDBC SQL Server (with JTDS driver) source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
               "tasks.max": "1",
               "connection.url": "jdbc:sqlserver://sqlserver:1433;databaseName=testDB",
               "connection.user": "sa",
               "connection.password": "Password!",
               "table.whitelist": "customers",
               "mode": "timestamp",
               "timestamp.delay.interval.ms": "0",
               "timestamp.column.name": "last_update",
               "topic.prefix": "sqlserver-",
               "validate.non.null":"false",
               "errors.log.enable": "true",
               "errors.log.include.messages": "true"
          }' \
     http://localhost:8083/connectors/sqlserver-source/config | jq .

# with JTDS driver:
# [2022-01-24 09:26:19,830] ERROR [sqlserver-source-ssl|task-0] Failed to run query for table: TimestampTableQuerier{table="testDB"."dbo"."customers", query='null', topicPrefix='sqlserver-', timestampColumns=[last_update]} (io.confluent.connect.jdbc.source.JdbcSourceTask:423)
# java.lang.ClassCastException: class java.lang.String cannot be cast to class java.sql.Timestamp (java.lang.String is in module java.base of loader 'bootstrap'; java.sql.Timestamp is in module java.sql of loader 'platform')
#         at io.confluent.connect.jdbc.source.TimestampIncrementingCriteria.extractOffsetTimestamp(TimestampIncrementingCriteria.java:229)
#         at io.confluent.connect.jdbc.source.TimestampIncrementingCriteria.extractValues(TimestampIncrementingCriteria.java:198)
#         at io.confluent.connect.jdbc.source.TimestampTableQuerier.doExtractRecord(TimestampTableQuerier.java:148)
#         at io.confluent.connect.jdbc.source.TimestampTableQuerier.next(TimestampTableQuerier.java:98)
#         at io.confluent.connect.jdbc.source.JdbcSourceTask.poll(JdbcSourceTask.java:383)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.poll(WorkerSourceTask.java:291)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.execute(WorkerSourceTask.java:248)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:189)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:238)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)

# with Microsoft driver
# OK

# 09:47:18 ℹ️ Verifying topic sqlserver-customers
# {"id":1001,"first_name":"Sally","last_name":"Thomas","email":"sally.thomas@acme.com","last_update":{"long":1643017632873}}
# {"id":1002,"first_name":"George","last_name":"Bailey","email":"gbailey@foobar.com","last_update":{"long":1643017632876}}
# {"id":1003,"first_name":"Edward","last_name":"Walker","email":"ed@walker.com","last_update":{"long":1643017632876}}
# {"id":1004,"first_name":"Anne","last_name":"Kretchmar","email":"annek@noanswer.org","last_update":{"long":1643017632880}}
# {"id":1005,"first_name":"Pam","last_name":"Thomas","email":"pam@office.com","last_update":{"long":1643017638376}}
# Processed a total of 5 messages

sleep 5

docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! << EOF
USE testDB;
INSERT INTO customers(first_name,last_name,email,last_update) VALUES ('Pam','Thomas','pam@office.com', GETDATE());
GO
EOF

log "Verifying topic sqlserver-customers"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic sqlserver-customers --from-beginning --max-messages 5
