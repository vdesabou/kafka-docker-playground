#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

#############
playground start-environment --environment ccloud --docker-compose-override-file "${PWD}/docker-compose-connect-onprem-to-cloud.yml"

if [ -f /tmp/delta_configs/env.delta ]
then
     source /tmp/delta_configs/env.delta
else
     logerror "ERROR: /tmp/delta_configs/env.delta has not been generated"
     exit 1
fi
#############

set +e
playground topic delete --topic _confluent-command
set -e

log "Creating topic in Confluent Cloud (auto.create.topics.enable=false)"
set +e
playground topic delete --topic products
sleep 3
playground topic create --topic products
set -e

log "Sending messages to topic products on source OnPREM cluster"
playground topic produce -t products --nb-messages 10 << 'EOF'
%g
EOF

playground connector create-or-update --connector replicate-onprem-to-cloud << EOF
{
     "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
     "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
     "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
     "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
     "src.consumer.group.id": "replicate-onprem-to-cloud",
     "src.kafka.bootstrap.servers": "broker:9092",
     "dest.kafka.ssl.endpoint.identification.algorithm":"https",
     "dest.kafka.bootstrap.servers": "\${file:/data:bootstrap.servers}",
     "dest.kafka.security.protocol" : "SASL_SSL",
     "dest.kafka.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"\${file:/data:sasl.username}\" password=\"\${file:/data:sasl.password}\";",
     "dest.kafka.sasl.mechanism":"PLAIN",
     "dest.kafka.request.timeout.ms":"20000",
     "dest.kafka.retry.backoff.ms":"500",
     "provenance.header.enable": true,
     "topic.whitelist": "products",
     "topic.config.sync": false,
     "topic.auto.create": false
}
EOF


log "Verify we have received the data in products topic"
playground topic consume --topic products --min-expected-messages 10 --timeout 60