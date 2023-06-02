#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh


${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


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

log "Create topic splunk-qs"
docker exec broker kafka-topics --create --topic splunk-qs --partitions 10 --replication-factor 1 --bootstrap-server broker:9092


log "Creating Splunk sink connector"
playground connector create-or-update --connector splunk-sink << EOF
{
               "connector.class": "com.splunk.kafka.connect.SplunkSinkConnector",
               "tasks.max": "1",
               "topics": "splunk-qs",
               "splunk.indexes": "main",
               "splunk.hec.uri": "http://splunk:8088",
               "splunk.hec.token": "99582090-3ac3-4db1-9487-e17b17a05081",
               "splunk.sourcetypes": "my_sourcetype",
               "value.converter": "org.apache.kafka.connect.storage.StringConverter",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }
EOF


log "Sending messages to topic splunk-qs"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic splunk-qs << EOF
This is a test with Splunk 1
This is a test with Splunk 2
This is a test with Splunk 3
EOF

log "Sleeping 60 seconds"
sleep 60

log "Verify data is in splunk"
docker exec splunk bash -c 'sudo /opt/splunk/bin/splunk search "source=\"http:splunk_hec_token\"" -auth "admin:password"' > /tmp/result.log  2>&1
cat /tmp/result.log
grep "This is a test with Splunk" /tmp/result.log
