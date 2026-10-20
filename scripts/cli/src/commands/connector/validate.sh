connector="${args[--connector]}"
json=${args[json]}
skip_automatic_connector_config=${args[--skip-automatic-connector-config]}
verbose="${args[--verbose]}"

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
    if ! echo "$json_content" | jq -e 'type == "object"' > /dev/null 2>&1
    then
        logerror "❌ the config is not a valid JSON object"
        exit 1
    fi
    connector="${connector:-playground-validate}"
    log "🔎 Validating $connector_type connector config (nothing is created)"
fi

set +e
validate_connector_config "$connector" "$json_content" "$tmp_dir" "$environment" "$is_cfk" "$skip_automatic_connector_config"
ret=$?
set -e
if [ $ret -eq 1 ]
then
    exit 1
fi
