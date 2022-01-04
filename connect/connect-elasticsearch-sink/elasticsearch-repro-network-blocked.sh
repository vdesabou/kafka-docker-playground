#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh


function wait_for_repro () {
     MAX_WAIT=600
     CUR_WAIT=0
     log "⌛ Waiting up to $MAX_WAIT seconds for error due to consumer poll timeout has expired. to happen"
     docker container logs connect > /tmp/out.txt 2>&1
     while ! grep "due to consumer poll timeout has expired." /tmp/out.txt > /dev/null;
     do
          sleep 10
          docker container logs connect > /tmp/out.txt 2>&1
          CUR_WAIT=$(( CUR_WAIT+10 ))
          if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
               echo -e "\nERROR: The logs in all connect containers do not show 'due to consumer poll timeout has expired.' after $MAX_WAIT seconds. Please troubleshoot with 'docker container ps' and 'docker container logs'.\n"
               exit 1
          fi
     done
     log "The problem has been reproduced !"
}

# As of version 11.0.0, the connector uses the Elasticsearch High Level REST Client (version 7.0.1),
# which means only Elasticsearch 7.x is supported.

export ELASTIC_VERSION="6.8.3"
if version_gt $CONNECTOR_TAG "10.9.9"
then
    log "Connector version is > 11.0.0, using Elasticsearch 7.x"
    export ELASTIC_VERSION="7.12.0"
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

curl --request PUT \
  --url http://localhost:8083/admin/loggers/io.confluent.connect.elasticsearch \
  --header 'Accept: application/json' \
  --header 'Content-Type: application/json' \
  --data '{
	"level": "TRACE"
}'

log "Creating Elasticsearch Sink connector (Elasticsearch version is $ELASTIC_VERSION"
if version_gt $CONNECTOR_TAG "10.9.9"
then
     # 7.x
     curl -X PUT \
          -H "Content-Type: application/json" \
          --data '{
               "connector.class": "io.confluent.connect.elasticsearch.ElasticsearchSinkConnector",
               "tasks.max": "1",
               "topics": "test-elasticsearch-sink",
               "key.ignore": "true",
               "connection.url": "http://elasticsearch:9200",
               "max.retries": "1000",
               "retry.backoff.ms": "5000"
               }' \
          http://localhost:8083/connectors/elasticsearch-sink/config | jq .
else
     # 6.x
     curl -X PUT \
          -H "Content-Type: application/json" \
          --data '{
               "connector.class": "io.confluent.connect.elasticsearch.ElasticsearchSinkConnector",
               "tasks.max": "1",
               "topics": "test-elasticsearch-sink",
               "key.ignore": "true",
               "connection.url": "http://elasticsearch:9200",
               "type.name": "kafka-connect"
               }' \
          http://localhost:8083/connectors/elasticsearch-sink/config | jq .
fi

log "Sending messages to topic test-elasticsearch-sink"
seq -f "{\"f1\": \"valubefore%g\"}" 3 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic test-elasticsearch-sink --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

sleep 10

log "Check that the data is available in Elasticsearch"
curl -XGET 'http://localhost:9200/test-elasticsearch-sink/_search?pretty' > /tmp/result.log  2>&1
cat /tmp/result.log
grep "f1" /tmp/result.log | grep "valubefore1"

log "Block response from ES"
docker exec --privileged --user root connect bash -c "iptables -A INPUT -p tcp --sport 9200 -j DROP"

log "Sending messages to topic test-elasticsearch-sink"
seq -f "{\"f1\": \"valueafter%g\"}" 3 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic test-elasticsearch-sink --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

log "sleep 6 minutes"
sleep 360

log "Unblock response from ES"
docker exec --privileged --user root connect bash -c "iptables -D INPUT -p tcp --sport 9200 -j DROP"

log "Sending messages to topic test-elasticsearch-sink"
seq -f "{\"f1\": \"valueafter2%g\"}" 3 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic test-elasticsearch-sink --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

sleep 10

log "Check that the data is available in Elasticsearch"
curl -XGET 'http://localhost:9200/test-elasticsearch-sink/_search?pretty' > /tmp/result.log  2>&1
cat /tmp/result.log
grep "f1" /tmp/result.log | grep "valueafter"
grep "f1" /tmp/result.log | grep "valueafter2"

# [2021-10-28 10:08:16,546] WARN [elasticsearch-sink|task-0] Failed to check if index test-elasticsearch-sink exists due to java.net.ConnectException: Timeout connecting to [elasticsearch/172.29.0.3:9200]. Retrying attempt (1/1001) after backoff of 2771 ms (io.confluent.connect.elasticsearch.RetryUtil:171)
# [2021-10-28 10:08:21,321] WARN [elasticsearch-sink|task-0] Failed to check if index test-elasticsearch-sink exists due to java.net.ConnectException: Timeout connecting to [elasticsearch/172.29.0.3:9200]. Retrying attempt (2/1001) after backoff of 14057 ms (io.confluent.connect.elasticsearch.RetryUtil:171)
# [2021-10-28 10:08:36,381] WARN [elasticsearch-sink|task-0] Failed to check if index test-elasticsearch-sink exists due to java.net.ConnectException: Timeout connecting to [elasticsearch/172.29.0.3:9200]. Retrying attempt (3/1001) after backoff of 32798 ms (io.confluent.connect.elasticsearch.RetryUtil:171)
# [2021-10-28 10:09:10,185] WARN [elasticsearch-sink|task-0] Failed to check if index test-elasticsearch-sink exists due to java.net.ConnectException: Timeout connecting to [elasticsearch/172.29.0.3:9200]. Retrying attempt (4/1001) after backoff of 25636 ms (io.confluent.connect.elasticsearch.RetryUtil:171)
# [2021-10-28 10:09:36,826] WARN [elasticsearch-sink|task-0] Failed to check if index test-elasticsearch-sink exists due to java.net.ConnectException: Timeout connecting to [elasticsearch/172.29.0.3:9200]. Retrying attempt (5/1001) after backoff of 3721 ms (io.confluent.connect.elasticsearch.RetryUtil:171)
# [2021-10-28 10:09:41,550] WARN [elasticsearch-sink|task-0] Failed to check if index test-elasticsearch-sink exists due to java.net.ConnectException: Timeout connecting to [elasticsearch/172.29.0.3:9200]. Retrying attempt (6/1001) after backoff of 177688 ms (io.confluent.connect.elasticsearch.RetryUtil:171)
# [2021-10-28 10:12:40,242] WARN [elasticsearch-sink|task-0] Failed to check if index test-elasticsearch-sink exists due to java.net.ConnectException: Timeout connecting to [elasticsearch/172.29.0.3:9200]. Retrying attempt (7/1001) after backoff of 532500 ms (io.confluent.connect.elasticsearch.RetryUtil:171)
# [2021-10-28 10:13:15,182] INFO [elasticsearch-sink|task-0] [Consumer clientId=connector-consumer-elasticsearch-sink-0, groupId=connect-elasticsearch-sink] Member connector-consumer-elasticsearch-sink-0-59179556-62af-4a0a-9bc2-57bdf7ad7077 sending LeaveGroup request to coordinator broker:9092 (id: 2147483646 rack: null) due to consumer poll timeout has expired. This means the time between subsequent calls to poll() was longer than the configured max.poll.interval.ms, which typically implies that the poll loop is spending too much time processing messages. You can address this either by increasing max.poll.interval.ms or by reducing the maximum size of batches returned in poll() with max.poll.records. (org.apache.kafka.clients.consumer.internals.AbstractCoordinator:1043)


# {
#   "name": "elasticsearch-sink",
#   "connector": {
#     "state": "RUNNING",
#     "worker_id": "connect:8083"
#   },
#   "tasks": [
#     {
#       "id": 0,
#       "state": "RUNNING",
#       "worker_id": "connect:8083"
#     }
#   ],
#   "type": "sink"
# }

# [2021-10-28 10:21:33,193] INFO [elasticsearch-sink|task-0] [Consumer clientId=connector-consumer-elasticsearch-sink-0, groupId=connect-elasticsearch-sink] Giving away all assigned partitions as lost since generation has been reset,indicating that consumer is no longer part of the group (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:691)
# [2021-10-28 10:21:33,193] INFO [elasticsearch-sink|task-0] [Consumer clientId=connector-consumer-elasticsearch-sink-0, groupId=connect-elasticsearch-sink] Lost previously assigned partitions test-elasticsearch-sink-0 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:326)
# [2021-10-28 10:21:33,194] INFO [elasticsearch-sink|task-0] [Consumer clientId=connector-consumer-elasticsearch-sink-0, groupId=connect-elasticsearch-sink] (Re-)joining group (org.apache.kafka.clients.consumer.internals.AbstractCoordinator:538)
# [2021-10-28 10:21:33,197] INFO [elasticsearch-sink|task-0] [Consumer clientId=connector-consumer-elasticsearch-sink-0, groupId=connect-elasticsearch-sink] (Re-)joining group (org.apache.kafka.clients.consumer.internals.AbstractCoordinator:538)
# [2021-10-28 10:21:36,199] INFO [elasticsearch-sink|task-0] [Consumer clientId=connector-consumer-elasticsearch-sink-0, groupId=connect-elasticsearch-sink] Successfully joined group with generation Generation{generationId=1, memberId='connector-consumer-elasticsearch-sink-0-402dc558-2279-4250-a144-3e0a925d140b', protocol='range'} (org.apache.kafka.clients.consumer.internals.AbstractCoordinator:594)
# [2021-10-28 10:21:36,199] INFO [elasticsearch-sink|task-0] [Consumer clientId=connector-consumer-elasticsearch-sink-0, groupId=connect-elasticsearch-sink] Finished assignment for group at generation 1: {connector-consumer-elasticsearch-sink-0-402dc558-2279-4250-a144-3e0a925d140b=Assignment(partitions=[test-elasticsearch-sink-0])} (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:626)
# [2021-10-28 10:21:36,201] INFO [elasticsearch-sink|task-0] [Consumer clientId=connector-consumer-elasticsearch-sink-0, groupId=connect-elasticsearch-sink] Successfully synced group in generation Generation{generationId=1, memberId='connector-consumer-elasticsearch-sink-0-402dc558-2279-4250-a144-3e0a925d140b', protocol='range'} (org.apache.kafka.clients.consumer.internals.AbstractCoordinator:758)
# [2021-10-28 10:21:36,202] INFO [elasticsearch-sink|task-0] [Consumer clientId=connector-consumer-elasticsearch-sink-0, groupId=connect-elasticsearch-sink] Notifying assignor about the new Assignment(partitions=[test-elasticsearch-sink-0]) (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:276)
# [2021-10-28 10:21:36,202] INFO [elasticsearch-sink|task-0] [Consumer clientId=connector-consumer-elasticsearch-sink-0, groupId=connect-elasticsearch-sink] Adding newly assigned partitions: test-elasticsearch-sink-0 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:288)
# [2021-10-28 10:21:36,203] INFO [elasticsearch-sink|task-0] [Consumer clientId=connector-consumer-elasticsearch-sink-0, groupId=connect-elasticsearch-sink] Found no committed offset for partition test-elasticsearch-sink-0 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1362)
# [2021-10-28 11:08:08,976] INFO [Worker clientId=connect-1, groupId=connect-cluster] Session key updated (org.apache.kafka.connect.runtime.distributed.DistributedHerder:1582)
