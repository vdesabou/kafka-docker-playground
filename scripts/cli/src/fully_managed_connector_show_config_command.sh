connector="${args[--connector]}"
force_rest_endpoint="${args[--force-rest-endpoint]}"
verbose="${args[--verbose]}"

get_ccloud_connect

if [[ ! -n "$connector" ]]
then
    set +e
    log "✨ --connector flag was not provided, applying command to all ccloud connectors"
    connector=$(playground get-fully-managed-connector-list)
    if [ $? -ne 0 ]
    then
        logerror "❌ Could not get list of connectors"
        echo "$connector"
        exit 1
    fi
    if [ "$connector" == "" ]
    then
        logerror "💤 No ccloud connector is running !"
        exit 1
    fi
    set -e
fi

items=($connector)
for connector in ${items[@]}
do
    if [ -f "/tmp/config-$connector" ] && [ -z "$GITHUB_RUN_NUMBER" ] && [[ ! -n "$force_rest_endpoint" ]]
    then
        log "🧰 Current config for connector $connector"
        echo "playground fully-managed-connector --connector $connector << EOF"
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
                echo "playground fully-managed-connector --connector $connector << EOF" > $tmp_dir/tmp
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
            echo "curl $security -s -X GET -H "Content-Type: application/json" \"https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector/config\" --header \"authorization: Basic $authorization\""
        fi
        curl_output=$(curl $security -s -X GET -H "Content-Type: application/json" "https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector/config" --header "authorization: Basic $authorization")
        ret=$?
        if [ $ret -eq 0 ]
        then
            if echo "$curl_output" | jq 'if .error then .error | has("code") else has("error_code") end' 2> /dev/null | grep -q true
            then
                if echo "$curl_output" | jq '.error | has("code")' 2> /dev/null | grep -q true
                then
                    code=$(echo "$curl_output" | jq -r .error.code)
                    message=$(echo "$curl_output" | jq -r .error.message)
                else
                    code=$(echo "$curl_output" | jq -r .error_code)
                    message=$(echo "$curl_output" | jq -r .message)
                fi
                logerror "Command failed with error code $code"
                logerror "$message"
                exit 1
            else
                echo "playground fully-managed-connector create-or-update --connector $connector << EOF"
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
                        echo "playground fully-managed-connector --connector $connector << EOF" > $tmp_dir/tmp
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