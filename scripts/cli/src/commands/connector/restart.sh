connector="${args[--connector]}"
verbose="${args[--verbose]}"
task_id="${args[--task-id]}"
only_failed="${args[--only-failed]}"

connector_type=$(playground state get run.connector_type)
environment=$(playground state get run.environment)

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
restarted=()
for connector in "${items[@]}"
do
    if [[ -n "$only_failed" ]]
    then
        if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ]
        then
            get_ccloud_connect
            connect_api="https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector"
            curl_auth="--header \"authorization: Basic $authorization\""
            handle_ccloud_connect_rest_api "curl -s $curl_auth \"$connect_api/status\""
        else
            get_connect_url_and_security
            connect_api="$connect_url/connectors/$connector"
            curl_auth="$security"
            handle_onprem_connect_rest_api "curl $security -s \"$connect_api/status\""
        fi
        if [ $? -ne 0 ] || [ -z "$curl_output" ]
        then
            logerror "❌ Could not get the status of $connector_type connector $connector"
            exit 1
        fi
        connector_state=$(echo "$curl_output" | jq -r '.connector.state')
        failed_task_ids=$(echo "$curl_output" | jq -r '.tasks[]? | select(.state == "FAILED") | .id' | tr '\n' ' ')
        if [ "$connector_state" != "FAILED" ] && [ -z "${failed_task_ids// /}" ]
        then
            log "✅ Nothing is FAILED in $connector_type connector $connector, skipping it"
            continue
        fi
        what=""
        [ "$connector_state" == "FAILED" ] && what="connector instance"
        if [ -n "${failed_task_ids// /}" ]
        then
            [ -n "$what" ] && what="$what and "
            what="${what}FAILED task(s) ${failed_task_ids% }"
        fi
        log "🩹 Restarting the $what of $connector_type connector $connector"

        tag=""
        if [ "$connector_type" != "$CONNECTOR_TYPE_FULLY_MANAGED" ] && [[ "$environment" != cfk* ]]
        then
            tag=$(get_running_cp_tag)
        fi
        if [ "$connector_type" != "$CONNECTOR_TYPE_FULLY_MANAGED" ] && { [[ "$environment" == cfk* ]] || { [ -n "$tag" ] && version_gt $tag "6.9.9"; }; }
        then
            # KIP-745: one call restarts the FAILED connector instance and the FAILED tasks only
            handle_onprem_connect_rest_api "curl $security -s -X POST -H \"Content-Type: application/json\" \"$connect_api/restart?includeTasks=true&onlyFailed=true\"" || exit 1
        else
            if [ "$connector_state" == "FAILED" ]
            then
                if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ]
                then
                    handle_ccloud_connect_rest_api "curl -s --request POST $curl_auth \"$connect_api/restart\"" || exit 1
                else
                    handle_onprem_connect_rest_api "curl $security -s -X POST -H \"Content-Type: application/json\" \"$connect_api/restart\"" || exit 1
                fi
            fi
            for failed_task_id in $failed_task_ids
            do
                log "🤹‍♂️ Restart task $failed_task_id"
                if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ]
                then
                    handle_ccloud_connect_rest_api "curl -s --request POST $curl_auth \"$connect_api/tasks/$failed_task_id/restart\"" || exit 1
                else
                    handle_onprem_connect_rest_api "curl $security -s -X POST -H \"Content-Type: application/json\" \"$connect_api/tasks/$failed_task_id/restart\"" || exit 1
                fi
            done
        fi
        restarted+=("$connector")
        continue
    fi

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
    elif [[ "$environment" == cfk* ]]
    then
        if [[ -n "$task_id" ]]; then
            log "☸️ kubectl annotate connector $connector -n confluent platform.confluent.io/restart-task=$task_id --overwrite"
            kubectl annotate connector "$connector" -n confluent platform.confluent.io/restart-task="$task_id" --overwrite >/dev/null
        else
            log "☸️ kubectl annotate connector $connector -n confluent platform.confluent.io/restart-connector=true --overwrite"
            kubectl annotate connector "$connector" -n confluent platform.confluent.io/restart-connector="true" --overwrite >/dev/null
        fi
    else
            tag=$(get_running_cp_tag)
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
            handle_onprem_connect_rest_api "curl $security -s -X GET \"$connect_url/connectors/$connector/tasks\""

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
    restarted+=("$connector")
done
if [ ${#restarted[@]} -eq 0 ]
then
    exit 0
fi
sleep 3
for connector in "${restarted[@]}"
do
	playground connector status --connector $connector
done