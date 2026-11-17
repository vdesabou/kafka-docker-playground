#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/cfk-day2-utils.bash

# Rolling upgrade of a cluster deployed by Confluent for Kubernetes, with a producer and a sink connector running
# through it: CP 8.3.2 -> the default CP version (or --tag), 3 brokers, then the feature level. The classic mistake: a
# JSON merge patch of configOverrides replaces the whole list
day2_require_cfk
OLD_VERSION="${DAY2_OLD_VERSION:-8.3.2}"
NEW_VERSION="${TAG_BASE:-$TAG}"
if ! version_gt "$NEW_VERSION" "$OLD_VERSION"
then
    logwarn "the upgrade goes from $OLD_VERSION to the CP version of the run ($NEW_VERSION): use a version above $OLD_VERSION (--tag)"
    exit 111
fi

log "Step 1: Confluent Platform $OLD_VERSION deployed by CFK, 3 KRaft controllers, 3 brokers, schema registry, connect"
day2_start_cfk "$OLD_VERSION"
day2_broker_versions

log "Step 2: a workload that must survive the upgrade"
day2_start_workload "$OLD_VERSION"

log "Step 3: the rolling upgrade to $NEW_VERSION (playground cfk upgrade: the image tag of each custom resource, controller first, CFK rolls one pod at a time)"
errors_before=$(day2_send_errors)
since=$(day2_now)
playground cfk upgrade --to "$NEW_VERSION"
errors_upgrade=$(( $(day2_send_errors) - errors_before ))
pause_upgrade=$(day2_longest_pause "$since")
day2_report_workload "after the upgrade"
day2_pod_restarts kafka "$since"
spread_upgrade=$DAY2_RESTART_SPREAD
log "🕐 send errors per minute (the controllers rolled first, then each broker):"
day2_error_timeline "$since"
log "🔁 during the rolling upgrade: $errors_upgrade send errors (kafka-verifiable-producer does not retry: a leader move during a broker restart is an error), longest time without an ack ${pause_upgrade}s"
day2_broker_versions
playground connector status --connector day2-sink

log "Step 4: the feature level is not upgraded by CFK: finalize it once every broker runs the new version"
day2_features describe | grep -E 'confluent.metadata.version|Feature: metadata.version'
# --release-version is the Apache Kafka version of the CP version: CP 8.4 is Kafka 4.4
kafka_release="$(( $(echo "$NEW_VERSION" | cut -d '.' -f 1) - 4 )).$(echo "$NEW_VERSION" | cut -d '.' -f 2)"
level=$(day2_features upgrade --release-version "$kafka_release" --dry-run 2> /dev/null | sed -n 's/^confluent.metadata.version can be upgraded to \([0-9]*\)\..*/\1/p')
if [ -n "$level" ]
then
    log "⬆️ kafka-features upgrade --feature confluent.metadata.version=$level"
    day2_features upgrade --feature "confluent.metadata.version=$level"
fi
day2_features describe | grep -E 'confluent.metadata.version'

log "Step 5: the classic mistake, a JSON merge patch of configOverrides: the list is replaced, not merged"
log "configOverrides.server before: $(kubectl -n confluent get kafka kafka -o jsonpath='{.spec.configOverrides.server}')"
since=$(day2_now)
playground cfk patch kafka/kafka '{"spec": {"configOverrides": {"server": ["log.retention.hours=72"]}}}'
log "configOverrides.server after: $(kubectl -n confluent get kafka kafka -o jsonpath='{.spec.configOverrides.server}')"
log "💥 every other override is gone (replication factors of the internal topics, auto.create.topics.enable...): add an item with --type json instead"
day2_pod_restarts kafka "$since"
spread_patch=$DAY2_RESTART_SPREAD
log "Step 6: the same kind of change with a JSON patch (an item added to the list), right after the roll of step 5"
since=$(day2_now)
playground cfk patch kafka/kafka '[{"op": "add", "path": "/spec/configOverrides/server/-", "value": "num.io.threads=16"}]' --type json
day2_pod_restarts kafka "$since"
in_file=$(kubectl -n confluent exec kafka-0 -c kafka -- sh -c "grep '^num.io.threads=' /opt/confluentinc/etc/kafka/kafka.properties" 2> /dev/null | cut -d '=' -f 2)
running=$(day2_client "kafka-configs --bootstrap-server $DAY2_BOOTSTRAP --describe --all --entity-type brokers --entity-name 0" 2> /dev/null | sed -n 's/^ *num.io.threads=\([0-9]*\).*/\1/p' | head -1)
log "🔎 num.io.threads of broker 0: ${in_file:-?} in the kafka.properties of kafka-0, ${running:-?} in the running broker"
if [ "$DAY2_RESTART_SPREAD" -eq 0 ] && [ "${in_file}" != "${running}" ]
then
    logwarn "💥 the ConfigMap and the file of the pods have the change, the brokers were not rolled and still run the old value: CFK did not see a new revision for a change applied right after a roll (the same change on an idle cluster rolls the brokers). Check the brokers after each change; roll them the supported way (annotation kafkacluster-manual-roll):"
    playground cfk roll kafka/kafka
    running=$(day2_client "kafka-configs --bootstrap-server $DAY2_BOOTSTRAP --describe --all --entity-type brokers --entity-name 0" 2> /dev/null | sed -n 's/^ *num.io.threads=\([0-9]*\).*/\1/p' | head -1)
    log "🔎 num.io.threads of broker 0 after the roll: ${running:-?} in the running broker"
fi
day2_report_workload "after the configOverrides changes"

log "Step 7: no record lost"
day2_check_no_loss
log "📋 send errors during the upgrade: $errors_upgrade (longest time without an ack ${pause_upgrade}s)"
log "📋 brokers restarted over: upgrade ${spread_upgrade}s, configOverrides change ${spread_patch}s (CFK always rolls one broker at a time)"
if [ "$spread_upgrade" -lt 20 ] || [ "$spread_patch" -lt 20 ]
then
    logerror "❌ expected CFK to roll the brokers one at a time (upgrade ${spread_upgrade}s, configOverrides change ${spread_patch}s)"
    exit 1
fi
