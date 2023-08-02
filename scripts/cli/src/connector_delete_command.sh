ret=$(get_connect_url_and_security)

connect_url=$(echo "$ret" | cut -d "@" -f 1)
security=$(echo "$ret" | cut -d "@" -f 2)

connector="${args[--connector]}"

if [[ ! -n "$connector" ]]
then
    logwarn "--connector flag was not provided, applying command to all connectors"
    check_if_continue
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
    log "❌ Deleting connector $connector"
    curl $security -s -X DELETE "$connect_url/connectors/$connector" | jq .
done