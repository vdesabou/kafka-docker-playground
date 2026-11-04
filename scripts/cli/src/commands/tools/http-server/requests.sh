container="${args[--container]}"
last="${args[--last]}"
method="${args[--method]}"
grep_regex="${args[--grep]}"
show_headers="${args[--headers]}"
full="${args[--full]}"
json="${args[--json]}"
min_expected="${args[--min-expected-requests]}"
max_wait="${args[--max-wait]}"
clear="${args[--clear]}"

http_server_resolve "$container"

method=$(tr '[:lower:]' '[:upper:]' <<< "$method")
# the requests matching --method and --grep (on the url and the body)
jq_filter='[.requests[] | select(($method == "" or .method == $method) and ($grep == "" or (((.url) + " " + (.body | if type == "string" then . else tojson end)) | test($grep))))]'

if [[ -n "$min_expected" ]]
then
    log "⏳ Waiting up to $max_wait seconds for $http_server_container to receive at least $min_expected request(s)${method:+ $method}${grep_regex:+ matching $grep_regex}"
    start_time=$SECONDS
    last_count=""
    while true
    do
        response=$(http_server_received_requests) || exit 1
        count=$(jq --arg method "$method" --arg grep "$grep_regex" "$jq_filter | length" <<< "$response")
        elapsed=$((SECONDS - start_time))
        if [ "$count" -ge "$min_expected" ]
        then
            log "✅ $http_server_container received $count request(s) (expected at least $min_expected) after $elapsed seconds"
            break
        fi
        if [ "$count" != "$last_count" ]
        then
            log "⌛ $http_server_container received $count request(s) (expected at least $min_expected)"
            last_count="$count"
        fi
        if [ $elapsed -ge $max_wait ]
        then
            logerror "❌ $http_server_container received $count request(s) after $max_wait seconds, expected at least $min_expected"
            exit 1
        fi
        sleep 2
    done
fi

response=$(http_server_received_requests) || exit 1
if [[ -n "$json" ]]
then
    jq --arg method "$method" --arg grep "$grep_regex" --argjson last "$last" \
        "{settings, total, kept, matched: ($jq_filter | length), requests: ($jq_filter | if \$last > 0 then .[-\$last:] else . end)}" <<< "$response"
else
    jq -r --arg method "$method" --arg grep "$grep_regex" --argjson last "$last" '
        (.settings | "🌐 answers: \(if .close_connection then "connection closed" else "\(.status_code) after \(.delay_ms) ms, body \(.body | tojson | if length > 80 then .[0:80] + "…" else . end)" end)"),
        "📥 \(.total) request(s) received since the start or the last reset (\(.kept) kept)\(if $method != "" or $grep != "" then ", \('"$jq_filter"' | length) matching" else "" end)"' <<< "$response" | while IFS= read -r line; do log "$line"; done
    jq -r --arg method "$method" --arg grep "$grep_regex" --argjson last "$last" --arg headers "$show_headers" --arg full "$full" '
        '"$jq_filter"' | (if $last > 0 then .[-$last:] else . end)[] |
        "#\(.number) \(.time | sub("\\.[0-9]+Z$"; "Z") | fromdate | localtime | strftime("%H:%M:%S")) \(.method) \(.url) → \(.status)  \(.headers["content-type"] // "-"), \(.headers["content-length"] // "0") bytes",
        (if $headers != "" then (.headers | to_entries[] | "   \(.key): \(.value)") else empty end),
        (if .body == null then empty
         elif $full != "" then (.body | if type == "string" then . else tojson end | split("\n")[] | "   " + .)
         else "   " + (.body | if type == "string" then . else tojson end | gsub("\n"; " ") | if length > 300 then .[0:300] + "… (--full for the whole body)" else . end)
         end)' <<< "$response"
fi

if [[ -n "$clear" ]]
then
    http_server_call DELETE /received-requests > /dev/null && log "🧹 received requests cleared"
fi
