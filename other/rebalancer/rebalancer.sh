#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

docker compose down -v --remove-orphans
docker compose up -d
${DIR}/wait_container_ready -a -b

log "Create topic adb-test"
docker compose exec zookeeper kafka-topics --create --topic adb-test --partitions 20 --replication-factor 3 --if-not-exists --bootstrap-server broker1:9092

log "Describe new topic adb-test"
docker compose exec zookeeper kafka-topics --describe --topic adb-test --bootstrap-server broker1:9092

log "Generating some data to our new topic"
docker compose exec broker1 kafka-producer-perf-test --topic adb-test --num-records 200000 --record-size 1000 --throughput 100000 --producer-props bootstrap.servers=broker1:9092

log "Run confluent-rebalancer to balance the data in the cluster"
docker compose exec broker1 confluent-rebalancer execute --bootstrap-server broker1:9092 --metrics-bootstrap-server broker1:9092 --throttle 100000000 --force --verbose

sleep 3

log "Check Status"
docker compose exec broker1 confluent-rebalancer status --bootstrap-server broker1:9092

log "Finish rebalance"
docker compose exec broker1 confluent-rebalancer finish --bootstrap-server broker1:9092


log "Removing broker4"
docker compose exec broker1 confluent-rebalancer execute --bootstrap-server broker1:9092 --metrics-bootstrap-server broker1:9092 --throttle 100000000 --force --verbose --remove-broker-ids 4

sleep 3

log "Check Status"
docker compose exec broker1 confluent-rebalancer status --bootstrap-server broker1:9092

log "Finish rebalance"
docker compose exec broker1 confluent-rebalancer finish --bootstrap-server broker1:9092

log "Verify broker4 is no more in replicas for topic adb-test"
docker compose exec zookeeper kafka-topics --describe --topic adb-test --bootstrap-server broker1:9092