topic="${args[--topic]}"

get_security_broker "--command-config"
get_environment_used

set +e
existing_topics=$(playground get-topic-list)
if ! echo "$existing_topics" | grep -qFx "$topic"
then
    logwarn "🆕 topic $topic does not exist, creating it..."
    # created once, then altered below: no recursive call, which looped forever when the creation failed or when the
    # topic only showed up later (asynchronous creation)
    if ! playground topic create --topic "$topic"
    then
        logerror "❌ could not create topic $topic"
        exit 1
    fi
fi

log "🪛 Altering topic $topic"
rc=0
if [[ "$environment" == "ccloud" ]]
then
    get_kafka_docker_playground_dir
    DELTA_CONFIGS_ENV=$KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/env.delta

    if [ -f $DELTA_CONFIGS_ENV ]
    then
        source $DELTA_CONFIGS_ENV
    else
        logerror "❌ $DELTA_CONFIGS_ENV has not been generated"
        exit 1
    fi
    if [ ! -f $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta ]
    then
        logerror "❌ $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta has not been generated"
        exit 1
    fi

    get_connect_image
    docker run --quiet --rm -v $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta:/tmp/configuration/ccloud.properties ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} kafka-configs --alter --entity-type topics --entity-name $topic --bootstrap-server $BOOTSTRAP_SERVERS --command-config /tmp/configuration/ccloud.properties ${other_args[*]} || rc=$?
elif [[ "$environment" == cfk* ]]
then
    kubectl -n confluent exec $container -- kafka-configs --alter --entity-type topics --entity-name $topic --bootstrap-server $bootstrap_server $security ${other_args[*]} || rc=$?
else
    docker exec $container kafka-configs --alter --entity-type topics --entity-name $topic --bootstrap-server $bootstrap_server $security ${other_args[*]} || rc=$?
fi
if [ $rc -ne 0 ]
then
    logerror "❌ could not alter topic $topic (kafka-configs exit code $rc)"
    exit 1
fi
