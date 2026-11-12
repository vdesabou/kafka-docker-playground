topic="${args[--topic]}"
isolation_level="${args[--isolation-level]}"

get_security_broker "--command-config"

if [[ ! -n "$topic" ]]
then
    log "✨ --topic flag was not provided, applying command to all topics"
    topic=$(playground get-topic-list --skip-internal-topics)
    if [ "$topic" == "" ]
    then
        logerror "❌ No topic found !"
        exit 1
    fi
fi

get_environment_used

items=($topic)

# sum of the offsets printed by GetOffsetShell (topic:partition:offset lines) for the command "$@", in $offsets_sum.
# Fails when the tool fails (broker down, authentication): before, the sum of nothing was 0, and 'wait-for-records' or
# 'consume --min-expected-messages' waited until their timeout for an empty topic that was in fact unreachable
offsets_err_file=$(mktemp -t pg-offsets-XXXXXXXXXX)
function sum_offsets() {
    local out rc
    out=$("$@" 2> "$offsets_err_file")
    rc=$?
    if [ $rc -ne 0 ]
    then
        logerror "❌ could not get the offsets of topic $topic (exit code $rc)"
        grep -v -E "^$|SLF4J|No configuration found" "$offsets_err_file" | tail -5 >&2
        return 1
    fi
    offsets_sum=$(echo "$out" | grep -E ':[0-9]+:-?[0-9]+$' | awk -F ":" '{sum += $NF} END {print sum+0}')
}
failed=0

# ------------------------------------------------------
# PREPARATION: Cache configs and Start Containers
# ------------------------------------------------------

# Cache broker tag and container (non-ccloud) once
cached_tag=""
cached_broker_container=""
if [[ "$environment" != "ccloud" ]] && [[ "$environment" != cfk* ]]; then
    cached_tag=$(get_running_cp_tag)
    if [ -z "$cached_tag" ]; then
        logerror "Could not find current CP version from docker ps"
        exit 1
    fi
    get_broker_container
    cached_broker_container="$broker_container"
fi

# Cache cfk tag once
cached_cfk_tag=""
if [[ "$environment" == cfk* ]]; then
    if [ -n "$CP_CONNECT_TAG" ]; then
        cached_cfk_tag="$CP_CONNECT_TAG"
    elif [ -n "$TAG" ]; then
        cached_cfk_tag="$TAG"
    else
        cached_cfk_tag=$(kubectl -n confluent get pod "$container" -o jsonpath='{.spec.containers[?(@.name=="connect")].image}' 2>/dev/null | awk -F':' '{print $NF}')
    fi

    if [ -z "$cached_cfk_tag" ]; then
        logwarn "Could not determine CFK tag version, defaulting to latest GetOffsetShell class/flags"
        cached_cfk_tag="99.99.99"
    fi
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
    # edenhill/kcat:1.7.1 (librdkafka 1.8.2): confluentinc/cp-kcat:latest is kcat 1.7.0 (librdkafka 1.7.0), which some
    # Confluent Cloud clusters reject with "Broker: API version not supported" (#10406). amd64 only
    if ! kcat_error=$(docker run -d --rm --platform linux/amd64 --name "$kcat_container_name" --network=host \
        -v $root_folder/.ccloud/librdkafka_no_quotes.delta:/tmp/configuration/ccloud.properties \
        --entrypoint tail \
        edenhill/kcat:1.7.1 -f /dev/null 2>&1)
    then
        # without it, every count was 0 and 'consume --min-expected-messages' waited until its timeout
        logerror "❌ could not start the kcat container that counts the records: $kcat_error"
        exit 1
    fi

    kcat_err_file=$(mktemp)
    trap "docker stop $kcat_container_name > /dev/null 2>&1; rm -f $offsets_err_file $kcat_err_file" EXIT
fi

# read_committed: the offsets include the aborted records and the transaction markers, the records are counted with a
# read_committed console consumer instead (ccloud: kcat, below)
committed_consumer_args=()
if [ "$isolation_level" == "read_committed" ] && [[ "$environment" != "ccloud" ]]
then
    committed_tag="$cached_tag"
    if [[ "$environment" == cfk* ]]
    then
        committed_tag="$cached_cfk_tag"
    else
        container_tag=$(docker inspect -f '{{.Config.Image}}' "$container" 2>/dev/null | awk -F ':' '{print $NF}')
        if [[ "$container_tag" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]
        then
            committed_tag="$container_tag"
        fi
    fi
    if version_gt "$committed_tag" "8.1.99"
    then
        get_security_broker "--command-config"
        committed_property="--formatter-property"
    else
        get_security_broker "--consumer.config"
        committed_property="--property"
    fi
    committed_consumer_args=(kafka-console-consumer --bootstrap-server "$bootstrap_server" $security --from-beginning --isolation-level read_committed --timeout-ms 10000 "$committed_property" print.value=false "$committed_property" print.offset=true)
fi

# listed once: the loop used to list the topics again for each topic
existing_topics=$(playground get-topic-list)

# ------------------------------------------------------
# MAIN LOOP
# ------------------------------------------------------

for topic in "${items[@]}"
do
    log "💯 Get number of records in topic $topic"
    set +e
    if ! echo "$existing_topics" | grep -qFx "$topic"
    then
        logwarn "topic $topic does not exist !"
        continue
    fi
    set +e
    if [[ "$environment" == "ccloud" ]]
    then
        # Count actual records rather than summing offsets: offsets overestimate the number of
        # readable records with transaction markers or compaction, which makes
        # 'playground topic consume' wait forever for records that never come
        # isolation.level is always passed: the default of librdkafka is read_committed, not read_uncommitted
        kcat_isolation_level="read_uncommitted"
        if [ "$isolation_level" == "read_committed" ]
        then
            kcat_isolation_level="read_committed"
        fi
        count=$(docker exec "$kcat_container_name" kcat \
            -F /tmp/configuration/ccloud.properties \
            -X isolation.level=$kcat_isolation_level \
            -C -t "$topic" \
            -o beginning -e -q \
            -f '%o\n' 2>"$kcat_err_file" | wc -l | tr -d ' ')

        # a kcat error must not become a count of 0: 'consume --min-expected-messages' then waited until its timeout
        # with "contains 0 messages" (kcat 1.7.0 got "Broker: API version not supported" from a Confluent Cloud
        # cluster, #10406). "Unknown topic or partition" is transient right after the topic creation: it stays a count
        kcat_error=$(grep "% ERROR" "$kcat_err_file" | grep -v "Unknown topic or partition" | head -1)
        if [ -n "$kcat_error" ]
        then
            logerror "❌ kcat could not count the records of topic $topic: $kcat_error"
            echo "kcat error: $kcat_error"
            exit 1
        fi
        echo "${count:-0}"

    elif [ ${#committed_consumer_args[@]} -ne 0 ]
    then
        # one "Offset:N" line per committed record (print.value=false: a value with new lines counts once)
        if [[ "$environment" == cfk* ]]
        then
            kubectl -n confluent exec "$container" -c connect -- "${committed_consumer_args[@]}" --topic "$topic" 2>/dev/null | grep -c "Offset:"
        else
            docker exec "$container" "${committed_consumer_args[@]}" --topic "$topic" 2>/dev/null | grep -c "Offset:"
        fi
    elif [[ "$environment" == cfk* ]]
    then
        cfk_class_name="kafka.tools.GetOffsetShell"
        if version_gt "$cached_cfk_tag" "7.6.99"
        then
            cfk_class_name="org.apache.kafka.tools.GetOffsetShell"
        fi

        cfk_parameter_for_list_broker="--bootstrap-server"
        if ! version_gt "$cached_cfk_tag" "5.3.99"
        then
            cfk_parameter_for_list_broker="--broker-list"
        fi

        # records = latest - earliest offsets: the earliest is not 0 any more once retention or a deletion removed records
        sum_offsets kubectl -n confluent exec "$container" -c connect -- bash -c "kafka-run-class $cfk_class_name $cfk_parameter_for_list_broker $bootstrap_server $security --topic $topic --time -1" || { failed=1; continue; }
        latest=$offsets_sum
        sum_offsets kubectl -n confluent exec "$container" -c connect -- bash -c "kafka-run-class $cfk_class_name $cfk_parameter_for_list_broker $bootstrap_server $security --topic $topic --time -2" || { failed=1; continue; }
        earliest=$offsets_sum
        echo $((latest - earliest))
    else
        # --- ON-PREM / LOCAL LOGIC ---
        tag="$cached_tag"
        broker_container="$cached_broker_container"
        
        if ! version_gt "$tag" "6.9.9" && [ -n "$security" ]
        then
            get_security_broker "--consumer.config"
            set +e
            docker exec "$container" timeout 15 kafka-console-consumer --bootstrap-server "$bootstrap_server" --topic "$topic" $security --from-beginning --timeout-ms 15000 2>/dev/null | wc -l | tr -d ' '
            set -e
        else
            # GetOffsetShell runs in $container (the broker, or the kerberos client): its version, not the one of
            # connect (--connect-tag), decides the class name
            container_tag=$(docker inspect -f '{{.Config.Image}}' "$container" 2>/dev/null | awk -F ':' '{print $NF}')
            if [[ "$container_tag" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]
            then
                tag="$container_tag"
            fi
            class_name="kafka.tools.GetOffsetShell"
            if version_gt "$tag" "7.6.99"
            then
                class_name="org.apache.kafka.tools.GetOffsetShell"
            fi
            parameter_for_list_broker="--bootstrap-server"
            if ! version_gt "$tag" "5.3.99"
            then
                parameter_for_list_broker="--broker-list"
            fi
            
            # container and bootstrap come from get_security_broker: the broker container and
            # broker:9092 by default, but the kerberized client container and the broker FQDN
            # with kerberos, whose client config needs a ticket and the real principal host
            # records = latest - earliest offsets: the earliest is not 0 any more once retention or a deletion removed records
            sum_offsets docker exec "$container" kafka-run-class "$class_name" "$parameter_for_list_broker" "$bootstrap_server" $security --topic "$topic" --time -1 || { failed=1; continue; }
            latest=$offsets_sum
            sum_offsets docker exec "$container" kafka-run-class "$class_name" "$parameter_for_list_broker" "$bootstrap_server" $security --topic "$topic" --time -2 || { failed=1; continue; }
            earliest=$offsets_sum
            echo $((latest - earliest))
        fi
    fi
done
rm -f "$offsets_err_file"
exit $failed
