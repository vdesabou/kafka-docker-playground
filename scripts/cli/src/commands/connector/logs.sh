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
analyze="${args[--analyze]}"
output_dir="${args[--output-dir]}"
fm_logs_to_analyze=()

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
            # every page as JSON lines (--output-file: the human output of the CLI is a table, with wrapped cells), then
            # turned into log lines with the [connector|task-0] context of a Connect worker (json_log_export.py): shown,
            # opened, or analyzed with --analyze. The first page without --next (a new query), then --next until "No
            # logs found for the current query"
            fm_base="/tmp/playground-connector-logs-${connector}-$(date '+%Y%m%d-%H%M%S')"
            fm_jsonl="${fm_base}.jsonl"
            fm_log="${fm_base}.log"
            : > "$fm_jsonl"
            if [[ -n "$verbose" ]]
            then
                log "🐞 CLI command used"
                echo "confluent connect logs \"$connectorId\" --level \"$levels\" --start-time \"$start_time\" --end-time \"$end_time\" ${maybe_search[*]} --output-file \"$fm_jsonl\" [--next]"
            fi
            log "📄 Fetching the logs of fully managed connector $connector ($connectorId, $levels, last 71 hours)..."
            page_num=1
            maybe_next=()
            while true
            do
                output=$(confluent connect logs "$connectorId" --level "$levels" --start-time "$start_time" --end-time "$end_time" "${maybe_search[@]}" "${maybe_next[@]}" --output-file "$fm_jsonl" 2>&1) && status=0 || status=$?
                if echo "$output" | grep -q "No logs found"
                then
                    break
                fi
                if [[ $status -ne 0 ]]
                then
                    logerror "❌ confluent connect logs failed on page $page_num: $(echo "$output" | head -3)"
                    break
                fi
                nb_entries=$(echo "$output" | sed -n 's/^Appended \([0-9]*\) log entries.*/\1/p' | head -1)
                log "📖 page $page_num: ${nb_entries:-?} log entries"
                if [[ "${nb_entries:-0}" -eq 0 ]]
                then
                    break
                fi
                page_num=$((page_num + 1))
                if [ $page_num -gt 100 ]
                then
                    logwarn "⚠️ Reached maximum page limit (100), stopping pagination"
                    break
                fi
                maybe_next=(--next)
                sleep 1
            done
            nb_lines=$(wc -l < "$fm_jsonl" | tr -d ' ')
            if [[ "$nb_lines" -eq 0 ]]
            then
                log "💤 No log entry for fully managed connector $connector ($levels, last 71 hours)"
                rm -f "$fm_jsonl"
                continue
            fi
            if ! PG_LOG_CONNECTOR_NAME="$connector" python3 -I "$root_folder/tools/log-analyzer/json_log_export.py" "$fm_jsonl" "$fm_log" > /dev/null 2>&1
            then
                logwarn "⚠️ could not turn the logs of $connector into log lines: the JSON lines are in $fm_jsonl"
                fm_log="$fm_jsonl"
            fi
            log "✅ $nb_lines log entries of $connector in $fm_log (JSON lines of the CLI: $fm_jsonl)"
            if [[ -n "$analyze" ]]
            then
                fm_logs_to_analyze+=("$fm_log")
            elif [[ -n "$open" ]]
            then
                cp "$fm_log" "$filename"
            else
                cat "$fm_log"
            fi
        fi
        if [[ -n "$open" ]] && [[ -f "${filename}" ]]
        then
            playground open --file "${filename}"
        fi
    done
    if [[ -n "$analyze" ]]
    then
        if [ ${#fm_logs_to_analyze[@]} -eq 0 ]
        then
            logerror "❌ --analyze: no log entry to analyze"
            exit 1
        fi
        analyze_args=()
        for fm_log in "${fm_logs_to_analyze[@]}"
        do
            analyze_args+=(--file "$fm_log")
        done
        [[ -n "$output_dir" ]] && analyze_args+=(--output-dir "$output_dir")
        playground analyze logs "${analyze_args[@]}"
    fi
else
    connect_container="connect"
    if is_mdc_environment
    then
        get_connect_container
    fi
    if [[ -n "$analyze" ]]
    then
        # the full report of playground analyze logs on the logs of the worker, kept to this connector when one is given
        analyze_args=(--from-containers --container "$connect_container")
        [[ -n "$connector" ]] && analyze_args+=(--connector "$connector")
        [[ -n "$errors" ]] && analyze_args+=(--errors-only)
        [[ -n "$output_dir" ]] && analyze_args+=(--output-dir "$output_dir")
        if [[ -n "$verbose" ]]
        then
            log "🐞 CLI command used"
            echo "playground analyze logs ${analyze_args[*]}"
        fi
        playground analyze logs "${analyze_args[@]}"
        exit $?
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
