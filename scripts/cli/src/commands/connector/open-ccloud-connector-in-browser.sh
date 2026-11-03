connector="${args[--connector]}"
browser="${args[--browser]}"
only_show_url="${args[--only-show-url]}"

connector_type=$(playground state get run.connector_type)

if [ "$connector_type" != "$CONNECTOR_TYPE_FULLY_MANAGED" ] && [ "$connector_type" != "$CONNECTOR_TYPE_CUSTOM" ]
then
    logerror "❌ connector open-ccloud-connector-in-browser command is not supported with $connector_type connector"
    exit 1
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

    url="https://confluent.cloud/environments/$environment/clusters/$cluster/connectors/$TYPE/$connector?granularity=PT1M&interval=3600000&label=Last%20hour"
    if [[ -n "$only_show_url" ]]
    then
        echo "$url"
    elif ! can_open_url
    then
        log "🔗 Cannot open browser, use url:"
        echo "$url"
    else
        if [[ -n "$browser" ]]
        then
            log "🤖 Open $connector_type connector $connector ($connectorId) in Confluent Cloud dashboard with browser $browser"
            open_url "https://confluent.cloud/environments/$environment/clusters/$cluster/connectors/$TYPE/$connector?granularity=PT1M&interval=3600000&label=Last%20hour" "$browser"
        else
            log "🤖 Open $connector_type connector $connector ($connectorId) in Confluent Cloud dashboard"
            open_url "https://confluent.cloud/environments/$environment/clusters/$cluster/connectors/$TYPE/$connector?granularity=PT1M&interval=3600000&label=Last%20hour"
        fi
    fi
done