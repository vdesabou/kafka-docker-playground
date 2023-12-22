#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

playground start-environment --environment plaintext --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Sending messages to topic test-topic"
playground topic produce -t test-topic --nb-messages 10 << 'EOF'
%g
EOF

log "Creating Replicator connector"
playground connector create-or-update --connector duplicate-topic << EOF
{
         "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
               "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
               "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
               "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
               "src.consumer.group.id": "duplicate-topic",
               "confluent.topic.replication.factor": 1,
               "provenance.header.enable": true,
               "topic.whitelist": "test-topic",
               "topic.rename.format": "test-topic-duplicate",
               "dest.kafka.bootstrap.servers": "broker:9092",
               "src.kafka.bootstrap.servers": "broker:9092"
           }
EOF

sleep 10

log "Verify we have received the data in test-topic-duplicate topic"
playground topic consume --topic test-topic-duplicate --min-expected-messages 10 --timeout 60