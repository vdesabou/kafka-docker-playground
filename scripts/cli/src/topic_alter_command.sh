topic="${args[--topic]}"

get_security_broker "--command-config"
get_environment_used



playground topic get-number-records --topic $topic > /tmp/result.log 2>/tmp/result.log
set +e
grep "does not exist" /tmp/result.log > /dev/null 2>&1
if [ $? == 0 ]
then
    logwarn "🆕 topic $topic does not exist, creating it..."
    playground topic create --topic $topic

    playground topic alter --topic $topic ${other_args[*]}
else
    log "🪛 Altering topic $topic"
    if [[ "$environment" == "ccloud" ]]
    then
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

        get_connect_image
        docker run --rm -v /tmp/delta_configs/ak-tools-ccloud.delta:/tmp/configuration/ccloud.properties ${CP_CONNECT_IMAGE}:${CONNECT_TAG} kafka-configs --alter --entity-type topics --entity-name $topic --bootstrap-server $BOOTSTRAP_SERVERS --command-config /tmp/configuration/ccloud.properties ${other_args[*]}
    else
        docker exec $container kafka-configs --alter --entity-type topics --entity-name $topic --bootstrap-server broker:9092 $security ${other_args[*]}
    fi
fi
set -e
