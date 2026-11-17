resource="${args[resource]}"
timeout="${args[--timeout]}"

if [[ "$resource" != */* ]] || ! kubectl -n confluent get "$resource" > /dev/null 2>&1
then
    logerror "❌ give a custom resource of namespace confluent as kind/name, one of: $(cfk_cr_list | tr '\n' ' ')"
    exit 1
fi
kind="${resource%%/*}"
name="${resource#*/}"
case "$kind" in
    kafka|kraftcontroller)
        # the only supported way to roll Kafka and KRaft: CFK rolls one pod at a time, with its health checks
        # (docs.confluent.io/operator/current/co-roll-cluster.html)
        trigger="playground-$(date +%s)"
        log "🔁 $resource: spec.podTemplate.annotations.kafkacluster-manual-roll=$trigger"
        cfk_patch_and_wait "$resource" "{\"spec\": {\"podTemplate\": {\"annotations\": {\"kafkacluster-manual-roll\": \"$trigger\"}}}}" merge "$timeout"
        ;;
    *)
        generation_before=$(cfk_statefulset_generation "$name")
        since=$(date +%s)
        run_logged kubectl -n confluent rollout restart "statefulset/$name"
        cfk_wait_rollout "$resource" "$generation_before" "$timeout" "$since"
        ;;
esac
