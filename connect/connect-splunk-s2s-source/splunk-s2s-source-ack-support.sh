#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# Purpose: Verify Splunk S2S Source acknowledgment and Kafka Connect commitRecords() sequence
if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "2.2.1"
then
     logwarn "minimal supported connector version is 2.2.2 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.1.html#supported-connector-versions-in-cp-8-1"
     exit 111
fi

log "Starting Splunk S2S Source ACK verification test"

# -------------------------------------------------------
# 1️⃣  Setup Environment
# -------------------------------------------------------
PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

playground topic create --topic splunk-s2s-events

log "Deploying Splunk S2S Source connector with ack support"
playground connector create-or-update --connector splunk-s2s-source-ack-test << EOF
{
  "connector.class": "io.confluent.connect.splunk.s2s.SplunkS2SSourceConnector",
  "tasks.max": "1",
  "kafka.topic": "splunk-s2s-events",
  "splunk.collector.index.default": "default-index",
  "splunk.s2s.port": "9997",
  "splunk.s2s.enable.ack": "true",
  "key.converter": "org.apache.kafka.connect.storage.StringConverter",
  "value.converter": "org.apache.kafka.connect.json.JsonConverter",
  "value.converter.schemas.enable": "false",
  "confluent.topic.bootstrap.servers": "broker:9092",
  "confluent.topic.replication.factor": "1"
}
EOF

sleep 5

log "Enabling ack support in splunk forwarder and restarting."
docker exec splunk-uf bash -c "echo -e '[tcpout]\ndefaultGroup = default-autolb-group\n\n[tcpout:default-autolb-group]\nserver = indexer1:9997\nuseACK = true' > /opt/splunkforwarder/etc/system/local/outputs.conf"
docker exec -i splunk-uf bash -c "./bin/splunk restart --answer-yes --no-prompt && \
  echo 'Waiting for Splunk UF to start...' && \
  until ./bin/splunk status | grep -q 'splunkd is running'; do
  sleep 2
  done && echo '✅ Splunk UF is up and running.'"

sleep 30

docker exec -i splunk-uf bash -c "echo '' > /opt/splunkforwarder/splunk-s2s-test.log"

log "Configure the UF to monitor the splunk-s2s-test.log file"
docker exec -i splunk-uf sudo ./bin/splunk add monitor -source /opt/splunkforwarder/splunk-s2s-test.log -auth admin:password

log "Configure the UF to connect to Splunk S2S Source connector"
docker exec -i splunk-uf sudo ./bin/splunk add forward-server connect:9997

sleep 20


# -------------------------------------------------------
# 2️⃣  Produce Simulated Splunk Events
# -------------------------------------------------------
docker exec -i splunk-uf bash -c "echo 'test event 1' > /opt/splunkforwarder/splunk-s2s-test.log"
docker exec -i splunk-uf bash -c "echo 'test event 2' >> /opt/splunkforwarder/splunk-s2s-test.log"
docker exec -i splunk-uf bash -c "echo 'test event 3' >> /opt/splunkforwarder/splunk-s2s-test.log"
# -------------------------------------------------------
# 3️⃣  Verify Kafka Records
# -------------------------------------------------------
log "Verifying topic splunk-s2s-events has expected records"
playground topic consume --topic splunk-s2s-events --timeout 20 --min-expected-messages 3 --grep "test event" --max-messages=5000 
events=$(playground topic consume --topic splunk-s2s-events --timeout 20 --min-expected-messages 3 --grep "test event" --max-messages=5000 \
  | grep -o '"event":"test event [0-9]*"' \
  | sed -E 's/.*"event":"(.*)".*/\1/')

if [[ "$events" == $'test event 1\ntest event 2\ntest event 3' ]]; then
  log "✅ No duplicate events found"
else
  logerror "❌ Message mismatch — potential commit/ACK failure"
  exit 1
fi

# -------------------------------------------------------
# ✅ Done
# -------------------------------------------------------
log "✅ Splunk S2S Source ACK Test Passed Successfully"
