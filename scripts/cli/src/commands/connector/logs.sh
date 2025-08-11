open="${args[--open]}"
log="${args[--wait-for-log]}"
connector="${args[--connector]}"
verbose="${args[--verbose]}"

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
    # macOS (BSD date) vs Linux (GNU date) compatibility
    if [[ "$OSTYPE" == "darwin"* ]]; then
        start_time=$(date -u -v-71H +"%Y-%m-%dT%H:%M:%SZ")
    else
        start_time=$(date -u -d "71 hours ago" +"%Y-%m-%dT%H:%M:%SZ")
    fi
    end_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    for connector in "${items[@]}"
    do
        connectorId=$(get_ccloud_connector_lcc $connector)
        if [[ -n "$open" ]]
        then
            filename="/tmp/${connector}-$(date '+%Y-%m-%d-%H-%M-%S').log"
        fi
        if [[ -n "$log" ]]
        then
            if [[ -n "$verbose" ]]
            then
                log "🐞 CLI command used"
                echo "confluent connect logs \"$connectorId\" --level \"ERROR|WARN|INFO\" --start-time \"$start_time\" --end-time \"$end_time\" --search-text \"$log\""
            fi
            confluent connect logs "$connectorId" --level "ERROR|WARN|INFO" --start-time "$start_time" --end-time "$end_time" --search-text "$log"
        else
            if [[ -n "$verbose" ]]
            then
                log "🐞 CLI command used"
                echo "confluent connect logs \"$connectorId\" --level \"ERROR|WARN|INFO\" --start-time \"$start_time\" --end-time \"$end_time\" --next"
            fi
            
            log "📄 Fetching connector logs for $connector (this may take a while for large log sets)..."
            page_num=1
            while true; do
                log "📖 Fetching page $page_num..."
                output=$(confluent connect logs "$connectorId" --level "ERROR|WARN|INFO" --start-time "$start_time" --end-time "$end_time" --next 2>&1)
                
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
    if [[ -n "$open" ]]
    then
        playground container logs --open --container connect
    elif [[ -n "$log" ]]
    then
        playground container logs --container connect --wait-for-log "$log"
    else 
        playground container logs --container connect
    fi
fi