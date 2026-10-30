#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "6.9.9"; then
    logwarn "Cluster Linking is GA since CP 7.0 only"
    exit 111
fi

playground start-environment --environment mdc-plaintext --docker-compose-override-file "${PWD}/docker-compose.mdc-plaintext-migrate-sink-connector.yml"


log "Create topic demo"
playground topic create --cluster us --topic demo --nb-partitions 1

log "Create the cluster link on the destination cluster (with metadata.max.age.ms=5 seconds + consumer.offset.sync.enable=true + consumer.offset.sync.ms=3000 + consumer.offset.sync.json set to all consumer groups)"
playground container cp --source consumer.offset.sync.json --destination broker-europe:/tmp/consumer.offset.sync.json
docker exec broker-europe kafka-cluster-links --bootstrap-server broker-europe:9092 --create --link demo-link --config bootstrap.servers=broker-us:9092,metadata.max.age.ms=5000,consumer.offset.sync.enable=true,consumer.offset.sync.ms=3000 --consumer-group-filters-json-file /tmp/consumer.offset.sync.json

log "Initialize the topic mirror for topic demo"
docker exec broker-europe kafka-mirrors --create --mirror-topic demo --link demo-link --bootstrap-server broker-europe:9092

log "Check the replica status on the destination"
docker exec broker-europe kafka-replica-status --topics demo --include-linked --bootstrap-server broker-europe:9092

log "Sending messages to topic demo"
playground topic produce --cluster us --topic demo --nb-messages 1 --value '{"customer_name":"Ed", "complaint_type":"Dirty car", "trip_cost": 29.10, "new_customer": false, "number_of_rides": 22}'

log "Creating FileStream Sink connector in US"
playground connector create-or-update --cluster us --connector filestream-sink << EOF
{
     "tasks.max": "1",
     "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
     "topics": "demo",
     "file": "/tmp/output.json",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.json.JsonConverter",
     "value.converter.schemas.enable": "false"
}
EOF


sleep 5

log "Verify we have received the data in file"
playground container exec -c connect-us --command "cat /tmp/output.json"

log "Delete connector in US"
playground connector delete --cluster us --connector filestream-sink

log "Wait 6 seconds for consumer.offset sync to happen (2 times consumer.offset.sync.ms=3000)"
sleep 6

log "Verify that current offset is consistent in source and destination"
log "Describe consumer group connect-filestream-sink at Source cluster"
playground consumer-group describe --cluster us --group connect-filestream-sink

# GROUP                   TOPIC           PARTITION  CURRENT-OFFSET  LOG-END-OFFSET  LAG             CONSUMER-ID                                                               HOST            CLIENT-ID
# connect-filestream-sink demo            0          1               1               0               connector-consumer-filestream-sink-0-23902981-4d65-424d-a7ff-7bce17eb6669 /172.28.0.10    connector-consumer-filestream-sink-0

log "Describe consumer group connect-filestream-sink at Destination cluster"
playground consumer-group describe --cluster europe --group connect-filestream-sink
# Consumer group 'connect-filestream-sink' has no active members.

# GROUP                   TOPIC           PARTITION  CURRENT-OFFSET  LOG-END-OFFSET  LAG             CONSUMER-ID     HOST            CLIENT-ID
# connect-filestream-sink demo            0          1               1               0               -               -               -
log "Creating FileStream Sink connector in Europe"
playground connector create-or-update --cluster europe --connector filestream-sink << EOF
{
     "tasks.max": "1",
     "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
     "topics": "demo",
     "file": "/tmp/output.json",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.json.JsonConverter",
     "value.converter.schemas.enable": "false"
}
EOF


sleep 5

log "Verify we have not received the data in file, since offset is 1"
playground container exec -c connect-europe --command "cat /tmp/output.json"

log "Sending another message to topic demo"
playground topic produce --cluster us --topic demo --nb-messages 1 --value '{"customer_name":"Ed2", "complaint_type":"Dirty car2", "trip_cost": 29.10, "new_customer": true, "number_of_rides": 22}'

sleep 5

log "Verify we have received the data in Europe"
playground container exec -c connect-europe --command "cat /tmp/output.json"
# {complaint_type=Dirty car2, new_customer=true, trip_cost=29.1, customer_name=Ed2, number_of_rides=22}