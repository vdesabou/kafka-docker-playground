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

items=($connector)
length=${#items[@]}
if ((length > 1))
then
    log "✨ --connector flag was not provided, applying command to all connectors"
fi
for connector in "${items[@]}"
do
    set +e
    maybe_id=""
    if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
    then
        get_ccloud_connect
        handle_ccloud_connect_rest_api "curl -s --request GET \"https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector/status\" --header \"authorization: Basic $authorization\""
        connectorId=$(get_ccloud_connector_lcc $connector)
        maybe_id=" ($connectorId)"

        log "🧩 Displaying status for $connector_type connector $connector${maybe_id}"

        printf "%-30s %-12s %-60s %-50s\n" "Name" "Status" "Tasks" "Stack Trace"
        echo "-------------------------------------------------------------------------------------------------------------"
        status=$(echo "$curl_output" | jq -r '.connector.state')

        if [ "$status" == "RUNNING" ]
        then
            status="✅ RUNNING"
        elif [ "$status" == "PAUSED" ]
        then
            status="⏸️  PAUSED"
        elif [ "$status" == "FAILED" ]
        then
            status="❌ FAILED"
        elif [ "$status" == "STOPPED" ]
        then
            status="🛑 STOPPED"
        else
            status="🤔 UNKNOWN"
        fi
        
        tasks=$(echo "$curl_output" | jq -r '.tasks[] | "\(.id):\(.state)"' | tr '\n' ',' | sed 's/,$/\n/')
        
        if [[ "$tasks" == *"RUNNING"* ]]
        then
            tasks="${tasks//RUNNING/🟢 RUNNING}"
        elif [[ "$tasks" == *"PAUSED"* ]]
        then
            tasks="${tasks//PAUSED/⏸️  PAUSED}"
        elif [[ "$tasks" == *"STOPPED"* ]]
        then
            tasks="${tasks//STOPPED/🛑  STOPPED}"
        elif [[ "$tasks" == *"FAILED"* ]]
        then
            tasks="${tasks//FAILED/🛑 FAILED}"
        else
            tasks="🤔 N/A"
        fi
        
        stacktrace_connector=$(echo "$curl_output" | jq -r '.connector.trace | select(length > 0)')
        errors_from_trace=$(echo "$curl_output" | jq -r '.errors_from_trace[0].error | select(length > 0)')
        validation_errors=$(echo "$curl_output" | jq -r '.validation_errors[0] | select(length > 0)')
        stacktrace=""
        if [ "$stacktrace_connector" != "" ]
        then
            stacktrace="connector: $stacktrace_connector"
        fi

        if [ "$errors_from_trace" != "" ]
        then
            stacktrace="$stacktrace errors_from_trace: $errors_from_trace"
        fi

        if [ "$validation_errors" != "" ]
        then
            stacktrace="$stacktrace validation_errors: $validation_errors"
        fi

        if [ -z "$stacktrace" ]
        then
            stacktrace="-"
        fi

        printf "%-30s %-12s %-30s %-50s\n" "$connector" "$status" "$tasks" "$stacktrace"
        echo "-------------------------------------------------------------------------------------------------------------"
    else
        log "🧩 Displaying status for $connector_type connector $connector"
        get_connect_url_and_security
        handle_onprem_connect_rest_api "curl -s $security \"$connect_url/connectors/$connector/status\""

        printf "%-30s %-12s %-60s %-50s\n" "Name" "Status" "Tasks" "Stack Trace"
        echo "-------------------------------------------------------------------------------------------------------------"
        status=$(echo "$curl_output" | jq -r '.connector.state')

        if [ "$status" == "RUNNING" ]
        then
            status="✅ RUNNING"
        elif [ "$status" == "PAUSED" ]
        then
            status="⏸️  PAUSED"
        elif [ "$status" == "FAILED" ]
        then
            status="❌ FAILED"
        elif [ "$status" == "STOPPED" ]
        then
            status="🛑 STOPPED"
        else
            status="🤔 UNKNOWN"
        fi
        
        tasks=$(echo "$curl_output" | jq -r '.tasks[] | "\(.id):\(.state)[\(.worker_id)]"' | tr '\n' ',' | sed 's/,$/\n/' | sed 's/:8083//g' | sed 's/:8283//g' | sed 's/:8383//g')
        
        if [[ "$tasks" == *"RUNNING"* ]]
        then
            tasks="${tasks//RUNNING/🟢 RUNNING}"
        elif [[ "$tasks" == *"PAUSED"* ]]
        then
            tasks="${tasks//PAUSED/⏸️  PAUSED}"
        elif [[ "$tasks" == *"STOPPED"* ]]
        then
            tasks="${tasks//STOPPED/🛑  STOPPED}"
        elif [[ "$tasks" == *"FAILED"* ]]
        then
            tasks="${tasks//FAILED/🛑 FAILED}"
        else
            tasks="🤔 N/A"
        fi
        
        stacktrace_connector=$(echo "$curl_output" | jq -r '.connector.trace | select(length > 0)')
        stacktrace_tasks=$(echo "$curl_output" | jq -r '.tasks[].trace | select(length > 0)')
        stacktrace=""
        if [ "$stacktrace_connector" != "" ]
        then
            stacktrace="connector: $stacktrace_connector"
        fi

        if [ "$stacktrace_tasks" != "" ]
        then
            stacktrace="$stacktrace tasks: $stacktrace_tasks"
        fi

        if [ -z "$stacktrace" ]
        then
            stacktrace="-"
        fi

        printf "%-30s %-12s %-30s %-50s\n" "$connector" "$status" "$tasks" "$stacktrace"
        echo "-------------------------------------------------------------------------------------------------------------"
    fi
    set -e
done