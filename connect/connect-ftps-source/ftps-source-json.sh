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

docker exec -t ftps-server bash -c "
mkdir -p /home/vsftpd/bob/input
mkdir -p /home/vsftpd/bob/error
mkdir -p /home/vsftpd/bob/finished

chown -R ftp /home/vsftpd/bob
"

echo $'{"id":1,"first_name":"Roscoe","last_name":"Brentnall","email":"rbrentnall0@mediafire.com","gender":"Male","ip_address":"202.84.142.254","last_login":"2018-02-12T06:26:23Z","account_balance":1450.68,"country":"CZ","favorite_color":"#4eaefa"}\n{"id":2,"first_name":"Gregoire","last_name":"Fentem","email":"gfentem1@nsw.gov.au","gender":"Male","ip_address":"221.159.106.63","last_login":"2015-03-27T00:29:56Z","account_balance":1392.37,"country":"ID","favorite_color":"#e8f686"}' > json-ftps-source.json

docker cp json-ftps-source.json ftps-server:/home/vsftpd/bob/input/
rm -f json-ftps-source.json

log "Creating JSON file with schema FTPS Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.ftps.FtpsSourceConnector",
               "ftps.behavior.on.error":"LOG",
               "ftps.input.path": "/input",
               "ftps.error.path": "/error",
               "ftps.finished.path": "/finished",
               "ftps.input.file.pattern": "json-ftps-source.json",
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
               "kafka.topic": "ftps-testing-topic",
               "schema.generation.enabled": "false",
               "key.converter": "io.confluent.connect.avro.AvroConverter",
               "key.converter.schema.registry.url": "http://schema-registry:8081",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "key.schema": "{\"name\" : \"com.example.users.UserKey\",\"type\" : \"STRUCT\",\"isOptional\" : false,\"fieldSchemas\" : {\"id\" : {\"type\" : \"INT64\",\"isOptional\" : false}}}",
               "value.schema": "{\"name\" : \"com.example.users.User\",\"type\" : \"STRUCT\",\"isOptional\" : false,\"fieldSchemas\" : {\"id\" : {\"type\" : \"INT64\",\"isOptional\" : false},\"first_name\" : {\"type\" : \"STRING\",\"isOptional\" : true},\"last_name\" : {\"type\" : \"STRING\",\"isOptional\" : true},\"email\" : {\"type\" : \"STRING\",\"isOptional\" : true},\"gender\" : {\"type\" : \"STRING\",\"isOptional\" : true},\"ip_address\" : {\"type\" : \"STRING\",\"isOptional\" : true},\"last_login\" : {\"type\" : \"STRING\",\"isOptional\" : true},\"account_balance\" : {\"name\" : \"org.apache.kafka.connect.data.Decimal\",\"type\" : \"BYTES\",\"version\" : 1,\"parameters\" : {\"scale\" : \"2\"},\"isOptional\" : true},\"country\" : {\"type\" : \"STRING\",\"isOptional\" : true},\"favorite_color\" : {\"type\" : \"STRING\",\"isOptional\" : true}}}"
          }' \
     http://localhost:8083/connectors/ftps-source-json/config | jq .

sleep 5

log "Verifying topic ftps-testing-topic"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic ftps-testing-topic --from-beginning --max-messages 2