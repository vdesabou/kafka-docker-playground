connector="${args[--connector]}"
verbose="${args[--verbose]}"
since="${args[--since]}"
max_findings="${args[--max-findings]}"
output_dir="${args[--output-dir]}"
no_open="${args[--no-open]}"

connector_type=$(playground state get run.connector_type)
get_environment_used
# get_ccloud_connect overwrites $environment with the Confluent Cloud environment id
playground_environment="$environment"

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

maybe_verbose=""
if [[ -n "$verbose" ]]
then
    maybe_verbose="--verbose"
fi

is_cloud=0
if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
then
    is_cloud=1
fi

# each step also lands in a folder per connector, for the HTML report (tools/connector-diagnose/diagnose_report.py)
report_tmp=$(mktemp -d -t pg-diagnose-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $report_tmp' EXIT
else
    log "🐛📂 not deleting tmp dir $report_tmp"
fi
connector_dirs=()

for connector in "${items[@]}"
do
    cdir="$report_tmp/${#connector_dirs[@]}"
    mkdir -p "$cdir"
    connector_dirs+=("$cdir")

    log "####################################################"
    log "🩺 diagnosing $connector_type connector $connector"
    log "####################################################"

    echo ""
    log "🗺️  1/4 status"
    PG_SKIP_DIAGNOSE_HINT=1 playground connector status --connector "$connector" $maybe_verbose

    # sink or source, and state, from the status endpoint
    if [ $is_cloud -eq 1 ]
    then
        get_ccloud_connect
        handle_ccloud_connect_rest_api "curl -s --request GET \"https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector/status\" --header \"authorization: Basic $authorization\""
    else
        get_connect_url_and_security
        handle_onprem_connect_rest_api "curl -s $security \"$connect_url/connectors/$connector/status\""
    fi
    type=$(echo "$curl_output" | jq -r '.type // empty')
    connector_state=$(echo "$curl_output" | jq -r '.connector.state // empty')
    task_states=$(echo "$curl_output" | jq -r '[.tasks[]?.state] | unique | join(",")')
    echo "$curl_output" > "$cdir/status.json"
    jq -n --arg connector "$connector" --arg connector_type "$connector_type" --arg is_cloud "$is_cloud" --arg type "$type" \
        --arg since "$since" --arg environment "$playground_environment" \
        '{connector: $connector, connector_type: $connector_type, is_cloud: $is_cloud, type: $type, since: $since, environment: $environment}' > "$cdir/meta.json"
    if [ $is_cloud -eq 1 ]
    then
        handle_ccloud_connect_rest_api "curl -s --request GET \"https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector/config\" --header \"authorization: Basic $authorization\"" > /dev/null 2>&1 && echo "$curl_output" > "$cdir/config.json"
    else
        handle_onprem_connect_rest_api "curl -s $security \"$connect_url/connectors/$connector/config\"" > /dev/null 2>&1 && echo "$curl_output" > "$cdir/config.json"
    fi

    echo ""
    if [ $is_cloud -eq 1 ]
    then
        log "🔥 2/4 errors: Confluent Cloud error recommendations"
        playground connector error-recommendations --connector "$connector" $maybe_verbose | tee "$cdir/recommendations.txt"
        display_ccloud_connector_service_account_acl_check "$connector"
    else
        log "🔥 2/4 errors: digest of connect ERROR/FATAL records since $since (whole worker, not only this connector)"
        PG_LOG_DIGEST_RECORDS_FILE="$cdir/errors.records" PG_LOG_DIGEST_LABEL="connect" playground container logs --container connect --errors --since "$since" --max-findings "$max_findings"
    fi

    echo ""
    if [ "$type" == "sink" ]
    then
        if [[ "$connector_state" == "RUNNING" ]] && [[ "$task_states" == "RUNNING" ]]
        then
            log "🐢 3/4 progress: consumer lag of sink $connector"
            { playground connector show-lag --connector "$connector" --interval 1 --max-wait 1 $maybe_verbose || true; } | tee "$cdir/lag.txt"
        else
            # show-lag waits 60s for a RUNNING task and then fails, which would hide the next steps
            log "🐢 3/4 progress: committed offsets of sink $connector (no lag while the connector and all its tasks are not RUNNING)"
            { playground connector offsets get --connector "$connector" $maybe_verbose || true; } | tee "$cdir/offsets.txt"
        fi
    elif [ "$type" == "source" ]
    then
        log "🐢 3/4 progress: offsets of source $connector (run it again to see whether they move)"
        { playground connector offsets get --connector "$connector" $maybe_verbose || true; } | tee "$cdir/offsets.txt"
    else
        logwarn "🐢 3/4 progress: unknown connector type <$type>, skipped"
    fi

    echo ""
    log "👉 4/4 next steps"
    next_steps=()
    if [[ "$connector_state" == "FAILED" ]] || [[ "$task_states" == *"FAILED"* ]]
    then
        next_steps+=("🔥 a task or the connector FAILED: read the trace above, then after a fix: playground connector restart --connector $connector")
    elif [[ "$connector_state" == "PAUSED" ]] || [[ "$task_states" == *"PAUSED"* ]]
    then
        next_steps+=("⏸️  the connector is PAUSED: playground connector resume --connector $connector")
    elif [[ "$connector_state" == "RUNNING" ]]
    then
        next_steps+=("🐌 RUNNING but no progress? run this command again, then take a thread dump if lag or offsets do not move")
    fi
    next_steps+=("playground connector show-config --connector $connector")
    if [ $is_cloud -eq 1 ]
    then
        next_steps+=("playground connector logs --connector $connector")
    else
        next_steps+=("playground container logs -c connect --grep \"$connector\" --no-follow --tail 200")
        next_steps+=("playground debug log-level set --package <connector package> --level TRACE")
        next_steps+=("playground debug thread-dump --container connect")
    fi
    for step in "${next_steps[@]}"
    do
        echo "   $step"
    done
    printf '%s\n' "${next_steps[@]}" > "$cdir/next_steps.txt"
    echo ""
done

if ! command -v python3 &>/dev/null
then
    logwarn "⚠️ python3 is not on PATH: no HTML report"
    exit 0
fi
report_name="all"
if ((length == 1))
then
    report_name=$(printf '%s' "$connector" | tr -c 'A-Za-z0-9._-' '_')
fi
mkdir -p "$output_dir"
output_dir=$(cd "$output_dir" && pwd)
html_out="$output_dir/connector-diagnose-${report_name}-$(date '+%Y%m%d-%H%M%S').html"
report_args=()
for cdir in "${connector_dirs[@]}"
do
    report_args+=(--connector-dir "$cdir")
done
if ! python3 -I "$root_folder/tools/connector-diagnose/diagnose_report.py" "${report_args[@]}" --html-out "$html_out"
then
    logerror "❌ could not write the HTML report"
    exit 1
fi
log "✅ HTML report saved: $html_out"
# only open a browser in an interactive terminal
if [[ -t 1 ]] && [ -z "$GITHUB_RUN_NUMBER" ] && [[ ! -n "$no_open" ]] && command -v open &>/dev/null
then
    log "🌐 Opening $html_out in browser..."
    open "$html_out"
else
    log "🔗 Open in browser: file://$html_out"
fi
