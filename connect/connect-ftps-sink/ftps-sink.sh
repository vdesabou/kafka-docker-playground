#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

cd ${DIR}/security

log "Generate keys and certificates used for SSL"
verify_installed "keytool"
./certs-create.sh # > /dev/null 2>&1

cd ${DIR}

if [ ! -z "$TRAVIS" ]
then
     # running with travis
     sudo chown root ${DIR}/config/vsftpd.conf
     sudo chown root ${DIR}/security/vsftpd.pem
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


log "Creating JSON file with schema FTPS Sink connector"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "3",
               "connector.class": "io.confluent.connect.ftps.FtpsSinkConnector",
               "ftps.working.dir": "/",
               "ftps.username":"bob",
               "ftps.password":"test",
               "ftps.host":"ftps-server",
               "ftps.port":"220",
               "ftps.security.mode": "EXPLICIT",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "ftps.ssl.truststore.location": "/etc/kafka/secrets/kafka.ftps-server.truststore.jks",
               "ftps.ssl.truststore.password": "confluent",
               "ftps.ssl.keystore.location": "/etc/kafka/secrets/kafka.ftps-server.keystore.jks",
               "ftps.ssl.key.password": "confluent",
               "ftps.ssl.keystore.password": "confluent",
               "topics": "test_ftps_sink",
               "key.converter": "io.confluent.connect.avro.AvroConverter",
               "key.converter.schema.registry.url": "http://schema-registry:8081",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "format.class": "io.confluent.connect.ftps.sink.format.avro.AvroFormat",
               "flush.size": "1"
          }' \
     http://localhost:8083/connectors/ftps-sink/config | jq .

log "Sending messages to topic test_ftps_sink"
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic test_ftps_sink --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

sleep 10

log "Listing content of /home/vsftpd/bob/test_ftps_sink/partition\=0/"
docker exec ftps-server bash -c "ls /home/vsftpd/bob/test_ftps_sink/partition\=0/"

docker cp ftps-server:/home/vsftpd/bob/test_ftps_sink/partition\=0/test_ftps_sink+0+0000000000.avro /tmp/

docker run -v /tmp:/tmp actions/avro-tools tojson /tmp/test_ftps_sink+0+0000000000.avro
