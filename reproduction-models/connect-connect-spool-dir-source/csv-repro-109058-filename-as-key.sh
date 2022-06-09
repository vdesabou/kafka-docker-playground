#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-109058-filename-as-key.yml"

log "Generate data"
docker exec -i connect bash -c 'mkdir -p /tmp/data/input/ && mkdir -p /tmp/data/error/ && mkdir -p /tmp/data/finished/ && curl -k "https://api.mockaroo.com/api/58605010?count=1000&key=25fd9c80" > /tmp/data/input/csv-spooldir-source.csv'

log "Creating CSV Spool Dir Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "tasks.max": "1",
          "connector.class": "com.github.jcustenborder.kafka.connect.spooldir.SpoolDirCsvSourceConnector",
          "input.file.pattern": "csv-spooldir-source.csv",
          "input.path": "/tmp/data/input",
          "error.path": "/tmp/data/error",
          "finished.path": "/tmp/data/finished",
          "halt.on.error": "false",
          "topic": "a-topic",
          "csv.first.row.as.header": "true",

          "key.converter": "io.confluent.connect.avro.AvroConverter",
          "key.converter.schema.registry.url": "http://schema-registry:8081",
          "value.converter": "io.confluent.connect.avro.AvroConverter",
          "value.converter.schema.registry.url": "http://schema-registry:8081",

          "key.schema": "{\n  \"name\" : \"com.example.users.UserKey\",\n  \"type\" : \"STRUCT\",\n  \"isOptional\" : false,\n  \"fieldSchemas\" : {\n    \"id\" : {\n      \"type\" : \"INT64\",\n      \"isOptional\" : false\n    }\n  }\n}",
          "value.schema": "{\n  \"name\" : \"com.example.users.User\",\n  \"type\" : \"STRUCT\",\n  \"isOptional\" : false,\n  \"fieldSchemas\" : {\n    \"id\" : {\n      \"type\" : \"INT64\",\n      \"isOptional\" : false\n    },\n    \"first_name\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"last_name\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"email\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"gender\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"ip_address\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"last_login\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"account_balance\" : {\n      \"name\" : \"org.apache.kafka.connect.data.Decimal\",\n      \"type\" : \"BYTES\",\n      \"version\" : 1,\n      \"parameters\" : {\n        \"scale\" : \"2\"\n      },\n      \"isOptional\" : true\n    },\n    \"country\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"favorite_color\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    }\n  }\n}",
          "transforms" : "headerToField,ValueToKey,ExtractField,ReplaceField",
          "transforms.headerToField.type" : "com.github.jcustenborder.kafka.connect.transform.common.HeaderToField$Value",
          "transforms.headerToField.header.mappings" : "file.name:STRING:file_name",
          "transforms.ValueToKey.type": "org.apache.kafka.connect.transforms.ValueToKey",
          "transforms.ValueToKey.fields": "file_name",
          "transforms.ExtractField.type": "org.apache.kafka.connect.transforms.ExtractField$Key",
          "transforms.ExtractField.field": "file_name",
          "transforms.ReplaceField.type": "org.apache.kafka.connect.transforms.ReplaceField$Value",
          "transforms.ReplaceField.blacklist": "file_name"
     }}' \
     http://localhost:8083/connectors/spool-dir/config | jq .


sleep 5

log "Verify we have received the data in a-topic topic"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic a-topic --from-beginning --property print.key=true --max-messages 1

# "csv-spooldir-source.csv"       {"id":9,"first_name":{"string":"Mariel"},"last_name":{"string":"Bann"},"email":{"string":"mbann8@webs.com"},"gender":{"string":"Female"},"ip_address":{"string":"11.250.140.218"},"last_login":{"string":"2018-05-06T04:58:31Z"},"account_balance":{"bytes":"\u000B²M"},"country":{"string":"AR"},"favorite_color":{"string":"#4e4620"}}

