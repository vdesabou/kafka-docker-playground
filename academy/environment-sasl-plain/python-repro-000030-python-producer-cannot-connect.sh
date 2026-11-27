#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# this exercise is about a non-Java client (Python, librdkafka) on SASL/PLAIN listeners: it needs the sasl-plain
# environment. Only the client-python container and what it depends on
playground start-environment --environment sasl-plain --docker-compose-override-file "${PWD}/docker-compose.sasl-plain.repro-000030-python-producer-cannot-connect.yml" --service client-python

playground topic create --topic orders --nb-partitions 3

log "The orders service (Python) sends 5 orders, with the properties of the test environment"
set +e
playground container exec -c client-python --command "python client.py produce orders /tmp/conf/client.properties 5"
set -e

playground topic get-offsets --topic orders || true
