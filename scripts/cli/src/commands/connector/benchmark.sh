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
eval "connector_tags=(${args[--connector-tag]:-})"
rounds="${args[--rounds]}"
no_flight_recorder="${args[--no-flight-recorder]}"
sessions="${args[--sessions]}"

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
    if [ "$state" == "PAUSED" ] || [ "$state" == "STOPPED" ]
    then
        log "💡 resume it with: playground connector resume --connector $connector"
    fi
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

# --shape: one shape, or a sequence of shapes (bulk,update,delete) run one after the other on the same rows
IFS=',' read -ra shapes <<< "$shape"
for phase_shape in "${shapes[@]}"
do
    case "$phase_shape" in
        bulk|small-txn|update|delete) ;;
        *) logerror "❌ --shape $phase_shape: use bulk, small-txn, update or delete (or a sequence, e.g. bulk,update,delete)"; exit 1 ;;
    esac
done

# --shape a,b,c: one drain per shape (child runs of this command) on the same rows, then the phases are compared
if [ ${#shapes[@]} -gt 1 ] && [ -z "$BENCHMARK_MATRIX_CHILD" ]
then
    if [ ${#connector_tags[@]} -gt 0 ] || [ "$mode" != "drain" ] || [ "$type" != "source" ] || [ -n "$load_command" ]
    then
        logerror "❌ a --shape sequence is a series of drains of the load script of a source connector: not with --connector-tag, --mode steady, a sink connector or --load-command"
        exit 1
    fi
    mkdir -p "$output_dir"
    sequence_id="${connector}-sequence-$(date +%Y%m%d-%H%M%S)"
    sequence_results="$output_dir/$sequence_id.results"
    : > "$sequence_results"
    child_args=(--connector "$connector" --mode drain --nb-records "$nb_records" --record-size "$record_size"
        --interval "${args[--interval]}" --max-wait "${args[--max-wait]}" --output-dir "$output_dir" --sessions "$sessions")
    for topic in "${topics[@]}"
    do
        child_args+=(--topic "$topic")
    done
    [ -n "$no_history" ] && child_args+=(--no-history)
    [ -n "$no_flight_recorder" ] && child_args+=(--no-flight-recorder)
    [ -n "$verbose" ] && child_args+=(--verbose)
    log "🔁 sequence of ${#shapes[@]} drains of $nb_records records on $connector: ${shape//,/ → }"
    sequence_failed=0
    phase=0
    for phase_shape in "${shapes[@]}"
    do
        phase=$((phase + 1))
        log "🏁 phase $phase/${#shapes[@]}: --shape $phase_shape"
        if ! BENCHMARK_MATRIX_CHILD=1 BENCHMARK_NO_OPEN=1 BENCHMARK_MATRIX_RESULTS="$sequence_results" playground connector benchmark "${child_args[@]}" --shape "$phase_shape"
        then
            logerror "❌ phase $phase (--shape $phase_shape) failed"
            sequence_failed=1
            break
        fi
    done
    if [ ! -s "$sequence_results" ]
    then
        logerror "❌ no phase could be benchmarked"
        exit 1
    fi
    log "🏁 sequence of $connector_class ($connector): ${shape//,/ → }"
    xargs cat < "$sequence_results" | jq -s -r '
        def r1: if . == null then "-" else (. * 10 | round) / 10 | tostring end;
        (["phase", "shape", "records", "seconds", "records/s"] | @tsv),
        (to_entries[] | [(.key + 1), .value.shape, .value.records, .value.seconds,
            ((if .value.lower_bound == true then "≥ " else "" end) + (.value.records_per_second | r1))] | @tsv)' \
        | column -t -s $'\t' | sed 's/^/   /'
    html_file="$output_dir/$sequence_id.html"
    if python3 -I "$root_folder/tools/benchmark-report/benchmark_report.py" --runs $(cat "$sequence_results") --group-by shape --output "$html_file" > /dev/null
    then
        log "📊 report: $html_file"
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
    logwarn "⚠️ results are relative to this docker host: compare runs on the same machine only"
    [ $sequence_failed -eq 1 ] && exit 1
    exit 0
fi

# --connector-tag: benchmark each version (child runs of this command), compare them, restore the original version
if [ ${#connector_tags[@]} -gt 0 ] && [ -z "$BENCHMARK_MATRIX_CHILD" ]
then
    test_file=$(playground state get run.test_file)
    original_version="$plugin_version"
    original_value=$(benchmark_connector_tag_value "$connector_class" "$original_version")
    if [ -z "$original_value" ]
    then
        logerror "❌ could not find the confluent hub plugin of $connector_class in the example (CONNECT_PLUGIN_PATH of its docker compose file): --connector-tag needs a connector installed from confluent hub"
        exit 1
    fi
    mkdir -p "$output_dir"
    matrix_id="${connector}-versions-$(date +%Y%m%d-%H%M%S)"
    matrix_results="$output_dir/$matrix_id.results"
    : > "$matrix_results"
    # same benchmark in each child run
    child_args=(--connector "$connector" --mode "$mode" --nb-records "$nb_records" --shape "$shape" --record-size "$record_size"
        --duration "${args[--duration]}" --warmup "${args[--warmup]}" --interval "${args[--interval]}" --max-wait "${args[--max-wait]}" --output-dir "$output_dir")
    [ -n "$load_command" ] && child_args+=(--load-command "$load_command")
    [ -n "$stream_load_command" ] && child_args+=(--stream-load-command "$stream_load_command")
    for topic in "${topics[@]}"
    do
        child_args+=(--topic "$topic")
    done
    [ -n "$no_history" ] && child_args+=(--no-history)
    [ -n "$no_flight_recorder" ] && child_args+=(--no-flight-recorder)
    child_args+=(--sessions "$sessions")
    [ -n "$verbose" ] && child_args+=(--verbose)

    function switch_connector_version () {
        local version="$1" value
        value=$(benchmark_connector_tag_value "$connector_class" "$version")
        log "🧩 switching the plugin of $connector_class to $version (playground update-version --connector-tag $value)"
        if ! playground update-version --connector-tag "$value" > "$output_dir/$matrix_id-update-$version.log" 2>&1
        then
            logerror "❌ playground update-version --connector-tag $value failed, see $output_dir/$matrix_id-update-$version.log"
            return 1
        fi
        if ! playground connector wait --connector "$connector" --max-wait 300 > /dev/null 2>&1
        then
            logerror "❌ $connector_type connector $connector is not RUNNING with version $version"
            playground connector status --connector "$connector"
            return 1
        fi
        get_connect_url_and_security
        handle_onprem_connect_rest_api "curl -s $security \"$connect_url/connector-plugins\""
        running_version=$(echo "$curl_output" | jq -r --arg c "$connector_class" '[.[] | select(.class == $c) | .version][0] // "unknown"')
        if [ "$running_version" != "$version" ]
        then
            logerror "❌ the connect worker runs $connector_class $running_version, not the requested $version"
            return 1
        fi
    }
    function restore_original_version () {
        get_connect_url_and_security
        handle_onprem_connect_rest_api "curl -s $security \"$connect_url/connector-plugins\""
        if [ "$(echo "$curl_output" | jq -r --arg c "$connector_class" '[.[] | select(.class == $c) | .version][0] // empty')" == "$original_version" ]
        then
            log "🧩 $connector_class is already at its original version $original_version"
            return
        fi
        log "🧩 restoring the original version $original_version"
        switch_connector_version "$original_version" || logwarn "⚠️ could not restore $connector_class $original_version: run playground update-version --connector-tag $original_value"
    }

    nb_versions=${#connector_tags[@]}
    log "🏎️ benchmark of $connector_class versions ${connector_tags[*]} ($rounds round(s), currently $original_version)"
    matrix_failed=0
    for ((round = 1; round <= rounds; round++))
    do
        for version in "${connector_tags[@]}"
        do
            log "🏁 version $version, round $round/$rounds"
            if ! switch_connector_version "$version"
            then
                matrix_failed=1
                break 2
            fi
            if [ "$mode" == "drain" ]
            then
                # the worker jvm was restarted: an untimed drain first
                warmup_records=$(( nb_records / 10 > 10000 ? nb_records / 10 : 10000 ))
                log "🔥 warm-up drain of $warmup_records records (not recorded)"
                BENCHMARK_MATRIX_CHILD=1 BENCHMARK_NO_OPEN=1 playground connector benchmark "${child_args[@]}" --nb-records "$warmup_records" --no-history --no-flight-recorder > "$output_dir/$matrix_id-warmup-$version-$round.log" 2>&1 || true
            fi
            if ! BENCHMARK_MATRIX_CHILD=1 BENCHMARK_NO_OPEN=1 BENCHMARK_MATRIX_RESULTS="$matrix_results" playground connector benchmark "${child_args[@]}"
            then
                logerror "❌ the benchmark of version $version failed"
                matrix_failed=1
                break 2
            fi
        done
    done
    restore_original_version

    if [ ! -s "$matrix_results" ]
    then
        logerror "❌ no version could be benchmarked"
        exit 1
    fi
    # comparison of the versions: mean per version, delta with the first version
    log "🏁 comparison of $connector_class versions ($connector, $mode, shape $shape)"
    xargs cat < "$matrix_results" | jq -s -r '
        group_by(.plugin_version) as $groups
        | [ $groups[] | (map(select(.lower_bound != true) | .records_per_second)) as $r
            | {version: .[0].plugin_version, runs: length, lower_bounds: (map(select(.lower_bound == true)) | length),
               mean: (if ($r | length) > 0 then ($r | add / length) else null end), min: ($r | min), max: ($r | max)} ] as $v
        | ($v | map(select(.mean != null) | .mean) | .[0]) as $first
        | def r1: if . == null then "-" else (. * 10 | round) / 10 | tostring end;
          (["version", "runs", "lower bounds", "records/s (mean)", "min", "max", "vs first"] | @tsv),
          ($v[] | [.version, .runs, .lower_bounds, (.mean | r1), (.min | r1), (.max | r1),
                   (if $first != null and $first > 0 and .mean != null then (((.mean - $first) / $first * 100) | round | tostring) + "%" else "-" end)] | @tsv)' \
        | column -t -s $'\t' | sed 's/^/   /'
    # grafana: one link over all the runs of the comparison, each run is annotated with its version
    grafana_link=$(xargs cat < "$matrix_results" | jq -s -r 'map(select(.grafana.enabled == true)) | if length > 0 then
        "\(.[0].grafana.dashboards[0].uid) \(map(.measure_from_ms) | min) \(map(.measure_to_ms) | max)" else empty end')
    if [ -n "$grafana_link" ]
    then
        read -r grafana_uid grafana_from grafana_to <<< "$grafana_link"
        log "📊 grafana (each run is annotated with its version): $(benchmark_grafana_url "$grafana_uid" "$grafana_from" "$grafana_to")"
    fi
    html_file="$output_dir/$matrix_id.html"
    if python3 -I "$root_folder/tools/benchmark-report/benchmark_report.py" --runs $(cat "$matrix_results") --output "$html_file" > /dev/null
    then
        log "📊 report: $html_file"
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
    logwarn "⚠️ results are relative to this docker host: compare runs on the same machine only"
    [ $matrix_failed -eq 1 ] && exit 1
    exit 0
fi

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
    load_script=$(benchmark_load_script "$test_file") || exit 1
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
    if [ -n "$BENCHMARK_LOAD_SCRIPT" ]
    then
        log "📥 load: $(basename "$load_script") (BENCHMARK_LOAD_SCRIPT)"
    fi
else
    load_cmd=""
fi
# load scripts can adapt to the variant of the example that was run (cdb or pdb...)
export BENCHMARK_TEST_FILE="$test_file"
export BENCHMARK_CONNECTOR="$connector"

mkdir -p "$output_dir"
run_id="${connector}-$(date +%Y%m%d-%H%M%S)"
# a benchmark-load.bash validates the combination (shape, mode, connector config) before the connector is paused
if [ -n "$load_script" ] && [[ "$load_cmd" == "bash \"$load_script\""* ]]
then
    load_check_config="$output_dir/$run_id-check-config.json"
    echo "$connector_config_json" > "$load_check_config"
    set +e
    load_check_output=$(BENCHMARK_CONNECTOR_CONFIG="$load_check_config" BENCHMARK_TEST_FILE="$test_file" BENCHMARK_CONNECTOR="$connector" bash -c "$load_cmd --check" 2>&1)
    load_check_ret=$?
    set -e
    rm -f "$load_check_config"
    if [ $load_check_ret -ne 0 ]
    then
        echo "$load_check_output" | grep -v '^$' | tail -5
        exit 1
    fi
fi
# --sessions: the load script runs in <sessions> parallel sessions, in one bash process (the load pid of the
# benchmark), sharing the stop file; a drain splits --nb-records between them, a stream gives each one batches of
# --nb-records
if [ "$sessions" -gt 1 ]
then
    if [ -z "$load_script" ] || [[ "$load_cmd" != "bash \"$load_script\""* ]]
    then
        logerror "❌ --sessions needs the benchmark-load.bash of the example: it cannot split --load-command, --stream-load-command or a replayed produce"
        exit 1
    fi
    per_session=$nb_records
    [ "$load_mode" == "preload" ] && per_session=$((nb_records / sessions))
    sessions_cmd="rc=0; pids=''"
    for ((session = 1; session <= sessions; session++))
    do
        session_records=$per_session
        [ "$load_mode" == "preload" ] && [ $session -eq 1 ] && session_records=$((per_session + nb_records - per_session * sessions))
        sessions_cmd="$sessions_cmd; bash \"$load_script\" --records $session_records --mode $load_mode --shape $shape --record-size $record_size & pids=\"\$pids \$!\""
    done
    load_cmd="$sessions_cmd; for p in \$pids; do wait \$p || rc=\$?; done; exit \$rc"
fi
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
    if [ -n "$jfr_recordings" ]
    then
        jfr_jmx_discard "$jfr_recordings"
    fi
    if [ $paused_by_benchmark -eq 1 ]
    then
        logwarn "⏯️ resuming $connector_type connector $connector paused by the benchmark"
        playground connector resume --connector "$connector" > /dev/null 2>&1
        playground connector wait --connector "$connector" --max-wait 60 --interval 2 > /dev/null 2>&1 || logwarn "⚠️ $connector_type connector $connector is not RUNNING again after 60s"
    fi
}
trap benchmark_cleanup EXIT

# flight recorder of the workers during the measure, over JMX (no jcmd in the cp images, no restart)
# jfr_status: disabled (--no-flight-recorder), unavailable (could not start: no overhead), recorded, failed (recorded,
# but not copied or not analyzed)
jfr_recordings=""
jfr_files=""
jfr_status="disabled"
function start_flight_recorder () {
    if [ -n "$no_flight_recorder" ]
    then
        return
    fi
    if jfr_recordings=$(jfr_jmx_start "$workers")
    then
        jfr_status="recorded"
        log "🛩️ flight recorder started on $(echo "$workers" | awk '{ print $1 }' | xargs) for the measure (--no-flight-recorder to disable it)"
    else
        jfr_recordings=""
        jfr_status="unavailable"
        logwarn "⚠️ the flight recorder could not be started over JMX on $(echo "$workers" | awk '{ print $1 }' | xargs): the report will not show where the time goes"
    fi
}
function stop_flight_recorder () {
    if [ -z "$jfr_recordings" ]
    then
        return
    fi
    jfr_files=$(jfr_jmx_stop "$jfr_recordings" "$output_dir/$run_id")
    jfr_recordings=""
    if [ -z "$jfr_files" ]
    then
        jfr_status="failed"
        logwarn "⚠️ the flight recordings could not be copied from the workers"
    fi
}

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
# a task restarted (rebalance, reconfiguration by its connector) counts from 0 again: the records counter of each task
# is kept monotonic by adding the value it had before the reset (a reset that goes unnoticed, when the new count is
# already above the old one at the next sample, is caught by the topics in a drain)
declare -A task_last_records=()
declare -A task_records_offset=()
task_counter_resets=0
function take_sample () {
    local phase="$1"
    local values
    values=$(benchmark_jmx_sample "$connector" "$type" "$workers")
    sample_time=$(now)
    read -r sample_records sample_batch sample_ratio sample_cpu sample_lag sample_cpu_available sample_pause sample_gc sample_dlq sample_skipped sample_tasks <<< "$values"
    if [ "$sample_tasks" != "-" ] && [ -n "$sample_tasks" ] && [ -z "$records_from_topics" ]
    then
        local entry task value corrected=0
        for entry in ${sample_tasks//;/ }
        do
            task="${entry%%:*}"
            value="${entry#*:}"
            if [ -n "${task_last_records[$task]}" ] && [ "$value" -lt "${task_last_records[$task]}" ]
            then
                task_records_offset[$task]=$(( ${task_records_offset[$task]:-0} + ${task_last_records[$task]} ))
                task_counter_resets=$((task_counter_resets + 1))
            fi
            task_last_records[$task]="$value"
            corrected=$((corrected + value + ${task_records_offset[$task]:-0}))
        done
        sample_records="$corrected"
    fi
    # the task counters were reset by a restart during the drain: the records come from the topics
    if [ -n "$records_from_topics" ]
    then
        sample_records=$((baseline_records + $(topic_records_progress)))
    fi
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

# records written to the topics since the backlog was loaded (topic_records_before)
function topic_records_progress () {
    awk 'NR == FNR { before[$1] = $2; next } { delta += $2 - before[$1] } END { print delta + 0 }' \
        <(echo "$topic_records_before") <(count_topic_records)
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
# set when a task restart reset the JMX counters during a drain: the samples count the records in the topics
records_from_topics=""
# the drain stopped at --max-wait before the end of the backlog
incomplete=false
load_seconds="-"
topic_records_delta="-"
start_time=$(now)

if [ "$mode" == "drain" ]
then
    log "⏸️ pausing $connector_type connector $connector ($type, $nb_tasks task(s), $connector_class $plugin_version)"
    playground connector pause --connector "$connector" > /dev/null
    paused_by_benchmark=1
    # a task only sees the pause between two polls of its consumer, and can miss it (connector PAUSED, task still
    # RUNNING) if a rebalance swallows the wakeup: a task restarted while its connector is paused starts paused
    if ! playground connector wait --connector "$connector" --state PAUSED --max-wait 30 --interval 2 > /dev/null 2>&1
    then
        logwarn "⚠️ $connector_type connector $connector is not paused with all its tasks after 30s, restarting them (they start paused): a task stuck in its code keeps its thread running next to the new one until the worker restarts, the flight recorder findings tell where it is stuck"
        playground connector restart --connector "$connector" > /dev/null
        playground connector wait --connector "$connector" --state PAUSED --max-wait 120 --interval 2 > /dev/null
    fi

    log "📥 loading the backlog$([ "$sessions" -gt 1 ] && echo " in $sessions sessions"): $load_cmd"
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
    # one line per session with --sessions
    records_from_load=$(grep -E '^BENCHMARK_RECORDS=[0-9]+$' "$load_log" | cut -d= -f2 | awk '{ n += $1 } END { if (NR) print n }')
    if [ -n "$records_from_load" ]
    then
        expected="$records_from_load"
    fi
    log "📦 backlog of $expected records loaded in ${load_seconds}s"

    if [ "$type" == "source" ]
    then
        topic_records_before=$(count_topic_records)
    fi

    start_flight_recorder
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
    stalled_samples=0
    while true
    do
        sleep "$interval"
        before_records="$prev_records"
        before_time="$prev_time"
        take_sample "drain"
        processed=$((sample_records - baseline_records))
        elapsed=$(awk -v t="$sample_time" -v s="$start_time" 'BEGIN { printf "%d", t - s }')
        # a source task restarted by its connector (the cloud storage and hdfs sources reconfigure their task every
        # minute or so) counts from 0 again: when the counter goes down, or stalls while the topics keep growing, the
        # rest of the drain counts the records in the topics
        if [ "$type" == "source" ] && [ -z "$records_from_topics" ] && [ ${#topics[@]} -gt 0 ]
        then
            if [ "$sample_records" -lt "$before_records" ]
            then
                stalled_samples=2
            elif [ "$sample_records" == "$before_records" ]
            then
                stalled_samples=$((stalled_samples + 1))
            else
                stalled_samples=0
            fi
            if [ "$stalled_samples" -gt 0 ] && [ $((stalled_samples % 2)) -eq 0 ]
            then
                topic_progress=$(topic_records_progress)
                # the topics must have moved: a counter below its baseline (processed < 0) proves nothing alone
                if [ "$topic_progress" -gt 0 ] && [ "$topic_progress" -gt "$processed" ]
                then
                    logwarn "⚠️ the task metrics count $processed/$expected records but the topics got $topic_progress (a restarted task counts from 0 again): counting the records in the topics from now on"
                    records_from_topics=1
                    sample_records=$((baseline_records + topic_progress))
                    prev_records="$sample_records"
                    processed="$topic_progress"
                    if [ "$processed" -ge "$expected" ]
                    then
                        end_time="$sample_time"
                        break
                    fi
                fi
            fi
        fi
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
            # a connector that does not drain is what the flight recording explains best: measure what was processed, write
            # the report, and fail at the end
            logerror "❌ only $processed/$expected records processed after ${max_wait}s, the drain did not finish: reporting on what was processed"
            set +e
            playground connector status --connector "$connector"
            set -e
            incomplete=true
            end_time="$sample_time"
            break
        fi
    done
    stop_flight_recorder
    measured_seconds=$(awk -v e="$end_time" -v s="$start_time" 'BEGIN { printf "%.1f", e - s }')
    measured_records="$expected"
    if [ "$incomplete" == "true" ]
    then
        measured_records="$processed"
    fi
    if [ "$type" == "source" ]
    then
        refresh_connector_topics
        if [ ${#topics[@]} -gt 0 ]
        then
            # topics created during the drain count from 0
            topic_records_delta=$(topic_records_progress)
        fi
    fi
else
    if [ -n "$load_cmd" ]
    then
        log "🌊 starting the load in the background$([ "$sessions" -gt 1 ] && echo " ($sessions sessions)"): $load_cmd"
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
    start_flight_recorder
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
    stop_flight_recorder
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

# window of the measure, in ms, for the grafana annotation and links
if [ "$mode" == "drain" ]
then
    measure_from_ms=$(awk -v t="$start_time" 'BEGIN { printf "%d", t * 1000 }')
    measure_to_ms=$(awk -v t="$end_time" 'BEGIN { printf "%d", t * 1000 }')
else
    measure_from_ms=$(awk -v t="$measure_start" 'BEGIN { printf "%d", t * 1000 }')
    measure_to_ms=$(awk -v t="$sample_time" 'BEGIN { printf "%d", t * 1000 }')
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

setup_json=$(benchmark_collect_setup "$workers" "$connector_config_json" "$test_file" "$environment")
[ -z "$setup_json" ] && setup_json='{}'

# where the time of the tasks went, from the flight recordings
jfr_analysis=""
if [ -n "$jfr_files" ]
then
    log "🛩️ analyzing the flight recording(s) ($JFR_ANALYZER_IMAGE)"
    task_threads="^task-thread-$(printf '%s' "$connector" | sed 's/[][\.*^$(){}+?|/]/\\&/g')-[0-9]+$"
    # shellcheck disable=SC2086
    jfr_digests=$(jfr_digest "$output_dir" "$task_threads" $jfr_files)
    if [ -n "$jfr_digests" ]
    then
        digest_args=()
        for digest in $jfr_digests
        do
            digest_args+=(--digest "$digest")
        done
        if python3 -I "$root_folder/tools/jfr-analyzer/jfr_analyzer.py" "${digest_args[@]}" --connector-class "$connector_class" --connector-type "$type" \
            --mode "$mode" --source-url "$(echo "$setup_json" | jq -r '.connector.source_url // empty')" --json-out "$output_dir/$run_id-jfr.json" > "$output_dir/$run_id-jfr.txt" 2>&1
        then
            jfr_analysis="$output_dir/$run_id-jfr.json"
        fi
    fi
    if [ -z "$jfr_analysis" ]
    then
        jfr_status="failed"
        logwarn "⚠️ the flight recording(s) could not be analyzed: $(echo $jfr_files)"
    fi
fi
if [ -n "$jfr_analysis" ]
then
    flight_recorder_json=$(jq -c --arg files "$jfr_files" --arg analysis "$jfr_analysis" \
        '{enabled: true, files: ($files | split("\n") | map(select(. != ""))), analysis: $analysis, findings: [.findings[] | {severity, title}]}' "$jfr_analysis")
else
    flight_recorder_json=$(jq -n -c --arg status "$jfr_status" --arg files "$jfr_files" \
        '{enabled: ($status != "disabled" and $status != "unavailable"), status: $status, files: ($files | split("\n") | map(select(. != "")))}')
fi

# grafana of the environment (--enable-jmx-grafana): the measure as an annotation on the dashboards of the connector
grafana_json='{"enabled": false}'
if benchmark_grafana_available
then
    grafana_dashboards=$(benchmark_grafana_dashboards "$connector_class")
    grafana_annotated=$(benchmark_grafana_annotate "$measure_from_ms" "$measure_to_ms" \
        "🏎️ benchmark of $connector ($plugin_version): $mode of $measured_records records, $([ "$lower_bound" == "true" ] && echo "≥ ")$throughput records/s" \
        "playground-benchmark,$connector,$plugin_version" "$grafana_dashboards")
    grafana_json=$(while IFS='|' read -r uid title
        do
            [ -n "$uid" ] && jq -n -c --arg uid "$uid" --arg title "$title" --arg url "$(benchmark_grafana_url "$uid" "$measure_from_ms" "$measure_to_ms")" '{uid: $uid, title: $title, url: $url}'
        done <<< "$grafana_dashboards" | jq -s -c --argjson annotated "${grafana_annotated:-0}" --arg interval "$(benchmark_grafana_scrape_interval)" \
            '{enabled: true, annotated: $annotated, scrape_interval_s: ($interval | tonumber? // null), dashboards: .}')
fi

test_file_relative="${test_file#$root_folder/}"
result=$(jq -n \
    --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg test_file "$test_file_relative" --arg connector "$connector" \
    --arg connector_class "$connector_class" --arg plugin_version "$plugin_version" --arg cp_tag "$cp_tag" \
    --arg type "$type" --arg mode "$mode" --arg shape "$shape" --argjson tasks "$nb_tasks" --argjson sessions "$sessions" \
    --argjson records "$measured_records" --argjson seconds "$measured_seconds" --argjson records_per_second "$throughput" \
    --arg rate_p50 "$rate_p50" --arg rate_p95 "$rate_p95" --arg rate_min "$rate_min" \
    --arg batch_avg_ms "$batch_avg" --arg running_ratio "$ratio_avg" --arg cpu_avg "$cpu_avg" --arg cpu_max "$cpu_max" \
    --arg load_seconds "$load_seconds" --arg topic_records_delta "$topic_records_delta" \
    --arg samples_csv "$csv_file" --argjson lower_bound "$lower_bound" --argjson incomplete "$incomplete" --argjson expected_records "$expected" \
    --arg gc_percent "$gc_percent" --arg cpu_available_avg "$cpu_available_avg" --arg pause_ratio "$pause_avg" \
    --arg dlq_records "$dlq_delta" --arg skipped_records "$skipped_delta" --arg task_shares "$task_shares" \
    --argjson setup "$setup_json" --argjson flight_recorder "$flight_recorder_json" --argjson grafana "$grafana_json" \
    --argjson measure_from_ms "$measure_from_ms" --argjson measure_to_ms "$measure_to_ms" \
    --arg load_script "$([ -n "$load_script" ] && [[ "$load_cmd" == *"$load_script"* ]] && basename "$load_script")" \
    '{date: $date, test_file: $test_file, connector: $connector, connector_class: $connector_class, plugin_version: $plugin_version,
      cp_tag: $cp_tag, type: $type, mode: $mode, shape: $shape, sessions: $sessions, tasks: $tasks, records: $records, seconds: $seconds,
      records_per_second: $records_per_second, lower_bound: $lower_bound,
      incomplete: $incomplete, expected_records: $expected_records, rate_p50: $rate_p50, rate_p95: $rate_p95, rate_min: $rate_min,
      batch_avg_ms: $batch_avg_ms, running_ratio: $running_ratio, cpu_percent_of_one_core_avg: $cpu_avg,
      cpu_percent_of_one_core_max: $cpu_max, load_seconds: $load_seconds, topic_records_delta: $topic_records_delta,
      gc_percent: $gc_percent, cpu_percent_of_available_avg: $cpu_available_avg, pause_ratio: $pause_ratio,
      dlq_records: $dlq_records, skipped_records: $skipped_records, task_shares: $task_shares,
      samples_csv: $samples_csv, setup: $setup, flight_recorder: $flight_recorder, grafana: $grafana,
      measure_from_ms: $measure_from_ms, measure_to_ms: $measure_to_ms, load_script: $load_script}')
echo "$result" > "$json_file"
if [ -n "$BENCHMARK_MATRIX_RESULTS" ]
then
    echo "$json_file" >> "$BENCHMARK_MATRIX_RESULTS"
fi

# previous result to compare with: --compare, or the last one of the same connector, example, mode and shape
history_file="$root_folder/benchmark-history"
previous=""
if [ -n "$compare_file" ]
then
    previous=$(jq -c . "$compare_file")
elif [ -f "$history_file" ]
then
    # lower bounds are not comparable
    previous=$(jq -c --arg t "$test_file_relative" --arg c "$connector" --arg m "$mode" --arg s "$shape" 'select(.test_file == $t and .connector == $c and .mode == $m and .shape == $s and .lower_bound != true and .incomplete != true and .records > 0)' "$history_file" 2> /dev/null | tail -1)
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
    [ "$incomplete" == "true" ] && exit 1
    exit 0
fi

log "🏁 benchmark of $connector_type connector $connector ($type, $nb_tasks task(s), $connector_class $plugin_version, CP $cp_tag)"
if [ "$mode" == "drain" ]
then
    if [ "$incomplete" == "true" ]
    then
        printf "   %-22s %s\n" "mode" "drain stopped after ${max_wait}s (--max-wait): $measured_records of $expected records processed (shape $shape)"
    else
        printf "   %-22s %s\n" "mode" "drain of $measured_records records (shape $shape$([ "$sessions" -gt 1 ] && echo ", $sessions sessions"), loaded in ${load_seconds}s)"
    fi
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
printf "   %-22s %s\n" "setup" "$(benchmark_setup_summary "$setup_json")"
if [ "$(echo "$grafana_json" | jq -r '.enabled')" == "true" ]
then
    printf "   %-22s %s\n" "grafana" "$(echo "$grafana_json" | jq -r '.dashboards[0].url // "-"')"
    printf "   %-22s %s\n" "" "measure annotated on $(echo "$grafana_json" | jq -r '"\(.annotated) dashboard(s): " + ([.dashboards[].title] | join(", "))')"
fi
if [ -n "$jfr_analysis" ]
then
    jfr_lines=$(jq -r '.findings[0:4][] | (if .severity == "critical" then "🔴" elif .severity == "warning" then "🟠" else "ℹ️ " end) + " " + .title' "$jfr_analysis")
    if [ -z "$jfr_lines" ]
    then
        jfr_lines="no finding"
    fi
    first_line=1
    while IFS= read -r line
    do
        printf "   %-22s %s\n" "$([ $first_line -eq 1 ] && echo "flight recorder")" "$line"
        first_line=0
    done <<< "$jfr_lines"
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
if [ "$task_counter_resets" -gt 0 ] && [ -z "$records_from_topics" ]
then
    add_warning "the records counter of a task was reset $task_counter_resets time(s) (task restarts: rebalance, or a connector reconfiguring its tasks): the records counted before each reset were kept, see the task restarts in the connect logs"
fi
if [ -n "$records_from_topics" ]
then
    add_warning "the JMX counters of the tasks fell behind the records written to the topics during the drain, usually because a task was restarted (the cloud storage and hdfs sources reconfigure their task at each poll interval): the samples count the records in the topics from then on, see the task restarts in the connect logs"
fi
if [ -n "$previous" ] && [ "$(echo "$previous" | jq -c '.setup // empty')" != "" ]
then
    setup_differences=$(benchmark_setup_differences "$setup_json" "$(echo "$previous" | jq -c '.setup')")
    if [ -n "$setup_differences" ]
    then
        add_warning "the previous run was on a different setup ($setup_differences): the comparison is not meaningful"
    fi
fi
# a load script of another name loads something else (BENCHMARK_LOAD_SCRIPT)
previous_load_script=$(echo "$previous" | jq -r '.load_script // empty' 2> /dev/null)
current_load_script=$(echo "$result" | jq -r '.load_script // empty')
if [ -n "$previous_load_script" ] && [ -n "$current_load_script" ] && [ "$previous_load_script" != "$current_load_script" ]
then
    add_warning "the previous run used the load $previous_load_script and this one $current_load_script: the load is not the same"
fi
if [ -n "$previous" ] && [ "$(echo "$previous" | jq -r '.sessions // 1')" != "$sessions" ]
then
    add_warning "the previous run used $(echo "$previous" | jq -r '.sessions // 1') load session(s) and this one $sessions: the load is not the same"
fi
if [ -n "$previous" ] && [ "$(echo "$previous" | jq -r '.grafana.enabled // false')" != "$(echo "$grafana_json" | jq -r '.enabled')" ]
then
    add_warning "the previous run was $([ "$(echo "$previous" | jq -r '.grafana.enabled // false')" == "true" ] && echo "measured with" || echo "measured without") Grafana and this one $([ "$(echo "$grafana_json" | jq -r '.enabled')" == "true" ] && echo "with" || echo "without"): the JMX exporter in the JVMs and the Grafana containers use CPU, compare runs measured the same way"
fi
# grafana only has the samples prometheus scraped during the measure
scrape_interval=$(echo "$grafana_json" | jq -r '.scrape_interval_s // empty')
if [ -n "$scrape_interval" ] && awk -v s="$measured_seconds" -v i="$scrape_interval" 'BEGIN { exit !(s < 3 * i) }'
then
    add_warning "the measure lasted ${measured_seconds}s and prometheus scrapes every ${scrape_interval}s: grafana has only $(awk -v s="$measured_seconds" -v i="$scrape_interval" 'BEGIN { printf "%d", s / i }') sample(s) during it, increase --nb-records or use --mode steady --duration 2m to see the run on the dashboards"
fi
if [ -n "$previous" ]
then
    previous_jfr=$(echo "$previous" | jq -r '.flight_recorder.enabled // false')
    current_jfr=$(echo "$flight_recorder_json" | jq -r '.enabled')
    if [ "$previous_jfr" != "$current_jfr" ]
    then
        add_warning "the previous run was $([ "$previous_jfr" == "true" ] && echo "recorded with" || echo "run without") the flight recorder and this one $([ "$current_jfr" == "true" ] && echo "with" || echo "without"): it costs a few % of throughput, compare runs recorded the same way (--no-flight-recorder)"
    fi
fi
if [ "$(echo "$setup_json" | jq -r '.connect.emulated // false')" == "true" ]
then
    add_warning "the connect worker runs an image of another architecture ($(echo "$setup_json" | jq -r '.connect.image_arch') on $(echo "$setup_json" | jq -r '.host.arch')): emulation makes it much slower than on native hardware"
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
if [ "$incomplete" == "true" ]
then
    add_warning "the drain did not finish: only $measured_records of $expected records were processed in ${max_wait}s (--max-wait), the throughput is the one of the records processed; see where the time goes in the flight recorder findings"
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
    if [ "$generated" -gt 0 ] && awk -v m="$measured_records" -v g="$generated" 'BEGIN { exit !(g > 2 * m) }'
    then
        add_warning "the load generated $generated records during the measure but the connector processed only $measured_records: a backlog builds up in the source system, or a publish/subscribe broker (mqtt) drops the messages it cannot deliver"
    elif [ "$generated" -gt 0 ] && awk -v m="$measured_records" -v g="$generated" -v b="${largest_batch:-0}" 'BEGIN { exit !(m >= 0.9 * g || m >= g - b) }'
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
if [ -n "$jfr_analysis" ]
then
    log "🛩️ flight recording(s): $(echo $jfr_files) (open in JDK Mission Control, or playground analyze flight-recorder -f <file>)"
fi

html_file="$output_dir/$run_id.html"
report_args=(--result "$json_file" --samples "$csv_file" --history "$history_file" --output "$html_file")
if [ -n "$jfr_analysis" ]
then
    report_args+=(--jfr "$jfr_analysis")
fi
for warning in "${report_warnings[@]}"
do
    report_args+=(--warning "$warning")
done
if python3 -I "$root_folder/tools/benchmark-report/benchmark_report.py" "${report_args[@]}" > /dev/null
then
    log "📊 report: $html_file"
    # only open a browser in an interactive terminal, never in CI nor for the runs of a --connector-tag comparison
    if [[ -t 1 ]] && [ -z "$GITHUB_RUN_NUMBER" ] && [ -z "$BENCHMARK_NO_OPEN" ]
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

# the report is written, but a drain that did not finish is a failed benchmark
if [ "$incomplete" == "true" ]
then
    exit 1
fi
