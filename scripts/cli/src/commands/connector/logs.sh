open="${args[--open]}"
log="${args[--wait-for-log]}"
connector="${args[--connector]}"
verbose="${args[--verbose]}"
max_wait=$(duration_to_seconds "${args[--max-wait]}")
grep_pattern="${args[--grep]}"
since="${args[--since]}"
tail_lines="${args[--tail]}"
no_follow="${args[--no-follow]}"
errors="${args[--errors]}"

connector_type=$(playground state get run.connector_type)

if [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
then
    logerror "🚨 This command is not supported for custom connectors"
    exit 1
fi

if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ]
then
    if ! command -v confluent > /dev/null 2>&1
    then
        logerror "❌ the confluent CLI is required to read the logs of a fully managed connector, see https://docs.confluent.io/confluent-cli/current/overview.html to install it"
        exit 1
    fi
    if [[ -n "$since" ]] || [[ -n "$tail_lines" ]] || [[ -n "$no_follow" ]]
    then
        logwarn "⚠️ --since, --tail and --no-follow only apply to self managed connectors: ignored"
    fi
    levels="ERROR|WARN|INFO"
    if [[ -n "$errors" ]]
    then
        levels="ERROR"
    fi
    maybe_search=()
    if [[ -n "$grep_pattern" ]]
    then
        maybe_search=(--search-text "$grep_pattern")
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

    items=($connector)
    length=${#items[@]}
    if ((length > 1))
    then
        log "✨ --connector flag was not provided, applying command to all connectors"
    fi
    # macOS (BSD date) vs Linux (GNU date) compatibility
    if [[ "$OSTYPE" == "darwin"* ]]; then
        start_time=$(date -u -v-71H +"%Y-%m-%dT%H:%M:%SZ")
    else
        start_time=$(date -u -d "71 hours ago" +"%Y-%m-%dT%H:%M:%SZ")
    fi
    end_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    for connector in "${items[@]}"
    do
        connectorId=$(get_ccloud_connector_lcc "$connector" || true)
        if [[ -z "$connectorId" ]] || [[ "$connectorId" == "null" ]]
        then
            logerror "❌ Could not find the id of fully managed connector $connector"
            exit 1
        fi
        if [[ -n "$open" ]]
        then
            filename="/tmp/${connector}-$(date '+%Y-%m-%d-%H-%M-%S').log"
        fi
        if [[ -n "$log" ]]
        then
            if [[ -n "$verbose" ]]
            then
                log "🐞 CLI command used"
                echo "confluent connect logs \"$connectorId\" --level \"$levels\" --start-time \"$start_time\" --end-time <now> --search-text \"$log\""
            fi
            # poll until the text is found: a single search returned whatever the outcome
            log "😴 Waiting up to $max_wait seconds for log \"$log\" in fully managed connector $connector ($connectorId)"
            cur_wait=0
            while true
            do
                end_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
                output=$(confluent connect logs "$connectorId" --level "$levels" --start-time "$start_time" --end-time "$end_time" --search-text "$log" 2>&1 || true)
                if ! echo "$output" | grep -q "No logs found" && echo "$output" | grep -qF "$log"
                then
                    echo "$output"
                    log "✅ log \"$log\" found in fully managed connector $connector"
                    break
                fi
                if [[ "$cur_wait" -ge "$max_wait" ]]
                then
                    logerror "❌ log \"$log\" was not found in fully managed connector $connector after $max_wait seconds"
                    exit 1
                fi
                sleep 10
                cur_wait=$((cur_wait + 10))
            done
        else
            if [[ -n "$verbose" ]]
            then
                log "🐞 CLI command used"
                echo "confluent connect logs \"$connectorId\" --level \"$levels\" --start-time \"$start_time\" --end-time \"$end_time\" ${maybe_search[*]} --next"
            fi
            
            log "📄 Fetching connector logs for $connector (this may take a while for large log sets)..."
            page_num=1
            while true; do
                log "📖 Fetching page $page_num..."
                output=$(confluent connect logs "$connectorId" --level "$levels" --start-time "$start_time" --end-time "$end_time" "${maybe_search[@]}" --next 2>&1)
                
                # Check if no logs found
                if echo "$output" | grep -q "No logs found for the current query"; then
                    log "✅ Finished fetching all log pages (total pages: $((page_num-1)))"
                    break
                fi
                
                if [[ -n "$open" ]]
                then
                    # Save the logs to a file
                    echo "$output" >> "$filename"
                else
                    # Display the logs
                    echo "$output"
                fi

                # Check if there are more pages by looking for log entries
                if [ -z "$(echo "$output" | grep -E '\[INFO\]|\[WARN\]|\[ERROR\]')" ]; then
                    log "✅ No more log entries found (total pages: $page_num)"
                    break
                fi
                
                page_num=$((page_num + 1))
                
                # Safety limit to prevent infinite loops
                if [ $page_num -gt 100 ]; then
                    logwarn "⚠️  Reached maximum page limit (100), stopping pagination"
                    break
                fi
                
                sleep 1  # Small delay between requests
            done
        fi
        if [[ -n "$open" ]]
        then
            playground open --file "${filename}"
        fi
    done
else
    connect_container="connect"
    if is_mdc_environment
    then
        get_connect_container
    fi
    # container logs resolves connect to connect-0 on cfk
    container_args=(--container "$connect_container")
    if [[ -n "$open" ]]
    then
        container_args+=(--open)
    elif [[ -n "$log" ]]
    then
        container_args+=(--wait-for-log "$log" --max-wait "$max_wait")
    else
        if [[ -n "$errors" ]]
        then
            container_args+=(--errors)
        fi
        if [[ -n "$grep_pattern" ]]
        then
            container_args+=(--grep "$grep_pattern")
        elif [[ -n "$connector" ]] && [[ -z "$errors" ]]
        then
            # the worker logs every connector: keep the lines of this one (its name is in the log context)
            log "🎯 keeping only the lines mentioning connector $connector (use --grep to choose another pattern)"
            container_args+=(--grep "$connector")
        fi
        if [[ -n "$since" ]]
        then
            container_args+=(--since "$since")
        fi
        if [[ -n "$tail_lines" ]]
        then
            container_args+=(--tail "$tail_lines")
        fi
        if [[ -n "$no_follow" ]]
        then
            container_args+=(--no-follow)
        fi
    fi
    if [[ -n "$verbose" ]]
    then
        log "🐞 CLI command used"
        echo "playground container logs ${container_args[*]}"
    fi
    playground container logs "${container_args[@]}"
fi
