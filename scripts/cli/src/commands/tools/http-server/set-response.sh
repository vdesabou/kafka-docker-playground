container="${args[--container]}"
status_code="${args[--status-code]}"
body="${args[--body]}"
delay="${args[--delay]}"
close_connection="${args[--close-connection]}"

if [[ -z "$body" && -z "$status_code" && -z "$delay" && -z "$close_connection" ]]
then
    # the body can come on stdin (heredoc), when nothing else is set
    body=$(read_stdin_if_any)
fi
if [[ -z "${body//[[:space:]]/}" && -z "$status_code" && -z "$delay" && -z "$close_connection" ]]
then
    logerror "❌ nothing to set: pass --status-code, --body (or a JSON body on stdin), --delay and/or --close-connection"
    exit 1
fi
if [[ -n "${body//[[:space:]]/}" ]] && ! jq -e 'type == "object" or type == "array"' > /dev/null 2>&1 <<< "$body"
then
    logerror "❌ --body must be a JSON object or array, got: $(head -c 200 <<< "$body")"
    exit 1
fi

http_server_resolve "$container"

# set_one <endpoint> <json>: fails with the message of the server when it refuses the value
function set_one () {
    local response
    response=$(http_server_call PUT "$1" "$2") || { logerror "❌ could not reach the http server in $http_server_container"; exit 1; }
    if ! jq -e '.message' > /dev/null 2>&1 <<< "$response" || jq -e '.message | test("Please provide")' > /dev/null 2>&1 <<< "$response"
    then
        logerror "❌ $1 refused: $response"
        exit 1
    fi
}

if [[ -n "${body//[[:space:]]/}" ]]
then
    set_one /set-response-body "$body"
fi
if [[ -n "$status_code" ]]
then
    set_one /set-response-error-code "{\"errorCode\": $status_code}"
fi
if [[ -n "$delay" ]]
then
    set_one /set-response-time "{\"delay\": $delay}"
fi
if [[ -n "$close_connection" ]]
then
    set_one /set-connection-closed ""
fi

# the resulting settings (an image older than the requests endpoint only gets the summary of what was set)
response=$(http_server_call GET /received-requests 2>/dev/null)
if jq -e '.settings' > /dev/null 2>&1 <<< "$response"
then
    jq -r --arg c "$http_server_container" '.settings | "🌐 \($c) now answers \(if .close_connection then "by closing the connection" else "\(.status_code) after \(.delay_ms) ms, body \(.body | tojson | if length > 120 then .[0:120] + "…" else . end)" end)"' <<< "$response" | while IFS= read -r line; do log "$line"; done
else
    log "🌐 $http_server_container: set${status_code:+ status code $status_code}${delay:+ delay ${delay} ms}${body:+ body}${close_connection:+ connection closed}"
fi
