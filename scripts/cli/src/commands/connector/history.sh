connector="${args[--connector]}"
verbose="${args[--verbose]}"
since="${args[--since]}"
config_topic="${args[--config-topic]}"
status_topic="${args[--status-topic]}"
json="${args[--json]}"

connector_type=$(playground state get run.connector_type)

if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
then
    log "connector history command is not supported with $connector_type connector: the internal topics of the connect cluster are not readable"
    exit 0
fi

get_environment_used

# internal topics of the connect cluster: from the worker properties, unless set
if [[ -z "$config_topic" ]] || [[ -z "$status_topic" ]]
then
    connect_container="connect"
    [[ "$environment" == cfk* ]] && connect_container="connect-0"
    [[ "$environment" == mdc* ]] && get_connect_container
    worker_properties=$(playground container get-properties -c "$connect_container" 2> /dev/null || true)
    [[ -z "$config_topic" ]] && config_topic=$(echo "$worker_properties" | grep -E "^config\.storage\.topic=" | cut -d= -f2 | tr -d '\r')
    [[ -z "$status_topic" ]] && status_topic=$(echo "$worker_properties" | grep -E "^status\.storage\.topic=" | cut -d= -f2 | tr -d '\r')
    config_topic=${config_topic:-connect-configs}
    status_topic=${status_topic:-connect-status}
fi

# prints the records of internal topic $1 as "<timestamp ms>|<key>|<value>" lines (a tombstone value is "null")
function read_internal_topic() {
    local topic="$1"
    # --property works with every version (only deprecated in favor of --formatter-property since Kafka 4.0)
    local consumer_args=(--topic "$topic" --from-beginning --timeout-ms 6000 --property print.key=true --property print.timestamp=true --property key.separator='|')
    if [[ "$environment" == "ccloud" ]]
    then
        get_kafka_docker_playground_dir
        if [ ! -f $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/env.delta ] || [ ! -f $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta ]
        then
            logerror "❌ $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/env.delta or ak-tools-ccloud.delta has not been generated"
            exit 1
        fi
        source $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/env.delta
        get_connect_image
        [[ -n "$verbose" ]] && log "🐞 kafka-console-consumer ${consumer_args[*]} --bootstrap-server $BOOTSTRAP_SERVERS --consumer.config /tmp/configuration/ccloud.properties"
        docker run --quiet --rm -v $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta:/tmp/configuration/ccloud.properties ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} kafka-console-consumer "${consumer_args[@]}" --bootstrap-server $BOOTSTRAP_SERVERS --consumer.config /tmp/configuration/ccloud.properties 2> /dev/null
    else
        get_security_broker "--consumer.config"
        [[ -n "$verbose" ]] && log "🐞 kafka-console-consumer ${consumer_args[*]} --bootstrap-server $bootstrap_server $security (in $container)"
        if [[ "$environment" == cfk* ]]
        then
            kubectl -n confluent exec -i $container -- kafka-console-consumer "${consumer_args[@]}" --bootstrap-server $bootstrap_server $security 2> /dev/null
        else
            docker exec -i $container kafka-console-consumer "${consumer_args[@]}" --bootstrap-server $bootstrap_server $security 2> /dev/null
        fi
    fi | awk '/^(CreateTime|LogAppendTime):[0-9]+\|/ { sub(/^[A-Za-z]+:/, ""); print }'
}

if [[ -z "$json" ]]
then
    log "🕰️ Reading the internal topics $config_topic and $status_topic"
fi
# both at once: each read ends after 6 seconds without a new record
tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
trap 'rm -rf $tmp_dir' EXIT
read_internal_topic "$config_topic" > "$tmp_dir/config" &
read_internal_topic "$status_topic" > "$tmp_dir/status" &
wait
config_records=$(cat "$tmp_dir/config")
status_records=$(cat "$tmp_dir/status")
if [[ -z "$config_records" ]] && [[ -z "$status_records" ]]
then
    logerror "❌ No record found in $config_topic and $status_topic: wrong topic names? (--config-topic, --status-topic)"
    exit 1
fi

since_ms=0
if [[ -n "$since" ]]
then
    since_ms=$(( ($(date +%s) - $(duration_to_seconds "$since")) * 1000 ))
fi

# task configs returned by the REST API are not masked: hide the values of the keys that look like secrets
secret_keys_regex='(password|secret|jaas|token|credential|api[._]key|private[._]key|keystore\.key|access[._]key)'

history=$( { echo "$config_records" | sed 's/^/config|/'; echo "$status_records" | sed 's/^/status|/'; } | jq -R -s \
    --arg only "$connector" \
    --argjson since_ms "$since_ms" \
    --argjson now_ms "$(( $(date +%s) * 1000 ))" \
    --arg secret_regex "$secret_keys_regex" '
    # also the passwords embedded in a value: password=... parameters of a jdbc url, user:password@ of a url
    def mask: with_entries(if (.key | test($secret_regex; "i")) then .value = "********"
        else .value |= (if type == "string" then gsub("(?<k>(password|pwd)=)[^&;]*"; "\(.k)********"; "i") | gsub("(?<s>://[^/:@]+:)[^/@]+@"; "\(.s)********@") else . end) end);
    def first_line: if . == null then null else (split("\n") | first) end;

    split("\n") | map(select(length > 0) | split("|")
        | {source: .[0], ts: (.[1] | tonumber), key: .[2], value: (.[3:] | join("|") | if . == "null" then null else (fromjson? // .) end)})
    # what each record is about
    | map(. + (
        if .source == "config" then
            (.key | capture("^connector-(?<c>.+)$") | {connector: .c, kind: "config"})
            // (.key | capture("^target-state-(?<c>.+)$") | {connector: .c, kind: "target-state"})
            // (.key | capture("^commit-(?<c>.+)$") | {connector: .c, kind: "commit"})
            // {kind: "other"}
        else
            (.key | capture("^status-connector-(?<c>.+)$") | {connector: .c, kind: "status", task: null})
            // (.key | capture("^status-task-(?<c>.+)-(?<t>[0-9]+)$") | {connector: .c, kind: "status", task: (.t | tonumber)})
            // (.key | capture("^status-topic-(?<topic>.+):connector-(?<c>.+)$") | {connector: .c, kind: "topic", topic: .topic})
            // {kind: "other"}
        end))
    | map(select(.kind != "other" and ($only == "" or .connector == $only)))
    | sort_by(.ts)
    | group_by(.connector)
    | map(
        . as $records
        | .[0].connector as $c
        | reduce $records[] as $r ({events: [], props: null, states: {}, topics: {}};
            if $r.kind == "config" then
                if $r.value == null then
                    .events += [{ts: $r.ts, kind: "deleted", what: "connector", text: "connector deleted"}] | .props = null
                else
                    # __internal.config.version changes with every update, it says nothing
                    ($r.value.properties // {} | with_entries(select(.key | startswith("__internal.") | not)) | mask) as $new
                    | if .props == null then
                        .events += [{ts: $r.ts, kind: "created", what: "config", text: "created (\($new["connector.class"] // "?" | split(".") | last), tasks.max=\($new["tasks.max"] // "?"))"}]
                      else
                        .props as $old
                        | ([$new | keys[] | select($old[.] == null) | "+ \(.)=\($new[.])"]
                           + [$old | keys[] | select($new[.] == null) | "- \(.)"]
                           + [$new | keys[] | select($old[.] != null and $old[.] != $new[.]) | "\(.): \($old[.]) → \($new[.])"]) as $changes
                        | if ($changes | length) == 0 then
                            .events += [{ts: $r.ts, kind: "config", what: "config", text: "config updated, nothing changed"}]
                          else
                            .events += [{ts: $r.ts, kind: "config", what: "config", text: "config changed", changes: $changes}]
                          end
                      end
                    | .props = $new
                end
            elif $r.kind == "target-state" then
                if $r.value == null then . else
                .events += [{ts: $r.ts, kind: "target-state", what: "connector", text: "target state \($r.value.state // "?") (\(if $r.value.state == "STARTED" then "resume" elif $r.value.state == "PAUSED" then "pause" elif $r.value.state == "STOPPED" then "stop" else "?" end))"}]
                end
            elif $r.kind == "commit" then
                if $r.value == null then . else
                .events += [{ts: $r.ts, kind: "commit", what: "tasks", text: "\($r.value.tasks // "?") task config(s) committed"}]
                end
            elif $r.kind == "topic" then
                if .topics[$r.topic] then . else
                .topics[$r.topic] = true
                | .events += [{ts: $r.ts, kind: "topic", what: "topic", text: "first use of topic \($r.topic)\(if $r.value.topic.task != null then " (task \($r.value.topic.task))" else "" end)"}]
                end
            elif $r.kind == "status" then
                (if $r.task == null then "connector" else "task \($r.task)" end) as $what
                | if $r.value == null then
                    # one tombstone per worker that had the status: only the first one
                    if (.states | has($what)) and .states[$what] == null then . else
                    .events += [{ts: $r.ts, kind: "status", what: $what, state: "REMOVED", text: "status removed (connector deleted)"}] | .states[$what] = null
                    end
                  else
                    .states[$what] as $prev
                    | ($r.value.state // "?") as $state
                    # the same state written again by the same worker generation says nothing
                    | if $prev != null and $prev.state == $state and $prev.worker_id == $r.value.worker_id and $prev.generation == $r.value.generation then . else
                      .events += [{
                          ts: $r.ts, kind: "status", what: $what, state: $state, previous: ($prev.state // null),
                          worker_id: ($r.value.worker_id // null), generation: ($r.value.generation // null),
                          trace: ($r.value.trace | first_line),
                          text: "\(if $prev.state != null and $prev.state != $state then "\($prev.state) → " else "" end)\($state) on \($r.value.worker_id // "?") (generation \($r.value.generation // "?"))"
                        }]
                      | .states[$what] = {state: $state, worker_id: $r.value.worker_id, generation: $r.value.generation, since: $r.ts}
                      end
                  end
            else . end)
        | . as $h
        | ($h.events | map(select(.kind == "status"))) as $status_events
        | {
            connector: $c,
            events: ($h.events | map(select(.ts >= $since_ms))),
            summary: {
              failures: ($status_events | map(select(.state == "FAILED")) | group_by(.what) | map({key: .[0].what, value: length}) | from_entries),
              # back to RUNNING after a FAILED (directly, or through RESTARTING / UNASSIGNED)
              recoveries: ($status_events | group_by(.what) | map(reduce .[] as $e ({failed: false, n: 0};
                  if $e.state == "FAILED" then .failed = true
                  elif $e.state == "RUNNING" and .failed then .n += 1 | .failed = false
                  else . end) | .n) | add // 0),
              config_changes: ($h.events | map(select(.kind == "config")) | length),
              deleted: ($h.props == null and ($h.events | map(select(.kind == "deleted")) | length) > 0),
              current: ($h.states | to_entries | map(select(.value != null) | {what: .key, state: .value.state, worker_id: .value.worker_id, since: .value.since, age_s: (($now_ms - .value.since) / 1000 | floor)}))
            }
          })')

if [[ -n "$json" ]]
then
    echo "$history" | jq .
    exit 0
fi

if [ "$(echo "$history" | jq 'length')" == "0" ]
then
    logwarn "⚠️ No history found$([[ -n "$connector" ]] && echo " for connector $connector") in $config_topic and $status_topic"
    exit 0
fi

while read -r h
do
    c=$(echo "$h" | jq -r '.connector')
    log "🕰️ History of $connector_type connector $c$([[ -n "$since" ]] && echo " (last $since)")"
    if [ "$(echo "$h" | jq '.events | length')" == "0" ]
    then
        log "💤 no event$([[ -n "$since" ]] && echo " in the last $since")"
    fi
    echo "$h" | jq -r '
        def icon: if .kind == "created" then "🆕"
            elif .kind == "deleted" then "🗑️ "
            elif .kind == "config" then "⚙️ "
            elif .kind == "commit" then "🧵"
            elif .kind == "topic" then "📚"
            elif .kind == "target-state" then "🎯"
            elif .state == "RUNNING" then "🟢"
            elif .state == "FAILED" then "🛑"
            elif .state == "PAUSED" then "⏸️ "
            elif .state == "STOPPED" then "⏹️ "
            elif .state == "UNASSIGNED" then "⌛"
            elif .state == "RESTARTING" then "🔄"
            elif .state == "REMOVED" then "🗑️ "
            else "• " end;
        .events[]
        | "\(.ts / 1000 | floor | strftime("%Y-%m-%d %H:%M:%S UTC"))  \(icon) \(.what | . + (" " * (([10 - length, 0] | max))))  \(.text)",
          (.changes // [] | .[] | "                                        \(.)"),
          (if .trace then "                                        ↳ \(.trace)" else empty end)'
    echo "$h" | jq -r '
        def age: if . < 120 then "\(.)s" elif . < 7200 then "\(. / 60 | floor)min" elif . < 172800 then "\(. / 3600 | floor)h" else "\(. / 86400 | floor)d" end;
        .summary
        | "🧾 \(.failures | to_entries | map(.value) | add // 0) failure(s)\(if (.failures | length) > 0 then " (" + (.failures | to_entries | map("\(.key): \(.value)") | join(", ")) + ")" else "" end), \(.recoveries) recovery(ies) after a failure, \(.config_changes) config change(s)\(if .deleted then ", deleted" else "" end)",
          (.current[] | "   \(.what): \(.state) on \(.worker_id // "?") for \(.age_s | age)")'
done < <(echo "$history" | jq -c '.[]')
