#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

#############
playground start-environment --environment ccloud --docker-compose-override-file "${PWD}/docker-compose.yml"

if [ -f ${DIR}/../../.ccloud/env.delta ]
then
     source ${DIR}/../../.ccloud/env.delta
else
     logerror "ERROR: ${DIR}/../../.ccloud/env.delta has not been generated"
     exit 1
fi
#############

if ! version_gt $TAG_BASE "5.9.9"; then
     # note: for 6.x CONNECT_TOPIC_CREATION_ENABLE=true
     log "Creating topic in Confluent Cloud (auto.create.topics.enable=false)"
     set +e
     playground topic create --topic test-travel-sample
     set -e
fi

log "Creating Couchbase cluster"
docker exec couchbase bash -c "/opt/couchbase/bin/couchbase-cli cluster-init --cluster-username Administrator --cluster-password password --services=data,index,query"
log "Install Couchbase bucket example travel-sample"
set +e
docker exec couchbase bash -c "/opt/couchbase/bin/cbdocloader -c localhost:8091 -u Administrator -p password -b travel-sample -m 100 -d /opt/couchbase/samples/travel-sample.zip"
set -e

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
     "topic.creation.default.replication.factor": "-1",
     "topic.creation.default.partitions": "-1"
}
EOF

sleep 10

log "Verifying topic test-travel-sample"
playground topic consume --topic test-travel-sample --min-expected-messages 2 --timeout 60

