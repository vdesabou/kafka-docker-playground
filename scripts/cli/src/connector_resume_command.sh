ret=$(get_connect_url_and_security)

connect_url=$(echo "$ret" | cut -d "@" -f 1)
security=$(echo "$ret" | cut -d "@" -f 2)

connector="${args[--connector]}"
log "Resuming connector $connector"
curl $security -s -X PUT -H "Content-Type: application/json" "$connect_url/connectors/$connector/resume"  | jq .

playground connector status