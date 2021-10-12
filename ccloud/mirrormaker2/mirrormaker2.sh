#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../ccloud/environment/start.sh "${PWD}/docker-compose.plaintext.yml" -a -b

if [ -f /tmp/delta_configs/env.delta ]
then
     source /tmp/delta_configs/env.delta
else
     logerror "ERROR: /tmp/delta_configs/env.delta has not been generated"
     exit 1
fi

# generate connect-mirror-maker.properties config
sed -e "s|:BOOTSTRAP_SERVERS:|$BOOTSTRAP_SERVERS|g" \
    -e "s|:CLOUD_KEY:|$CLOUD_KEY|g" \
    -e "s|:CLOUD_SECRET:|$CLOUD_SECRET|g" \
    ${DIR}/connect-mirror-maker-template.properties > ${DIR}/connect-mirror-maker.properties

log "Creating topic sales_A in Confluent Cloud"
set +e
delete_topic sales_A
delete_topic mm2-configs.A.internal
delete_topic mm2-offsets.A.internal
delete_topic mm2-status.A.internal
sleep 3
create_topic sales_A
set -e

log "Start MirrorMaker2 (logs are in mirrormaker.log):"
docker cp ${DIR}/connect-mirror-maker.properties connect:/tmp/connect-mirror-maker.properties
docker exec -i connect /usr/bin/connect-mirror-maker /tmp/connect-mirror-maker.properties > mirrormaker.log 2>&1 &

log "sleeping 30 seconds"
sleep 30

log "Sending messages in A cluster (OnPrem)"
seq -f "A_sale_%g ${RANDOM}" 20 | docker container exec -i broker1 kafka-console-producer --broker-list localhost:9092 --topic sales_A

log "Consumer with group my-consumer-group reads 10 messages in A cluster"
docker exec -i connect bash -c "kafka-console-consumer --bootstrap-server broker1:9092 --whitelist 'sales_A' --from-beginning --max-messages 10 --consumer-property group.id=my-consumer-group"

log "sleeping 70 seconds"
sleep 70

log "Consumer with group my-consumer-group reads 10 messages in B cluster (Confluent Cloud), it should start from previous offset"
timeout 60 docker container exec -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SASL_JAAS_CONFIG="$SASL_JAAS_CONFIG" connect bash -c 'kafka-console-consumer --topic sales_A --bootstrap-server $BOOTSTRAP_SERVERS --consumer-property sasl.mechanism=PLAIN --consumer-property security.protocol=SASL_SSL --consumer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --max-messages 10 --consumer-property group.id=my-consumer-group'


# FIXTHIS: not working getting:
# [2021-10-12 09:23:39,996] INFO [Consumer clientId=consumer-my-consumer-group-1, groupId=my-consumer-group] Found no committed offset for partition sales_A-3 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator)
# [2021-10-12 09:23:39,996] INFO [Consumer clientId=consumer-my-consumer-group-1, groupId=my-consumer-group] Found no committed offset for partition sales_A-2 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator)
# [2021-10-12 09:23:39,996] INFO [Consumer clientId=consumer-my-consumer-group-1, groupId=my-consumer-group] Found no committed offset for partition sales_A-1 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator)
# [2021-10-12 09:23:39,996] INFO [Consumer clientId=consumer-my-consumer-group-1, groupId=my-consumer-group] Found no committed offset for partition sales_A-0 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator)
# [2021-10-12 09:23:39,996] INFO [Consumer clientId=consumer-my-consumer-group-1, groupId=my-consumer-group] Found no committed offset for partition sales_A-5 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator)
# [2021-10-12 09:23:39,997] INFO [Consumer clientId=consumer-my-consumer-group-1, groupId=my-consumer-group] Found no committed offset for partition sales_A-4 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator)