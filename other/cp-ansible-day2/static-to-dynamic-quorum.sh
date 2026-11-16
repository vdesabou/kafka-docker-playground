#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/day2-utils.bash

# Static KRaft quorum (controller.quorum.voters, kraft.version 0) -> dynamic quorum (KIP-853, kraft.version 1) on a
# running cluster deployed by cp-ansible, with its playbook StaticToDynamicQuorumMigration, then two controllers added
# while the cluster runs (impossible with a static quorum). The classic mistake first: setting
# kraft_dynamic_quorum_enabled and running the normal playbook, which cp-ansible refuses.
day2_require_plaintext
if ! version_gt "${TAG_BASE:-$TAG}" "8.3.99"
then
    logwarn "the dynamic KRaft quorum migration of cp-ansible needs Confluent Platform 8.4 or later"
    exit 111
fi

function day2_quorum () {
    playground container exec -c controller --command "kafka-features --bootstrap-controller controller:9093 --command-config /opt/confluent/etc/controller/client.properties describe | grep kraft.version"
    playground container exec -c controller --command "kafka-metadata-quorum --bootstrap-controller controller:9093 --command-config /opt/confluent/etc/controller/client.properties describe --replication"
    playground container exec -c broker --command "grep -E '^controller.quorum.(voters|bootstrap.servers)' /opt/confluent/etc/kafka/server.properties"
}

log "Step 1: a static KRaft quorum (one controller), 3 brokers, deployed by cp-ansible"
ENABLE_KAFKA_NODES=1 playground start-environment --environment ansible --docker-compose-override-file "${DIR}/docker-compose.plaintext.yml"
day2_start_workload
day2_quorum

log "Step 2: the classic mistake, kraft_dynamic_quorum_enabled set and the normal playbook run on a static cluster"
playground ansible inventory set .all.vars.kraft_dynamic_quorum_enabled true
set +e
playground ansible playbook --limit kafka_controller
rc=$?
set -e
if [ $rc -eq 0 ]
then
    logerror "❌ cp-ansible should refuse to render a dynamic quorum configuration on a running static cluster"
    exit 1
fi
grep -o "Detected a running static KRaft cluster[^\"]*" "${PLAYGROUND_HOST_TMP_DIR:-/tmp}/playground-ansible-playbook.log" | head -1 | cut -c1-300
log "✅ cp-ansible refused it: the migration playbook comes first"

log "Step 3: the migration playbook (kraft.version 1, then the controllers and the brokers restarted one at a time)"
playground ansible playbook --playbook confluent.platform.StaticToDynamicQuorumMigration
day2_quorum
day2_report_workload "after the migration"

log "Step 4: two controllers added while the cluster runs, with the controller playbook on the new hosts only"
playground ansible add-host controller2 controller3
playground ansible playbook --playbook confluent.platform.kafka_controller --limit controller2,controller3
sleep 20
day2_quorum
day2_report_workload "after adding the controllers"

log "Step 5: no record lost"
day2_check_no_loss
