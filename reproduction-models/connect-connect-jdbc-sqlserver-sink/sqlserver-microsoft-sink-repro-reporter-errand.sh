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

${DIR}/../../environment/sasl-plain/start.sh "${PWD}/docker-compose.sasl-plain.repro-reporter-errand.yml"

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

# log "activate DEBUG for org.apache.kafka.connect.runtime.WorkerSinkTask"
# curl --request PUT \
#   --url http://localhost:8083/admin/loggers/org.apache.kafka.connect.runtime.WorkerSinkTask \
#   --header 'Accept: application/json' \
#   --header 'Content-Type: application/json' \
#   --data '{
# 	"level": "DEBUG"
# }'

docker exec broker kafka-acls --bootstrap-server broker:9092 --add --allow-principal User:sftp --consumer --topic customers --group connect-sqlserver-sink --command-config /tmp/client.properties
docker exec broker kafka-acls --bootstrap-server broker:9092 --add --allow-principal User:sftp --operation CREATE --topic dlq --command-config /tmp/client.properties
# Write for DLQ is not set

sleep 5

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
               "errors.retry.delay.max.ms": "301",
               "errors.retry.timeout": "0",
               "admin.override.sasl.mechanism": "PLAIN",
               "admin.override.security.protocol": "SASL_PLAINTEXT",
               "admin.override.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"sftp\" password=\"sftp-secret\";",
               "consumer.override.sasl.mechanism": "PLAIN",
               "consumer.override.security.protocol": "SASL_PLAINTEXT",
               "consumer.override.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"sftp\" password=\"sftp-secret\";",
               "producer.override.sasl.mechanism": "PLAIN",
               "producer.override.security.protocol": "SASL_PLAINTEXT",
               "producer.override.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"sftp\" password=\"sftp-secret\";"
          }' \
     http://localhost:8083/connectors/sqlserver-sink/config | jq .

log "Sending messages to topic customers, valid record"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic customers --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"first_name", "type": "string"}]}' --producer.config /tmp/client.properties << EOF
{"first_name": "vincent"}
EOF


log "Sending messages to topic customers, it goes to DLQ"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic customers --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"first_name", "type": "string"}]}' --producer.config /tmp/client.properties << EOF
{"first_name": "fooccccvvfjnvdkjnbjkdgnbjfgnbkjfgnbkjfngjkbnfgbjfg"}
EOF

log "continue manually..."
exit 0


# [2022-02-15 13:38:33,537] ERROR [sqlserver-sink|task-0] [Producer clientId=connect-worker-producer] Topic authorization failed for topics [dlq] (org.apache.kafka.clients.Metadata:309)

# the commit does not happen
docker exec broker kafka-acls --bootstrap-server broker:9092 --add --allow-principal User:client --operation READ --topic __consumer_offsets --command-config /tmp/client.properties
docker container exec -i connect bash -c 'kafka-console-consumer --bootstrap-server broker:9092 --topic __consumer_offsets --from-beginning --formatter "kafka.coordinator.group.GroupMetadataManager\$OffsetsMessageFormatter" --consumer.config /tmp/client.properties'   | grep sqlserver-sink

log "Add write ACL for DLQ"
docker exec broker kafka-acls --bootstrap-server broker:9092 --add --allow-principal User:sftp --operation WRITE --topic dlq --command-config /tmp/client.properties


# commit happens after

log "Show content of customers table:"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! > /tmp/result.log  2>&1 <<-EOF
USE testDB;
select * from customers
GO
EOF
cat /tmp/result.log
