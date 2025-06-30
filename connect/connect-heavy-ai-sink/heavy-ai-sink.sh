#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if version_gt $TAG_BASE "7.9.99" && ! version_gt $CONNECTOR_TAG "0.0.99"
then
     logwarn "minimal supported connector version is 1.0.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.0.html#supported-connector-versions-in-cp-8-0"
     exit 111
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"


log "Sending messages to topic orders"
playground topic produce -t orders --nb-messages 3 << 'EOF'
{
  "fields": [
    {
      "name": "id",
      "type": "int"
    },
    {
      "name": "product",
      "type": "string"
    },
    {
      "name": "quantity",
      "type": "int"
    },
    {
      "name": "price",
      "type": "float"
    }
  ],
  "name": "myrecord",
  "type": "record"
}
EOF


log "Creating HEAVY-AI (Formerly OmniSci) sink connector"
playground connector create-or-update --connector omnisci-sink  << EOF
{
     "connector.class": "io.confluent.connect.omnisci.OmnisciSinkConnector",
     "tasks.max" : "1",
     "topics": "orders",
     "connection.database": "omnisci",
     "connection.port": "6274",
     "connection.host": "omnisci",
     "connection.user": "admin",
     "connection.password": "HyperInteractive",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor": "1",
     "auto.create": "true"
}
EOF

sleep 10

log "Verify data is in OmniSci"
docker exec -i omnisci /omnisci/bin/omnisql -p HyperInteractive > /tmp/result.log  2>&1 <<-EOF
select * from orders;
EOF
cat /tmp/result.log
grep "product" /tmp/result.log
