#!/bin/bash

# https://kafka-tutorials.confluent.io/filter-a-stream-of-events/kstreams.html

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

echo -e "\033[0;33mProduce rock songs\033[0m"
docker exec -i schema-registry /usr/bin/kafka-avro-console-producer --topic rock-song-events --broker-list broker:9092 --property value.schema="$(< src/main/avro/song_event.avsc)" << EOF
{"artist": "Metallica", "title": "Fade to Black"}
{"artist": "Smashing Pumpkins", "title": "Today"}
{"artist": "Pink Floyd", "title": "Another Brick in the Wall"}
{"artist": "Van Halen", "title": "Jump"}
{"artist": "Led Zeppelin", "title": "Kashmir"}
EOF

echo -e "\033[0;33mProduce classical songs\033[0m"
docker exec -i schema-registry /usr/bin/kafka-avro-console-producer --topic classical-song-events --broker-list broker:9092 --property value.schema="$(< src/main/avro/song_event.avsc)"  << EOF
{"artist": "Wolfgang Amadeus Mozart", "title": "The Magic Flute"}
{"artist": "Johann Pachelbel", "title": "Canon"}
{"artist": "Ludwig van Beethoven", "title": "Symphony No. 5"}
{"artist": "Edward Elgar", "title": "Pomp and Circumstance"}
EOF

echo -e "\033[0;33mConsume all songs\033[0m"
docker exec -it schema-registry /usr/bin/kafka-avro-console-consumer --topic all-song-events --bootstrap-server broker:9092 --from-beginning --max-messages 9
