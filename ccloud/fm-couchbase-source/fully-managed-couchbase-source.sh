#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh


COUCHBASE_USERNAME=${COUCHBASE_USERNAME:-$1}
COUCHBASE_PASSWORD=${COUCHBASE_PASSWORD:-$2}
COUCHBASE_HOSTNAME=${COUCHBASE_HOSTNAME:-$3}

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

if [ -z "$COUCHBASE_HOSTNAME" ]
then
     logerror "COUCHBASE_HOSTNAME is not set. Export it as environment variable or pass it as argument"
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
  "couchbase.seed.nodes": "couchbases://$COUCHBASE_HOSTNAME",
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

# CreateTime:2025-06-26 14:12:27.540|Partition:0|Offset:99|Headers:NO_HEADERS|Key:"route_14541"|Value:{"event":"mutation","partition":1,"key":"route_14541","cas":1750939773140467712,"bySeqno":48,"revSeqno":1,"expiration":0,"flags":0,"lockTime":0,"content":"eyJpZCI6MTQ1NDEsInR5cGUiOiJyb3V0ZSIsImFpcmxpbmUiOiJCQSIsImFpcmxpbmVpZCI6ImFpcmxpbmVfMTM1NSIsInNvdXJjZWFpcnBvcnQiOiJIQUoiLCJkZXN0aW5hdGlvbmFpcnBvcnQiOiJMSFIiLCJzdG9wcyI6MCwiZXF1aXBtZW50IjoiMzE5Iiwic2NoZWR1bGUiOlt7ImRheSI6MCwidXRjIjoiMDI6MTI6MDAiLCJmbGlnaHQiOiJCQTE0MyJ9LHsiZGF5IjowLCJ1dGMiOiIwMDowMzowMCIsImZsaWdodCI6IkJBNTIyIn0seyJkYXkiOjAsInV0YyI6IjE1OjA3OjAwIiwiZmxpZ2h0IjoiQkE1NjcifSx7ImRheSI6MSwidXRjIjoiMjE6MDU6MDAiLCJmbGlnaHQiOiJCQTM4NSJ9LHsiZGF5IjoyLCJ1dGMiOiIxOTozNjowMCIsImZsaWdodCI6IkJBNzc2In0seyJkYXkiOjIsInV0YyI6IjEzOjMwOjAwIiwiZmxpZ2h0IjoiQkE5NjMifSx7ImRheSI6MywidXRjIjoiMDA6MTM6MDAiLCJmbGlnaHQiOiJCQTExMyJ9LHsiZGF5IjozLCJ1dGMiOiIxMTo1NjowMCIsImZsaWdodCI6IkJBMjc0In0seyJkYXkiOjMsInV0YyI6IjIxOjU2OjAwIiwiZmxpZ2h0IjoiQkEzNjYifSx7ImRheSI6NCwidXRjIjoiMDY6MjY6MDAiLCJmbGlnaHQiOiJCQTY2NiJ9LHsiZGF5Ijo0LCJ1dGMiOiIyMzozMjowMCIsImZsaWdodCI6IkJBMDgwIn0seyJkYXkiOjQsInV0YyI6IjAxOjMwOjAwIiwiZmxpZ2h0IjoiQkE2MjcifSx7ImRheSI6NSwidXRjIjoiMTA6MDA6MDAiLCJmbGlnaHQiOiJCQTYzMiJ9LHsiZGF5Ijo2LCJ1dGMiOiIxNDoyODowMCIsImZsaWdodCI6IkJBOTU4In0seyJkYXkiOjYsInV0YyI6IjE0OjUxOjAwIiwiZmxpZ2h0IjoiQkE2NzQifSx7ImRheSI6NiwidXRjIjoiMDg6MDE6MDAiLCJmbGlnaHQiOiJCQTM4MCJ9LHsiZGF5Ijo2LCJ1dGMiOiIxNTozMjowMCIsImZsaWdodCI6IkJBMjM1In1dLCJkaXN0YW5jZSI6NzAzLjAzMjIyNDU4ODAzODV9","bucket":"travel-sample","vBucketUuid":269619920705797}|ValueSchemaId:


log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name