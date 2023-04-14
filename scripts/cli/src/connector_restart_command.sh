ret=$(get_connect_url_and_security)

connect_url=$(echo "$ret" | cut -d "@" -f 1)
security=$(echo "$ret" | cut -d "@" -f 2)

connector="${args[--connector]}"
log "Restarting connector $connector"
curl $security -s -X POST -H "Content-Type: application/json" "$connect_url/connectors/$connector/restart?includeTasks=true&onlyFailed=false" | jq .