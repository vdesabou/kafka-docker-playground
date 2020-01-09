#!/bin/bash

# https://kafka-tutorials.confluent.io/transform-a-stream-of-events/kstreams.html

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
verify_installed "docker-compose"

docker-compose down -v
docker-compose up -d --build

echo -e "\n\n⏳ Waiting for Schema Registry to be available\n"
while [ $(curl -s -o /dev/null -w %{http_code} http://localhost:8081/) -eq 000 ]
do
  echo -e $(date) "Schema Registry HTTP state: " $(curl -s -o /dev/null -w %{http_code} http://localhost:8081/) " (waiting for 200)"
  sleep 5
done

echo -e "\033[0;33mProduce events to the input topic\033[0m"
docker exec -i schema-registry /usr/bin/kafka-avro-console-producer --topic raw-movies --broker-list broker:9092 --property value.schema="$(< src/main/avro/input_movie_event.avsc)" << EOF
{"id": 294, "title": "Die Hard::1988", "genre": "action"}
{"id": 354, "title": "Tree of Life::2011", "genre": "drama"}
{"id": 782, "title": "A Walk in the Clouds::1995", "genre": "romance"}
{"id": 128, "title": "The Big Lebowski::1998", "genre": "comedy"}
EOF

echo -e "\033[0;33mObserve the transformed movies in the output topic\033[0m"
docker exec -it schema-registry /usr/bin/kafka-avro-console-consumer --topic movies --bootstrap-server broker:9092 --from-beginning --max-messages 4