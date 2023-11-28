get_ccloud_connect

log "🧩 Displaying all connector plugins installed"
curl -s --request GET "https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connector-plugins" \
--header "authorization: Basic $authorization" | jq -r '.[] | [.class , .version , .type] | @tsv' | column -t
