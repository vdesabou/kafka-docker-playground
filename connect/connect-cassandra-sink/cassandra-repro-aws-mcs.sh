#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

verify_installed "keytool"

if [ ! -z "$MCS_USERNAME" ] && [ ! -z "$MCS_PASSWORD" ]
then
    log "MCS credentials are correctly set"
else
     # https://docs.aws.amazon.com/mcs/latest/devguide/accessing.html#ssc
    log "Environment variables MCS_USERNAME and MCS_PASSWORD should be set !"
    log "You can get them using: aws iam create-service-specific-credential --user-name <user> --service-name cassandra.amazonaws.com"
    log "Check ServiceUserName and ServicePassword"
    exit 1
fi

KEYSPACE=${1:-dockerplayground}
CASSANDRA_HOSTNAME=${2:-cassandra.us-east-1.amazonaws.com}

cd ${DIR}/security

log "Generate keys and certificates used for SSL"
verify_installed "keytool"
if [ ! -f $(find JAVA_HOME -name cacerts) ]
then
  logerror "ERROR: $(find JAVA_HOME -name cacerts) is not set"
  exit 1
fi

./certs-create.sh

cd ${DIR}

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext-aws-mcs.yml"

log "create a topic topic1"
docker exec broker kafka-topics --create --topic topic1 --partitions 1 --replication-factor 1 --zookeeper zookeeper:2181

log "Creating Cassandra Sink connector"
docker exec -e CASSANDRA_HOSTNAME="$CASSANDRA_HOSTNAME" -e KEYSPACE="$KEYSPACE" -e MCS_USERNAME="$MCS_USERNAME" -e MCS_PASSWORD="$MCS_PASSWORD" connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.cassandra.CassandraSinkConnector",
                    "tasks.max": "1",
                    "topics" : "topic1",
                    "cassandra.contact.points" : "'"$CASSANDRA_HOSTNAME"'",
                    "cassandra.port": "9142",
                    "cassandra.keyspace" : "'"$KEYSPACE"'",
                    "cassandra.username": "'"$MCS_USERNAME"'",
                    "cassandra.password": "'"$MCS_PASSWORD"'",
                    "cassandra.ssl.enabled": "true",
                    "cassandra.ssl.truststore.path": "/etc/kafka/secrets/kafka.connect.truststore.jks",
                    "cassandra.ssl.truststore.password": "confluent",
                    "cassandra.consistency.level": "ONE",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1",
                    "transforms": "createKey",
                    "transforms.createKey.fields": "f1",
                    "transforms.createKey.type": "org.apache.kafka.connect.transforms.ValueToKey"
          }' \
     http://localhost:8083/connectors/cassandra-mcs-sink/config | jq .

log "Sleep 45 seconds"
sleep 45

log "Sending messages to topic topic1"
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic topic1 --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

sleep 10

log "Go to your MCS console to verify messages are in AWS MCS cassandra table mydockerplaygroundkeyspace.topic1"

log "SELECT * FROM dockerplayground.topic1;"

log "if there is no data, you might restart the connector"
# docker exec -e CASSANDRA_HOSTNAME="$CASSANDRA_HOSTNAME" -e KEYSPACE="$KEYSPACE" -e MCS_USERNAME="$MCS_USERNAME" -e MCS_PASSWORD="$MCS_PASSWORD" cassandra  bash -c "export SSL_CERTFILE=/etc/kafka/secrets/kafka.cassandra.truststore.jks;cqlsh $CASSANDRA_HOSTNAME 9142 -u $MCS_USERNAME -p $MCS_PASSWORD --ssl -e 'select * from mydockerplaygroundkeyspace.topic1;'"
