connector="${args[--connector]}"
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
    if [ -f "/tmp/config-$connector" ] && [ -z "$GITHUB_RUN_NUMBER" ]
    then
        log "🧰 Current config for connector $connector (including all sensitive data)"
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
        log "🧰 Current config for connector $connector (not including all sensitive data)"
        if [[ -n "$verbose" ]]
        then
            log "🐞 curl command used"
            echo "curl $security -s -X GET -H "Content-Type: application/json" "https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector/config" --header "authorization: Basic $authorization""
        fi
        curl_output=$(curl $security -s -X GET -H "Content-Type: application/json" "https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector/config" --header "authorization: Basic $authorization")
        ret=$?
        set -e
        if [ $ret -eq 0 ]
        then
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
        else
            logerror "❌ curl request failed with error code $ret!"
            exit 1
        fi
    fi
done