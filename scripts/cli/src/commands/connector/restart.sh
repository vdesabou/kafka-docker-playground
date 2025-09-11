connector="${args[--connector]}"
verbose="${args[--verbose]}"
task_id="${args[--task-id]}"

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

if [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
then
    log "connector restart command is not supported with $connector_type connector"
    exit 0
fi

items=($connector)
length=${#items[@]}
if ((length > 1))
then
    log "✨ --connector flag was not provided, applying command to all connectors"
fi
for connector in "${items[@]}"
do
    if [[ -n "$task_id" ]]; then
        log "🔄 Restarting $connector_type connector $connector task $task_id"
    else
        log "🔄 Restarting $connector_type connector $connector"
    fi
    
    if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] #|| [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
    then
        get_ccloud_connect
        if [[ -n "$task_id" ]]; then
            handle_ccloud_connect_rest_api "curl -s --request POST \"https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector/tasks/$task_id/restart\" --header \"authorization: Basic $authorization\""
        else
            handle_ccloud_connect_rest_api "curl -s --request POST \"https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector/restart\" --header \"authorization: Basic $authorization\""
        fi
    else
            tag=$(docker ps --format '{{.Image}}' | grep -E 'confluentinc/cp-.*-connect-.*:' | awk -F':' '{print $2}')
            if [ $? != 0 ] || [ "$tag" == "" ]
            then
                logerror "Could not find current CP version from docker ps"
                exit 1
            fi
        get_connect_url_and_security
        
        if [[ -n "$task_id" ]]; then
            # Restart specific task
            log "🤹‍♂️ Restart task $task_id"
            handle_onprem_connect_rest_api "curl $security -s -X POST -H \"Content-Type: application/json\" \"$connect_url/connectors/$connector/tasks/$task_id/restart\""
        elif ! version_gt $tag "6.9.9"
        then
            # For older versions, restart all tasks individually
            handle_onprem_connect_rest_api "curl $security -s -X GET \"$connect_url/connectors/$connector/tasks"

            task_ids=$(echo "$curl_output" | jq -r '.[].id.task')

            for task_id_loop in $task_ids
            do
                log "🤹‍♂️ Restart task $task_id_loop"
                handle_onprem_connect_rest_api "curl $security -s -X POST -H \"Content-Type: application/json\" \"$connect_url/connectors/$connector/tasks/$task_id_loop/restart\""
            done
        else
            # For newer versions, restart entire connector
            handle_onprem_connect_rest_api "curl $security -s -X POST -H \"Content-Type: application/json\" \"$connect_url/connectors/$connector/restart?includeTasks=true&onlyFailed=false\""
        fi
    fi

    if [[ -n "$task_id" ]]; then
        log "🔄 $connector_type connector $connector task $task_id has been restarted successfully"
    else
        log "🔄 $connector_type connector $connector has been restarted successfully"
    fi
done
sleep 3
playground connector status --connector $connector