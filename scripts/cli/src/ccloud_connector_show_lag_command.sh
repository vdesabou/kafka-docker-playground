ret=$(get_ccloud_connect)

environment=$(echo "$ret" | cut -d "@" -f 1)
cluster=$(echo "$ret" | cut -d "@" -f 2)
authorization=$(echo "$ret" | cut -d "@" -f 3)

connector="${args[--connector]}"

if [[ ! -n "$connector" ]]
then
    log "✨ --connector flag was not provided, applying command to all ccloud connectors"
    connector=$(playground get-ccloud-connector-list)
    if [ "$connector" == "" ]
    then
        logerror "💤 No ccloud connector is running !"
        exit 1
    fi
fi

if [ -f /tmp/delta_configs/env.delta ]
then
    source /tmp/delta_configs/env.delta
else
    logerror "ERROR: /tmp/delta_configs/env.delta has not been generated"
    exit 1
fi
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

items=($connector)
for connector in ${items[@]}
do
    type=$(curl -s --request GET "https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector?expand=status" --header "authorization: Basic $authorization" | jq -r '.type')
    if [ "$type" != "sink" ]
    then
        logwarn "⏭️ Skipping $type connector $connector, it must be a sink to show the lag"
        continue 
    fi
    connectorId=$(get_ccloud_connector_lcc $connector)

    log "🐢 Show lag for sink connector $connector ($connectorId)"
    #docker exec $container kafka-consumer-groups --bootstrap-server broker:9092 --group connect-$connector --describe $security
    docker run --rm -v /tmp/delta_configs/ak-tools-ccloud.delta:/tmp/configuration/ccloud.properties -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SASL_JAAS_CONFIG="$SASL_JAAS_CONFIG" ${CP_CONNECT_IMAGE}:${CONNECT_TAG} kafka-consumer-groups --bootstrap-server $BOOTSTRAP_SERVERS --command-config /tmp/configuration/ccloud.properties --group connect-$connectorId --describe
done
