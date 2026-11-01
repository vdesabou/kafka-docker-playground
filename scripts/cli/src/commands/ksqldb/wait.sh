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

# true when every input topic of the query $1 is empty (its sources from EXPLAIN, their topic from DESCRIBE): such a
# query never commits offsets, and has nothing to process
function query_inputs_empty () {
    local query_id="$1" query_sources source topic nb
    if ! query_sources=$(ksqldb_rest_statement "EXPLAIN $query_id;")
    then
        return 1
    fi
    for source in $(echo "$query_sources" | jq -r '.[0].queryDescription.sources[]?')
    do
        topic=$(ksqldb_rest_statement "DESCRIBE \`$source\`;" | jq -r '.[0].sourceDescription.topic // empty')
        [[ -z "$topic" ]] && return 1
        nb=$(playground topic get-number-records --topic "$topic" 2> /dev/null | tail -1)
        if [[ ! "$nb" =~ ^[0-9]+$ ]] || [[ "$nb" -ne 0 ]]
        then
            return 1
        fi
    done
    return 0
}

log "⏳ Waiting up to ${max_wait}s for the queries writing to ${sources[*]} to be RUNNING and to have processed all their input records"
start=$SECONDS
last_log=$SECONDS
first_pass=1
no_commit_grace=20
declare -A no_commit_since=()
declare -A no_commit_warned=()
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
        # id, state and lag of each query writing to $s. A query that has not committed yet has no offsets in its
        # summary: its lag is unknown (empty)
        while IFS=$'\t' read -r query_id query_state query_lag
        do
            [[ -z "$query_id" ]] && continue
            if [[ "$query_state" != "RUNNING" ]]
            then
                pending="${pending}${query_id}: ${query_state}"$'\n'
            elif [[ -z "$query_lag" ]]
            then
                # no commit yet: either it has not processed its records yet, or its input topics are empty (nothing
                # to commit, ever): count the records of its input topics
                # Kafka Streams commits every few seconds once it has processed a record: still no commit after
                # $no_commit_grace seconds RUNNING means nothing to process from where it started (empty input, or
                # auto.offset.reset latest)
                if [[ -z "${no_commit_since[$query_id]}" ]]
                then
                    no_commit_since[$query_id]=$SECONDS
                fi
                if query_inputs_empty "$query_id"
                then
                    continue
                elif [ $((SECONDS - no_commit_since[$query_id])) -ge $no_commit_grace ]
                then
                    if [[ -z "${no_commit_warned[$query_id]}" ]]
                    then
                        logwarn "⚠️ $query_id is RUNNING but has not committed any offset after ${no_commit_grace}s: nothing to process from where it started (auto.offset.reset is latest unless SET 'auto.offset.reset' = 'earliest' was sent with its CREATE)"
                        no_commit_warned[$query_id]=1
                    fi
                    continue
                fi
                pending="${pending}${query_id}: RUNNING, no committed offsets yet"$'\n'
            elif [[ "$query_lag" -gt 0 ]]
            then
                pending="${pending}${query_id}: RUNNING, lag ${query_lag}"$'\n'
            fi
        done < <(echo "$description" | jq -r '
            ((.queryOffsetSummaries // []) | map({key: (.groupId | sub("^_confluent-ksql-.*query_"; "")),
                value: ([.topicSummaries[]?.offsets[]? | (.logEndOffset - (.consumerOffset // 0))] | if length == 0 then null else add end)}) | from_entries) as $lag
            | .writeQueries[] | [.id, (.state // "?"), (($lag[.id] // "") | tostring)] | @tsv')
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
