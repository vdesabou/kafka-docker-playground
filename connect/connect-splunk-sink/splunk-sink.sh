#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh


PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"


playground --output-level WARN container logs --container splunk --wait-for-log "Ansible playbook complete, will begin streaming splunkd_stderr.log" --max-wait 2500
log "SPLUNK has started!"


log "Splunk UI is accessible at http://127.0.0.1:8000 (admin/password)"

# log "Setting minfreemb to 1Gb (by default 5Gb)"
# docker exec splunk bash -c 'sudo /opt/splunk/bin/splunk set minfreemb 1000 -auth "admin:password"'
# docker exec splunk bash -c 'sudo /opt/splunk/bin/splunk restart'
# sleep 60

log "Create topic splunk-qs"
docker exec broker kafka-topics --create --topic splunk-qs --partitions 10 --replication-factor 1 --bootstrap-server broker:9092


log "Creating Splunk sink connector"
playground connector create-or-update --connector splunk-sink  << EOF
{
     "connector.class": "com.splunk.kafka.connect.SplunkSinkConnector",
     "tasks.max": "1",
     "topics": "splunk-qs",
     "splunk.indexes": "main",
     "splunk.hec.uri": "http://splunk:8088",
     "splunk.hec.token": "99582090-3ac3-4db1-9487-e17b17a05081",
     "splunk.sourcetypes": "my_sourcetype",
     "value.converter": "org.apache.kafka.connect.storage.StringConverter"
}
EOF

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
