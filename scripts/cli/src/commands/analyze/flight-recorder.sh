eval "file_array=(${args[--file]})"
sample="${args[--sample]}"
container="${args[--container]}"
duration=$(duration_to_seconds "${args[--duration]}")
connector="${args[--connector]}"
connector_class="${args[--connector-class]}"
threads="${args[--threads]}"
output_dir="${args[--output-dir]}"
json_out="${args[--json]}"
top="${args[--top]}"

set +e

nb_modes=0
[[ ${#file_array[@]} -gt 0 ]] && nb_modes=$((nb_modes + 1))
[[ -n "$sample" ]] && nb_modes=$((nb_modes + 1))
[[ -n "$container" ]] && nb_modes=$((nb_modes + 1))
if [[ $nb_modes -gt 1 ]]; then
    logerror "❌ Provide only one of --file, --container and --sample"
    exit 1
fi
if [[ $nb_modes -eq 0 ]]; then
    container="connect"
fi

analyzer="$root_folder/tools/jfr-analyzer/jfr_analyzer.py"
if ! command -v python3 &>/dev/null; then
    logerror "❌ python3 is required but not found on PATH"
    exit 1
fi

# with --json, logs go to stderr and only the analysis to stdout
if [[ -n "$json_out" ]]; then
    exec 3>&1 1>&2
fi

mkdir -p "$output_dir"
output_dir_abs=$(cd "$output_dir" && pwd)

if [[ -n "$connector" ]]; then
    [[ -z "$threads" ]] && threads="^task-thread-$(printf '%s' "$connector" | sed 's/[][\.*^$(){}+?|/]/\\&/g')-[0-9]+$"
    if [[ -z "$connector_class" ]]; then
        get_connect_url_and_security
        if handle_onprem_connect_rest_api "curl -s $security \"$connect_url/connectors/$connector/config\"" > /dev/null 2>&1; then
            connector_class=$(echo "$curl_output" | jq -r '."connector.class" // empty' 2> /dev/null)
        fi
    fi
fi
[[ -z "$threads" ]] && threads="^task-thread-"

# fzf completion returns <display>@<path>
for i in "${!file_array[@]}"
do
    if [[ ! -e "${file_array[$i]}" && "${file_array[$i]}" == *"@"* ]]; then
        file_array[$i]=$(echo "${file_array[$i]}" | cut -d "@" -f 2)
    fi
done

# ── Container mode: record the JVM over JMX ──
if [[ -n "$container" ]]; then
    port=$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$container" 2> /dev/null | sed -n 's/^[A-Z_]*JMX_PORT=//p' | head -1)
    if [[ -z "$port" ]]; then
        logerror "❌ container $container is not running or has no JMX port (KAFKA_JMX_PORT, SCHEMA_REGISTRY_JMX_PORT...): the flight recorder is driven over JMX"
        exit 1
    fi
    workers="$container $port"
    benchmark_jmx_init "$workers"
    recordings=$(jfr_jmx_start "$workers")
    if [[ $? -ne 0 || -z "$recordings" ]]; then
        logerror "❌ could not start the flight recorder of $container over JMX (localhost:$port): JDK 8 before 8u262, or JMX not reachable"
        exit 1
    fi
    trap 'jfr_jmx_discard "$recordings"' EXIT
    log "🛩️ recording $container for ${duration}s with the settings of tools/jfr-analyzer/playground.jfc"
    sleep "$duration"
    recorded=$(jfr_jmx_stop "$recordings" "$output_dir_abs/flight-recorder-$(date '+%Y-%m-%d-%H-%M-%S')")
    recordings=""
    trap - EXIT
    if [[ -z "$recorded" ]]; then
        logerror "❌ the recording could not be copied from $container"
        exit 1
    fi
    log "✅ recording saved in $recorded"
    file_array=("$recorded")
fi

# ── Digests: from the samples, the .json digests given, or the .jfr files ──
digests=()
if [[ -n "$sample" ]]; then
    # a sample digest also carries the connector class, type and mode of its benchmark
    digests=("$root_folder/tools/jfr-analyzer/samples/$sample.digest.json")
fi
jfr_files=()
for file in "${file_array[@]}"
do
    if [[ "$file" == *.digest.json ]]; then
        digests+=("$file")
    else
        jfr_files+=("$file")
    fi
done
if [[ ${#jfr_files[@]} -gt 0 ]]; then
    log "🔬 reading ${#jfr_files[@]} recording(s) with the JDK flight recorder API ($JFR_ANALYZER_IMAGE)"
    produced=$(jfr_digest "$output_dir_abs" "$threads" "${jfr_files[@]}")
    ret=$?
    for digest in $produced
    do
        digests+=("$digest")
    done
    if [[ $ret -ne 0 ]]; then
        logerror "❌ not a flight recording, or it could not be read: ${jfr_files[*]}"
        for file in "${jfr_files[@]}"
        do
            log_file="$output_dir_abs/$(basename "${file%.jfr}").digest.json.log"
            [[ -s "$log_file" ]] && grep -m1 -E "Exception|Error" "$log_file"
        done
        exit 2
    fi
fi

analyzer_args=()
for digest in "${digests[@]}"
do
    analyzer_args+=(--digest "$digest")
done
analyzer_args+=(--top "$top")
[[ -n "$connector_class" ]] && analyzer_args+=(--connector-class "$connector_class")

if [[ -n "$json_out" ]]; then
    python3 -I "$analyzer" "${analyzer_args[@]}" --json >&3
    exit $?
fi

if [[ ${#jfr_files[@]} -gt 0 ]]; then
    first=$(basename "${jfr_files[0]}")
    html_out="$output_dir_abs/${first%.jfr}-jfr-report.html"
    [[ ${#jfr_files[@]} -eq 1 ]] && analyzer_args+=(--recording-link "${jfr_files[0]}")
else
    first=$(basename "${digests[0]}")
    html_out="$output_dir_abs/${first%.digest.json}-jfr-report.html"
fi
analyzer_args+=(--html-out "$html_out")

log ""
python3 -I "$analyzer" "${analyzer_args[@]}"
exit_code=$?
if [[ $exit_code -ne 0 ]]; then
    logerror "❌ flight recording analysis failed (exit code $exit_code)"
    exit $exit_code
fi

if [[ -f "$html_out" ]]; then
    log ""
    log "✅ HTML report saved: $html_out"
    # only open a browser in an interactive terminal
    if [[ -t 1 ]] && command -v open &>/dev/null; then
        log "🌐 Opening report in browser..."
        open "$html_out"
    else
        log "🔗 Open in browser: file://$html_out"
    fi
fi

exit 0
