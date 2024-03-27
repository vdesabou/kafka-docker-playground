connector="${args[--connector]}"
verbose="${args[--verbose]}"

connector_type=$(playground state get run.connector_type)

if [[ ! -n "$connector" ]]
then
    connector=$(playground get-connector-list)
    if [ "$connector" == "" ]
    then
        log "💤 No $connector_type connector is running !"
        exit 1
    fi
fi

if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
then
    log "connector restart command is not supported with $connector_type connector"
    exit 0
fi

tag=$(docker ps --format '{{.Image}}' | egrep 'confluentinc/cp-.*-connect-base:' | awk -F':' '{print $2}')
if [ $? != 0 ] || [ "$tag" == "" ]
then
    logerror "Could not find current CP version from docker ps"
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
    log "🔄 Restarting $connector_type connector $connector"

    get_connect_url_and_security
    log "🔄 Restarting connector $connector"
    if ! version_gt $tag "6.9.9"
    then
        handle_onprem_connect_rest_api "curl $security -s -X GET \"$connect_url/connectors/$connector/tasks"

        task_ids=$(echo "$curl_output" | jq -r '.[].id.task')

        for task_id in $task_ids
        do
            log "🤹‍♂️ Restart task $task_id"
            handle_onprem_connect_rest_api "curl $security -s -X POST -H \"Content-Type: application/json\" \"$connect_url/connectors/$connector/tasks/$task_id/restart\""
        done
    else
        handle_onprem_connect_rest_api "curl $security -s -X POST -H \"Content-Type: application/json\" \"$connect_url/connectors/$connector/restart?includeTasks=true&onlyFailed=false\""
    fi
    echo "$curl_output" | jq .
done
sleep 3
playground connector status --connector $connector