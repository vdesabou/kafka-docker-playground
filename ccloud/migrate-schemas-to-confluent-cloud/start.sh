#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.2.0"; then
    logwarn "WARN: Audit logs is only available from Confluent Platform 5.2.0"
    exit 111
fi

# make sure control-center is not disabled
export ENABLE_CONTROL_CENTER=true

playground start-environment --environment ccloud --docker-compose-override-file "${PWD}/docker-compose-executable-onprem-to-cloud.yml" --wait-for-control-center



# generate executable-onprem-to-cloud-producer.properties config
sed -e "s|:BOOTSTRAP_SERVERS:|$BOOTSTRAP_SERVERS|g" \
    -e "s|:CLOUD_KEY:|$CLOUD_KEY|g" \
    -e "s|:CLOUD_SECRET:|$CLOUD_SECRET|g" \
    ${DIR}/executable-onprem-to-cloud-producer.properties > ${DIR}/tmp
mv ${DIR}/tmp ${DIR}/executable-onprem-to-cloud-producer.properties

sed -e "s|:SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO:|$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO|g" \
    -e "s|:SCHEMA_REGISTRY_URL:|$SCHEMA_REGISTRY_URL|g" \
    ${DIR}/executable-onprem-to-cloud-replicator.properties > ${DIR}/tmp
mv ${DIR}/tmp ${DIR}/executable-onprem-to-cloud-replicator.properties

set +e
curl -X DELETE -u $SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO $SCHEMA_REGISTRY_URL/subjects/executable-products-value
set -e

log "Verify there is no subject defined on destination SR: WARNING: output should be empty []"
curl -u $SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO $SCHEMA_REGISTRY_URL/subjects

check_if_continue

# delete subjects as required
# curl -X DELETE -u $SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO $SCHEMA_REGISTRY_URL/subjects/my-existing-subject
# or ccloud schema-registry schema delete --subject my-existing-subject --version latest

log "Set the destination Schema Registry to IMPORT mode"
curl -u $SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO -X PUT -H "Content-Type: application/json" "$SCHEMA_REGISTRY_URL/mode" --data '{"mode": "IMPORT"}'

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
playground topic produce -t orders --nb-messages 3 << 'EOF'
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
docker compose -f ../../ccloud/environment/docker-compose.yml -f ${PWD}/docker-compose-executable-onprem-to-cloud.yml -f docker-compose-executable-onprem-to-cloud-replicator.yml up -d
wait_container_ready replicator

sleep 50

log "Verify we have the schema"
curl -u $SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO $SCHEMA_REGISTRY_URL/subjects

log "Set the source Schema Registry to READONLY mode"
curl -X PUT -H "Content-Type: application/json" "http://localhost:8081/mode" --data '{"mode": "READONLY"}'

log "Set the destination Schema Registry to READWRITE mode"
curl -u $SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO -X PUT -H "Content-Type: application/json" "$SCHEMA_REGISTRY_URL/mode" --data '{"mode": "READWRITE"}'

