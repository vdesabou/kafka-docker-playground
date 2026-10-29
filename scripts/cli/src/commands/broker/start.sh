broker="${args[--broker]}"
max_wait="${args[--max-wait]}"
no_wait="${args[--no-wait]}"
verbose="${args[--verbose]}"

get_broker_container_of_id "$broker" || exit 1
container="$broker_id_container"

if is_container_running "$container"
then
    logwarn "🤷 broker $broker (container $container) is already running"
else
    log "▶️ Starting broker $broker (container $container)"
    docker start "$container" > /dev/null || exit 1
fi

if [[ -n "$no_wait" ]]
then
    exit 0
fi

start_time=$SECONDS
log "⏳ Waiting for broker $broker to be registered"
wait_for_broker_registered "$broker" "$max_wait" || exit 1
log "✅ broker $broker is registered, waiting for its replicas to be back in sync"
wait_for_cluster_healthy $((max_wait - (SECONDS - start_time))) || exit 1
log "✅ cluster is healthy, broker $broker started in $((SECONDS - start_time))s"
