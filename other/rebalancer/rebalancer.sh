#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

docker-compose down -v
docker-compose up -d
${DIR}/../../scripts/wait-for-connect-and-controlcenter.sh -a

echo -e "\033[0;33mCreate topic adb-test\033[0m"
docker-compose exec zookeeper kafka-topics --create --topic adb-test --partitions 20 --replication-factor 3 --if-not-exists --zookeeper zookeeper:2181

echo -e "\033[0;33mDescribe new topic adb-test\033[0m"
docker-compose exec zookeeper kafka-topics --describe --topic adb-test --zookeeper zookeeper:2181

echo -e "\033[0;33mGenerating some data to our new topic\033[0m"
docker-compose exec broker1 kafka-producer-perf-test --topic adb-test --num-records 200000 --record-size 1000 --throughput 100000 --producer-props bootstrap.servers=broker1:9092

echo -e "\033[0;33mRun confluent-rebalancer to balance the data in the cluster\033[0m"
docker-compose exec broker1 confluent-rebalancer execute --zookeeper zookeeper:2181 --metrics-bootstrap-server broker1:9092 --throttle 100000000 --force --verbose

sleep 3

echo -e "\033[0;33mCheck Status\033[0m"
docker-compose exec broker1 confluent-rebalancer status --zookeeper zookeeper:2181

echo -e "\033[0;33mFinish rebalance\033[0m"
docker-compose exec broker1 confluent-rebalancer finish --zookeeper zookeeper:2181


echo -e "\033[0;33mRemoving broker4\033[0m"
docker-compose exec broker1 confluent-rebalancer execute --zookeeper zookeeper:2181 --metrics-bootstrap-server broker1:9092 --throttle 100000000 --force --verbose --remove-broker-ids 4

sleep 3

echo -e "\033[0;33mCheck Status\033[0m"
docker-compose exec broker1 confluent-rebalancer status --zookeeper zookeeper:2181

echo -e "\033[0;33mFinish rebalance\033[0m"
docker-compose exec broker1 confluent-rebalancer finish --zookeeper zookeeper:2181

echo -e "\033[0;33mVerify broker4 is no more in replicas for topic adb-test\033[0m"
docker-compose exec zookeeper kafka-topics --describe --topic adb-test --zookeeper zookeeper:2181