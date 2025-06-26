#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh


COUCHBASE_USERNAME=${COUCHBASE_USERNAME:-$1}
COUCHBASE_PASSWORD=${COUCHBASE_PASSWORD:-$2}
COUCHBASE_CONNECTION_URL=${COUCHBASE_CONNECTION_URL:-$3}

if [ -z "$COUCHBASE_USERNAME" ]
then
     logerror "COUCHBASE_USERNAME is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$COUCHBASE_PASSWORD" ]
then
     logerror "COUCHBASE_PASSWORD is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$COUCHBASE_CONNECTION_URL" ]
then
     logerror "COUCHBASE_CONNECTION_URL is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

bootstrap_ccloud_environment

set +e
playground topic delete --topic test-travel-sample
sleep 3
playground topic create --topic test-travel-sample --nb-partitions 1
set -e

connector_name="CouchbaseSource_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
  "connector.class": "CouchbaseSource",
  "name": "$connector_name",
  "kafka.auth.mode": "KAFKA_API_KEY",
  "kafka.api.key": "$CLOUD_KEY",
  "kafka.api.secret": "$CLOUD_SECRET",
  "output.data.format": "JSON",
  "couchbase.seed.nodes": "$COUCHBASE_CONNECTION_URL",
  "couchbase.bucket": "travel-sample",
  "couchbase.topic": "test-travel-sample",
  "couchbase.username": "$COUCHBASE_USERNAME",
  "couchbase.password": "$COUCHBASE_PASSWORD",
  "couchbase.source.handler": "com.couchbase.connect.kafka.handler.source.DefaultSchemaSourceHandler",
  "couchbase.stream.from": "SAVED_OFFSET_OR_BEGINNING",
  "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

log "Verifying topic test-travel-sample"
playground topic consume --topic test-travel-sample --min-expected-messages 2 --timeout 60

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name