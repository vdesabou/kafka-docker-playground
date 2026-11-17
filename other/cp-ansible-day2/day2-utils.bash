#!/bin/bash
# Helpers shared by the cp-ansible day-2 examples (sourced, not run: run-tests.sh only runs the *.sh files of the folder).
#
# Each example changes a running cluster deployed by cp-ansible (upgrade, security, scale out...) while a workload runs
# through the change, and checks at the end that it survived:
#  - kafka-verifiable-producer on the connect host: a numbered sequence, acks=all, no retries, one json line per ack and
#    per error in /tmp/day2-<name>.log (name: producer by default; enable-sasl-ssl.sh adds a legacy one)
#  - the FileStream sink connector: the same topic to /tmp/day2-sink.txt on the worker

DAY2_TOPIC="day2"

# the examples start their own ansible environment: run them from the plaintext CI job only (like the deep dive labs)
function day2_require_plaintext () {
    if [ "${PLAYGROUND_ENVIRONMENT:-plaintext}" != "plaintext" ]
    then
        logwarn "the cp-ansible day-2 examples start their own ansible environment, skipping with ${PLAYGROUND_ENVIRONMENT}"
        exit 111
    fi
    # the hosts of the example only: the optional hosts of the --enable-* flags exported in the shell are not part of it
    unset ENABLE_CONTROL_CENTER ENABLE_KSQLDB ENABLE_RESTPROXY ENABLE_CONNECT_NODES
}

# bootstrap servers of the running brokers: broker:9092,broker2:9092,...
function day2_bootstrap () {
    local b list=""
    for b in broker broker2 broker3
    do
        if docker inspect -f '{{.State.Running}}' "$b" 2> /dev/null | grep -q true
        then
            list="${list:+$list,}$b:${1:-9092}"
        fi
    done
    echo "$list"
}

# the topic (replication factor 3 and min.insync.replicas 2 with 3 brokers), the producer and the sink connector.
# $1: port of the listener the producer uses (default 9092), $2: client properties file on the connect host (optional)
function day2_start_workload () {
    local port="${1:-9092}" client_config="$2" nb_brokers rf=1 min_isr=1
    # a secured cluster: the client settings of the connect host (written by the hand-over of the playbook)
    if [ -z "$client_config" ] && docker exec connect test -f /etc/kafka/client.properties 2> /dev/null
    then
        client_config=/etc/kafka/client.properties
    fi
    nb_brokers=$(day2_bootstrap | tr ',' '\n' | grep -c .)
    if [ "$nb_brokers" -ge 3 ]
    then
        rf=3
        min_isr=2
    fi
    playground topic create --topic "$DAY2_TOPIC" --nb-partitions 3 --if-not-exists --replication-factor $rf --config min.insync.replicas=$min_isr
    day2_start_producer "$port" "$client_config"
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

# (re)starts a producer, appending to its log: $1 port, $2 client properties file on the connect host, $3 name
function day2_start_producer () {
    local port="${1:-9092}" client_config="$2" name="${3:-producer}" config_option=""
    if [ -n "$client_config" ]
    then
        config_option="--producer.config $client_config"
    fi
    log "📤 $name: kafka-verifiable-producer on the connect host, topic $DAY2_TOPIC, 20 records/s, acks=all, bootstrap $(day2_bootstrap "$port")${client_config:+, $client_config}"
    log_command docker exec -d connect sh -c "kafka-verifiable-producer --bootstrap-server $(day2_bootstrap "$port") --topic $DAY2_TOPIC --throughput 20 --max-messages -1 --acks -1 $config_option >> /tmp/day2-$name.log 2>&1"
    docker exec -d connect sh -c "kafka-verifiable-producer --bootstrap-server $(day2_bootstrap "$port") --topic $DAY2_TOPIC --throughput 20 --max-messages -1 --acks -1 $config_option >> /tmp/day2-$name.log 2>&1"
}

# stops a producer ($1 name, all of them without it): the java process writing to /tmp/day2-<name>.log
function day2_stop_producer () {
    if [ -n "$1" ]
    then
        docker exec -e LOG="/tmp/day2-$1.log" connect sh -c 'for p in $(pgrep -f VerifiableProducer); do if ls -l /proc/$p/fd 2> /dev/null | grep -q "$LOG"; then kill $p; fi; done; sleep 3' || true
    else
        docker exec connect sh -c 'pkill -f VerifiableProducer; sleep 3' || true
    fi
}

# count of a json event ($1: producer_send_success or producer_send_error) in the log of producer $2 (default producer)
function day2_count () {
    local count
    # grep -c prints 0 and exits 1 when nothing matches
    count=$(docker exec connect sh -c "grep -c '\"$1\"' /tmp/day2-${2:-producer}.log || true" 2> /dev/null)
    echo "${count:-0}"
}

# longest time (seconds) without an ack of producer $2 (default producer) since epoch millis $1
function day2_longest_pause () {
    docker exec connect sh -c "grep '\"producer_send_success\"' /tmp/day2-${2:-producer}.log" 2> /dev/null \
        | jq -r --argjson since "$1" 'select(.timestamp >= $since) | .timestamp' \
        | awk 'NR > 1 && $1 - prev > max { max = $1 - prev } { prev = $1 } END { printf "%.1f", max / 1000 }'
}

# acks of producer $2 (default producer) since epoch millis $1
function day2_acks_since () {
    docker exec connect sh -c "grep '\"producer_send_success\"' /tmp/day2-${2:-producer}.log" 2> /dev/null \
        | jq -r --argjson since "$1" 'select(.timestamp >= $since) | .timestamp' | grep -c . || true
}

# epoch millis now, for day2_longest_pause and day2_broker_restarts
function day2_now () {
    echo $(( $(date +%s) * 1000 ))
}

# when each broker service was restarted since epoch millis $1 (journald of the hosts), and the spread between the first
# and the last restart in DAY2_RESTART_SPREAD (seconds)
function day2_broker_restarts () {
    local since_s=$(( $1 / 1000 )) b t first="" last=""
    log "🕐 broker restarts since $(date -r "$since_s" '+%H:%M:%S' 2> /dev/null || date -d "@$since_s" '+%H:%M:%S') (journald of each broker host):"
    log_command docker exec broker journalctl -u confluent-server --no-pager -o short-unix --since "@$since_s"
    for b in broker broker2 broker3
    do
        if ! docker inspect -f '{{.State.Running}}' "$b" 2> /dev/null | grep -q true
        then
            continue
        fi
        t=$(docker exec "$b" journalctl -u confluent-server --no-pager -o short-unix --since "@$since_s" 2> /dev/null | grep "Stopping confluent-server" | tail -1 | cut -d '.' -f 1)
        if [ -n "$t" ]
        then
            log "   $b restarted at $(date -r "$t" '+%H:%M:%S' 2> /dev/null || date -d "@$t" '+%H:%M:%S')"
            [ -z "$first" ] || [ "$t" -lt "$first" ] && first=$t
            [ -z "$last" ] || [ "$t" -gt "$last" ] && last=$t
        else
            log "   $b not restarted"
        fi
    done
    DAY2_RESTART_SPREAD=$(( ${last:-0} - ${first:-0} ))
}

# acked records and send errors of a producer so far ($2 name), and its last error
function day2_report_workload () {
    local name="${2:-producer}" acked errors last_error
    acked=$(day2_count producer_send_success "$name")
    errors=$(day2_count producer_send_error "$name")
    log "📊 ${1:-workload} ($name): ${acked:-0} records acked, ${errors:-0} send errors"
    if [ "${errors:-0}" != "0" ]
    then
        last_error=$(docker exec connect sh -c "grep '\"producer_send_error\"' /tmp/day2-$name.log | tail -1" | jq -r '.exception + ": " + .message' 2> /dev/null | cut -c1-200)
        logwarn "   last send error: $last_error"
    fi
}

# number of send errors of a producer ($1 name) since the start of the example
function day2_send_errors () {
    day2_count producer_send_error "${1:-producer}"
}

# stops the producer and checks that every acked record is in the topic and in the file of the sink. Fails the example
# otherwise
function day2_check_no_loss () {
    local acked records sink_lines i
    day2_stop_producer
    day2_report_workload "workload stopped"
    # the acked records of every producer of the example
    log_command docker exec connect sh -c 'cat /tmp/day2-*.log | grep -c "\"producer_send_success\""'
    log_command --polled docker exec connect sh -c 'wc -l < /tmp/day2-sink.txt'
    acked=$(docker exec connect sh -c 'cat /tmp/day2-*.log | grep -c "\"producer_send_success\""' 2> /dev/null || echo 0)
    records=$(playground topic get-number-records -t "$DAY2_TOPIC" 2> /dev/null | tail -1)
    # the sink catches up
    for i in $(seq 1 30)
    do
        sink_lines=$(docker exec connect sh -c 'wc -l < /tmp/day2-sink.txt' 2> /dev/null | tr -d ' ')
        if [ "${sink_lines:-0}" -ge "$records" ]
        then
            break
        fi
        sleep 5
    done
    log "🔎 acked by the producer: $acked, records in topic $DAY2_TOPIC: $records, lines written by the sink connector: ${sink_lines:-0}"
    if [ "$records" -lt "$acked" ]
    then
        logerror "❌ $((acked - records)) acked record(s) are not in the topic"
        exit 1
    fi
    if [ "${sink_lines:-0}" -lt "$records" ]
    then
        logerror "❌ the sink connector wrote ${sink_lines:-0} records, the topic has $records"
        playground connector status --connector day2-sink
        exit 1
    fi
    log "✅ no record lost: every acked record is in the topic and was written by the sink connector"
}

# Confluent Platform version of each broker host
function day2_broker_versions () {
    local b
    for b in broker broker2 broker3
    do
        if docker inspect -f '{{.State.Running}}' "$b" 2> /dev/null | grep -q true
        then
            log "   $b: Confluent Platform $(get_container_cp_tag "$b")"
        fi
    done
}
