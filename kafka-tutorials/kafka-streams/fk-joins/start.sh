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

log "Load in some movie reference data"
docker exec -i schema-registry /usr/bin/kafka-avro-console-producer --topic albums --broker-list broker:9092 --property "parse.key=true" --property 'key.schema={"type":"long"}' --property "key.separator=:" --property value.schema="$(< src/main/avro/album.avsc)" << EOF
5:{"id": 5, "title": "Physical Graffiti", "artist": "Led Zeppelin", "genre": "Rock"}
6:{"id": 6, "title": "Highway to Hell",   "artist": "AC/DC", "genre": "Rock"}
7:{"id": 7, "title": "Radio", "artist": "LL Cool J",  "genre": "Hip hop"}
8:{"id": 8, "title": "King of Rock", "artist": "Run-D.M.C", "genre": "Rap rock"}
EOF

log "Produce some track purchases to the input topic"
docker exec -i schema-registry /usr/bin/kafka-avro-console-producer --topic purchases --broker-list broker:9092 --property "parse.key=true" --property 'key.schema={"type":"long"}' --property "key.separator=:" --property value.schema="$(< src/main/avro/track-purchase.avsc)" << EOF
100:{"id": 100, "album_id": 5, "song_title": "Houses Of The Holy", "price": 0.99}
101:{"id": 101, "album_id": 8, "song_title": "King Of Rock", "price": 0.99}
102:{"id": 102, "album_id": 6, "song_title": "Shot Down In Flames", "price": 0.99}
103:{"id": 103, "album_id": 7, "song_title": "Rock The Bells", "price": 0.99}
104:{"id": 104, "album_id": 8, "song_title": "Can You Rock It Like This", "price": 0.99}
105:{"id": 105, "album_id": 6, "song_title": "Highway To Hell", "price": 0.99}
106:{"id": 106, "album_id": 5, "song_title": "Kashmir", "price": 0.99}
EOF

log "Observe the music interest trends in the output topic"
docker exec -it schema-registry /usr/bin/kafka-avro-console-consumer --topic music-interest --bootstrap-server broker:9092 --from-beginning --max-messages 7