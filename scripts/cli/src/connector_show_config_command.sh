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
    log "🧰 Current config for connector $connector"
    if [[ -n "$verbose" ]]
    then
        log "🐞 curl command used"
        echo "curl $security -s -X GET -H "Content-Type: application/json" "$connect_url/connectors/$connector/config""
    fi
    json_config=$(curl $security -s -X GET -H "Content-Type: application/json" "$connect_url/connectors/$connector/config")
    echo "playground connector create-or-update --connector $connector << EOF"
    echo "$json_config" | jq -S . | sed 's/\$/\\$/g'
    echo "EOF"

    if [[ "$OSTYPE" == "darwin"* ]]
    then
        clipboard=$(playground config get clipboard)
        if [ "$clipboard" == "" ]
        then
            playground config set clipboard true
        fi

        if [ "$clipboard" == "true" ] || [ "$clipboard" == "" ]
        then
            tmp_dir=$(mktemp -d -t ci-XXXXXXXXXX)
            trap 'rm -rf $tmp_dir' EXIT
            echo "playground connector create-or-update --connector $connector << EOF" > $tmp_dir/tmp
            echo "$json_config" | jq -S . | sed 's/\$/\\$/g' >> $tmp_dir/tmp
            echo "EOF" >> $tmp_dir/tmp

            cat $tmp_dir/tmp | pbcopy
            log "📋 connector config has been copied to the clipboard (disable with 'playground config set clipboard false')"
        fi
    fi
done