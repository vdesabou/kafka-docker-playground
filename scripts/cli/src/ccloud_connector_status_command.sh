ret=$(get_ccloud_connect)

environment=$(echo "$ret" | cut -d "@" -f 1)
cluster=$(echo "$ret" | cut -d "@" -f 2)
authorization=$(echo "$ret" | cut -d "@" -f 3)

curl -s --request GET "https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors?expand=status" \
--header "authorization: Basic $authorization" | jq .