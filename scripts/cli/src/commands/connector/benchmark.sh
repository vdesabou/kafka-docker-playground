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
echo "$connector_config_json" > "$BENCHMARK_CONNECTOR_CONFIG"

# a sink without load: replay the 'playground topic produce' of the example script that feeds its topics
if [ -z "$load_cmd" ] && [ "$type" == "sink" ] && [ -n "$test_file" ] && [ -f "$test_file" ]
then
    if [ -z "$sink_topics" ]
    then
        handle_onprem_connect_rest_api "curl -s $security \"$connect_url/connectors/$connector/topics\""
        sink_topics=$(echo "$curl_output" | jq -r --arg c "$connector" '.[$c].topics // [] | join(" ")')
    fi
    replay_nb="$nb_records"
    [ "$mode" == "steady" ] && replay_nb=-1
    replay_file="$output_dir/$run_id-replay.bash"
    set +e
    replay_output=$(benchmark_produce_load_from_example "$test_file" "$sink_topics" "$replay_nb" "$record_size" "$replay_file")
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
echo "timestamp,elapsed_s,phase,records,rate_records_per_s,batch_avg_ms,running_ratio,cpu_percent_of_one_core" > "$csv_file"

benchmark_jmx_init "$workers"
paused_by_benchmark=0
load_stopped_early=0
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
    kill "$pid" 2> /dev/null
}
function benchmark_cleanup () {
    restore_run_state
    if [ -n "$load_pid" ] && kill -0 "$load_pid" 2> /dev/null
    then
        kill_tree "$load_pid"
    fi
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
    read -r sample_records sample_batch sample_ratio sample_cpu <<< "$values"
    local rate="-"
    if [ -n "$prev_records" ]
    then
        rate=$(awk -v r="$sample_records" -v pr="$prev_records" -v t="$sample_time" -v pt="$prev_time" 'BEGIN { if (t > pt) printf "%.1f", (r - pr) / (t - pt); else print "-" }')
    fi
    echo "$(date +%H:%M:%S),$(awk -v t="$sample_time" -v s="$start_time" 'BEGIN { printf "%.1f", t - s }'),$phase,$sample_records,$rate,$sample_batch,$sample_ratio,$sample_cpu" >> "$csv_file"
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
            kill_tree "$load_pid"
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
    '{date: $date, test_file: $test_file, connector: $connector, connector_class: $connector_class, plugin_version: $plugin_version,
      cp_tag: $cp_tag, type: $type, mode: $mode, shape: $shape, tasks: $tasks, records: $records, seconds: $seconds,
      records_per_second: $records_per_second, lower_bound: $lower_bound, rate_p50: $rate_p50, rate_p95: $rate_p95, rate_min: $rate_min,
      batch_avg_ms: $batch_avg_ms, running_ratio: $running_ratio, cpu_percent_of_one_core_avg: $cpu_avg,
      cpu_percent_of_one_core_max: $cpu_max, load_seconds: $load_seconds, topic_records_delta: $topic_records_delta,
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
printf "   %-22s %s\n" "connect cpu avg / max" "${cpu_avg}% / ${cpu_max}% of one core"
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
if [ "$ratio_avg" != "-" ] && awk -v r="$ratio_avg" 'BEGIN { exit !(r < 0.5) }'
then
    add_warning "the tasks were running only $ratio_avg of the time (paused or restarting)"
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
