#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.with-transforms.yml"

log "Creating Couchbase cluster"
docker exec couchbase bash -c "/opt/couchbase/bin/couchbase-cli cluster-init --cluster-username Administrator --cluster-password password --services=data,index,query"
log "Install Couchbase bucket example travel-sample"
set +e
docker exec couchbase bash -c "/opt/couchbase/bin/cbdocloader -c localhost:8091 -u Administrator -p password -b travel-sample -m 100 -d /opt/couchbase/samples/travel-sample.zip"
set -e

log "Creating Couchbase Source connector with transforms"
playground connector create-or-update --connector couchbase-source << EOF
{
               "connector.class": "com.couchbase.connect.kafka.CouchbaseSourceConnector",
               "tasks.max": "2",
               "couchbase.topic": "default-topic",
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
               "transforms": "KeyExample,dropSufffix",
               "transforms.KeyExample.type": "io.confluent.connect.transforms.ExtractTopic\$Key",
               "transforms.KeyExample.skip.missing.or.null": "true",
               "transforms.dropSufffix.type": "org.apache.kafka.connect.transforms.RegexRouter",
               "transforms.dropSufffix.regex": "(.*)_.*",
               "transforms.dropSufffix.replacement": "\$1",
               "errors.tolerance": "all",
               "errors.log.enable": "true",
               "errors.log.include.messages": "true"
          }
EOF

sleep 10

log "Verifying topic airline"
playground topic consume --topic airline --min-expected-messages 1 --timeout 60
log "Verifying topic airport"
playground topic consume --topic airport --min-expected-messages 1 --timeout 60
log "Verifying topic hotel"
playground topic consume --topic hotel --min-expected-messages 1 --timeout 60
log "Verifying topic landmark"
playground topic consume --topic landmark --min-expected-messages 1 --timeout 60
log "Verifying topic route"
playground topic consume --topic route --min-expected-messages 1 --timeout 60
