connector="${args[--connector]}"
verbose="${args[--verbose]}"

connector_type=$(playground state get run.connector_type)

if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
then
    log "connector offsets get command is not available with $connector_type connector"
    exit 0
fi

if [[ ! -n "$connector" ]]
then
    connector=$(playground get-connector-list)
    if [ "$connector" == "" ]
    then
        logerror "💤 No $connector_type connector is running !"
        exit 1
    fi
fi

tag=$(docker ps --format '{{.Image}}' | egrep 'confluentinc/cp-.*-connect-base:' | awk -F':' '{print $2}')
if [ $? != 0 ] || [ "$tag" == "" ]
then
    logerror "❌ could not find current CP version from docker ps"
    exit 1
fi

if ! version_gt $tag "7.5.99"; then
    logerror "❌ stop connector is available since CP 7.5 only"
    exit 1
fi

items=($connector)
length=${#items[@]}
if ((length > 1))
then
    log "✨ --connector flag was not provided, applying command to all connectors"
fi
for connector in ${items[@]}
do
    maybe_id=""
    if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
    then
        # should not happen but keeping it just in case
        get_ccloud_connect
        handle_ccloud_connect_rest_api "curl -s --request GET \"https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector/status\" --header \"authorization: Basic $authorization\""
        connectorId=$(get_ccloud_connector_lcc $connector)
        maybe_id=" ($connectorId)"
    else
        get_connect_url_and_security
        handle_onprem_connect_rest_api "curl -s $security \"$connect_url/connectors/$connector/status\""
    fi

    type=$(echo "$curl_output" | jq -r '.type')
    if [ "$type" != "source" ]
    then
        logwarn "⏭️ Skipping $type $connector_type connector ${connector}${maybe_id}, it must be a source to show the offsets"
        continue 
    fi

    log "📏 Getting offsets for $connector_type connector $connector"
    get_connect_url_and_security
    handle_onprem_connect_rest_api "curl $security -s -X GET \"$connect_url/connectors/$connector/offsets\""

    echo "$curl_output" | jq .
done