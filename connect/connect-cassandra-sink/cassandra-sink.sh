#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "2.0.10"
then
     logwarn "minimal supported connector version is 2.0.11 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.1.html#supported-connector-versions-in-cp-8-1"
     exit 111
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"


log "Getting value for cassandra.local.datacenter (2.0.x only), see https://docs.confluent.io/kafka-connect-cassandra/current/index.html#upgrading-to-version-2-0-x"
DATACENTER=$(docker exec cassandra cqlsh -e 'SELECT data_center FROM system.local;' | head -4 | tail -1 | tr -d ' ')

log "Sending messages to topic topic1"
playground topic produce -t topic1 --nb-messages 10 --forced-value '{"f1": "value1"}' << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "f1",
      "type": "string"
    }
  ]
}
EOF

log "Creating Cassandra Sink connector"
playground connector create-or-update --connector cassandra-sink  << EOF
{
     "connector.class": "io.confluent.connect.cassandra.CassandraSinkConnector",
     "tasks.max": "1",
     "topics" : "topic1",
     "cassandra.contact.points" : "cassandra",
     "cassandra.keyspace" : "test",
     "cassandra.consistency.level": "ONE",
     "cassandra.local.datacenter":"$DATACENTER",
     "confluent.license": "",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor": "1",
     "transforms": "createKey",
     "transforms.createKey.fields": "f1",
     "transforms.createKey.type": "org.apache.kafka.connect.transforms.ValueToKey"
}
EOF

sleep 15

log "Verify messages are in cassandra table test.topic1"
docker exec cassandra cqlsh -e 'select * from test.topic1;' > /tmp/result.log  2>&1
cat /tmp/result.log
grep "value1" /tmp/result.log