topic="${args[--topic]}"

get_security_broker "--command-config"

if [[ ! -n "$topic" ]]
then
    log "✨ --topic flag was not provided, applying command to all topics"
    topic=$(playground get-topic-list --skip-connect-internal-topics)
    if [ "$topic" == "" ]
    then
        logerror "❌ No topic found !"
        exit 1
    fi
fi

get_environment_used

items=($topic)
for topic in ${items[@]}
do
    log "💯 Get number of records in topic $topic"
    set +e
    playground topic describe --topic $topic > /tmp/result.log 2>/tmp/result.log
    grep "does not exist" /tmp/result.log > /dev/null 2>&1
    if [ $? == 0 ]
    then
        logwarn "topic $topic does not exist !"
        continue
    fi
    set +e
    if [[ "$environment" == "ccloud" ]]
    then
        get_sr_url_and_security

        value_type=""
        version=$(curl $sr_security -s "${sr_url}/subjects/${topic}-value/versions/1" | jq -r .version)
        if [ "$version" != "null" ]
        then
        schema_type=$(curl $sr_security -s "${sr_url}/subjects/${topic}-value/versions/1"  | jq -r .schemaType)
        case "${schema_type}" in
            JSON)
            value_type="json-schema"
            ;;
            PROTOBUF)
            value_type="protobuf"
            ;;
            null)
            value_type="avro"
            ;;
        esac
        fi

        if [ ! -f $root_folder/.ccloud/librdkafka.delta ]
        then
            logerror "ERROR: $root_folder/.ccloud/librdkafka.delta has not been generated"
            exit 1
        fi
        tr -d '"' < $root_folder/.ccloud/librdkafka.delta > $root_folder/.ccloud/librdkafka_no_quotes_tmp.delta
        sr_url=$(grep "schema.registry.url=" $root_folder/.ccloud/librdkafka_no_quotes_tmp.delta | cut -d "=" -f2)
        sr_url_hostname=$(echo $sr_url | cut -d "/" -f 3)
        sr_auth=$(grep "basic.auth.user.info=" $root_folder/.ccloud/librdkafka_no_quotes_tmp.delta | cut -d "=" -f2)
        sr_username=$(echo $sr_auth | cut -d ":" -f 1)
        sr_password=$(echo $sr_auth | cut -d ":" -f 2)
        # sr_password_url_encoded=$(urlencode $sr_password)
        grep -v "basic.auth.user.info" $root_folder/.ccloud/librdkafka_no_quotes_tmp.delta > $root_folder/.ccloud/librdkafka_no_quotes.delta

        case "${value_type}" in
        avro)
        docker run -i --network=host \
                -v $root_folder/.ccloud/librdkafka_no_quotes.delta:/tmp/configuration/ccloud.properties \
            confluentinc/cp-kcat:latest kcat \
                -F /tmp/configuration/ccloud.properties \
                -C -t $topic \
                -s value=avro \
                -r https://$sr_username:$sr_password@$sr_url_hostname \
                -e -q > /tmp/result.log 2>/dev/null
            ;;
        *)
        docker run -i --network=host \
                -v $root_folder/.ccloud/librdkafka_no_quotes.delta:/tmp/configuration/ccloud.properties \
            confluentinc/cp-kcat:latest kcat \
                -F /tmp/configuration/ccloud.properties \
                -C -t $topic \
                -e -q > /tmp/result.log 2>/dev/null
        ;;
        esac
        wc -l /tmp/result.log | awk '{print $1}'
    else
        tag=$(docker ps --format '{{.Image}}' | egrep 'confluentinc/cp-.*-connect-base:' | awk -F':' '{print $2}')
        if [ $? != 0 ] || [ "$tag" == "" ]
        then
            logerror "Could not find current CP version from docker ps"
            exit 1
        fi
        if ! version_gt $tag "6.9.9" && [ "$security" != "" ]
        then
            # GetOffsetShell does not support security before 7.x
            get_security_broker "--consumer.config"
            
            set +e
            docker exec $container timeout 15 kafka-console-consumer --bootstrap-server broker:9092 --topic $topic $security --from-beginning --timeout-ms 15000 2>/dev/null | wc -l | tr -d ' '
            set -e
        else
            class_name="kafka.tools.GetOffsetShell"
            if version_gt $tag "7.6.9"
            then
                class_name="org.apache.kafka.tools.GetOffsetShell"
            fi
            docker exec $container kafka-run-class $class_name --broker-list broker:9092 $security --topic $topic --time -1 | awk -F ":" '{sum += $3} END {print sum}'
        fi
    fi
done
