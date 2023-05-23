#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Creating Couchbase cluster"
docker exec couchbase bash -c "/opt/couchbase/bin/couchbase-cli cluster-init --cluster-username Administrator --cluster-password password --services=data,index,query"
log "Install Couchbase bucket example travel-sample"
set +e
docker exec couchbase bash -c "/opt/couchbase/bin/cbdocloader -c localhost:8091 -u Administrator -p password -b travel-sample -m 100 -d /opt/couchbase/samples/travel-sample.zip"
set -e

log "Creating Couchbase Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "com.couchbase.connect.kafka.CouchbaseSourceConnector",
               "tasks.max": "2",
               "couchbase.topic": "test-travel-sample",
               "couchbase.seed.nodes": "couchbase",
               "couchbase.bootstrap.timeout": "2000ms",
               "couchbase.bucket": "travel-sample",
               "couchbase.username": "Administrator",
               "couchbase.password": "password",
               "couchbase.source.handler": "com.couchbase.connect.kafka.handler.source.DefaultSchemaSourceHandler",
               "couchbase.event.filter": "com.couchbase.connect.kafka.filter.AllPassFilter",
               "couchbase.stream.from": "SAVED_OFFSET_OR_BEGINNING",
               "couchbase.compression": "ENABLED",
               "couchbase.flow.control.buffer": "128m",
               "couchbase.persistence.polling.interval": "100ms",
               "errors.tolerance": "all",
               "errors.log.enable": "true",
               "errors.log.include.messages": "true"
          }' \
     http://localhost:8083/connectors/couchbase-source/config | jq .

sleep 10

log "Verifying topic test-travel-sample"
playground topic consume --topic test-travel-sample --min-expected-messages 2
