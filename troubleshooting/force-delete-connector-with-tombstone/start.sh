#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

CLI=${1:-kafka-console-producer}

if [ "$CLI" != "kafka-console-producer" ] && [ "$CLI" != "kafkacat" ]
then
     logerror "CLI should be either kafka-console-producer (default) or kafkacat"
     exit 1
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Sending messages to topic http-messages"
seq 10 | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic http-messages

log "Creating http-sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "topics": "http-messages",
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.http.HttpSinkConnector",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.storage.StringConverter",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "reporter.bootstrap.servers": "broker:9092",
               "reporter.error.topic.name": "error-responses",
               "reporter.error.topic.replication.factor": 1,
               "reporter.result.topic.name": "success-responses",
               "reporter.result.topic.replication.factor": 1,
               "http.api.url": "http://http-service-no-auth:8080/api/messages",
               "batch.max.size": "10"
          }' \
     http://localhost:8083/connectors/http-sink/config | jq .


sleep 10

log "Confirm that the data was sent to the HTTP endpoint."
curl localhost:8080/api/messages | jq . > /tmp/result.log  2>&1
cat /tmp/result.log
grep "10" /tmp/result.log

log "Check the success-responses topic"
timeout 60 docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic success-responses --from-beginning --max-messages 10 --property print.headers=true

log "Show connect-configs"
docker exec -i broker kafka-console-consumer --bootstrap-server localhost:9092 --topic connect-configs --from-beginning --property print.key=true --timeout-ms 10000 1> /tmp/connect-configs.backup
cat /tmp/connect-configs.backup

log "Stopping worker"
docker stop connect

if [ "$CLI" = "kafka-console-producer" ]
then
     log "Sending string null (kafka-console-producer is not able to send tombstone, coming in https://cwiki.apache.org/confluence/pages/viewpage.action?pageId=199527475)"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic connect-configs --property parse.key=true --property key.separator=, << EOF
connector-http-sink,null
task-http-sink-0,null
commit-http-sink,null
EOF
else
     log "Sending tombstone with kafkacat"
     echo 'connector-http-sink#' | docker exec -i kafkacat kafkacat -b broker:9092 -t connect-configs -P -Z -K#
fi

log "Starting worker"
docker start connect

../../scripts/wait-for-connect-and-controlcenter.sh

sleep 30

log "Get connector status"
curl http://localhost:8083/connectors?expand=status&expand=info | jq .

# {}

log "Show connect-configs"
docker exec -i broker kafka-console-consumer --bootstrap-server localhost:9092 --topic connect-configs --from-beginning --property print.key=true --timeout-ms 10000 1> /tmp/connect-configs.backup
cat /tmp/connect-configs.backup

log "re-create connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "topics": "http-messages",
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.http.HttpSinkConnector",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.storage.StringConverter",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "reporter.bootstrap.servers": "broker:9092",
               "reporter.error.topic.name": "error-responses",
               "reporter.error.topic.replication.factor": 1,
               "reporter.result.topic.name": "success-responses",
               "reporter.result.topic.replication.factor": 1,
               "http.api.url": "http://http-service-no-auth:8080/api/messages",
               "batch.max.size": "10"
          }' \
     http://localhost:8083/connectors/http-sink/config | jq .

log "Get connector status"
curl http://localhost:8083/connectors?expand=status&expand=info | jq .

log "Sending messages to topic http-messages"
seq 10 | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic http-messages

log "Check the success-responses topic"
timeout 60 docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic success-responses --from-beginning --max-messages 20 --property print.headers=true

log "Show connect-configs"
docker exec -i broker kafka-console-consumer --bootstrap-server localhost:9092 --topic connect-configs --from-beginning --property print.key=true --timeout-ms 10000 1> /tmp/connect-configs.backup
cat /tmp/connect-configs.backup


# with kakfa-console-producer:

# [2022-03-13 13:56:48,975] INFO Successfully processed removal of connector 'http-sink' (org.apache.kafka.connect.storage.KafkaConfigBackingStore:633)
# [2022-03-13 13:56:48,977] INFO [Worker clientId=connect-1, groupId=connect-cluster] Connector http-sink config removed (org.apache.kafka.connect.runtime.distributed.DistributedHerder:1664)
# [2022-03-13 13:56:48,977] ERROR Ignoring task configuration for task http-sink-0 because it is unexpectedly null (org.apache.kafka.connect.storage.KafkaConfigBackingStore:673)
# [2022-03-13 13:56:48,978] ERROR Ignoring connector tasks configuration commit for connector 'http-sink' because it is in the wrong format: null (org.apache.kafka.connect.storage.KafkaConfigBackingStore:721)
# [2022-03-13 13:56:48,978] INFO [Worker clientId=connect-1, groupId=connect-cluster] Handling connector-only config update by stopping connector http-sink (org.apache.kafka.connect.runtime.distributed.DistributedHerder:633)
# [2022-03-13 13:56:48,979] INFO [http-sink|worker] Stopping connector http-sink (org.apache.kafka.connect.runtime.Worker:411)
# [2022-03-13 13:56:48,979] INFO [http-sink|worker] Scheduled shutdown for WorkerConnector{id=http-sink} (org.apache.kafka.connect.runtime.WorkerConnector:249)
# [2022-03-13 13:56:48,980] INFO [http-sink|worker] Completed shutdown for WorkerConnector{id=http-sink} (org.apache.kafka.connect.runtime.WorkerConnector:269)
# [2022-03-13 13:56:48,982] INFO [Worker clientId=connect-1, groupId=connect-cluster] Rebalance started (org.apache.kafka.connect.runtime.distributed.WorkerCoordinator:222)
# [2022-03-13 13:56:48,982] INFO [Worker clientId=connect-1, groupId=connect-cluster] (Re-)joining group (org.apache.kafka.connect.runtime.distributed.WorkerCoordinator:535)
# [2022-03-13 13:56:48,986] INFO [Worker clientId=connect-1, groupId=connect-cluster] Successfully joined group with generation Generation{generationId=4, memberId='connect-1-3b5b3704-b325-47a7-9528-d1daa049e5e6', protocol='sessioned'} (org.apache.kafka.connect.runtime.distributed.WorkerCoordinator:591)
# [2022-03-13 13:56:48,996] INFO [Worker clientId=connect-1, groupId=connect-cluster] Successfully synced group in generation Generation{generationId=4, memberId='connect-1-3b5b3704-b325-47a7-9528-d1daa049e5e6', protocol='sessioned'} (org.apache.kafka.connect.runtime.distributed.WorkerCoordinator:757)
# [2022-03-13 13:56:49,000] INFO [http-sink|worker] Stopping connector http-sink (org.apache.kafka.connect.runtime.Worker:411)
# [2022-03-13 13:56:49,000] WARN [http-sink|worker] Ignoring stop request for unowned connector http-sink (org.apache.kafka.connect.runtime.Worker:414)
# [2022-03-13 13:56:49,001] INFO [http-sink|task-0] Stopping task http-sink-0 (org.apache.kafka.connect.runtime.Worker:919)
# [2022-03-13 13:56:49,001] WARN [http-sink|worker] Ignoring await stop request for non-present connector http-sink (org.apache.kafka.connect.runtime.Worker:439)
# [2022-03-13 13:56:49,017] INFO [http-sink|task-0] Stopping HttpSinkTask (io.confluent.connect.http.HttpSinkTask:72)
# [2022-03-13 13:56:49,017] INFO [http-sink|task-0] [Producer clientId=producer-4] Closing the Kafka producer with timeoutMillis = 9223372036854775807 ms. (org.apache.kafka.clients.producer.KafkaProducer:1208)
# [2022-03-13 13:56:49,021] INFO [http-sink|task-0] Metrics scheduler closed (org.apache.kafka.common.metrics.Metrics:676)
# [2022-03-13 13:56:49,022] INFO [http-sink|task-0] Closing reporter org.apache.kafka.common.metrics.JmxReporter (org.apache.kafka.common.metrics.Metrics:680)
# [2022-03-13 13:56:49,022] INFO [http-sink|task-0] Metrics reporters closed (org.apache.kafka.common.metrics.Metrics:686)
# [2022-03-13 13:56:49,022] INFO [http-sink|task-0] App info kafka.producer for producer-4 unregistered (org.apache.kafka.common.utils.AppInfoParser:83)
# [2022-03-13 13:56:49,023] INFO [http-sink|task-0] [Consumer clientId=connector-consumer-http-sink-0, groupId=connect-http-sink] Revoke previously assigned partitions http-messages-0 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:310)
# [2022-03-13 13:56:49,023] INFO [http-sink|task-0] [Consumer clientId=connector-consumer-http-sink-0, groupId=connect-http-sink] Member connector-consumer-http-sink-0-1370479b-2663-4c35-b868-5678d7b91513 sending LeaveGroup request to coordinator broker:9092 (id: 2147483646 rack: null) due to the consumer is being closed (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1048)
# [2022-03-13 13:56:49,024] INFO [http-sink|task-0] [Consumer clientId=connector-consumer-http-sink-0, groupId=connect-http-sink] Resetting generation due to: consumer pro-actively leaving the group (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:966)
# [2022-03-13 13:56:49,024] INFO [http-sink|task-0] [Consumer clientId=connector-consumer-http-sink-0, groupId=connect-http-sink] Request joining group due to: consumer pro-actively leaving the group (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:988)
# [2022-03-13 13:56:49,029] INFO [http-sink|task-0] Publish thread interrupted for client_id=connector-consumer-http-sink-0 client_type=CONSUMER session= cluster=NY4z7L9BR-aJD-hnr69FIA group=connect-http-sink (io.confluent.monitoring.clients.interceptor.MonitoringInterceptor:285)
# [2022-03-13 13:56:49,122] INFO [http-sink|task-0] Publishing Monitoring Metrics stopped for client_id=connector-consumer-http-sink-0 client_type=CONSUMER session= cluster=NY4z7L9BR-aJD-hnr69FIA group=connect-http-sink (io.confluent.monitoring.clients.interceptor.MonitoringInterceptor:297)
# [2022-03-13 13:56:49,122] INFO [http-sink|task-0] [Producer clientId=confluent.monitoring.interceptor.connector-consumer-http-sink-0] Closing the Kafka producer with timeoutMillis = 9223372036854775807 ms. (org.apache.kafka.clients.producer.KafkaProducer:1208)
# [2022-03-13 13:56:49,138] INFO [http-sink|task-0] Metrics scheduler closed (org.apache.kafka.common.metrics.Metrics:676)
# [2022-03-13 13:56:49,138] INFO [http-sink|task-0] Closing reporter org.apache.kafka.common.metrics.JmxReporter (org.apache.kafka.common.metrics.Metrics:680)
# [2022-03-13 13:56:49,139] INFO [http-sink|task-0] Metrics reporters closed (org.apache.kafka.common.metrics.Metrics:686)
# [2022-03-13 13:56:49,139] INFO [http-sink|task-0] App info kafka.producer for confluent.monitoring.interceptor.connector-consumer-http-sink-0 unregistered (org.apache.kafka.common.utils.AppInfoParser:83)
# [2022-03-13 13:56:49,140] INFO [http-sink|task-0] Closed monitoring interceptor for client_id=connector-consumer-http-sink-0 client_type=CONSUMER session= cluster=NY4z7L9BR-aJD-hnr69FIA group=connect-http-sink (io.confluent.monitoring.clients.interceptor.MonitoringInterceptor:320)
# [2022-03-13 13:56:49,141] INFO [http-sink|task-0] Metrics scheduler closed (org.apache.kafka.common.metrics.Metrics:676)
# [2022-03-13 13:56:49,141] INFO [http-sink|task-0] Closing reporter org.apache.kafka.common.metrics.JmxReporter (org.apache.kafka.common.metrics.Metrics:680)
# [2022-03-13 13:56:49,141] INFO [http-sink|task-0] Metrics reporters closed (org.apache.kafka.common.metrics.Metrics:686)
# [2022-03-13 13:56:49,149] INFO [http-sink|task-0] App info kafka.consumer for connector-consumer-http-sink-0 unregistered (org.apache.kafka.common.utils.AppInfoParser:83)
# [2022-03-13 13:56:49,161] INFO [Worker clientId=connect-1, groupId=connect-cluster] Finished stopping tasks in preparation for rebalance (org.apache.kafka.connect.runtime.distributed.DistributedHerder:1931)
# [2022-03-13 13:56:49,176] INFO [Worker clientId=connect-1, groupId=connect-cluster] Finished flushing status backing store in preparation for rebalance (org.apache.kafka.connect.runtime.distributed.DistributedHerder:1950)
# [2022-03-13 13:56:49,176] INFO [Worker clientId=connect-1, groupId=connect-cluster] Joined group at generation 4 with protocol version 2 and got assignment: Assignment{error=0, leader='connect-1-3b5b3704-b325-47a7-9528-d1daa049e5e6', leaderUrl='http://connect:8083/', offset=7, connectorIds=[], taskIds=[], revokedConnectorIds=[http-sink], revokedTaskIds=[http-sink-0], delay=0} with rebalance delay: 0 (org.apache.kafka.connect.runtime.distributed.DistributedHerder:1853)
# [2022-03-13 13:56:49,178] INFO [Worker clientId=connect-1, groupId=connect-cluster] Starting connectors and tasks using config offset 7 (org.apache.kafka.connect.runtime.distributed.DistributedHerder:1378)
# [2022-03-13 13:56:49,178] INFO [Worker clientId=connect-1, groupId=connect-cluster] Finished starting connectors and tasks (org.apache.kafka.connect.runtime.distributed.DistributedHerder:1406)
# [2022-03-13 13:56:49,178] INFO [Worker clientId=connect-1, groupId=connect-cluster] Rebalance started (org.apache.kafka.connect.runtime.distributed.WorkerCoordinator:222)
# [2022-03-13 13:56:49,178] INFO [Worker clientId=connect-1, groupId=connect-cluster] (Re-)joining group (org.apache.kafka.connect.runtime.distributed.WorkerCoordinator:535)
# [2022-03-13 13:56:49,183] INFO [Worker clientId=connect-1, groupId=connect-cluster] Successfully joined group with generation Generation{generationId=5, memberId='connect-1-3b5b3704-b325-47a7-9528-d1daa049e5e6', protocol='sessioned'} (org.apache.kafka.connect.runtime.distributed.WorkerCoordinator:591)
# [2022-03-13 13:56:49,192] INFO [Worker clientId=connect-1, groupId=connect-cluster] Successfully synced group in generation Generation{generationId=5, memberId='connect-1-3b5b3704-b325-47a7-9528-d1daa049e5e6', protocol='sessioned'} (org.apache.kafka.connect.runtime.distributed.WorkerCoordinator:757)
# [2022-03-13 13:56:49,192] INFO [Worker clientId=connect-1, groupId=connect-cluster] Joined group at generation 5 with protocol version 2 and got assignment: Assignment{error=0, leader='connect-1-3b5b3704-b325-47a7-9528-d1daa049e5e6', leaderUrl='http://connect:8083/', offset=7, connectorIds=[], taskIds=[], revokedConnectorIds=[], revokedTaskIds=[], delay=0} with rebalance delay: 0 (org.apache.kafka.connect.runtime.distributed.DistributedHerder:1853)
# [2022-03-13 13:56:49,193] INFO [Worker clientId=connect-1, groupId=connect-cluster] Starting connectors and tasks using config offset 7 (org.apache.kafka.connect.runtime.distributed.DistributedHerder:1378)
# [2022-03-13 13:56:49,193] INFO [Worker clientId=connect-1, groupId=connect-cluster] Finished starting connectors and tasks (org.apache.kafka.connect.runtime.distributed.DistributedHerder:1406)


# with kafkacat:

# [2022-03-13 14:28:07,809] INFO Successfully processed removal of connector 'http-sink' (org.apache.kafka.connect.storage.KafkaConfigBackingStore:633)
# [2022-03-13 14:28:07,810] INFO [Worker clientId=connect-1, groupId=connect-cluster] Connector http-sink config removed (org.apache.kafka.connect.runtime.distributed.DistributedHerder:1664)
# [2022-03-13 14:28:07,812] INFO [Worker clientId=connect-1, groupId=connect-cluster] Handling connector-only config update by stopping connector http-sink (org.apache.kafka.connect.runtime.distributed.DistributedHerder:633)
# [2022-03-13 14:28:07,812] INFO [http-sink|worker] Stopping connector http-sink (org.apache.kafka.connect.runtime.Worker:411)
# [2022-03-13 14:28:07,812] INFO [http-sink|worker] Scheduled shutdown for WorkerConnector{id=http-sink} (org.apache.kafka.connect.runtime.WorkerConnector:249)
# [2022-03-13 14:28:07,815] INFO [http-sink|worker] Completed shutdown for WorkerConnector{id=http-sink} (org.apache.kafka.connect.runtime.WorkerConnector:269)
# [2022-03-13 14:28:07,816] INFO [Worker clientId=connect-1, groupId=connect-cluster] Rebalance started (org.apache.kafka.connect.runtime.distributed.WorkerCoordinator:222)
# [2022-03-13 14:28:07,816] INFO [Worker clientId=connect-1, groupId=connect-cluster] (Re-)joining group (org.apache.kafka.connect.runtime.distributed.WorkerCoordinator:535)
# [2022-03-13 14:28:07,820] INFO [Worker clientId=connect-1, groupId=connect-cluster] Successfully joined group with generation Generation{generationId=6, memberId='connect-1-8d08aa61-dd38-459b-a217-e90fdbb9f920', protocol='sessioned'} (org.apache.kafka.connect.runtime.distributed.WorkerCoordinator:591)
# [2022-03-13 14:28:07,827] INFO [Worker clientId=connect-1, groupId=connect-cluster] Successfully synced group in generation Generation{generationId=6, memberId='connect-1-8d08aa61-dd38-459b-a217-e90fdbb9f920', protocol='sessioned'} (org.apache.kafka.connect.runtime.distributed.WorkerCoordinator:757)
# [2022-03-13 14:28:07,830] INFO [http-sink|worker] Stopping connector http-sink (org.apache.kafka.connect.runtime.Worker:411)
# [2022-03-13 14:28:07,830] WARN [http-sink|worker] Ignoring stop request for unowned connector http-sink (org.apache.kafka.connect.runtime.Worker:414)
# [2022-03-13 14:28:07,831] INFO [http-sink|task-0] Stopping task http-sink-0 (org.apache.kafka.connect.runtime.Worker:919)
# [2022-03-13 14:28:07,831] WARN [http-sink|worker] Ignoring await stop request for non-present connector http-sink (org.apache.kafka.connect.runtime.Worker:439)
# [2022-03-13 14:28:07,833] INFO [http-sink|task-0] Stopping HttpSinkTask (io.confluent.connect.http.HttpSinkTask:72)
# [2022-03-13 14:28:07,833] INFO [http-sink|task-0] [Producer clientId=producer-4] Closing the Kafka producer with timeoutMillis = 9223372036854775807 ms. (org.apache.kafka.clients.producer.KafkaProducer:1208)
# [2022-03-13 14:28:07,837] INFO [http-sink|task-0] Metrics scheduler closed (org.apache.kafka.common.metrics.Metrics:676)
# [2022-03-13 14:28:07,837] INFO [http-sink|task-0] Closing reporter org.apache.kafka.common.metrics.JmxReporter (org.apache.kafka.common.metrics.Metrics:680)
# [2022-03-13 14:28:07,837] INFO [http-sink|task-0] Metrics reporters closed (org.apache.kafka.common.metrics.Metrics:686)
# [2022-03-13 14:28:07,837] INFO [http-sink|task-0] App info kafka.producer for producer-4 unregistered (org.apache.kafka.common.utils.AppInfoParser:83)
# [2022-03-13 14:28:07,838] INFO [http-sink|task-0] [Consumer clientId=connector-consumer-http-sink-0, groupId=connect-http-sink] Revoke previously assigned partitions http-messages-0 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:310)
# [2022-03-13 14:28:07,838] INFO [http-sink|task-0] [Consumer clientId=connector-consumer-http-sink-0, groupId=connect-http-sink] Member connector-consumer-http-sink-0-4d24b8b6-f192-43c2-84ab-17761f7b1b4b sending LeaveGroup request to coordinator broker:9092 (id: 2147483646 rack: null) due to the consumer is being closed (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1048)
# [2022-03-13 14:28:07,839] INFO [http-sink|task-0] [Consumer clientId=connector-consumer-http-sink-0, groupId=connect-http-sink] Resetting generation due to: consumer pro-actively leaving the group (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:966)
# [2022-03-13 14:28:07,840] INFO [http-sink|task-0] [Consumer clientId=connector-consumer-http-sink-0, groupId=connect-http-sink] Request joining group due to: consumer pro-actively leaving the group (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:988)
# [2022-03-13 14:28:07,843] INFO [http-sink|task-0] Publish thread interrupted for client_id=connector-consumer-http-sink-0 client_type=CONSUMER session= cluster=w3IrYMtSRXKYb4cXy7Xw7w group=connect-http-sink (io.confluent.monitoring.clients.interceptor.MonitoringInterceptor:285)
# [2022-03-13 14:28:07,844] INFO [http-sink|task-0] Publishing Monitoring Metrics stopped for client_id=connector-consumer-http-sink-0 client_type=CONSUMER session= cluster=w3IrYMtSRXKYb4cXy7Xw7w group=connect-http-sink (io.confluent.monitoring.clients.interceptor.MonitoringInterceptor:297)
# [2022-03-13 14:28:07,844] INFO [http-sink|task-0] [Producer clientId=confluent.monitoring.interceptor.connector-consumer-http-sink-0] Closing the Kafka producer with timeoutMillis = 9223372036854775807 ms. (org.apache.kafka.clients.producer.KafkaProducer:1208)
# [2022-03-13 14:28:07,849] INFO [http-sink|task-0] Metrics scheduler closed (org.apache.kafka.common.metrics.Metrics:676)
# [2022-03-13 14:28:07,849] INFO [http-sink|task-0] Closing reporter org.apache.kafka.common.metrics.JmxReporter (org.apache.kafka.common.metrics.Metrics:680)
# [2022-03-13 14:28:07,849] INFO [http-sink|task-0] Metrics reporters closed (org.apache.kafka.common.metrics.Metrics:686)
# [2022-03-13 14:28:07,850] INFO [http-sink|task-0] App info kafka.producer for confluent.monitoring.interceptor.connector-consumer-http-sink-0 unregistered (org.apache.kafka.common.utils.AppInfoParser:83)
# [2022-03-13 14:28:07,850] INFO [http-sink|task-0] Closed monitoring interceptor for client_id=connector-consumer-http-sink-0 client_type=CONSUMER session= cluster=w3IrYMtSRXKYb4cXy7Xw7w group=connect-http-sink (io.confluent.monitoring.clients.interceptor.MonitoringInterceptor:320)
# [2022-03-13 14:28:07,850] INFO [http-sink|task-0] Metrics scheduler closed (org.apache.kafka.common.metrics.Metrics:676)
# [2022-03-13 14:28:07,850] INFO [http-sink|task-0] Closing reporter org.apache.kafka.common.metrics.JmxReporter (org.apache.kafka.common.metrics.Metrics:680)
# [2022-03-13 14:28:07,850] INFO [http-sink|task-0] Metrics reporters closed (org.apache.kafka.common.metrics.Metrics:686)
# [2022-03-13 14:28:07,855] INFO [http-sink|task-0] App info kafka.consumer for connector-consumer-http-sink-0 unregistered (org.apache.kafka.common.utils.AppInfoParser:83)
# [2022-03-13 14:28:07,865] INFO [Worker clientId=connect-1, groupId=connect-cluster] Finished stopping tasks in preparation for rebalance (org.apache.kafka.connect.runtime.distributed.DistributedHerder:1931)
# [2022-03-13 14:28:07,873] INFO [Worker clientId=connect-1, groupId=connect-cluster] Finished flushing status backing store in preparation for rebalance (org.apache.kafka.connect.runtime.distributed.DistributedHerder:1950)
# [2022-03-13 14:28:07,873] INFO [Worker clientId=connect-1, groupId=connect-cluster] Joined group at generation 6 with protocol version 2 and got assignment: Assignment{error=0, leader='connect-1-8d08aa61-dd38-459b-a217-e90fdbb9f920', leaderUrl='http://connect:8083/', offset=7, connectorIds=[], taskIds=[], revokedConnectorIds=[http-sink], revokedTaskIds=[http-sink-0], delay=0} with rebalance delay: 0 (org.apache.kafka.connect.runtime.distributed.DistributedHerder:1853)
# [2022-03-13 14:28:07,874] INFO [Worker clientId=connect-1, groupId=connect-cluster] Starting connectors and tasks using config offset 7 (org.apache.kafka.connect.runtime.distributed.DistributedHerder:1378)
# [2022-03-13 14:28:07,874] INFO [Worker clientId=connect-1, groupId=connect-cluster] Finished starting connectors and tasks (org.apache.kafka.connect.runtime.distributed.DistributedHerder:1406)
# [2022-03-13 14:28:07,874] INFO [Worker clientId=connect-1, groupId=connect-cluster] Rebalance started (org.apache.kafka.connect.runtime.distributed.WorkerCoordinator:222)
# [2022-03-13 14:28:07,875] INFO [Worker clientId=connect-1, groupId=connect-cluster] (Re-)joining group (org.apache.kafka.connect.runtime.distributed.WorkerCoordinator:535)
# [2022-03-13 14:28:07,877] INFO [Worker clientId=connect-1, groupId=connect-cluster] Successfully joined group with generation Generation{generationId=7, memberId='connect-1-8d08aa61-dd38-459b-a217-e90fdbb9f920', protocol='sessioned'} (org.apache.kafka.connect.runtime.distributed.WorkerCoordinator:591)
# [2022-03-13 14:28:07,882] INFO [Worker clientId=connect-1, groupId=connect-cluster] Successfully synced group in generation Generation{generationId=7, memberId='connect-1-8d08aa61-dd38-459b-a217-e90fdbb9f920', protocol='sessioned'} (org.apache.kafka.connect.runtime.distributed.WorkerCoordinator:757)
# [2022-03-13 14:28:07,883] INFO [Worker clientId=connect-1, groupId=connect-cluster] Joined group at generation 7 with protocol version 2 and got assignment: Assignment{error=0, leader='connect-1-8d08aa61-dd38-459b-a217-e90fdbb9f920', leaderUrl='http://connect:8083/', offset=7, connectorIds=[], taskIds=[], revokedConnectorIds=[], revokedTaskIds=[], delay=0} with rebalance delay: 0 (org.apache.kafka.connect.runtime.distributed.DistributedHerder:1853)
# [2022-03-13 14:28:07,883] INFO [Worker clientId=connect-1, groupId=connect-cluster] Starting connectors and tasks using config offset 7 (org.apache.kafka.connect.runtime.distributed.DistributedHerder:1378)
# [2022-03-13 14:28:07,884] INFO [Worker clientId=connect-1, groupId=connect-cluster] Finished starting connectors and tasks (org.apache.kafka.connect.runtime.distributed.DistributedHerder:1406)



# Conclusion: same behaviour except with kafkacat we don't have:

# [2022-03-13 13:56:48,977] ERROR Ignoring task configuration for task http-sink-0 because it is unexpectedly null (org.apache.kafka.connect.storage.KafkaConfigBackingStore:673)
# [2022-03-13 13:56:48,978] ERROR Ignoring connector tasks configuration commit for connector 'http-sink' because it is in the wrong format: null (org.apache.kafka.connect.storage.KafkaConfigBackingStore:721)