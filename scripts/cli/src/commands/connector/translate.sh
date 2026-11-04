connector="${args[--connector]}"
connector_plugin="${args[--connector-plugin]}"
verbose="${args[--verbose]}"

if [[ $connector_plugin == *"@"* ]]
then
  connector_plugin=$(echo "$connector_plugin" | cut -d "@" -f 2)
fi

if [[ $connector_plugin == *"/"* ]]
then
  connector_plugin=$(echo "$connector_plugin" | cut -d "/" -f 2)
fi

connector_type=$(playground state get run.connector_type)

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

items=($connector)
length=${#items[@]}
if ((length > 1))
then
    log "✨ --connector flag was not provided, applying command to all connectors"
fi
for connector in "${items[@]}"
do
    # one file per connector: the config is read as JSON from the REST API (or the CR on cfk), never from the
    # show-config heredoc, so backslashes and quotes inside values reach the translate API untouched
    json_file="$tmp_dir/connector-$connector.json"
    if ! get_connector_config_json "$connector"
    then
        logerror "❌ could not read the config of connector $connector"
        exit 1
    fi
    echo "$curl_output" > "$json_file"

    log "💱 Translating $connector_type connector $connector ($connector_plugin)"
    get_ccloud_connect
    handle_ccloud_connect_rest_api "curl -s --request PUT -H \"Content-Type: application/json\" --data @$json_file \"https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connector-plugins/$connector_plugin/config/translate\" --header \"authorization: Basic $authorization\""
    # the helper prints the answer itself when it has errors or warnings, print it otherwise
    if ! echo "$curl_output" | jq -e 'has("errors") or has("warnings")' > /dev/null 2>&1
    then
        echo "$curl_output" | jq .
    fi
done
