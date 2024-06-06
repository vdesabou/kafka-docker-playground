#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

NGROK_AUTH_TOKEN=${NGROK_AUTH_TOKEN:-$1}

display_ngrok_warning

bootstrap_ccloud_environment



set +e
playground topic delete --topic test_sftp_sink
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

connector_name="SftpSink_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Sending messages to topic test_sftp_sink"
playground topic produce -t test_sftp_sink --nb-messages 1000 --forced-value '{"f1":"value%g"}' << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "f1",
      "type": "string"
    }
  ]
}
EOF

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
  "connector.class": "SftpSink",
  "name": "$connector_name",
  "kafka.auth.mode": "KAFKA_API_KEY",
  "kafka.api.key": "$CLOUD_KEY",
  "kafka.api.secret": "$CLOUD_SECRET",
  "topics": "test_sftp_sink",
  "sftp.username":"foo",
  "sftp.password":"pass",
  "sftp.host":"$NGROK_HOSTNAME",
  "sftp.port":"$NGROK_PORT",
  "sftp.working.dir": "/upload",
  "input.data.format" : "AVRO",
  "output.data.format" : "AVRO",
  "time.interval" : "HOURLY",
  "flush.size": "1000",
  "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

sleep 10

log "Listing content of ./upload/topics/test_sftp_sink"
docker exec sftp-server bash -c "ls /home/foo/upload/topics/test_sftp_sink/*/*/*/*"
docker exec sftp-server bash -c "cp /home/foo/upload/topics/test_sftp_sink/*/*/*/*/test_sftp_sink+0+0000000000.avro /tmp/"
docker cp sftp-server:/tmp/test_sftp_sink+0+0000000000.avro /tmp/
playground  tools read-avro-file --file /tmp/test_sftp_sink+0+0000000000.avro


log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name