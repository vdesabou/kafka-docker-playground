connector="${args[--connector]}"
verbose="${args[--verbose]}"
since="${args[--since]}"
max_findings="${args[--max-findings]}"

connector_type=$(playground state get run.connector_type)
get_environment_used

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

for connector in "${items[@]}"
do
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

    echo ""
    if [ $is_cloud -eq 1 ]
    then
        log "🔥 2/4 errors: Confluent Cloud error recommendations"
        playground connector error-recommendations --connector "$connector" $maybe_verbose
    else
        log "🔥 2/4 errors: digest of connect ERROR/FATAL records since $since (whole worker, not only this connector)"
        playground container logs --container connect --errors --since "$since" --max-findings "$max_findings"
    fi

    echo ""
    if [ "$type" == "sink" ]
    then
        log "🐢 3/4 progress: consumer lag of sink $connector"
        playground connector show-lag --connector "$connector" --interval 1 --max-wait 1 $maybe_verbose
    elif [ "$type" == "source" ]
    then
        log "🐢 3/4 progress: offsets of source $connector (run it again to see whether they move)"
        playground connector offsets get --connector "$connector" $maybe_verbose
    else
        logwarn "🐢 3/4 progress: unknown connector type <$type>, skipped"
    fi

    echo ""
    log "👉 4/4 next steps"
    if [[ "$connector_state" == "FAILED" ]] || [[ "$task_states" == *"FAILED"* ]]
    then
        echo "   🔥 a task or the connector FAILED: read the trace above, then after a fix: playground connector restart --connector $connector"
    elif [[ "$connector_state" == "PAUSED" ]] || [[ "$task_states" == *"PAUSED"* ]]
    then
        echo "   ⏸️  the connector is PAUSED: playground connector resume --connector $connector"
    elif [[ "$connector_state" == "RUNNING" ]]
    then
        echo "   🐌 RUNNING but no progress? run this command again, then take a thread dump if lag or offsets do not move"
    fi
    echo "   playground connector show-config --connector $connector"
    if [ $is_cloud -eq 1 ]
    then
        echo "   playground connector logs --connector $connector"
    else
        echo "   playground container logs -c connect --grep \"$connector\" --no-follow --tail 200"
        echo "   playground debug log-level set --package <connector package> --level TRACE"
        echo "   playground debug thread-dump --container connect"
    fi
    echo ""
done
