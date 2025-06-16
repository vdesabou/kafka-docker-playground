#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.9.9"; then
    logwarn "WARN: Schema Registry plugin before 6.x requires zookeeper"
    exit 111
fi

bootstrap_ccloud_environment



set +e
log "Cleanup schemas-security-plugin topic"
playground topic delete --topic schemas-security-plugin
set -e

JAAS_CONFIG_FILE="/tmp/jaas_config.file"
if version_gt $TAG_BASE "7.9.9"; then
  export JAAS_CONFIG_FILE="/tmp/jaas_config_8_plus.file"
fi

docker compose -f "${PWD}/docker-compose.yml" down
docker compose -f "${PWD}/docker-compose.yml" up -d --quiet-pull

sleep 10

docker exec schema-registry sr-acl-cli --config /etc/schema-registry/schema-registry.properties --add -s '*' -p read -o SUBJECT_READ
docker exec schema-registry sr-acl-cli --config /etc/schema-registry/schema-registry.properties --add -s '*' -p write -o SUBJECT_WRITE

# ccloud/schema-registry-security-plugin failing with 5.5.3 #223
# GLOBAL_SUBJECTS_READ replaced by GLOBAL_READ in CP 6.1.0 and onward
operations_list="SUBJECT_READ:SUBJECT_WRITE:SUBJECT_DELETE:SUBJECT_COMPATIBILITY_READ:SUBJECT_COMPATIBILITY_WRITE:GLOBAL_COMPATIBILITY_WRITE:GLOBAL_SUBJECTS_READ"
if version_gt $TAG_BASE "6.0.99"; then
     operations_list="SUBJECT_READ:SUBJECT_WRITE:SUBJECT_DELETE:SUBJECT_COMPATIBILITY_READ:SUBJECT_COMPATIBILITY_WRITE:GLOBAL_COMPATIBILITY_WRITE:GLOBAL_READ"
fi
docker exec schema-registry sr-acl-cli --config /etc/schema-registry/schema-registry.properties --add -s '*' -p admin -o $operations_list

docker exec schema-registry sr-acl-cli --config /etc/schema-registry/schema-registry.properties --list

log "Schema Registry is listening on http://localhost:8081"
log "-> user:password  |  description"
log "-> _____________"
log "-> read:read    |  Global read access (SUBJECT_READ)"
log "-> write:write  |  Global write access (SUBJECT_WRITE)"
log "-> admin:admin  |  Global admin access (All operations, i.e $operations_list)"

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