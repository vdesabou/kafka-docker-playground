#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

ICEBERG_VERSION=${ICEBERG_VERSION:-"1.9.2"}
cd ../../ccloud/custom-connector-connect-iceberg-sink
if [ ! -f iceberg-iceberg-kafka-connect-$ICEBERG_VERSION.zip ]
then
    log "Downloading iceberg-iceberg-kafka-connect-$ICEBERG_VERSION.zip from confluent hub"
    wget -q https://hub-downloads.confluent.io/api/plugins/iceberg/iceberg-kafka-connect/versions/$ICEBERG_VERSION/iceberg-iceberg-kafka-connect-$ICEBERG_VERSION.zip
fi

plugin_name="pg_${USER}_apache_iceberg_sink"

bootstrap_ccloud_environment

ENVIRONMENT=$(playground state get ccloud.ENVIRONMENT)

set +e
for row in $(confluent ccpm plugin list --environment $ENVIRONMENT --output json | jq -r '.[] | @base64'); do
    _jq() {
    echo ${row} | base64 -d | jq -r ${1}
    }
    
    id=$(echo $(_jq '.id'))
    name=$(echo $(_jq '.name'))

    if [[ "$name" = "$plugin_name" ]]
    then
        plugin_id=$id
        log "deleting plugin $plugin_id ($name)"
        confluent ccpm plugin delete $plugin_id --environment $ENVIRONMENT --force
    fi
done
if [ "$plugin_id" != "" ]
then
    for row in $(confluent ccpm plugin version list --plugin $plugin_id --environment $ENVIRONMENT --output json | jq -r '.[] | @base64'); do
        _jq() {
        echo ${row} | base64 -d | jq -r ${1}
        }
        
        plugin_version_id=$(echo $(_jq '.id'))
        name=$(echo $(_jq '.name'))

        log "deleting plugin version $plugin_version_id"
        confluent ccpm plugin version delete $plugin_version_id --plugin $plugin_id --environment $ENVIRONMENT --force
    done
fi
set -e

log "Create a custom plugin $plugin_name in environment $ENVIRONMENT"
output=$(confluent ccpm plugin create --name $plugin_name --description "Custom Iceberg Sink Connector" --cloud "aws" --environment $ENVIRONMENT --output json)
ret=$?
if [ $ret -eq 0 ]
then
    plugin_id=$(echo $output | jq -r '.id')
    log "custom plugin $plugin_name ($plugin_id) was successfully created!"
else
    logerror "❌ command failed with error code $ret!"
    echo "$output"
    exit 1
fi

log "Uploading custom plugin $plugin_name version $ICEBERG_VERSION with plugin id $plugin_id in environment $ENVIRONMENT"
output=$(confluent ccpm plugin version create --plugin $plugin_id --plugin-file "iceberg-iceberg-kafka-connect-$ICEBERG_VERSION.zip" --version "$ICEBERG_VERSION" --connector-classes "org.apache.iceberg.connect.IcebergSinkConnector:SINK" --sensitive-properties "iceberg.kafka.sasl.jaas.config" --environment $ENVIRONMENT --output json)
ret=$?
if [ $ret -eq 0 ]
then
    plugin_version_id=$(echo $output | jq -r '.id')
    log "custom plugin version $ICEBERG_VERSION with id $plugin_version_id was successfully created!"
else
    logerror "❌ command failed with error code $ret!"
    echo "$output"
    exit 1
fi

function cleanup_resources {
    log "Do you want to delete the custom plugin $plugin_name ($plugin_id), plugin version $plugin_version_id and custom connector $connector_name ?"
    check_if_continue

    playground connector delete --connector $connector_name
    confluent ccpm plugin version delete $plugin_version_id --plugin $plugin_id --environment $ENVIRONMENT --force
    confluent ccpm plugin delete $plugin_id --environment $ENVIRONMENT --force
}
trap cleanup_resources EXIT

NGROK_AUTH_TOKEN=${NGROK_AUTH_TOKEN:-$1}

display_ngrok_warning

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
  "confluent.custom.plugin.version": "$ICEBERG_VERSION",
  "confluent.custom.connection.endpoints": "$NGROK_HOSTNAME:$NGROK_PORT:TCP;$NGROK_HOSTNAME2:$NGROK_PORT2:TCP",
  "connector.class": "org.apache.iceberg.connect.IcebergSinkConnector",

  "kafka.api.key": "$CLOUD_KEY",
  "kafka.api.secret": "$CLOUD_SECRET",
  "name": "$connector_name",
  "tasks.max": "1",
  "topics": "payments",

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

playground connector show-lag --max-wait 300 --connector $connector_name

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