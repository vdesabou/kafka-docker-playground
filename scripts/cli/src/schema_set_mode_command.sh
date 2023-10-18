subject="${args[--subject]}"
mode="${args[--mode]}"

ret=$(get_sr_url_and_security)

sr_url=$(echo "$ret" | cut -d "@" -f 1)
sr_security=$(echo "$ret" | cut -d "@" -f 2)

log "🔏 Set mode for subject ${subject} to $mode"
curl $sr_security -s -X PUT -H "Content-Type: application/vnd.schemaregistry.v1+json" --data "{\"mode\": \"$mode\"}" "${sr_url}/mode/${subject}" | jq .