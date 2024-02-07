verbose="${args[--verbose]}"
connector="${args[--connector]}"

connector_type=$(playground state get run.connector_type)

if [[ ! -n "$connector" ]]
then
    connector=$(playground get-connector-list)
    if [ "$connector" == "" ]
    then
        logerror "💤 No $connector_type connector is running !"
        exit 1
    fi
fi

items=($connector)
length=${#items[@]}
if ((length > 1))
then
    log "✨ --connector flag was not provided, applying command to all connectors"
    check_if_continue
fi
for connector in ${items[@]}
do
    log "❌ Deleting $connector_type connector $connector"
    if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
    then
        get_ccloud_connect
        handle_ccloud_connect_rest_api "curl -s --request DELETE \"https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector\" --header \"authorization: Basic $authorization\""
    else
        get_connect_url_and_security
        handle_onprem_connect_rest_api "curl $security -s -X DELETE \"$connect_url/connectors/$connector\""
    fi

    echo "$curl_output" | jq .
done