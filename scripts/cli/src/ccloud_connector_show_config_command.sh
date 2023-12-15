connector="${args[--connector]}"
verbose="${args[--verbose]}"

get_ccloud_connect

if [[ ! -n "$connector" ]]
then
    set +e
    log "✨ --connector flag was not provided, applying command to all ccloud connectors"
    connector=$(playground get-ccloud-connector-list)
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
    echo "playground ccloud-connector create-or-update --connector $connector << EOF"
    echo "$json_config" | jq -S . | sed 's/\$/\\$/g'
    echo "EOF"
done