connector_type=$(playground state get run.connector_type)
environment=$(playground state get run.environment_before_switch)
if [ "$environment" = "" ]
then
    environment=$(playground state get run.environment)
fi

if [ "$environment" = "cfk" ] && [ "$connector_type" != "$CONNECTOR_TYPE_FULLY_MANAGED" ] && [ "$connector_type" != "$CONNECTOR_TYPE_CUSTOM" ]
then
    set +e
    connectors=$(kubectl -n confluent get connectors.platform.confluent.io -o custom-columns=NAME:.metadata.name --no-headers 2>/dev/null)
    rc=$?
    set -e

    if [ $rc -ne 0 ]
    then
        exit 0
    fi

    echo "$connectors" | tr '\n' ' ' | sed -e 's/[[:space:]]*$//'
    exit 0
fi

if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
then
    get_ccloud_connect
    handle_ccloud_connect_rest_api "curl -s --request GET \"https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors\" --header \"authorization: Basic $authorization\""
else
    get_connect_url_and_security
    handle_onprem_connect_rest_api "curl $security -s \"$connect_url/connectors\""
fi

echo "$curl_output" | jq -r '.[]' | tr '\n' ' ' | sed -e 's/[[:space:]]*$//'