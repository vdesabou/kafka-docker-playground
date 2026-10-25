eval "file_array=(${args[--file]})"
eval "sample_array=(${args[--sample]})"
include_warnings="${args[--include-warnings]}"
max_findings="${args[--max-findings]}"
output_dir="${args[--output-dir]}"
json_out="${args[--json]}"

# with --json, logs and the text digest go to stderr and only the analysis to stdout (same as analyze thread-dump)
if [[ -n "$json_out" ]]
then
    exec 3>&1 1>&2
fi

if [[ ${#file_array[@]} -gt 0 && ${#sample_array[@]} -gt 0 ]]
then
    logerror "❌ Provide either --file or --sample, not both"
    exit 1
fi
if [[ ${#file_array[@]} -eq 0 && ${#sample_array[@]} -eq 0 ]]
then
    logerror "❌ Must provide --file <log file, folder or bundle> (or --sample connect_task_failure to try it)"
    exit 1
fi

# ── Sample mode: logs shipped in tools/log-analyzer/samples ──
for sample in "${sample_array[@]}"
do
    case "$sample" in
        connect_task_failure) file_array+=("$root_folder/tools/log-analyzer/samples/connect-oracle-xstream-task-failure.log") ;;
        support_bundle) file_array+=("$root_folder/tools/log-analyzer/samples/support-bundle.zip") ;;
    esac
done

for file in "${file_array[@]}"
do
    if [ ! -e "$file" ]
    then
        logerror "❌ <$file> does not exist, please make sure to use absolute full path or correct relative path !"
        exit 1
    fi
done

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

# every distinct record, for the HTML report and --json (see summarize_log_errors)
records_file="$tmp_dir/records"
: > "$records_file"
nb_files=0
nb_files_with_findings=0
nb_skipped=0
nb_extracted=0

# prints the digest of one log, read on stdin, when it has findings
# $1: label to display
function analyze_logs_digest () {
    label="$1"
    output=$(PG_LOG_DIGEST_RECORDS_FILE="$records_file" PG_LOG_DIGEST_LABEL="$label" summarize_log_errors "$max_findings" "$include_warnings")
    nb_files=$((nb_files+1))
    if [[ "$output" == "✅"* ]]
    then
        return
    fi
    nb_files_with_findings=$((nb_files_with_findings+1))
    log "🔥 ERROR/FATAL digest for $label"
    # there is no --since here
    echo "$output" | sed 's/ or narrow with --since$//'
    echo ""
}

# analyzes a file, a folder or an archive, recursively
# $1: path, $2: label to display
function analyze_logs_path () {
    local path="$1"
    local label="$2"
    local extract_dir
    local f

    if [ -d "$path" ]
    then
        while IFS= read -r -d '' f
        do
            if [[ "$label" == *":" ]]
            then
                analyze_logs_path "$f" "${label}${f#$path/}"
            else
                analyze_logs_path "$f" "${label%/}/${f#$path/}"
            fi
        done < <(find "$path" -type f ! -path "*/__MACOSX/*" ! -name ".DS_Store" -print0 | sort -z)
        return
    fi

    case "$path" in
        *.zip|*.tar|*.tar.gz|*.tgz)
            nb_extracted=$((nb_extracted+1))
            extract_dir="$tmp_dir/$nb_extracted"
            mkdir -p "$extract_dir"
            case "$path" in
                *.zip) unzip -q -o "$path" -d "$extract_dir" > /dev/null 2>&1 ;;
                *) tar -xf "$path" -C "$extract_dir" > /dev/null 2>&1 ;;
            esac
            if [ $? -ne 0 ]
            then
                logwarn "⚠️ could not fully extract $label"
            fi
            analyze_logs_path "$extract_dir" "$label:"
            ;;
        *.gz)
            analyze_logs_digest "$label" < <(gzip -dc "$path" 2>/dev/null)
            ;;
        *)
            if grep -Iq . "$path" 2>/dev/null
            then
                analyze_logs_digest "$label" < "$path"
            else
                nb_skipped=$((nb_skipped+1))
            fi
            ;;
    esac
}

set +e
for file in "${file_array[@]}"
do
    analyze_logs_path "${file%/}" "${file%/}"
done
set -e

levels="ERROR/FATAL"
if [[ -n "$include_warnings" ]]
then
    levels="ERROR/FATAL/WARN"
fi
if [ $nb_files_with_findings -eq 0 ]
then
    log "✅ no $levels record found in $nb_files file(s) (binary files skipped: $nb_skipped)"
else
    log "📊 $nb_files_with_findings file(s) with findings out of $nb_files scanned (binary files skipped: $nb_skipped)"
fi

if ! command -v python3 &>/dev/null
then
    logwarn "⚠️ python3 is not on PATH: no HTML report"
    exit 0
fi
title="${file_array[*]}"
if [[ ${#sample_array[@]} -gt 0 ]]
then
    title="sample ${sample_array[*]}"
fi
report_args=(--records "$records_file" --title "$title" --levels "$levels" --skipped "$nb_skipped")
if [[ -n "$json_out" ]]
then
    python3 -I "$root_folder/tools/log-analyzer/log_report.py" "${report_args[@]}" --json >&3
    exit $?
fi

mkdir -p "$output_dir"
output_dir=$(cd "$output_dir" && pwd)
stem=$(basename "${file_array[0]%/}")
stem="${stem%%.*}"
if [[ ${#sample_array[@]} -gt 0 ]]
then
    stem="${sample_array[0]}"
fi
html_out="$output_dir/${stem}-log-report.html"
if ! python3 -I "$root_folder/tools/log-analyzer/log_report.py" "${report_args[@]}" --html-out "$html_out"
then
    logerror "❌ could not write the HTML report"
    exit 1
fi
log "✅ HTML report saved: $html_out"
# only open a browser in an interactive terminal
if [[ -t 1 ]] && [ -z "$GITHUB_RUN_NUMBER" ] && command -v open &>/dev/null
then
    log "🌐 Opening $html_out in browser..."
    open "$html_out"
else
    log "🔗 Open in browser: file://$html_out"
fi
