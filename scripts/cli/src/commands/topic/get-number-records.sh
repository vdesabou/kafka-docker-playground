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

# ------------------------------------------------------
# PREPARATION: Cache configs and Start Containers
# ------------------------------------------------------

# Cache broker tag and container (non-ccloud) once
cached_tag=""
cached_broker_container=""
if [[ "$environment" != "ccloud" ]]; then
    cached_tag=$(docker ps --format '{{.Image}}' | grep -E 'confluentinc/cp-.*-connect-.*:' | awk -F':' '{print $2}')
    if [ -z "$cached_tag" ]; then
        logerror "Could not find current CP version from docker ps"
        exit 1
    fi
    get_broker_container
    cached_broker_container="$broker_container"
fi

# Optimization: Prepare CCloud Kcat container once
kcat_container_name="kcat_worker_$$"
if [[ "$environment" == "ccloud" ]]; then
    if [ ! -f $root_folder/.ccloud/librdkafka.delta ]
    then
        logerror "❌ $root_folder/.ccloud/librdkafka.delta has not been generated"
        exit 1
    fi
    
    tr -d '"' < $root_folder/.ccloud/librdkafka.delta > $root_folder/.ccloud/librdkafka_no_quotes_tmp.delta
    grep -v "basic.auth.user.info" $root_folder/.ccloud/librdkafka_no_quotes_tmp.delta > $root_folder/.ccloud/librdkafka_no_quotes.delta

    # FIXED: Added --entrypoint to override the default 'kcat' entrypoint
    docker run -d --rm --name "$kcat_container_name" --network=host \
        -v $root_folder/.ccloud/librdkafka_no_quotes.delta:/tmp/configuration/ccloud.properties \
        --entrypoint tail \
        confluentinc/cp-kcat:latest -f /dev/null > /dev/null 2>&1

    trap "docker stop $kcat_container_name > /dev/null 2>&1" EXIT
fi

# ------------------------------------------------------
# MAIN LOOP
# ------------------------------------------------------

for topic in "${items[@]}"
do
    log "💯 Get number of records in topic $topic"
    set +e
    existing_topics=$(playground get-topic-list)
    if ! echo "$existing_topics" | grep -qFw "$topic"
    then
        logwarn "topic $topic does not exist !"
        continue
    fi
    set +e
    if [[ "$environment" == "ccloud" ]]
    then
        # --- OFFSET MODE (Default) ---
        # Note: We must explicitly call 'kcat' in the exec command now
        offsets=$(docker exec "$kcat_container_name" kcat \
            -F /tmp/configuration/ccloud.properties \
            -C -t "$topic" \
            -o -1 -e -q \
            -f '%o\n' 2>/dev/null)
        
        if [ -z "$offsets" ]; then
            echo "0"
        else
            # Sum offsets + 1 (0-based index)
            echo "$offsets" | awk '{s+=$1+1} END {print s}'
        fi

    else
        # --- ON-PREM / LOCAL LOGIC ---
        tag="$cached_tag"
        broker_container="$cached_broker_container"
        
        if ! version_gt "$tag" "6.9.9" && [ -n "$security" ]
        then
            get_security_broker "--consumer.config"
            set +e
            docker exec "$container" timeout 15 kafka-console-consumer --bootstrap-server "$broker_container":9092 --topic "$topic" $security --from-beginning --timeout-ms 15000 2>/dev/null | wc -l | tr -d ' '
            set -e
        else
            class_name="kafka.tools.GetOffsetShell"
            if version_gt "$tag" "7.6.9"
            then
                class_name="org.apache.kafka.tools.GetOffsetShell"
            fi
            parameter_for_list_broker="--bootstrap-server"
            if ! version_gt "$tag" "5.3.99"
            then
                parameter_for_list_broker="--broker-list"
            fi
            
            docker exec "$broker_container" kafka-run-class "$class_name" "$parameter_for_list_broker" "$broker_container":9092 $security --topic "$topic" --time -1 | grep -v "No configuration found" | awk -F ":" '{sum += $3} END {print sum}'
        fi
    fi
done