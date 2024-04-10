#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

NGROK_AUTH_TOKEN=${NGROK_AUTH_TOKEN:-$1}

display_ngrok_warning

bootstrap_ccloud_environment



set +e
playground topic delete --topic sftp-testing-topic
set -e

docker compose build
docker compose down -v --remove-orphans
docker compose up -d --quiet-pull

sleep 5

docker exec sftp-server bash -c "
mkdir -p /chroot/home/foo/upload/input
mkdir -p /chroot/home/foo/upload/error
mkdir -p /chroot/home/foo/upload/finished

chown -R foo /chroot/home/foo/upload
"

echo $'id,first_name,last_name,email,gender,ip_address,last_login,account_balance,country,favorite_color\n1,Salmon,Baitman,sbaitman0@feedburner.com,Male,120.181.75.98,2015-03-01T06:01:15Z,17462.66,IT,#f09bc0\n2,Debby,Brea,dbrea1@icio.us,Female,153.239.187.49,2018-10-21T12:27:12Z,14693.49,CZ,#73893a' > csv-sftp-source.csv
docker cp csv-sftp-source.csv sftp-server:/chroot/home/foo/upload/input/
rm -f csv-sftp-source.csv

log "Getting ngrok hostname and port"
NGROK_URL=$(curl --silent http://127.0.0.1:4040/api/tunnels | jq -r '.tunnels[0].public_url')
NGROK_HOSTNAME=$(echo $NGROK_URL | cut -d "/" -f3 | cut -d ":" -f 1)
NGROK_PORT=$(echo $NGROK_URL | cut -d "/" -f3 | cut -d ":" -f 2)

connector_name="SftpSource_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
     "connector.class": "SftpSource",
     "name": "$connector_name",
     "kafka.auth.mode": "KAFKA_API_KEY",
     "kafka.api.key": "$CLOUD_KEY",
     "kafka.api.secret": "$CLOUD_SECRET",
     "output.data.format": "JSON",
     "input.file.parser.format": "CSV",
     "kafka.topic": "sftp-testing-topic",
     "schema.generation.enabled": "true",
     "schema.generation.key.name": "key",
     "schema.generation.value.name": "value",

     "input.path": "/home/foo/upload/input",
     "error.path": "/home/foo/upload/error",
     "finished.path": "/home/foo/upload/finished",
     "input.file.pattern": ".*\\\\.csv",

     "sftp.username":"foo",
     "sftp.password":"pass",
     "sftp.host":"$NGROK_HOSTNAME",
     "sftp.port":"$NGROK_PORT",

     "csv.first.row.as.header": "true",

     "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 600


log "Verifying topic sftp-testing-topic"
playground topic consume --topic sftp-testing-topic --min-expected-messages 2 --timeout 60


log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name