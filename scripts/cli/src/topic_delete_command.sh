topic="${args[--topic]}"
verbose="${args[--verbose]}"
skip_delete_schema="${args[--skip-delete-schema]}"

get_security_broker "--command-config"
get_environment_used



playground topic get-number-records --topic $topic > /tmp/result.log 2>/tmp/result.log
set +e
grep "does not exist" /tmp/result.log > /dev/null 2>&1
if [ $? == 0 ]
then
    logwarn "❌ topic $topic does not exist !"
    exit 1
fi
set -e

log "❌ Deleting topic $topic"
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
    if [[ -n "$verbose" ]]
    then
        log "🐞 CLI command used"
        echo "kafka-topics --delete --topic $topic --bootstrap-server $BOOTSTRAP_SERVERS --command-config /tmp/configuration/ccloud.properties"
    fi
    get_connect_image
    docker run --rm -v /tmp/delta_configs/ak-tools-ccloud.delta:/tmp/configuration/ccloud.properties ${CP_CONNECT_IMAGE}:${CONNECT_TAG} kafka-topics --delete --topic $topic --bootstrap-server $BOOTSTRAP_SERVERS --command-config /tmp/configuration/ccloud.properties
else
    if [[ -n "$verbose" ]]
    then
        log "🐞 CLI command used"
        echo "kafka-topics --delete --topic $topic --bootstrap-server broker:9092 $security"
    fi
    docker exec $container kafka-topics --delete --topic $topic --bootstrap-server broker:9092 $security
fi

if [[ -n "$skip_delete_schema" ]]
then
    log "🔰 Do not delete subject/schema as --skip-delete-schema is set"
else
    set +e
    playground schema get --subject "$topic-key" > /dev/null 2>&1
    if [ $? -eq 0 ]
    then
        log "🔰 Delete subject $topic-key"
        playground schema delete --subject "$topic-key" --permanent
    fi
    
    playground schema get --subject "$topic-value" > /dev/null 2>&1
    if [ $? -eq 0 ]
    then
        log "🔰 Delete subject $topic-value"
        playground schema delete --subject "$topic-value" --permanent
    fi
fi