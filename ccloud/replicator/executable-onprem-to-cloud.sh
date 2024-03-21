#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.3.99"; then
    log "Removing rest.extension.classes from properties files, otherwise getting Failed to find any class that implements interface org.apache.kafka.connect.rest.ConnectRestExtension and which name matches io.confluent.connect.replicator.monitoring.ReplicatorMonitoringExtension"
    head -n -1 executable-onprem-to-cloud-replicator.properties > /tmp/temp.properties ; mv /tmp/temp.properties executable-onprem-to-cloud-replicator.properties
    head -n -1 executable-onprem-to-cloud-replicator-avro.properties > /tmp/temp.properties ; mv /tmp/temp.properties executable-onprem-to-cloud-replicator-avro.properties
fi

# make sure control-center is not disabled
export ENABLE_CONTROL_CENTER=true

playground start-environment --environment ccloud --docker-compose-override-file "${PWD}/docker-compose-executable-onprem-to-cloud.yml" --wait-for-control-center

if [ -f ${DIR}/../../.ccloud/env.delta ]
then
     source ${DIR}/../../.ccloud/env.delta
else
     logerror "ERROR: ${DIR}/../../.ccloud/env.delta has not been generated"
     exit 1
fi


# generate executable-onprem-to-cloud-producer.properties config
sed -e "s|:BOOTSTRAP_SERVERS:|$BOOTSTRAP_SERVERS|g" \
    -e "s|:CLOUD_KEY:|$CLOUD_KEY|g" \
    -e "s|:CLOUD_SECRET:|$CLOUD_SECRET|g" \
    ${DIR}/executable-onprem-to-cloud-producer.properties > ${DIR}/tmp
mv ${DIR}/tmp ${DIR}/executable-onprem-to-cloud-producer.properties

log "Creating topic in Confluent Cloud (auto.create.topics.enable=false)"
set +e
playground topic delete --topic executable-products
sleep 3
playground topic create --topic executable-products
playground topic delete --topic connect-onprem-to-cloud.offsets
playground topic delete --topic connect-onprem-to-cloud.status
playground topic delete --topic connect-onprem-to-cloud.config
set -e

log "Sending messages to topic executable-products on source OnPREM cluster"
playground topic produce -t executable-products --nb-messages 10 << 'EOF'
%g
EOF

log "Starting replicator executable"
docker compose -f ../../ccloud/environment/docker-compose.yml -f ${PWD}/docker-compose-executable-onprem-to-cloud.yml -f docker-compose-executable-onprem-to-cloud-replicator.yml up -d
wait_container_ready replicator


sleep 50

log "Verify we have received the data in executable-products topic"
playground topic consume --topic executable-products --min-expected-messages 10 --timeout 60