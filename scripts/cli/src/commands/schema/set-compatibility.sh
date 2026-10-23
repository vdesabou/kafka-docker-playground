subject="${args[--subject]}"
compatibility="${args[--compatibility]}"
verbose="${args[--verbose]}"

get_sr_url_and_security

log "🛡️ Set compatibility for subject ${subject} to $compatibility"
if [[ -n "$verbose" ]]
then
    log "🐞 curl command used"
    echo "curl $sr_security -s -X PUT -H "Content-Type: application/vnd.schemaregistry.v1+json" --data "{\"compatibility\": \"$compatibility\"}" "${sr_url}/config/${subject}""
fi
curl_output=$(curl $sr_security -s -X PUT -H "Content-Type: application/vnd.schemaregistry.v1+json" --data "{\"compatibility\": \"$compatibility\"}" "${sr_url}/config/${subject}" | jq .)
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
        # PUT /config answers {"compatibility": …} (GET answers compatibilityLevel)
        compatibilityLevel=$(echo "$curl_output" | jq -r '.compatibility // .compatibilityLevel')
        echo "$compatibilityLevel"
    fi
else
    logerror "❌ curl request failed with error code $ret!"
    exit 1
fi