connector="${args[--connector]}"
verbose="${args[--verbose]}"

connector_type=$(playground state get run.connector_type)
environment=$(playground state get run.environment)

if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
then
    log "connector stop command is not available with $connector_type connector"
    exit 0
fi

if [[ "$environment" == "cfk" ]]
then
    log "ℹ️ CFK does not expose a dedicated stop endpoint; using REST API to stop the connector"
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

if [[ "$environment" != "cfk" ]]
then
    tag=$(docker ps --format '{{.Image}}' | grep -E 'confluentinc/cp-.*-connect.*:' | awk -F':' '{print $2}')
    if [ $? != 0 ] || [ "$tag" == "" ]
    then
        logerror "❌ could not find current CP version from docker ps"
        exit 1
    fi

    if ! version_gt $tag "7.4.99"; then
        logerror "❌ stop connector is available since CP 7.5 only"
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
    log "🛑 Stopping $connector_type connector $connector"
    get_connect_url_and_security
    handle_onprem_connect_rest_api "curl $security -s -X PUT -H \"Content-Type: application/json\" \"$connect_url/connectors/$connector/stop\""

    log "🛑 $connector_type connector $connector has been stopped successfully"

    sleep 1
    playground connector status --connector $connector
done