#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if version_gt $TAG_BASE "7.9.9"; then
    logerror "This can only be run with image or version lower than 8.0.0"
    exit 111
fi

#############
playground start-environment --environment ccloud --docker-compose-override-file "${PWD}/docker-compose-connect-onprem-to-cloud.yml"


#############

log "Creating topic in Confluent Cloud (auto.create.topics.enable=false)"
set +e
playground topic delete --topic products
sleep 3
playground topic create --topic products
set -e

log "Sending messages to topic products on source OnPREM cluster"
seq -f "This is a message %g" 10 | docker exec -i broker kafka-console-producer --bootstrap-server broker:9092 --topic products

playground connector create-or-update --connector replicate-onprem-to-cloud  << EOF
{
     "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
     "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
     "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
     "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
     "src.consumer.group.id": "replicate-onprem-to-cloud",
     "src.kafka.bootstrap.servers": "broker:9092",
     "dest.kafka.ssl.endpoint.identification.algorithm":"https",
     "dest.kafka.bootstrap.servers": "\${file:/datacloud:bootstrap.servers}",
     "dest.kafka.security.protocol" : "SASL_SSL",
     "dest.kafka.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"\${file:/datacloud:sasl.username}\" password=\"\${file:/datacloud:sasl.password}\";",
     "dest.kafka.sasl.mechanism":"PLAIN",
     "dest.kafka.request.timeout.ms":"20000",
     "dest.kafka.retry.backoff.ms":"500",
     "confluent.topic.ssl.endpoint.identification.algorithm" : "https",
     "confluent.topic.sasl.mechanism" : "PLAIN",
     "confluent.topic.bootstrap.servers": "\${file:/datacloud:bootstrap.servers}",
     "confluent.topic.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"\${file:/datacloud:sasl.username}\" password=\"\${file:/datacloud:sasl.password}\";",
     "confluent.topic.security.protocol" : "SASL_SSL",
     "confluent.topic.replication.factor": "3",
     "provenance.header.enable": true,
     "topic.whitelist": "products",
     "topic.config.sync": false,
     "topic.auto.create": false
}
EOF


log "Verify we have received the data in products topic"
playground topic consume --topic products --min-expected-messages 10 --timeout 60
