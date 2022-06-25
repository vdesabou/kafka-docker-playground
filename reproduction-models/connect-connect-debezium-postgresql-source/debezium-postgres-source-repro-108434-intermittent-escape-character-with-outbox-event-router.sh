#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-108434-intermittent-escape-character-with-outbox-event-router.yml"


log "Show content of outboxevent table:"
docker exec postgres bash -c "psql -U myuser -d postgres -c 'SELECT * FROM outboxevent'"

# curl --request PUT \
#   --url http://localhost:8083/admin/loggers/io.debezium.connector \
#   --header 'Accept: application/json' \
#   --header 'Content-Type: application/json' \
#   --data '{
# 	"level": "DEBUG"
# }'

log "Creating Debezium PostgreSQL source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
               "tasks.max": "1",
               "database.hostname": "postgres",
               "database.port": "5432",
               "database.user": "myuser",
               "database.password": "mypassword",
               "database.dbname" : "postgres",
               "database.server.name": "asgard",

               "value.converter.delegate.converter.type.schemas.enable": "false",
               "value.converter.delegate.converter.type": "org.apache.kafka.connect.json.JsonConverter",
               "value.converter.schemas.enabled": "false",
               "value.converter": "io.debezium.converters.ByteBufferConverter",

               "transforms": "outbox",
               "transforms.outbox.type" : "io.debezium.transforms.outbox.EventRouter",
               "transforms.outbox.route.topic.replacement" : "users.events",
               "transforms.outbox.table.expand.json.payload": "true"
          }' \
     http://localhost:8083/connectors/debezium-postgres-source/config | jq .


sleep 5

log "Verifying topic users.events"
timeout 60 docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic users.events --from-beginning --property print.key=true --max-messages 1
# 1       {"phones":[{"type":"mobile","phone":"001001"},{"type":"fix","phone":"002002"}]}


log "Adding another element to the table"
docker exec postgres psql -U myuser -d postgres -c "INSERT INTO outboxevent (id,aggregatetype,aggregateid,type,payload) VALUES ('506c07f3-26f0-4eea-a50c-109940064b8f','Order','2','OrderCreated','{ \"phones\":[ {\"type\": \"mobile\", \"phone\": \"001002\"} , {\"type\": \"fix\", \"phone\": \"002003\"} ] }');"

# log "Adding invalid json to the table"
# docker exec postgres psql -U myuser -d postgres -c "INSERT INTO outboxevent (id,aggregatetype,aggregateid,type,payload) VALUES ('606c07f3-26f0-4eea-a50c-109940064b8f','Order','3','OrderCreated','{ \"phones\":[ {\"type\": \"mobile\", \"phone\": \"001003\"} , {\"type\": \"fix\", \"phone\": \"002004} ] }');"