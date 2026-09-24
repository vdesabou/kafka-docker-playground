connector="${args[--connector]}"
verbose="${args[--verbose]}"

connector_type=$(playground state get run.connector_type)

if [ "$connector_type" != "$CONNECTOR_TYPE_FULLY_MANAGED" ] && [ "$connector_type" != "$CONNECTOR_TYPE_CUSTOM" ]
then
    logerror "❌ playground connector error-recommendations only works with fully managed and custom connectors (connector type is $connector_type)"
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

get_ccloud_connect

items=($connector)
length=${#items[@]}
if ((length > 1))
then
    log "✨ --connector flag was not provided, applying command to all connectors"
fi
for connector in "${items[@]}"
do
    connectorId=$(get_ccloud_connector_lcc $connector)
    log "💡 Error recommendations for $connector_type connector $connector ($connectorId)"
    curl_request="curl -s --request GET \"https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector/error-recommendations\" --header \"authorization: Basic $authorization\""
    if [[ -n "$verbose" ]]
    then
        log "🐞 curl command used"
        echo "$curl_request"
    fi
    # not using handle_ccloud_connect_rest_api: a 400 error is the normal answer for a healthy connector
    eval "curl_output=\$($curl_request)"

    error_message=$(echo "$curl_output" | jq -r 'if (.error | type) == "object" then .error.message // empty else .message // empty end' 2>/dev/null || true)
    if [[ "$error_message" == "could not generate recommendations as error stack trace is not available"* ]]
    then
        log "✅ No error recommendations available: the connector has no failure stack trace (healthy, or it failed only at config validation, see 'playground connector status')"
        continue
    fi
    if [ -n "$error_message" ]
    then
        logerror "❌ Failed to get error recommendations: $error_message"
        continue
    fi

    nb_recommendations=$(echo "$curl_output" | jq -r '.recommendations // [] | length' 2>/dev/null || true)
    if [[ ! "$nb_recommendations" =~ ^[0-9]+$ ]]
    then
        logerror "❌ Unexpected response:"
        echo "$curl_output"
        continue
    fi
    if [ "$nb_recommendations" == "0" ]
    then
        log "✅ No error recommendations available"
        continue
    fi
    echo "$curl_output" | jq -r '.recommendations[] | if type == "string" then "👉 " + . else . end'
done
