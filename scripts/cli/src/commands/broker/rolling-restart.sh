brokers="${args[--brokers]}"
max_wait="${args[--max-wait]}"
force="${args[--force]}"
verbose="${args[--verbose]}"

containers=$(get_broker_containers)
if [[ -z "$containers" ]]
then
    logerror "❌ no broker container found, is an environment running? (playground status)"
    exit 1
fi

if [[ -n "$brokers" ]]
then
    ids=$(echo "$brokers" | tr ',' '\n' | sed '/^$/d')
    for id in $ids
    do
        get_broker_container_of_id "$id" || exit 1
    done
else
    ids=$(echo "$containers" | awk '{print $1}')
fi
nb=$(echo "$ids" | wc -l | tr -d ' ')
if [ "$(echo "$containers" | wc -l | tr -d ' ')" == "1" ]
then
    logwarn "⚠️ only one broker: the cluster is unavailable while it restarts (start the example with playground run --enable-multiple-brokers for a real rolling restart)"
fi

if ! get_cluster_health
then
    if [[ -z "$force" ]]
    then
        logerror "❌ cluster is not healthy before the rolling restart: $(cluster_health_one_line)"
        logerror "   check it with 'playground broker health', or use --force to restart anyway"
        exit 1
    fi
    logwarn "⚠️ cluster is not healthy before the rolling restart ($(cluster_health_one_line)), restarting anyway (--force)"
fi

start_time=$SECONDS
i=0
for id in $ids
do
    i=$((i + 1))
    get_broker_container_of_id "$id" || exit 1
    container="$broker_id_container"
    broker_start_time=$SECONDS
    log "🔄 [$i/$nb] Restarting broker $id (container $container)"
    docker restart -t 60 "$container" > /dev/null || exit 1
    wait_for_broker_registered "$id" "$max_wait" || exit 1
    wait_for_cluster_healthy $((max_wait - (SECONDS - broker_start_time))) || {
        logerror "❌ rolling restart stopped after broker $id: the next brokers were not restarted"
        exit 1
    }
    log "✅ [$i/$nb] broker $id restarted, cluster is healthy ($((SECONDS - broker_start_time))s)"
done
log "🎉 rolling restart of brokers $(echo $ids | tr ' ' ',') done in $((SECONDS - start_time))s"
