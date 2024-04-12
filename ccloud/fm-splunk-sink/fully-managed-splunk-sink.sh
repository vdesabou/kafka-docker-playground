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

set +e
playground topic delete --topic splunk-qs
sleep 3
playground topic create --topic splunk-qs --nb-partitions 3
set -e

# Verify SPLUNK has started within MAX_WAIT seconds
MAX_WAIT=2500
CUR_WAIT=0
log "⌛ Waiting up to $MAX_WAIT seconds for SPLUNK to start"
docker container logs splunk > /tmp/out.txt 2>&1
while [[ ! $(cat /tmp/out.txt) =~ "Ansible playbook complete, will begin streaming splunkd_stderr.log" ]]; do
sleep 10
docker container logs splunk > /tmp/out.txt 2>&1
CUR_WAIT=$(( CUR_WAIT+10 ))
if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
     logerror "ERROR: The logs in splunk container do not show 'Ansible playbook complete, will begin streaming splunkd_stderr.log' after $MAX_WAIT seconds. Please troubleshoot with 'docker container ps' and 'docker container logs'.\n"
     exit 1
fi
done
log "SPLUNK has started!"


log "Splunk UI is accessible at http://127.0.0.1:8000 (admin/password)"


# log "Setting minfreemb to 1Gb (by default 5Gb)"
# docker exec splunk bash -c 'sudo /opt/splunk/bin/splunk set minfreemb 1000 -auth "admin:password"'
# docker exec splunk bash -c 'sudo /opt/splunk/bin/splunk restart'
# sleep 60

log "Waiting for ngrok to start"
while true
do
  container_id=$(docker ps -q -f name=ngrok)
  if [ -n "$container_id" ]
  then
    status=$(docker inspect --format '{{.State.Status}}' $container_id)
    if [ "$status" = "running" ]; then
      break
    fi
  fi
  log "Waiting for container ngrok to start..."
  sleep 5
done
log "Getting ngrok hostname and port"
NGROK_URL=$(curl --silent http://127.0.0.1:4040/api/tunnels | jq -r '.tunnels[0].public_url')
NGROK_HOSTNAME=$(echo $NGROK_URL | cut -d "/" -f3 | cut -d ":" -f 1)
NGROK_PORT=$(echo $NGROK_URL | cut -d "/" -f3 | cut -d ":" -f 2)

connector_name="SplunkSink_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
     "connector.class": "SplunkSink",
     "name": "$connector_name",
     "kafka.auth.mode": "KAFKA_API_KEY",
     "kafka.api.key": "$CLOUD_KEY",
     "kafka.api.secret": "$CLOUD_SECRET",
     "input.data.format": "STRING",
     "splunk.indexes": "main",
     "splunk.hec.uri": "http://$NGROK_HOSTNAME:$NGROK_PORT",
     "splunk.hec.token": "99582090-3ac3-4db1-9487-e17b17a05081",
     "splunk.sourcetypes": "my_sourcetype",
     "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 600

log "Sending messages to topic splunk-qs"
playground topic produce -t splunk-qs --nb-messages 3 << 'EOF'
This is a test with Splunk %g
EOF

log "Sleeping 60 seconds"
sleep 60

log "Verify data is in splunk"
docker exec splunk bash -c 'sudo /opt/splunk/bin/splunk search "source=\"http:splunk_hec_token\"" -auth "admin:password"' > /tmp/result.log  2>&1
cat /tmp/result.log
grep "This is a test with Splunk" /tmp/result.log

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name