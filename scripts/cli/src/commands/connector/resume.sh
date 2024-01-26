get_connect_url_and_security

connector="${args[--connector]}"
verbose="${args[--verbose]}"

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
    log "⏯️ Resuming connector $connector"
    if [[ -n "$verbose" ]]
    then
        log "🐞 curl command used"
        echo "curl $security -s -X PUT -H "Content-Type: application/json" "$connect_url/connectors/$connector/resume""
    fi
    curl $security -s -X PUT -H "Content-Type: application/json" "$connect_url/connectors/$connector/resume"  | jq .

    sleep 1
    playground connector status --connector $connector
done