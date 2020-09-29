#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.4.0"; then
    logwarn "WARN: Audit logs is only available from Confluent Platform 5.4.1"
    exit 0
fi

verify_installed "docker-compose"

if [ -z "$TRAVIS" ]
then
     # not running with TRAVIS
     verify_installed "ccloud"
     check_ccloud_version 1.0 || exit 1
     verify_ccloud_login  "ccloud kafka cluster list"
     verify_ccloud_details
     check_if_continue
fi

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

# generate sr.json config
sed -e "s|:SCHEMA_REGISTRY_URL:|$SCHEMA_REGISTRY_URL|g" \
    ${DIR}/sr-template.json > ${DIR}/sr.json

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.yml"

# results a re inconsistent depending on RHEL or DEBIAN
if [[ "$TAG" == *ubi8 ]]  || version_gt $TAG_BASE "5.9.0" #starting from 6.0, all images are ubi8
then
     # RHEL
     docker exec -i --privileged --user root -t webserver  bash -c "yum update && yum install -y nc"
     docker exec -d -t webserver bash -c "bash /tmp/httpd_rhel.sh 1500 /tmp/json/sr.json"
else
     # debian
     docker exec -i --privileged --user root -t webserver  bash -c "apt-get update && apt-get install net-tools"
     docker exec -d -t webserver bash -c "bash /tmp/httpd_debian.sh 1500 /tmp/json/sr.json"
fi

sleep 5

log "Executing curl http://localhost:1500/v1/metadata/schemaRegistryUrls"
curl http://localhost:1500/v1/metadata/schemaRegistryUrls


log "Creating topic my_avro_topic in Confluent Cloud (auto.create.topics.enable=false)"
set +e
create_topic my_avro_topic
set -e

log "Sending messages to topic my_avro_topic"
docker exec -i -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SASL_JAAS_CONFIG="$SASL_JAAS_CONFIG" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" connect kafka-avro-console-producer --broker-list $BOOTSTRAP_SERVERS --producer-property ssl.endpoint.identification.algorithm=https --producer-property sasl.mechanism=PLAIN --producer-property security.protocol=SASL_SSL --producer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --topic my_avro_topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"u_name","type":"string"},{"name":"u_price", "type": "float"}, {"name":"u_quantity", "type": "int"}]}' << EOF
{"u_name": "scissors", "u_price": 2.75, "u_quantity": 3}
{"u_name": "tape", "u_price": 0.99, "u_quantity": 10}
{"u_name": "notebooks", "u_price": 1.99, "u_quantity": 5}
EOF
