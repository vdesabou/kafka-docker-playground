#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.2.0"; then
    logwarn "WARN: Audit logs is only available from Confluent Platform 5.2.0"
    exit 0
fi

#############
${DIR}/../../ccloud/environment/start.sh "${PWD}/docker-compose-executable-onprem-to-cloud.yml" -a -b

if [ -f /tmp/delta_configs/env.delta ]
then
     source /tmp/delta_configs/env.delta
else
     logerror "ERROR: /tmp/delta_configs/env.delta has not been generated"
     exit 1
fi
#############

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
delete_topic executable-products
sleep 3
create_topic executable-products
delete_topic connect-onprem-to-cloud.offsets
delete_topic connect-onprem-to-cloud.status
delete_topic connect-onprem-to-cloud.config
set -e

# Avoid java.lang.OutOfMemoryError: Java heap space
docker container restart connect
sleep 5

log "Sending messages to topic executable-products on source OnPREM cluster"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic executable-products --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"name","type":"string"},
{"name":"price", "type": "float"}, {"name":"quantity", "type": "int"}]}' << EOF
{"name": "scissors", "price": 2.75, "quantity": 3}
{"name": "tape", "price": 0.99, "quantity": 10}
{"name": "notebooks", "price": 1.99, "quantity": 5}
EOF

log "Starting replicator executable (logs are in /tmp/replicator.log):"
# run in detach mode -d
docker exec -d connect bash -c 'export CLASSPATH=/etc/kafka-connect/jars/replicator-rest-extension-*.jar; replicator --consumer.config /etc/kafka/executable-onprem-to-cloud-consumer.properties --producer.config /etc/kafka/executable-onprem-to-cloud-producer.properties  --replication.config /etc/kafka/executable-onprem-to-cloud-replicator.properties  --cluster.id executable-onprem-to-cloud --whitelist _schemas > /tmp/replicator.log 2>&1'

sleep 50

log "Verify we have the schema"
curl -u $SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO $SCHEMA_REGISTRY_URL/subjects

log "Set the source Schema Registry to READONLY mode"
curl -X PUT -H "Content-Type: application/json" "http://localhost:8081/mode" --data '{"mode": "READONLY"}'

log "Set the destination Schema Registry to READWRITE mode"
curl -u $SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO -X PUT -H "Content-Type: application/json" "$SCHEMA_REGISTRY_URL/mode" --data '{"mode": "READWRITE"}'

log "Copying replicator logs to /tmp/replicator.log"
docker cp connect:/tmp/replicator.log /tmp/replicator.log
