topic="${args[--topic]}"
to_topic="${args[--to-topic]}"
from="${args[--from]}"
to="${args[--to]}"
wait="${args[--wait]}"
max_wait="${args[--max-wait]}"
json="${args[--json]}"
verbose="${args[--verbose]}"

get_environment_used
to_topic=${to_topic:-$topic}

if [[ "$environment" == mdc* ]]
then
    if [[ -z "$from" ]] || [[ -z "$to" ]]
    then
        logerror "❌ $environment runs two clusters: pass the source with --from us|europe and the destination with --to us|europe"
        exit 1
    fi
    if [[ "$from" == "$to" ]] && [[ "$to_topic" == "$topic" ]]
    then
        logerror "❌ the source and the destination are the same topic: change --to, or set --to-topic"
        exit 1
    fi
    from_label="$topic ($from)"
    to_label="$to_topic ($to)"
else
    if [[ -n "$from" ]] || [[ -n "$to" ]]
    then
        logwarn "--from and --to are only used in the mdc-* environments: ignored"
    fi
    from=""
    to=""
    if [[ "$to_topic" == "$topic" ]]
    then
        logerror "❌ the source and the destination are the same topic: set --to-topic"
        exit 1
    fi
    from_label="$topic"
    to_label="$to_topic"
fi

maybe_verbose=""
if [[ -n "$verbose" ]]
then
    maybe_verbose="--verbose"
fi

# "<partition> <earliest> <latest>" for every partition of topic $1 in cluster $2 (empty: the cluster of the environment)
function compare_get_offsets () {
    PLAYGROUND_CLUSTER="$2" playground --output-level ERROR topic get-offsets --topic "$1" $maybe_verbose 2> /dev/null | awk 'NF == 4 && $1 ~ /^[0-9]+$/ { print $1, $2, $3 }'
}

start_time=$SECONDS
while true
do
    from_offsets=$(compare_get_offsets "$topic" "$from")
    if [[ -z "$from_offsets" ]]
    then
        logerror "❌ topic $from_label does not exist or has no partition"
        exit 1
    fi
    to_offsets=$(compare_get_offsets "$to_topic" "$to")

    # "<partition> <from earliest> <from latest> <to earliest> <to latest>", "-" for a partition missing on one side
    rows=$(awk 'NF == 0 { next }
        FNR == NR { fe[$1] = $2; fl[$1] = $3; p[$1] = 1; next }
        { te[$1] = $2; tl[$1] = $3; p[$1] = 1 }
        END { for (k in p) print k, (k in fe ? fe[k] : "-"), (k in fl ? fl[k] : "-"), (k in te ? te[k] : "-"), (k in tl ? tl[k] : "-") }' \
        <(echo "$from_offsets") <(echo "$to_offsets") | sort -n)
    from_records=$(echo "$rows" | awk '$2 != "-" { n += $3 - $2 } END { print n + 0 }')
    to_records=$(echo "$rows" | awk '$4 != "-" { n += $5 - $4 } END { print n + 0 }')
    missing=$((from_records - to_records))
    from_partitions=$(echo "$from_offsets" | grep -c . || true)
    to_partitions=$(echo "$to_offsets" | grep -c . || true)

    if [[ -z "$wait" ]] || { [[ -n "$to_offsets" ]] && [ $missing -le 0 ]; } || [ $((SECONDS - start_time)) -ge $max_wait ]
    then
        break
    fi
    if [[ -z "$json" ]]
    then
        if [[ -z "$to_offsets" ]]
        then
            log "⏳ topic $to_label does not exist yet, waiting... ($((SECONDS - start_time))s/${max_wait}s)"
        else
            log "⏳ $to_label misses $missing records of $from_label, waiting... ($((SECONDS - start_time))s/${max_wait}s)"
        fi
    fi
    sleep 5
done

in_sync=false
if [[ -n "$to_offsets" ]] && [ $missing -le 0 ]
then
    in_sync=true
fi

if [[ -n "$json" ]]
then
    echo "$rows" | jq -R -s \
        --arg from_cluster "$from" --arg from_topic "$topic" \
        --arg to_cluster "$to" --arg to_topic "$to_topic" \
        --argjson from_records "$from_records" --argjson to_records "$to_records" \
        --argjson to_exists "$([[ -n "$to_offsets" ]] && echo true || echo false)" \
        --argjson in_sync "$in_sync" '
        def side(e; l): if e == "-" then null else {earliest: (e | tonumber), latest: (l | tonumber), records: ((l | tonumber) - (e | tonumber))} end;
        {
            from: {cluster: (if $from_cluster == "" then null else $from_cluster end), topic: $from_topic, records: $from_records},
            to: {cluster: (if $to_cluster == "" then null else $to_cluster end), topic: $to_topic, exists: $to_exists, records: $to_records},
            missing: ($from_records - $to_records),
            in_sync: $in_sync,
            partitions: (split("\n") | map(select(length > 0) | split(" ") | {
                partition: (.[0] | tonumber),
                from: side(.[1]; .[2]),
                to: side(.[3]; .[4])
            }))
        }'
else
    log "🔀 Comparing $from_label with $to_label"
    printf "%-10s %-14s %-14s %-14s %-14s %-14s %-14s\n" "PARTITION" "FROM-EARLIEST" "FROM-LATEST" "FROM-RECORDS" "TO-EARLIEST" "TO-LATEST" "TO-RECORDS"
    echo "$rows" | awk '{
        fr = ($2 == "-") ? "-" : $3 - $2
        tr = ($4 == "-") ? "-" : $5 - $4
        printf "%-10s %-14s %-14s %-14s %-14s %-14s %-14s\n", $1, $2, $3, fr, $4, $5, tr
    }'
    printf "%-10s %-14s %-14s %-14s %-14s %-14s %-14s\n" "TOTAL" "" "" "$from_records" "" "" "$to_records"
fi

if [[ -z "$to_offsets" ]]
then
    [[ -z "$json" ]] && logerror "❌ topic $to_label does not exist"
    exit 1
fi
if [[ -z "$json" ]] && [ "$from_partitions" != "$to_partitions" ]
then
    logwarn "⚠️ $from_label has $from_partitions partitions, $to_label has $to_partitions: the records are not compared partition by partition"
fi
if [ $missing -gt 0 ]
then
    [[ -z "$json" ]] && logerror "❌ $to_label misses $missing records of $from_label ($to_records of $from_records)"
    exit 1
fi
if [[ -z "$json" ]]
then
    if [ $missing -lt 0 ]
    then
        logwarn "⚠️ $to_label has $((-missing)) more records than $from_label: duplicates (a replication that restarted), other producers on the destination, or records already deleted by retention in the source"
    else
        log "✅ $to_label has as many records as $from_label ($from_records)"
    fi
fi
