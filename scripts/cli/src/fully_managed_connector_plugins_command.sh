get_ccloud_connect
verbose="${args[--verbose]}"

log "🧩 Displaying all connector plugins installed"
if [[ -n "$verbose" ]]
then
    log "🐞 curl command used"
    echo "curl -s --request GET \"https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connector-plugins\" \
--header \"authorization: Basic $authorization\" | jq -r '.[] | [.class , .version , .type] | @tsv' | column -t"
fi
curl -s --request GET "https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connector-plugins" \
--header "authorization: Basic $authorization" | jq -r '.[] | [.class , .version , .type] | @tsv' | column -t
