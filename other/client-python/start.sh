#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
# only the client-python container and what it depends on (broker, schema-registry): no connect, nothing to wait for
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml" --service client-python

NB_MESSAGES=10

log "Creating topics python-string and python-avro"
playground topic create --topic python-string --nb-partitions 3
playground topic create --topic python-avro --nb-partitions 3

log "Producing $NB_MESSAGES string records with the Python producer"
playground container exec -c client-python --command "python client.py produce python-string /tmp/client.properties $NB_MESSAGES"

log "Consuming them with the Python consumer, it fails if fewer than $NB_MESSAGES records arrive within 60 seconds"
playground container exec -c client-python --command "python client.py consume python-string /tmp/client.properties $NB_MESSAGES"

log "Producing $NB_MESSAGES Avro records with the Python producer (AvroSerializer, schema registered under subject python-avro-value)"
playground container exec -c client-python --command "python client.py produce-avro python-avro /tmp/client.properties $NB_MESSAGES"

log "Consuming them with the Python consumer (AvroDeserializer)"
playground container exec -c client-python --command "python client.py consume-avro python-avro /tmp/client.properties $NB_MESSAGES"

log "Checking the schema registered by the Python AvroSerializer under subject python-avro-value"
playground schema get --subject python-avro-value

log "Checking the consumer groups of the Python consumer committed the offsets"
playground consumer-group describe --group python-string-group
playground consumer-group describe --group python-avro-group
