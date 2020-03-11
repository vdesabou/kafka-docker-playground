#!/bin/bash

set -e

# https://kafka-tutorials.confluent.io/create-tumbling-windows/kstreams.html

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../../scripts/utils.sh
verify_installed "docker-compose"

docker-compose down -v
docker-compose up -d --build

echo -e "\n\n⏳ Waiting for Schema Registry to be available\n"
while [ $(curl -s -o /dev/null -w %{http_code} http://localhost:8081/) -eq 000 ]
do
  echo -e $(date) "Schema Registry HTTP state: " $(curl -s -o /dev/null -w %{http_code} http://localhost:8081/) " (waiting for 200)"
  sleep 5
done

log "Produce some ratings to the input topic"
docker exec -i schema-registry /usr/bin/kafka-avro-console-producer --topic input-topic --broker-list broker:9092 --property value.schema="$(< src/main/avro/pressure-alert.avsc)" << EOF
{"id":"101","datetime":"'$(date +%FT%T.%z)'","pressure":30}
{"id":"101","datetime":"'$(date +%FT%T.%z)'","pressure":30}
{"id":"101","datetime":"'$(date +%FT%T.%z)'","pressure":30}
{"id":"102","datetime":"'$(date +%FT%T.%z)'","pressure":30}
EOF
sleep 10
docker exec -i schema-registry /usr/bin/kafka-avro-console-producer --topic input-topic --broker-list broker:9092 --property value.schema="$(< src/main/avro/pressure-alert.avsc)" << EOF
{"id":"101","datetime":"'$(date -v-10S +%FT%T.%z)'","pressure":30}
{"id":"101","datetime":"'$(date -v-15S +%FT%T.%z)'","pressure":30}
{"id":"101","datetime":"'$(date -v-60S +%FT%T.%z)'","pressure":30}
{"id":"102","datetime":"'$(date +%FT%T.%z)'","pressure":30}
EOF
sleep 10
docker exec -i schema-registry /usr/bin/kafka-avro-console-producer --topic input-topic --broker-list broker:9092 --property value.schema="$(< src/main/avro/pressure-alert.avsc)" << EOF
{"id":"102","datetime":"'$(date -v-60S +%FT%T.%z)'","pressure":30}
EOF
export TZ=Asia/Tokyo
docker exec -i schema-registry /usr/bin/kafka-avro-console-producer --topic input-topic --broker-list broker:9092 --property value.schema="$(< src/main/avro/pressure-alert.avsc)" << EOF
{"id":"301","datetime":"'$(date +%FT%T.%z)'","pressure":30}
{"id":"301","datetime":"'$(date +%FT%T.%z)'","pressure":30}
EOF
sleep 10
docker exec -i schema-registry /usr/bin/kafka-avro-console-producer --topic input-topic --broker-list broker:9092 --property value.schema="$(< src/main/avro/pressure-alert.avsc)" << EOF
{"id":"XXX","datetime":"'$(date +%FT%T.%z)'","pressure":30}
EOF

log "observe the counted ratings in the output topic"
docker exec stream bash -c "java -cp *.jar io.confluent.developer.helper.ResultConsumer"