get_connect_url_and_security

connector="${args[--connector]}"

if [[ ! -n "$connector" ]]
then
    connector=$(playground get-connector-list)
    if [ "$connector" == "" ]
    then
        logerror "💤 No connector is running !"
        exit 1
    fi
fi

items=($connector)
length=${#items[@]}
if ((length > 1))
then
    log "✨ --connector flag was not provided, applying command to all connectors"
fi
for connector in ${items[@]}
do
    log "⏸️ Pausing connector $connector"
    curl $security -s -X PUT -H "Content-Type: application/json" "$connect_url/connectors/$connector/pause" | jq .

    sleep 1
    playground connector status --connector $connector
done