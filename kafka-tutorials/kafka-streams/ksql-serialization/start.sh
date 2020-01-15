#!/bin/bash

# https://kafka-tutorials.confluent.io/filter-a-stream-of-events/kstreams.html

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

log "Produce some JSON-formatted movies to the input topic"
docker exec -i broker /usr/bin/kafka-console-producer --topic json-movies --broker-list broker:9092 << EOF
{"movie_id":1,"title":"Lethal Weapon","release_year":1992}
{"movie_id":2,"title":"Die Hard","release_year":1988}
{"movie_id":3,"title":"Predator","release_year":1987}
EOF

log "Observe the Avro-formatted movies in the output topic"
docker exec -it schema-registry /usr/bin/kafka-avro-console-consumer --topic avro-movies --bootstrap-server broker:9092 --from-beginning --property value.schema="$(< src/main/avro/movie.avsc)" --max-messages 3