job="${args[--name]}"
timeout="${args[--timeout]}"

phase=$(kubectl -n confluent get kraftmigrationjob "$job" -o jsonpath='{.status.phase}' 2> /dev/null)
if [[ "$phase" != "DUAL-WRITE" ]]
then
    logerror "❌ KRaftMigrationJob $job is in phase ${phase:-?}: finalize only from DUAL-WRITE (playground cfk kraft-migration status)"
    exit 1
fi
log "🏁 finalize: the brokers lose their ZooKeeper dependency, no rollback after this point"
run_logged kubectl -n confluent annotate kraftmigrationjob "$job" platform.confluent.io/kraft-migration-trigger-finalize-to-kraft=true | sed 's/^/   /'
cfk_kmj_wait "$job" "COMPLETE" "$timeout" || exit 1
log_command kubectl -n confluent get kafka kafka -o 'jsonpath={.spec.dependencies}'
log "   Kafka dependencies: $(kubectl -n confluent get kafka kafka -o jsonpath='{.spec.dependencies}')"
log "🔒 locked CRs: $(cfk_kmj_locks)"
log "🎓 next: playground cfk kraft-migration release-lock --remove-log4j1, then delete the Zookeeper CR"
