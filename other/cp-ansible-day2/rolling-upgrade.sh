#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/day2-utils.bash

# Rolling upgrade of a cluster deployed by cp-ansible, with a producer and a sink connector running through it:
# CP 8.3.2 (cp-ansible 8.3) -> the default CP version (or --tag), 3 brokers, then the feature level, then the classic
# mistake: a change applied with the default deployment_strategy of cp-ansible (parallel)
day2_require_plaintext
OLD_VERSION="${DAY2_OLD_VERSION:-8.3.2}"
NEW_VERSION="${TAG_BASE:-$TAG}"
if ! version_gt "$NEW_VERSION" "$OLD_VERSION"
then
    logwarn "the upgrade goes from $OLD_VERSION to the CP version of the run ($NEW_VERSION): use a version above $OLD_VERSION (--tag)"
    exit 111
fi

log "Step 1: Confluent Platform $OLD_VERSION deployed by cp-ansible, 1 controller, 3 brokers, schema registry, connect"
TAG="$OLD_VERSION" TAG_BASE="$OLD_VERSION" ENABLE_KAFKA_NODES=1 playground start-environment --environment ansible --docker-compose-override-file "${DIR}/docker-compose.plaintext.yml"
day2_broker_versions

log "Step 2: a workload that must survive the upgrade"
day2_start_workload

log "Step 3: the rolling upgrade to $NEW_VERSION (controller, then one broker at a time, then the other components)"
errors_before=$(day2_send_errors)
since=$(day2_now)
playground ansible upgrade --to "$NEW_VERSION"
errors_upgrade=$(( $(day2_send_errors) - errors_before ))
pause_upgrade=$(day2_longest_pause "$since")
day2_report_workload "after the upgrade"
day2_broker_restarts "$since"
log "🔁 during the rolling upgrade: $errors_upgrade send errors (kafka-verifiable-producer does not retry: a leader move during a broker restart is an error), longest time without an ack ${pause_upgrade}s"
day2_broker_versions
playground connector status --connector day2-sink

log "Step 4: the feature level is not upgraded by cp-ansible: finalize it once every broker runs the new version"
playground container exec -c broker --command "kafka-features --bootstrap-server broker:9092 --command-config /etc/kafka/client.properties describe | grep -E 'confluent.metadata.version|Feature: metadata.version'"
# --release-version is the Apache Kafka version of the CP version: CP 8.4 is Kafka 4.4
kafka_release="$(( $(echo "$NEW_VERSION" | cut -d '.' -f 1) - 4 )).$(echo "$NEW_VERSION" | cut -d '.' -f 2)"
log_command docker exec broker sh -c "kafka-features --bootstrap-server broker:9092 --command-config /etc/kafka/client.properties upgrade --release-version $kafka_release --dry-run"
level=$(docker exec broker sh -c "kafka-features --bootstrap-server broker:9092 --command-config /etc/kafka/client.properties upgrade --release-version $kafka_release --dry-run" 2> /dev/null | sed -n 's/^confluent.metadata.version can be upgraded to \([0-9]*\)\..*/\1/p')
if [ -n "$level" ]
then
    log "⬆️ kafka-features upgrade --feature confluent.metadata.version=$level"
    playground container exec -c broker --command "kafka-features --bootstrap-server broker:9092 --command-config /etc/kafka/client.properties upgrade --feature confluent.metadata.version=$level"
fi
playground container exec -c broker --command "kafka-features --bootstrap-server broker:9092 --command-config /etc/kafka/client.properties describe | grep -E 'confluent.metadata.version'"

log "Step 5: the classic mistake, a change applied with the default deployment_strategy of cp-ansible (parallel)"
playground ansible inventory set '.all.children.kafka_broker.vars.kafka_broker_custom_properties["log.retention.hours"]' 72
errors_before=$(day2_send_errors)
since=$(day2_now)
playground ansible playbook --limit kafka_broker
errors_parallel=$(( $(day2_send_errors) - errors_before ))
pause_parallel=$(day2_longest_pause "$since")
day2_report_workload "after the parallel restart"
day2_broker_restarts "$since"
spread_parallel=$DAY2_RESTART_SPREAD
log "💥 parallel: every broker restarted within ${spread_parallel}s, $errors_parallel send errors, longest time without an ack ${pause_parallel}s"
log "   (the brokers of this example hold little data and are back in seconds: with real data a broker takes minutes to start, and every partition is offline meanwhile)"

log "Step 6: the same kind of change, with --rolling"
playground ansible inventory set '.all.children.kafka_broker.vars.kafka_broker_custom_properties["log.retention.hours"]' 96
errors_before=$(day2_send_errors)
since=$(day2_now)
playground ansible playbook --limit kafka_broker --rolling
errors_rolling=$(( $(day2_send_errors) - errors_before ))
pause_rolling=$(day2_longest_pause "$since")
day2_report_workload "after the rolling restart"
day2_broker_restarts "$since"
spread_rolling=$DAY2_RESTART_SPREAD
log "🔁 rolling: the brokers restarted one at a time over ${spread_rolling}s, $errors_rolling send errors, longest time without an ack ${pause_rolling}s"
playground container get-properties -c broker | grep "^log.retention.hours"

log "Step 7: no record lost"
day2_check_no_loss
log "📋 send errors: rolling upgrade $errors_upgrade, parallel restart $errors_parallel, rolling restart $errors_rolling"
log "📋 brokers restarted within: parallel ${spread_parallel}s, rolling ${spread_rolling}s"
if [ "$spread_parallel" -gt 10 ] || [ "$spread_rolling" -lt 20 ]
then
    logerror "❌ expected the parallel run to restart every broker at once (${spread_parallel}s) and the rolling one to space them (${spread_rolling}s)"
    exit 1
fi
