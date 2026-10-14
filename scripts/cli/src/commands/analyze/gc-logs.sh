eval "file_array=(${args[--file]})"
eval "sample_array=(${args[--sample]})"
container="${args[--container]}"
output_dir="${args[--output-dir]}"
json_out="${args[--json]}"
top_pauses="${args[--top-pauses]}"
run="${args[--run]}"

set +e

# ── Validate input: one of --file, --container or --sample ─────────────────
nb_modes=0
[[ ${#file_array[@]} -gt 0 ]] && nb_modes=$((nb_modes + 1))
[[ ${#sample_array[@]} -gt 0 ]] && nb_modes=$((nb_modes + 1))
[[ -n "$container" ]] && nb_modes=$((nb_modes + 1))
if [[ $nb_modes -eq 0 ]]; then
    logerror "❌ Must provide one of --file <gc-log-file-or-folder>, --container <name> or --sample <name>"
    log ""
    log "Examples:"
    log "  playground analyze gc-logs --file kafkaServer-gc.log"
    log "  playground analyze gc-logs --container broker"
    log "  playground analyze gc-logs --sample jdk21_g1_kafka_real"
    exit 1
fi
if [[ $nb_modes -gt 1 ]]; then
    logerror "❌ Provide only one of --file, --container and --sample"
    exit 1
fi

# ── Sample mode: GC logs shipped with the analyzer ──
for sample in "${sample_array[@]}"
do
    file_array+=("$root_folder/gc-analysis/samples/${sample}.log")
done

analyzer="$root_folder/gc-analysis/gc_log_analyzer.py"
if [[ ! -f "$analyzer" ]]; then
    logerror "❌ GC analyzer not found at: $analyzer"
    exit 1
fi

if ! command -v python3 &>/dev/null; then
    logerror "❌ python3 is required but not found on PATH"
    exit 1
fi

# ── Container mode: find the GC log and copy it with its rotated files ─────
if [[ -n "$container" ]]; then
    log "🐳 Looking for the GC log in container: $container"

    # path from the java command line: -Xlog:gc*:file=<path>:... (JDK 9+) or -Xloggc:<path> (JDK 8)
    gc_log_path=$(playground --output-level ERROR container exec --container "$container" --command "cat /proc/[0-9]*/cmdline 2>/dev/null | tr '\\000' '\\n' | sed -n -e 's/^-Xlog:gc[^:]*:file=\"\\{0,1\\}\\([^:\"]*\\).*/\\1/p' -e 's/^-Xloggc:\\(.*\\)/\\1/p' | head -1" 2>/dev/null | tr -d '\r')

    if [[ -z "$gc_log_path" ]]; then
        log "🔍 No -Xlog:gc / -Xloggc flag found, searching common log locations..."
        gc_log_path=$(playground --output-level ERROR container exec --container "$container" --command "find /usr/logs /var/log /tmp /opt /home -maxdepth 4 -type f -name '*gc*.log*' 2>/dev/null | head -1" 2>/dev/null | tr -d '\r')
    fi

    if [[ -z "$gc_log_path" ]]; then
        logerror "❌ Could not locate a GC log in container '$container'"
        log ""
        log "💡 The playground environments pass -loggc to ZooKeeper, brokers, controllers, Schema Registry and Connect"
        log "   (GC log in /var/log/kafka/<name>-gc.log, /usr/logs for Schema Registry), and ksqlDB writes one by default. If this container has none, it was"
        log "   started before that change (playground re-run) or its EXTRA_ARGS is overridden by the example."
        log "   To enable it on a running container (this replaces the current KAFKA_OPTS value, if any):"
        log "   playground container set-environment-variables --container $container --env \"KAFKA_OPTS: -Xlog:gc*:file=/tmp/gc.log:time,uptime,level,tags:filecount=5,filesize=20m\""
        log "   JDK 8: -XX:+PrintGCDetails -XX:+PrintGCDateStamps -XX:+PrintGCTimeStamps -Xloggc:/tmp/gc.log"
        exit 1
    fi

    # rotated files: <path>, <path>.0..N (JDK 9+), <path>.N.current (JDK 8)
    base="${gc_log_path%.current}"
    base=$(echo "$base" | sed -E 's/\.[0-9]+$//')
    log "📄 Found GC log: $gc_log_path"

    tmp_dir="$output_dir/gc-logs-${container}-$(date '+%Y%m%d-%H%M%S')"
    mkdir -p "$tmp_dir"
    nb_copied=0
    while read -r f
    do
        [[ -z "$f" ]] && continue
        if playground --output-level ERROR container cp --source "${container}:${f}" --destination "$tmp_dir/$(basename "$f")" > /dev/null 2>&1; then
            nb_copied=$((nb_copied+1))
        fi
    done < <(playground --output-level ERROR container exec --container "$container" --command "ls -1d ${base} ${base}.* 2>/dev/null" 2>/dev/null | tr -d '\r')

    if [[ $nb_copied -eq 0 ]]; then
        logerror "❌ Failed to copy the GC log from container '$container'"
        exit 1
    fi
    log "✅ $nb_copied GC log file(s) copied to: $tmp_dir"
    file_array=("$tmp_dir")
fi

# Handle fzf @path trick
for i in "${!file_array[@]}"
do
    if [[ ! -e "${file_array[$i]}" && "${file_array[$i]}" == *"@"* ]]; then
        file_array[$i]=$(echo "${file_array[$i]}" | cut -d "@" -f 2)
    fi
done

analyzer_args=("${file_array[@]}" --top-pauses "$top_pauses")
if [[ -n "$run" ]]; then
    analyzer_args+=(--run "$run")
fi

if [[ -n "$json_out" ]]; then
    python3 -I "$analyzer" "${analyzer_args[@]}" --json
    exit $?
fi

log "📈 Analyzing GC log: ${file_array[*]}"
log ""

html_out=""
# the HTML report is always written (not with --json: stdout must stay JSON)
if [[ -z "$json_out" ]]; then
    mkdir -p "$output_dir"
    output_dir_abs=$(cd "$output_dir" && pwd)
    first=$(basename "${file_array[0]}")
    html_out="${output_dir_abs}/${first%.log}-gc-report.html"
    analyzer_args+=(--html-out "$html_out")
fi

python3 -I "$analyzer" "${analyzer_args[@]}"
exit_code=$?

if [[ $exit_code -ne 0 ]]; then
    logerror "❌ GC log analysis failed (exit code $exit_code)"
    exit $exit_code
fi

if [[ -n "$html_out" && -f "$html_out" ]]; then
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
