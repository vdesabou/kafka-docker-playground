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
    log "🧰 Current config for connector $connector"
    json_config=$(curl $security -s -X GET -H "Content-Type: application/json" "$connect_url/connectors/$connector/config")
    echo "playground connector create-or-update --connector $connector << EOF"
    echo "$json_config" | jq -S . | sed 's/\$/\\$/g'
    echo "EOF"
done