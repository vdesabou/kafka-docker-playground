api_versions="${args[--api-versions]}"
broker="${args[--broker]}"
verbose="${args[--verbose]}"

if [[ -n "$api_versions" ]]
then
    output=$(run_kafka_admin_tool kafka-broker-api-versions 2>&1 | grep -v -E "^WARNING|SLF4J|log4j" || true)
    if ! echo "$output" | grep -q -E "\(id: [0-9]+"
    then
        logerror "❌ kafka-broker-api-versions failed:"
        echo "$output" | grep -v -E "^[[:space:]]+at "
        exit 1
    fi
    if [[ -z "$broker" ]]
    then
        broker=$(echo "$output" | grep -o -E "\(id: [0-9]+" | grep -o -E "[0-9]+" | sort -n | head -1)
    fi
    block=$(echo "$output" | awk -v id="$broker" '
        /\(id: [0-9]+/ { keep = ($0 ~ "\\(id: " id " ") }
        keep')
    if [[ -z "$block" ]]
    then
        logerror "❌ broker $broker does not exist, brokers are: $(echo "$output" | grep -o -E "\(id: [0-9]+" | grep -o -E "[0-9]+" | sort -n | paste -sd, -)"
        exit 1
    fi
    log "🔌 API versions supported by broker $broker (min to max, [usable: N] is the version this client picks)"
    echo "$block"
    exit 0
fi

api_output=$(run_kafka_admin_tool kafka-broker-api-versions 2>/dev/null | grep -E "\(id: [0-9]+" || true)
if [[ -z "$api_output" ]]
then
    logerror "❌ no broker answers, is an environment running? (playground status)"
    exit 1
fi

cp_tag=$(get_running_cp_tag)
log "🖥️ Brokers$([[ -n "$cp_tag" ]] && echo " (CP $cp_tag)")"
get_environment_used
containers=""
[[ "$environment" != cfk* ]] && containers=$(get_broker_containers)
{
    printf 'ID\tENDPOINT\tRACK\tFENCED\tCONTAINER\n'
    echo "$api_output" | sed -E 's/^([^ ]+) \(id: ([0-9]+) rack: ([^ )]+)( isFenced: ([a-z]+))?.*/\2 \1 \3 \5/' | sort -n | while read -r id endpoint rack fenced
    do
        container=$(echo "$containers" | awk -v id="$id" '$1 == id { print $2 }')
        printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$endpoint" "$rack" "${fenced:--}" "${container:--}"
    done
    # broker containers that are not registered (stopped or starting)
    echo "$containers" | while read -r id container
    do
        [[ -z "$id" ]] && continue
        if ! echo "$api_output" | grep -q "(id: $id "
        then
            state=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null)
            printf '%s\t%s\t%s\t%s\t%s\n' "$id" "(not registered)" "-" "-" "$container ($state) ⚠️"
        fi
    done
} | column -t -s $'\t'

output=$(run_kafka_admin_subcommand_tool kafka-metadata-quorum describe --status 2>&1) || true
if echo "$output" | grep -q "^LeaderId"
then
    field() { echo "$output" | grep -E "^$1:" | sed -E "s/^$1:[[:space:]]*//" ; }
    voters=$(field CurrentVoters | grep -o -E '"id": [0-9]+' | grep -o -E "[0-9]+" | paste -sd, -)
    [[ -z "$voters" ]] && voters=$(field CurrentVoters | tr -d '[] ')
    observers=$(field CurrentObservers | grep -o -E '"id": [0-9]+' | grep -o -E "[0-9]+" | sort -n | paste -sd, -)
    [[ -z "$observers" ]] && observers=$(field CurrentObservers | tr -d '[] ')
    log "🗳️ KRaft"
    printf '%-22s %s\n' "Cluster id:" "$(field ClusterId)"
    printf '%-22s %s\n' "Active controller:" "$(field LeaderId) (epoch $(field LeaderEpoch))"
    printf '%-22s %s\n' "Voters (controllers):" "$voters"
    printf '%-22s %s\n' "Observers (brokers):" "$observers"
    printf '%-22s %s\n' "Max follower lag:" "$(field MaxFollowerLag) records, $(field MaxFollowerLagTimeMs) ms"
elif echo "$output" | grep -q -E "UnsupportedVersion|ZooKeeper|zookeeper"
then
    log "🐘 ZooKeeper mode (no KRaft quorum)"
else
    logwarn "⚠️ could not describe the KRaft quorum:"
    echo "$output" | grep -v -E "^[[:space:]]+at " | grep -E "Error|Exception" | head -3
fi

output=$(run_kafka_admin_subcommand_tool kafka-features describe 2>&1) || true
if echo "$output" | grep -q "^Feature:"
then
    log "🏷️ Features"
    {
        printf 'FEATURE\tFINALIZED\tSUPPORTED\n'
        echo "$output" | grep "^Feature:" | awk '{
            feature = $2 ; finalized = "" ; min = "" ; max = ""
            for (i = 3; i <= NF; i++) {
                if ($i == "SupportedMinVersion:") min = $(i+1)
                if ($i == "SupportedMaxVersion:") max = $(i+1)
                if ($i == "FinalizedVersionLevel:") { finalized = $(i+1) ; if ($(i+2) ~ /^[0-9]+$/) finalized = finalized " " $(i+2) }
            }
            printf "%s\t%s\t%s to %s\n", feature, finalized, min, max
        }'
    } | column -t -s $'\t'
fi
log "🎓 health of the cluster: playground broker health, API versions of a broker: playground broker describe --api-versions"
