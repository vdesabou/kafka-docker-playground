container="${args[--container]}"
broker="${args[--broker]}"
user="${args[--user]}"
password="${args[--password]}"
mq_vhost="${args[--vhost]:-/}"
mq_vpn="${args[--vpn]:-default}"
queue="${args[--queue]}"
topic="${args[--topic]}"
min_expected="${args[--min-expected-messages]}"
max_expected="${args[--max-expected-messages]}"
max_wait="${args[--max-wait]}"
interval="${args[--interval]}"

mq_resolve_container "$container" "$broker" || exit 2
mq_resolve_credentials "$user" "$password"
mq_check_destination "$queue" "$topic" wait || exit 2
if [[ "$mq_broker" == "mqtt" ]]
then
    mq_mqtt_check_login || exit 2
fi

if [[ "$mq_broker" == "mqtt" ]]
then
    # MQTT keeps no queue to count: count the messages received while subscribed
    log "👂 Waiting up to $max_wait seconds for $min_expected message(s) on topic $mq_dest ($(mq_describe)): counted while subscribed, from now on"
    count=$(mq_exec mosquitto_sub -h localhost -p 1883 -u "$mq_user" -P "$mq_password" -t "$mq_dest" -C "$min_expected" -W "$max_wait" < /dev/null 2>/dev/null | grep -c '' || true)
    if [[ "$count" -ge "$min_expected" ]]
    then
        log "✅ $count message(s) received on topic $mq_dest (expected at least $min_expected)"
        exit 0
    fi
    logerror "❌ $count message(s) received on topic $mq_dest after $max_wait seconds, expected at least $min_expected"
    exit 1
fi


what="queue $mq_dest"
if [[ -n "$max_expected" ]]
then
    log "⏳ Waiting up to $max_wait seconds for $what to contain at most $max_expected message(s) ($(mq_describe))"
else
    log "⏳ Waiting up to $max_wait seconds for $what to contain at least $min_expected message(s) ($(mq_describe))"
fi
start_time=$SECONDS
last_state=""
nb_failures=0
while true
do
    depth=$(mq_depth)
    elapsed=$((SECONDS - start_time))
    if [[ -z "$depth" ]]
    then
        nb_failures=$((nb_failures + 1))
        if [ $nb_failures -ge 3 ]
        then
            logerror "❌ could not read the number of messages of $what in $mq_container"
            exit 2
        fi
        state="could not be read"
        depth=-1
    else
        nb_failures=0
        state="contains $depth message(s)"
    fi
    if [[ -n "$max_expected" ]]
    then
        if [[ "$depth" -ge 0 && "$depth" -le "$max_expected" ]]
        then
            log "✅ $what $state (expected at most $max_expected) after $elapsed seconds"
            exit 0
        fi
    elif [[ "$depth" -ge "$min_expected" ]]
    then
        log "✅ $what $state (expected at least $min_expected) after $elapsed seconds"
        exit 0
    fi
    if [[ "$state" != "$last_state" ]]
    then
        log "⌛ $what $state"
        last_state="$state"
    fi
    if [ $elapsed -ge $max_wait ]
    then
        logerror "❌ $what $state after $max_wait seconds, expected $([[ -n "$max_expected" ]] && echo "at most $max_expected" || echo "at least $min_expected")"
        exit 1
    fi
    sleep $interval
done
