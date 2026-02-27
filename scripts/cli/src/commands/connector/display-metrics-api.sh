open="${args[--open]}"
connector="${args[--connector]}"
verbose="${args[--verbose]}"

format_metric_value() {
    local value="$1"
    local printable_value

    if [[ "$value" =~ ^-?[0-9]+\.[0-9]+$ ]]
    then
        printable_value=$(printf "%.2f" "$value")
    else
        printable_value="$value"
    fi

    echo "$printable_value"
}

format_metric_timestamp() {
    local timestamp="$1"
    if [[ -z "$timestamp" ]]
    then
        return
    fi

    local ts_seconds=$((timestamp / 1000))
    date -r "$ts_seconds" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || true
}

extract_metric() {
    local metric_name="$1"
    local connector_id="$2"
    local source_file="$3"

    grep "^${metric_name}{" "$source_file" | grep "connector_id=\"${connector_id}\"" | head -1 | awk '{print $(NF-1), $NF}'
}

extract_metric_with_label() {
    local metric_name="$1"
    local label_name="$2"
    local connector_id="$3"
    local source_file="$4"

    grep "^${metric_name}{" "$source_file" | grep "connector_id=\"${connector_id}\"" | \
    sed -n "s/.*${label_name}=\"\([^\"]*\)\".*/\1/p" | head -1
}

is_zero_value() {
    local value="$1"
    [[ "$value" =~ ^-?0+([.]0+)?$ ]]
}

is_summary_duplicate_metric() {
    local metric_name="$1"
    [[ "$metric_name" == "confluent_kafka_connect_connector_status" || "$metric_name" == "confluent_kafka_connect_connector_task_status" ]]
}

extract_label_value() {
    local labels="$1"
    local label_name="$2"
    echo "$labels" | sed -n "s/.*${label_name}=\"\([^\"]*\)\".*/\1/p"
}

build_metric_context() {
    local labels="$1"

    local task
    task=$(extract_label_value "$labels" "task")
    local status
    status=$(extract_label_value "$labels" "status")
    local plugin_type
    plugin_type=$(extract_label_value "$labels" "plugin_type")

    local context=""
    if [[ -n "$task" ]]
    then
        context="task $task"
    fi
    if [[ -n "$status" ]]
    then
        if [[ -n "$context" ]]
        then
            context="$context, status $status"
        else
            context="status $status"
        fi
    fi
    if [[ -n "$plugin_type" ]]
    then
        if [[ -n "$context" ]]
        then
            context="$context, plugin $plugin_type"
        else
            context="plugin $plugin_type"
        fi
    fi

    echo "$context"
}

display_metrics_summary() {
    local source_file="$1"
    local connector_name="$2"
    local connector_id="$3"

    local connector_status
    connector_status=$(extract_metric_with_label "confluent_kafka_connect_connector_status" "status" "$connector_id" "$source_file")

    local task_statuses=""
    local task_line
    while IFS= read -r task_line
    do
        if [[ "$task_line" =~ ^[^\{]+\{(.*)\}[[:space:]]+[^[:space:]]+([[:space:]]+[0-9]+)?$ ]]
        then
            local task_labels="${BASH_REMATCH[1]}"
            local task_id
            task_id=$(extract_label_value "$task_labels" "task")
            local task_status
            task_status=$(extract_label_value "$task_labels" "status")

            if [[ -n "$task_id" ]] && [[ -n "$task_status" ]]
            then
                if [[ -n "$task_statuses" ]]
                then
                    task_statuses="$task_statuses, "
                fi
                task_statuses+="task $task_id: $task_status"
            fi
        fi
    done < <(grep '^confluent_kafka_connect_connector_task_status{' "$source_file" | grep "connector_id=\"${connector_id}\"")

    log "📊 Connector metrics summary"
    echo "Connector: $connector_name"
    echo "Connector ID: $connector_id"
    echo "Status: ${connector_status:-N/A}"
    echo "Tasks: ${task_statuses:-N/A}"
    echo ""

    local metrics_timestamp=""
    while IFS= read -r metric_line
    do
        if [[ "$metric_line" =~ ^([^\{]+)\{(.*)\}[[:space:]]+([^[:space:]]+)([[:space:]]+([0-9]+))?$ ]]
        then
            local metric_name="${BASH_REMATCH[1]}"
            local metric_value="${BASH_REMATCH[3]}"
            local metric_ts="${BASH_REMATCH[5]}"

            if is_summary_duplicate_metric "$metric_name"
            then
                continue
            fi

            if is_zero_value "$metric_value"
            then
                continue
            fi

            if [[ -n "$metric_ts" ]]
            then
                metrics_timestamp=$(format_metric_timestamp "$metric_ts")
            fi
            break
        fi
    done < <(grep '^confluent_kafka_connect_.*{' "$source_file" | grep "connector_id=\"${connector_id}\"")

    if [[ -n "$metrics_timestamp" ]]
    then
        echo "〽️ Non-zero metrics (at $metrics_timestamp)"
    else
        echo "〽️ Non-zero metrics"
    fi

    local displayed=0
    local metric_line
    while IFS= read -r metric_line
    do
        if [[ "$metric_line" =~ ^([^\{]+)\{(.*)\}[[:space:]]+([^[:space:]]+)([[:space:]]+([0-9]+))?$ ]]
        then
            local metric_name="${BASH_REMATCH[1]}"
            local labels="${BASH_REMATCH[2]}"
            local metric_value="${BASH_REMATCH[3]}"
            local metric_ts="${BASH_REMATCH[5]}"

            if is_summary_duplicate_metric "$metric_name"
            then
                continue
            fi

            if is_zero_value "$metric_value"
            then
                continue
            fi

            local display_name
            display_name=$(echo "$metric_name" | sed 's/^confluent_kafka_connect_//; s/_/ /g')

            local metric_context
            metric_context=$(build_metric_context "$labels")

            if [[ -n "$metric_context" ]]
            then
                echo " - ${display_name} (${metric_context}): $(format_metric_value "$metric_value")"
            else
                echo " - ${display_name}: $(format_metric_value "$metric_value")"
            fi
            ((displayed+=1))
        fi
    done < <(grep '^confluent_kafka_connect_.*{' "$source_file" | grep "connector_id=\"${connector_id}\"")

    if (( displayed == 0 ))
    then
        echo "🔴 No non-zero metrics for this connector"
    fi
}

connector_type=$(playground state get run.connector_type)

if [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
then
    logerror "🚨 This command is not supported for custom connectors"
    exit 1
fi

if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ]
then

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

    get_ccloud_connect
    for connector in "${items[@]}"
    do
        connectorId=$(get_ccloud_connector_lcc $connector)
        metrics_file=$(mktemp)
        if [[ -n "$open" ]]
        then
            filename="/tmp/${connector}-$(date '+%Y-%m-%d-%H-%M-%S').log"
        fi

        if [[ -n "$verbose" ]]
        then
            log "🐞 CLI command used"
            echo "curl -sS \"https://api.telemetry.confluent.cloud/v2/metrics/cloud/export?resource.connector.id=$connectorId\" -H \"Content-Type: application/json\" -X GET -H \"Authorization: Basic $authorization\""
        fi

        log "〽️ Display metrics api for fully managed connector $connector (id: $connectorId), see https://api.telemetry.confluent.cloud/docs/descriptors/datasets/cloud"
        curl -sS "https://api.telemetry.confluent.cloud/v2/metrics/cloud/export?resource.connector.id=$connectorId" \
        -H "Content-Type: application/json" \
        -X GET \
        -H "Authorization: Basic $authorization" > "$metrics_file"

        if [[ -n "$verbose" ]]
        then
            log "🐞 Raw metrics api output"
            cat "$metrics_file"
            echo ""
        fi

        display_metrics_summary "$metrics_file" "$connector" "$connectorId"

        if [[ -n "$open" ]]
        then
            cp "$metrics_file" "$filename"
            playground open --file "${filename}"
        fi

        rm -f "$metrics_file"
    done
else
    logerror "🚨 This command is only supported for fully managed connectors"
    exit 1
fi