if [ ! -f /tmp/delta_configs/ak-tools-ccloud.delta ]
then
    logerror "ERROR: /tmp/delta_configs/ak-tools-ccloud.delta has not been generated"
    exit 1
fi
DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
dir1=$(echo ${DIR_CLI%/*})
root_folder=$(echo ${dir1%/*})
IGNORE_CHECK_FOR_DOCKER_COMPOSE=true
source $root_folder/scripts/utils.sh

environment=$(grep "ENVIRONMENT ID" /tmp/delta_configs/ak-tools-ccloud.delta | cut -d " " -f 4)
cluster=$(grep "KAFKA CLUSTER ID" /tmp/delta_configs/ak-tools-ccloud.delta | cut -d " " -f 5)

if [[ "$OSTYPE" == "darwin"* ]]
then
    authorization=$(echo -n "$CLOUD_API_KEY:$CLOUD_API_SECRET" | base64)
else
    authorization=$(echo -n "$CLOUD_API_KEY:$CLOUD_API_SECRET" | base64 -w 0)
fi

curl -s --request GET "https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors?expand=info%2Cstatus%2Cid" \
--header "authorization: Basic $authorization" | jq