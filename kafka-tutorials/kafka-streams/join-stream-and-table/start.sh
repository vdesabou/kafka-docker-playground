#!/bin/bash

# https://kafka-tutorials.confluent.io/create-stateful-aggregation-sum/kstreams.html

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

echo -e "\033[0;33mLoad in some movie reference data\033[0m"
docker exec -i schema-registry /usr/bin/kafka-avro-console-producer --topic movies --broker-list broker:9092 --property value.schema="$(< src/main/avro/movie.avsc)" << EOF
{"id": 294, "title": "Die Hard", "release_year": 1988}
{"id": 354, "title": "Tree of Life", "release_year": 2011}
{"id": 782, "title": "A Walk in the Clouds", "release_year": 1995}
{"id": 128, "title": "The Big Lebowski", "release_year": 1998}
{"id": 780, "title": "Super Mario Bros.", "release_year": 1993}
EOF

echo -e "\033[0;33mProduce some ratings to the input topic\033[0m"
docker exec -i schema-registry /usr/bin/kafka-avro-console-producer --topic ratings --broker-list broker:9092 --property value.schema="$(< src/main/avro/rating.avsc)" << EOF
{"id": 294, "rating": 8.2}
{"id": 294, "rating": 8.5}
{"id": 354, "rating": 9.9}
{"id": 354, "rating": 9.7}
{"id": 782, "rating": 7.8}
{"id": 782, "rating": 7.7}
{"id": 128, "rating": 8.7}
{"id": 128, "rating": 8.4}
{"id": 780, "rating": 2.1}
EOF

echo -e "\033[0;33mObserve the rated movies in the output topic\033[0m"
docker exec -it schema-registry /usr/bin/kafka-avro-console-consumer --topic rated-movies --bootstrap-server broker:9092 --from-beginning --max-messages 9