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

log "Produce events to the input topic"
docker exec -i schema-registry /usr/bin/kafka-avro-console-producer --topic acting-events --broker-list broker:9092 --property value.schema="$(< src/main/avro/acting_event.avsc)" << EOF
{"name": "Meryl Streep", "title": "The Iron Lady", "genre": "drama"}
{"name": "Will Smith", "title": "Men in Black", "genre": "comedy"}
{"name": "Matt Damon", "title": "The Martian", "genre": "drama"}
{"name": "Judy Garland", "title": "The Wizard of Oz", "genre": "fantasy"}
{"name": "Jennifer Aniston", "title": "Office Space", "genre": "comedy"}
{"name": "Bill Murray", "title": "Ghostbusters", "genre": "fantasy"}
{"name": "Christian Bale", "title": "The Dark Knight", "genre": "crime"}
{"name": "Laura Dern", "title": "Jurassic Park", "genre": "fantasy"}
{"name": "Keanu Reeves", "title": "The Matrix", "genre": "fantasy"}
{"name": "Russell Crowe", "title": "Gladiator", "genre": "drama"}
{"name": "Diane Keaton", "title": "The Godfather: Part II", "genre": "crime"}
EOF

log "Consume the events of drama films"
docker exec -it schema-registry /usr/bin/kafka-avro-console-consumer --topic drama-acting-events --bootstrap-server broker:9092 --from-beginning --max-messages 3

log "Consume the events of fantasy films"
docker exec -it schema-registry /usr/bin/kafka-avro-console-consumer --topic fantasy-acting-events --bootstrap-server broker:9092 --from-beginning --max-messages 4

log "Consume all other events"
docker exec -it schema-registry /usr/bin/kafka-avro-console-consumer --topic other-acting-events --bootstrap-server broker:9092 --from-beginning --max-messages 4