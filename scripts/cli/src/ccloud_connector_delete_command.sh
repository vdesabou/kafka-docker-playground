ret=$(get_ccloud_connect)

environment=$(echo "$ret" | cut -d "@" -f 1)
cluster=$(echo "$ret" | cut -d "@" -f 2)
authorization=$(echo "$ret" | cut -d "@" -f 3)

connector="${args[--connector]}"

if [[ ! -n "$connector" ]]
then
    logwarn "--connector flag was not provided, applying command to all ccloud connectors"
    check_if_continue
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
    log "❌ Deleting ccloud connector $connector"
    curl -s --request DELETE "https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector" --header "authorization: Basic $authorization" | jq .
done
sleep 3
playground ccloud-connector status