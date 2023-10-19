#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# make sure ksqlDB is not disabled
export ENABLE_KSQLDB=true

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

sleep 5

log "Send message in raw Protobuf, without Schema Registry"
docker exec proto_producer bash -c "python publisher.py"

cd api && python publisher.py

log "Create the ksqlDB stream"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';

CREATE STREAM persons (key INT KEY, name STRING, id INT, email STRING, phones ARRAY<STRUCT<number STRING, type INT>>) with (kafka_topic='persons', partitions=1, value_format='PROTOBUF_NOSR');

EOF
docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';

CREATE STREAM UserCreatedEvent (event_id INT KEY, event_timestamp TIMESTAMP, event_name STRING, version STRING) with (kafka_topic='user_created_event', partitions=1, value_format='PROTOBUF_NOSR');

select * from USERCREATEDEVENT limit 3;

EOF

docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';

select * from USERCREATEDEVENT limit 3;

EOF
