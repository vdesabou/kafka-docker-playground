eval "sources=(${args[--source]:-})"
max_wait="${args[--max-wait]}"

get_ksqldb_url_and_security

if [ ${#sources[@]} -eq 0 ]
then
    # every sink of a persistent query
    if ! queries=$(ksqldb_rest_statement "SHOW QUERIES;")
    then
        logerror "❌ could not list the queries: $(echo "$queries" | jq -r '.message // .' 2>/dev/null)"
        exit 1
    fi
    while IFS= read -r s
    do
        [[ -n "$s" ]] && sources+=("$s")
    done < <(echo "$queries" | jq -r '[.[0].queries[] | select(.queryType == "PERSISTENT") | .sinks[]] | unique[]')
    if [ ${#sources[@]} -eq 0 ]
    then
        log "🔎 No persistent query, nothing to wait for"
        exit 0
    fi
fi

log "⏳ Waiting up to ${max_wait}s for the queries writing to ${sources[*]} to be RUNNING and to have processed all their input records"
start=$SECONDS
last_log=$SECONDS
first_pass=1
while true
do
    pending=""
    for s in "${sources[@]}"
    do
        if ! response=$(ksqldb_rest_statement "DESCRIBE $s EXTENDED;")
        then
            logerror "❌ could not describe $s: $(echo "$response" | jq -r '.message // .' 2>/dev/null)"
            exit 1
        fi
        description=$(echo "$response" | jq '.[0].sourceDescription')
        if [[ "$(echo "$description" | jq '.writeQueries | length')" -eq 0 ]]
        then
            if [[ -n "$first_pass" ]]
            then
                logwarn "⚠️ no query writes to $s, nothing to wait for on it"
            fi
            continue
        fi
        failed=$(echo "$description" | jq -r '.writeQueries[] | select(.state == "ERROR") | .id')
        if [[ -n "$failed" ]]
        then
            logerror "❌ query $failed writing to $s is in ERROR"
            logerror "   🎓 playground ksqldb describe --source $s, playground container logs -c ksqldb-server --errors"
            exit 1
        fi
        # a query that has not committed yet has no offsets in its summary (or no summary): its lag is unknown, wait
        state=$(echo "$description" | jq -r '
            ((.queryOffsetSummaries // []) | map({key: (.groupId | sub("^_confluent-ksql-.*query_"; "")),
                value: ([.topicSummaries[]?.offsets[]? | (.logEndOffset - (.consumerOffset // 0))] | if length == 0 then null else add end)}) | from_entries) as $lag
            | .writeQueries[] | select(.state != "RUNNING" or ($lag[.id] == null) or ($lag[.id] > 0))
            | "\(.id): \(.state // "?"), lag \($lag[.id] // "unknown, no committed offsets yet")"')
        if [[ -n "$state" ]]
        then
            pending="${pending}${state}"$'\n'
        fi
    done

    if [[ -z "$pending" ]]
    then
        log "✅ the queries writing to ${sources[*]} are RUNNING and have no lag (after $((SECONDS - start))s)"
        exit 0
    fi

    if [ $((SECONDS - start)) -ge "$max_wait" ]
    then
        logerror "❌ still waiting after ${max_wait}s:"
        printf '%s' "$pending" | sed 's/^/   /' >&2
        logerror "   🎓 playground ksqldb describe --source <sink> shows the statistics and errors, increase --max-wait for a big input"
        exit 1
    fi

    if [ $((SECONDS - last_log)) -ge 10 ]
    then
        printf '%s' "$pending" | while IFS= read -r line; do log "   ⏳ $line"; done
        last_log=$SECONDS
    fi
    first_pass=""
    sleep 2
done
