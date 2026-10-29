topic="${args[--topic]}"
partition="${args[--partition]}"
replicas="${args[--replicas]}"
brokers="${args[--brokers]}"
throttle="${args[--throttle]}"
dry_run="${args[--dry-run]}"
no_wait="${args[--no-wait]}"
verify_only="${args[--verify-only]}"
max_wait="${args[--max-wait]}"
verbose="${args[--verbose]}"

# plan of the last --no-wait reassignment of the topic, for --verify-only
plan_file="/tmp/playground-reassign-${topic}.json"

if [[ -n "$verify_only" ]]
then
    if [ ! -f "$plan_file" ]
    then
        logerror "❌ no reassignment started with --no-wait for topic $topic ($plan_file not found)"
        exit 1
    fi
    log "🔎 Progress of the reassignment of topic $topic"
    rc=0
    wait_for_partition_reassignment "$(cat "$plan_file")" 0 || rc=$?
    if [ $rc -eq 2 ]
    then
        log "🎓 check again later with the same command"
        exit 0
    elif [ $rc -ne 0 ]
    then
        exit 1
    fi
    rm -f "$plan_file"
    print_topic_partition_assignment "$topic"
    exit 0
fi

if [[ -z "$replicas" ]] && [[ -z "$brokers" ]]
then
    logerror "❌ set --replicas (replicas of the partitions) or --brokers (brokers to spread the partitions over)"
    exit 1
fi

current=$(get_topic_partition_assignment "$topic")
if [[ -z "$current" ]]
then
    logerror "❌ topic $topic not found"
    exit 1
fi

broker_ids=$(get_broker_ids)
for id in $(echo "${replicas}${brokers}" | tr ',' ' ')
do
    if ! [[ "$id" =~ ^[0-9]+$ ]] || ! echo "$broker_ids" | grep -qx "$id"
    then
        logerror "❌ broker $id does not exist, the brokers are: $(echo $broker_ids | tr ' ' ',')"
        if [ "$(echo "$broker_ids" | wc -l | tr -d ' ')" == "1" ]
        then
            logerror "   only one broker is running: start the example with playground run --enable-multiple-brokers"
        fi
        exit 1
    fi
done

if [[ -n "$replicas" ]]
then
    if [ "$(echo "$replicas" | tr ',' '\n' | sort | uniq -d)" != "" ]
    then
        logerror "❌ --replicas $replicas lists a broker twice"
        exit 1
    fi
    if [[ -n "$partition" ]] && ! echo "$current" | awk '{print $1}' | grep -qx "$partition"
    then
        logerror "❌ topic $topic has no partition $partition"
        exit 1
    fi
    plan=$(echo "$current" | awk -v topic="$topic" -v only="$partition" -v replicas="$replicas" '
        BEGIN { printf "{\"version\":1,\"partitions\":[" ; first = 1 }
        only == "" || $1 == only {
            if (!first) printf ","
            printf "{\"topic\":\"%s\",\"partition\":%s,\"replicas\":[%s]}", topic, $1, replicas
            first = 0
        }
        END { print "]}" }')
else
    output=$(echo "{\"topics\":[{\"topic\":\"$topic\"}],\"version\":1}" | run_kafka_admin_tool kafka-reassign-partitions --topics-to-move-json-file /dev/stdin --broker-list "$brokers" --generate 2>&1)
    plan=$(echo "$output" | grep -A1 "Proposed partition reassignment configuration" | tail -1)
    if ! echo "$plan" | jq -e '.partitions' > /dev/null 2>&1
    then
        logerror "❌ kafka-reassign-partitions --generate failed:"
        echo "$output" | grep -v -E "^$|SLF4J"
        exit 1
    fi
fi

# partition, current replicas, new replicas
changes=$(join <(echo "$current" | awk '{print $1, $3}' | sort) <(echo "$plan" | jq -r '.partitions[] | "\(.partition) \(.replicas | map(tostring) | join(","))"' | sort) | sort -n)

log "🔀 Reassignment of topic $topic"
printf '%-10s %-16s %-16s\n' "PARTITION" "REPLICAS" "NEW REPLICAS"
echo "$changes" | while read -r p old new
do
    if [ "$old" == "$new" ]
    then
        printf '%-10s %-16s %-16s\n' "$p" "$old" "(unchanged)"
    else
        printf '%-10s %-16s %-16s\n' "$p" "$old" "$new"
    fi
done

if ! echo "$changes" | awk '$2 != $3 {found=1} END {exit !found}'
then
    log "🤷 nothing to reassign, the replicas are already the requested ones"
    exit 0
fi

if [[ -n "$dry_run" ]]
then
    log "🧪 dry run, nothing was changed: run again without --dry-run to apply"
    exit 0
fi

execute_partition_reassignment "$plan" "$throttle" "$no_wait" "$max_wait" || exit 1
if [[ -n "$no_wait" ]]
then
    echo "$plan" > "$plan_file"
    log "🎓 follow it with: playground topic reassign --topic $topic --verify-only"
    exit 0
fi

print_topic_partition_assignment "$topic"
if get_topic_partition_assignment "$topic" | awk '{split($3, r, ","); if ($2 != r[1]) found=1} END {exit !found}'
then
    log "🎓 move the leaders to the preferred replicas with: playground topic elect-leader --topic $topic"
fi
