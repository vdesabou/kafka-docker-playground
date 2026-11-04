container="${args[--container]}"
keep_requests="${args[--keep-requests]}"

http_server_resolve "$container"
clear_requests="true"
if [[ -n "$keep_requests" ]]
then
    clear_requests="false"
fi
response=$(http_server_call PUT "/reset?requests=$clear_requests") || { logerror "❌ could not reach the http server in $http_server_container"; exit 1; }
if ! jq -e '.message | test("reset")' > /dev/null 2>&1 <<< "$response"
then
    http_server_old_image_error
fi
log "🔄 $http_server_container reset: answers 200 at once with {} as body, connections kept open$( [[ -z "$keep_requests" ]] && echo ", received requests forgotten")"
