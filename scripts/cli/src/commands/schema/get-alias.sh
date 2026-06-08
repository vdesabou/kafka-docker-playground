alias="${args[--alias]}"
verbose="${args[--verbose]}"

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

log "🔯 Get alias for alias ${alias}"
if [[ -n "$verbose" ]]
then
    log "🐞 curl command used"
    echo "curl $sr_security -s -H "Content-Type: application/vnd.schemaregistry.v1+json" "${sr_url}/config/${alias}""
fi
curl_output=$(curl $sr_security -s -H "Content-Type: application/vnd.schemaregistry.v1+json" "${sr_url}/config/${alias}")
ret=$?
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
        alias=$(echo "$curl_output" | jq -r .alias)
        echo "$alias"
    fi
else
    logerror "❌ curl request failed with error code $ret!"
    exit 1
fi