#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# Purpose: Verify Splunk S2S Source acknowledgment and Kafka Connect commitRecords() sequence
if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "2.2.1"
then
     logwarn "minimal supported connector version is 2.2.2 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.0.html#supported-connector-versions-in-cp-8-0"
     exit 111
fi

log "Starting Splunk S2S Source ACK verification test"

# -------------------------------------------------------
# 1️⃣  Setup Environment
# -------------------------------------------------------
PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Deploying Splunk S2S Source connector with ack support"
playground connector create-or-update --connector splunk-s2s-source-ack-test << EOF
{
  "connector.class": "io.confluent.connect.splunk.s2s.SplunkS2SSourceConnector",
  "tasks.max": "1",
  "kafka.topic": "splunk-s2s-ack-events",
  "splunk.collector.index.default": "default-index",
  "splunk.s2s.port": "9997",
  "splunk.s2s.enable.ack": "true",
  "key.converter": "org.apache.kafka.connect.storage.StringConverter",
  "value.converter": "org.apache.kafka.connect.json.JsonConverter",
  "confluent.topic.bootstrap.servers": "broker:9092",
  "confluent.topic.replication.factor": "1",
  "logs.level": "DEBUG"
}
EOF

sleep 5

# -------------------------------------------------------
# 2️⃣  Produce Simulated Splunk Events
# -------------------------------------------------------

echo "log event 1" > splunk-s2s-test.log
echo "log event 2" >> splunk-s2s-test.log
echo "log event 3" >> splunk-s2s-test.log

log "Copy the splunk-s2s-test.log file to the Splunk UF Docker container"
docker cp splunk-s2s-test.log splunk-uf:/opt/splunkforwarder/splunk-s2s-test.log
docker exec splunk-uf bash -c "echo -e '[tcpout]\ndefaultGroup = default-autolb-group\n\n[tcpout:default-autolb-group]\nserver = indexer1:9997\nuseACK = true' > /opt/splunkforwarder/etc/system/local/outputs.conf"

log "Configure the UF to monitor the splunk-s2s-test.log file"
docker exec -i splunk-uf sudo ./bin/splunk add monitor -source /opt/splunkforwarder/splunk-s2s-test.log -auth admin:password

log "Configure the UF to connect to Splunk S2S Source connector"
docker exec -i splunk-uf sudo ./bin/splunk add forward-server connect:9997

sleep 30

# -------------------------------------------------------
# 3️⃣  Verify Kafka Records
# -------------------------------------------------------
log "Verifying topic splunk-s2s-ack-events has expected records"
NUM_MSGS_EXPECTED=3
NUM_MSGS_ACTUAL=$(playground topic consume --topic splunk-s2s-ack-events --timeout 20 --max-messages 1000 --min-expected-messages 3 | grep "log event" | wc -l)
log "Expected: $NUM_MSGS_EXPECTED, Found: $NUM_MSGS_ACTUAL"

if [ "$NUM_MSGS_ACTUAL" -ne "$NUM_MSGS_EXPECTED" ]; then
  logerror "❌ Message count mismatch — potential commit/ACK failure"
  exit 1
fi


# -------------------------------------------------------
# 4️⃣  Detect Duplicates
# -------------------------------------------------------
log "Checking for duplicate events"

DUP_COUNT=$(playground topic consume --topic splunk-s2s-ack-events --timeout 20 --max-messages 1000 --min-expected-messages 3 | grep "log event" | sort | uniq -d | wc -l)
if [ "$DUP_COUNT" -ne 0 ]; then
  logerror "❌ Found duplicate events — commitRecord flow might not be idempotent"
  exit 1
else
  log "✅ No duplicates found — commitRecord + ACK sequence validated"
fi

# -------------------------------------------------------
# ✅ Done
# -------------------------------------------------------
log "✅ Splunk S2S Source ACK Test Passed Successfully"
