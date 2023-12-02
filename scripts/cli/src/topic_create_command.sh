topic="${args[--topic]}"
nb_partitions="${args[--nb-partitions]}"

get_security_broker "--command-config"
get_environment_used

if [ "$nb_partitions" == "" ]
then
    nb_partitions=1
fi

if [ "$environment" == "error" ]
then
  logerror "File containing restart command /tmp/playground-command does not exist!"
  exit 1 
fi

playground topic get-number-records --topic $topic > /tmp/result.log 2>/tmp/result.log
set +e
grep "does not exist" /tmp/result.log > /dev/null 2>&1
if [ $? == 0 ]
then
    set -e
    log "🆕 Creating topic $topic"
    if [[ "$environment" == "environment" ]]
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

        docker run --rm -v /tmp/delta_configs/ak-tools-ccloud.delta:/tmp/configuration/ccloud.properties ${CP_CONNECT_IMAGE}:${CONNECT_TAG} kafka-topics --create --topic $topic --bootstrap-server $BOOTSTRAP_SERVERS --command-config /tmp/configuration/ccloud.properties --partitions $nb_partitions ${other_args[*]}
    else
        docker exec $container kafka-topics --create --topic $topic --bootstrap-server broker:9092 --partitions $nb_partitions $security ${other_args[*]}
    fi
else
    logerror "❌ topic $topic already exist !"
    exit 1
fi