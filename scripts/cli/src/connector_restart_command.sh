ret=$(get_connect_url_and_security)

connect_url=$(echo "$ret" | cut -d "@" -f 1)
security=$(echo "$ret" | cut -d "@" -f 2)

connector="${args[--connector]}"

if [[ ! -n "$connector" ]]
then
    log "✨ --connector flag was not provided, applying command to all connectors"
    connector=$(playground get-connector-list)
    if [ "$connector" == "" ]
    then
        logerror "💤 No connector is running !"
        exit 1
    fi
fi

items=($connector)
for connector in ${items[@]}
do
    log "🔄 Restarting connector $connector"
    curl $security -s -X POST -H "Content-Type: application/json" "$connect_url/connectors/$connector/restart?includeTasks=true&onlyFailed=false" | jq .
done
sleep 2
playground connector status