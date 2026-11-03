connector="${args[--connector]}"
json=${args[json]}
skip_automatic_connector_config=${args[--skip-automatic-connector-config]}
verbose="${args[--verbose]}"
output_json="${args[--json]}"

# --json: the verdict and the errors per key are the only thing on stdout (fd 3), everything else (log lines, nested
# commands) goes to stderr
if [[ -n "$output_json" ]]
then
    exec 3>&1 1>&2
fi

connector_type=$(playground state get run.connector_type)

environment=$(playground state get run.environment_before_switch)
if [ "$environment" = "" ]
then
    environment=$(playground state get run.environment)
fi
if [ "$environment" = "" ]
then
    environment="plaintext"
fi
is_cfk=0
if [[ "$environment" == cfk* ]]
then
    is_cfk=1
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
    # no config on stdin: validate the config of the running connector
    if [[ -z "$connector" ]]
    then
        logerror "❌ give the config to validate on stdin, or --connector to validate the config of a running connector"
        exit 1
    fi
    if ! get_connector_config_json "$connector"
    then
        logerror "❌ could not get the config of connector $connector"
        exit 1
    fi
    json_content="$curl_output"
    log "🔎 Validating the config of running $connector_type connector $connector"
    if echo "$json_content" | jq -e 'to_entries | any(.value | tostring | test("^(\\*+|\\[hidden\\])$") or contains("••"))' > /dev/null 2>&1
    then
        logwarn "⚠️ the REST API masks the passwords of the running config: errors on those keys can be false positives"
    fi
    # the running config already has what create-or-update added for the environment
    skip_automatic_connector_config=running
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
    connector="${connector:-${NORMALIZED_NAME:-playground-validate}}"
    log "🔎 Validating $connector_type connector config (nothing is created)"
fi

set +e
if [[ -n "$output_json" ]]
then
    # the error messages of the helper go to stderr too, only the JSON verdict is on stdout
    validate_connector_config "$connector" "$json_content" "$tmp_dir" "$environment" "$is_cfk" "$skip_automatic_connector_config" 1>&2
else
    validate_connector_config "$connector" "$json_content" "$tmp_dir" "$environment" "$is_cfk" "$skip_automatic_connector_config"
fi
ret=$?
set -e
if [[ -n "$output_json" ]]
then
    validate_answer="$curl_output"
    if [ $ret -eq 2 ] || ! echo "$validate_answer" | jq -e '.configs' > /dev/null 2>&1
    then
        validate_answer='{"configs": []}'
    fi
    echo "$validate_answer" | jq --arg connector "$connector" --arg class "$(echo "$json_content" | jq -r '."connector.class" // empty' 2>/dev/null)" \
        --arg type "$connector_type" --argjson ret "$ret" '
        [.configs[]? | select((.value.errors // []) | length > 0) | {key: .value.name, value: .value.value, errors: .value.errors}] as $errors
        | {connector: $connector, connector_class: $class, type: $type,
           valid: ($ret != 1), basic_checks_only: ($ret == 2), error_count: ($errors | length), errors: $errors}' >&3
fi
if [ $ret -eq 1 ]
then
    exit 1
fi
