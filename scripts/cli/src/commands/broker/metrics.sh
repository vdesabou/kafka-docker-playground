broker="${args[--broker]}"
topic="${args[--topic]}"
json="${args[--json]}"
verbose="${args[--verbose]}"

if [[ -n "$broker" ]]
then
    get_broker_container_of_id "$broker" || exit 1
    targets="$broker $broker_id_container"
else
    targets=$(get_broker_containers)
    if [[ -z "$targets" ]]
    then
        logerror "❌ no broker container found, is an environment running? (playground status)"
        exit 1
    fi
fi

topic_suffix=""
[[ -n "$topic" ]] && topic_suffix=",topic=$topic"

# label|object name|attribute|format|warning
metrics_spec="Partitions|kafka.server:type=ReplicaManager,name=PartitionCount|Value|int|
Leaders|kafka.server:type=ReplicaManager,name=LeaderCount|Value|int|
Under-replicated partitions|kafka.server:type=ReplicaManager,name=UnderReplicatedPartitions|Value|int|gt0
Under min ISR partitions|kafka.server:type=ReplicaManager,name=UnderMinIsrPartitionCount|Value|int|gt0
Request handler idle (1m)|kafka.server:type=KafkaRequestHandlerPool,name=RequestHandlerAvgIdlePercent|OneMinuteRate|pct|lt30
Network processor idle|kafka.network:type=SocketServer,name=NetworkProcessorAvgIdlePercent|Value|pct|lt30
Request queue size|kafka.network:type=RequestChannel,name=RequestQueueSize|Value|int|
Produce p99|kafka.network:type=RequestMetrics,name=TotalTimeMs,request=Produce|99thPercentile|ms|
Fetch consumer p99|kafka.network:type=RequestMetrics,name=TotalTimeMs,request=FetchConsumer|99thPercentile|ms|
Fetch follower p99|kafka.network:type=RequestMetrics,name=TotalTimeMs,request=FetchFollower|99thPercentile|ms|
Messages in/s (1m)|kafka.server:type=BrokerTopicMetrics,name=MessagesInPerSec$topic_suffix|OneMinuteRate|rate|
Bytes in/s (1m)|kafka.server:type=BrokerTopicMetrics,name=BytesInPerSec$topic_suffix|OneMinuteRate|bytes|
Bytes out/s (1m)|kafka.server:type=BrokerTopicMetrics,name=BytesOutPerSec$topic_suffix|OneMinuteRate|bytes|
ISR shrinks (since start)|kafka.server:type=ReplicaManager,name=IsrShrinksPerSec|Count|int|
ISR expands (since start)|kafka.server:type=ReplicaManager,name=IsrExpandsPerSec|Count|int|
Failed produce requests (since start)|kafka.server:type=BrokerTopicMetrics,name=FailedProduceRequestsPerSec$topic_suffix|Count|int|
Failed fetch requests (since start)|kafka.server:type=BrokerTopicMetrics,name=FailedFetchRequestsPerSec$topic_suffix|Count|int|"

# the generated CLI indents the lines of this string
metrics_spec=$(echo "$metrics_spec" | sed 's/^[[:space:]]*//')

object_args=()
while IFS='|' read -r label object attribute format warning
do
    object_args+=(--object-name "$object")
done <<< "$metrics_spec"

# "<broker id>|<label>|<raw value>" for every metric of every running broker
values=""
ids=""
while read -r id container
do
    [[ -z "$id" ]] && continue
    if ! is_container_running "$container"
    then
        logwarn "⚠️ broker $id (container $container) is not running, skipped"
        continue
    fi
    port=$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$container" | grep -E "^KAFKA_JMX_PORT=" | cut -d= -f2 || true)
    if [[ -z "$port" ]]
    then
        logwarn "⚠️ JMX is not enabled on broker $id (no KAFKA_JMX_PORT), skipped"
        continue
    fi
    jmx_tool="kafka-jmx"
    if ! docker exec "$container" bash -c "command -v kafka-jmx" > /dev/null 2>&1
    then
        # before Kafka 3.5
        jmx_tool="kafka-run-class kafka.tools.JmxTool"
    fi
    [[ -n "$verbose" ]] && log "🐞 $jmx_tool --jmx-url service:jmx:rmi:///jndi/rmi://localhost:$port/jmxrmi ${object_args[*]} --one-time true --report-format tsv (in $container)"
    output=$(docker exec "$container" $jmx_tool --jmx-url "service:jmx:rmi:///jndi/rmi://localhost:$port/jmxrmi" "${object_args[@]}" --one-time true --report-format tsv 2>&1) || true
    if ! echo "$output" | grep -q -E "^kafka\."
    then
        logwarn "⚠️ could not read the JMX metrics of broker $id:"
        echo "$output" | grep -v -E "^[[:space:]]+at " | tail -3
        continue
    fi
    ids+="$id "
    while IFS='|' read -r label object attribute format warning
    do
        value=$(echo "$output" | awk -F'\t' -v key="$object:$attribute" '$1 == key { print $2 ; exit }')
        values+="$id|$label|$value"$'\n'
    done <<< "$metrics_spec"
done <<< "$targets"

if [[ -z "$ids" ]]
then
    logerror "❌ no broker metrics could be read"
    exit 1
fi

if [[ -n "$json" ]]
then
    echo -n "$values" | jq -R -s 'split("\n") | map(select(length > 0) | split("|"))
        | group_by(.[0]) | map({ broker: (.[0][0] | tonumber), metrics: (map({ (.[1]): (.[2] | tonumber? // null) }) | add) })'
    exit 0
fi

log "📈 Broker metrics$([[ -n "$topic" ]] && echo " (rates and failed requests of topic $topic)")"
{
    printf 'METRIC'
    for id in $ids
    do
        printf '\tBROKER %s' "$id"
    done
    printf '\n'
    while IFS='|' read -r label object attribute format warning
    do
        printf '%s' "$label"
        for id in $ids
        do
            value=$(echo -n "$values" | awk -F'|' -v id="$id" -v label="$label" '$1 == id && $2 == label { print $3 ; exit }')
            printf '\t%s' "$(echo "$value" | awk -v format="$format" -v warning="$warning" '
                $0 == "" { print "-" ; exit }
                {
                    v = $0 + 0
                    if (format == "pct") out = sprintf("%.0f%%", v * 100)
                    else if (format == "ms") out = sprintf("%.0f ms", v)
                    else if (format == "rate") out = sprintf("%.1f", v)
                    else if (format == "bytes") {
                        if (v >= 1048576) out = sprintf("%.1f MB", v / 1048576)
                        else if (v >= 1024) out = sprintf("%.1f KB", v / 1024)
                        else out = sprintf("%.0f B", v)
                    }
                    else out = sprintf("%.0f", v)
                    if ((warning == "gt0" && v > 0) || (warning == "lt30" && v < 0.3)) out = out " ⚠️"
                    print out
                }')"
        done
        printf '\n'
    done <<< "$metrics_spec"
} | column -t -s $'\t'
log "🎓 idle below 30% means the broker threads are saturated (num.io.threads, num.network.threads)"
log "   fetch p99 includes the time a fetch waits for data (fetch.max.wait.ms, replica.fetch.wait.max.ms: 500 ms by default)"
