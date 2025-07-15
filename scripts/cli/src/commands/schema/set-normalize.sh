value="${args[--value]}"
verbose="${args[--verbose]}"

get_sr_url_and_security

log "🧽 Set normalize to $value at schema registry level"
if [[ -n "$verbose" ]]
then
    log "🐞 curl command used"
    echo "curl $sr_security -s -X PUT -H "Content-Type: application/vnd.schemaregistry.v1+json" --data "{\"normalize\": \"${value}\"}" "${sr_url}/config""
fi
curl_output=$(curl $sr_security -s -X PUT -H "Content-Type: application/vnd.schemaregistry.v1+json" --data "{\"normalize\": \"${value}\"}" "${sr_url}/config" | jq .)
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
        normalize=$(echo "$curl_output" | jq -r .normalize)
        echo "$normalize"
    fi
else
    logerror "❌ curl request failed with error code $ret!"
    exit 1
fi