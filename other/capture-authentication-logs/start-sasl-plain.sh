#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

playground start-environment --environment sasl-plain --docker-compose-override-file "${PWD}/docker-compose.sasl-plain.yml"

sleep 10

seq 10 | docker exec -i broker kafka-console-producer --bootstrap-server broker:9092 --topic test-topic --producer.config /tmp/good-credentials-client.properties
# docker logs broker | grep -E "SocketServer.*Successfully authent.*"
docker logs broker | sed -rn 's/^.*SocketServer.*Successfully authent.*\/([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}).*$/Authentication success from IP: \1/p'

docker exec -i broker kafka-console-producer --bootstrap-server localhost:9092 --topic foo --producer.config /tmp/bad-credentials-client.properties &
console_producer_pid=$!
sleep 10
kill -9 $console_producer_pid
sleep 5

#docker logs broker | grep -E "SocketServer.*Failed authent.*userId=(bad-client).*"
docker logs broker | sed -rn 's/^.*SocketServer.*Failed authent.*\/([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}).*userId=(.*),.*$/Authentication failed from IP: \1 with userId: \2/p'

