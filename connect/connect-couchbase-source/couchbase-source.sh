#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Creating Couchbase cluster"
docker exec couchbase bash -c "/opt/couchbase/bin/couchbase-cli cluster-init --cluster-username Administrator --cluster-password password --services=data,index,query"
log "Install Couchbase bucket example travel-sample"
curl -X POST -u Administrator:password http://localhost:8091/sampleBuckets/install -d '["travel-sample"]'

log "Creating Couchbase Source connector"
playground connector create-or-update --connector couchbase-source  << EOF
{
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
}
EOF

sleep 10

log "Verifying topic test-travel-sample"
playground topic consume --topic test-travel-sample --min-expected-messages 2 --max-messages 3  --timeout 60
