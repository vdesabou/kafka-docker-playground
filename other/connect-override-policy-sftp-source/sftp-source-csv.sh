#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

rm -rf ${DIR}/upload/

${DIR}/../../environment/sasl-plain/start.sh "${PWD}/docker-compose.sasl-plain.yml"

mkdir -p ${DIR}/upload/input
mkdir -p ${DIR}/upload/error
mkdir -p ${DIR}/upload/finished

echo $'id,first_name,last_name,email,gender,ip_address,last_login,account_balance,country,favorite_color\n1,Salmon,Baitman,sbaitman0@feedburner.com,Male,120.181.75.98,2015-03-01T06:01:15Z,17462.66,IT,#f09bc0\n2,Debby,Brea,dbrea1@icio.us,Female,153.239.187.49,2018-10-21T12:27:12Z,14693.49,CZ,#73893a' > ${DIR}/upload/input/csv-sftp-source.csv



# Principal = User:sftp is Denied Operation = Describe from host = 192.168.208.6 on resource = Topic:LITERAL:sftp-testing-topic (kafka.authorizer.logger)

docker exec broker kafka-acls --authorizer-properties zookeeper.connect=zookeeper:2181 --add --allow-principal User:sftp --producer --topic sftp-testing-topic

# Adding ACLs for resource `Topic:LITERAL:sftp-testing-topic`:
#         User:sftp has Allow permission for operations: Create from hosts: *
#         User:sftp has Allow permission for operations: Describe from hosts: *
#         User:sftp has Allow permission for operations: Write from hosts: *

echo "Creating CSV SFTP Source connector"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
        "topics": "test_sftp_sink",
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.sftp.SftpCsvSourceConnector",
               "cleanup.policy":"NONE",
               "behavior.on.error":"IGNORE",
               "input.path": "/upload/input",
               "error.path": "/upload/error",
               "finished.path": "/upload/finished",
               "input.file.pattern": "csv-sftp-source.csv",
               "sftp.username":"foo",
               "sftp.password":"pass",
               "sftp.host":"sftp-server",
               "sftp.port":"22",
               "kafka.topic": "sftp-testing-topic",
               "csv.first.row.as.header": "true",
               "schema.generation.enabled": "true",
               "producer.override.sasl.mechanism": "PLAIN",
               "producer.override.security.protocol": "SASL_PLAINTEXT",
               "producer.override.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"sftp\" password=\"sftp-secret\";"
          }' \
     http://localhost:8083/connectors/sftp-source/config | jq .

sleep 5

echo "Verifying topic sftp-testing-topic"
docker exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --topic sftp-testing-topic --consumer.config /tmp/client.properties --from-beginning --max-messages 2