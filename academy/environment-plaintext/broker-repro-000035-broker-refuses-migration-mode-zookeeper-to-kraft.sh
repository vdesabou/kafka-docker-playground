#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# ZooKeeper is gone in CP 8: the cluster of this exercise runs CP 7.9 (same as other/zookeeper-to-kraft-migration)
if version_gt $TAG_BASE "7.9.99"
then
    logwarn "⏪ ZooKeeper is removed in CP 8: the exercise runs on CP 7.9.11"
    for tag_variable in $(compgen -e | grep -E '^CP_[A-Z_]+_TAG$')
    do
        unset "$tag_variable"
    done
    export TAG=7.9.11
fi
unset ENABLE_KRAFT KRAFT_MODE_LOGGED KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE
source ${DIR}/../../scripts/utils.sh
if ! version_gt $TAG_BASE "7.5.99"
then
    logwarn "the ZooKeeper to KRaft migration is supported from CP 7.6 (Apache Kafka 3.6)"
    exit 111
fi
ibp="3.$(echo "$TAG_BASE" | cut -d. -f2)"

# the compose override of the migration example: ZooKeeper, one broker, and a KRaft controller in migration mode that
# waits for the cluster id in other/zookeeper-to-kraft-migration/migration/cluster.id
migration_dir="${DIR}/../../other/zookeeper-to-kraft-migration"
mkdir -p "$migration_dir/migration"
rm -f "$migration_dir/migration/cluster.id"

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "$migration_dir/docker-compose.plaintext.yml"

playground topic produce -t orders --nb-messages 5 --forced-value '{"order": %g, "phase": "zookeeper"}'

log "Phase 1 and 2 of the migration plan: the KRaft controller, formatted with the cluster id of ZooKeeper"
cluster_id=$(playground --output-level ERROR container exec -c zookeeper --command "zookeeper-shell localhost:2181 get /cluster/id 2>/dev/null" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
printf '%s' "$cluster_id" > "$migration_dir/migration/cluster.id"
playground container logs -c kraft-controller --wait-for-log "waiting for brokers to register" --max-wait 120 > /dev/null

# 💥 phase 3, with the properties of the Apache Kafka migration guide: Confluent Server needs one more
log "Phase 3 of the migration plan: the broker restarted in migration mode"
playground container set-environment-variables -c broker \
    --env "KAFKA_ZOOKEEPER_METADATA_MIGRATION_ENABLE: 'true'" \
    --env "KAFKA_CONTROLLER_QUORUM_VOTERS: '3000@kraft-controller:9093'" \
    --env "KAFKA_CONTROLLER_LISTENER_NAMES: CONTROLLER" \
    --env "KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: 'BROKER:PLAINTEXT,HOST:PLAINTEXT,CONTROLLER:PLAINTEXT'" \
    --env "KAFKA_INTER_BROKER_PROTOCOL_VERSION: '$ibp'"
sleep 20

playground --output-level ERROR topic produce -t orders --nb-messages 5 --forced-value '{"order": %g, "phase": "dual-write"}' || logerror "❌ the orders cannot be sent"
