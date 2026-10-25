file="${args[--file]}"
sample="${args[--sample]}"
output_dir="${args[--output-dir]}"
json_out="${args[--json]}"
top="${args[--top]}"

set +e

if [[ -n "$file" && -n "$sample" ]]; then
    logerror "❌ Provide either --file or --sample, not both"
    exit 1
fi
if [[ -z "$file" && -z "$sample" ]]; then
    logerror "❌ Must provide --file <trace folder> (copied by playground debug jscissors --action stop), or --sample demo to try it"
    exit 1
fi
if [[ -n "$sample" ]]; then
    file="$root_folder/tools/jscissors/samples/$sample"
fi
# fzf completion returns <display>@<path>
if [[ ! -e "$file" && "$file" == *"@"* ]]; then
    file=$(echo "$file" | cut -d "@" -f 2)
fi
if [[ ! -e "$file" ]]; then
    logerror "❌ $file not found"
    exit 1
fi

if ! command -v python3 &>/dev/null; then
    logerror "❌ python3 is required but not found on PATH"
    exit 1
fi
analyzer="$root_folder/tools/jscissors/jscissors_report.py"

if [[ -n "$json_out" ]]; then
    python3 -I "$analyzer" --dir "$file" --top "$top" --json
    exit $?
fi

mkdir -p "$output_dir"
output_dir_abs=$(cd "$output_dir" && pwd)
html_out="$output_dir_abs/$(basename "$(cd "$(dirname "$file")" && pwd)/$(basename "$file")")-jscissors-report.html"

python3 -I "$analyzer" --dir "$file" --top "$top" --html-out "$html_out"
exit_code=$?
if [[ $exit_code -ne 0 ]]; then
    logerror "❌ jscissors trace analysis failed (exit code $exit_code)"
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
