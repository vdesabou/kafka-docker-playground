connector="${args[--connector]}"
verbose="${args[--verbose]}"
all_keys="${args[--all-keys]}"
json="${args[--json]}"

connector_type=$(playground state get run.connector_type)

if [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
then
    log "connector tasks command is not supported with $connector_type connector"
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

# task configs returned by the REST API are not masked: hide the values of the keys that look like secrets
secret_keys_regex='(password|secret|jaas|token|credential|api[._]key|private[._]key|keystore\.key|access[._]key)'

function state_with_emoji() {
    case "$1" in
        RUNNING) echo "🟢 RUNNING" ;;
        FAILED) echo "🛑 FAILED" ;;
        PAUSED) echo "⏸️  PAUSED" ;;
        STOPPED) echo "🛑 STOPPED" ;;
        UNASSIGNED) echo "⌛ UNASSIGNED" ;;
        RESTARTING) echo "🔄 RESTARTING" ;;
        *) echo "$1" ;;
    esac
}

items=($connector)
length=${#items[@]}
if ((length > 1)) && [[ -z "$json" ]]
then
    log "✨ --connector flag was not provided, applying command to all connectors"
fi

results="[]"
for connector in "${items[@]}"
do
    if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ]
    then
        get_ccloud_connect
        handle_ccloud_connect_rest_api "curl -s --header \"authorization: Basic $authorization\" \"https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector/status\""
        if [ $? -ne 0 ] || [ -z "$curl_output" ]
        then
            logerror "❌ Could not get the status of $connector_type connector $connector"
            exit 1
        fi
        status_json="$curl_output"
        # the task configs and the worker of each task are not exposed for fully managed connectors
        tasks_json="[]"
        config_json="{}"
        partitions_json="{}"
    else
        get_connect_url_and_security
        handle_onprem_connect_rest_api "curl $security -s \"$connect_url/connectors/$connector/status\""
        if [ $? -ne 0 ] || [ -z "$curl_output" ]
        then
            logerror "❌ Could not get the status of $connector_type connector $connector"
            exit 1
        fi
        status_json="$curl_output"
        handle_onprem_connect_rest_api "curl $security -s \"$connect_url/connectors/$connector/tasks\""
        tasks_json="${curl_output:-[]}"
        handle_onprem_connect_rest_api "curl $security -s \"$connect_url/connectors/$connector/config\""
        config_json="$curl_output"
        [ -z "$config_json" ] && config_json="{}"

        # sink: partitions assigned to each task, from the CLIENT-ID (connector-consumer-<connector>-<task>) of its consumer group
        partitions_json="{}"
        if [ "$(echo "$status_json" | jq -r '.type')" == "sink" ]
        then
            group=$(echo "$config_json" | jq -r '."consumer.override.group.id" // empty')
            group=${group:-connect-$connector}
            set +e
            group_output=$(run_kafka_admin_tool kafka-consumer-groups --describe --group "$group" 2>/dev/null)
            set -e
            partitions_json=$(echo "$group_output" | awk -v prefix="connector-consumer-$connector-" '
                $1 != "GROUP" && NF >= 9 {
                    client = $NF
                    if (index(client, prefix) == 1) {
                        task = substr(client, length(prefix) + 1)
                        if (task ~ /^[0-9]+$/) print task "\t" $2 "-" $3
                    }
                }' | jq -R -s 'split("\n") | map(select(length > 0) | split("\t")) | group_by(.[0]) | map({key: .[0][0], value: (map(.[1]) | sort)}) | from_entries')
        fi
    fi

    result=$(jq -n \
        --arg connector "$connector" \
        --arg connector_type "$connector_type" \
        --arg secret_regex "$secret_keys_regex" \
        --argjson status "$status_json" \
        --argjson tasks "$tasks_json" \
        --argjson config "$config_json" \
        --argjson partitions "$partitions_json" '
        # also the passwords embedded in a value: password=... parameters of a jdbc url, user:password@ of a url
        def mask: with_entries(if (.key | test($secret_regex; "i")) then .value = "********"
            else .value |= (if type == "string" then gsub("(?<k>(password|pwd)=)[^&;]*"; "\(.k)********"; "i") | gsub("(?<s>://[^/:@]+:)[^/@]+@"; "\(.s)********@") else . end) end);
        ($tasks | map({key: (.id.task | tostring), value: (.config // {})}) | from_entries) as $task_configs
        | ($task_configs | [.[] | keys[]] | unique) as $all_keys
        # a key differs when it is not in the connector config with the same value, or when the tasks do not all have the same value
        | ($all_keys | map(select(. != "task.class") | select(. as $k |
              ($task_configs | [.[] | .[$k]] | unique | length) > 1
              or ($task_configs | to_entries | any(.value[$k] != $config[$k]))))) as $diff_keys
        | {
            connector: $connector,
            connector_type: $connector_type,
            type: ($status.type // null),
            state: $status.connector.state,
            worker_id: ($status.connector.worker_id // null),
            tasks_max: ($config["tasks.max"] // null),
            task_class: ($task_configs | [.[] | .["task.class"]] | unique | first // null),
            tasks: ($status.tasks // [] | sort_by(.id) | map(
                (.id | tostring) as $id
                | {
                    id: .id,
                    state: .state,
                    worker_id: (.worker_id // null),
                    trace: ((.trace // "") | split("\n") | first // "" | if . == "" then null else . end),
                    config_diff: (($task_configs[$id] // {}) | with_entries(select(.key as $k | $diff_keys | index($k))) | mask),
                    config: (($task_configs[$id] // {}) | mask),
                    partitions: ($partitions[$id] // null)
                  }))
          }')
    results=$(echo "$results" | jq --argjson r "$result" '. + [$r]')

    if [[ -n "$json" ]]
    then
        continue
    fi

    nb_tasks=$(echo "$result" | jq '.tasks | length')
    log "🧵 Tasks of $connector_type connector $connector ($(echo "$result" | jq -r '[.type, ("connector " + .state), (if .worker_id then "on " + .worker_id else empty end), (if .tasks_max then "tasks.max=" + .tasks_max else empty end), "\($tasks_count) task(s)"] | map(select(. != null)) | join(", ")' --argjson tasks_count "$nb_tasks"))"
    if [ "$nb_tasks" == "0" ]
    then
        logwarn "⚠️ The connector has no task: a source connector creates its tasks once it found work (tables, files...), check 'playground connector logs'"
        continue
    fi
    task_class=$(echo "$result" | jq -r '.task_class // empty')
    if [ -n "$task_class" ]
    then
        log "🧩 task.class: $task_class"
    fi

    is_sink=0
    [ "$(echo "$result" | jq -r '.type')" == "sink" ] && [ "$connector_type" != "$CONNECTOR_TYPE_FULLY_MANAGED" ] && is_sink=1

    printf "%-6s %-16s %-24s %s\n" "Task" "State" "Worker" "$( [ $is_sink == 1 ] && echo "Partitions" || echo "")"
    echo "-------------------------------------------------------------------------------------------------------------"
    while read -r task
    do
        id=$(echo "$task" | jq -r '.id')
        state=$(state_with_emoji "$(echo "$task" | jq -r '.state')")
        worker=$(echo "$task" | jq -r '.worker_id // "-"')
        partitions=""
        if [ $is_sink == 1 ]
        then
            partitions=$(echo "$task" | jq -r 'if .partitions then (.partitions | join(",")) else "- (no partition assigned)" end')
        fi
        printf "%-6s %-16s %-24s %s\n" "$id" "$state" "$worker" "$partitions"
        trace=$(echo "$task" | jq -r '.trace // empty')
        if [ -n "$trace" ]
        then
            echo "       ↳ $trace"
        fi
        if [[ -n "$all_keys" ]]
        then
            echo "$task" | jq -r '.config | to_entries | sort_by(.key)[] | "       \(.key)=\(.value)"'
        else
            echo "$task" | jq -r '.config_diff | to_entries | sort_by(.key)[] | "       ⚙️  \(.key)=\(.value)"'
        fi
    done < <(echo "$result" | jq -c '.tasks[]')
    echo "-------------------------------------------------------------------------------------------------------------"

    if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ]
    then
        log "ℹ️ Fully managed connector: the config and the worker of each task are not exposed"
        continue
    fi
    if [[ -z "$all_keys" ]] && [ "$(echo "$result" | jq '[.tasks[].config_diff | length] | add // 0')" == "0" ]
    then
        log "⚙️ All the tasks have the same config as the connector (use --all-keys to see it)"
    fi
    nb_workers=$(echo "$result" | jq '[.tasks[].worker_id] | unique | length')
    if [ "$nb_workers" -gt 1 ]
    then
        log "👷 Tasks per worker:"
        echo "$result" | jq -r '.tasks | group_by(.worker_id)[] | "   \(.[0].worker_id): \(length) task(s) (\(map(.id | tostring) | join(",")))"'
    fi
    if [ $is_sink == 1 ]
    then
        unassigned=$(echo "$result" | jq '[.tasks[] | select(.partitions == null)] | length')
        if [ "$unassigned" != "0" ]
        then
            log "💤 $unassigned task(s) without partition: tasks.max is higher than the number of partitions of the topics, or the consumer group is rebalancing"
        fi
    fi
done

if [[ -n "$json" ]]
then
    echo "$results" | jq 'map(.tasks |= map(if $all then del(.config_diff) else del(.config) end))' --argjson all "$( [[ -n "$all_keys" ]] && echo true || echo false )"
fi
