#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

playground start-environment --environment mdc-sasl-plain --docker-compose-override-file "${PWD}/docker-compose.mdc-sasl-plain.yml"

log "Sending sales in Europe cluster"
playground topic produce --cluster europe --topic sales_EUROPE --nb-messages 10 --value "european_sale_%g ${RANDOM}"

log "Sending sales in US cluster"
playground topic produce --cluster us --topic sales_US --nb-messages 10 --value "us_sale_%g ${RANDOM}"

log "Consolidating all sales in the US"

playground connector create-or-update --cluster us --connector replicate-europe-to-us << EOF
{
     "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
     "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
     "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
     "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
     "src.consumer.group.id": "replicate-europe-to-us",
     "src.kafka.bootstrap.servers": "broker-europe:9092",
     "src.kafka.security.protocol" : "SASL_PLAINTEXT",
     "src.kafka.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required  username=\"client\" password=\"client-secret\";",
     "src.kafka.sasl.mechanism": "PLAIN",
     "dest.kafka.bootstrap.servers": "broker-us:9092",
     "dest.kafka.security.protocol" : "SASL_PLAINTEXT",
     "dest.kafka.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required  username=\"client\" password=\"client-secret\";",
     "dest.kafka.sasl.mechanism": "PLAIN",
     "confluent.topic.replication.factor": 1,
     "confluent.topic.security.protocol" : "SASL_PLAINTEXT",
     "confluent.topic.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required  username=\"client\" password=\"client-secret\";",
     "confluent.topic.sasl.mechanism": "PLAIN",
     "provenance.header.enable": true,
     "topic.whitelist": "sales_EUROPE"
}
EOF


log "Consolidating all sales in Europe"

playground connector create-or-update --cluster europe --connector replicate-us-to-europe << EOF
{
     "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
     "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
     "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
     "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
     "src.consumer.group.id": "replicate-us-to-europe",
     "src.kafka.bootstrap.servers": "broker-us:9092",
     "src.kafka.security.protocol" : "SASL_PLAINTEXT",
     "src.kafka.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required  username=\"client\" password=\"client-secret\";",
     "src.kafka.sasl.mechanism": "PLAIN",
     "dest.kafka.bootstrap.servers": "broker-europe:9092",
     "dest.kafka.security.protocol" : "SASL_PLAINTEXT",
     "dest.kafka.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required  username=\"client\" password=\"client-secret\";",
     "dest.kafka.sasl.mechanism": "PLAIN",
     "confluent.topic.replication.factor": 1,
     "confluent.topic.security.protocol" : "SASL_PLAINTEXT",
     "confluent.topic.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required  username=\"client\" password=\"client-secret\";",
     "confluent.topic.sasl.mechanism": "PLAIN",
     "provenance.header.enable": true,
     "topic.whitelist": "sales_US"
}
EOF

log "Verify we have received the US sales in EUROPE"
playground topic wait-for-records --cluster europe --topic sales_US --min-expected-messages 10 --max-wait 180
playground topic consume --cluster europe --topic sales_US --min-expected-messages 10 --timeout 60

log "Verify we have received the European sales in the US"
playground topic wait-for-records --cluster us --topic sales_EUROPE --min-expected-messages 10 --max-wait 180
playground topic consume --cluster us --topic sales_EUROPE --min-expected-messages 10 --timeout 60
