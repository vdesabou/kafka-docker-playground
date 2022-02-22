#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# make sure control-center is not disabled
unset DISABLE_CONTROL_CENTER

${DIR}/../../reproduction-models/ccloud-environment/start.sh "${PWD}/docker-compose-executable-onprem-to-cloud.yml" -a -b

if [ -f /tmp/delta_configs/env.delta ]
then
     source /tmp/delta_configs/env.delta
else
     logerror "ERROR: /tmp/delta_configs/env.delta has not been generated"
     exit 1
fi


# generate executable-onprem-to-cloud-producer.properties config
sed -e "s|:BOOTSTRAP_SERVERS:|$BOOTSTRAP_SERVERS|g" \
    -e "s|:CLOUD_KEY:|$CLOUD_KEY|g" \
    -e "s|:CLOUD_SECRET:|$CLOUD_SECRET|g" \
    ${DIR}/executable-onprem-to-cloud-producer.properties > ${DIR}/tmp
mv ${DIR}/tmp ${DIR}/executable-onprem-to-cloud-producer.properties

log "Cleanup topics"
set +e
delete_topic executable-products
delete_topic connect-onprem-to-cloud.offsets
delete_topic connect-onprem-to-cloud.status
delete_topic connect-onprem-to-cloud.config
set -e

log "Sending messages to topic executable-products on source OnPREM cluster"
seq 10 | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic executable-products

log "Starting replicator executable"
docker-compose -f ../../reproduction-models/ccloud-environment/docker-compose.yml -f ${PWD}/docker-compose-executable-onprem-to-cloud.yml -f docker-compose-executable-onprem-to-cloud-replicator-repro-topic-sync-true.yml up -d
../../scripts/wait-for-connect-and-controlcenter.sh replicator $@

sleep 50

log "Verify we have received the data in executable-products topic"
timeout 60 docker container exec -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SASL_JAAS_CONFIG="$SASL_JAAS_CONFIG" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" connect bash -c 'kafka-console-consumer --topic executable-products --bootstrap-server $BOOTSTRAP_SERVERS --consumer-property ssl.endpoint.identification.algorithm=https --consumer-property sasl.mechanism=PLAIN --consumer-property security.protocol=SASL_SSL --consumer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=$BASIC_AUTH_CREDENTIALS_SOURCE --from-beginning --max-messages 10'
