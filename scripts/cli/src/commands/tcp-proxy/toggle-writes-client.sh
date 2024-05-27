connection_id="${args[--connection-id]}"

if [[ ! -n "$connection_id" ]]
then
    connection_id=$(playground get-zazkia-connection-list)
    if [ "$connection_id" == "" ]
    then
        logerror "❌ No active Zazkia TCP connection found, make sure that Zazkia is being used!"
        exit 1
    fi
fi

items=($connection_id)
length=${#items[@]}
if ((length > 1))
then
    log "🧲 --connection-id flag was not provided, applying command to all active Zazkia TCP connections"
fi
for id in "${items[@]}"
do
    log "✅ toggle-writes-client for connection id $id"
    handle_onprem_connect_rest_api "curl -o /dev/null -w '%{http_code}' -s -X POST -H \"Content-Type: application/json\" \"http://localhost:9191/links/$id/toggle-writes-client\""
    echo "$curl_output"
done