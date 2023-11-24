connector="${args[--connector]}"

if [[ ! -n "$connector" ]]
then
    logwarn "--connector flag was not provided, applying command to all ccloud connectors"
    check_if_continue
    connector=$(playground get-ccloud-connector-list)
    if [ $? -ne 0 ]
    then
        logerror "❌ Could not get list of connectors"
        echo "$connector"
        exit 1
    fi
    if [ "$connector" == "" ]
    then
        logerror "💤 No ccloud connector is running !"
        exit 1
    fi
    set -e
fi

items=($connector)
for connector in ${items[@]}
do
    log "❌ Deleting ccloud connector $connector"
    curl -s --request DELETE "https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector" --header "authorization: Basic $authorization" | jq .
done