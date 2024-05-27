delay_service_response="${args[--delay-service-response]}"
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
    log "⏲️ Add $delay_service_response milliseconds delay to service response for connection id $id"
    handle_onprem_connect_rest_api "curl -s -X POST -H \"Content-Type: application/json\" \"http://localhost:9191/links/$id/delay-response?ms=$delay_service_response\""

    echo "$curl_output"

    sleep 1

    playground tcp-proxy get-connections --connection-id $connection_id
done