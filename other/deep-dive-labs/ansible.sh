#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/lab-utils.bash

# lab of https://kafka-docker-playground.io/#/deep-dive-ansible
# it starts its own ansible environments: run it once, from the plaintext CI job only
if [ "${PLAYGROUND_ENVIRONMENT:-plaintext}" != "plaintext" ]
then
    logwarn "the cp-ansible lab starts its own environments, skipping with ${PLAYGROUND_ENVIRONMENT}"
    exit 111
fi
# the hosts of the lab only: the optional hosts of the --enable-* flags exported in the shell are not part of the page
unset ENABLE_CONTROL_CENTER ENABLE_KSQLDB ENABLE_RESTPROXY ENABLE_KAFKA_NODES ENABLE_CONNECT_NODES ENABLE_CONTROLLER_NODES

log "Step 1: the FileStream example on hosts deployed by cp-ansible"
lab_run playground start-environment --environment ansible --docker-compose-override-file "${DIR}/docker-compose.plaintext.yml"
lab_expect_exit 0
lab_expect_contains "🖥️ hosts: controller broker schema-registry connect"
lab_expect_contains "🧩 translating the example's docker compose override docker-compose.plaintext.yml into inventory variables"
lab_expect_contains "connect: plugin.path=/opt/confluent/confluent-${TAG_BASE:-$TAG}/share/filestream-connectors (kafka_connect_custom_properties)"
lab_expect_contains "▶️ Running the playbook (a few minutes): docker exec ansible-controller ansible-playbook -i /inventory/hosts.yml confluent.platform.all"
lab_expect_contains "PLAY RECAP"
lab_expect_not_contains "failed=1"
lab_expect_contains "🚦 containers have started!"
lab_run playground state get run.environment
lab_expect_equals "$LAB_OUTPUT" "ansible" "environment"
playground topic produce -t filestream --nb-messages 5 --value '{"id": %g, "name": "name-%g"}'
lab_create_filestream_sink
lab_run playground container exec -c connect --command "cat /tmp/output.json"
lab_expect_exit 0
lab_expect_contains "{name=name-1, id=1}"
lab_run playground container get-properties -c connect
lab_expect_contains "plugin.path=/opt/confluent/confluent-${TAG_BASE:-$TAG}/share/filestream-connectors"
lab_expect_contains "key.converter=org.apache.kafka.connect.storage.StringConverter"

log "Step 2: the playground commands on cp-ansible hosts"
lab_run playground container logs -c connect --wait-for-log "Finished starting connectors and tasks" --max-wait 30
lab_expect_exit 0
lab_expect_contains "The log is there !"
lab_run playground container logs -c connect --errors
lab_expect_exit 0
lab_expect_contains "no ERROR/FATAL record found in"
lab_run playground broker stop --broker 1
lab_expect_exit 0
lab_expect_contains "🛑 Stopping broker 1 (systemctl stop confluent-server.service on host broker)"
lab_run playground broker start --broker 1
lab_expect_exit 0
lab_expect_contains "▶️ Starting broker 1 (systemctl start confluent-server.service on host broker)"
lab_expect_contains "✅ cluster is healthy, broker 1 started in"
lab_run playground debug thread-dump -c connect
lab_expect_exit 0
lab_expect_contains "👻 thread dump is available at"
lab_run playground container recreate
lab_expect_exit 1
lab_expect_contains "❌ container recreate is not supported in ansible mode: a recreated host loses what the playbook installed, run the playbook again instead"
lab_run playground container set-environment-variables -c connect --env "KAFKA_OPTS: -verbose:class"
lab_expect_exit 1
lab_expect_contains "this command is not available with ansible: the containers are hosts where cp-ansible installed Confluent Platform"

log "Step 3: change the inventory, run the playbook again"
yq -i '.all.children.kafka_connect.vars.kafka_connect_custom_properties["consumer.max.poll.records"] = 100' "${DIR}/../../environment/ansible/inventory/hosts.yml"
lab_run docker exec -e ANSIBLE_FORCE_COLOR=0 ansible-controller ansible-playbook -i /inventory/hosts.yml confluent.platform.all --limit connect
lab_expect_exit 0
lab_expect_contains "connect                    : ok="
lab_expect_contains "failed=0"
playground container wait-for-connect-rest-api-ready --max-wait 120
lab_run playground container get-properties -c connect
lab_expect_contains "consumer.max.poll.records=100"
lab_run playground connector status -c filestream-sink
lab_expect_contains "filestream-sink ✅ RUNNING 0:🟢 RUNNING"

log "Step 4: the inventory of the customer, with SASL_SSL"
lab_run playground start-environment --environment ansible --ansible-inventory "${DIR}/ansible-customer-hosts.yml"
lab_expect_exit 0
lab_expect_contains "📋 reading the customer inventory"
lab_expect_contains "✏️ kb1.prod.example.com -> broker: connection variables removed (ansible_host)"
lab_expect_contains "✏️ all: connection variables removed (ansible_become, ansible_connection, ansible_user)"
lab_expect_contains "✏️ all: confluent_common_repository_baseurl removed (package repository or file of the customer, the public ones are used)"
lab_expect_contains "✏️ host names in the variables: kb1.prod.example.com -> broker"
lab_expect_contains "⚠️ all: ssl_custom_certs set to false, the certificates are generated by cp-ansible"
lab_expect_contains "⚠️ 1 vault value(s) replaced by 'playground-vault-value' (no vault password): all.vars.confluent_common_repository_baseurl"
lab_expect_contains "🔐 security of the cluster: SASL_SSL"
lab_run playground container get-properties -c connect
lab_expect_contains "producer.bootstrap.servers=broker:9092"
lab_run playground container get-properties -c broker
lab_expect_contains "num.partitions=6"
lab_run playground topic produce -t customer-orders --nb-messages 3 << 'EOF'
{"type": "record", "name": "order", "fields": [{"name": "id", "type": "int"}]}
EOF
lab_expect_exit 0
lab_run playground topic consume -t customer-orders --min-expected-messages 3 --timeout 60
lab_expect_exit 0
lab_expect_contains "|ValueSchemaId:1"
lab_run playground connector create-or-update -c lab-rewrites --dry-run << 'EOF'
{
  "tasks.max": "1",
  "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
  "topics": "customer-orders",
  "file": "/tmp/output.json",
  "confluent.topic.bootstrap.servers": "broker:9092",
  "value.converter": "io.confluent.connect.avro.AvroConverter",
  "value.converter.schema.registry.url": "http://schema-registry:8081"
}
EOF
lab_expect_exit 0
lab_expect_contains '"confluent.topic.security.protocol": "SASL_SSL"'
lab_expect_contains '"value.converter.schema.registry.url": "https://schema-registry:8081"'
lab_expect_contains "🌵 request: PUT https://connect:8083/connectors/lab-rewrites/config"

log "✅ cp-ansible lab done"
