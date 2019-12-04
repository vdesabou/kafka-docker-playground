#!/bin/bash

# https://kafka-tutorials.confluent.io/transform-a-stream-of-events/kstreams.html

verify_installed()
{
  local cmd="$1"
  if [[ $(type $cmd 2>&1) =~ "not found" ]]; then
    echo -e "\nERROR: This script requires '$cmd'. Please install '$cmd' and run again.\n"
    exit 1
  fi
}
verify_installed "docker-compose"

docker-compose down -v
docker-compose up -d --build

echo -e "\n\n⏳ Waiting for Schema Registry to be available\n"
while [ $(curl -s -o /dev/null -w %{http_code} http://localhost:8081/) -eq 000 ]
do
  echo -e $(date) "Schema Registry HTTP state: " $(curl -s -o /dev/null -w %{http_code} http://localhost:8081/) " (waiting for 200)"
  sleep 5
done

echo "Produce events to the input topic"
docker exec -i schema-registry /usr/bin/kafka-avro-console-producer --topic raw-movies --broker-list broker:9092 --property value.schema="$(< src/main/avro/input_movie_event.avsc)" << EOF
{"id": 294, "title": "Die Hard::1988", "genre": "action"}
{"id": 354, "title": "Tree of Life::2011", "genre": "drama"}
{"id": 782, "title": "A Walk in the Clouds::1995", "genre": "romance"}
{"id": 128, "title": "The Big Lebowski::1998", "genre": "comedy"}
EOF

echo "Observe the transformed movies in the output topic"
docker exec -it schema-registry /usr/bin/kafka-avro-console-consumer --topic movies --bootstrap-server broker:9092 --from-beginning --max-messages 4