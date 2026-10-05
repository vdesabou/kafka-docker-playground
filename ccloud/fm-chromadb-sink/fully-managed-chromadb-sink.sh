#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

NGROK_AUTH_TOKEN=${NGROK_AUTH_TOKEN:-$1}

display_ngrok_warning

bootstrap_ccloud_environment

docker compose build
docker compose down -v --remove-orphans
docker compose up -d --quiet-pull

sleep 5

log "Waiting for ngrok to start"
while true
do
  container_id=$(docker ps -q -f name=ngrok)
  if [ -n "$container_id" ]
  then
    status=$(docker inspect --format '{{.State.Status}}' $container_id)
    if [ "$status" = "running" ]
    then
      log "Getting ngrok hostname and port"
      NGROK_URL=$(curl --silent http://127.0.0.1:4040/api/tunnels | jq -r '.tunnels[0].public_url')
      NGROK_HOSTNAME=$(echo $NGROK_URL | cut -d "/" -f3 | cut -d ":" -f 1)
      NGROK_PORT=$(echo $NGROK_URL | cut -d "/" -f3 | cut -d ":" -f 2)

      if ! [[ $NGROK_PORT =~ ^[0-9]+$ ]]
      then
        log "NGROK_PORT is not a valid number, keep retrying..."
        continue
      else
        break
      fi
    fi
  fi
  log "Waiting for container ngrok to start..."
  sleep 5
done

log "Checking ChromaDB is up"
curl -s --fail --retry 10 --retry-all-errors --retry-delay 3 http://localhost:8000/api/v2/healthcheck
echo ""

set +e
playground topic delete --topic chromadb-topic
sleep 3
playground topic create --topic chromadb-topic --nb-partitions 1
set -e

# the connector expects fields id, document, embedding (all embeddings of a collection must have the same dimension) and metadata
log "Sending messages to topic chromadb-topic"
playground topic produce -t chromadb-topic --nb-messages 10 --forced-value '{"id":"doc%g","document":"this is document number %g","embedding":[0.1,0.2,0.3,0.4],"metadata":{"source":"kafka-docker-playground"}}' << 'EOF'
{
  "type": "record",
  "name": "ChromaDocument",
  "fields": [
    {
      "name": "id",
      "type": "string"
    },
    {
      "name": "document",
      "type": "string"
    },
    {
      "name": "embedding",
      "type": {
        "type": "array",
        "items": "float"
      }
    },
    {
      "name": "metadata",
      "type": {
        "type": "map",
        "values": "string"
      }
    }
  ]
}
EOF

connector_name="ChromaDBSink_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

# self-hosted ChromaDB (1.x) has no server-side authentication, the api key is required by the connector but ignored by the server
log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
  "connector.class": "ChromaDBSink",
  "name": "$connector_name",
  "kafka.auth.mode": "KAFKA_API_KEY",
  "kafka.api.key": "$CLOUD_KEY",
  "kafka.api.secret": "$CLOUD_SECRET",
  "topics": "chromadb-topic",
  "input.data.format": "AVRO",
  "chromadb.endpoint": "http://$NGROK_HOSTNAME:$NGROK_PORT",
  "chromadb.api.key": "not-used",
  "chromadb.tenant": "default_tenant",
  "chromadb.database": "default_database",
  "chromadb.auto.create.collection": "true",
  "collection1.name": "playground-collection",
  "collection1.topic": "chromadb-topic",
  "tasks.max": "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

sleep 30

playground connector show-lag --connector $connector_name

log "Verify data is in ChromaDB collection playground-collection"
collection_id=$(curl -s --fail http://localhost:8000/api/v2/tenants/default_tenant/databases/default_database/collections/playground-collection | jq -r '.id')
curl -s --fail -X POST http://localhost:8000/api/v2/tenants/default_tenant/databases/default_database/collections/$collection_id/get \
  -H "Content-Type: application/json" \
  -d '{"limit": 10, "include": ["documents", "metadatas"]}' > /tmp/result.log
cat /tmp/result.log | jq .
nb=$(curl -s --fail http://localhost:8000/api/v2/tenants/default_tenant/databases/default_database/collections/$collection_id/count)
log "Collection playground-collection contains $nb records"
if [ "$nb" != "10" ]
then
  logerror "❌ expected 10 records in collection playground-collection, got $nb"
  exit 1
fi

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name
