#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

mkdir -p ${DIR}/data/input
mkdir -p ${DIR}/data/error
mkdir -p ${DIR}/data/finished

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

if [ ! -f "${DIR}/data/input/csv-spooldir-source.csv" ]
then
     log "Generating data"
     curl "https://api.mockaroo.com/api/58605010?count=1000&key=25fd9c80" > "${DIR}/data/input/csv-spooldir-source.csv"
fi

log "Registering subject spooldir-csv-topic-value"
curl --request POST \
  --url http://localhost:8081/subjects/spooldir-csv-topic-value/versions \
  --header 'Content-Type: application/vnd.schemaregistry.v1+json' \
  --data '{
    "schema": "{\n    \"type\": \"record\",\n    \"name\": \"User\",\n    \"namespace\": \"com.example.users\",\n    \"fields\": [\n        {\n            \"name\": \"id\",\n            \"type\": \"long\"\n        },\n        {\n            \"name\": \"first_name\",\n            \"type\": [\n                \"null\",\n                \"string\"\n            ],\n            \"default\": null\n        },\n        {\n            \"name\": \"last_name\",\n            \"type\": [\n                \"null\",\n                \"string\"\n            ],\n            \"default\": null\n        },\n        {\n            \"name\": \"email\",\n            \"type\": [\n                \"null\",\n                \"string\"\n            ],\n            \"default\": null\n        },\n        {\n            \"name\": \"gender\",\n            \"type\": [\n                \"null\",\n                \"string\"\n            ],\n            \"default\": null\n        },\n        {\n            \"name\": \"ip_address\",\n            \"type\": [\n                \"null\",\n                \"string\"\n            ],\n            \"default\": null\n        },\n        {\n            \"name\": \"last_login\",\n            \"type\": [\n                \"null\",\n                \"string\"\n            ],\n            \"default\": null\n        },\n        {\n            \"name\": \"account_balance\",\n            \"type\": [\n                \"null\",\n                {\n                    \"type\": \"bytes\",\n                    \"scale\": 2,\n                    \"precision\": 64,\n                    \"logicalType\": \"decimal\"\n                }\n            ],\n            \"default\": null\n        },\n        {\n            \"name\": \"country\",\n            \"type\": [\n                \"null\",\n                \"string\"\n            ],\n            \"default\": null\n        },\n        {\n            \"name\": \"favorite_color\",\n            \"type\": [\n                \"null\",\n                \"string\"\n            ],\n            \"default\": null\n        }\n    ]\n}"
}'

log "Creating CSV Spool Dir Source connector with auto.register.schemas=false"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                    "tasks.max": "1",
                    "connector.class": "com.github.jcustenborder.kafka.connect.spooldir.SpoolDirCsvSourceConnector",
                    "input.path": "/root/data/input",
                    "input.file.pattern": "csv-spooldir-source.csv",
                    "error.path": "/root/data/error",
                    "finished.path": "/root/data/finished",
                    "halt.on.error": "false",
                    "topic": "spooldir-csv-topic",
                    "schema.generation.enabled" : "false",
                    "key.schema": "{\n  \"name\" : \"com.example.users.UserKey\",\n  \"type\" : \"STRUCT\",\n  \"isOptional\" : false,\n  \"fieldSchemas\" : {\n    \"id\" : {\n      \"type\" : \"INT64\",\n      \"isOptional\" : false\n    }\n  }\n}",
                    "value.schema": "{\n  \"name\" : \"com.example.users.User\",\n  \"type\" : \"STRUCT\",\n  \"isOptional\" : false,\n  \"fieldSchemas\" : {\n    \"id\" : {\n      \"type\" : \"INT64\",\n      \"isOptional\" : false\n    },\n    \"first_name\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"last_name\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"email\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"gender\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"ip_address\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"last_login\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"account_balance\" : {\n      \"name\" : \"org.apache.kafka.connect.data.Decimal\",\n      \"type\" : \"BYTES\",\n      \"version\" : 1,\n      \"parameters\" : {\n        \"scale\" : \"2\"\n      },\n      \"isOptional\" : true\n    },\n    \"country\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"favorite_color\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    }\n  }\n}",
                    "csv.first.row.as.header": "true",
                    "value.converter": "io.confluent.connect.avro.AvroConverter",
                    "value.converter.schema.registry.url": "http://schema-registry:8081",
                    "value.converter.connect.meta.data": "false",
                    "value.converter.auto.register.schemas" : "false"
          }}' \
     http://localhost:8083/connectors/spool-dir/config | jq .

# FIX THIS: order of fields matters ()
# Caused by: org.apache.kafka.common.errors.SerializationException: Error retrieving Avro schema: {"type":"record","name":"User","namespace":"com.example.users","fields":[{"name":"id","type":"long"},{"name":"first_name","type":["null","string"],"default":null},{"name":"last_name","type":["null","string"],"default":null},{"name":"email","type":["null","string"],"default":null},{"name":"gender","type":["null","string"],"default":null},{"name":"ip_address","type":["null","string"],"default":null},{"name":"last_login","type":["null","string"],"default":null},{"name":"account_balance","type":["null",{"type":"bytes","scale":2,"precision":64,"logicalType":"decimal"}],"default":null},{"name":"country","type":["null","string"],"default":null},{"name":"favorite_color","type":["null","string"],"default":null}]}

# FIX THIS when "schema.generation.enabled" : "true" Screenshot 2020-10-30 at 12.41.10
# Caused by: org.apache.kafka.common.errors.SerializationException: Error retrieving Avro schema: {"type":"record","name":"Value","namespace":"com.github.jcustenborder.kafka.connect.model","fields":[{"name":"id","type":["null","string"],"default":null},{"name":"first_name","type":["null","string"],"default":null},{"name":"last_name","type":["null","string"],"default":null},{"name":"email","type":["null","string"],"default":null},{"name":"gender","type":["null","string"],"default":null},{"name":"ip_address","type":["null","string"],"default":null},{"name":"last_login","type":["null","string"],"default":null},{"name":"account_balance","type":["null","string"],"default":null},{"name":"country","type":["null","string"],"default":null},{"name":"favorite_color","type":["null","string"],"default":null}]}

sleep 5

log "Verify we have received the data in spooldir-csv-topic topic"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic spooldir-csv-topic --from-beginning --max-messages 10

# Without "value.converter.connect.meta.data": "false":

# {
#   "connect.name": "com.example.users.User",
#   "fields": [
#     {
#       "name": "id",
#       "type": "long"
#     },
#     {
#       "default": null,
#       "name": "first_name",
#       "type": [
#         "null",
#         "string"
#       ]
#     },
#     {
#       "default": null,
#       "name": "last_name",
#       "type": [
#         "null",
#         "string"
#       ]
#     },
#     {
#       "default": null,
#       "name": "email",
#       "type": [
#         "null",
#         "string"
#       ]
#     },
#     {
#       "default": null,
#       "name": "gender",
#       "type": [
#         "null",
#         "string"
#       ]
#     },
#     {
#       "default": null,
#       "name": "ip_address",
#       "type": [
#         "null",
#         "string"
#       ]
#     },
#     {
#       "default": null,
#       "name": "last_login",
#       "type": [
#         "null",
#         "string"
#       ]
#     },
#     {
#       "default": null,
#       "name": "account_balance",
#       "type": [
#         "null",
#         {
#           "connect.name": "org.apache.kafka.connect.data.Decimal",
#           "connect.parameters": {
#             "scale": "2"
#           },
#           "connect.version": 1,
#           "logicalType": "decimal",
#           "precision": 64,
#           "scale": 2,
#           "type": "bytes"
#         }
#       ]
#     },
#     {
#       "default": null,
#       "name": "country",
#       "type": [
#         "null",
#         "string"
#       ]
#     },
#     {
#       "default": null,
#       "name": "favorite_color",
#       "type": [
#         "null",
#         "string"
#       ]
#     }
#   ],
#   "name": "User",
#   "namespace": "com.example.users",
#   "type": "record"
# }

# With "value.converter.connect.meta.data": "false":


# {
#   "fields": [
#     {
#       "name": "id",
#       "type": "long"
#     },
#     {
#       "default": null,
#       "name": "first_name",
#       "type": [
#         "null",
#         "string"
#       ]
#     },
#     {
#       "default": null,
#       "name": "last_name",
#       "type": [
#         "null",
#         "string"
#       ]
#     },
#     {
#       "default": null,
#       "name": "email",
#       "type": [
#         "null",
#         "string"
#       ]
#     },
#     {
#       "default": null,
#       "name": "gender",
#       "type": [
#         "null",
#         "string"
#       ]
#     },
#     {
#       "default": null,
#       "name": "ip_address",
#       "type": [
#         "null",
#         "string"
#       ]
#     },
#     {
#       "default": null,
#       "name": "last_login",
#       "type": [
#         "null",
#         "string"
#       ]
#     },
#     {
#       "default": null,
#       "name": "account_balance",
#       "type": [
#         "null",
#         {
#           "logicalType": "decimal",
#           "precision": 64,
#           "scale": 2,
#           "type": "bytes"
#         }
#       ]
#     },
#     {
#       "default": null,
#       "name": "country",
#       "type": [
#         "null",
#         "string"
#       ]
#     },
#     {
#       "default": null,
#       "name": "favorite_color",
#       "type": [
#         "null",
#         "string"
#       ]
#     }
#   ],
#   "name": "User",
#   "namespace": "com.example.users",
#   "type": "record"
# }