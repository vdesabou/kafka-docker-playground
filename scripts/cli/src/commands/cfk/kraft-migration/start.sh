controllers="${args[--controllers]}"
preflight="${args[--preflight]}"
job="${args[--name]}"
timeout="${args[--timeout]}"

if ! kubectl -n confluent get zookeeper zookeeper > /dev/null 2>&1
then
    logerror "❌ no Zookeeper CR zookeeper in namespace confluent: the cluster already runs KRaft (start the cfk environment with a CP 7.x --tag, without --enable-kraft)"
    exit 1
fi
if kubectl -n confluent get kraftmigrationjob "$job" > /dev/null 2>&1
then
    logwarn "⚠️ KRaftMigrationJob $job already exists, waiting for DUAL-WRITE (playground cfk kraft-migration status for the details)"
    cfk_kmj_wait "$job" "DUAL-WRITE" "$timeout"
    exit $?
fi
application=$(kubectl -n confluent get kafka kafka -o jsonpath='{.spec.image.application}')
init=$(kubectl -n confluent get kafka kafka -o jsonpath='{.spec.image.init}')
cp_major=$(echo "${application##*:}" | cut -d '.' -f 1)

log "🗳️ Step 1: KRaftController CR, $controllers replicas, the images of the Kafka CR ($application), on HOLD until the migration job mutates it"
log_command kubectl -n confluent get kafka kafka -o yaml
log4j1_annotation=""
if [[ "$cp_major" =~ ^[0-9]+$ ]] && [[ "$cp_major" -lt 8 ]]
then
    log4j1_annotation='    platform.confluent.io/use-log4j1: "true"'
fi
manifest=$(cat << EOM
apiVersion: platform.confluent.io/v1beta1
kind: KRaftController
metadata:
  name: kraftcontroller
  namespace: confluent
  annotations:
    platform.confluent.io/kraft-migration-hold-krc-creation: "true"
${log4j1_annotation}
spec:
  replicas: ${controllers}
  dataVolumeCapacity: 10Gi
  image:
    application: ${application}
    init: ${init}
EOM
)
echo "$manifest" | sed '/^$/d; s/^/   /'
log_command kubectl apply -f kraftcontroller.yaml
echo "$manifest" | sed '/^$/d' | kubectl apply -f - | sed 's/^/   /'
for i in $(seq 1 30)
do
    if [[ "$(kubectl -n confluent get kraftcontroller kraftcontroller -o jsonpath='{.status.phase}' 2> /dev/null)" == "HOLD" ]]
    then
        break
    fi
    sleep 2
done
log_command kubectl -n confluent get kraftcontroller kraftcontroller
kubectl -n confluent get kraftcontroller kraftcontroller | sed 's/^/   /'

log "🚚 Step 2: KRaftMigrationJob $job${preflight:+, with the ZooKeeper metadata preflight check}"
preflight_annotation=""
if [[ -n "$preflight" ]]
then
    preflight_annotation=$'  annotations:\n    platform.confluent.io/kraft-migration-enable-preflight: "true"'
fi
manifest=$(cat << EOM
apiVersion: platform.confluent.io/v1beta1
kind: KRaftMigrationJob
metadata:
  name: ${job}
  namespace: confluent
${preflight_annotation}
spec:
  dependencies:
    kafka:
      name: kafka
      namespace: confluent
    zookeeper:
      name: zookeeper
      namespace: confluent
    kRaftController:
      name: kraftcontroller
      namespace: confluent
EOM
)
echo "$manifest" | sed '/^$/d; s/^/   /'
log_command kubectl apply -f kraftmigrationjob.yaml
echo "$manifest" | sed '/^$/d' | kubectl apply -f - | sed 's/^/   /'

log "⏳ Step 3: the operator goes through SETUP (Kafka rolls, the controllers start), MIGRATE (metadata copied from ZooKeeper, Kafka rolls again) to DUAL-WRITE, where it waits for you"
cfk_kmj_wait "$job" "DUAL-WRITE" "$timeout" || exit 1
log "🔒 locked CRs: $(cfk_kmj_locks)"
log "🎓 validate the cluster, then: playground cfk kraft-migration finalize (irreversible), or roll back to ZooKeeper ("Roll Back to ZooKeeper" in the CFK docs)"
