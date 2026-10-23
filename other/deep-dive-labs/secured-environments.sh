#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/lab-utils.bash

# lab of https://kafka-docker-playground.io/#/deep-dive-secured-environments
# it starts its own secured environments: run it once, from the plaintext CI job only
if [ "${PLAYGROUND_ENVIRONMENT:-plaintext}" != "plaintext" ]
then
    logwarn "the secured environments lab starts its own environments, skipping with ${PLAYGROUND_ENVIRONMENT}"
    exit 111
fi

# starts an environment with the FileStream connectors (its override only sets the plugin path, it works with every
# type: they all extend environment/plaintext/docker-compose.yml), 5 records in topic filestream, and filestream-sink
function lab_start_secured_environment () {
    playground start-environment --environment "$1" --docker-compose-override-file "${DIR}/docker-compose.plaintext.yml"
    playground topic produce -t filestream --nb-messages 5 --value '{"id": %g, "name": "name-%g"}'
    lab_create_filestream_sink
}

log "Step 1: the FileStream example under SASL_SSL"
lab_start_secured_environment sasl-ssl
lab_run playground state get run.environment
lab_expect_contains "sasl-ssl"
playground topic produce -t filestream --nb-messages 3 --value '{"id": %g}'
lab_run playground topic consume -t filestream --min-expected-messages 8 --timeout 60
lab_expect_exit 0
lab_expect_contains "Display content of topic filestream, it contains 8 messages"

log "Step 2: what the CLI uses under the hood"
lab_run playground container get-properties -c connect
lab_expect_contains "security.protocol=SASL_SSL"
lab_expect_contains "sasl.mechanism=PLAIN"
lab_expect_contains "listeners=https://0.0.0.0:8083"
lab_run playground connector create-or-update -c filestream-sink --dry-run << 'EOF'
{
  "tasks.max": "1",
  "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
  "topics": "filestream",
  "file": "/tmp/output.json",
  "value.converter": "io.confluent.connect.avro.AvroConverter",
  "value.converter.schema.registry.url": "http://schema-registry:8081"
}
EOF
lab_expect_exit 0
lab_expect_contains "✨ Following config was added to handle environment sasl-ssl:"
lab_expect_contains '"value.converter.schema.registry.url": "https://schema-registry:8081"'
lab_expect_contains "value.converter.schema.registry.ssl.truststore.location"
lab_run timeout 60 ${DIR}/../../scripts/cli/playground container exec -c connect --command "kafka-topics --bootstrap-server broker:9092 --list --command-config /dev/null"
if [ "$LAB_EXIT" == "0" ]
then
    logerror "❌ a client without the SASL_SSL config should not be able to list the topics"
    exit 1
fi
log "✅ a client without the SASL_SSL config fails (exit $LAB_EXIT)"

log "Step 3: the same example under RBAC, then an authorization error"
lab_start_secured_environment rbac-sasl-plain
lab_run playground connector status -c filestream-sink
lab_expect_contains "filestream-sink"
lab_expect_contains "RUNNING"
lab_run playground rbac role-binding list --principal User:connectorSA
lab_expect_exit 0
lab_expect_contains "ResourceOwner"
lab_run playground rbac role-binding delete --principal User:connectorSA --role ResourceOwner --resource 'Topic:*'
lab_expect_exit 0
playground topic produce -t filestream --nb-messages 1 --value '{"id": "after-delete"}'
playground connector restart -c filestream-sink
lab_run playground connector wait -c filestream-sink --state FAILED --max-wait 180
lab_expect_exit 0
lab_run playground connector status -c filestream-sink
lab_expect_contains "FAILED"
lab_expect_contains "AuthorizationException"
lab_run playground rbac role-binding create --principal User:connectorSA --role ResourceOwner --resource 'Topic:*'
lab_expect_exit 0
playground connector restart -c filestream-sink
lab_run playground connector wait -c filestream-sink --max-wait 180
lab_expect_exit 0

log "✅ all the outputs of the page are as expected"
