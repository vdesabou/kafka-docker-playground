broker="${args[--broker]}"
kill="${args[--kill]}"
verbose="${args[--verbose]}"

get_broker_container_of_id "$broker" || exit 1
container="$broker_id_container"

if ! is_container_running "$container"
then
    logwarn "🤷 broker $broker (container $container) is already stopped"
    exit 0
fi

running=0
while read -r id c
do
    if is_container_running "$c"
    then
        running=$((running + 1))
    fi
done <<< "$(get_broker_containers)"
if [ $running -eq 1 ]
then
    logwarn "⚠️ broker $broker is the only running broker: the cluster is unavailable until it starts again"
fi

if [[ -n "$kill" ]]
then
    log "🔫 Killing broker $broker (container $container): no controlled shutdown, like a crash"
    docker kill "$container" > /dev/null || exit 1
else
    log "🛑 Stopping broker $broker (container $container): controlled shutdown, its leaders move to the other replicas first"
    docker stop -t 60 "$container" > /dev/null || exit 1
fi
log "🎓 see the impact with 'playground broker health$(mdc_cluster_flag)', start it again with 'playground broker start --broker $broker$(mdc_cluster_flag)'"
