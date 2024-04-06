level="${args[--level]}"
connector="${args[--connector]}"

connector_type=$(playground state get run.connector_type)

if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
then
    log "connector log-level command is not supported with $connector_type connector"
    exit 0
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

log "🔰 also setting io.confluent.kafka.schemaregistry.client.rest.RestService (to see schema registry rest requests) to $level"
playground debug log-level set -p "io.confluent.kafka.schemaregistry.client.rest.RestService" -l $level
log "🔗 also setting org.apache.kafka.connect.runtime.TransformationChain (to see records before and after SMTs) to $level"
playground debug log-level set -p "org.apache.kafka.connect.runtime.TransformationChain" -l $level

items=($connector)
length=${#items[@]}
if ((length > 1))
then
    log "✨ --connector flag was not provided, applying command to all connectors"
fi
for connector in "${items[@]}"
do
    get_connect_url_and_security
    handle_onprem_connect_rest_api "curl -s $security \"$connect_url/connectors/$connector\""

    tmp=$(echo "$curl_output" | jq -r '.config."connector.class"')
    package="${tmp%.*}"

    type=$(echo "$curl_output" | jq -r '.type')
    if [ "$type" == "sink" ]
    then
        log "🔗 also setting org.apache.kafka.connect.runtime.WorkerSinkTask to $level"
        playground debug log-level set -p "org.apache.kafka.connect.runtime.WorkerSinkTask" -l $level
    else
        log "🔗 also setting org.apache.kafka.connect.runtime.WorkerSourceTask to $level"
        playground debug log-level set -p "org.apache.kafka.connect.runtime.WorkerSourceTask" -l $level
    fi
    # log "🧬 Set log level for connector $connector to $level"
    playground debug log-level set -p "$package" -l "$level"
done