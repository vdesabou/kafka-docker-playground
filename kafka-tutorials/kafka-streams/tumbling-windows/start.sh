#!/bin/bash

# https://kafka-tutorials.confluent.io/create-tumbling-windows/kstreams.html

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

log "Produce some ratings to the input topic"
docker exec -i schema-registry /usr/bin/kafka-avro-console-producer --topic ratings --broker-list broker:9092 --property value.schema="$(< src/main/avro/rating.avsc)" << EOF
{"title": "Die Hard", "release_year": 1998, "rating": 8.2, "timestamp": "2019-04-25T18:00:00-0700"}
{"title": "Die Hard", "release_year": 1998, "rating": 4.5, "timestamp": "2019-04-25T18:03:00-0700"}
{"title": "Die Hard", "release_year": 1998, "rating": 5.1, "timestamp": "2019-04-25T18:04:00-0700"}
{"title": "Die Hard", "release_year": 1998, "rating": 2.0, "timestamp": "2019-04-25T18:07:00-0700"}
{"title": "Die Hard", "release_year": 1998, "rating": 8.3, "timestamp": "2019-04-25T18:32:00-0700"}
{"title": "Die Hard", "release_year": 1998, "rating": 3.4, "timestamp": "2019-04-25T18:36:00-0700"}
{"title": "Die Hard", "release_year": 1998, "rating": 4.2, "timestamp": "2019-04-25T18:43:00-0700"}
{"title": "Die Hard", "release_year": 1998, "rating": 7.6, "timestamp": "2019-04-25T18:44:00-0700"}
{"title": "Tree of Life", "release_year": 2011, "rating": 4.9, "timestamp": "2019-04-25T20:01:00-0700"}
{"title": "Tree of Life", "release_year": 2011, "rating": 5.6, "timestamp": "2019-04-25T20:02:00-0700"}
{"title": "Tree of Life", "release_year": 2011, "rating": 9.0, "timestamp": "2019-04-25T20:03:00-0700"}
{"title": "Tree of Life", "release_year": 2011, "rating": 6.5, "timestamp": "2019-04-25T20:12:00-0700"}
{"title": "Tree of Life", "release_year": 2011, "rating": 2.1, "timestamp": "2019-04-25T20:13:00-0700"}
{"title": "A Walk in the Clouds", "release_year": 1995, "rating": 3.6, "timestamp": "2019-04-25T22:20:00-0700"}
{"title": "A Walk in the Clouds", "release_year": 1995, "rating": 6.0, "timestamp": "2019-04-25T22:21:00-0700"}
{"title": "A Walk in the Clouds", "release_year": 1995, "rating": 7.0, "timestamp": "2019-04-25T22:22:00-0700"}
{"title": "A Walk in the Clouds", "release_year": 1995, "rating": 4.6, "timestamp": "2019-04-25T22:23:00-0700"}
{"title": "A Walk in the Clouds", "release_year": 1995, "rating": 7.1, "timestamp": "2019-04-25T22:24:00-0700"}
{"title": "The Big Lebowski", "release_year": 1998, "rating": 9.9, "timestamp": "2019-04-25T21:15:00-0700"}
{"title": "The Big Lebowski", "release_year": 1998, "rating": 8.6, "timestamp": "2019-04-25T21:16:00-0700"}
{"title": "The Big Lebowski", "release_year": 1998, "rating": 4.2, "timestamp": "2019-04-25T21:17:00-0700"}
{"title": "The Big Lebowski", "release_year": 1998, "rating": 7.0, "timestamp": "2019-04-25T21:18:00-0700"}
{"title": "The Big Lebowski", "release_year": 1998, "rating": 9.5, "timestamp": "2019-04-25T21:19:00-0700"}
{"title": "The Big Lebowski", "release_year": 1998, "rating": 3.2, "timestamp": "2019-04-25T21:20:00-0700"}
{"title": "Super Mario Bros.", "release_year": 1993, "rating": 3.5, "timestamp": "2019-04-25T13:00:00-0700"}
{"title": "Super Mario Bros.", "release_year": 1993, "rating": 4.0, "timestamp": "2019-04-25T13:07:00-0700"}
{"title": "Super Mario Bros.", "release_year": 1993, "rating": 5.1, "timestamp": "2019-04-25T13:30:00-0700"}
{"title": "Super Mario Bros.", "release_year": 1993, "rating": 2.0, "timestamp": "2019-04-25T13:34:00-0700"}
EOF

log "observe the counted ratings in the output topic"
docker exec -it broker /usr/bin/kafka-console-consumer --topic rating-counts --bootstrap-server broker:9092 --from-beginning --property print.key=true --max-messages 13