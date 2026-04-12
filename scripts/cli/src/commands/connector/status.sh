connector="${args[--connector]}"
verbose="${args[--verbose]}"

# Configuration for retries
MAX_RETRIES=5
RETRY_INTERVAL=2

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
    
    # --- CLOUD / CUSTOM BLOCK ---
    if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
    then
        get_ccloud_connect
        connectorId=$(get_ccloud_connector_lcc $connector)
        maybe_id=" ($connectorId)"

        log "🧩 Displaying status for $connector_type connector $connector${maybe_id}"

        # Retry Logic
        attempt=1
        while [ $attempt -le $MAX_RETRIES ]; do
            handle_ccloud_connect_rest_api "curl -s --request GET \"https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector/status\" --header \"authorization: Basic $authorization\""
            
            # Check if we got a valid status
            status=$(echo "$curl_output" | jq -r '.connector.state')
            
            if [ "$status" != "null" ] && [ -n "$status" ]; then
                break # Valid status found, exit retry loop
            fi

            if [ $attempt -lt $MAX_RETRIES ]; then
                log "⚠️  API did not return a valid status (attempt $attempt/$MAX_RETRIES). Retrying in ${RETRY_INTERVAL}s..."
                sleep $RETRY_INTERVAL
            fi
            ((attempt++))
        done

        printf "%-30s %-12s %-60s %-50s\n" "Name" "Status" "Tasks" "Stack Trace"
        echo "-------------------------------------------------------------------------------------------------------------"
        
        # Status mapping (using the status retrieved from the loop)
        if [ "$status" == "RUNNING" ]; then status="✅ RUNNING"
        elif [ "$status" == "PAUSED" ]; then status="⏸️  PAUSED"
        elif [ "$status" == "FAILED" ]; then status="❌ FAILED"
        elif [ "$status" == "UNASSIGNED" ]; then status="⌛ UNASSIGNED"
        elif [ "$status" == "STOPPED" ]; then status="🛑 STOPPED"
        elif [ "$status" == "PROVISIONING" ]; then status="🏭 PROVISIONING"
        else status="🤔 UNKNOWN (API Error)"; fi
        
        tasks=$(echo "$curl_output" | jq -r '.tasks[] | "\(.id):\(.state)"' | tr '\n' ',' | sed 's/,$/\n/')
        
        # Task Mapping
        if [[ "$tasks" == *"RUNNING"* ]]; then tasks="${tasks//RUNNING/🟢 RUNNING}"
        elif [[ "$tasks" == *"PAUSED"* ]]; then tasks="${tasks//PAUSED/⏸️  PAUSED}"
        elif [[ "$tasks" == *"STOPPED"* ]]; then tasks="${tasks//STOPPED/🛑  STOPPED}"
        elif [[ "$tasks" == *"FAILED"* ]]; then tasks="${tasks//FAILED/🛑 FAILED}"
        elif [[ "$tasks" == *"UNASSIGNED"* ]]; then tasks="${tasks//UNASSIGNED/⌛ UNASSIGNED}"
        elif [[ "$tasks" == *"USER_ACTIONABLE_ERROR"* ]]; then tasks="${tasks//USER_ACTIONABLE_ERROR/💪 USER_ACTIONABLE_ERROR}"
        else tasks="🤔 N/A"; fi
        
        # Stacktrace Extraction
        stacktrace_connector=$(echo "$curl_output" | jq -r '.connector.trace | select(length > 0)')
        errors_from_trace=$(echo "$curl_output" | jq -r '.errors_from_trace[0].error | select(length > 0)')
        validation_errors=$(echo "$curl_output" | jq -r '.validation_errors[0] | select(length > 0)')
        stacktrace=""
        if [ "$stacktrace_connector" != "" ]; then stacktrace="connector: $stacktrace_connector"; fi
        if [ "$errors_from_trace" != "" ]; then stacktrace="$stacktrace errors_from_trace: $errors_from_trace"; fi
        if [ "$validation_errors" != "" ]; then stacktrace="$stacktrace validation_errors: $validation_errors"; fi
        if [ -z "$stacktrace" ]; then stacktrace="-"; fi

        printf "%-30s %-12s %-30s %-50s\n" "$connector" "$status" "$tasks" "$stacktrace"
        echo "-------------------------------------------------------------------------------------------------------------"

    # --- ON PREM BLOCK ---
    else
        log "🧩 Displaying status for $connector_type connector $connector"
        get_connect_url_and_security
        
        # Retry Logic
        attempt=1
        while [ $attempt -le $MAX_RETRIES ]; do
            handle_onprem_connect_rest_api "curl -s $security \"$connect_url/connectors/$connector/status\""
            
            # Check if we got a valid status
            status=$(echo "$curl_output" | jq -r '.connector.state')

            if [ "$status" != "null" ] && [ -n "$status" ]; then
                break # Valid status found
            fi

            if [ $attempt -lt $MAX_RETRIES ]; then
                log "⚠️  API did not return a valid status (attempt $attempt/$MAX_RETRIES). Retrying in ${RETRY_INTERVAL}s..."
                sleep $RETRY_INTERVAL
            fi
            ((attempt++))
        done

        if [ "$status" == "RUNNING" ]; then status="✅ RUNNING"
        elif [ "$status" == "PAUSED" ]; then status="⏸️  PAUSED"
        elif [ "$status" == "FAILED" ]; then status="❌ FAILED"
        elif [ "$status" == "UNASSIGNED" ]; then status="⌛ UNASSIGNED"
        elif [ "$status" == "STOPPED" ]; then status="🛑 STOPPED"
        else status="🤔 UNKNOWN (API Error)"; fi
        
        status_display="$status"
        tasks=$(echo "$curl_output" | jq -r '.tasks[] | "\(.id):\(.state)"' | tr '\n' ',' | sed 's/,$/\n/')

        if is_multiple_connect_workers_running
        then
            leader_name=$(playground --output-level WARN connector display-leader-name)
            leader_name=$(echo "$leader_name" | tr -d '[:space:]')
            
            connector_worker_id=$(echo "$curl_output" | jq -r '.connector.worker_id // empty' | sed 's/:8083$//' | sed 's/:8283$//' | sed 's/:8383$//')
            if [ -n "$connector_worker_id" ]
            then
                status_display="$status[$connector_worker_id]"
                if [ -n "$leader_name" ] && [ "$connector_worker_id" == "$leader_name" ]
                then
                    status_display="$status[$connector_worker_id 👑]"
                fi
            fi
            
            tasks=$(echo "$curl_output" | jq -r '.tasks[] | "\(.id):\(.state)[\(.worker_id)]"' | tr '\n' ',' | sed 's/,$/\n/' | sed 's/:8083//g' | sed 's/:8283//g' | sed 's/:8383//g')
            if [ -n "$leader_name" ]
            then
                tasks=$(echo "$tasks" | sed "s/\[$leader_name\]/[$leader_name 👑]/g")
            fi
        fi

        printf "%-30s %-12s %-60s %-50s\n" "Name" "Status" "Tasks" "Stack Trace"
        echo "-------------------------------------------------------------------------------------------------------------"
        
        if [[ "$tasks" == *"RUNNING"* ]]; then tasks="${tasks//RUNNING/🟢 RUNNING}"
        elif [[ "$tasks" == *"PAUSED"* ]]; then tasks="${tasks//PAUSED/⏸️  PAUSED}"
        elif [[ "$tasks" == *"STOPPED"* ]]; then tasks="${tasks//STOPPED/🛑  STOPPED}"
        elif [[ "$tasks" == *"FAILED"* ]]; then tasks="${tasks//FAILED/🛑 FAILED}"
        elif [[ "$tasks" == *"UNASSIGNED"* ]]; then tasks="${tasks//UNASSIGNED/⌛ UNASSIGNED}"
        else tasks="🤔 N/A"; fi
        
        stacktrace_connector=$(echo "$curl_output" | jq -r '.connector.trace | select(length > 0)')
        stacktrace_tasks=$(echo "$curl_output" | jq -r '.tasks[].trace | select(length > 0)')
        stacktrace=""
        if [ "$stacktrace_connector" != "" ]; then stacktrace="connector: $stacktrace_connector"; fi
        if [ "$stacktrace_tasks" != "" ]; then stacktrace="$stacktrace tasks: $stacktrace_tasks"; fi
        if [ -z "$stacktrace" ]; then stacktrace="-"; fi

        printf "%-30s %-12s %-30s %-50s\n" "$connector" "$status_display" "$tasks" "$stacktrace"
        echo "-------------------------------------------------------------------------------------------------------------"
    fi
    set -e
done