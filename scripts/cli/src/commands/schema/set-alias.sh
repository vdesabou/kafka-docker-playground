subject="${args[--subject]}"
alias="${args[--alias]}"
verbose="${args[--verbose]}"


get_environment_used
if [[ "$environment" != "ccloud" ]]
then
    get_connect_image

    if ! version_gt $CP_CONNECT_TAG "7.4.1"
    then
        logerror "❌ subject aliases are available since CP 7.4.1 only"
        exit 1
    fi
fi

get_sr_url_and_security

log "🔯 Set alias for subject ${subject} with alias ${alias}"
if [[ -n "$verbose" ]]
then
    log "🐞 curl command used"
    echo "curl $sr_security -s -X PUT -H "Content-Type: application/vnd.schemaregistry.v1+json" --data "{\"alias\": \"$subject\"}" "${sr_url}/config/${alias}""
fi
curl_output=$(curl $sr_security -s -X PUT -H "Content-Type: application/vnd.schemaregistry.v1+json" --data "{\"alias\": \"$subject\"}" "${sr_url}/config/${alias}" | jq .)
ret=$?
if [ $ret -eq 0 ]
then
    error_code=$(echo "$curl_output" | jq -r .error_code)
    if [ "$error_code" != "null" ]
    then
        message=$(echo "$curl_output" | jq -r .message)
        logerror "Command failed with error code $error_code"
        logerror "$message"
        exit 1
    else
        alias=$(echo "$curl_output" | jq -r .alias)
        echo "$alias"
    fi
else
    logerror "❌ curl request failed with error code $ret!"
    exit 1
fi