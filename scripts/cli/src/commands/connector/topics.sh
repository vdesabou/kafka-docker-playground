connector="${args[--connector]}"
verbose="${args[--verbose]}"
reset="${args[--reset]}"
json="${args[--json]}"

connector_type=$(playground state get run.connector_type)

if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
then
    log "connector topics command is not supported with $connector_type connector"
    exit 0
fi

if [[ ! -n "$connector" ]]
then
    connector=$(playground get-connector-list)
    if [ "$connector" == "" ]
    then
        logerror "💤 No $connector_type connector is running !"
        exit 1
    fi
fi

tag=$(get_running_cp_tag)
if [ -n "$tag" ] && ! version_gt $tag "5.4.99"
then
    logerror "❌ the active topics of a connector are tracked since CP 5.5 (KIP-558), current version is $tag"
    exit 1
fi

get_connect_url_and_security

items=($connector)
length=${#items[@]}
if ((length > 1)) && [[ -z "$json" ]]
then
    log "✨ --connector flag was not provided, applying command to all connectors"
fi

results="{}"
for connector in "${items[@]}"
do
    # the /topics endpoints do not check that the connector exists
    if ! handle_onprem_connect_rest_api "curl $security -s \"$connect_url/connectors/$connector/status\"" > /dev/null
    then
        logerror "❌ $connector_type connector $connector not found"
        exit 1
    fi
    if [[ -n "$reset" ]]
    then
        log "🧹 Resetting the active topics of $connector_type connector $connector"
        handle_onprem_connect_rest_api "curl $security -s -X PUT \"$connect_url/connectors/$connector/topics/reset\"" || exit 1
        log "🧹 The active topics of $connector_type connector $connector have been reset, the list fills again with the topics it uses from now on"
        continue
    fi

    handle_onprem_connect_rest_api "curl $security -s \"$connect_url/connectors/$connector/topics\"" || exit 1
    topics=$(echo "$curl_output" | jq -c --arg c "$connector" '.[$c].topics // [] | sort')
    results=$(echo "$results" | jq --arg c "$connector" --argjson t "$topics" '. + {($c): $t}')

    if [[ -n "$json" ]]
    then
        continue
    fi

    nb=$(echo "$topics" | jq 'length')
    if [ "$nb" == "0" ]
    then
        log "📚 $connector_type connector $connector has no active topic yet: it has not produced or consumed any record since it started or since its last reset"
    else
        log "📚 Active topics of $connector_type connector $connector ($nb):"
        echo "$topics" | jq -r '.[]'
    fi
done

if [[ -n "$json" ]]
then
    echo "$results" | jq .
fi
