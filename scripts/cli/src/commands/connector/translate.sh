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
json_file=$tmp_dir/connector.json

items=($connector)
length=${#items[@]}
if ((length > 1))
then
    log "✨ --connector flag was not provided, applying command to all connectors"
fi
for connector in "${items[@]}"
do
    playground --output-level WARN connector show-config --connector "$connector" --no-clipboard | grep -v "EOF" | sed 's/\\//g' >> $json_file
    if [ $? -ne 0 ]
    then
        logerror "❌ playground connector show-config --connector $connector failed with:"
        cat $file
        exit 1
    fi

    # connector_class=$(cat "$json_file" | jq -r '."connector.class"')
    # class=$(echo $connector_class | rev | cut -d '.' -f 1 | rev)

    log "💱 Translating $connector_type connector $connector ($connector_plugin)"
    get_ccloud_connect
    handle_ccloud_connect_rest_api "curl -s --request PUT -H \"Content-Type: application/json\" --data @$json_file \"https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connector-plugins/$connector_plugin/config/translate\" --header \"authorization: Basic $authorization\""
done