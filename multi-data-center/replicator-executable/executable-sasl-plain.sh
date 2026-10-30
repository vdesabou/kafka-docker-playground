#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.3.99"; then
    log "Removing rest.extension.classes from properties files, otherwise getting Failed to find any class that implements interface org.apache.kafka.connect.rest.ConnectRestExtension and which name matches io.confluent.connect.replicator.monitoring.ReplicatorMonitoringExtension"
    head -n -1 replication-europe.properties > /tmp/temp.properties ; mv /tmp/temp.properties replication-europe.properties
    head -n -1 replication-us.properties > /tmp/temp.properties ; mv /tmp/temp.properties replication-us.properties
fi

playground start-environment --environment mdc-sasl-plain --docker-compose-override-file "${PWD}/docker-compose.mdc-sasl-plain.replicator.yml"

log "Sending sales in Europe cluster"
playground topic produce --cluster europe --topic sales_EUROPE --nb-messages 10 --value "european_sale_%g ${RANDOM}"

log "Sending sales in US cluster"
playground topic produce --cluster us --topic sales_US --nb-messages 10 --value "us_sale_%g ${RANDOM}"

playground container restart -c replicator-europe
playground container restart -c replicator-us

wait_container_ready replicator-us
wait_container_ready replicator-europe

log "Verify we have received the US sales in EUROPE"
playground topic wait-for-records --cluster europe --topic sales_US --min-expected-messages 10 --max-wait 240
playground topic consume --cluster europe --topic sales_US --min-expected-messages 10 --timeout 60

log "Verify we have received the European sales in the US"
playground topic wait-for-records --cluster us --topic sales_EUROPE --min-expected-messages 10 --max-wait 240
playground topic consume --cluster us --topic sales_EUROPE --min-expected-messages 10 --timeout 60
