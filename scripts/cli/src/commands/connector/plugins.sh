all="${args[--all]}"
verbose="${args[--verbose]}"

log "🎨 Displaying all connector plugins installed"
if [[ -n "$all" ]]
then
    log "🌕 Displaying also transforms, converters, predicates available"
    if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
    then
        logerror "❌ --all is set but not supported with $connector_type connector"
        exit 1
    else
        get_connect_url_and_security
        handle_onprem_connect_rest_api "curl $security -s -X GET -H \"Content-Type: application/json\" \"$connect_url/connector-plugins?connectorsOnly=false\""
    fi

    echo "$curl_output" | jq -r '.[] | [.class , .version , .type] | @tsv' | column -t

else
    if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
    then
        get_ccloud_connect
        handle_ccloud_connect_rest_api "curl -s --request GET \"https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connector-plugins\" --header \"authorization: Basic $authorization\""
    else
        get_connect_url_and_security
        handle_onprem_connect_rest_api "curl $security -s -X GET -H \"Content-Type: application/json\" \"$connect_url/connector-plugins\""
    fi

    echo "$curl_output" | jq -r '.[] | [.class , .version , .type] | @tsv' | column -t
fi
