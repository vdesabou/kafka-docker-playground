#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

NGROK_AUTH_TOKEN=${NGROK_AUTH_TOKEN:-$1}

display_ngrok_warning

bootstrap_ccloud_environment


set +e
playground topic delete --topic users
set -e

docker compose build
docker compose down -v --remove-orphans
docker compose up -d --quiet-pull

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

playground topic produce --topic users --quickstart users_schema --derive-value-schema-as AVRO --nb-messages 10000 --key User%g

connector_name="Neo4jSink_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

# https://neo4j.com/docs/kafka/current/sink/
log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
    "connector.class": "Neo4jSink",
    "name": "$connector_name",
    "kafka.auth.mode": "KAFKA_API_KEY",
    "kafka.api.key": "$CLOUD_KEY",
    "kafka.api.secret": "$CLOUD_SECRET",
    "neo4j.uri": "neo4j://$NGROK_HOSTNAME:$NGROK_PORT",
    "neo4j.authentication.type": "BASIC",
    "neo4j.authentication.basic.username": "neo4j",
    "neo4j.authentication.basic.password": "C0nne6tPassw0rd",
    "neo4j.security.encrypted": "false",
    "neo4j.cypher.topic.map": "{\"users\": \"MERGE (u:User {userId: __value.userid}) SET u.registerTime = datetime({epochMillis: toInteger(__value.registertime)}), u.regionId = __value.regionid, u.gender = __value.gender\"}",
    "input.key.format": "STRING",
    "input.data.format": "AVRO",
    "topics": "users",

    "tasks.max": "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

sleep 5

log "Verify data is present in Neo4j using cypher-shell CLI"
docker exec -i neo4j cypher-shell -u neo4j -p C0nne6tPassw0rd << EOF
MATCH (n) RETURN n;
EOF
docker exec -i neo4j cypher-shell -u neo4j -p C0nne6tPassw0rd > /tmp/result.log <<-EOF
MATCH (n) RETURN n;
EOF
cat /tmp/result.log
grep "regionId" /tmp/result.log | grep "MALE"

if [ -z "$GITHUB_RUN_NUMBER" ]
then
     log "Verify data is present in Neo4j http://localhost:7474 (neo4j/C0nne6tPassw0rd)"
     open "http://localhost:7474/"
fi

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name