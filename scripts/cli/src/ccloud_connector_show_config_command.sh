ret=$(get_ccloud_connect)

environment=$(echo "$ret" | cut -d "@" -f 1)
cluster=$(echo "$ret" | cut -d "@" -f 2)
authorization=$(echo "$ret" | cut -d "@" -f 3)

connector="${args[--connector]}"

if [[ ! -n "$connector" ]]
then
    log "✨ --connector flag was not provided, applying command to all ccloud connectors"
    connector=$(playground get-ccloud-connector-list)
    if [ "$connector" == "" ]
    then
        logerror "💤 No ccloud connector is running !"
        exit 1
    fi
fi

items=($connector)
for connector in ${items[@]}
do
    log "🧰 Current config for ccloud connector $connector"
    json_config=$(curl $security -s -X GET -H "Content-Type: application/json" "https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector/config" --header "authorization: Basic $authorization")
    echo "playground ccloud-connector create-or-update --connector $connector << EOF"
    echo "$json_config" | jq -S .
    echo "EOF"
done