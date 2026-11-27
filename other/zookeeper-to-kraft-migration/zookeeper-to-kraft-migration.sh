#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# a self-managed ZooKeeper cluster (CP 7.9) migrated to KRaft, the phases of the Confluent documentation:
# https://docs.confluent.io/platform/7.9/installation/migrate-zk-kraft.html
# ZooKeeper is gone in CP 8: with a CP 8 tag (the default), the example uses CP 7.9.11
if version_gt $TAG_BASE "7.9.99"
then
    logwarn "⏪ ZooKeeper is removed in CP 8: the migration runs on CP 7.9.11 (pass --tag 7.6.x to 7.9.x for another one)"
    for tag_variable in $(compgen -e | grep -E '^CP_[A-Z_]+_TAG$')
    do
        unset "$tag_variable"
    done
    export TAG=7.9.11
fi
# the cluster starts in ZooKeeper mode: forget the KRaft mode chosen for a CP 8 tag (or --enable-kraft), then source
# utils.sh again with the tag of the migration
unset ENABLE_KRAFT KRAFT_MODE_LOGGED KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE
source ${DIR}/../../scripts/utils.sh
if ! version_gt $TAG_BASE "7.5.99"
then
    logwarn "the ZooKeeper to KRaft migration is supported from CP 7.6 (Apache Kafka 3.6)"
    exit 111
fi
# the inter.broker.protocol.version of the brokers during the migration: the Apache Kafka version of this CP (7.9 is 3.9)
ibp="3.$(echo "$TAG_BASE" | cut -d. -f2)"

mkdir -p ${DIR}/migration
rm -f ${DIR}/migration/cluster.id

# ZooKeeper, one broker in ZooKeeper mode, and the KRaft controller of the migration, which waits for the cluster id
PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Before the migration: 5 orders"
playground topic produce -t orders --nb-messages 5 --forced-value '{"order": %g, "phase": "zookeeper"}'

log "🧭 Phase 1: the cluster id of the ZooKeeper cluster"
cluster_id=$(playground --output-level ERROR container exec -c zookeeper --command "zookeeper-shell localhost:2181 get /cluster/id 2>/dev/null" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
if [ -z "$cluster_id" ]
then
    logerror "❌ could not read /cluster/id from ZooKeeper"
    exit 1
fi
log "cluster id: $cluster_id"

log "🗳️ Phase 2: the KRaft controller, formatted with that cluster id, in migration mode (zookeeper.metadata.migration.enable=true)"
printf '%s' "$cluster_id" > ${DIR}/migration/cluster.id
playground container logs -c kraft-controller --wait-for-log "waiting for brokers to register" --max-wait 120 > /dev/null

log "🔀 Phase 3: the broker in migration mode, then restarted: the controller copies the metadata from ZooKeeper"
# confluent.cluster.link.metadata.topic.enable: Confluent Server refuses to start in migration mode without it
# ("requirement failed: Must have link coordinator enabled during migration")
playground container set-environment-variables -c broker \
    --env "KAFKA_ZOOKEEPER_METADATA_MIGRATION_ENABLE: 'true'" \
    --env "KAFKA_CONTROLLER_QUORUM_VOTERS: '3000@kraft-controller:9093'" \
    --env "KAFKA_CONTROLLER_LISTENER_NAMES: CONTROLLER" \
    --env "KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: 'BROKER:PLAINTEXT,HOST:PLAINTEXT,CONTROLLER:PLAINTEXT'" \
    --env "KAFKA_INTER_BROKER_PROTOCOL_VERSION: '$ibp'" \
    --env "KAFKA_CONFLUENT_CLUSTER_LINK_METADATA_TOPIC_ENABLE: 'true'"
playground container logs -c kraft-controller --wait-for-log "Completed migration of metadata from ZooKeeper to KRaft" --max-wait 180

log "Dual-write: the KRaft controller writes every change to ZooKeeper too, the broker still has its ZooKeeper settings: 5 orders"
playground topic produce -t orders --nb-messages 5 --forced-value '{"order": %g, "phase": "dual-write"}'

log "🖥️ Phase 4: the broker restarted in KRaft mode (process.roles=broker, node.id = its broker.id, no migration, no zookeeper.connect)"
playground container set-environment-variables -c broker \
    --env "KAFKA_PROCESS_ROLES: broker" \
    --env "KAFKA_NODE_ID: 1" \
    --env "CLUSTER_ID: '$cluster_id'" \
    --env "KAFKA_ZOOKEEPER_METADATA_MIGRATION_ENABLE: 'false'" \
    --env "KAFKA_ZOOKEEPER_CONNECT: ''"
playground container logs -c broker --wait-for-log "KafkaRaftServer nodeId=1] Kafka Server started" --max-wait 180 > /dev/null

log "🗳️ Phase 5: the controller out of migration mode (zookeeper.metadata.migration.enable=false, no zookeeper.connect)"
playground container set-environment-variables -c kraft-controller \
    --env "KAFKA_ZOOKEEPER_METADATA_MIGRATION_ENABLE: 'false'" \
    --env "KAFKA_ZOOKEEPER_CONNECT: ''"
playground container logs -c kraft-controller --wait-for-log "KafkaRaftServer nodeId=3000] Kafka Server started" --max-wait 180 > /dev/null

log "🦓 Phase 6: ZooKeeper is not needed any more"
playground container kill -c zookeeper

log "After the migration: 5 orders"
playground topic produce -t orders --nb-messages 5 --forced-value '{"order": %g, "phase": "kraft"}'

log "Every order of the three phases is in the topic"
playground topic consume -t orders --min-expected-messages 15 --timeout 60

playground broker describe
