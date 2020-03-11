#!/bin/bash

set -e

# https://kafka-tutorials.confluent.io/create-stateful-aggregation-sum/kstreams.html

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

log "Produce events to the input topic"
docker exec -i schema-registry /usr/bin/kafka-avro-console-producer --topic movie-ticket-sales --broker-list broker:9092 --property value.schema="$(< src/main/avro/movie-ticket-sales.avsc)" << EOF
{"title":"Avengers: Endgame","release_year":2019,"total_sales":856980506}
{"title":"Captain Marvel","release_year":2019,"total_sales":426829839}
{"title":"Toy Story 4","release_year":2019,"total_sales":401486230}
{"title":"The Lion King","release_year":2019,"total_sales":385082142}
{"title":"Black Panther","release_year":2018,"total_sales":700059566}
{"title":"Avengers: Infinity War","release_year":2018,"total_sales":678815482}
{"title":"Deadpool 2","release_year":2018,"total_sales":324512774}
{"title":"Beauty and the Beast","release_year":2017,"total_sales":517218368}
{"title":"Wonder Woman","release_year":2017,"total_sales":412563408}
{"title":"Star Wars Ep. VIII: The Last Jedi","release_year":2017,"total_sales":517218368}
EOF

log "Consume aggregated results from the output topic"
docker exec -it schema-registry /usr/bin/kafka-avro-console-consumer --topic movie-figures-by-year --bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --from-beginning --max-messages 9