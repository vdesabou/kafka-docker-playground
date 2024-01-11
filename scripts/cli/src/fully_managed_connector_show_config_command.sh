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
    log "🧰 Current config for ccloud connector $connector"
    if [[ -n "$verbose" ]]
    then
        log "🐞 curl command used"
        echo "curl $security -s -X GET -H "Content-Type: application/json" "https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector/config" --header "authorization: Basic $authorization""
    fi
    json_config=$(curl $security -s -X GET -H "Content-Type: application/json" "https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector/config" --header "authorization: Basic $authorization")
    echo "playground fully-managed-connector create-or-update --connector $connector << EOF"
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
            echo "playground fully-managed-connector --connector $connector << EOF" > $tmp_dir/tmp
            echo "$json_config" | jq -S . | sed 's/\$/\\$/g' >> $tmp_dir/tmp
            echo "EOF" >> $tmp_dir/tmp

            cat $tmp_dir/tmp | pbcopy
            log "📋 connector config has been copied to the clipboard (disable with 'playground config set clipboard false')"
        fi
    fi
done