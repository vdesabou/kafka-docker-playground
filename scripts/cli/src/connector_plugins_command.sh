get_connect_url_and_security

log "🧩 Displaying all connector plugins installed"
curl $security -s -X GET -H "Content-Type: application/json" "$connect_url/connector-plugins" | jq -r '.[] | [.class , .version , .type] | @tsv' | column -t