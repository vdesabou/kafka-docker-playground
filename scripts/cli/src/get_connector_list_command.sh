ret=$(get_connect_url_and_security)

connect_url=$(echo "$ret" | cut -d "@" -f 1)
security=$(echo "$ret" | cut -d "@" -f 2)

curl_output=$(curl $security -s "$connect_url/connectors")
ret=$?
if [ $ret -eq 0 ]
then
    if [ "$curl_output" == "[]" ]
    then
        # logerror "No connector running"
        # exit 1
        echo ""
        return
    fi
    error_code=$(echo "$curl_output" | jq -r .error_code)
    if [ "$error_code" != "null" ]
    then
        message=$(echo "$curl_output" | jq -r .message)
        logerror "Command failed with error code $error_code"
        logerror "$message"
        exit 1
    else
        echo "$curl_output" | jq -r '.[]' | tr '\n' ' ' | sed -e 's/[[:space:]]*$//'
    fi
else
    logerror "❌ curl request failed with error code $ret!"
    exit 1
fi