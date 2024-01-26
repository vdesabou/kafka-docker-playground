get_connect_url_and_security

connector="${args[--connector]}"
force_rest_endpoint="${args[--force-rest-endpoint]}"
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
    if [ -f "/tmp/config-$connector" ] && [ -z "$GITHUB_RUN_NUMBER" ] && [[ ! -n "$force_rest_endpoint" ]]
    then
        log "🧰 Current config for connector $connector"
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

            if [ "$clipboard" == "true" ] || [ "$clipboard" == "" ]
            then
                tmp_dir=$(mktemp -d -t ci-XXXXXXXXXX)
                trap 'rm -rf $tmp_dir' EXIT
                echo "playground connector create-or-update --connector $connector << EOF" > $tmp_dir/tmp
                cat "/tmp/config-$connector" | jq -S . | sed 's/\$/\\$/g' >> $tmp_dir/tmp
                echo "EOF" >> $tmp_dir/tmp

                cat $tmp_dir/tmp | pbcopy
                log "📋 connector config has been copied to the clipboard (disable with 'playground config set clipboard false')"
            fi
        fi
    else
        log "🧰 Current config for connector $connector (using REST API /config endpoint)"
        if [[ -n "$verbose" ]]
        then
            log "🐞 curl command used"
            echo "curl $security -s -X GET -H "Content-Type: application/json" "$connect_url/connectors/$connector/config""
        fi
        curl_output=$(curl $security -s -X GET -H "Content-Type: application/json" "$connect_url/connectors/$connector/config")
        ret=$?
        set -e
        if [ $ret -eq 0 ]
        then
            if echo "$curl_output" | jq '. | has("error_code")' 2> /dev/null | grep -q true 
            then
                error_code=$(echo "$curl_output" | jq -r .error_code)
                message=$(echo "$curl_output" | jq -r .message)
                logerror "Command failed with error code $error_code"
                logerror "$message"
                exit 1
            else
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

                    if [ "$clipboard" == "true" ] || [ "$clipboard" == "" ]
                    then
                        tmp_dir=$(mktemp -d -t ci-XXXXXXXXXX)
                        trap 'rm -rf $tmp_dir' EXIT
                        echo "playground connector create-or-update --connector $connector << EOF" > $tmp_dir/tmp
                        echo "$curl_output" | jq -S . | sed 's/\$/\\$/g' >> $tmp_dir/tmp
                        echo "EOF" >> $tmp_dir/tmp

                        cat $tmp_dir/tmp | pbcopy
                        log "📋 connector config has been copied to the clipboard (disable with 'playground config set clipboard false')"
                    fi
                fi
            fi
        else
            logerror "❌ curl request failed with error code $ret!"
            exit 1
        fi
    fi
done