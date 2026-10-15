topic="${args[--topic]}"
min_expected_messages="${args[--min-expected-messages]}"
max_wait="${args[--max-wait]}"
interval="${args[--interval]}"

log "⏳ Waiting up to $max_wait seconds for topic $topic to contain at least $min_expected_messages records"
start_time=$SECONDS
last_count=""
while true
do
    # a topic that does not exist yet prints nothing: counts as empty
    set +e
    count=$(playground --output-level WARN topic get-number-records --topic "$topic" 2>/dev/null | grep -E '^[0-9]+$' | tail -1)
    set -e
    count=${count:-0}
    elapsed=$((SECONDS - start_time))

    if [ "$count" -ge "$min_expected_messages" ]
    then
        log "✅ topic $topic contains $count records (expected at least $min_expected_messages) after $elapsed seconds"
        break
    fi

    if [ "$count" != "$last_count" ]
    then
        log "⌛ topic $topic contains $count records (expected at least $min_expected_messages)"
        last_count="$count"
    fi

    if [ $elapsed -ge $max_wait ]
    then
        logerror "❌ topic $topic contains $count records after $max_wait seconds, expected at least $min_expected_messages"
        exit 1
    fi
    sleep $interval
done
