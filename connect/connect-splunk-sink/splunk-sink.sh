#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -z "$TAG_BASE" ] && version_gt $TAG_BASE "7.9.99" && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "2.1.99"
then
     logwarn "minimal supported connector version is 2.2.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.0.html#supported-connector-versions-in-cp-8-0"
     exit 111
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"


playground container logs --container splunk --wait-for-log "Ansible playbook complete, will begin streaming splunkd_stderr.log" --max-wait 600
log "SPLUNK has started!"


log "Splunk UI is accessible at http://127.0.0.1:8000 (admin/password)"

# log "Setting minfreemb to 1Gb (by default 5Gb)"
# docker exec splunk bash -c 'sudo /opt/splunk/bin/splunk set minfreemb 1000 -auth "admin:password"'
# docker exec splunk bash -c 'sudo /opt/splunk/bin/splunk restart'
# sleep 60

log "Sending messages to topic splunk-qs"
playground topic produce -t splunk-qs --nb-messages 3 << 'EOF'
{"store":{"book":[{"category":"reference", "sold": false,"author":"Nigel Rees","title":"Sayings of the Century","price":8.95},{"category":"fiction","author":"Evelyn Waugh","title":"Sword of Honour","price":12.99},{"category":"fiction","author":"J. R. R. Tolkien","title":"The Lord of the Rings","act": null, "isbn":"0-395-19395-8","price":22.99}],"bicycle":{"color":"red","price":19.95}}}
EOF

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
     "value.converter":"org.apache.kafka.connect.json.JsonConverter",
     "value.converter.schemas.enable":"false"
}
EOF

log "Sleeping 80 seconds"
sleep 80

log "Verify data is in splunk"
docker exec splunk bash -c 'sudo /opt/splunk/bin/splunk search "source=\"http:splunk_hec_token\"" -auth "admin:password"' > /tmp/result.log  2>&1
cat /tmp/result.log
grep "Sword of Honour" /tmp/result.log
