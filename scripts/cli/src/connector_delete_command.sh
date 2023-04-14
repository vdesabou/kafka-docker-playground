ret=$(get_connect_url_and_security)

connect_url=$(echo "$ret" | cut -d "@" -f 1)
security=$(echo "$ret" | cut -d "@" -f 2)

connector="${args[--connector]}"
log "Deleting connector $connector"
curl $security -s -X DELETE "$connect_url/connectors/$connector" | jq .