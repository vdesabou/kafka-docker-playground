#!/bin/bash
# Helpers shared by the CFK day-2 examples (sourced, not run: run-tests.sh only runs the *.sh files of the folder).
#
# Each example changes a running cluster deployed by Confluent for Kubernetes (upgrade, operator upgrade...) while a
# workload runs through the change, and checks at the end that it survived:
#  - kafka-verifiable-producer in its own pod (day2-client: the pods of CFK are rolled by the changes): a numbered
#    sequence, acks=all, no retries, one json line per ack and per error in /tmp/day2-<name>.log
#  - the FileStream sink connector on the same topic: at the end, its consumer group has no lag

DAY2_TOPIC="day2"
DAY2_CLIENT_POD="day2-client"
DAY2_BOOTSTRAP="kafka:9071"
# client properties file in the client pod, for the checks once the listeners are secured (cfk-enable-sasl-ssl.sh), and
# the bootstrap servers they use
DAY2_CLIENT_CONFIG=""
DAY2_CHECK_BOOTSTRAP="$DAY2_BOOTSTRAP"

# the examples start their own cfk environment: run them from the cfk CI job only (k3d, kubectl, helm), like the cfk.sh
# deep dive lab
function day2_require_cfk () {
    if [ "${PLAYGROUND_ENVIRONMENT:-plaintext}" != "cfk" ]
    then
        logwarn "the CFK day-2 examples need the cfk environment (k3d, kubectl, helm), skipping with ${PLAYGROUND_ENVIRONMENT:-plaintext}"
        exit 111
    fi
    unset ENABLE_CONTROL_CENTER ENABLE_KSQLDB ENABLE_RESTPROXY ENABLE_CONNECT_NODES
}

# the cfk environment with 3 KRaft controllers (3 ZooKeeper nodes with CP 7.x) and 3 brokers (a production-like quorum:
# one controller can roll without stalling the brokers), Confluent Platform $1 (default: the version of the run). The image tags exported
# by utils.sh for the version of the run (CP_KAFKA_TAG...) are only set when empty: unset them for another version
function day2_start_cfk () {
    (
        if [ -n "$1" ]
        then
            unset CP_KAFKA_TAG CP_CONNECT_TAG CP_SCHEMA_REGISTRY_TAG CP_CONTROL_CENTER_TAG CP_KSQL_TAG CP_KSQL_CLI_TAG CP_REST_PROXY_TAG CP_ZOOKEEPER_TAG
            # and the KRaft / ZooKeeper mode decided for the version of the run: CP 7.x starts in ZooKeeper mode
            unset ENABLE_KRAFT ENABLE_ZOOKEEPER KRAFT_MODE_LOGGED
            export TAG="$1" TAG_BASE="$1"
        fi
        export ENABLE_CONTROLLER_NODES=1
        # DAY2_SINGLE_BROKER=1: one broker (cfk-scale-out-brokers.sh)
        if [ -z "$DAY2_SINGLE_BROKER" ]
        then
            export ENABLE_KAFKA_NODES=1
        else
            unset ENABLE_KAFKA_NODES
        fi
        playground start-environment --environment cfk
    )
}

function day2_client () {
    kubectl -n confluent exec "$DAY2_CLIENT_POD" -- sh -c "$1"
}

# the client pod (the cp-server image of version $1, for kafka-verifiable-producer), the topic (replication factor 3,
# min.insync.replicas 2), the producer and the sink connector
function day2_start_workload () {
    local image="confluentinc/cp-server:${1:-$TAG}"
    log "🧑‍💻 client pod $DAY2_CLIENT_POD ($image), not managed by CFK: the producer survives the rolls"
    kubectl -n confluent delete pod "$DAY2_CLIENT_POD" --ignore-not-found --wait=true > /dev/null
    run_logged kubectl -n confluent run "$DAY2_CLIENT_POD" --image "$image" --restart Never --command -- sleep infinity > /dev/null
    run_logged kubectl -n confluent wait --for=condition=Ready "pod/$DAY2_CLIENT_POD" --timeout=300s > /dev/null
    # DAY2_SINGLE_BROKER=1: replication factor 1 (one broker)
    if [ -z "$DAY2_SINGLE_BROKER" ]
    then
        playground topic create --topic "$DAY2_TOPIC" --nb-partitions 3 --if-not-exists --replication-factor 3 --config min.insync.replicas=2
    else
        playground topic create --topic "$DAY2_TOPIC" --nb-partitions 3 --if-not-exists --replication-factor 1
    fi
    day2_start_producer
    playground connector create-or-update --connector day2-sink --wait << EOF
{
     "tasks.max": "1",
     "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
     "topics": "$DAY2_TOPIC",
     "file": "/tmp/day2-sink.txt",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.storage.StringConverter"
}
EOF
    sleep 10
    day2_report_workload "workload started"
}

# (re)starts a producer in the client pod, appending to its log: $1 name, $2 topic, $3 bootstrap servers, $4 client
# properties file in the client pod
function day2_start_producer () {
    local name="${1:-producer}" topic="${2:-$DAY2_TOPIC}" bootstrap="${3:-$DAY2_BOOTSTRAP}" config="$4"
    local cmd="nohup kafka-verifiable-producer --bootstrap-server $bootstrap --topic $topic --throughput 20 --max-messages -1 --acks -1${config:+ --producer.config $config} >> /tmp/day2-$name.log 2>&1 &"
    log "📤 $name: kafka-verifiable-producer in pod $DAY2_CLIENT_POD, topic $topic, 20 records/s, acks=all, no retries, bootstrap $bootstrap${config:+, $config}"
    log_command kubectl -n confluent exec "$DAY2_CLIENT_POD" -- sh -c "$cmd"
    kubectl -n confluent exec "$DAY2_CLIENT_POD" -- sh -c "$cmd"
}

# stops a producer ($1 name: the java process writing to /tmp/day2-<name>.log), all of them without it
function day2_stop_producers () {
    if [ -n "$1" ]
    then
        kubectl -n confluent exec "$DAY2_CLIENT_POD" -- env LOG="/tmp/day2-$1.log" sh -c 'for p in $(pgrep -f VerifiableProducer); do if ls -l /proc/$p/fd 2> /dev/null | grep -q "$LOG"; then kill $p; fi; done; sleep 3' || true
    else
        day2_client 'pkill -f VerifiableProducer; sleep 3' || true
    fi
}

# number of records of a topic ($1): playground topic get-number-records, or through the client pod with
# DAY2_CLIENT_CONFIG once the listener of the playground commands is secured
function day2_topic_records () {
    if [ -n "$DAY2_CLIENT_CONFIG" ]
    then
        log_command kubectl -n confluent exec "$DAY2_CLIENT_POD" -- kafka-get-offsets --bootstrap-server "$DAY2_CHECK_BOOTSTRAP" --command-config "$DAY2_CLIENT_CONFIG" --topic "$1" >&2
        day2_client "kafka-get-offsets --bootstrap-server $DAY2_CHECK_BOOTSTRAP --command-config $DAY2_CLIENT_CONFIG --topic $1 2> /dev/null" | awk -F ':' '{ n += $3 } END { print n + 0 }'
    else
        playground topic get-number-records -t "$1" 2> /dev/null | tail -1
    fi
}

# number of lines of a type in the log of a producer: $1 type (producer_send_success, producer_send_error), $2 name
function day2_count () {
    local count
    count=$(day2_client "grep -c '\"$1\"' /tmp/day2-${2:-producer}.log || true" 2> /dev/null)
    echo "${count:-0}"
}

function day2_send_errors () {
    day2_count producer_send_error "${1:-producer}"
}

function day2_now () {
    echo $(( $(date +%s) * 1000 ))
}

# longest time in seconds without an ack since epoch millis $1 ($2 name)
function day2_longest_pause () {
    day2_client "grep '\"producer_send_success\"' /tmp/day2-${2:-producer}.log" 2> /dev/null \
        | jq -r --argjson since "$1" 'select(.timestamp >= $since) | .timestamp' \
        | awk 'NR > 1 { d = $1 - prev; if (d > max) max = d } { prev = $1 } END { printf "%.1f\n", max / 1000 }'
}

# send errors of a producer since epoch millis $1 ($2 name), per minute and exception: when each step hurt
function day2_error_timeline () {
    day2_client "grep '\"producer_send_error\"' /tmp/day2-${2:-producer}.log" 2> /dev/null \
        | jq -r --argjson since "$1" 'select(.timestamp >= $since) | ((.timestamp / 1000 | localtime | strftime("%H:%M")) + " " + (.exception | sub("^class "; "") | sub("^.*[.]"; "")))' \
        | sort | uniq -c | awk '{ printf "   %s %5d %s\n", $2, $1, $3 }'
}

# acked records and send errors of a producer so far ($2 name), and its last error
function day2_report_workload () {
    local name="${2:-producer}" acked errors last_error
    acked=$(day2_count producer_send_success "$name")
    errors=$(day2_count producer_send_error "$name")
    log "📊 ${1:-workload} ($name): $acked records acked, $errors send errors"
    if [ "$errors" != "0" ]
    then
        last_error=$(day2_client "grep '\"producer_send_error\"' /tmp/day2-$name.log | tail -1" | jq -r '.exception + ": " + .message' 2> /dev/null | cut -c1-200)
        logwarn "   last send error: $last_error"
    fi
}

# when each pod of a statefulset ($1: kafka, kraftcontroller, connect...) started since epoch millis $2, and the spread
# between the first and the last in DAY2_RESTART_SPREAD (seconds)
function day2_pod_restarts () {
    local sts="$1" since_s=$(( $2 / 1000 )) pod start t first="" last=""
    while read -r pod start
    do
        t=$(date -u -d "$start" +%s 2> /dev/null || date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$start" +%s)
        if [ "$t" -ge "$since_s" ]
        then
            log "   $pod restarted at $(date -d "@$t" '+%H:%M:%S' 2> /dev/null || date -r "$t" '+%H:%M:%S')"
            if [ -z "$first" ] || [ "$t" -lt "$first" ]
            then
                first=$t
            fi
            if [ -z "$last" ] || [ "$t" -gt "$last" ]
            then
                last=$t
            fi
        else
            log "   $pod not restarted"
        fi
    done < <(kubectl -n confluent get pods -l "app=$sts" -o jsonpath='{range .items[*]}{.metadata.name} {.status.startTime}{"\n"}{end}' | sort)
    DAY2_RESTART_SPREAD=$(( ${last:-0} - ${first:-0} ))
}

# every stop of a CFK pod since epoch millis $1 (the Killing events of kubernetes, kept one hour): one line per pod with
# the times, the total in DAY2_POD_STOPS
function day2_pod_stops () {
    local since_s=$(( $1 / 1000 )) lines
    log "🛑 pod stops since $(date -d "@$since_s" +%H:%M:%S 2> /dev/null || date -r "$since_s" +%H:%M:%S) (Killing events):"
    log_command kubectl -n confluent get events --field-selector reason=Killing --sort-by=.lastTimestamp
    lines=$(kubectl -n confluent get events --field-selector reason=Killing -o json | jq -r --argjson since "$since_s" '
        [.items[]
         | select(.involvedObject.name | test("^(kraftcontroller|zookeeper|kafka|connect|schemaregistry|ksqldb|kafkarestproxy|controlcenter)-[0-9]+$"))
         | {pod: .involvedObject.name, t: ((.lastTimestamp // .eventTime // .metadata.creationTimestamp) | sub("\\.[0-9]+"; "") | fromdateiso8601)}
         | select(.t >= $since)]
        | group_by(.pod)[]
        | "\(.[0].pod) \(length) \([.[].t | strftime("%H:%M:%S")] | sort | join(" "))"')
    DAY2_POD_STOPS=0
    while read -r pod count times
    do
        [ -z "$pod" ] && continue
        log "   $pod stopped $count time(s): $times"
        DAY2_POD_STOPS=$(( DAY2_POD_STOPS + count ))
    done <<< "$lines"
}

function day2_broker_versions () {
    kubectl -n confluent get pods -l app=kafka -o jsonpath='{range .items[*]}{.metadata.name}{": "}{.spec.containers[0].image}{"\n"}{end}' | sed 's/^/   /'
}

# kafka-features in a broker pod (the internal listener of the cfk environment is PLAINTEXT)
function day2_features () {
    log_command kubectl -n confluent exec kafka-0 -c kafka -- kafka-features --bootstrap-server "$DAY2_BOOTSTRAP" "$@"
    kubectl -n confluent exec kafka-0 -c kafka -- kafka-features --bootstrap-server "$DAY2_BOOTSTRAP" "$@"
}

# stops the producers and checks that every acked record is in the topic and that the sink consumed every record.
# Fails the example otherwise
function day2_check_no_loss () {
    local acked records lag i
    day2_stop_producers
    day2_report_workload "workload stopped"
    acked=$(day2_count producer_send_success producer)
    records=$(day2_topic_records "$DAY2_TOPIC")
    log_command --polled kubectl -n confluent exec "$DAY2_CLIENT_POD" -- kafka-consumer-groups --bootstrap-server "$DAY2_CHECK_BOOTSTRAP" ${DAY2_CLIENT_CONFIG:+--command-config "$DAY2_CLIENT_CONFIG"} --describe --group connect-day2-sink
    for i in $(seq 1 30)
    do
        lag=$(day2_client "kafka-consumer-groups --bootstrap-server $DAY2_CHECK_BOOTSTRAP ${DAY2_CLIENT_CONFIG:+--command-config $DAY2_CLIENT_CONFIG} --describe --group connect-day2-sink 2> /dev/null" | awk -v t="$DAY2_TOPIC" '$2 == t && $6 ~ /^[0-9]+$/ { lag += $6 } END { print lag + 0 }')
        if [ "$lag" -eq 0 ]
        then
            break
        fi
        sleep 5
    done
    log "🔎 acked by the producer: $acked, records in topic $DAY2_TOPIC: $records, lag of the sink connector: $lag"
    if [ "$records" -lt "$acked" ]
    then
        logerror "❌ $((acked - records)) acked record(s) are not in the topic"
        exit 1
    fi
    if [ "$lag" -ne 0 ]
    then
        logerror "❌ the sink connector did not consume every record (lag $lag)"
        playground connector status --connector day2-sink
        exit 1
    fi
    log "✅ no record lost: every acked record is in the topic and was consumed by the sink connector"
}
