get_ccloud_connect

curl_output=$(curl -s --request GET "https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors" \
--header "authorization: Basic $authorization")
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
    if echo "$curl_output" | jq 'if .error then .error | has("error_code") else has("error_code") end' 2> /dev/null | grep -q true 
    then
        if echo "$curl_output" | jq '.error | has("error_code")' 2> /dev/null | grep -q true 
        then
            code=$(echo "$curl_output" | jq -r .error.code)
            message=$(echo "$curl_output" | jq -r .error.message)
        else
            code=$(echo "$curl_output" | jq -r .error_code)
            message=$(echo "$curl_output" | jq -r .message)
        fi
        logerror "Command failed with error code $code"
        logerror "$message"
        exit 1
    else
    echo "$curl_output" | jq -r '.[]' | tr '\n' ' ' | sed -e 's/[[:space:]]*$//'
    fi
else
    logerror "❌ curl request failed with error code $ret!"
    exit 1
fi