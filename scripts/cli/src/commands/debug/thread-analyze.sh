eval "file_array=(${args[--file]})"
container="${args[--container]}"
count="${args[--count]}"
interval="${args[--interval]}"
output_dir="${args[--output-dir]}"
html="${args[--html]}"
json_out="${args[--json]}"
top="${args[--top]}"

set +e

if [[ ${#file_array[@]} -gt 0 && -n "$container" ]]; then
    logerror "❌ Provide either --file or --container, not both"
    exit 1
fi
if [[ ${#file_array[@]} -eq 0 && -z "$container" ]]; then
    container="connect"
fi

analyzer="$root_folder/tools/thread-analyzer/thread_dump_analyzer.py"
if [[ ! -f "$analyzer" ]]; then
    logerror "❌ Thread dump analyzer not found at: $analyzer"
    exit 1
fi
if ! command -v python3 &>/dev/null; then
    logerror "❌ python3 is required but not found on PATH"
    exit 1
fi

mkdir -p "$output_dir"
output_dir_abs=$(cd "$output_dir" && pwd)

# ── Container mode: kill -3 the JVM (prints the dumps on its stdout, no JDK needed), read them back from the logs ──
if [[ -n "$container" ]]; then
    get_environment_used
    resolved_container=$(resolve_container_name_for_environment "$container")
    dumps_file="$output_dir_abs/thread-dumps-${container}-$(date '+%Y%m%d-%H%M%S').log"
    log "🎯 Taking $count thread dump(s) of container $container with kill -3, $interval second(s) apart"
    if ! take_thread_dumps_with_kill_quit "$container" "$count" "$interval" "$dumps_file"; then
        # the JVM stdout does not reach the container logs: fall back to jstack when the image has a JDK
        if playground --output-level ERROR container exec --container "$resolved_container" --command "type jstack" > /dev/null 2>&1; then
            logwarn "⚠️  kill -3 output not found in the logs of $container, using jstack"
            : > "$dumps_file"
            for i in $(seq 1 "$count")
            do
                playground --output-level ERROR container exec --container "$resolved_container" --command "date '+%Y-%m-%d %H:%M:%S'; jstack -l 1" >> "$dumps_file" 2>&1
                [[ $i -lt $count ]] && sleep "$interval"
            done
        fi
    fi
    nb_dumps=$(grep -c "Full thread dump" "$dumps_file" 2>/dev/null)
    if [[ -z "$nb_dumps" || $nb_dumps -eq 0 ]]; then
        logerror "❌ Could not get a thread dump from container $container (kill -3 output not in its logs, no jstack)"
        log "💡 playground debug thread-dump --container $container --jstack also works on cfk (debug container)"
        exit 1
    fi
    log "✅ $nb_dumps thread dump(s) saved in $dumps_file"
    file_array=("$dumps_file")
fi

# Handle fzf @path trick
for i in "${!file_array[@]}"
do
    if [[ ! -e "${file_array[$i]}" && "${file_array[$i]}" == *"@"* ]]; then
        file_array[$i]=$(echo "${file_array[$i]}" | cut -d "@" -f 2)
    fi
done

analyzer_args=("${file_array[@]}" --top "$top")

if [[ -n "$json_out" ]]; then
    python3 -I "$analyzer" "${analyzer_args[@]}" --json
    exit $?
fi

html_out=""
if [[ -n "$html" ]]; then
    first=$(basename "${file_array[0]}")
    html_out="${output_dir_abs}/${first%.*}-thread-report.html"
    analyzer_args+=(--html-out "$html_out")
fi

log "🧵 Analyzing thread dump(s): ${file_array[*]}"
log ""
python3 -I "$analyzer" "${analyzer_args[@]}"
exit_code=$?

if [[ $exit_code -ne 0 ]]; then
    logerror "❌ Thread dump analysis failed (exit code $exit_code)"
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
