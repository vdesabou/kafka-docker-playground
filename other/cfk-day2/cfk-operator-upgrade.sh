#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/cfk-day2-utils.bash

# Upgrade of the CFK operator under a running cluster, with a producer and a sink connector running through it:
#   1. CFK 3.3.0 -> 3.3.1 the classic way, helm upgrade without blocking reconciliation: the new operator reconciles every
#      component as soon as it starts, controller, brokers, connect and schema registry roll at the same time, then the
#      new init container images roll them all a second time
#   2. CFK 3.3.1 -> 3.4.0 with the CFK upgrade procedure (playground cfk operator upgrade): reconciliation blocked, CRDs,
#      helm upgrade, init container images staged, reconciliation enabled one component at a time: one roll each
day2_require_cfk
OLD_CFK="${DAY2_OLD_CFK:-3.3.0}"
MID_CFK="${DAY2_MID_CFK:-3.3.1}"
NEW_CFK="${DAY2_NEW_CFK:-3.4.0}"

log "Step 1: CFK $OLD_CFK, Confluent Platform $TAG, 3 KRaft controllers, 3 brokers, schema registry, connect"
CFK_VERSION="$OLD_CFK" day2_start_cfk
helm -n confluent list --filter '^confluent-operator$'

log "Step 2: a workload that must survive the operator upgrades"
day2_start_workload

log "Step 3: the classic mistake, CFK $OLD_CFK → $MID_CFK with helm upgrade and nothing else (reconciliation not blocked)"
errors_before=$(day2_send_errors)
since=$(day2_now)
playground cfk operator upgrade --to "$MID_CFK" --no-block-reconcile
errors_mistake=$(( $(day2_send_errors) - errors_before ))
pause_mistake=$(day2_longest_pause "$since")
day2_report_workload "after the operator upgrade without blocking reconciliation"
day2_pod_stops "$since"
stops_mistake=$DAY2_POD_STOPS
day2_error_timeline "$since"
log "💥 without blocking reconciliation: every component rolled when the new operator started (controller and brokers at the same time), then again for the init containers: $stops_mistake pod stops, $errors_mistake send errors, longest time without an ack ${pause_mistake}s"

log "Step 4: CFK $MID_CFK → $NEW_CFK with the CFK upgrade procedure (block reconcile, CRDs, helm upgrade, init containers staged, enable reconcile one component at a time)"
errors_before=$(day2_send_errors)
since=$(day2_now)
playground cfk operator upgrade --to "$NEW_CFK"
errors_procedure=$(( $(day2_send_errors) - errors_before ))
pause_procedure=$(day2_longest_pause "$since")
day2_report_workload "after the operator upgrade with the procedure"
day2_pod_stops "$since"
stops_procedure=$DAY2_POD_STOPS
day2_error_timeline "$since"
log "🔁 with the procedure: one roll per component, one component at a time: $stops_procedure pod stops, $errors_procedure send errors, longest time without an ack ${pause_procedure}s"
playground connector status --connector day2-sink

log "Step 5: no record lost"
day2_check_no_loss
log "📋 operator upgrade without blocking reconciliation: $stops_mistake pod stops, $errors_mistake send errors (longest pause ${pause_mistake}s); with the procedure: $stops_procedure pod stops, $errors_procedure send errors (longest pause ${pause_procedure}s)"
init_images=$(kubectl -n confluent get pods -o jsonpath='{range .items[*]}{.spec.initContainers[*].image}{"\n"}{end}' | grep confluent-init-container | sort -u)
log "🧷 init container images of the pods: $(echo $init_images)"
if [ "$init_images" != "confluentinc/confluent-init-container:$NEW_CFK" ]
then
    logerror "❌ expected every pod on confluentinc/confluent-init-container:$NEW_CFK"
    exit 1
fi
if [ "$stops_procedure" -ge "$stops_mistake" ]
then
    logerror "❌ expected fewer pod stops with the procedure ($stops_procedure) than without blocking reconciliation ($stops_mistake)"
    exit 1
fi
