connector="${args[--connector]}"
verbose="${args[--verbose]}"
watch="${args[--watch]}"
json="${args[--json]}"

connector_type=$(playground state get run.connector_type)

if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
then
    # no jmx for a fully managed connector: its metrics come from the Confluent Cloud Telemetry API
    if [[ -n "$json" ]] || [[ -n "$watch" ]]
    then
        logerror "❌ --json and --watch are not supported with $connector_type connector"
        exit 1
    fi
    log "〽️ $connector_type connector: metrics from the Confluent Cloud Telemetry API (playground connector display-metrics-api)"
    if [[ -n "$connector" ]]
    then
        playground connector display-metrics-api --connector "$connector" ${verbose:+--verbose}
    else
        playground connector display-metrics-api ${verbose:+--verbose}
    fi
    exit $?
fi

get_environment_used
if [[ "$environment" == cfk* ]]
then
    logerror "❌ connector metrics is not supported on $environment environment, use playground get-jmx-metrics -c connect-0 --domain kafka.connect"
    exit 1
fi

if [[ ! -n "$connector" ]]
then
    connector=$(playground get-connector-list)
    if [ "$connector" == "" ]
    then
        logerror "💤 No $connector_type connector is running !"
        exit 1
    fi
fi

get_connect_url_and_security

# <label>|<mbean type>|<attribute>|<format>, per connector type (rate, total, ms, pct, ratio, ts, str)
source_spec="state|connector-task-metrics|status|str
records polled/s|source-task-metrics|source-record-poll-rate|rate
records written/s|source-task-metrics|source-record-write-rate|rate
polled (total)|source-task-metrics|source-record-poll-total|total
written (total)|source-task-metrics|source-record-write-total|total
in flight|source-task-metrics|source-record-active-count|total
poll batch avg|source-task-metrics|poll-batch-avg-time-ms|ms
batch size avg|connector-task-metrics|batch-size-avg|total"
sink_spec="state|connector-task-metrics|status|str
partitions|sink-task-metrics|partition-count|total
records read/s|sink-task-metrics|sink-record-read-rate|rate
records sent/s|sink-task-metrics|sink-record-send-rate|rate
read (total)|sink-task-metrics|sink-record-read-total|total
sent (total)|sink-task-metrics|sink-record-send-total|total
in flight|sink-task-metrics|sink-record-active-count|total
put batch avg|sink-task-metrics|put-batch-avg-time-ms|ms
put batch max|sink-task-metrics|put-batch-max-time-ms|ms
batch size avg|connector-task-metrics|batch-size-avg|total"
common_spec="offset commit avg|connector-task-metrics|offset-commit-avg-time-ms|ms
offset commit failed|connector-task-metrics|offset-commit-failure-percentage|pct
running ratio|connector-task-metrics|running-ratio|pct
pause ratio|connector-task-metrics|pause-ratio|pct
record errors|task-error-metrics|total-record-errors|total
record failures|task-error-metrics|total-record-failures|total
records skipped|task-error-metrics|total-records-skipped|total
retries|task-error-metrics|total-retries|total
errors logged|task-error-metrics|total-errors-logged|total
sent to DLQ|task-error-metrics|deadletterqueue-produce-requests|total
DLQ produce failed|task-error-metrics|deadletterqueue-produce-failures|total
last error|task-error-metrics|last-error-timestamp|ts"

# the generated CLI indents the lines of these strings
source_spec=$(echo "$source_spec" | sed 's/^[[:space:]]*//')
sink_spec=$(echo "$sink_spec" | sed 's/^[[:space:]]*//')
common_spec=$(echo "$common_spec" | sed 's/^[[:space:]]*//')

# prints the MBeans of connector $1 on the worker container $2, $3 being its topic prefix (Debezium server name, can be
# empty): "<type>|<task>|<attribute>|<value>" lines for the task metrics of kafka connect, and
# "extra|<object name>|<attribute>|<value>" lines for the other MBeans of the connector (Debezium, MongoDB, Oracle CDC...)
function read_task_mbeans() {
    local connector="$1" container="$2" prefix="$3" port output
    port=$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$container" 2> /dev/null | grep -E "^KAFKA_JMX_PORT=" | cut -d= -f2 || true)
    if [[ -z "$port" ]]
    then
        logwarn "⚠️ JMX is not enabled on $container (no KAFKA_JMX_PORT), skipped"
        return 0
    fi
    # the jvm of the tool must not inherit the debug agent, jmx port or java agents of the worker (bind errors)
    local jmx_command=(docker exec "$container" env -u KAFKA_DEBUG -u JAVA_DEBUG_OPTS -u KAFKA_JMX_PORT -u KAFKA_JMX_OPTS -u KAFKA_OPTS -u KAFKA_HEAP_OPTS)
    if docker exec "$container" bash -c "command -v kafka-jmx" > /dev/null 2>&1
    then
        jmx_command+=(kafka-jmx)
    else
        # before Kafka 3.5
        jmx_command+=(kafka-run-class kafka.tools.JmxTool)
    fi
    # every MBean with a connector=<connector> key (kafka connect task metrics, MongoDB, Oracle CDC...), and the Debezium
    # ones, named after the topic prefix: debezium.<plugin>:type=connector-metrics,context=streaming,server=<prefix>...
    local object_args=(--object-name "*:connector=$connector,*")
    if [ -n "$prefix" ]
    then
        object_args+=(--object-name "debezium.*:server=$prefix,*")
    fi
    [[ -n "$verbose" ]] && log "🐞 ${jmx_command[*]} --jmx-url service:jmx:rmi:///jndi/rmi://localhost:$port/jmxrmi ${object_args[*]} --one-time true --report-format tsv"
    output=$("${jmx_command[@]}" --jmx-url "service:jmx:rmi:///jndi/rmi://localhost:$port/jmxrmi" "${object_args[@]}" --one-time true --report-format tsv 2>&1) || true
    if ! echo "$output" | grep -q -E "^[a-zA-Z0-9_.-]+:[a-zA-Z0-9_-]+="
    then
        if ! echo "$output" | grep -q -E "^(time|Trying to connect|Expected attribute counts)"
        then
            logwarn "⚠️ could not read the JMX metrics of $container:"
            echo "$output" | grep -v -E "^[[:space:]]+at " | tail -3
        fi
        return 0
    fi
    # <object name>:<attribute>\t<value>
    echo "$output" | awk -F'\t' '/^[a-zA-Z0-9_.-]+:[a-zA-Z0-9_-]+=/ && NF >= 2 {
        key = $1; value = $2
        attribute = key; sub(/.*:/, "", attribute)
        object = substr(key, 1, length(key) - length(attribute) - 1)
        if (object ~ /^kafka\.connect:type=(connector-task|source-task|sink-task|task-error)-metrics,connector=[^,]+,task=[0-9]+$/) {
            type = object; sub(/^kafka\.connect:type=/, "", type); sub(/,.*/, "", type)
            task = object; sub(/.*,task=/, "", task)
            print type "|" task "|" attribute "|" value
        } else if (object !~ /^kafka\.connect:type=(connector-metrics|connect-worker-metrics),/) {
            print "extra|" object "|" attribute "|" value
        }
    }'
}

function collect_metrics() {
    local connector="$1" status_json worker_ids container port prefix lines=""
    handle_onprem_connect_rest_api "curl $security -s \"$connect_url/connectors/$connector/status\"" || return 1
    status_json="$curl_output"
    handle_onprem_connect_rest_api "curl $security -s \"$connect_url/connectors/$connector/config\"" || return 1
    prefix=$(echo "$curl_output" | jq -r '."topic.prefix" // ."database.server.name" // empty')
    worker_ids=$(echo "$status_json" | jq -r '[.tasks[]?.worker_id] | unique | .[]')
    while read -r worker_id
    do
        [ -z "$worker_id" ] && continue
        read -r container port <<< "$(benchmark_worker_container_and_port "$worker_id")"
        if ! is_container_running "$container"
        then
            logwarn "⚠️ worker $worker_id (container $container) is not running, skipped"
            continue
        fi
        lines+="$(read_task_mbeans "$connector" "$container" "$prefix")"$'\n'
    done <<< "$worker_ids"

    echo -n "$lines" | jq -R -s --arg connector "$connector" --argjson status "$status_json" '
        split("\n") | map(select(length > 0) | split("|") | {type: .[0], task: .[1], attribute: .[2], value: (.[3:] | join("|"))})
        | map(select(.type != "extra")) as $mbeans
        | (map(select(.type == "extra")) | group_by(.task) | map({mbean: .[0].task, attributes: (map({key: .attribute, value: (.value | tonumber? // .)}) | from_entries)})) as $extra
        | {
            connector: $connector,
            type: $status.type,
            state: $status.connector.state,
            tasks: ($status.tasks // [] | sort_by(.id) | map(
                (.id | tostring) as $id
                | {
                    id: .id,
                    state: .state,
                    worker_id: (.worker_id // null),
                    metrics: ($mbeans | map(select(.task == $id)) | map({key: "\(.type):\(.attribute)", value: (.value | tonumber? // .)}) | from_entries)
                  })),
            connector_metrics: $extra
          }'
}

function print_metrics() {
    local result="$1" spec ids label type attribute format
    if [ "$(echo "$result" | jq -r '.type')" == "sink" ]
    then
        spec="$sink_spec"$'\n'"$common_spec"
    else
        spec="$source_spec"$'\n'"$common_spec"
    fi
    ids=$(echo "$result" | jq -r '.tasks[].id')
    if [ -z "$ids" ]
    then
        logwarn "⚠️ $connector_type connector $(echo "$result" | jq -r '.connector') has no task"
        return
    fi
    log "📈 Task metrics of $connector_type connector $(echo "$result" | jq -r '"\(.connector) (\(.type), connector \(.state))"')"
    {
        printf 'METRIC'
        for id in $ids
        do
            printf '\tTASK %s' "$id"
        done
        printf '\n'
        while IFS='|' read -r label type attribute format
        do
            [ -z "$label" ] && continue
            printf '%s' "$label"
            for id in $ids
            do
                printf '\t%s' "$(echo "$result" | jq -r --argjson id "$id" --arg key "$type:$attribute" --arg format "$format" '
                    (.tasks[] | select(.id == $id) | .metrics[$key]) as $v
                    | if $v == null then "-"
                      elif ($v | type) != "number" then
                        (if $format == "str" then ($v | ascii_upcase) else ($v | tostring) end)
                      elif ($v | isnan) then "-"
                      elif $format == "rate" then ($v * 10 | round / 10 | tostring) + "/s"
                      elif $format == "ms" then ($v | round | tostring) + " ms"
                      elif $format == "pct" then ($v * 100 | round | tostring) + "%"
                      elif $format == "ts" then (if $v <= 0 then "-" else ($v / 1000 | floor | strftime("%Y-%m-%d %H:%M:%S UTC")) end)
                      else ($v | if . == floor then (floor | tostring) else (. * 10 | round / 10 | tostring) end)
                      end')"
            done
            printf '\n'
        done <<< "$spec"
    } | column -t -s $'\t'
}

# the other MBeans of the connector (Debezium, MongoDB, Oracle CDC...), one block per MBean
function print_connector_metrics() {
    local result="$1"
    [ "$(echo "$result" | jq '.connector_metrics | length')" == "0" ] && return
    log "🧩 Metrics of the connector itself"
    echo "$result" | jq -r '
        .connector_metrics[]
        | "  \(.mbean)",
          (.attributes | to_entries | sort_by(.key)[]
            # null values, and arrays printed with their java toString ([Ljava.lang.String;@27f3b6d6), say nothing
            | select(.value != null and .value != "null" and (.value | tostring | test("^\\[L[a-zA-Z.]+;@") | not) and (.value | tostring | length) <= 120)
            | "    \(.key)\t\(.value | if type == "number" and . == floor then (floor | tostring) elif type == "number" then (. * 100 | round / 100 | tostring) else tostring end)")' \
        | awk -F'\t' 'NF == 1 { print; next } { printf "%-48s %s\n", $1, $2 }'
}

# what stands out, and what to run next
function print_findings() {
    local result="$1" findings
    findings=$(echo "$result" | jq -r '
        .connector as $c | .type as $type
        | [ .tasks[] | .id as $id | .metrics as $m
            | ($m["task-error-metrics:total-record-errors"] // 0) as $errors
            | ($m["task-error-metrics:total-records-skipped"] // 0) as $skipped
            | ($m["task-error-metrics:deadletterqueue-produce-requests"] // 0) as $dlq
            | ($m["task-error-metrics:total-retries"] // 0) as $retries
            | ($m["connector-task-metrics:offset-commit-failure-percentage"] // 0) as $commit_failed
            | (if ($m | length) == 0 then "❓ task \($id): no metric found (task not running on a reachable worker?)" else empty end),
              (if .state != "RUNNING" then "🛑 task \($id) is \(.state): playground connector diagnose --connector \($c)" else empty end),
              (if $errors > 0 then "⚠️ task \($id): \($errors | floor) record error(s), \($skipped | floor) skipped, \($dlq | floor) sent to the DLQ" else empty end),
              (if $dlq > 0 then "   ↳ playground topic dlq inspect --connector \($c)" else empty end),
              (if $skipped > 0 and $dlq == 0 then "   ↳ records are dropped (errors.tolerance=all) without a DLQ: set errors.deadletterqueue.topic.name, or errors.log.enable=true to see them" else empty end),
              (if $retries > 0 then "🔁 task \($id): \($retries | floor) retried operation(s) (errors.retry.timeout)" else empty end),
              (if ($m["task-error-metrics:deadletterqueue-produce-failures"] // 0) > 0 then "🔥 task \($id): records could not be written to the DLQ" else empty end),
              (if ($commit_failed | type) == "number" and $commit_failed > 0 then "⚠️ task \($id): \($commit_failed * 100 | round)% of the offset commits failed" else empty end),
              (if ($m["connector-task-metrics:pause-ratio"] // 0) > 0.5 then "⏸️ task \($id) was paused most of the time" else empty end),
              (if $type == "source" and ($m | length) > 0 and ($m["source-task-metrics:source-record-poll-total"] // 0) == 0 then "💤 task \($id) has not polled any record since it started" else empty end),
              (if $type == "sink" and ($m | length) > 0 and ($m["sink-task-metrics:partition-count"] // 0) == 0 then "💤 task \($id) has no partition assigned: playground connector tasks --connector \($c)" else empty end),
              (if $type == "sink" and ($m["sink-task-metrics:partition-count"] // 0) > 0 and ($m["sink-task-metrics:sink-record-read-total"] // 0) == 0 then "💤 task \($id) has not read any record since it started: playground connector show-lag --connector \($c)" else empty end),
              (if $type == "sink" and (($m["sink-task-metrics:put-batch-avg-time-ms"] // 0) | type) == "number" and ($m["sink-task-metrics:put-batch-avg-time-ms"] // 0) > 1000 then "🐢 task \($id): a put takes \($m["sink-task-metrics:put-batch-avg-time-ms"] | round) ms on average, the target system is slow: playground analyze flight-recorder -c connect --connector \($c)" else empty end)
          ]
        # Debezium (and the connectors built on it, Oracle XStream...): connection, lag, queue, snapshot
        + [ .connector_metrics[] | .mbean as $b | .attributes as $a
            | select($b | startswith("debezium."))
            | (if $a.Connected == false or $a.Connected == "false" then "🔌 \($b): not connected to the database" else empty end),
              (if ($a.MilliSecondsBehindSource | type) == "number" and $a.MilliSecondsBehindSource > 60000 then "🐢 \($b): \($a.MilliSecondsBehindSource / 1000 | floor) s behind the source database" else empty end),
              (if ($a.QueueRemainingCapacity | type) == "number" and $a.QueueRemainingCapacity == 0 then "🚧 \($b): the queue is full, the task cannot write to Kafka as fast as it reads the database (max.queue.size, producer throughput)" else empty end),
              (if $a.SnapshotRunning == true or $a.SnapshotRunning == "true" then "📸 \($b): snapshot in progress, \($a.RemainingTableCount // "?") of \($a.TotalTableCount // "?") table(s) remaining" else empty end),
              (if $a.SnapshotAborted == true or $a.SnapshotAborted == "true" then "🛑 \($b): the snapshot was aborted" else empty end)
          ] | .[]')
    if [ -n "$findings" ]
    then
        log "🔎 What stands out:"
        echo "$findings"
    else
        log "✅ Nothing stands out: no error, no skipped record, all tasks made progress"
    fi
}

items=($connector)
length=${#items[@]}
if ((length > 1)) && [[ -z "$json" ]]
then
    log "✨ --connector flag was not provided, applying command to all connectors"
fi

interval=""
[[ -n "$watch" ]] && interval=$(duration_to_seconds "$watch")

while true
do
    results="[]"
    for connector in "${items[@]}"
    do
        result=$(collect_metrics "$connector") || { logerror "❌ Could not get the status of $connector_type connector $connector"; exit 1; }
        if [[ -n "$json" ]]
        then
            results=$(echo "$results" | jq --argjson r "$result" '. + [$r]')
            continue
        fi
        print_metrics "$result"
        print_connector_metrics "$result"
        print_findings "$result"
    done
    if [[ -n "$json" ]]
    then
        echo "$results" | jq .
        break
    fi
    [[ -z "$interval" ]] && break
    log "🔁 next refresh in ${interval}s (ctrl-c to stop)"
    sleep "$interval"
done
