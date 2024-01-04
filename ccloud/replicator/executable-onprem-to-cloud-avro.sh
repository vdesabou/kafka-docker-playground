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

playground start-environment --environment ccloud --docker-compose-override-file "${PWD}/docker-compose-executable-onprem-to-cloud.yml" "-a -b"



# generate executable-onprem-to-cloud-producer-avro.properties config
sed -e "s|:BOOTSTRAP_SERVERS:|$BOOTSTRAP_SERVERS|g" \
    -e "s|:CLOUD_KEY:|$CLOUD_KEY|g" \
    -e "s|:CLOUD_SECRET:|$CLOUD_SECRET|g" \
    ${DIR}/executable-onprem-to-cloud-producer-avro.properties > ${DIR}/tmp
mv ${DIR}/tmp ${DIR}/executable-onprem-to-cloud-producer-avro.properties

# generate executable-onprem-to-cloud-replicator-avro.properties config
sed -e "s|:SCHEMA_REGISTRY_URL:|$SCHEMA_REGISTRY_URL|g" \
    -e "s|:SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO:|$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO|g" \
    ${DIR}/executable-onprem-to-cloud-replicator-avro.properties > ${DIR}/tmp
mv ${DIR}/tmp ${DIR}/executable-onprem-to-cloud-replicator-avro.properties

log "Creating topic in Confluent Cloud (auto.create.topics.enable=false)"
set +e
playground topic delete --topic executable-products-avro
sleep 3
playground topic create --topic executable-products-avro
playground topic delete --topic connect-onprem-to-cloud-avro.offsets
playground topic delete --topic connect-onprem-to-cloud-avro.status
playground topic delete --topic connect-onprem-to-cloud-avro.config
set -e

log "Delete schema for topic"
set +e
curl -X DELETE -u $SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO $SCHEMA_REGISTRY_URL/subjects/executable-products-avro-value
set -e

log "Sending messages to topic executable-products-avro on source OnPREM cluster"
playground topic produce -t executable-products-avro --nb-messages 3 << 'EOF'
{
  "fields": [
    {
      "name": "id",
      "type": "int"
    },
    {
      "name": "product",
      "type": "string"
    },
    {
      "name": "quantity",
      "type": "int"
    },
    {
      "name": "price",
      "type": "float"
    }
  ],
  "name": "myrecord",
  "type": "record"
}
EOF

log "Starting replicator executable"
docker compose -f ../../ccloud/environment/docker-compose.yml -f ${PWD}/docker-compose-executable-onprem-to-cloud.yml -f docker-compose-executable-onprem-to-cloud-avro-replicator.yml up -d
../../scripts/wait-for-connect-and-controlcenter.sh replicator $@

sleep 50

log "Verify we have received the data in executable-products-avro topic"
playground topic consume --topic executable-products-avro --min-expected-messages 3 --timeout 60