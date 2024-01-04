connector="${args[--connector]}"
wait_for_zero_lag="${args[--wait-for-zero-lag]}"
verbose="${args[--verbose]}"

get_ccloud_connect

if [[ ! -n "$connector" ]]
then
    set +e
    log "✨ --connector flag was not provided, applying command to all ccloud connectors"
    connector=$(playground get-fully-managed-connector-list)
    if [ $? -ne 0 ]
    then
        logerror "❌ Could not get list of connectors"
        echo "$connector"
        exit 1
    fi
    if [ "$connector" == "" ]
    then
        logerror "💤 No ccloud connector is running !"
        exit 1
    fi
    set -e
fi

get_kafka_docker_playground_dir
DELTA_CONFIGS_ENV=$KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/env.delta

if [ -f $DELTA_CONFIGS_ENV ]
then
    source $DELTA_CONFIGS_ENV
else
    logerror "ERROR: $DELTA_CONFIGS_ENV has not been generated"
    exit 1
fi
if [ ! -f $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta ]
then
    logerror "ERROR: $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta has not been generated"
    exit 1
fi

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

    if [[ -n "$wait_for_zero_lag" ]]
    then
        CHECK_INTERVAL=5
        SECONDS=0
        while true
        do
            get_connect_image
            lag_output=$(docker run --rm -v $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta:/tmp/configuration/ccloud.properties -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SASL_JAAS_CONFIG="$SASL_JAAS_CONFIG" ${CP_CONNECT_IMAGE}:${CONNECT_TAG} kafka-consumer-groups --bootstrap-server $BOOTSTRAP_SERVERS --command-config /tmp/configuration/ccloud.properties --group connect-$connectorId --describe)

            set +e
            echo "$lag_output" | awk -F" " '{ print $6 }' | grep "-"
            if [ $? -eq 0 ]
            then
                logwarn "🐢 consumer lag for connector $connector ($connectorId) is not set"
                echo "$lag_output" | awk -F" " '{ print $3,$4,$5,$6 }'
                sleep $CHECK_INTERVAL
            else
                total_lag=$(echo "$lag_output" | grep -v "PARTITION" | awk -F" " '{sum+=$6;} END{print sum;}')
                if [ $total_lag -ne 0 ]
                then
                    log "🐢 consumer lag for connector $connector ($connectorId) is $total_lag"
                    echo "$lag_output" | awk -F" " '{ print $3,$4,$5,$6 }'
                    sleep $CHECK_INTERVAL
                else
                    ELAPSED="took: $((($SECONDS / 60) % 60))min $(($SECONDS % 60))sec"
                    log "🏁 consumer lag for connector $connector ($connectorId) is 0 ! $ELAPSED"
                    break
                fi
            fi
        done
    else
        log "🐢 Show lag for sink connector $connector ($connectorId)"
        if [[ -n "$verbose" ]]
        then
            log "🐞 CLI command used"
            echo "kafka-consumer-groups --bootstrap-server $BOOTSTRAP_SERVERS --command-config /tmp/configuration/ccloud.properties --group connect-$connectorId --describe"
        fi
        get_connect_image
        docker run --rm -v $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta:/tmp/configuration/ccloud.properties -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SASL_JAAS_CONFIG="$SASL_JAAS_CONFIG" ${CP_CONNECT_IMAGE}:${CONNECT_TAG} kafka-consumer-groups --bootstrap-server $BOOTSTRAP_SERVERS --command-config /tmp/configuration/ccloud.properties --group connect-$connectorId --describe
    fi
done
