connector="${args[--connector]}"
force_rest_endpoint="${args[--force-rest-endpoint]}"
verbose="${args[--verbose]}"
no_clipboard="${args[--no-clipboard]}"

connector_type=$(playground state get run.connector_type)
environment=$(playground state get run.environment)
# mdc-* environments: the printed command carries the cluster of the connector
cluster_flag=""
if [[ "$environment" == mdc* ]]
then
    cluster_flag=$(mdc_cluster_flag)
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

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

# prints the config as a create-or-update heredoc, and copies it to the clipboard (macOS)
function print_config () {
    local connector="$1" config_json="$2"
    if [[ -n "$no_clipboard" ]]
    then
        echo "playground connector create-or-update$cluster_flag --connector $connector --no-clipboard << 'EOF'"
    else
        echo "playground connector create-or-update$cluster_flag --connector $connector << 'EOF'"
    fi
    echo "$config_json" | jq -S .
    echo "EOF"

    if [[ "$OSTYPE" == "darwin"* ]]
    then
        clipboard=$(playground config get clipboard)
        if [ "$clipboard" == "" ]
        then
            playground config set clipboard true
        fi

        if ( [ "$clipboard" == "true" ] || [ "$clipboard" == "" ] ) && [[ ! -n "$no_clipboard" ]]
        then
            {
                echo "playground connector create-or-update$cluster_flag --connector $connector << 'EOF'"
                echo "$config_json" | jq -S .
                echo "EOF"
            } > "$tmp_dir/clipboard-$connector"
            pbcopy < "$tmp_dir/clipboard-$connector"
            log "📋 $connector_type connector config has been copied to the clipboard (disable with 'playground config clipboard false')"
        fi
    fi
}

is_ccloud_connector=0
if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
then
    is_ccloud_connector=1
fi

items=($connector)
length=${#items[@]}
if ((length > 1))
then
    log "✨ --connector flag was not provided, applying command to all connectors"
fi
for connector in "${items[@]}"
do
    if [[ "$environment" == cfk* ]] && [ $is_ccloud_connector -eq 0 ]
    then
        log "🧰 Current config for $connector_type connector $connector (using CFK Connector CR)"
        log "☸️ kubectl -n confluent get connector $connector -o json"
        # spec.configs, plus connector.class and tasks.max (spec.class and spec.taskMax of the CR)
        if ! get_connector_config_json "$connector"
        then
            logerror "❌ Could not get config from CFK Connector CR $connector"
            exit 1
        fi
        print_config "$connector" "$curl_output"
        continue
    fi

    if [ -f "/tmp/config-$connector" ] && [ -z "$GITHUB_RUN_NUMBER" ] && [[ ! -n "$force_rest_endpoint" ]]
    then
        log "🧰 Current config for $connector_type connector $connector"
        print_config "$connector" "$(cat "/tmp/config-$connector")"
    else
        log "🧰 Current config for $connector_type connector $connector (using REST API /config endpoint)"
        if ! get_connector_config_json "$connector"
        then
            logerror "❌ Could not get config of $connector_type connector $connector from the REST API"
            exit 1
        fi
        print_config "$connector" "$curl_output"
    fi
done
