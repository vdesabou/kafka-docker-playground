#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# make sure Rest Proxy is not disabled
export ENABLE_RESTPROXY=true

${DIR}/../../environment/plaintext/start.sh

log "Produce 5 records to the topic jsontest"
docker exec -i rest-proxy curl -X POST -H "Content-Type: application/vnd.kafka.json.v2+json" \
      --data '{"records":[{"value":{"foo":"bar1"}},{"value":{"foo":"bar2"}},{"value":{"foo":"bar3"}},{"value":{"foo":"bar4"}},{"value":{"foo":"bar5"}}]}' "http://rest-proxy:8082/topics/jsontest"

log "Create the consumer group"
docker exec -i rest-proxy curl -X POST -H "Content-Type: application/vnd.kafka.v2+json" \
      --data '{"name": "my_consumer_instance", "format": "json", "auto.offset.reset": "earliest"}' \
      http://rest-proxy:8082/consumers/my_json_consumer_group

docker exec -i rest-proxy curl -X POST -H "Content-Type: application/vnd.kafka.v2+json" --data '{"topics":["jsontest"]}' \
  http://rest-proxy:8082/consumers/my_json_consumer_group/instances/my_consumer_instance/subscription

log "Consuming records from the topic jsontest"
docker exec -i rest-proxy curl -X GET -H "Accept: application/vnd.kafka.json.v2+json" \
  http://rest-proxy:8082/consumers/my_json_consumer_group/instances/my_consumer_instance/records
# Note that you must issue this command twice due to https://github.com/confluentinc/kafka-rest/issues/432)
sleep 10
docker exec -i rest-proxy curl -X GET -H "Accept: application/vnd.kafka.json.v2+json" \
  http://rest-proxy:8082/consumers/my_json_consumer_group/instances/my_consumer_instance/records
# Expected output
# [{"topic":"jsontest","key":null,"value":{"foo":"bar"},"partition":0,"offset":1},{"topic":"jsontest","key":null,"value":{"foo":"bar"},"partition":0,"offset":2},{"topic":"jsontest","key":null,"value":{"foo":"bar"},"partition":0,"offset":3},{"topic":"jsontest","key":null,"value":{"foo":"bar"},"partition":0,"offset":4},{"topic":"jsontest","ke

log "Destroy the consumer instance"
# If the Consumer has timed out (default timeout is 5 minutes) this step can be skipped:
docker exec -i rest-proxy curl -X DELETE -H "Content-Type: application/vnd.kafka.v2+json" \
  http://rest-proxy:8082/consumers/my_json_consumer_group/instances/my_consumer_instance

log "Re-create the Consumer:"
docker exec -i rest-proxy curl -X POST \
     -H "Content-Type: application/vnd.kafka.v2+json" \
     --data '{"name": "my_consumer_instance", "format": "json"}' \
     http://rest-proxy:8082/consumers/my_json_consumer_group

log "Check the current offsets:"
docker exec -i rest-proxy curl -s -X GET -H "Accept: application/vnd.kafka.v2+json" -H "Content-Type: application/vnd.kafka.v2+json" \
     http://rest-proxy:8082/consumers/my_json_consumer_group/instances/my_consumer_instance/offsets  \
     --data '{"partitions": [{"topic": "jsontest","partition": 0}]}' | jq

# The offsets.retention.minutes setting is set by default to 7 days .
# So if you recreate the consumer group with the same ID/name before this 7 days retentions. The last committed offset is still stored.
# If you recreate the consumer group after this 7 days retention period, you would need to manually reset the offset to the value you would like.

log "Reset the offset to earliest"
docker exec -i rest-proxy curl -X POST \
  -H "Accept: application/vnd.kafka.v2+json" \
  -H "Content-Type: application/vnd.kafka.v2+json" \
  http://rest-proxy:8082/consumers/my_json_consumer_group/instances/my_consumer_instance/offsets \
  --data '{"offsets": [ {"topic": "jsontest", "partition": 0, "offset": -1} ]}' | jq

log "Re-subscribe the Consumer"
docker exec -i rest-proxy curl -X POST \
     -H "Content-Type: application/vnd.kafka.v2+json" \
     --data '{"topics":["jsontest"]}' \
     http://rest-proxy:8082/consumers/my_json_consumer_group/instances/my_consumer_instance/subscription

log "Read the messages/records"
docker exec -i rest-proxy curl -X GET -H "Accept: application/vnd.kafka.json.v2+json" \
  http://rest-proxy:8082/consumers/my_json_consumer_group/instances/my_consumer_instance/records
# Note that you must issue this command twice due to https://github.com/confluentinc/kafka-rest/issues/432)
sleep 10
docker exec -i rest-proxy curl -X GET -H "Accept: application/vnd.kafka.json.v2+json" \
  http://rest-proxy:8082/consumers/my_json_consumer_group/instances/my_consumer_instance/records
