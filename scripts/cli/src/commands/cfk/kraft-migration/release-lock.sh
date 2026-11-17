job="${args[--name]}"
remove_log4j1="${args[--remove-log4j1]}"

run_logged kubectl -n confluent annotate kraftmigrationjob "$job" platform.confluent.io/kraft-migration-release-cr-lock=true --overwrite | sed 's/^/   /'
log_command --polled kubectl -n confluent get kafka kafka -o yaml '|' grep kraft-migration-cr-lock
locks=""
for i in $(seq 1 60)
do
    locks=$(cfk_kmj_locks)
    if [[ -z "$locks" ]]
    then
        break
    fi
    sleep 5
done
if [[ -n "$locks" ]]
then
    logerror "❌ still locked after 300 s: $locks"
    exit 1
fi
log "🔓 locks released: the Kafka, KRaftController and Zookeeper CRs can be changed again"
if [[ -n "$remove_log4j1" ]] && [[ -n "$(kubectl -n confluent get kraftcontroller kraftcontroller -o jsonpath='{.metadata.annotations.platform\.confluent\.io/use-log4j1}' 2> /dev/null)" ]]
then
    generation_before=$(cfk_statefulset_generation kraftcontroller)
    since=$(date +%s)
    run_logged kubectl -n confluent annotate kraftcontroller kraftcontroller platform.confluent.io/use-log4j1- | sed 's/^/   /'
    cfk_wait_rollout kraftcontroller/kraftcontroller "$generation_before" 900 "$since"
fi
