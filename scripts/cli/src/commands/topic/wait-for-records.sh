topic="${args[--topic]}"
min_expected_messages="${args[--min-expected-messages]}"
max_wait="${args[--max-wait]}"
interval="${args[--interval]}"

log "⏳ Waiting up to $max_wait seconds for topic $topic to contain at least $min_expected_messages records"
start_time=$SECONDS
last_count=""
while true
do
    # a topic that does not exist yet prints nothing and succeeds: counts as empty. A failure (environment down,
    # authentication) is not an empty topic: fail after 3 in a row instead of waiting until --max-wait
    set +e
    output=$(playground --output-level WARN topic get-number-records --topic "$topic" 2>&1)
    rc=$?
    set -e
    if [ $rc -ne 0 ]
    then
        nb_failures=$((${nb_failures:-0} + 1))
        if [ $nb_failures -ge 3 ]
        then
            logerror "❌ could not count the records of topic $topic:"
            echo "$output" | tail -10
            exit 1
        fi
    else
        nb_failures=0
    fi
    count=$(echo "$output" | grep -E '^[0-9]+$' | tail -1)
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
