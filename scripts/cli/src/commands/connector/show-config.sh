connector="${args[--connector]}"
force_rest_endpoint="${args[--force-rest-endpoint]}"
verbose="${args[--verbose]}"
no_clipboard="${args[--no-clipboard]}"

connector_type=$(playground state get run.connector_type)

if [[ ! -n "$connector" ]]
then
    connector=$(playground get-connector-list)
    if [ "$connector" == "" ]
    then
        log "💤 No $connector_type connector is running !"
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
    if [ -f "/tmp/config-$connector" ] && [ -z "$GITHUB_RUN_NUMBER" ] && [[ ! -n "$force_rest_endpoint" ]]
    then
        log "🧰 Current config for $connector_type connector $connector"
        echo "playground connector create-or-update --connector $connector << EOF"
        cat "/tmp/config-$connector" | jq -S . | sed 's/\$/\\$/g'
        echo "EOF"

        if [[ "$OSTYPE" == "darwin"* ]]
        then
            clipboard=$(playground config get clipboard)
            if [ "$clipboard" == "" ]
            then
                playground config set clipboard true
            fi

            if ( [ "$clipboard" == "true" ] || [ "$clipboard" == "" ] ) && [[ ! -n "$no_clipboard" ]]
            then
                tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
                if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi
                echo "playground connector create-or-update --connector $connector << EOF" > $tmp_dir/tmp
                cat "/tmp/config-$connector" | jq -S . | sed 's/\$/\\$/g' >> $tmp_dir/tmp
                echo "EOF" >> $tmp_dir/tmp

                cat $tmp_dir/tmp | pbcopy
                log "📋 $connector_type connector config has been copied to the clipboard (disable with 'playground config set clipboard false')"
            fi
        fi
    else
        log "🧰 Current config for $connector_type connector $connector (using REST API /config endpoint)"

        if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
        then
            get_ccloud_connect
            handle_ccloud_connect_rest_api "curl $security -s -X GET -H \"Content-Type: application/json\" \"https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector/config\" --header \"authorization: Basic $authorization\""
        else
            get_connect_url_and_security
            handle_onprem_connect_rest_api "curl $security -s -X GET -H \"Content-Type: application/json\" \"$connect_url/connectors/$connector/config\""
        fi

        echo "playground connector create-or-update --connector $connector << EOF"
        echo "$curl_output" | jq -S . | sed 's/\$/\\$/g'
        echo "EOF"

        if [[ "$OSTYPE" == "darwin"* ]]
        then
            clipboard=$(playground config get clipboard)
            if [ "$clipboard" == "" ]
            then
                playground config set clipboard true
            fi

            if ( [ "$clipboard" == "true" ] || [ "$clipboard" == "" ] ) && [[ ! -n "$no_clipboard" ]]
            then
                tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
                if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi
                echo "playground connector create-or-update --connector $connector << EOF" > $tmp_dir/tmp
                echo "$curl_output" | jq -S . | sed 's/\$/\\$/g' >> $tmp_dir/tmp
                echo "EOF" >> $tmp_dir/tmp

                cat $tmp_dir/tmp | pbcopy
                log "📋 $connector_type connector config has been copied to the clipboard (disable with 'playground config set clipboard false')"
            fi
        fi
    fi
done