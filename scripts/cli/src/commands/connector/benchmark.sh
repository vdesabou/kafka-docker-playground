connector="${args[--connector]}"
verbose="${args[--verbose]}"
mode="${args[--mode]}"
nb_records="${args[--nb-records]}"
shape="${args[--shape]}"
record_size="${args[--record-size]}"
load_command="${args[--load-command]}"
stream_load_command="${args[--stream-load-command]}"
duration=$(duration_to_seconds "${args[--duration]}")
warmup=$(duration_to_seconds "${args[--warmup]}")
interval=$(duration_to_seconds "${args[--interval]}")
max_wait=$(duration_to_seconds "${args[--max-wait]}")
output_dir="${args[--output-dir]}"
compare_file="${args[--compare]}"
no_history="${args[--no-history]}"
json="${args[--json]}"
eval "topics=(${args[--topic]:-})"

# with --json, logs go to stderr and only the result json to stdout
exec 3>&1
if [[ -n "$json" ]]
then
    exec 1>&2
fi

connector_type=$(playground state get run.connector_type)
environment=$(playground state get run.environment)

if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
then
    logerror "❌ benchmark is not available for $connector_type connectors yet"
    exit 1
fi
if [[ "$environment" == cfk* ]]
then
    logerror "❌ benchmark is not available with the cfk environment yet"
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
    if [ $(echo "$connector" | wc -w) -gt 1 ]
    then
        logerror "❌ several connectors are running ($(echo $connector)), choose one with --connector"
        exit 1
    fi
fi

function now () {
    if [ -n "$EPOCHREALTIME" ]
    then
        echo "${EPOCHREALTIME/,/.}"
    else
        date +%s
    fi
}

get_connect_url_and_security
handle_onprem_connect_rest_api "curl -s $security \"$connect_url/connectors/$connector/status\""
status_json="$curl_output"
type=$(echo "$status_json" | jq -r '.type')
state=$(echo "$status_json" | jq -r '.connector.state')
if [ "$state" != "RUNNING" ]
then
    logerror "❌ $connector_type connector $connector is $state, it must be RUNNING to be benchmarked"
    playground connector status --connector "$connector"
    exit 1
fi
if echo "$status_json" | jq -e '[.tasks[]?.state] | index("FAILED")' > /dev/null 2>&1
then
    logerror "❌ a task of $connector_type connector $connector is FAILED, it must be RUNNING to be benchmarked"
    playground connector status --connector "$connector"
    exit 1
fi
if [ "$type" != "sink" ] && [ "$type" != "source" ]
then
    logerror "❌ could not get the type of $connector_type connector $connector from its status"
    exit 1
fi
nb_tasks=$(echo "$status_json" | jq '.tasks | length')
workers=$(echo "$status_json" | jq -r '.tasks[].worker_id' | sort -u | while read -r worker_id; do benchmark_worker_container_and_port "$worker_id"; done | sort -u)

handle_onprem_connect_rest_api "curl -s $security \"$connect_url/connectors/$connector/config\""
connector_class=$(echo "$curl_output" | jq -r '."connector.class"')
connector_config_json="$curl_output"
sink_topics=$(echo "$curl_output" | jq -r '.topics // "" | split(",") | map(gsub("^\\s+|\\s+$"; "")) | join(" ")')
handle_onprem_connect_rest_api "curl -s $security \"$connect_url/connector-plugins\""
plugin_version=$(echo "$curl_output" | jq -r --arg c "$connector_class" '[.[] | select(.class == $c) | .version][0] // "unknown"')
cp_tag=$(get_running_cp_tag)

if [ ${#topics[@]} -eq 0 ] && [ "$type" == "source" ]
then
    handle_onprem_connect_rest_api "curl -s $security \"$connect_url/connectors/$connector/topics\""
    read -ra topics <<< "$(echo "$curl_output" | jq -r --arg c "$connector" '.[$c].topics // [] | join(" ")')"
fi

test_file=$(playground state get run.test_file)
example_dir=""
load_script=""
if [ -n "$test_file" ] && [ -f "$test_file" ]
then
    example_dir=$(dirname "$test_file")
    if [ -f "$example_dir/benchmark-load.bash" ]
    then
        load_script="$example_dir/benchmark-load.bash"
    fi
fi

load_mode="preload"
[ "$mode" == "steady" ] && load_mode="stream"
if [ "$mode" == "drain" ] && [ -n "$load_command" ]
then
    load_cmd="$load_command"
elif [ "$mode" == "steady" ] && [ -n "$stream_load_command" ]
then
    load_cmd="$stream_load_command"
elif [ -n "$load_script" ]
then
    load_cmd="bash \"$load_script\" --records $nb_records --mode $load_mode --shape $shape --record-size $record_size"
else
    load_cmd=""
fi
# load scripts can adapt to the variant of the example that was run (cdb or pdb...)
export BENCHMARK_TEST_FILE="$test_file"
export BENCHMARK_CONNECTOR="$connector"

mkdir -p "$output_dir"
run_id="${connector}-$(date +%Y%m%d-%H%M%S)"
# load scripts can adapt to the connector configuration (a redo log topic doubles the records of oracle cdc...)
export BENCHMARK_CONNECTOR_CONFIG="$output_dir/$run_id-config.json"
# a stream load stops at the end of its current batch when this file exists
export BENCHMARK_STOP_FILE="$output_dir/$run_id.stop"
rm -f "$BENCHMARK_STOP_FILE"
echo "$connector_config_json" > "$BENCHMARK_CONNECTOR_CONFIG"

# a sink without load: replay the 'playground topic produce' of the example script that feeds its topics
if [ -z "$load_cmd" ] && [ "$type" == "sink" ] && [ -n "$test_file" ] && [ -f "$test_file" ]
then
    if [ -z "$sink_topics" ]
    then
        handle_onprem_connect_rest_api "curl -s $security \"$connect_url/connectors/$connector/topics\""
        sink_topics=$(echo "$curl_output" | jq -r --arg c "$connector" '.[$c].topics // [] | join(" ")')
    fi
    replay_stream=""
    [ "$mode" == "steady" ] && replay_stream=1
    replay_file="$output_dir/$run_id-replay.bash"
    set +e
    replay_output=$(benchmark_produce_load_from_example "$test_file" "$sink_topics" "$nb_records" "$record_size" "$replay_file" "$replay_stream")
    replay_ret=$?
    set -e
    if [ $replay_ret -eq 0 ]
    then
        load_cmd="bash \"$replay_file\""
        log "🔁 load: replay of the 'playground topic produce' of $(basename "$test_file") to topic $replay_output"
    elif [ $replay_ret -eq 3 ]
    then
        logerror "❌ cannot replay the produce command of the example: $replay_output, set them or use --load-command"
        exit 1
    fi
fi

if [ -z "$load_cmd" ] && [ "$mode" == "drain" ]
then
    logerror "❌ no load for the drain: the example has no benchmark-load.bash and no 'playground topic produce' to replay, use --load-command"
    exit 1
fi
if [ -z "$load_cmd" ]
then
    logwarn "⚠️ no --stream-load-command, no benchmark-load.bash and no 'playground topic produce' to replay: measuring the connector with the load already running, if any"
fi

csv_file="$output_dir/$run_id.csv"
json_file="$output_dir/$run_id.json"
load_log="$output_dir/$run_id-load.log"
echo "timestamp,elapsed_s,phase,records,rate_records_per_s,batch_avg_ms,running_ratio,cpu_percent_of_one_core,consumer_lag_max,epoch,cpu_percent_of_available,pause_ratio,gc_time_ms,dlq_records,skipped_records,task_records" > "$csv_file"

benchmark_jmx_init "$workers"
paused_by_benchmark=0
load_stopped_early=0
not_running_checks=0
not_running_states=""
load_pid=""
# a load script sourcing scripts/utils.sh records itself as the example being run: put the state back
function restore_run_state () {
    if [ "$(playground state get run.test_file)" != "$test_file" ]
    then
        playground state set run.test_file "$test_file"
    fi
    if [ "$(playground state get run.connector_type)" != "$connector_type" ]
    then
        playground state set run.connector_type "$connector_type"
    fi
}
# the stream load is a tree of processes (bash, playground, docker exec): stop all of them
function kill_tree () {
    local pid="$1" child
    for child in $(pgrep -P "$pid" 2> /dev/null)
    do
        kill_tree "$child"
    done
    # the process can already be gone (a parent exits when its child is killed): not an error
    kill "$pid" 2> /dev/null || true
}
function benchmark_cleanup () {
    restore_run_state
    if [ -n "$load_pid" ] && kill -0 "$load_pid" 2> /dev/null
    then
        # interrupted: give the load a chance to finish its batch before killing it
        touch "$BENCHMARK_STOP_FILE" 2> /dev/null
        for i in 1 2 3 4 5 6 7 8 9 10
        do
            kill -0 "$load_pid" 2> /dev/null || break
            sleep 1
        done
        kill -0 "$load_pid" 2> /dev/null && kill_tree "$load_pid"
    fi
    rm -f "$BENCHMARK_STOP_FILE"
    if [ $paused_by_benchmark -eq 1 ]
    then
        logwarn "⏯️ resuming $connector_type connector $connector paused by the benchmark"
        playground connector resume --connector "$connector" > /dev/null 2>&1
    fi
}
trap benchmark_cleanup EXIT

# fails the benchmark as soon as the connector or one of its tasks is FAILED
function check_not_failed () {
    if ! handle_onprem_connect_rest_api "curl -s $security \"$connect_url/connectors/$connector/status\"" > /dev/null 2>&1
    then
        return
    fi
    if ! echo "$curl_output" | jq -e '[.connector.state, .tasks[]?.state] | all(. == "RUNNING")' > /dev/null 2>&1
    then
        not_running_checks=$((not_running_checks + 1))
        not_running_states=$(echo "$curl_output" | jq -r '"connector \(.connector.state), tasks \([.tasks[]?.state] | join(" "))"')
    fi
    if echo "$curl_output" | jq -e '[.connector.state, .tasks[]?.state] | index("FAILED")' > /dev/null 2>&1
    then
        logerror "❌ $connector_type connector $connector is FAILED, stopping the benchmark"
        set +e
        playground connector status --connector "$connector"
        exit 1
    fi
}

# one sample: appends a csv line and sets sample_records, sample_time
prev_records=""
prev_time=""
function take_sample () {
    local phase="$1"
    local values
    values=$(benchmark_jmx_sample "$connector" "$type" "$workers")
    sample_time=$(now)
    read -r sample_records sample_batch sample_ratio sample_cpu sample_lag sample_cpu_available sample_pause sample_gc sample_dlq sample_skipped sample_tasks <<< "$values"
    local rate="-"
    if [ -n "$prev_records" ]
    then
        rate=$(awk -v r="$sample_records" -v pr="$prev_records" -v t="$sample_time" -v pt="$prev_time" 'BEGIN { if (t > pt) printf "%.1f", (r - pr) / (t - pt); else print "-" }')
    fi
    echo "$(date +%H:%M:%S),$(awk -v t="$sample_time" -v s="$start_time" 'BEGIN { printf "%.1f", t - s }'),$phase,$sample_records,$rate,$sample_batch,$sample_ratio,$sample_cpu,${sample_lag:--},$sample_time,${sample_cpu_available:--},${sample_pause:--},${sample_gc:--},${sample_dlq:--},${sample_skipped:--},${sample_tasks:--}" >> "$csv_file"
    prev_records="$sample_records"
    prev_time="$sample_time"
}

# records per topic, as "<topic> <count>" lines
function count_topic_records () {
    local topic count
    for topic in "${topics[@]}"
    do
        count=$(playground --output-level WARN topic get-number-records --topic "$topic" 2> /dev/null | grep -E '^[0-9]+$' | tail -1)
        echo "$topic ${count:-0}"
    done
}

# a source can create topics during the drain (a new table): read the topics of the connector again
function refresh_connector_topics () {
    if [ -n "${args[--topic]}" ]
    then
        return
    fi
    if handle_onprem_connect_rest_api "curl -s $security \"$connect_url/connectors/$connector/topics\"" > /dev/null 2>&1
    then
        read -ra topics <<< "$(echo "$curl_output" | jq -r --arg c "$connector" '.[$c].topics // [] | join(" ")')"
    fi
}

expected="$nb_records"
load_seconds="-"
topic_records_delta="-"
start_time=$(now)

if [ "$mode" == "drain" ]
then
    log "⏸️ pausing $connector_type connector $connector ($type, $nb_tasks task(s), $connector_class $plugin_version)"
    playground connector pause --connector "$connector" > /dev/null
    paused_by_benchmark=1
    playground connector wait --connector "$connector" --state PAUSED --max-wait 120 --interval 2 > /dev/null

    log "📥 loading the backlog: $load_cmd"
    load_start=$(now)
    set +e
    if [[ -n "$verbose" ]]
    then
        bash -c "$load_cmd" 2>&1 | tee "$load_log" >&2
        load_ret=${PIPESTATUS[0]}
    else
        bash -c "$load_cmd" > "$load_log" 2>&1
        load_ret=$?
    fi
    set -e
    if [ $load_ret -ne 0 ]
    then
        logerror "❌ the load failed with exit code $load_ret, last lines of $load_log:"
        tail -20 "$load_log"
        exit 1
    fi
    load_seconds=$(awk -v e="$(now)" -v s="$load_start" 'BEGIN { printf "%.1f", e - s }')
    restore_run_state
    records_from_load=$(grep -E '^BENCHMARK_RECORDS=[0-9]+$' "$load_log" | tail -1 | cut -d= -f2)
    if [ -n "$records_from_load" ]
    then
        expected="$records_from_load"
    fi
    log "📦 backlog of $expected records loaded in ${load_seconds}s"

    if [ "$type" == "source" ]
    then
        topic_records_before=$(count_topic_records)
    fi

    start_time=$(now)
    take_sample "baseline"
    baseline_records="$sample_records"
    log "⏯️ resuming $connector_type connector $connector and waiting for $expected records (max ${max_wait}s, sample every ${interval}s)"
    start_time=$(now)
    prev_time="$start_time"
    playground connector resume --connector "$connector" > /dev/null
    paused_by_benchmark=0

    end_time=""
    last_logged=0
    while true
    do
        sleep "$interval"
        before_records="$prev_records"
        before_time="$prev_time"
        take_sample "drain"
        processed=$((sample_records - baseline_records))
        elapsed=$(awk -v t="$sample_time" -v s="$start_time" 'BEGIN { printf "%d", t - s }')
        if [ "$processed" -ge "$expected" ]
        then
            # the backlog was processed between the last two samples: interpolate
            end_time=$(awk -v e="$expected" -v b="$baseline_records" -v pr="$before_records" -v r="$sample_records" -v pt="$before_time" -v t="$sample_time" \
                'BEGIN { done_before = pr - b; if (r > pr) printf "%.3f", pt + (e - done_before) / (r - pr) * (t - pt); else printf "%.3f", t }')
            break
        fi
        if [ $((elapsed - last_logged)) -ge 30 ]
        then
            log "⌛ $processed/$expected records after ${elapsed}s"
            last_logged=$elapsed
        fi
        check_not_failed
        if [ "$elapsed" -ge "$max_wait" ]
        then
            logerror "❌ only $processed/$expected records processed after ${max_wait}s"
            playground connector status --connector "$connector"
            exit 1
        fi
    done
    measured_seconds=$(awk -v e="$end_time" -v s="$start_time" 'BEGIN { printf "%.1f", e - s }')
    measured_records="$expected"
    if [ "$type" == "source" ]
    then
        refresh_connector_topics
        if [ ${#topics[@]} -gt 0 ]
        then
            # topics created during the drain count from 0
            topic_records_delta=$(awk 'NR == FNR { before[$1] = $2; next } { delta += $2 - before[$1] } END { print delta + 0 }' \
                <(echo "$topic_records_before") <(count_topic_records))
        fi
    fi
else
    if [ -n "$load_cmd" ]
    then
        log "🌊 starting the load in the background: $load_cmd"
        bash -c "$load_cmd" > "$load_log" 2>&1 &
        load_pid=$!
    fi
    log "🔥 warm-up for ${warmup}s"
    take_sample "warmup"
    warmup_end=$(awk -v s="$start_time" -v w="$warmup" 'BEGIN { printf "%.3f", s + w }')
    while awk -v n="$(now)" -v e="$warmup_end" 'BEGIN { exit !(n < e) }'
    do
        sleep "$interval"
        take_sample "warmup"
        check_not_failed
    done
    baseline_records="$sample_records"
    measure_start="$sample_time"
    not_running_checks=0
    log "⏱️ measuring for ${duration}s (sample every ${interval}s)"
    measure_end=$(awk -v s="$measure_start" -v d="$duration" 'BEGIN { printf "%.3f", s + d }')
    while awk -v n="$(now)" -v e="$measure_end" 'BEGIN { exit !(n < e) }'
    do
        sleep "$interval"
        take_sample "steady"
        check_not_failed
    done
    if [ -n "$load_pid" ]
    then
        if kill -0 "$load_pid" 2> /dev/null
        then
            # let the load finish its current batch: killing a producer in the middle of a batch can send a truncated record
            log "🛑 stopping the load at the end of its current batch"
            touch "$BENCHMARK_STOP_FILE"
            stop_wait=0
            while kill -0 "$load_pid" 2> /dev/null && [ $stop_wait -lt 120 ]
            do
                sleep 1
                stop_wait=$((stop_wait + 1))
            done
            if kill -0 "$load_pid" 2> /dev/null
            then
                logwarn "⚠️ the load did not stop after 120s, killing it"
                kill_tree "$load_pid"
            fi
        else
            logwarn "⚠️ the load stopped before the end of the measure, see $load_log"
            load_stopped_early=1
        fi
        load_pid=""
    fi
    measured_records=$((sample_records - baseline_records))
    measured_seconds=$(awk -v e="$sample_time" -v s="$measure_start" 'BEGIN { printf "%.1f", e - s }')
fi

# summary from the samples of the measure (drain or steady phase)
phase="$mode"
read -r rate_p50 rate_p95 rate_min batch_avg ratio_avg cpu_avg cpu_max <<< "$(awk -F, -v p="$phase" '
    NR > 1 && $3 == p {
        if ($5 != "-") rates[n++] = $5
        if ($6 != "-") { batch += $6; nb++ }
        if ($7 != "-") { ratio += $7; nr++ }
        if ($8 != "-") { cpu += $8; nc++; if ($8 > cpumax) cpumax = $8 }
    }
    END {
        # insertion sort, a few hundred samples at most
        for (i = 1; i < n; i++) { v = rates[i]; j = i - 1; while (j >= 0 && rates[j] > v) { rates[j + 1] = rates[j]; j-- } rates[j + 1] = v }
        printf "%s %s %s %s %s %s %s\n",
            (n ? rates[int((n - 1) * 0.5)] : "-"), (n ? rates[int((n - 1) * 0.95)] : "-"), (n ? rates[0] : "-"),
            (nb ? sprintf("%.1f", batch / nb) : "-"), (nr ? sprintf("%.2f", ratio / nr) : "-"),
            (nc ? sprintf("%.0f", cpu / nc) : "-"), (nc ? sprintf("%.0f", cpumax) : "-")
    }' "$csv_file")"
throughput=$(awk -v r="$measured_records" -v s="$measured_seconds" 'BEGIN { if (s > 0) printf "%.1f", r / s; else print "0" }')
nb_samples=$(awk -F, -v p="$phase" 'NR > 1 && $3 == p' "$csv_file" | wc -l | tr -d ' ')
# the backlog was processed before the first sample: only an upper bound of the duration is known
lower_bound=false
if [ "$mode" == "drain" ] && [ "$nb_samples" -le 1 ]
then
    lower_bound=true
fi

# bottleneck indicators over the measure: from the sample just before the measure to the last one of the measure
# (cumulative gc time, dlq and skipped records, records per task), and averages over the samples of the measure
read -r gc_percent cpu_available_avg pause_avg dlq_delta skipped_delta task_shares max_task_share idle_tasks <<< "$(awk -F, -v p="$phase" -v nw="$(echo "$workers" | grep -c .)" '
    NR == 1 { next }
    $3 != p && !started { ref = $0; next }
    $3 == p {
        started = 1; last = $0
        if ($11 != "-") { cpu += $11; nc++ }
        if ($12 != "-") { pause += $12; np++ }
    }
    END {
        split(ref, r, ","); split(last, l, ",")
        gc = "-"
        if (r[13] != "-" && l[13] != "-" && l[10] > r[10] && nw > 0) gc = sprintf("%.1f", (l[13] - r[13]) / ((l[10] - r[10]) * 1000 * nw) * 100)
        dlq = (r[14] != "-" && l[14] != "-") ? l[14] - r[14] : "-"
        skipped = (r[15] != "-" && l[15] != "-") ? l[15] - r[15] : "-"
        # records per task during the measure
        nt = split(l[16], lt, ";"); split(r[16], rt, ";")
        for (i in rt) { split(rt[i], kv, ":"); before[kv[1]] = kv[2] }
        total = 0
        for (i = 1; i <= nt; i++) { split(lt[i], kv, ":"); d[kv[1]] = kv[2] - before[kv[1]]; total += d[kv[1]]; ids[i] = kv[1] }
        shares = "-"; maxshare = 0; idle = 0
        if (nt > 1 && total > 0) {
            shares = ""
            for (i = 1; i <= nt; i++) {
                s = d[ids[i]] / total
                shares = shares (shares ? "," : "") "task " ids[i] " " sprintf("%.0f%%", s * 100)
                if (s > maxshare) maxshare = s
                if (d[ids[i]] == 0) idle++
            }
            gsub(/ /, "_", shares)
        }
        printf "%s %s %s %s %s %s %.2f %d\n", gc, (nc ? sprintf("%.0f", cpu / nc) : "-"), (np ? sprintf("%.2f", pause / np) : "-"),
            dlq, skipped, shares, maxshare, idle
    }' "$csv_file")"
# total-records-skipped also counts the records sent to the dlq: keep the ones dropped without a dlq
if [ "$dlq_delta" != "-" ] && [ "$skipped_delta" != "-" ]
then
    skipped_delta=$((skipped_delta - dlq_delta))
fi
task_shares="${task_shares//_/ }"
task_shares="${task_shares//,/, }"

test_file_relative="${test_file#$root_folder/}"
result=$(jq -n \
    --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg test_file "$test_file_relative" --arg connector "$connector" \
    --arg connector_class "$connector_class" --arg plugin_version "$plugin_version" --arg cp_tag "$cp_tag" \
    --arg type "$type" --arg mode "$mode" --arg shape "$shape" --argjson tasks "$nb_tasks" \
    --argjson records "$measured_records" --argjson seconds "$measured_seconds" --argjson records_per_second "$throughput" \
    --arg rate_p50 "$rate_p50" --arg rate_p95 "$rate_p95" --arg rate_min "$rate_min" \
    --arg batch_avg_ms "$batch_avg" --arg running_ratio "$ratio_avg" --arg cpu_avg "$cpu_avg" --arg cpu_max "$cpu_max" \
    --arg load_seconds "$load_seconds" --arg topic_records_delta "$topic_records_delta" \
    --arg samples_csv "$csv_file" --argjson lower_bound "$lower_bound" \
    --arg gc_percent "$gc_percent" --arg cpu_available_avg "$cpu_available_avg" --arg pause_ratio "$pause_avg" \
    --arg dlq_records "$dlq_delta" --arg skipped_records "$skipped_delta" --arg task_shares "$task_shares" \
    '{date: $date, test_file: $test_file, connector: $connector, connector_class: $connector_class, plugin_version: $plugin_version,
      cp_tag: $cp_tag, type: $type, mode: $mode, shape: $shape, tasks: $tasks, records: $records, seconds: $seconds,
      records_per_second: $records_per_second, lower_bound: $lower_bound, rate_p50: $rate_p50, rate_p95: $rate_p95, rate_min: $rate_min,
      batch_avg_ms: $batch_avg_ms, running_ratio: $running_ratio, cpu_percent_of_one_core_avg: $cpu_avg,
      cpu_percent_of_one_core_max: $cpu_max, load_seconds: $load_seconds, topic_records_delta: $topic_records_delta,
      gc_percent: $gc_percent, cpu_percent_of_available_avg: $cpu_available_avg, pause_ratio: $pause_ratio,
      dlq_records: $dlq_records, skipped_records: $skipped_records, task_shares: $task_shares,
      samples_csv: $samples_csv}')
echo "$result" > "$json_file"

# previous result to compare with: --compare, or the last one of the same connector, example, mode and shape
history_file="$root_folder/benchmark-history"
previous=""
if [ -n "$compare_file" ]
then
    previous=$(jq -c . "$compare_file")
elif [ -f "$history_file" ]
then
    # lower bounds are not comparable
    previous=$(jq -c --arg t "$test_file_relative" --arg c "$connector" --arg m "$mode" --arg s "$shape" 'select(.test_file == $t and .connector == $c and .mode == $m and .shape == $s and .lower_bound != true and .records > 0)' "$history_file" 2> /dev/null | tail -1)
fi
if [[ ! -n "$no_history" ]]
then
    echo "$result" | jq -c . >> "$history_file"
fi

if [[ -n "$json" ]]
then
    if [ -n "$previous" ]
    then
        echo "$result" | jq --argjson p "$previous" '. + {previous: $p}' >&3
    else
        echo "$result" >&3
    fi
    exit 0
fi

log "🏁 benchmark of $connector_type connector $connector ($type, $nb_tasks task(s), $connector_class $plugin_version, CP $cp_tag)"
if [ "$mode" == "drain" ]
then
    printf "   %-22s %s\n" "mode" "drain of $measured_records records (shape $shape, loaded in ${load_seconds}s)"
else
    printf "   %-22s %s\n" "mode" "steady for ${measured_seconds}s after ${warmup}s of warm-up"
fi
printf "   %-22s %s\n" "duration" "${measured_seconds}s"
if [ "$lower_bound" == "true" ]
then
    printf "   %-22s %s\n" "throughput" "≥ $throughput records/s   (the backlog was processed before the first sample)"
else
    printf "   %-22s %s\n" "throughput" "$throughput records/s   (per ${interval}s sample: p50 $rate_p50  p95 $rate_p95  min $rate_min)"
fi
if [ "$type" == "sink" ]
then
    printf "   %-22s %s\n" "put batch avg" "$batch_avg ms"
else
    printf "   %-22s %s\n" "poll batch avg" "$batch_avg ms"
fi
printf "   %-22s %s\n" "running ratio avg" "$ratio_avg"
printf "   %-22s %s\n" "connect cpu avg / max" "${cpu_avg}% / ${cpu_max}% of one core (${cpu_available_avg}% of the cpus available)"
printf "   %-22s %s\n" "gc pauses" "${gc_percent}% of the time"
if [ "$task_shares" != "-" ]
then
    printf "   %-22s %s\n" "records per task" "$task_shares"
fi
if [ "$dlq_delta" != "-" ] && [ "$dlq_delta" != "0" ] || { [ "$skipped_delta" != "-" ] && [ "$skipped_delta" != "0" ]; }
then
    printf "   %-22s %s\n" "dlq / dropped" "$dlq_delta records sent to the dlq, $skipped_delta dropped without dlq"
fi
if [ "$topic_records_delta" != "-" ]
then
    printf "   %-22s %s\n" "records in topics" "+$topic_records_delta (${topics[*]})"
fi
if [ -n "$previous" ]
then
    previous_throughput=$(echo "$previous" | jq -r '.records_per_second')
    delta=$(awk -v n="$throughput" -v p="$previous_throughput" 'BEGIN { if (p > 0) printf "%+.0f%%", (n - p) / p * 100; else print "n/a" }')
    printf "   %-22s %s\n" "previous run" "$previous_throughput records/s on $(echo "$previous" | jq -r '.date'): $delta"
    printf "   %-22s %s\n" "" "($(echo "$previous" | jq -r '"\(.plugin_version), CP \(.cp_tag), \(.tasks) task(s), \(.records) records, shape \(.shape)"'))"
fi

# warnings of the summary, also shown in the html report
report_warnings=()
function add_warning () {
    logwarn "⚠️ $1"
    report_warnings+=("$1")
}
if [ "$load_stopped_early" == "1" ]
then
    report_warnings+=("the load stopped before the end of the measure, see $load_log")
fi
if [ "$not_running_checks" -gt 0 ]
then
    add_warning "the connector or its tasks were not RUNNING at $not_running_checks status check(s) during the measure (last seen: $not_running_states): paused, restarting or rebalancing"
# running and pause ratios are averaged over a window of up to a minute, so an earlier pause (a previous drain) still
# shows in a short measure: only use them for a steady measure of 2 minutes or more
elif [ "$mode" == "steady" ] && awk -v s="$measured_seconds" 'BEGIN { exit !(s >= 120) }' && { { [ "$ratio_avg" != "-" ] && awk -v r="$ratio_avg" 'BEGIN { exit !(r < 0.5) }'; } || { [ "$pause_avg" != "-" ] && awk -v r="$pause_avg" 'BEGIN { exit !(r > 0.2) }'; }; }
then
    add_warning "the tasks are paused or idle most of the time (running ratio $ratio_avg, pause ratio $pause_avg): restarts, rebalances or a paused connector"
fi
if [ "$cpu_available_avg" != "-" ] && [ "$cpu_available_avg" -ge 90 ]
then
    add_warning "the connect worker is CPU bound (${cpu_available_avg}% of the cpus available to it): the results reflect the docker host"
fi
if [ "$gc_percent" != "-" ] && awk -v g="$gc_percent" 'BEGIN { exit !(g > 10) }'
then
    add_warning "the connect worker spent ${gc_percent}% of the time in gc pauses: the results reflect its heap size (KAFKA_HEAP_OPTS), not the connector"
fi
if [ "$task_shares" != "-" ] && { [ "$idle_tasks" -gt 0 ] || awk -v m="$max_task_share" -v n="$nb_tasks" 'BEGIN { t = 1.5 / n; if (t < 0.6) t = 0.6; exit !(m >= t) }'; }
then
    add_warning "the records are not spread across the tasks ($task_shares): tasks.max greater than the number of partitions, key skew, or a connector that does not parallelize this load"
fi
if [ "$dlq_delta" != "-" ] && [ "$dlq_delta" -gt 0 ]
then
    add_warning "$dlq_delta records went to the dead letter queue during the run: they are counted in the throughput"
fi
if [ "$skipped_delta" != "-" ] && [ "$skipped_delta" -gt 0 ]
then
    add_warning "$skipped_delta records were dropped by errors.tolerance=all without a dead letter queue during the run: they are counted in the throughput"
fi
if [ "$mode" == "steady" ] && [ "$rate_min" != "-" ] && [ "$rate_p50" != "-" ] && awk -v m="$rate_min" -v p="$rate_p50" 'BEGIN { exit !(p > 0 && m < p * 0.2) }'
then
    add_warning "the throughput dropped to $rate_min records/s at least once (p50 $rate_p50): stalls, rebalances or a load that does not keep up"
fi
if [ "$lower_bound" == "true" ]
then
    add_warning "the backlog was processed before the first sample, the throughput is a lower bound: increase --nb-records (10x) for a real measure"
elif [ "$nb_samples" -lt 3 ]
then
    add_warning "only $nb_samples samples during the measure: the percentiles are not meaningful, increase --nb-records (or --duration) or reduce --interval"
fi
# steady mode measures the load as much as the connector: detect when the connector simply kept up with it
if [ "$mode" == "steady" ] && [ "$measured_records" -gt 0 ]
then
    generated=0
    if [ -f "$load_log" ]
    then
        # records generated by the stream load during the measure, from its BENCHMARK_BATCH=<records> <epoch> lines
        # a batch is counted when it ends: allow one batch of difference at the edges of the measure
        read -r generated largest_batch <<< "$(awk -v s="$measure_start" -v e="$sample_time" '/^BENCHMARK_BATCH=/ { split($1, kv, "="); if (kv[2] > b) b = kv[2]; if ($2 >= s && $2 <= e) g += kv[2] } END { print g + 0, b + 0 }' "$load_log")"
    fi
    if [ "$generated" -gt 0 ] && awk -v m="$measured_records" -v g="$generated" -v b="${largest_batch:-0}" 'BEGIN { exit !(m >= 0.9 * g || m >= g - b) }'
    then
        add_warning "the connector kept up with the load ($measured_records records processed, $generated generated during the measure): this is the speed of the load, not of the connector, use --mode drain to measure its maximum"
    elif [ "$type" == "sink" ]
    then
        # a sink that keeps up never has more than a few records waiting in its topics
        lag_peak=$(awk -F, -v p="$phase" 'NR > 1 && $3 == p && $9 != "-" { if ($9 > m) m = $9; n++ } END { if (n) print m + 0 }' "$csv_file")
        per_interval=$(awk -v t="$throughput" -v i="$interval" 'BEGIN { printf "%d", t * i }')
        if [ -n "$lag_peak" ] && [ "$lag_peak" -le "$per_interval" ]
        then
            add_warning "the connector kept up with the load (consumer lag peak $lag_peak records, less than one ${interval}s sample of records): this is the speed of the load, not of the connector, use --mode drain to measure its maximum"
        fi
    fi
fi
if [ "$mode" == "steady" ] && [ "$measured_records" -eq 0 ]
then
    add_warning "no record was processed during the measure: is there any load?"
fi
logwarn "⚠️ results are relative to this docker host: compare runs on the same machine only"
log "📄 samples: $csv_file"
log "📄 result: $json_file"

html_file="$output_dir/$run_id.html"
report_args=(--result "$json_file" --samples "$csv_file" --history "$history_file" --output "$html_file")
for warning in "${report_warnings[@]}"
do
    report_args+=(--warning "$warning")
done
if python3 -I "$root_folder/tools/benchmark-report/benchmark_report.py" "${report_args[@]}" > /dev/null
then
    log "📊 report: $html_file"
    # only open a browser in an interactive terminal, never in CI
    if [[ -t 1 ]] && [ -z "$GITHUB_RUN_NUMBER" ]
    then
        if command -v open > /dev/null 2>&1
        then
            open "$html_file"
        elif command -v xdg-open > /dev/null 2>&1
        then
            xdg-open "$html_file" > /dev/null 2>&1 || true
        fi
    fi
else
    logwarn "⚠️ the html report could not be generated"
fi
