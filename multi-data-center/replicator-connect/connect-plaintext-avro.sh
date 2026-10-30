#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

playground start-environment --environment mdc-plaintext --docker-compose-override-file "${PWD}/docker-compose.mdc-plaintext.yml"

log "Sending products in Europe cluster"
playground topic produce --cluster europe --topic products_EUROPE --nb-messages 3 << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {"name": "name", "type": "string"},
    {"name": "price", "type": "float"},
    {"name": "quantity", "type": "int"}
  ]
}
EOF

log "Replicate topic products_EUROPE from Europe to US using AvroConverter"
playground connector create-or-update --cluster us --connector replicate-europe-to-us << EOF
{
     "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
     "value.converter": "io.confluent.connect.avro.AvroConverter",
     "value.converter.schema.registry.url": "http://schema-registry-us:8081",
     "value.converter.connect.meta.data": "false",
     "src.consumer.group.id": "replicate-europe-to-us",
     "src.kafka.bootstrap.servers": "broker-europe:9092",
     "src.value.converter": "io.confluent.connect.avro.AvroConverter",
     "src.value.converter.schema.registry.url": "http://schema-registry-europe:8081",
     "dest.kafka.bootstrap.servers": "broker-us:9092",
     "confluent.topic.replication.factor": 1,
     "provenance.header.enable": true,
     "topic.whitelist": "products_EUROPE"
}
EOF

log "Verify we have received the data in topic products_EUROPE in US"
playground topic wait-for-records --cluster us --topic products_EUROPE --min-expected-messages 3 --max-wait 120
playground topic consume --cluster us --topic products_EUROPE --min-expected-messages 3 --timeout 60

log "The schema was registered in the US schema registry"
playground schema get --cluster us --subject products_EUROPE-value
