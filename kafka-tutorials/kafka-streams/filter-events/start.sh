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
docker exec -i schema-registry /usr/bin/kafka-avro-console-producer --topic publications --broker-list broker:9092 --property value.schema="$(< src/main/avro/publication.avsc)" << EOF
{"name": "George R. R. Martin", "title": "A Song of Ice and Fire"}
{"name": "C.S. Lewis", "title": "The Silver Chair"}
{"name": "C.S. Lewis", "title": "Perelandra"}
{"name": "George R. R. Martin", "title": "Fire & Blood"}
{"name": "J. R. R. Tolkien", "title": "The Hobbit"}
{"name": "J. R. R. Tolkien", "title": "The Lord of the Rings"}
{"name": "George R. R. Martin", "title": "A Dream of Spring"}
{"name": "J. R. R. Tolkien", "title": "The Fellowship of the Ring"}
{"name": "George R. R. Martin", "title": "The Ice Dragon"}
EOF

log "Consume filtered events from the output topic"
docker exec -it schema-registry /usr/bin/kafka-avro-console-consumer --topic filtered-publications --bootstrap-server broker:9092 --from-beginning --max-messages 4