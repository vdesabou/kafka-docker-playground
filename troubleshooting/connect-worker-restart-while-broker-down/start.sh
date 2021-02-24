#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

docker-compose down -v --remove-orphans
docker-compose up -d
${DIR}/../../scripts/wait-for-connect-and-controlcenter.sh "connect1"
${DIR}/../../scripts/wait-for-connect-and-controlcenter.sh "connect2"


log "Creating SFTP Sink connector with 4 tasks"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
        "topics": "test_sftp_sink",
               "tasks.max": "4",
               "connector.class": "io.confluent.connect.sftp.SftpSinkConnector",
               "partitioner.class": "io.confluent.connect.storage.partitioner.DefaultPartitioner",
               "schema.generator.class": "io.confluent.connect.storage.hive.schema.DefaultSchemaGenerator",
               "flush.size": "3",
               "schema.compatibility": "NONE",
               "format.class": "io.confluent.connect.sftp.sink.format.avro.AvroFormat",
               "storage.class": "io.confluent.connect.sftp.sink.storage.SftpSinkStorage",
               "sftp.host": "sftp-server",
               "sftp.port": "22",
               "sftp.username": "foo",
               "sftp.password": "pass",
               "sftp.working.dir": "/upload",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/sftp-sink/config | jq .

sleep 5

log "Getting tasks placement"
curl --request GET \
  --url http://localhost:8083/connectors/sftp-sink/status \
  --header 'accept: application/json' | jq

log "Stop broker 1 (first in the connect worker bootstrap.servers list)"
docker container stop broker1
# if broker 2 or 3 is down, no problem
# docker container stop broker2

docker container stop connect2

log "Getting tasks placement"
curl --request GET \
  --url http://localhost:8083/connectors/sftp-sink/status \
  --header 'accept: application/json' | jq

docker container start connect2

#FIXTHIS
# 172.27.0.4:9092) could not be established. Broker may not be available.
# [kafka-admin-client-thread | adminclient-1] WARN org.apache.kafka.clients.NetworkClient - [AdminClient clientId=adminclient-1] Connection to node -1 (broker2/172.27.0.5:9092) could not be established. Broker may not be available.
# [kafka-admin-client-thread | adminclient-1] WARN org.apache.kafka.clients.NetworkClient - [AdminClient clientId=adminclient-1] Connection to node -2 (broker3/172.27.0.4:9092) could not be established. Broker may not be available.
# [kafka-admin-client-thread | adminclient-1] WARN org.apache.kafka.clients.NetworkClient - [AdminClient clientId=adminclient-1] Connection to node -1 (broker2/172.27.0.5:9092) could not be established. Broker may not be available.
# [kafka-admin-client-thread | adminclient-1] WARN org.apache.kafka.clients.NetworkClient - [AdminClient clientId=adminclient-1] Connection to node -2 (broker3/172.27.0.4:9092) could not be established. Broker may not be available.
# [kafka-admin-client-thread | adminclient-1] WARN org.apache.kafka.clients.NetworkClient - [AdminClient clientId=adminclient-1] Connection to node -1 (broker2/172.27.0.5:9092) could not be established. Broker may not be available.
# [main] ERROR io.confluent.admin.utils.ClusterStatus - Error while getting broker list.
# java.util.concurrent.ExecutionException: org.apache.kafka.common.errors.TimeoutException: Call(callName=listNodes, deadlineMs=1614162287210, tries=1, nextAllowedTryMs=1614162287311) timed out at 1614162287211 after 1 attempt(s)
#         at org.apache.kafka.common.internals.KafkaFutureImpl.wrapAndThrow(KafkaFutureImpl.java:45)
#         at org.apache.kafka.common.internals.KafkaFutureImpl.access$000(KafkaFutureImpl.java:32)
#         at org.apache.kafka.common.internals.KafkaFutureImpl$SingleWaiter.await(KafkaFutureImpl.java:89)
#         at org.apache.kafka.common.internals.KafkaFutureImpl.get(KafkaFutureImpl.java:260)
#         at io.confluent.admin.utils.ClusterStatus.isKafkaReady(ClusterStatus.java:149)
#         at io.confluent.admin.utils.cli.KafkaReadyCommand.main(KafkaReadyCommand.java:150)
# Caused by: org.apache.kafka.common.errors.TimeoutException: Call(callName=listNodes, deadlineMs=1614162287210, tries=1, nextAllowedTryMs=1614162287311) timed out at 1614162287211 after 1 attempt(s)
# Caused by: org.apache.kafka.common.errors.TimeoutException: Timed out waiting for a node assignment. Call: listNodes
# [kafka-admin-client-thread | adminclient-1] WARN org.apache.kafka.clients.NetworkClient - [AdminClient clientId=adminclient-1] Connection to node -2 (broker3/172.27.0.4:9092) could not be established. Broker may not be available.
# [kafka-admin-client-thread | adminclient-1] WARN org.apache.kafka.clients.NetworkClient - [AdminClient clientId=adminclient-1] Connection to node -1 (broker2/172.27.0.5:9092) could not be established. Broker may not be available.
# [main] INFO io.confluent.admin.utils.ClusterStatus - Expected 1 brokers but found only 0. Trying to query Kafka for metadata again ...
# [main] ERROR io.confluent.admin.utils.ClusterStatus - Expected 1 brokers but found only 0. Brokers found [].

log "sleep 5 minutes (scheduled.rebalance.max.delay.ms), after this time all tasks should be RUNNING (no more UNASSIGNED)"
sleep 310

log "Getting tasks placement"
curl --request GET \
  --url http://localhost:8083/connectors/sftp-sink/status \
  --header 'accept: application/json' | jq
