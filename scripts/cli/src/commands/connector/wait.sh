connector="${args[--connector]}"
verbose="${args[--verbose]}"
state="${args[--state]}"
max_wait="${args[--max-wait]}"
interval="${args[--interval]}"

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

if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
then
    get_ccloud_connect
else
    get_connect_url_and_security
fi

# sets connector_state and tasks_states (one state per task) from the REST API, empty if not available yet
function get_connector_states () {
    local connector="$1"
    connector_state=""
    tasks_states=""
    # the REST helpers log errors (404 while the connector is being created, worker still starting): keep the wait output quiet,
    # and call them as a condition so that their non-zero return does not abort the command (set -e)
    if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
    then
        if ! handle_ccloud_connect_rest_api "curl -s --request GET \"https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector/status\" --header \"authorization: Basic $authorization\"" > /dev/null 2>&1
        then
            return
        fi
    else
        if ! handle_onprem_connect_rest_api "curl -s $security \"$connect_url/connectors/$connector/status\"" > /dev/null 2>&1
        then
            return
        fi
    fi
    connector_state=$(echo "$curl_output" | jq -r '.connector.state // empty' 2>/dev/null)
    tasks_states=$(echo "$curl_output" | jq -r '.tasks[]?.state' 2>/dev/null)
}

# a connector can legitimately run without tasks (Replicator or MirrorMaker without matching topic yet, JDBC source
# without table): RUNNING with 0 tasks for that long is accepted, with a warning
zero_tasks_max_seconds=30

for connector in ${connector}
do
    log "⏳ Waiting up to $max_wait seconds for $connector_type connector $connector to be $state"
    start_time=$SECONDS
    last_seen=""
    running_seen=false
    zero_tasks_since=""
    while true
    do
        get_connector_states "$connector"
        nb_tasks=$(echo "$tasks_states" | { grep -c . || true; } | tr -d ' ')
        task_state_pattern="$state"
        # the tasks of a paused fully managed connector are STOPPED
        if [ "$state" == "PAUSED" ] && { [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]; }
        then
            task_state_pattern="PAUSED|STOPPED"
        fi
        nb_tasks_in_state=$(echo "$tasks_states" | { grep -cxE "$task_state_pattern" || true; } | tr -d ' ')
        elapsed=$((SECONDS - start_time))

        is_failed=false
        if [ "$connector_state" == "FAILED" ] || echo "$tasks_states" | grep -qx "FAILED"
        then
            is_failed=true
        fi

        # a task can fail while its connector stays RUNNING: FAILED means the connector or any of its tasks
        if [ "$state" == "FAILED" ] && [ "$is_failed" == true ]
        then
            log "✅ $connector_type connector $connector is FAILED after $elapsed seconds"
            set +e
            playground connector status --connector "$connector"
            break
        fi

        if [ "$state" == "RUNNING" ] && [ "$connector_state" == "RUNNING" ] && [ "$nb_tasks" == "0" ]
        then
            if [ -z "$zero_tasks_since" ]
            then
                zero_tasks_since=$elapsed
            elif [ $((elapsed - zero_tasks_since)) -ge $zero_tasks_max_seconds ]
            then
                logwarn "⚠️ $connector_type connector $connector is RUNNING without any task for $zero_tasks_max_seconds seconds (nothing to process yet?), not waiting for tasks"
                break
            fi
        else
            zero_tasks_since=""
        fi

        if [ "$state" != "FAILED" ] && [ "$connector_state" == "$state" ]
        then
            # a RUNNING connector without tasks is not processing anything yet, STOPPED connectors have no tasks
            if [ "$nb_tasks" == "$nb_tasks_in_state" ] && { [ "$state" != "RUNNING" ] || [ "$nb_tasks" -gt 0 ]; }
            then
                # a task is RUNNING before it processes its first record, and can fail right after:
                # RUNNING is only reached when it is still RUNNING at the next check
                if [ "$state" != "RUNNING" ] || [ "$running_seen" == true ]
                then
                    log "✅ $connector_type connector $connector is $state ($nb_tasks task(s)) after $elapsed seconds"
                    break
                fi
                running_seen=true
                sleep $interval
                continue
            fi
        fi
        running_seen=false

        if [ "$state" == "RUNNING" ] && [ "$is_failed" == true ]
        then
            logerror "❌ $connector_type connector $connector is FAILED, not waiting for it to be RUNNING"
            set +e
            playground connector status --connector "$connector"
            exit 1
        fi

        current="${connector_state:-not available} tasks: $(echo $tasks_states | tr ' ' ',')"
        if [ "$current" != "$last_seen" ]
        then
            log "⌛ $connector_type connector $connector is ${connector_state:-not available yet} ($nb_tasks_in_state/$nb_tasks task(s) $state)"
            last_seen="$current"
        fi

        if [ $elapsed -ge $max_wait ]
        then
            if [ -z "$connector_state" ]
            then
                logerror "❌ $connector_type connector $connector was not found after $max_wait seconds"
                exit 1
            fi
            logerror "❌ $connector_type connector $connector is not $state after $max_wait seconds"
            set +e
            playground connector status --connector "$connector"
            exit 1
        fi
        sleep $interval
    done
done
