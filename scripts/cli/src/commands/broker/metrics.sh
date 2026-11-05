broker="${args[--broker]}"
topic="${args[--topic]}"
json="${args[--json]}"
controller_only="${args[--controller]}"
verbose="${args[--verbose]}"

topic_suffix=""
[[ -n "$topic" ]] && topic_suffix=",topic=$topic"

# label|object name|attribute|format|warning (see jmx_digest_read)
broker_spec="Partitions|kafka.server:type=ReplicaManager,name=PartitionCount|Value|int|
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

# KRaft: MBeans of the controllers; ZooKeeper: of the broker that is the active controller
controller_spec="Active controller|kafka.controller:type=KafkaController,name=ActiveControllerCount|Value|bool|
Offline partitions|kafka.controller:type=KafkaController,name=OfflinePartitionsCount|Value|int|gt0
Partitions (cluster)|kafka.controller:type=KafkaController,name=GlobalPartitionCount|Value|int|
Topics (cluster)|kafka.controller:type=KafkaController,name=GlobalTopicCount|Value|int|
Preferred replica imbalance|kafka.controller:type=KafkaController,name=PreferredReplicaImbalanceCount|Value|int|gt0
Last applied record lag|kafka.controller:type=KafkaController,name=LastAppliedRecordLagMs|Value|ms|
Unclean leader elections (since start)|kafka.controller:type=ControllerStats,name=UncleanLeaderElectionsPerSec|Count|int|gt0"

# the generated CLI indents the lines of these strings
broker_spec=$(echo "$broker_spec" | sed 's/^[[:space:]]*//')
controller_spec=$(echo "$controller_spec" | sed 's/^[[:space:]]*//')

# the controller section: KRaft controllers, or the brokers with ZooKeeper
function display_controller_metrics () {
    local controller_targets header="CONTROLLER"
    controller_targets=$(get_controller_containers)
    if [[ -z "$controller_targets" ]]
    then
        controller_targets=$(get_broker_containers)
        header="BROKER"
    fi
    jmx_digest_collect "$controller_spec" "$controller_targets"
    if [[ -z "$JMX_DIGEST_IDS" ]]
    then
        logerror "❌ no controller metrics could be read"
        return 1
    fi
    if [[ -n "$json" ]]
    then
        jmx_digest_json "$(echo "$header" | tr '[:upper:]' '[:lower:]')"
        return 0
    fi
    log "🗳️ Controller metrics ($([[ "$header" == "CONTROLLER" ]] && echo "KRaft controllers" || echo "ZooKeeper mode: the active controller is a broker"))"
    jmx_digest_table "$header" "$controller_spec"
    local active=0 id
    for id in $JMX_DIGEST_IDS
    do
        case "$(jmx_digest_value "$id" "Active controller")" in
            1|1.0|true) active=$((active + 1)) ;;
        esac
    done
    if [[ "$active" != "1" ]]
    then
        logwarn "⚠️ $active active controller(s), there must be exactly 1"
    fi
}

if [[ -n "$controller_only" ]]
then
    display_controller_metrics
    exit $?
fi

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

[[ -n "$verbose" ]] && log "🐞 reading the MBeans of $(echo "$targets" | awk '{print $2}' | paste -sd, -) with kafka-jmx"
jmx_digest_collect "$broker_spec" "$targets"
if [[ -z "$JMX_DIGEST_IDS" ]]
then
    logerror "❌ no broker metrics could be read"
    exit 1
fi

if [[ -n "$json" ]]
then
    jmx_digest_json broker
    exit 0
fi

log "📈 Broker metrics$([[ -n "$topic" ]] && echo " (rates and failed requests of topic $topic)")"
if [[ -n "$topic" ]] && ! echo -n "$JMX_DIGEST_VALUES" | awk -F'|' '$2 == "Messages in/s (1m)" && $3 != ""' | grep -q .
then
    logwarn "⚠️ no metric for topic $topic: it does not exist, or no broker received or served records of it since it started"
fi
jmx_digest_table "BROKER" "$broker_spec"
log "🎓 idle below 30% means the broker threads are saturated (num.io.threads, num.network.threads)"
log "   fetch p99 includes the time a fetch waits for data (fetch.max.wait.ms, replica.fetch.wait.max.ms: 500 ms by default)"

# the controller section, unless one broker was asked for
if [[ -z "$broker" ]]
then
    echo ""
    display_controller_metrics || true
fi
