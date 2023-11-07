ret=$(get_ccloud_connect)

environment=$(echo "$ret" | cut -d "@" -f 1)
cluster=$(echo "$ret" | cut -d "@" -f 2)
authorization=$(echo "$ret" | cut -d "@" -f 3)

curl_output=$(curl -s --request GET "https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors" \
--header "authorization: Basic $authorization")
ret=$?
if [ $ret -eq 0 ]
then
    if [ "$curl_output" == "[]" ]
    then
        logerror "No connector running"
        exit 1
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