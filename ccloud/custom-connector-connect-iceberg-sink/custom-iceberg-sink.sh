#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f tabular-iceberg-kafka-connect-0.6.19.zip ]
then
    log "Downloading tabular-iceberg-kafka-connect-0.6.19.zip from confluent hub"
    wget -q https://d2p6pa21dvn84.cloudfront.net/api/plugins/tabular/iceberg-kafka-connect/versions/0.6.19/tabular-iceberg-kafka-connect-0.6.19.zip
fi

plugin_name="pg_${USER}_tabular_iceberg_sink_0_6_19"

set +e
for row in $(confluent connect custom-plugin list --output json | jq -r '.[] | @base64'); do
    _jq() {
    echo ${row} | base64 -d | jq -r ${1}
    }
    
    id=$(echo $(_jq '.id'))
    name=$(echo $(_jq '.name'))

    if [[ "$name" = "$plugin_name" ]]
    then
        log "deleting plugin $id ($name)"
        confluent connect custom-plugin delete $id --force
    fi
done
set -e

log "Uploading custom plugin $plugin_name"
confluent connect custom-plugin create $plugin_name --plugin-file tabular-iceberg-kafka-connect-0.6.19.zip --connector-class io.tabular.iceberg.connect.IcebergSinkConnector --connector-type SINK --sensitive-properties "iceberg.kafka.sasl.jaas.config"
ret=$?

function cleanup_resources {
    log "Do you want to delete the custom plugin $plugin_name ($plugin_id) and custom connector $connector_name ?"
    check_if_continue

    playground connector delete --connector $connector_name
    confluent connect custom-plugin delete $plugin_id --force
}
trap cleanup_resources EXIT

set -e
if [ $ret -eq 0 ]
then
    found=0
    set +e
    for row in $(confluent connect custom-plugin list --output json | jq -r '.[] | @base64'); do
        _jq() {
        echo ${row} | base64 -d | jq -r ${1}
        }
        
        id=$(echo $(_jq '.id'))
        name=$(echo $(_jq '.name'))

        if [[ "$name" = "$plugin_name" ]]
        then
            plugin_id="$id"
            log "custom plugin $plugin_name ($plugin_id) was successfully uploaded!"
            found=1
            break
        fi
    done
else
    logerror "❌ command failed with error code $ret!"
    exit 1
fi
set -e
if [ $found -eq 0 ]
then
     logerror "❌ plugin could not be uploaded !"
     exit 1
fi

NGROK_AUTH_TOKEN=${NGROK_AUTH_TOKEN:-$1}

display_ngrok_warning

bootstrap_ccloud_environment



set +e
playground topic delete --topic payments
playground topic delete --topic control-iceberg

sleep 3

playground topic create --topic control-iceberg
set -e

docker compose build
docker compose down -v --remove-orphans
docker compose up -d --quiet-pull

sleep 30

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

      NGROK_URL2=$(curl --silent http://127.0.0.1:4040/api/tunnels | jq -r '.tunnels[1].public_url')
      NGROK_HOSTNAME2=$(echo $NGROK_URL2 | cut -d "/" -f3 | cut -d ":" -f 1)
      NGROK_PORT2=$(echo $NGROK_URL2 | cut -d "/" -f3 | cut -d ":" -f 2)

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


log "Sending messages to topic payments"
playground topic produce -t payments --nb-messages $(wc -l <"../../ccloud/custom-connector-connect-iceberg-sink/data/transactions.json") --value ../../ccloud/custom-connector-connect-iceberg-sink/data/transactions.json

connector_name="ICEBERG_SINK_CUSTOM_$USER"
set +e
log "Deleting confluent cloud custom connector $connector_name, it might fail..."
playground connector delete --connector $connector_name
set -e


log "Creating Iceberg sink connector"
playground connector create-or-update --connector $connector_name << EOF
{
  "confluent.connector.type": "CUSTOM",
  "confluent.custom.plugin.id": "$plugin_id",
  "confluent.custom.connection.endpoints": "$NGROK_HOSTNAME:$NGROK_PORT:TCP;$NGROK_HOSTNAME2:$NGROK_PORT2:TCP",
  "connector.class": "io.tabular.iceberg.connect.IcebergSinkConnector",

  "kafka.api.key": "$CLOUD_KEY",
  "kafka.api.secret": "$CLOUD_SECRET",
  "name": "$connector_name",
  "tasks.max": "1",
  "topics": "payments",
  "connector.class": "io.tabular.iceberg.connect.IcebergSinkConnector",

  "iceberg.catalog.s3.endpoint": "http://$NGROK_HOSTNAME2:$NGROK_PORT2",
  "iceberg.catalog.s3.secret-access-key": "minioadmin",
  "iceberg.catalog.s3.access-key-id": "minioadmin",
  "iceberg.catalog.s3.path-style-access": "true",
  "iceberg.catalog.uri": "http://$NGROK_HOSTNAME:$NGROK_PORT",
  "iceberg.catalog.warehouse": "s3://warehouse/",
  "iceberg.catalog.client.region": "eu-west-1",
  "iceberg.catalog.type": "rest",
  "iceberg.control.commit.interval-ms": "1000",
  "iceberg.tables.auto-create-enabled": "true",
  "iceberg.tables": "orders.payments",
  "iceberg.kafka.sasl.jaas.config":"org.apache.kafka.common.security.plain.PlainLoginModule required username=\"$CLOUD_KEY\" password=\"$CLOUD_SECRET\";",
  "value.converter.schemas.enable": "false",
  "value.converter": "org.apache.kafka.connect.json.JsonConverter",
  "key.converter": "org.apache.kafka.connect.storage.StringConverter",
  "schemas.enable": "false",

  "errors.tolerance": "all",
  "errors.deadletterqueue.topic.name": "dlq",
  "errors.deadletterqueue.topic.replication.factor": "3",
  "errors.deadletterqueue.context.headers.enable": "true",
  "errors.log.enable": "true",
  "errors.log.include.messages": "true"
}
EOF

sleep 30

playground connector show-lag --max-wait 300

if [ -z "$GITHUB_RUN_NUMBER" ]
then
  # doesn't work on github actions
  # not running with github actions
  log "You can open the jupyter lab at http://localhost:8888/lab/tree/notebooks and use the sample notebook in notebooks/iceberg.ipynb to query the table"

  log "Verify data is in Iceberg"
  docker exec -i spark-iceberg spark-sql << EOF
SELECT *
FROM orders.payments
LIMIT 10;
EOF
fi