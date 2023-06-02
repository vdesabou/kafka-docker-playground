#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "6.9.9"; then
    logwarn "WARN: Cluster Linking is GA since CP 7.0 only"
    exit 111
fi

${DIR}/../../environment/mdc-plaintext/start.sh "${PWD}/docker-compose.mdc-plaintext-migrate-sink-connector.yml"


log "Create topic demo"
docker exec broker-europe kafka-topics --create --topic demo --bootstrap-server broker-us:9092 --replication-factor 1 --partitions 1

log "Create the cluster link on the destination cluster (with metadata.max.age.ms=5 seconds + consumer.offset.sync.enable=true + consumer.offset.sync.ms=3000 + consumer.offset.sync.json set to all consumer groups)"
docker cp consumer.offset.sync.json broker-europe:/tmp/consumer.offset.sync.json
docker exec broker-europe kafka-cluster-links --bootstrap-server broker-europe:9092 --create --link demo-link --config bootstrap.servers=broker-us:9092,metadata.max.age.ms=5000,consumer.offset.sync.enable=true,consumer.offset.sync.ms=3000 --consumer-group-filters-json-file /tmp/consumer.offset.sync.json

log "Initialize the topic mirror for topic demo"
docker exec broker-europe kafka-mirrors --create --mirror-topic demo --link demo-link --bootstrap-server broker-europe:9092

log "Check the replica status on the destination"
docker exec broker-europe kafka-replica-status --topics demo --include-linked --bootstrap-server broker-europe:9092

log "Sending messages to topic demo"
docker exec -i broker-us kafka-console-producer --broker-list broker-us:9092 --topic demo << EOF
{"customer_name":"Ed", "complaint_type":"Dirty car", "trip_cost": 29.10, "new_customer": false, "number_of_rides": 22}
EOF

log "Creating FileStream Sink connector in US"
docker exec connect-us \
playground connector create-or-update --connector filestream-sink << EOF
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
docker exec connect-us cat /tmp/output.json

log "Delete connector in US"
docker exec connect-us curl -X DELETE localhost:8083/connectors/filestream-sink

log "Wait 6 seconds for consumer.offset sync to happen (2 times consumer.offset.sync.ms=3000)"
sleep 6

log "Verify that current offset is consistent in source and destination"
log "Describe consumer group connect-filestream-sink at Source cluster"
docker exec broker-europe kafka-consumer-groups --bootstrap-server broker-us:9092 --describe --group connect-filestream-sink

# GROUP                   TOPIC           PARTITION  CURRENT-OFFSET  LOG-END-OFFSET  LAG             CONSUMER-ID                                                               HOST            CLIENT-ID
# connect-filestream-sink demo            0          1               1               0               connector-consumer-filestream-sink-0-23902981-4d65-424d-a7ff-7bce17eb6669 /172.28.0.10    connector-consumer-filestream-sink-0

log "Describe consumer group connect-filestream-sink at Destination cluster"
docker exec broker-europe kafka-consumer-groups --bootstrap-server broker-europe:9092 --describe --group connect-filestream-sink
# Consumer group 'connect-filestream-sink' has no active members.

# GROUP                   TOPIC           PARTITION  CURRENT-OFFSET  LOG-END-OFFSET  LAG             CONSUMER-ID     HOST            CLIENT-ID
# connect-filestream-sink demo            0          1               1               0               -               -               -
log "Creating FileStream Sink connector in Europe"
docker exec connect-europe \
playground connector create-or-update --connector filestream-sink << EOF
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
docker exec connect-europe cat /tmp/output.json

log "Sending another message to topic demo"
docker exec -i broker-us kafka-console-producer --broker-list broker-us:9092 --topic demo << EOF
{"customer_name":"Ed2", "complaint_type":"Dirty car2", "trip_cost": 29.10, "new_customer": true, "number_of_rides": 22}
EOF

sleep 5

log "Verify we have received the data in Europe"
docker exec connect-europe cat /tmp/output.json
# {complaint_type=Dirty car2, new_customer=true, trip_cost=29.1, customer_name=Ed2, number_of_rides=22}