#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/cfk-day2-utils.bash

# ZooKeeper to KRaft migration of a cluster deployed by Confluent for Kubernetes, with the KRaftMigrationJob CR, while a
# producer and a sink connector run through it (docs.confluent.io/operator/current/co-migrate-kraft.html):
#   1. CP 7.9 in ZooKeeper mode: 3 ZooKeeper nodes, 3 brokers
#   2. a KRaftController CR on HOLD, then the KRaftMigrationJob: SETUP, MIGRATE, DUAL-WRITE (the metadata is written to
#      KRaft and to ZooKeeper: a rollback is still possible)
#   3. the classic mistake: a change of a locked CR during the migration is rejected, and it still is after COMPLETE
#      until the locks are released (GitOps reconciliations fail)
#   4. finalize (irreversible), release the locks, ZooKeeper deleted, the brokers run KRaft only
day2_require_cfk
ZK_VERSION="${DAY2_ZK_VERSION:-7.9.11}"
if ! version_gt "$ZK_VERSION" "7.6.99"
then
    logwarn "the CFK KRaft migration needs CP 7.7 or later in ZooKeeper mode (DAY2_ZK_VERSION=$ZK_VERSION)"
    exit 111
fi
LOCKED_PATCH='[{"op": "add", "path": "/spec/configOverrides/server/-", "value": "num.io.threads=16"}]'

function day2_try_locked_patch () {
    # a change of the Kafka CR, checked by the API server (server dry run: the admission policy or the webhook of CFK
    # run, nothing is changed): returns 0 when the change would be accepted
    local output
    log_command kubectl -n confluent patch kafka kafka --type json -p "$LOCKED_PATCH" --dry-run=server
    if output=$(kubectl -n confluent patch kafka kafka --type json -p "$LOCKED_PATCH" --dry-run=server 2>&1)
    then
        log "   ✅ accepted: $output"
        return 0
    fi
    log "   ⛔ rejected: $(echo "$output" | tr '\n' ' ' | cut -c1-300)"
    return 1
}

function day2_zookeeper_topics () {
    # the topics registered in ZooKeeper, under the chroot of the Kafka CR
    local chroot
    chroot=$(kubectl -n confluent exec kafka-0 -c kafka -- sh -c "grep '^zookeeper.connect=' /opt/confluentinc/etc/kafka/kafka.properties" 2> /dev/null | sed -n 's|^zookeeper.connect=[^/]*||p')
    log_command kubectl -n confluent exec zookeeper-0 -- zookeeper-shell localhost:2181 ls "${chroot}/brokers/topics"
    kubectl -n confluent exec zookeeper-0 -- zookeeper-shell localhost:2181 ls "${chroot}/brokers/topics" 2> /dev/null | tail -1
}

log "Step 1: Confluent Platform $ZK_VERSION deployed by CFK in ZooKeeper mode: 3 ZooKeeper nodes, 3 brokers, schema registry, connect"
day2_start_cfk "$ZK_VERSION"
log_command kubectl -n confluent get zookeeper,kafka
kubectl -n confluent get zookeeper,kafka
day2_broker_versions

log "Step 2: a workload that must survive the migration"
day2_start_workload "$ZK_VERSION"

log "Step 3: the migration, up to DUAL-WRITE (playground cfk kraft-migration start: KRaftController on HOLD, KRaftMigrationJob)"
errors_before=$(day2_send_errors)
since=$(day2_now)
playground cfk kraft-migration start
errors_migrate=$(( $(day2_send_errors) - errors_before ))
pause_migrate=$(day2_longest_pause "$since")
day2_report_workload "in DUAL-WRITE"
day2_pod_stops "$since"
stops_migrate=$DAY2_POD_STOPS
day2_error_timeline "$since"
log "🔁 up to DUAL-WRITE: $stops_migrate pod stops, $errors_migrate send errors, longest time without an ack ${pause_migrate}s"

log "Step 4: DUAL-WRITE: the controllers own the metadata, and still write it to ZooKeeper (a rollback is possible until finalize)"
log_command kubectl -n confluent exec kraftcontroller-0 -c kraftcontroller -- kafka-metadata-quorum --bootstrap-controller localhost:9074 describe --status
kubectl -n confluent exec kraftcontroller-0 -c kraftcontroller -- kafka-metadata-quorum --bootstrap-controller localhost:9074 describe --status 2> /dev/null | sed 's/^/   /' || true
playground topic create --topic day2-created-in-dual-write --nb-partitions 1
sleep 5
log "🔎 topics in ZooKeeper (the one created in DUAL-WRITE is there: written by the KRaft controllers):"
zk_topics=$(day2_zookeeper_topics)
echo "   $zk_topics"

log "Step 5: the classic mistake, a change of the Kafka CR during the migration (a GitOps reconciliation, a kubectl apply)"
locked_during=1
if day2_try_locked_patch
then
    locked_during=0
fi
log "🔒 locked CRs (annotation platform.confluent.io/kraft-migration-cr-lock): $(cfk_kmj_locks)"

log "Step 6: finalize (irreversible): the brokers lose their ZooKeeper dependency"
errors_before=$(day2_send_errors)
since=$(day2_now)
playground cfk kraft-migration finalize
errors_finalize=$(( $(day2_send_errors) - errors_before ))
pause_finalize=$(day2_longest_pause "$since")
day2_pod_stops "$since"
stops_finalize=$DAY2_POD_STOPS
log "🔁 finalize: $stops_finalize pod stops, $errors_finalize send errors, longest time without an ack ${pause_finalize}s"

log "Step 7: COMPLETE, and the locks are still there: the same change is still rejected until they are released"
locked_after_complete=1
if day2_try_locked_patch
then
    locked_after_complete=0
fi
playground cfk kraft-migration release-lock --remove-log4j1
unlocked=0
if day2_try_locked_patch
then
    unlocked=1
fi

log "Step 8: KRaft only: ZooKeeper deleted, the brokers have no zookeeper.connect"
run_logged kubectl -n confluent delete zookeeper zookeeper
log_command kubectl -n confluent exec kafka-0 -c kafka -- grep -E '^(zookeeper.connect|controller.quorum.voters|process.roles)=' /opt/confluentinc/etc/kafka/kafka.properties
broker_config=$(kubectl -n confluent exec kafka-0 -c kafka -- sh -c "grep -E '^(zookeeper.connect|controller.quorum.voters|process.roles)=' /opt/confluentinc/etc/kafka/kafka.properties" 2> /dev/null || true)
echo "$broker_config" | sed 's/^/   /'
sleep 20
day2_report_workload "after deleting ZooKeeper"
playground connector status --connector day2-sink

log "Step 9: no record lost"
day2_check_no_loss
log "📋 up to DUAL-WRITE: $stops_migrate pod stops, $errors_migrate send errors (longest pause ${pause_migrate}s); finalize: $stops_finalize pod stops, $errors_finalize send errors (longest pause ${pause_finalize}s)"
log "📋 change of the Kafka CR: rejected during the migration ($locked_during), rejected after COMPLETE with the locks ($locked_after_complete), accepted after release-lock ($unlocked)"
if [ "$locked_during" -ne 1 ] || [ "$locked_after_complete" -ne 1 ] || [ "$unlocked" -ne 1 ]
then
    logerror "❌ expected the change of the Kafka CR to be rejected while the locks are there, and accepted after release-lock"
    exit 1
fi
if [[ "$zk_topics" != *"day2-created-in-dual-write"* ]]
then
    logerror "❌ expected the topic created in DUAL-WRITE in ZooKeeper"
    exit 1
fi
if echo "$broker_config" | grep -q "^zookeeper.connect="
then
    logerror "❌ the brokers still have zookeeper.connect after the migration"
    exit 1
fi
