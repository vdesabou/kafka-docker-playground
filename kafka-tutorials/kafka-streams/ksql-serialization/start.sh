#!/bin/bash

# https://kafka-tutorials.confluent.io/filter-a-stream-of-events/kstreams.html

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

echo -e "\033[0;33mProduce some JSON-formatted movies to the input topic\033[0m"
docker exec -i broker /usr/bin/kafka-console-producer --topic json-movies --broker-list broker:9092 << EOF
{"movie_id":1,"title":"Lethal Weapon","release_year":1992}
{"movie_id":2,"title":"Die Hard","release_year":1988}
{"movie_id":3,"title":"Predator","release_year":1987}
EOF

echo -e "\033[0;33mObserve the Avro-formatted movies in the output topic\033[0m"
docker exec -it schema-registry /usr/bin/kafka-avro-console-consumer --topic avro-movies --bootstrap-server broker:9092 --from-beginning --property value.schema="$(< src/main/avro/movie.avsc)" --max-messages 3