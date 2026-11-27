#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# brokers 1, 2 and 3 (same as playground run --enable-multiple-brokers)
export ENABLE_KAFKA_NODES=true

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.repro-000039-sink-stuck-on-some-partitions-stale-dns.yml"

playground topic create --topic orders --nb-partitions 6 --replication-factor 3

log "Creating the FileStream sink connector"
playground connector create-or-update --connector filestream-sink << EOF2
{
     "tasks.max": "1",
     "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
     "topics": "orders",
     "file": "/tmp/output.json",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.storage.StringConverter"
}
EOF2

log "Monday: 60 orders"
playground topic produce -t orders --nb-messages 60 --key 'monday-%g' --forced-value '{"order": %g, "day": "monday"}'
sleep 10

log "🌙 Maintenance window: the connector is paused, the orders of Tuesday morning arrive"
playground connector pause --connector filestream-sink
playground topic produce -t orders --nb-messages 60 --key 'tuesday-%g' --forced-value '{"order": %g, "day": "tuesday"}'

# 💥 broker2 moved to a new host during the window: the DNS of the data center where the worker runs still has the old
# address (a host that is gone)
log "🌙 Broker 2 moves to a new host"
playground debug dns -c connect --host broker2 --resolve-to 10.255.255.1
playground broker stop --broker 2
playground broker start --broker 2
# what auto.leader.rebalance.enable does within 5 minutes: broker 2 leads its partitions again
playground topic elect-leader --topic orders

log "☀️ End of the window: the connector is resumed"
playground connector resume --connector filestream-sink
sleep 60
log "Orders written by the connector: $(playground --output-level ERROR container exec -c connect --command "wc -l < /tmp/output.json")"
