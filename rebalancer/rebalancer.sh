#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/reset-cluster.sh

echo "Create topic adb-test"
docker-compose exec zookeeper kafka-topics --create --topic adb-test --partitions 20 --replication-factor 3 --if-not-exists --zookeeper zookeeper:2181

echo "Describe new topic adb-test"
docker-compose exec zookeeper kafka-topics --describe --topic adb-test --zookeeper zookeeper:2181

echo "Generating some data to our new topic"
docker-compose exec broker1 kafka-producer-perf-test --topic adb-test --num-records 200000 --record-size 1000 --throughput 100000 --producer-props bootstrap.servers=broker1:9092

echo "Run confluent-rebalancer to balance the data in the cluster"
docker-compose exec broker1 confluent-rebalancer execute --zookeeper zookeeper:2181 --metrics-bootstrap-server broker1:9092 --throttle 100000000 --force --verbose

sleep 3

echo "Check Status"
docker-compose exec broker1 confluent-rebalancer status --zookeeper zookeeper:2181

echo "Finish rebalance"
docker-compose exec broker1 confluent-rebalancer finish --zookeeper zookeeper:2181


echo "Removing broker4"
docker-compose exec broker1 confluent-rebalancer execute --zookeeper zookeeper:2181 --metrics-bootstrap-server broker1:9092 --throttle 100000000 --force --verbose --remove-broker-ids 4

sleep 3

echo "Check Status"
docker-compose exec broker1 confluent-rebalancer status --zookeeper zookeeper:2181

echo "Finish rebalance"
docker-compose exec broker1 confluent-rebalancer finish --zookeeper zookeeper:2181

echo "Verify broker4 is no more in replicas for topic adb-test"
docker-compose exec zookeeper kafka-topics --describe --topic adb-test --zookeeper zookeeper:2181