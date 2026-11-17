job="${args[--name]}"

if ! kubectl -n confluent get kraftmigrationjob "$job" > /dev/null 2>&1
then
    logerror "❌ no KRaftMigrationJob $job in namespace confluent (playground cfk kraft-migration start)"
    exit 1
fi
log_command kubectl -n confluent get kraftmigrationjob "$job" -o yaml
phase=$(kubectl -n confluent get kraftmigrationjob "$job" -o jsonpath='{.status.phase}')
sub=$(kubectl -n confluent get kraftmigrationjob "$job" -o jsonpath='{.status.subPhase}')
message=$(kubectl -n confluent get kraftmigrationjob "$job" -o jsonpath='{.status.message}')
log "🚚 KRaftMigrationJob $job: $phase / $sub${message:+ ($message)}"
for cr in kafka/kafka kraftcontroller/kraftcontroller zookeeper/zookeeper
do
    if kubectl -n confluent get "$cr" > /dev/null 2>&1
    then
        printf "   %-32s %-10s %s\n" "$cr" "$(kubectl -n confluent get "$cr" -o jsonpath='{.status.phase}')" "$(kubectl -n confluent get "$cr" -o jsonpath='ready {.status.readyReplicas}/{.status.replicas}')"
    else
        printf "   %-32s %s\n" "$cr" "(deleted)"
    fi
done
locks=$(cfk_kmj_locks)
log "🔒 locked CRs: ${locks:-none}"
case "$phase" in
    SETUP|MIGRATE) log "🎓 no action required: the operator is working (pods roll one at a time)" ;;
    DUAL-WRITE) log "🎓 validate the cluster, then: playground cfk kraft-migration finalize (irreversible), or roll back to ZooKeeper" ;;
    COMPLETE)
        if [[ -n "$locks" ]]
        then
            log "🎓 release the locks, or every change of these CRs is rejected: playground cfk kraft-migration release-lock --remove-log4j1"
        else
            log "🎓 done: validate KRaft-only operation, then delete the Zookeeper CR (kubectl -n confluent delete zookeeper zookeeper)"
        fi
        ;;
    FAILURE) log "🎓 status.message and the operator log: kubectl -n confluent logs deployment/confluent-operator | grep -i migration" ;;
esac
