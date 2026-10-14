eval "file_array=(${args[--file]})"
eval "sample_array=(${args[--sample]})"
container="${args[--container]}"
output_dir="${args[--output-dir]}"
json_out="${args[--json]}"
top="${args[--top]}"
problem="${args[--problem]}"

set +e

nb_modes=0
[[ ${#file_array[@]} -gt 0 ]] && nb_modes=$((nb_modes + 1))
[[ ${#sample_array[@]} -gt 0 ]] && nb_modes=$((nb_modes + 1))
[[ -n "$container" ]] && nb_modes=$((nb_modes + 1))
if [[ $nb_modes -gt 1 ]]; then
    logerror "❌ Provide only one of --file, --container and --sample"
    exit 1
fi
if [[ $nb_modes -eq 0 ]]; then
    container="oracle"
fi

analyzer_dir="$root_folder/tools/xstream-analyzer"
analyzer="$analyzer_dir/xstream_report_analyzer.py"
if [[ ! -f "$analyzer" ]]; then
    logerror "❌ Oracle XStream report analyzer not found at: $analyzer"
    exit 1
fi
if ! command -v python3 &>/dev/null; then
    logerror "❌ python3 is required but not found on PATH"
    exit 1
fi

mkdir -p "$output_dir"
output_dir_abs=$(cd "$output_dir" && pwd)

# ── Sample mode: reports shipped with the analyzer ──
for sample in "${sample_array[@]}"
do
    file_array+=("$analyzer_dir/samples/orclcdc_diag_${sample}.html")
done

# ── Container mode: run the diagnostics script on the running example, keep a timestamped copy ──
if [[ -n "$container" ]]; then
    if ! docker ps --filter "name=^${container}$" --filter "status=running" --format "{{.Names}}" | grep -qx "$container"; then
        logerror "❌ container $container is not running: start an Oracle XStream example, or use --file with a report (or --sample to try it)"
        exit 1
    fi
    rm -f /tmp/orclcdc_diag.html
    log "⚙️ Generating the diagnostics report in container $container"
    playground --output-level ERROR connector oracle-cdc-xstream generate-report > /dev/null 2>&1
    if [[ ! -f /tmp/orclcdc_diag.html ]]; then
        logerror "❌ the diagnostics report could not be generated, run 'playground connector oracle-cdc-xstream generate-report' to see why"
        exit 1
    fi
    report="$output_dir_abs/orclcdc_diag_$(date '+%Y%m%d_%H%M%S').html"
    mv /tmp/orclcdc_diag.html "$report"
    log "✅ report saved in $report"
    file_array=("$report")
fi

# Handle fzf @path trick
for i in "${!file_array[@]}"
do
    if [[ ! -e "${file_array[$i]}" && "${file_array[$i]}" == *"@"* ]]; then
        file_array[$i]=$(echo "${file_array[$i]}" | cut -d "@" -f 2)
    fi
done

analyzer_args=("${file_array[@]}" --top "$top")
if [[ -n "$problem" ]]; then
    analyzer_args+=(--problem "$problem")
fi

if [[ -n "$json_out" ]]; then
    python3 -I "$analyzer" "${analyzer_args[@]}" --json
    exit $?
fi

html_out=""
# the HTML report is always written (not with --json: stdout must stay JSON)
if [[ -z "$json_out" ]]; then
    first=$(basename "${file_array[${#file_array[@]}-1]}")
    html_out="${output_dir_abs}/${first%.*}-xstream-report.html"
    analyzer_args+=(--html-out "$html_out")
fi

log "🅾️ Analyzing Oracle XStream diagnostics report(s): ${file_array[*]}"
log ""
python3 -I "$analyzer" "${analyzer_args[@]}" 2> >(grep -v '^HTML report:' >&2)
exit_code=$?

if [[ $exit_code -ne 0 ]]; then
    logerror "❌ Oracle XStream report analysis failed (exit code $exit_code)"
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
