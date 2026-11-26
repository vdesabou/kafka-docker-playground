connector="${args[--connector]}"
json=${args[json]}
offline="${args[--offline]}"
brokers="${args[--brokers]}"
verbose="${args[--verbose]}"
output_json="${args[--json]}"

# --json: the JSON verdict is the only thing on stdout (fd 3), the log lines go to stderr
if [[ -n "$output_json" ]]
then
    exec 3>&1 1>&2
fi

if ! command -v python3 > /dev/null 2>&1
then
    logerror "❌ python3 is required to lint the connector config"
    exit 1
fi

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

if [ "$json" = "-" ]
then
    json_content=$(read_stdin_if_any)
else
    json_content=$json
fi

if [[ -z "$json_content" ]]
then
    # no config on stdin: lint the config of the running connector
    if [[ -z "$connector" ]]
    then
        logerror "❌ give the config to lint on stdin, or --connector to lint the config of a running connector"
        exit 1
    fi
    if ! get_connector_config_json "$connector"
    then
        logerror "❌ could not get the config of connector $connector"
        exit 1
    fi
    json_content="$curl_output"
    log "🧪 Linting the config of running connector $connector"
else
    # json, or one of the formats customers send (CFK / Strimzi custom resource, terraform, .properties, REST API dump...)
    if ! normalize_connector_config "$json_content" "$connector"
    then
        logerror "❌ $NORMALIZED_ERROR"
        exit 1
    fi
    if [ "$NORMALIZED_FORMAT" != "JSON" ]
    then
        log "📦 detected: $NORMALIZED_FORMAT"
    fi
    json_content="$NORMALIZED_CONFIG"
    connector="${connector:-${NORMALIZED_NAME:-connector}}"
    log "🧪 Linting connector config of $connector (nothing is created)"
fi

echo "$json_content" > "$tmp_dir/config.json"

# context of the running environment (best effort, local docker environments only): number of brokers, partitions of
# the topics of a sink, connector.client.config.override.policy of the worker. --brokers gives the size of the
# customer's cluster instead
context="{}"
if [[ -n "$brokers" ]]
then
    context=$(jq -n --argjson b "$brokers" '{brokers: $b}')
fi
environment=$(playground state get run.environment)
if [[ -z "$offline" ]] && [[ "$environment" != "ccloud" ]] && [[ "$environment" != cfk* ]] && is_container_running broker
then
    get_connect_container
    if [[ -z "$brokers" ]]
    then
        nb_brokers=$(get_broker_ids | grep -c . || true)
        if [[ "$nb_brokers" -gt 0 ]]
        then
            context=$(echo "$context" | jq --argjson b "$nb_brokers" '. + {brokers: $b}')
        fi
    fi
    topics=$(echo "$json_content" | jq -r '.topics // empty' 2>/dev/null)
    partitions="{}"
    IFS=',' read -r -a topic_list <<< "$topics"
    for topic in "${topic_list[@]}"
    do
        topic=$(echo "$topic" | xargs)
        [[ -z "$topic" ]] && continue
        nb=$(get_topic_partition_assignment "$topic" | grep -c . || true)
        partitions=$(echo "$partitions" | jq --arg t "$topic" --argjson n "${nb:-0}" '. + {($t): $n}')
    done
    context=$(echo "$context" | jq --argjson p "$partitions" --arg env "$environment" '. + {partitions: $p, environment: $env}')
    if [[ -n "$connect_container" ]]
    then
        # unset = All, the default since Kafka 3.0 (KIP-722)
        policy=$(docker exec "$connect_container" printenv CONNECT_CONNECTOR_CLIENT_CONFIG_OVERRIDE_POLICY 2>/dev/null || true)
        context=$(echo "$context" | jq --arg p "${policy:-All}" '. + {worker_override_policy: $p}')
    fi
fi
if [[ "$context" != "{}" ]]
then
    echo "$context" > "$tmp_dir/context.json"
    lint_args=(--context "$tmp_dir/context.json")
else
    lint_args=()
fi
if [[ -n "$verbose" ]]
then
    log "🐞 context: $(echo "$context" | jq -c .)"
fi

set +e
if [[ -n "$output_json" ]]
then
    python3 -I "$root_folder/tools/connector-lint/lint.py" --config "$tmp_dir/config.json" --name "$connector" "${lint_args[@]}" --json >&3
else
    python3 -I "$root_folder/tools/connector-lint/lint.py" --config "$tmp_dir/config.json" --name "$connector" "${lint_args[@]}"
fi
ret=$?
set -e
exit $ret
