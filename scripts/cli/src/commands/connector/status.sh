connector="${args[--connector]}"
verbose="${args[--verbose]}"
json="${args[--json]}"
fail_on_error="${args[--fail-on-error]}"

# --json: the table and the nested commands write to stderr, only the JSON array goes to stdout (fd 3)
if [[ -n "$json" ]]
then
    exec 3>&1 1>&2
fi
json_entries=()
unhealthy=0

# Configuration for retries
MAX_RETRIES=5
RETRY_INTERVAL=2

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

items=($connector)
length=${#items[@]}
if ((length > 1))
then
    log "✨ --connector flag was not provided, applying command to all connectors"
fi

multiple_connect_workers_running=false
if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
then
    :
else
    if [[ "$environment" == cfk* ]]
    then
        cfk_connect_workers_count=$(kubectl -n confluent get pods -o name 2>/dev/null | sed 's#pod/##' | grep -E '^connect-[0-9]+$' | wc -l | tr -d '[:space:]')
        if [[ -n "$cfk_connect_workers_count" ]] && ((cfk_connect_workers_count > 1))
        then
            multiple_connect_workers_running=true
        fi
    elif is_multiple_connect_workers_running
    then
        multiple_connect_workers_running=true
        missing_connect_workers=""
        for worker in connect connect2 connect3
        do
            if ! is_container_running "$worker"
            then
                missing_connect_workers="$missing_connect_workers $worker"
            fi
        done
        if [ -n "$missing_connect_workers" ]
        then
            logwarn "⚠️ Connect workers not running:${missing_connect_workers}"
        fi
    fi

    if [[ "$multiple_connect_workers_running" == true ]] && [[ "$environment" != cfk* ]]
    then
        leader_name=$(playground --output-level WARN connector display-leader-name || true)
        leader_name=$(echo "$leader_name" | tr -d '[:space:]')
    fi
fi
# decorate every task state (an if/elif chain only decorated the first state found: 0:🟢 RUNNING,1:FAILED)
function decorate_task_states() {
    if [ -z "$1" ]
    then
        echo "🤔 N/A"
        return
    fi
    echo "$1" | sed -e 's/:RUNNING/:🟢 RUNNING/g' \
        -e 's/:PAUSED/:⏸️  PAUSED/g' \
        -e 's/:STOPPED/:⏹️  STOPPED/g' \
        -e 's/:FAILED/:🛑 FAILED/g' \
        -e 's/:UNASSIGNED/:⌛ UNASSIGNED/g' \
        -e 's/:RESTARTING/:🔄 RESTARTING/g' \
        -e 's/:USER_ACTIONABLE_ERROR/:💪 USER_ACTIONABLE_ERROR/g'
}

# true when the REST API answered "not found": retrying will not help
function is_not_found() {
    # self-managed: {"error_code":404}, Confluent Cloud API: {"error":{"code":404}}
    [ "$(echo "$curl_output" | jq -r '(.error_code // .error.code?) // empty' 2> /dev/null)" == "404" ]
}

for connector in "${items[@]}"
do
    set +e
    maybe_id=""
    connectorId=""
    curl_output=""
    
    if [[ "$environment" == cfk* ]]
    then
        # Display kubectl get connector output
        log "☸️ kubectl -n confluent get connector $connector"
        connector_status_json=$(kubectl -n confluent get connector "$connector" -o json 2>/dev/null || true)
        kubectl -n confluent get connector "$connector" 2>/dev/null || true
        echo ""

        if [[ -n "$connector_status_json" ]]
        then
            cfk_state=$(echo "$connector_status_json" | jq -r '.status.state // empty')
            connector_status=$(echo "$connector_status_json" | jq -r '.status.connectorStatus // empty')
            tasks_ready=$(echo "$connector_status_json" | jq -r '.status.tasksReady // empty')
            app_ready=$(echo "$connector_status_json" | jq -r '.status.conditions[]? | select(.type=="platform.confluent.io/app-ready") | .status' | head -1)
            reason=$(echo "$connector_status_json" | jq -r '.status.conditions[]? | select(.type=="platform.confluent.io/app-ready") | .reason' | head -1)
            message=$(echo "$connector_status_json" | jq -r '.status.conditions[]? | select(.type=="platform.confluent.io/app-ready") | .message' | head -1)

            if [[ -n "$cfk_state" || -n "$connector_status" || -n "$tasks_ready" || -n "$app_ready" || -n "$reason" || -n "$message" ]]
            then
                log "☸️ CFK status details"
                [[ -n "$cfk_state" ]] && log "   state: $cfk_state"
                [[ -n "$connector_status" ]] && log "   connectorStatus: $connector_status"
                [[ -n "$tasks_ready" ]] && log "   tasksReady: $tasks_ready"
                [[ -n "$app_ready" ]] && log "   app-ready: $app_ready"
                [[ -n "$reason" ]] && log "   reason: $reason"
                [[ -n "$message" ]] && log "   message: $message"
                echo ""

                if [[ "$reason" == "CreateFailed" ]]
                then
                    logerror "❌ CFK connector creation failed"
                    json_entries+=("$(jq -cn --arg name "$connector" --arg type "$connector_type" --arg message "$message" '{name: $name, type: $type, id: null, state: "CREATE_FAILED", worker_id: null, trace: $message, tasks: [], healthy: false}')")
                    unhealthy=$((unhealthy + 1))
                    if [ -z "$GITHUB_RUN_NUMBER" ]
                    then
                        # not running with CI
                        kubectl -n confluent get connector "$connector" -o yaml 2>/dev/null || true
                        echo ""
                    fi
                    continue
                fi
            fi
        fi
    fi
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
            if is_not_found; then
                break
            fi

            if [ $attempt -lt $MAX_RETRIES ]; then
                log "⚠️  API did not return a valid status (attempt $attempt/$MAX_RETRIES). Retrying in ${RETRY_INTERVAL}s..."
                sleep $RETRY_INTERVAL
            fi
            ((attempt++))
        done

        printf "%-30s %-12s %-30s %-50s\n" "Name" "Status" "Tasks" "Stack Trace"
        echo "-------------------------------------------------------------------------------------------------------------"
        
        # Status mapping (using the status retrieved from the loop)
        if [ "$status" == "RUNNING" ]; then status="✅ RUNNING"
        elif [ "$status" == "PAUSED" ]; then status="⏸️  PAUSED"
        elif [ "$status" == "FAILED" ]; then status="❌ FAILED"
        elif [ "$status" == "UNASSIGNED" ]; then status="⌛ UNASSIGNED"
        elif [ "$status" == "STOPPED" ]; then status="🛑 STOPPED"
        elif [ "$status" == "PROVISIONING" ]; then status="🏭 PROVISIONING"
        elif is_not_found; then status="🤔 NOT FOUND"
        else status="🤔 UNKNOWN (API Error)"; fi
        
        tasks=$(echo "$curl_output" | jq -r '.tasks[]? | "\(.id):\(.state)"' | tr '\n' ',' | sed 's/,$/\n/')
        
        tasks=$(decorate_task_states "$tasks")
        
        # Stacktrace Extraction
        stacktrace_connector=$(echo "$curl_output" | jq -r '.connector.trace? // empty')
        errors_from_trace=$(echo "$curl_output" | jq -r '.errors_from_trace[0]?.error? // empty')
        validation_errors=$(echo "$curl_output" | jq -r '.validation_errors[0]? // empty')
        stacktrace=""
        if [ "$stacktrace_connector" != "" ]; then stacktrace="connector: $stacktrace_connector"; fi
        if [ "$errors_from_trace" != "" ]; then stacktrace="$stacktrace errors_from_trace: $errors_from_trace"; fi
        if [ "$validation_errors" != "" ]; then stacktrace="$stacktrace validation_errors: $validation_errors"; fi
        if [ -z "$stacktrace" ]; then stacktrace="-"; fi

        printf "%-30s %-12s %-30s %-50s\n" "$connector" "$status" "$tasks" "$stacktrace"
        echo "-------------------------------------------------------------------------------------------------------------"

        # PG_SKIP_ERROR_RECOMMENDATIONS is set by callers running this command in a loop (show-lag, validate_ccloud_connector_up)
        if [ -z "$PG_SKIP_ERROR_RECOMMENDATIONS" ] && echo "$curl_output" | jq -e '[.connector.state, .tasks[]?.state] | index("FAILED")' > /dev/null 2>&1
        then
            log "💡 $connector_type connector $connector is failing, getting error recommendations from Confluent Cloud"
            playground connector error-recommendations --connector $connector || true
        fi

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
            if is_not_found; then
                break
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
        elif [ "$status" == "RESTARTING" ]; then status="🔄 RESTARTING"
        elif is_not_found; then status="🤔 NOT FOUND"
        else status="🤔 UNKNOWN (API Error)"; fi
        
        status_display="$status"
        tasks=$(echo "$curl_output" | jq -r '.tasks[] | "\(.id):\(.state)"' | tr '\n' ',' | sed 's/,$/\n/')

        if [[ "$multiple_connect_workers_running" == true ]]
        then
            connector_worker_id=$(echo "$curl_output" | jq -r '.connector.worker_id // empty' | sed 's/:8083$//' | sed 's/:8283$//' | sed 's/:8383$//' | sed -E 's/\..*$//')
            if [ -n "$connector_worker_id" ]
            then
                status_display="$status[$connector_worker_id]"
                if [ -n "$leader_name" ] && [ "$connector_worker_id" == "$leader_name" ]
                then
                    status_display="$status[$connector_worker_id 👑]"
                fi
            fi
            
            tasks=$(echo "$curl_output" | jq -r '.tasks[] | "\(.id):\(.state)[\(.worker_id)]"' | tr '\n' ',' | sed 's/,$/\n/' | sed 's/:8083//g' | sed 's/:8283//g' | sed 's/:8383//g' | sed -E 's/\[([a-zA-Z0-9-]+)\.[^]]*\]/[\1]/g')
            if [ -n "$leader_name" ]
            then
                tasks=$(echo "$tasks" | sed "s/\[$leader_name\]/[$leader_name 👑]/g")
            fi
        fi

        printf "%-30s %-12s %-30s %-50s\n" "Name" "Status" "Tasks" "Stack Trace"
        echo "-------------------------------------------------------------------------------------------------------------"
        
        tasks=$(decorate_task_states "$tasks")
        
        stacktrace_connector=$(echo "$curl_output" | jq -r '.connector.trace? // empty' | sed '/^$/d')
        stacktrace_tasks=$(echo "$curl_output" | jq -r '.tasks[]?.trace? // empty' | sed '/^$/d')
        stacktrace=""
        if [ "$stacktrace_connector" != "" ]; then stacktrace="connector: $stacktrace_connector"; fi
        if [ "$stacktrace_tasks" != "" ]; then stacktrace="$stacktrace tasks: $stacktrace_tasks"; fi
        if [ -z "$stacktrace" ]; then stacktrace="-"; fi

        printf "%-30s %-12s %-30s %-50s\n" "$connector" "$status_display" "$tasks" "$stacktrace"
        echo "-------------------------------------------------------------------------------------------------------------"
    fi

    # one JSON object per connector, for --json and --fail-on-error
    status_answer="$curl_output"
    if ! echo "$status_answer" | jq -e 'type == "object"' > /dev/null 2>&1
    then
        status_answer='{}'
    fi
    not_found=false
    if is_not_found; then not_found=true; fi
    json_entry=$(echo "$status_answer" | jq -c --arg name "$connector" --arg type "$connector_type" --arg id "$connectorId" --argjson not_found "$not_found" '
        {
            name: $name,
            type: $type,
            id: (if $id == "" then null else $id end),
            state: (if $not_found then "NOT_FOUND" else (.connector.state // "UNKNOWN") end),
            worker_id: (.connector.worker_id // null),
            trace: (.connector.trace // null),
            tasks: [.tasks[]? | {id: (.id | if type == "object" then .task else . end), state, worker_id: (.worker_id // null), trace: (.trace // null)}]
        }
        + (if .errors_from_trace then {errors_from_trace: .errors_from_trace} else {} end)
        + (if .validation_errors then {validation_errors: .validation_errors} else {} end)
        | .healthy = ((.state | IN("FAILED", "NOT_FOUND", "UNKNOWN") | not) and ([.tasks[].state] | index("FAILED") | not))')
    json_entries+=("$json_entry")
    if [ "$(echo "$json_entry" | jq -r '.healthy')" != "true" ]
    then
        unhealthy=$((unhealthy + 1))
    fi

    # only when something failed, and not when called in a loop (PG_SKIP_ERROR_RECOMMENDATIONS) or by diagnose itself
    if [ -z "$PG_SKIP_DIAGNOSE_HINT" ] && [ -z "$PG_SKIP_ERROR_RECOMMENDATIONS" ] && echo "$curl_output" | jq -e '[.connector.state, .tasks[]?.state] | index("FAILED")' > /dev/null 2>&1
    then
        log "🩺 for the error digest, the progress and the next steps, run: playground connector diagnose --connector $connector"
    fi
    set -e
done

if [[ -n "$json" ]]
then
    printf '%s\n' "${json_entries[@]}" | jq -s '.' >&3
fi
if [[ -n "$fail_on_error" ]] && [ "$unhealthy" -gt 0 ]
then
    logerror "❌ $unhealthy connector(s) FAILED, with a FAILED task, or not found"
    exit 1
fi
