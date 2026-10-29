topic="${args[--topic]}"
partition="${args[--partition]}"
leader="${args[--leader]}"
unclean="${args[--unclean]}"
verbose="${args[--verbose]}"

current=$(get_topic_partition_assignment "$topic")
if [[ -z "$current" ]]
then
    logerror "❌ topic $topic not found"
    exit 1
fi
if [[ -n "$partition" ]]
then
    current=$(echo "$current" | awk -v only="$partition" '$1 == only')
    if [[ -z "$current" ]]
    then
        logerror "❌ topic $topic has no partition $partition"
        exit 1
    fi
fi

if [[ -n "$leader" ]]
then
    # put the broker first in the replicas of the partitions it does not lead yet (no data movement), then elect it
    plan_partitions=""
    while read -r p l r i
    do
        if ! echo "$r" | tr ',' '\n' | grep -qx "$leader"
        then
            others=$(echo "$r" | cut -d, -f2-)
            logerror "❌ broker $leader is not a replica of partition $p (replicas $r): move it there first, e.g. playground topic reassign --topic $topic --partition $p --replicas $leader${others:+,$others}"
            exit 1
        fi
        if [ "${r%%,*}" != "$leader" ]
        then
            new_replicas=$(echo "$leader,$(echo "$r" | tr ',' '\n' | grep -vx "$leader" | paste -sd, -)" | sed 's/,$//')
            plan_partitions="${plan_partitions:+$plan_partitions,}{\"topic\":\"$topic\",\"partition\":$p,\"replicas\":[$new_replicas]}"
            log "🔀 partition $p: replicas $r -> $new_replicas"
        fi
    done <<< "$current"
    if [[ -n "$plan_partitions" ]]
    then
        execute_partition_reassignment "{\"version\":1,\"partitions\":[$plan_partitions]}" "" "" 60 || exit 1
    fi
fi

election_type="PREFERRED"
if [[ -n "$unclean" ]]
then
    election_type="UNCLEAN"
fi
election_partitions=$(echo "$current" | awk -v topic="$topic" '{printf "%s{\"topic\":\"%s\",\"partition\":%s}", (NR > 1 ? "," : ""), topic, $1}')

log "👑 ${election_type} leader election on topic $topic${partition:+ partition $partition}"
output=$(echo "{\"partitions\":[$election_partitions]}" | run_kafka_admin_tool kafka-leader-election --election-type "$election_type" --path-to-json-file /dev/stdin 2>&1) || true
echo "$output" | grep -v -E "^$|SLF4J"
# "Valid replica already elected" is not an error: the leader is already the one asked for
if echo "$output" | grep -q -E "^Error|Election failed|Exception" && ! echo "$output" | grep -q "Successfully completed\|Valid replica already elected"
then
    logerror "❌ the leader election failed"
    print_topic_partition_assignment "$topic"
    exit 1
fi

print_topic_partition_assignment "$topic"

if [[ -n "$leader" ]]
then
    not_moved=$(get_topic_partition_assignment "$topic" | awk -v only="$partition" -v leader="$leader" '(only == "" || $1 == only) && $2 != leader {print $1}')
    if [[ -n "$not_moved" ]]
    then
        logerror "❌ broker $leader is not the leader of partition(s) $(echo $not_moved | tr ' ' ','): it must be in sync (ISR) to be elected"
        exit 1
    fi
    log "✅ broker $leader is the leader of topic $topic${partition:+ partition $partition}"
fi
