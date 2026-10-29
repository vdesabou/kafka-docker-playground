wait_healthy="${args[--wait-healthy]}"
max_wait="${args[--max-wait]}"
json="${args[--json]}"
verbose="${args[--verbose]}"

healthy=0
start_time=$SECONDS
while true
do
    if get_cluster_health
    then
        healthy=1
        break
    fi
    if [[ -z "$wait_healthy" ]] || [ $((SECONDS - start_time)) -ge $max_wait ]
    then
        break
    fi
    if [[ -z "$json" ]]
    then
        log "⏳ cluster not healthy yet ($(cluster_health_one_line)), waiting... ($((SECONDS - start_time))s/${max_wait}s)"
    fi
    sleep 5
done

if [[ -n "$json" ]]
then
    partitions_json='split("\n") | map(select(length > 0) | split(" ") | {
        topic: .[0],
        partition: (.[1] | tonumber),
        leader: (.[2] | tonumber? // -1),
        replicas: (.[3] | split(",") | map(tonumber? // empty)),
        isr: (.[4] | split(",") | map(tonumber? // empty))
    })'
    ids_json='split("\n") | map(select(length > 0) | tonumber)'
    jq -n \
        --argjson healthy "$([ $healthy -eq 1 ] && echo true || echo false)" \
        --arg error "$health_error" \
        --argjson registered "$(echo -n "$health_registered" | jq -R -s "$ids_json")" \
        --argjson fenced "$(echo -n "$health_fenced" | jq -R -s "$ids_json")" \
        --argjson not_registered "$(echo -n "$health_not_registered" | jq -R -s 'split("\n") | map(select(length > 0) | split(" ") | {id: (.[0] | tonumber), container: .[1]})')" \
        --argjson urp "$(echo -n "$health_urp" | jq -R -s "$partitions_json")" \
        --argjson under_min_isr "$(echo -n "$health_under_min_isr" | jq -R -s "$partitions_json")" \
        --argjson rf_below_min_isr "$(echo -n "$health_rf_below_min_isr" | jq -R -s 'split("\n") | map(select(length > 0) | split(" ") | .[0]) | unique')" \
        --argjson unavailable "$(echo -n "$health_unavailable" | jq -R -s "$partitions_json")" \
        --argjson quorum "$(echo -n "$health_quorum" | jq -R -s 'split("\n") | map(select(length > 0) | split(" ") | {id: (.[0] | tonumber), status: .[1], log_end_offset: (.[2] | tonumber), lag: (.[3] | tonumber), seconds_since_caught_up: (.[4] | tonumber)})')" \
        --arg quorum_error "$health_quorum_error" \
        '{
            healthy: $healthy,
            error: (if $error == "" then null else $error end),
            brokers: { registered: $registered, fenced: $fenced, not_registered: $not_registered },
            under_replicated_partitions: $urp,
            under_min_isr_partitions: $under_min_isr,
            topics_with_replication_factor_below_min_isr: $rf_below_min_isr,
            unavailable_partitions: $unavailable,
            kraft_quorum: (if $quorum_error != "" then { error: $quorum_error } elif ($quorum | length) == 0 then null else { nodes: $quorum } end)
        }'
    [ $healthy -eq 1 ] && exit 0 || exit 1
fi

log "🩺 Health of the cluster"
if [[ -n "$health_error" ]]
then
    logerror "❌ $health_error"
    exit 1
fi

if [[ -z "$health_not_registered" ]] && [[ -z "$health_fenced" ]]
then
    log "✅ all brokers are registered: $(echo "$health_registered" | paste -sd, -)"
else
    log "🖥️ registered brokers: $(echo "$health_registered" | paste -sd, -)"
    while read -r id container
    do
        [[ -z "$id" ]] && continue
        if is_container_running "$container"
        then
            logerror "❌ broker $id (container $container) is not registered: still starting? (playground container logs -c $container --errors)"
        elif echo "$health_registered" | grep -q -x "$id"
        then
            logerror "❌ broker $id (container $container) is stopped, still registered until its session times out (playground broker start --broker $id)"
        else
            logerror "❌ broker $id (container $container) is not registered: it is stopped (playground broker start --broker $id)"
        fi
    done <<< "$health_not_registered"
    for id in $health_fenced
    do
        logerror "❌ broker $id is fenced: registered, but not caught up with the cluster metadata"
    done
fi

# prints the partitions ($2) found by a kafka-topics check ($1: label), at most 20
function print_partitions () {
    local label="$1" partitions="$2" count
    if [[ -z "$partitions" ]]
    then
        log "✅ no $label partition"
        return
    fi
    count=$(echo "$partitions" | wc -l | tr -d ' ')
    logerror "❌ $count $label partitions"
    {
        echo "TOPIC PARTITION LEADER REPLICAS ISR"
        echo "$partitions" | head -20
    } | column -t
    if [ "$count" -gt 20 ]
    then
        echo "... and $((count - 20)) more"
    fi
}

print_partitions "under-replicated" "$health_urp"
print_partitions "under min.insync.replicas" "$health_under_min_isr"
print_partitions "unavailable (no leader)" "$health_unavailable"
if [[ -n "$health_rf_below_min_isr" ]]
then
    logwarn "⚠️ topics with a replication factor below min.insync.replicas (acks=all producers to them always fail with NotEnoughReplicasException): $(echo "$health_rf_below_min_isr" | awk '{print $1}' | sort -u | paste -sd, - | sed 's/,/, /g')"
fi

if [[ -n "$health_quorum_error" ]]
then
    logerror "❌ KRaft quorum not available (kafka-metadata-quorum describe --replication):"
    echo "$health_quorum_error"
elif [[ -n "$health_quorum" ]]
then
    log "🗳️ KRaft quorum: leader is node $health_quorum_leader"
    {
        printf 'NODE\tSTATUS\tLOG_END_OFFSET\tLAG\tLAST_CAUGHT_UP\n'
        echo "$health_quorum" | awk 'BEGIN { OFS = "\t" } {
            caught = ($5 < 0) ? "never" : $5 "s ago"
            if ($5 > 30 || $5 < 0) caught = caught " ⚠️"
            print $1, $2, $3, $4, caught
        }'
    } | column -t -s $'\t'
fi

if [ $healthy -eq 1 ]
then
    log "✅ cluster is healthy"
else
    logerror "❌ cluster is not healthy: $(cluster_health_one_line)"
    exit 1
fi
