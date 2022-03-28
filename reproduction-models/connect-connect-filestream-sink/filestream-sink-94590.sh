#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Generate data"
docker exec -i connect bash -c 'mkdir -p /tmp/data/input/ && mkdir -p /tmp/data/error/ && mkdir -p /tmp/data/finished/ && curl -k "https://api.mockaroo.com/api/17c84440?count=500&key=25fd9c80" > /tmp/data/input/json-spooldir-source.json'

log "Creating JSON Spool Dir Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
               "connector.class": "com.github.jcustenborder.kafka.connect.spooldir.SpoolDirJsonSourceConnector",
               "input.file.pattern": "json-spooldir-source.json",
               "input.path": "/tmp/data/input",
               "error.path": "/tmp/data/error",
               "finished.path": "/tmp/data/finished",
               "halt.on.error": "false",
               "topic": "customer_avro",
               "key.schema": "{\n  \"name\" : \"com.example.users.UserKey\",\n  \"type\" : \"STRUCT\",\n  \"isOptional\" : false,\n  \"fieldSchemas\" : {\n    \"id\" : {\n      \"type\" : \"INT64\",\n      \"isOptional\" : false\n    }\n  }\n}",
               "value.schema": "{\n  \"name\" : \"com.example.users.User\",\n  \"type\" : \"STRUCT\",\n  \"isOptional\" : false,\n  \"fieldSchemas\" : {\n    \"id\" : {\n      \"type\" : \"INT64\",\n      \"isOptional\" : false\n    },\n    \"first_name\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"last_name\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"email\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"gender\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"ip_address\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"last_login\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"account_balance\" : {\n      \"name\" : \"org.apache.kafka.connect.data.Decimal\",\n      \"type\" : \"BYTES\",\n      \"version\" : 1,\n      \"parameters\" : {\n        \"scale\" : \"2\"\n      },\n      \"isOptional\" : true\n    },\n    \"country\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"favorite_color\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    }\n  }\n}"
         }' \
     http://localhost:8083/connectors/spool-dir/config | jq .

sleep 5

log "Verify we have received the headers in customer_avro topic"
timeout 60 docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic customer_avro --property print.headers=true --property print.value=false --from-beginning --max-messages 10

log "Creating FileStream Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
               "connector.class": "FileStreamSink",
               "topics": "customer_avro",
               "file": "/tmp/data/file_sink.json",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "transforms" : "headerToField",
               "transforms.headerToField.type" : "com.github.jcustenborder.kafka.connect.transform.common.HeaderToField$Value",
               "transforms.headerToField.header.mappings" : "file.path:STRING:file_path,file.name:STRING:file_name,file.last.modified:INT64(Timestamp):file_last_modified,file.length:INT32:file_length"
              }' \
     http://localhost:8083/connectors/filestream-sink/config | jq .

sleep 5


log "Verify that we have data in the file"
docker exec -i connect bash -c 'cat /tmp/data/file_sink.json | head -10 | grep "file.name"'