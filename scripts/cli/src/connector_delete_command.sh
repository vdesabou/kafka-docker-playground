get_connect_url_and_security
verbose="${args[--verbose]}"
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
    check_if_continue
fi
for connector in ${items[@]}
do
    log "❌ Deleting connector $connector"
    if [[ -n "$verbose" ]]
    then
        log "🐞 curl command used"
        echo "curl $security -s -X DELETE "$connect_url/connectors/$connector""
    fi
    curl $security -s -X DELETE "$connect_url/connectors/$connector" | jq .
done