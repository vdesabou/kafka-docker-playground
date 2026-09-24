group="${args[--group]}"
members="${args[--members]}"
state="${args[--state]}"
verbose="${args[--verbose]}"

# kafka-consumer-groups exits 0 on errors such as an unknown group, detect them from the output
function describe_group() {
    set +e
    output=$(run_kafka_admin_tool kafka-consumer-groups --describe --group "$group" "$@" 2>&1)
    set -e
    error=$(echo "$output" | grep -m1 "^Error: " || true)
    if [ -n "$error" ]
    then
        logerror "❌ Failed to describe consumer group $group: ${error#Error: }"
        exit 1
    fi
    echo "$output"
}

if [[ ! -n "$group" ]]
then
    log "✨ --group flag was not provided, applying command to all consumer groups"
    group=$(playground get-consumer-group-list)
    if [ "$group" == "" ]
    then
        logerror "❌ No consumer group found !"
        exit 1
    fi
fi

items=($group)
for group in "${items[@]}"
do
    log "🔬 Describing consumer group $group"
    if [[ -n "$state" ]]
    then
        describe_group --state
    fi
    if [[ -n "$members" ]]
    then
        describe_group --members --verbose
    fi
    if [[ -z "$state" ]] && [[ -z "$members" ]]
    then
        describe_group
        # LAG is the 6th column, it is "-" when the group has no committed offset for the partition
        total_lag=$(echo "$output" | awk '$1 != "GROUP" && $6 ~ /^[0-9]+$/ {sum += $6; found = 1} END {if (found) print sum}')
        if [ -n "$total_lag" ]
        then
            if [ "$total_lag" == "0" ]
            then
                log "🏁 Total lag for consumer group $group: 0"
            else
                log "🐢 Total lag for consumer group $group: $total_lag"
            fi
        fi
    fi
done
