#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/lab-utils.bash

# lab of https://kafka-docker-playground.io/#/deep-dive-observability
lab_require_plaintext
# same as playground run --enable-jmx-grafana --enable-control-center
export ENABLE_JMX_GRAFANA=1
export ENABLE_CONTROL_CENTER=1
lab_start_environment
LAB_ENVIRONMENT_READY=$SECONDS

log "Step 1: what the two flags start"
lab_run playground status
lab_expect_contains "control-center"
lab_expect_contains "prometheus-c3-v2"
lab_expect_contains "alertmanager-c3-v2"
lab_expect_contains "grafana"
lab_expect_contains "pyroscope"
lab_expect_contains "kafka-lag-exporter"

log "Step 2: a load, then the digest commands"
lab_run playground topic create --topic lab-observability --nb-partitions 3
lab_expect_exit 0
lab_run playground topic produce -t lab-observability --nb-messages 20000 --value '{"id": %g, "name": "name-%g"}'
lab_expect_exit 0
lab_create_filestream_sink
lab_run playground broker metrics --topic lab-observability
lab_expect_exit 0
lab_expect_contains "📈 Broker metrics (rates and failed requests of topic lab-observability)"
lab_expect_contains "METRIC BROKER 1"
lab_expect_contains "Under-replicated partitions 0"
lab_expect_contains "Request handler idle (1m)"
lab_expect_contains "Produce p99"
lab_expect_contains "🎓 idle below 30% means the broker threads are saturated (num.io.threads, num.network.threads)"
lab_run playground connector metrics --connector filestream-sink
lab_expect_exit 0
lab_expect_contains "📈 Task metrics of 🌎onprem connector filestream-sink (sink, connector RUNNING)"
lab_expect_contains "sent to DLQ 0"
lab_expect_contains "✅ Nothing stands out: no error, no skipped record, all tasks made progress"

log "Step 3: the raw MBeans behind them"
lab_run bash -c "playground get-jmx-metrics -c broker -d 'kafka.server kafka.network' 2>&1 | grep -E '^#mbean' | grep -E 'name=(UnderReplicatedPartitions|UnderMinIsrPartitionCount|RequestHandlerAvgIdlePercent|NetworkProcessorAvgIdlePercent|RequestQueueSize|IsrShrinksPerSec),|name=TotalTimeMs,request=Produce,' | sort -u"
lab_expect_contains "#mbean = kafka.server:name=UnderReplicatedPartitions,type=ReplicaManager:"
lab_expect_contains "#mbean = kafka.server:name=RequestHandlerAvgIdlePercent,type=KafkaRequestHandlerPool:"
lab_expect_contains "#mbean = kafka.network:name=NetworkProcessorAvgIdlePercent,type=SocketServer:"
lab_expect_contains "#mbean = kafka.network:name=RequestQueueSize,type=RequestChannel:"
lab_expect_contains "#mbean = kafka.network:name=TotalTimeMs,request=Produce,type=RequestMetrics:"
lab_run bash -c "playground get-jmx-metrics -c controller -d 'kafka.controller' 2>&1 | grep -E '^#mbean' | grep -E 'ActiveControllerCount|OfflinePartitionsCount|GlobalPartitionCount' | sort -u"
lab_expect_contains "#mbean = kafka.controller:name=ActiveControllerCount,type=KafkaController:"
lab_expect_contains "#mbean = kafka.controller:name=OfflinePartitionsCount,type=KafkaController:"

log "Step 4: Prometheus and Grafana (--enable-jmx-grafana)"
# the exporter agents serve metrics as soon as the JVM is up, Prometheus scrapes every 15 s
for i in $(seq 1 30)
do
    health=$(curl -s localhost:9090/api/v1/targets | jq -r '.data.activeTargets[] | select(.labels.instance == "broker:1234") | .health')
    [ "$health" == "up" ] && break
    log "⌛ broker:1234 target of Prometheus is ${health:-unknown}, waiting"
    sleep 5
done
log "⏱️ broker:1234 target up $((SECONDS - LAB_ENVIRONMENT_READY))s after the environment was ready"
lab_run bash -c "curl -s localhost:9090/api/v1/targets | jq -r '.data.activeTargets[] | \"\(.labels.job) \(.labels.instance) \(.health)\"' | sort"
lab_expect_contains "kafka-broker broker:1234 up"
lab_expect_contains "kafka-controller controller:1234 up" "KRaft: the controller is scraped too"
lab_expect_contains "kafka-connect connect:1234 up"
lab_expect_contains "schema-registry schema-registry:1234 up"
lab_expect_contains "kafka-broker broker2:1234 down" "a target of a container that is not started stays down"
lab_run bash -c "curl -s localhost:9090/api/v1/label/__name__/values | jq -r '.data[]'"
lab_expect_contains "kafka_server_replicamanager_underreplicatedpartitions"
lab_expect_contains "kafka_server_kafkarequesthandlerpool_requesthandleravgidlepercent"
lab_expect_contains "kafka_network_socketserver_networkprocessoravgidlepercent"
lab_expect_contains "kafka_network_requestchannel_requestqueuesize"
lab_expect_contains "kafka_network_requestmetrics_totaltimems"
lab_expect_contains "kafka_server_replicamanager_isrshrinkspersec"
lab_expect_contains "kafka_connect_task_error_metrics_deadletterqueue_produce_requests"
lab_expect_contains "kafka_consumer_consumer_fetch_manager_metrics_records_lag_max"
lab_expect_contains "jvm_gc_collection_seconds_sum"
# the expression of the "Active Controllers" panel of the Kafka cluster dashboard
lab_run bash -c "curl -s localhost:9090/api/v1/query --data-urlencode 'query=kafka_controller_kafkacontroller_activecontrollercount{job=~\"kafka-broker|kafka-controller\"} > 0' | jq -r '.data.result[] | \"\\(.metric.instance) \\(.value[1])\"'"
lab_expect_contains "controller:1234 1" "KRaft: the active controller, from the controller container"
lab_run bash -c "curl -s localhost:3000/api/health | jq -r .database; curl -s -u admin:password 'localhost:3000/api/search?type=dash-db' | jq -r '.[].title'"
lab_expect_contains "ok"
lab_expect_contains "Kafka cluster"
lab_expect_contains "Kafka Connect cluster"
lab_expect_contains "Confluent Platform overview"
lab_run bash -c "curl -s localhost:4040/api/apps | jq -r '.[].name'"
lab_expect_contains "broker.itimer"
lab_expect_contains "connect.itimer"

log "Step 5: Control Center and its own Prometheus (--enable-control-center)"
for i in $(seq 1 30)
do
    code=$(curl -s -o /dev/null -w "%{http_code}" localhost:9021/)
    [ "$code" == "200" ] && break
    log "⌛ Control Center answers $code, waiting"
    sleep 10
done
lab_expect_equals "$code" "200" "Control Center http://127.0.0.1:9021"
for i in $(seq 1 30)
do
    lab_run playground container exec -c prometheus-c3-v2 --shell sh --command "curl -s http://localhost:9090/api/v1/label/__name__/values"
    grep -q "io_confluent_kafka_server_partition_under_replicated" <<< "$LAB_OUTPUT" && break
    log "⌛ no broker telemetry in prometheus-c3-v2 yet, waiting"
    sleep 10
done
lab_expect_contains "io_confluent_kafka_server_partition_under_replicated"
lab_expect_contains "io_confluent_kafka_server_request_handler_pool_request_handler_avg_idle_percent_rate_1_min"
lab_expect_contains "io_confluent_kafka_server_request_channel_request_queue_size"

log "✅ all the outputs of the page are as expected"
