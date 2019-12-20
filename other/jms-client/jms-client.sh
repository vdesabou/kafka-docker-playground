#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml" -a -b


echo -e "\033[0;33mSending messages to topic test-queue using JMS client\033[0m"
docker exec -e BOOTSTRAP_SERVERS="broker:9092" -e ZOOKEEPER_CONNECT="zookeeper:2181" jms-client bash -c "java -jar jms-client-1.0.0-jar-with-dependencies.jar"