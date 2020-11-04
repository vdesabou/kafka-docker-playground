#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

CONFIG_FILE=~/.ccloud/config

if [ ! -f ${CONFIG_FILE} ]
then
     logerror "ERROR: ${CONFIG_FILE} is not set"
     exit 1
fi

${DIR}/../ccloud-demo/ccloud-generate-env-vars.sh ${CONFIG_FILE}

if [ -f /tmp/delta_configs/env.delta ]
then
     source /tmp/delta_configs/env.delta
else
     logerror "ERROR: /tmp/delta_configs/env.delta has not been generated"
     exit 1
fi

set +e
log "Cleanup schemas-security-plugin topic"
delete_topic schemas-security-plugin
set -e

docker-compose -f "${PWD}/docker-compose.yml" down
docker-compose -f "${PWD}/docker-compose.yml" up -d

sleep 10

docker exec schema-registry sr-acl-cli --config /etc/schema-registry/schema-registry.properties --add -s '*' -p read -o SUBJECT_READ
docker exec schema-registry sr-acl-cli --config /etc/schema-registry/schema-registry.properties --add -s '*' -p write -o SUBJECT_WRITE
docker exec schema-registry sr-acl-cli --config /etc/schema-registry/schema-registry.properties --add -s '*' -p admin -o '*'

log "Schema Registry is listening on http://localhost:8081"
log "-> user:password  |  description"
log "-> _____________"
log "-> read:read    |  Global read access (SUBJECT_READ)"
log "-> write:write  |  Global write access (SUBJECT_WRITE)"
log "-> admin:admin  |  Global admin access (All operations)"

log "Registering a subject with write user"
curl -X POST -u write:write http://localhost:8081/subjects/subject1-value/versions \
  --header 'Content-Type: application/vnd.schemaregistry.v1+json' \
  --data '{
    "schema": "{\n    \"fields\": [\n      {\n        \"name\": \"id\",\n        \"type\": \"long\"\n      },\n      {\n        \"default\": null,\n        \"name\": \"first_name\",\n        \"type\": [\n          \"null\",\n          \"string\"\n        ]\n      },\n      {\n        \"default\": null,\n        \"name\": \"last_name\",\n        \"type\": [\n          \"null\",\n          \"string\"\n        ]\n      },\n      {\n        \"default\": null,\n        \"name\": \"email\",\n        \"type\": [\n          \"null\",\n          \"string\"\n        ]\n      },\n      {\n        \"default\": null,\n        \"name\": \"gender\",\n        \"type\": [\n          \"null\",\n          \"string\"\n        ]\n      },\n      {\n        \"default\": null,\n        \"name\": \"ip_address\",\n        \"type\": [\n          \"null\",\n          \"string\"\n        ]\n      },\n      {\n        \"default\": null,\n        \"name\": \"last_login\",\n        \"type\": [\n          \"null\",\n          \"string\"\n        ]\n      },\n      {\n        \"default\": null,\n        \"name\": \"account_balance\",\n        \"type\": [\n          \"null\",\n          {\n            \"logicalType\": \"decimal\",\n            \"precision\": 64,\n            \"scale\": 2,\n            \"type\": \"bytes\"\n          }\n        ]\n      },\n      {\n        \"default\": null,\n        \"name\": \"country\",\n        \"type\": [\n          \"null\",\n          \"string\"\n        ]\n      },\n      {\n        \"default\": null,\n        \"name\": \"favorite_color\",\n        \"type\": [\n          \"null\",\n          \"string\"\n        ]\n      }\n    ],\n    \"name\": \"User\",\n    \"namespace\": \"com.example.users\",\n    \"type\": \"record\"\n  }"
}'

log "Doing an admin operation with read user - expected to fail"
set +e
curl -X GET -u read:read http://localhost:8081/subjects
set -e
log "Doing an admin operation with admin user - expected to succeed"
curl -X GET -u admin:admin http://localhost:8081/subjects
log "Getting a subject with read user - expected to succeed"
set +e
curl -X GET -u read:read http://localhost:8081/subjects/subject1-value/versions