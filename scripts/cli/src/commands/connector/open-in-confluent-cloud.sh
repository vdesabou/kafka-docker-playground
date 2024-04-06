connector="${args[--connector]}"

connector_type=$(playground state get run.connector_type)

if [ "$connector_type" != "$CONNECTOR_TYPE_FULLY_MANAGED" ] && [ "$connector_type" != "$CONNECTOR_TYPE_CUSTOM" ]
then
    log "connector open-in-confluent-cloud command is not supported with $connector_type connector"
    exit 0
fi

if [[ ! -n "$connector" ]]
then
    connector=$(playground get-connector-list)
    if [ "$connector" == "" ]
    then
        log "💤 No $connector_type connector is running !"
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
for connector in "${items[@]}"
do
    get_ccloud_connect
    handle_ccloud_connect_rest_api "curl -s --request GET \"https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector/status\" --header \"authorization: Basic $authorization\""
    connectorId=$(get_ccloud_connector_lcc $connector)

    type=$(echo "$curl_output" | jq -r '.type')
    TYPE=""
    if [ "$type" == "sink" ]
    then
        TYPE="sinks"
    else
        TYPE="sources"
    fi

    log "🤖 Open $connector_type connector $connector ($connectorId) in Confluent Cloud dashboard"
    open "https://confluent.cloud/environments/$environment/clusters/$cluster/connectors/$TYPE/$connector?granularity=PT1M&interval=3600000&label=Last%20hour"
done