#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "10.5.99"
then
     logwarn "minimal supported connector version is 10.6.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/8.0/connect/supported-connector-version.html#"
     exit 111
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.repro-000016-s3-sink-duplicates-after-worker-crash.yml"

log "Creating bucket mybucket in MinIO"
playground container restart --container create-buckets

# the customer's config: one folder per 10 seconds of processing time (their real config: one per hour)
log "Creating S3 sink connector minio-sink"
playground connector create-or-update --connector minio-sink << EOF
{
     "connector.class": "io.confluent.connect.s3.S3SinkConnector",
     "tasks.max": "1",
     "topics": "orders",
     "s3.bucket.name": "mybucket",
     "s3.part.size": 5242880,
     "store.url": "http://minio:9000",
     "flush.size": "3",
     "storage.class": "io.confluent.connect.s3.storage.S3Storage",
     "format.class": "io.confluent.connect.s3.format.avro.AvroFormat",
     "partitioner.class": "io.confluent.connect.storage.partitioner.TimeBasedPartitioner",
     "partition.duration.ms": "10000",
     "path.format": "'date'=YYYY-MM-dd/'time'=HH-mm-ss",
     "locale": "en-US",
     "timezone": "UTC",
     "timestamp.extractor": "Wallclock",
     "schema.compatibility": "NONE"
}
EOF

# the 9 orders in the same 10 seconds folder: send them in the first half of a 10 seconds window
while [ $(( $(date +%s) % 10 )) -gt 4 ]
do
    sleep 1
done
log "Sending 9 orders to topic orders"
playground topic produce -t orders --nb-messages 9 --forced-value '{"id": %g, "product": "product%g", "quantity": %g}' << 'EOF'
{
  "type": "record",
  "name": "order",
  "fields": [
    {"name": "id", "type": "int"},
    {"name": "product", "type": "string"},
    {"name": "quantity", "type": "int"}
  ]
}
EOF

playground storage wait-for-objects --connector minio-sink --min-expected-objects 3

# the issue: the worker dies (an OOM kill, a node lost...) a few seconds after writing the files, and is restarted
log "💥 The connect worker crashes, and is restarted"
playground container kill --container connect
playground container restart --container connect
playground container wait-for-connect-rest-api-ready
# the task joins its consumer group again once the member of the killed worker has timed out (session.timeout.ms, 45 s)
playground storage wait-for-objects --connector minio-sink --min-expected-objects 6 --max-wait 180

log "The connector is RUNNING..."
playground connector status --connector minio-sink
log "...the topic has 9 orders, the bucket has:"
playground storage ls --connector minio-sink
