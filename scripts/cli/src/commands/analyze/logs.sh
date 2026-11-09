eval "file_array=(${args[--file]})"
eval "sample_array=(${args[--sample]})"
# the WARN records are reported by default (--errors-only leaves them out): the Kafka clients log real problems at WARN
# (consumer poll timeout, records expiring in the producer); --include-warnings is kept for compatibility, and for a CFK
# bundle it still adds the WARN records that match no known category (cfk-analysis --include-warnings)
errors_only="${args[--errors-only]}"
cfk_include_warnings="${args[--include-warnings]}"
include_warnings=1
if [[ -n "$errors_only" ]]
then
    include_warnings=""
fi
max_findings="${args[--max-findings]}"
output_dir="${args[--output-dir]}"
json_out="${args[--json]}"
logs_only="${args[--logs-only]}"
severity="${args[--severity]}"
want_sanitize="${args[--sanitize]}"
eval "component_array=(${args[--component]})"
eval "connector_array=(${args[--connector]})"
with_worker="${args[--with-worker]}"
show_config="${args[--show-config]}"
json_sections="${args[--json-sections]}"
problem="${args[--problem]}"
eval "compare_array=(${args[--compare]})"
since="${args[--since]}"
until_ts="${args[--until]}"

# with --json, logs and the text digest go to stderr and only the analysis to stdout (same as analyze thread-dump)
if [[ -n "$json_out" ]]
then
    exec 3>&1 1>&2
fi
# the jq binary (not the jq function of the playground, which runs it in a container): configs of the input, --sanitize,
# --compare, --json. Checked first, the analysis works offline without a container engine
if ! type -P jq > /dev/null 2>&1
then
    logerror "❌ analyze logs needs jq: brew install jq, apt install jq, dnf install jq, apk add jq"
    exit 1
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

# --since / --until: "2026-11-06 10:00", "2026-11-06T10:00:00" or "2026-11-06", as 2026-11-06T10:00:00 (compared as text
# with the time of each line, as written in the logs)
function normalize_window_time () {
    local t="${1/ /T}"
    if [[ "$t" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then t="${t}T00:00:00"
    elif [[ "$t" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}$ ]]; then t="${t}:00"
    elif [[ ! "$t" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then return 1
    fi
    echo "$t"
}
if [[ -n "$since" ]] && ! since=$(normalize_window_time "$since")
then
    logerror "❌ --since ${args[--since]}: expected \"2026-11-06 10:00\", \"2026-11-06T10:00:00\" or \"2026-11-06\""
    exit 1
fi
if [[ -n "$until_ts" ]] && ! until_ts=$(normalize_window_time "$until_ts")
then
    logerror "❌ --until ${args[--until]}: expected \"2026-11-06 10:00\", \"2026-11-06T10:00:00\" or \"2026-11-06\""
    exit 1
fi
if [[ -n "$since" || -n "$until_ts" ]]
then
    log "⏱️ Only the lines logged ${since:+at or after ${since/T/ }}${since:+${until_ts:+ and }}${until_ts:+before ${until_ts/T/ }} (--since / --until)"
fi

# the lines out of the window of --since / --until become empty lines (the line numbers stay those of the file, for the
# links of the report); a line without its own time (a stack frame, the next line of a message) follows the line before
function log_window_filter () {
    if [[ -z "$since" && -z "$until_ts" ]]
    then
        cat
        return
    fi
    LC_ALL=C awk -v since="$since" -v until_ts="$until_ts" '
        {
            h = substr($0, 1, 120)
            if (match(h, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][ T][0-9][0-9]:[0-9][0-9]:[0-9][0-9]/)) {
                t = substr(h, RSTART, RLENGTH)
                sub(/ /, "T", t)
                keep = (since == "" || t >= since) && (until_ts == "" || t < until_ts)
            } else if (NR == 1) {
                keep = (since == "")
            }
            print (keep ? $0 : "")
        }'
}

# ── Sample mode: logs shipped in tools/log-analyzer/samples ──
for sample in "${sample_array[@]}"
do
    case "$sample" in
        connect_task_failure) file_array+=("$root_folder/tools/log-analyzer/samples/connect-oracle-xstream-task-failure.log") ;;
        connect_many_connectors) file_array+=("$root_folder/tools/log-analyzer/samples/connect-many-connectors.log") ;;
        support_bundle) file_array+=("$root_folder/tools/log-analyzer/samples/support-bundle.zip") ;;
        kafka_streams) file_array+=("$root_folder/tools/log-analyzer/samples/kafka-streams") ;;
        kafka_clients) file_array+=("$root_folder/tools/log-analyzer/samples/kafka-clients") ;;
        # the day after a fix, compared with the day before (unless --compare names another input)
        compare_fix)
            file_array+=("$root_folder/tools/log-analyzer/samples/compare/after.log")
            [[ ${#compare_array[@]} -eq 0 ]] && compare_array=("$root_folder/tools/log-analyzer/samples/compare/before.log")
            ;;
        cfk_bundle) file_array+=("$root_folder/cfk-analysis/samples/cfk-support-bundle-synthetic.tar.gz") ;;
        cfk_kraft_migration) file_array+=("$root_folder/cfk-analysis/samples/cfk-support-bundle-kraft-migration.tar.gz") ;;
        cfk_rollout) file_array+=("$root_folder/cfk-analysis/samples/cfk-support-bundle-rollout.tar.gz") ;;
        cfk_rollout_after) file_array+=("$root_folder/cfk-analysis/samples/cfk-support-bundle-rollout-after.tar.gz") ;;
    esac
done

# the TAB picker of --file (get-log-files-with-fzf) answers "<typed>@<path>": the path is what follows the first @, unless
# the value is an existing path as it is
for i in "${!file_array[@]}"
do
    if [[ ! -e "${file_array[$i]}" && "${file_array[$i]}" == *"@"* ]]
    then
        file_array[$i]="${file_array[$i]#*@}"
    fi
done

for file in "${file_array[@]}"
do
    if [ ! -e "$file" ]
    then
        logerror "❌ <$file> does not exist, please make sure to use absolute full path or correct relative path !"
        exit 1
    fi
done

if [[ -n "$with_worker" && ${#connector_array[@]} -eq 0 ]]
then
    logwarn "⚠️ --with-worker only applies with --connector"
    with_worker=""
fi
# --connector: the digest of each file (summarize_log_errors) prints only the records of these connectors
export PG_LOG_DIGEST_CONNECTORS="${connector_array[*]}"
export PG_LOG_DIGEST_WITH_WORKER="$with_worker"

# bytes of a file (0 when it cannot be read)
function file_size () {
    wc -c < "$1" 2>/dev/null | tr -d ' ' || echo 0
}

function file_size_human () {
    python3 -I "$root_folder/tools/log-analyzer/progress.py" human "$(file_size "$1")" 2>/dev/null
}

# opens a report written by another tool in the browser, once: the 🔄 progress page already open goes to it, else a new
# tab in an interactive terminal (open_html_report), else its path
function show_report () {
    if [ -n "$progress_page" ] && [ -f "$progress_page" ] && grep -q "Log Analysis in progress" "$progress_page" 2>/dev/null
    then
        python3 -I -c 'import html, sys, urllib.parse; u = "file://" + urllib.parse.quote(sys.argv[1]); print(f"<!DOCTYPE html><html><head><meta charset=\"utf-8\"><meta http-equiv=\"refresh\" content=\"0; url={html.escape(u)}\"></head><body><a href=\"{html.escape(u)}\">{html.escape(sys.argv[1])}</a></body></html>")' "$1" > "$progress_page.redirect" \
            && mv "$progress_page.redirect" "$progress_page"
        log "🌐 The page open in the browser shows $1"
    else
        open_html_report "$1"
    fi
}

# a step of the 🔄 progress page open in the browser (none without it)
function progress_step () {
    if [ -n "${PG_PROGRESS_HTML:-}" ]
    then
        python3 -I "$root_folder/tools/log-analyzer/progress.py" page --step "$1" 2>/dev/null || true
    fi
}

analyze_started=$SECONDS
tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)

# 🔄 large inputs (20 MB or more), in an interactive terminal: the report is opened in the browser right away, as a
# progress page (step, bytes read, elapsed time) that reloads every 2 s until the report replaces it at the same path
# (tools/log-analyzer/progress.py). Ended by an EXIT trap when there is no log report (only CFK bundles, failure)
progress_page=""
function finish_progress_page () {
    if [ -n "$progress_page" ] && [ -f "$progress_page" ] && grep -q "Log Analysis in progress" "$progress_page" 2>/dev/null
    then
        printf '%s\n' '<!DOCTYPE html><html><head><meta charset="utf-8"><title>playground analyze logs</title></head>' \
            '<body style="font-family: sans-serif; margin: 4rem auto; max-width: 46rem">' \
            '<h1>🔥 Log Analysis ended without a log report</h1>' \
            '<p>A CFK support bundle has its own report, or the analysis stopped: see the terminal.</p></body></html>' > "$progress_page"
    fi
}
# Ctrl-C, or an error: the digests still running in the background (see analyze_logs_digest) are stopped first. A
# background job of a script ignores SIGINT, so it would otherwise go on reading its file after the command ended, and
# fail on the tmp dir deleted under it ("awk: can't open file .../digests/1.records")
function stop_digest_jobs () {
    local pid
    # -r: the running ones (jobs -p also lists a job that has ended)
    for pid in $(jobs -rp)
    do
        kill_tree "$pid"
    done
}
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'stop_digest_jobs; finish_progress_page; rm -rf $tmp_dir' EXIT
else
    trap 'stop_digest_jobs; finish_progress_page' EXIT
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi
if [[ -z "$json_out" ]] && { [[ -t 1 ]] || [ -n "${PLAYGROUND_RUN_LOG_TERMINAL:-}" ]; } && [ -z "$GITHUB_RUN_NUMBER" ] \
    && command -v python3 > /dev/null 2>&1 && { command -v open > /dev/null 2>&1 || command -v xdg-open > /dev/null 2>&1; }
then
    read -r input_total_bytes input_total_files input_has_archive < <(python3 -I "$root_folder/tools/log-analyzer/progress.py" size "${file_array[@]}" 2>/dev/null || echo "0 0 1")
    if [ "${input_total_bytes:-0}" -ge $((20 * 1024 * 1024)) ]
    then
        mkdir -p "$output_dir"
        report_stem=$(basename "${file_array[0]%/}")
        report_stem="${report_stem%%.*}"
        progress_page="$(cd "$output_dir" && pwd)/${report_stem}-log-report.html"
        export PG_PROGRESS_HTML="$progress_page" PG_PROGRESS_TITLE="playground analyze logs ${file_array[*]}" PG_PROGRESS_STARTED="$(date +%s)"
        # the whole input: an archive counts for its size until it is extracted, then for the size of its content
        # (progress_add_extracted), so the bar is exact once the archives are extracted
        export PG_PROGRESS_TOTAL="$input_total_files" PG_PROGRESS_TOTAL_BYTES="$input_total_bytes" PG_PROGRESS_DONE=0 PG_PROGRESS_BYTES=0
        progress_step "🔎 starting: $(python3 -I "$root_folder/tools/log-analyzer/progress.py" human "$input_total_bytes") to analyze"
        log "🌐 Opening $progress_page in browser: it shows the progress, then the report"
        if command -v open > /dev/null 2>&1
        then
            open "$progress_page"
        else
            xdg-open "$progress_page" > /dev/null 2>&1 || true
        fi
    fi
fi

# every distinct record, for the HTML report and --json (see summarize_log_errors)
records_file="$tmp_dir/records"
: > "$records_file"
# the config files of the input (append_config_file), added to the records file once every digest is in it: written
# right away, before the @@PGFILE@@ of any digest (they run in the background), they were dropped by log_report.py
config_records_file="$tmp_dir/config-records"
: > "$config_records_file"
# label<tab>path on disk<tab>1 when the file stays there after the command (not extracted to $tmp_dir) of each file
# analyzed: the HTML report writes a page per file with findings next to it, its locations (connect.log:33) link to
# them, and its ✏️ open the file in the editor (a copy for the extracted ones)
sources_file="$tmp_dir/sources"
: > "$sources_file"
# label<tab>format<tab>number of events of each JSON / CSV export converted back to log lines (🔭 overview)
exports_file="$tmp_dir/exports"
: > "$exports_file"
# label<tab>reason of each input not fully read (digest failed, truncated gzip, archive not fully extracted): a ⚠️ in the
# terminal, in the HTML report and in --json (.summary.incomplete_inputs), never a silent ✅
incomplete_file="$tmp_dir/incomplete"
: > "$incomplete_file"
# label<tab>path of every file of the input (archives extracted): the 🧰 bundle triage looks there for the GC logs,
# thread dumps, heap dumps, flight recordings, network captures and XStream reports (tools/log-analyzer/bundle_triage.py)
walked_file="$tmp_dir/walked"
: > "$walked_file"
# $1: label, $2: reason
function note_incomplete () {
    logwarn "⚠️ $1: $2"
    printf '%s\t%s\n' "$1" "$2" >> "$incomplete_file"
}
nb_files=0
nb_bytes=0
nb_files_with_findings=0
nb_skipped=0
nb_duplicates=0
# files analyzed so far, to skip a copy (a folder with an archive and its extracted folder): label by size, and the
# checksum of each file, computed only when two files have the same size
declare -A seen_by_size=()
declare -A checksum_of=()

# returns 0 (and logs it) when the file has the same content as a file already analyzed
# $1: path, $2: label
function is_duplicate_file () {
    local path="$1"
    local label="$2"
    local size other sum
    size=$(wc -c < "$path" | tr -d ' ')
    if [ -n "${seen_by_size[$size]}" ]
    then
        sum=$(cksum < "$path")
        while IFS= read -r other
        do
            [ -z "$other" ] && continue
            if [ -z "${checksum_of[$other]}" ]
            then
                checksum_of[$other]=$(cksum < "${other%%$'\t'*}")
            fi
            if [ "${checksum_of[$other]}" == "$sum" ]
            then
                log "⏭️  $label: same content as ${other#*$'\t'}, skipped"
                nb_duplicates=$((nb_duplicates+1))
                return 0
            fi
        done <<< "${seen_by_size[$size]}"
    fi
    seen_by_size[$size]+="$path"$'\t'"$label"$'\n'
    return 1
}
nb_extracted=0
# --sanitize: secrets, IPs, hostnames, emails and LDAP DNs of the digests and of the records file are redacted (best
# effort), with the same placeholder for a value everywhere (state file of tools/report-common/sanitizer.py)
sanitizer="$root_folder/tools/report-common/sanitizer.py"
# PG_SANITIZE_STATE: the state of the run that started this one (--compare): the same placeholder for a value in both
sanitize_state="${PG_SANITIZE_STATE:-$tmp_dir/sanitize-state.json}"
sanitize=""
no_sanitize=1
if [[ -n "$want_sanitize" ]]
then
    if command -v python3 &>/dev/null
    then
        sanitize=1
        no_sanitize=""
    else
        logwarn "⚠️ python3 is not on PATH: the output is NOT sanitized (passwords, IPs, hostnames…), review it before sharing"
    fi
else
    log "🔓 Not sanitized: --sanitize replaces secrets, IPs and hostnames by placeholders before sharing the output outside Confluent"
fi
# $1: file, sanitized in place
function sanitize_file () {
    if [[ -n "$sanitize" ]] && python3 -I "$sanitizer" --state "$sanitize_state" < "$1" > "$1.sanitized"
    then
        mv "$1.sanitized" "$1"
    fi
}

# CFK support bundles found in the input (folder and label), analyzed by cfk-analysis instead of the log digest
cfk_bundles=()
cfk_labels=()
# fingerprint (relative path and size of each file) of each CFK bundle, to skip a copy (an archive next to its
# extracted folder): fingerprint -> label
declare -A cfk_fingerprints=()

# returns 0 (and logs it) when the folder has the same files as a CFK bundle already found
# $1: folder, $2: label
function is_duplicate_cfk_bundle () {
    local fingerprint
    fingerprint=$(cd "$1" && find . -type f ! -path "*/__MACOSX/*" ! -name ".DS_Store" -exec wc -c {} + | grep -v ' total$' | sed 's/^ *//' | LC_ALL=C sort | cksum)
    if [ -n "${cfk_fingerprints[$fingerprint]}" ]
    then
        log "⏭️  $2: same CFK support bundle as ${cfk_fingerprints[$fingerprint]}, skipped"
        nb_duplicates=$((nb_duplicates+1))
        return 0
    fi
    cfk_fingerprints[$fingerprint]="$2"
    return 1
}

# a folder written by kubectl confluent support-bundle (or playground debug cfk generate-bundle): cluster-details.txt
# and cluster-resources/ at the top, or operator/ next to a <namespace>/ folder with them (older layout). Also a flat
# collection of kubectl outputs made by hand (kubectl logs > kafka-0.log, kubectl get kafka -o yaml > kafka.yaml…): a
# log of the CFK operator, or the YAML of a platform.confluent.io custom resource, at the top of the folder
# $1: folder
function is_cfk_bundle () {
    local d
    [ -f "$1/cluster-details.txt" ] && return 0
    if [ -d "$1/operator" ]
    then
        [ -d "$1/cluster-resources" ] && return 0
        for d in "$1"/*/cluster-details.txt
        do
            [ -f "$d" ] && return 0
        done
    fi
    # the operator/ folder of a support bundle has the logs of the operator: it is not a bundle on its own
    [ "$(basename "$1")" == "operator" ] && return 1
    for d in "$1"/confluent-operator*.log "$1"/*.yaml "$1"/*.yml
    do
        [ -f "$d" ] || continue
        case "$(basename "$d")" in
            confluent-operator*.log) return 0 ;;
        esac
        head -n 20 "$d" 2>/dev/null | grep -q 'apiVersion: platform.confluent.io/' && return 0
    done
    return 1
}

# a JSON or CSV export of log events (CloudWatch Logs Insights, Elasticsearch / OpenSearch, Kibana Discover CSV,
# structured JSON logs, JSON lines of fluentd / Kubernetes / logstash): converted back to log lines, oldest first
# (tools/log-analyzer/json_log_export.py, JSON lines streamed), so that the records, their stack traces and the line
# numbers of the HTML report are those of a log file. Returns 1 when it is not an export of log events: the caller
# reads the file as it is. $1: path, $2: label, $3: format shown (JSON, CSV, JSON lines)
function analyze_logs_export () {
    local path="$1"
    local label="$2"
    local export_format="$3"
    local converted nb_events
    nb_extracted=$((nb_extracted+1))
    converted=$(basename "$path")
    converted="$tmp_dir/$nb_extracted/${converted%%.*}.log"
    mkdir -p "$(dirname "$converted")"
    # stderr kept: the progress bar of a large file
    if nb_events=$(PG_PROGRESS_STEP="🔄 converting $label ($export_format export)" python3 -I "$root_folder/tools/log-analyzer/json_log_export.py" "$path" "$converted")
    then
        log "🔄 $label: $export_format export of $nb_events log events ($(file_size_human "$path")), analyzed as log lines (oldest first)"
        printf '%s\t%s\t%s\n' "$label" "$export_format" "$nb_events" >> "$exports_file"
        analyze_logs_digest "$label" "$converted" "$path"
        return 0
    fi
    rm -f "$converted"
    return 1
}

# logs a customer pasted in a Word / LibreOffice Writer document, or a sheet a log tool exported to Excel / LibreOffice
# Calc (tools/log-analyzer/office_export.py, standard library): converted back to log lines and analyzed as a log file;
# the pictures of the document (screenshots of a log) are extracted and walked, so that 🧰 Other files of the input
# lists them. $1: path, $2: label
function analyze_logs_office () {
    local path="$1"
    local label="$2"
    local converted out rc fmt nb pictures media img
    nb_extracted=$((nb_extracted+1))
    converted="$tmp_dir/$nb_extracted/$(basename "$path").log"
    media="$tmp_dir/$nb_extracted/media"
    mkdir -p "$(dirname "$converted")"
    out=$(python3 -I "$root_folder/tools/log-analyzer/office_export.py" "$path" "$converted" "$media" 2> "$converted.err")
    rc=$?
    IFS=$'\t' read -r fmt nb pictures <<< "$out"
    if [ $rc -eq 0 ]
    then
        log "📄 $label: $([[ "$fmt" == *export ]] && echo "$fmt, ${nb} log events" || echo "$fmt document, ${nb} lines") ($(file_size_human "$path")), analyzed as log lines"
        # a sheet of a log console: like the JSON / CSV exports (the overview says the console exported the newest rows)
        if [[ "$fmt" == *export ]]
        then
            printf '%s\t%s\t%s\n' "$label" "$fmt" "$nb" >> "$exports_file"
        fi
        analyze_logs_digest "$label" "$converted" "$path"
    elif [ $rc -eq 2 ]
    then
        logwarn "⚠️ $label: $fmt document without text: nothing to analyze"
        nb_skipped=$((nb_skipped+1))
    else
        logwarn "⚠️ $label: cannot read this document ($(head -n 1 "$converted.err")): save it again as .docx / .xlsx, or ask for the logs as text"
        nb_skipped=$((nb_skipped+1))
    fi
    if [[ "${pictures:-0}" =~ ^[1-9][0-9]*$ ]]
    then
        logwarn "🖼️ $label holds $pictures picture(s) (screenshots of a log?): not analyzed, listed in 🧰 Other files of the input"
        for img in "$media"/*
        do
            [ -f "$img" ] && printf '%s\t%s\n' "$label:$(basename "$img")" "$img" >> "$walked_file"
        done
    fi
}

# the digest of each file runs in the background, PLAYGROUND_LOG_PARALLELISM at a time (4 by default, 1: one at a time,
# with the progress bar of a large file), each into its own part files; collect_digests merges them in the order of the
# input: the records file, the counters and the output are the same as one at a time
log_parallelism="${PLAYGROUND_LOG_PARALLELISM:-4}"
[[ "$log_parallelism" =~ ^[1-9][0-9]*$ ]] || log_parallelism=4
digest_parts="$tmp_dir/digests"
mkdir -p "$digest_parts"
nb_digests=0

# the digest of one log
# $1: label to display, $2: path of the file read, $3: the file it comes from (a JSON / CSV export converted), for its
# size, $4: "gz" to decompress it (a truncated or corrupt .gz, a partial download, is read up to the error, and said so)
function analyze_logs_digest () {
    local label="$1" path="$2" origin="${3:-$2}" gz="${4:-}"
    printf '%s\t%s\t%s\n' "$label" "$path" "$([[ "$path" == "$tmp_dir/"* ]] || echo 1)" >> "$sources_file"
    nb_digests=$((nb_digests+1))
    local part="$digest_parts/$nb_digests"
    printf '%s\t%s\n' "$label" "$(file_size "$origin")" > "$part.meta"
    if [ "$log_parallelism" -gt 1 ]
    then
        while [ "$(jobs -rp | wc -l | tr -d ' ')" -ge "$log_parallelism" ]
        do
            wait -n 2> /dev/null || true
            progress_digests
        done
        digest_one "$label" "$path" "$origin" "$gz" "$part" "" &
        progress_digests "$label"
    else
        digest_one "$label" "$path" "$origin" "$gz" "$part" 1
        report_digest "$part"
    fi
}

# $1: label, $2: path, $3: origin, $4: gz, $5: part (files written: .out, .rc, .records, .gzerr), $6: 1 in the foreground
function digest_one () {
    local label="$1" path="$2" origin="$3" gz="$4" part="$5" foreground="$6"
    local reader=(cat "$path")
    [ -n "$gz" ] && reader=(gzip -dc "$path")
    # a progress bar in the terminal for a large file (and the progress page), one file at a time only
    if [ -n "$foreground" ] && [[ -t 2 || -n "${PG_PROGRESS_HTML:-}" ]] && command -v python3 > /dev/null 2>&1
    then
        local size_args=()
        if [ -z "$gz" ] && [ -f "$path" ]
        then
            size_args=(--size "$(file_size "$path")")
        fi
        # a converted export: the conversion moved the whole input bar (it reads the original), the digest of the
        # converted file only moves the bar of the file
        local counts=1
        [ "$origin" != "$path" ] && counts=0
        "${reader[@]}" 2> "$part.gzerr" | PG_PROGRESS_COUNTS="$counts" PG_PROGRESS_STEP="🔎 ERROR/FATAL digest of $label" python3 -I "$root_folder/tools/log-analyzer/progress.py" cat --label "$label" "${size_args[@]}" | log_window_filter | PG_LOG_DIGEST_RECORDS_FILE="$part.records" PG_LOG_DIGEST_LABEL="$label" summarize_log_errors "$max_findings" "$include_warnings" > "$part.out"
    else
        "${reader[@]}" 2> "$part.gzerr" | log_window_filter | PG_LOG_DIGEST_RECORDS_FILE="$part.records" PG_LOG_DIGEST_LABEL="$label" summarize_log_errors "$max_findings" "$include_warnings" > "$part.out"
    fi
    echo "${PIPESTATUS[-1]}" > "$part.rc"
}

# merges one digest: its records into the records file, its warnings, its counters, and prints it when it has findings
# $1: part
function report_digest () {
    local part="$1" label input_bytes rc output
    IFS=$'\t' read -r label input_bytes < "$part.meta"
    rc=$(cat "$part.rc" 2> /dev/null || echo 1)
    output=$(cat "$part.out" 2> /dev/null)
    [ -f "$part.records" ] && cat "$part.records" >> "$records_file"
    touch "$part.done"
    if [ -s "$part.gzerr" ]
    then
        # the first line that is not empty: GNU gzip starts its message with a new line
        note_incomplete "$label" "truncated or corrupt gzip, read only up to the error ($(grep -m 1 . "$part.gzerr" | sed 's/^gzip: //'))"
    fi
    if [ "$rc" != "0" ]
    then
        note_incomplete "$label" "the digest failed (exit $rc): records of this file may be missing"
    fi
    nb_files=$((nb_files+1))
    nb_bytes=$((nb_bytes+${input_bytes:-0}))
    if [[ "$output" == "✅"* ]]
    then
        return
    fi
    nb_files_with_findings=$((nb_files_with_findings+1))
    if [[ -n "$sanitize" ]]
    then
        # --no-count: the records file, sanitized at the end, has the same records
        output=$(printf '%s\n' "$output" | python3 -I "$sanitizer" --state "$sanitize_state" --no-count)
    fi
    log "🔥 ERROR/FATAL digest for $label"
    # there is no --since here
    echo "$output" | sed 's/ or narrow with --since$//'
    echo ""
}

# the 🔄 progress page while the digests run in the background (they have no progress bar of their own): the files
# digested out of those queued, and the whole input bar without the files queued but not digested yet (analyze_logs_path
# counts a file as done once its digest is started). At most every 2 s, or $2=force. $1: the file just started
progress_digests_last=-1
progress_digests_current=""
function progress_digests () {
    [ -n "${PG_PROGRESS_HTML:-}" ] && [ "$log_parallelism" -gt 1 ] || return 0
    [ -n "${1:-}" ] && progress_digests_current="$1"
    [ "${2:-}" == "force" ] || [ $((SECONDS - progress_digests_last)) -ge 2 ] || return 0
    progress_digests_last=$SECONDS
    local i finished=0 pending_bytes=0 pending_files=0 label input_bytes
    for (( i = 1; i <= nb_digests; i++ ))
    do
        if [ -f "$digest_parts/$i.rc" ]
        then
            finished=$((finished+1))
        else
            IFS=$'\t' read -r label input_bytes < "$digest_parts/$i.meta"
            pending_bytes=$((pending_bytes+${input_bytes:-0}))
            pending_files=$((pending_files+1))
        fi
    done
    local done_bytes=$(( ${PG_PROGRESS_BYTES:-0} - pending_bytes )) done_files=$(( ${PG_PROGRESS_DONE:-0} - pending_files ))
    [ $done_bytes -ge 0 ] || done_bytes=0
    [ $done_files -ge 0 ] || done_files=0
    PG_PROGRESS_BYTES=$done_bytes PG_PROGRESS_DONE=$done_files progress_step "🔎 ERROR/FATAL digest: $finished of $nb_digests file(s) done, $log_parallelism at a time${progress_digests_current:+ (last started: $progress_digests_current)}"
}

# waits for the digests running in the background and merges them, in the order of the input
function collect_digests () {
    while [ -n "$(jobs -rp)" ]
    do
        wait -n 2> /dev/null || true
        progress_digests
    done
    wait
    [ "$nb_digests" -gt 0 ] && progress_digests "" force
    local i
    for (( i = 1; i <= nb_digests; i++ ))
    do
        [ -f "$digest_parts/$i.done" ] || report_digest "$digest_parts/$i"
    done
}

# digest of a .gz file: decompressed on the fly (a truncated or corrupt one is read up to the error, and said so)
# $1: label, $2: path
function analyze_logs_gzip () {
    analyze_logs_digest "$1" "$2" "$2" gz
}

# config files of the input for the ⚙️ Configuration section of the report (see summarize_log_errors): a .properties
# file, or a JSON file with connector configs (a connector config, {name, config}, the output of /connectors?expand=info),
# or the output of GET /connector-plugins (the versions installed)
# $1: path, $2: label
function append_config_file () {
    local path="$1"
    local label="$2"
    case "$path" in
        *.properties)
            printf '@@PGCFG@@\t%s\tfile\t\t\t\n' "$(basename "$path")" >> "$config_records_file"
            grep -v '^[[:space:]]*[#!]' "$path" 2>/dev/null | grep '=' | sed 's/^[[:space:]]*//; s/[[:space:]]*=[[:space:]]*/=/; s/^/@@PGCFGL@@\t/' >> "$config_records_file"
            ;;
        *.json)
            # a big JSON is data, not a config
            [ "$(wc -c < "$path" | tr -d ' ')" -lt 5000000 ] || return 0
            # the output of GET /connector-plugins: the version of each plugin installed on the worker (the version of a
            # connector whose logs miss its startup)
            if jq -e 'type == "array" and length > 0 and all(.[]; type == "object" and has("class") and has("version") and has("type"))' "$path" > /dev/null 2>&1
            then
                printf '@@PGCFG@@\tconnector plugins\tfile\t\t\t%s\n' "$label" >> "$config_records_file"
                jq -r '.[] | "@@PGCFGL@@\t\(.class)=\(.version)"' "$path" >> "$config_records_file" 2>/dev/null
                return 0
            fi
            jq -r '
                def configs:
                    if type == "array" then .[] | configs
                    elif type != "object" then empty
                    elif has("connector.class") then {name: (.name // ""), config: .}
                    elif (.config | type) == "object" and (.config | has("connector.class")) then {name: (.name // .config.name // ""), config: .config}
                    elif (.info.config | type) == "object" then {name: (.info.name // .info.config.name // ""), config: .info.config}
                    else .[] | select(type == "object") | configs
                    end;
                configs | "@@PGCFG@@\tconnector config\tfile\t\t\t\(.name)", (.config | to_entries[] | "@@PGCFGL@@\t\(.key)=\(.value | tostring)")
            ' "$path" >> "$config_records_file" 2>/dev/null
            ;;
    esac
}

# analyzes a file, a folder or an archive, recursively
# $1: path, $2: label to display
# the 🔄 progress page: a file of the input handled (digested, converted, skipped as binary or as a copy) counts as done
# with its size on disk
function analyze_logs_path () {
    if [ -f "$1" ] && ! is_archive_path "$1"
    then
        printf '%s\t%s\n' "$2" "$1" >> "$walked_file"
    fi
    analyze_logs_path_entry "$@"
    if [ -n "${PG_PROGRESS_HTML:-}" ] && [ -f "$1" ] && ! is_archive_path "$1"
    then
        progress_add_done "$(file_size "$1")" 1
    fi
}

function is_archive_path () {
    case "$1" in
        *.zip|*.tar|*.tar.gz|*.tgz|*.tar.bz2|*.tbz2|*.tar.xz|*.txz|*.7z) return 0 ;;
    esac
    return 1
}

# $1: bytes, $2: files, now done (progress page)
function progress_add_done () {
    export PG_PROGRESS_BYTES=$(( ${PG_PROGRESS_BYTES:-0} + ${1:-0} )) PG_PROGRESS_DONE=$(( ${PG_PROGRESS_DONE:-0} + ${2:-0} ))
}

# a folder already counted elsewhere (a CFK support bundle, analyzed on its own, or a copy of one): its files are done
function progress_add_done_folder () {
    if [ -n "${PG_PROGRESS_HTML:-}" ]
    then
        local bytes files archive
        read -r bytes files archive < <(python3 -I "$root_folder/tools/log-analyzer/progress.py" size "$1" 2>/dev/null || echo "0 0 0")
        progress_add_done "$bytes" "$files"
    fi
}

# an archive extracted: it counts for its content instead of its size in the whole input. $1: archive, $2: folder
function progress_add_extracted () {
    if [ -n "${PG_PROGRESS_HTML:-}" ]
    then
        local bytes files archive
        read -r bytes files archive < <(python3 -I "$root_folder/tools/log-analyzer/progress.py" size "$2" 2>/dev/null || echo "0 0 0")
        export PG_PROGRESS_TOTAL_BYTES=$(( ${PG_PROGRESS_TOTAL_BYTES:-0} - $(file_size "$1") + bytes )) \
               PG_PROGRESS_TOTAL=$(( ${PG_PROGRESS_TOTAL:-0} - 1 + files ))
    fi
}

# the pod and operator logs of a CFK support bundle (its *.log files) also go through the log digest: the regular log
# report (root causes, timeline, connectors, versions, tasks by worker, known bugs, data to request, summary for a
# ticket), with the sections of the bundle (pods, custom resources, events, versions, recent changes) right after its
# verdict: one report. $1: bundle folder, $2: its label
in_cfk_walk=""
# a file of the input outside the CFK bundles: with only bundles, --json keeps the shape of cfk-analysis
other_inputs=""
nb_cfk_log_files=0
function walk_cfk_bundle_logs () {
    local path="$1"
    local label="$2"
    local f
    in_cfk_walk=1
    while IFS= read -r -d '' f
    do
        nb_cfk_log_files=$((nb_cfk_log_files+1))
        printf '%s\t%s\n' "${label%/}/${f#$path/}" "$f" >> "$walked_file"
        if [[ "$label" == *":" ]]
        then
            analyze_logs_path_entry "$f" "${label}${f#$path/}"
        else
            analyze_logs_path_entry "$f" "${label%/}/${f#$path/}"
        fi
    done < <(find "$path" -type f \( -name '*.log' -o -name '*.log.gz' -o -name '*.log.[0-9]*' \) ! -path "*/__MACOSX/*" -print0 | sort -z)
    in_cfk_walk=""
}

function analyze_logs_path_entry () {
    local path="$1"
    local label="$2"
    local extract_dir
    local f

    if [ -d "$path" ]
    then
        if [[ -z "$logs_only" ]] && is_cfk_bundle "$path"
        then
            if ! is_duplicate_cfk_bundle "$path" "${label%:}"
            then
                cfk_bundles+=("$path")
                cfk_labels+=("${label%:}")
                walk_cfk_bundle_logs "$path" "$label"
            else
                progress_add_done_folder "$path"
            fi
            return
        fi
        # CFK bundles in sub folders: analyzed on their own, their files are left out of the log digest
        local prune=()
        local found_bundles=()
        local -A checked_dirs=()
        local bundle_dir
        local d
        if [[ -z "$logs_only" ]]
        then
            while IFS= read -r -d '' f
            do
                bundle_dir=$(dirname "$f")
                # inside a bundle already found (the CR yamls and operator log of a support bundle), or checked
                for d in "${found_bundles[@]}"
                do
                    [[ "$bundle_dir/" == "$d/"* ]] && continue 2
                done
                [ -n "${checked_dirs[$bundle_dir]}" ] && continue
                checked_dirs[$bundle_dir]=1
                # <bundle>/<namespace>/cluster-details.txt (older layout): the bundle is the folder above
                if [ "$(dirname "$bundle_dir")" != "$path" ] && is_cfk_bundle "$(dirname "$bundle_dir")"
                then
                    bundle_dir=$(dirname "$bundle_dir")
                fi
                if is_cfk_bundle "$bundle_dir"
                then
                    case " ${prune[*]} " in *" -path $bundle_dir "*) continue ;; esac
                    found_bundles+=("$bundle_dir")
                    [ ${#prune[@]} -gt 0 ] && prune+=(-o)
                    prune+=(-path "$bundle_dir")
                    if [[ "$label" == *":" ]]
                    then
                        analyze_logs_path "$bundle_dir" "${label}${bundle_dir#$path/}"
                    else
                        analyze_logs_path "$bundle_dir" "${label%/}/${bundle_dir#$path/}"
                    fi
                fi
            # the support bundles first, then the flat collections of kubectl outputs (operator log, CR yamls), so that the
            # files of a support bundle are never taken for a flat collection
            done < <(find "$path" -mindepth 2 \( -name cluster-details.txt -o -name cluster-resources \) ! -path "*/__MACOSX/*" -print0 | sort -z
                     find "$path" -mindepth 2 -type f \( -name 'confluent-operator*.log' -o -name '*.yaml' -o -name '*.yml' \) ! -path "*/__MACOSX/*" -print0 | sort -z)
        fi
        if [ ${#prune[@]} -gt 0 ]
        then
            prune=(\( "${prune[@]}" \) -prune -o)
        fi
        while IFS= read -r -d '' f
        do
            if [[ "$label" == *":" ]]
            then
                analyze_logs_path "$f" "${label}${f#$path/}"
            else
                analyze_logs_path "$f" "${label%/}/${f#$path/}"
            fi
        done < <(find "$path" "${prune[@]}" -type f ! -path "*/__MACOSX/*" ! -name ".DS_Store" -print0 | sort -z)
        return
    fi

    if [ -z "$in_cfk_walk" ] && ! is_archive_path "$path"
    then
        other_inputs=1
    fi
    case "$path" in
        *.7z)
            # bsdtar (macOS tar, libarchive) reads 7z, else 7-Zip
            local seven_zip=""
            if tar --version 2>/dev/null | grep -q bsdtar
            then
                seven_zip="tar"
            elif command -v bsdtar > /dev/null 2>&1
            then
                seven_zip="bsdtar"
            else
                seven_zip=$(command -v 7zz || command -v 7z || command -v 7za)
            fi
            if [ -z "$seven_zip" ]
            then
                logwarn "⚠️ $label: cannot extract a .7z archive without bsdtar or 7-Zip (brew install sevenzip, apt install p7zip-full / libarchive-tools): extract it and pass the folder"
                nb_skipped=$((nb_skipped+1))
                return
            fi
            nb_extracted=$((nb_extracted+1))
            extract_dir=$(basename "$path")
            extract_dir="$tmp_dir/$nb_extracted/${extract_dir%%.*}"
            mkdir -p "$extract_dir"
            case "$(basename "$seven_zip")" in
                tar|bsdtar) "$seven_zip" -xf "$path" -C "$extract_dir" > /dev/null 2>&1 ;;
                *) "$seven_zip" x -y -o"$extract_dir" "$path" > /dev/null 2>&1 ;;
            esac
            extract_rc=$?
            if [ $extract_rc -ne 0 ]
            then
                note_incomplete "$label" "could not fully extract the archive (exit $extract_rc): files may be missing"
            fi
            progress_add_extracted "$path" "$extract_dir"
            analyze_logs_path "$extract_dir" "$label:"
            ;;
        *.zip|*.tar|*.tar.gz|*.tgz|*.tar.bz2|*.tbz2|*.tar.xz|*.txz)
            nb_extracted=$((nb_extracted+1))
            # named after the archive: it names the report of a CFK bundle archived without a top folder
            extract_dir=$(basename "$path")
            extract_dir="$tmp_dir/$nb_extracted/${extract_dir%%.*}"
            mkdir -p "$extract_dir"
            progress_step "📦 extracting $label ($(file_size_human "$path"))"
            case "$path" in
                # without unzip (a minimal image), the zipfile module of python3 extracts it
                *.zip)
                    if command -v unzip > /dev/null 2>&1
                    then
                        unzip -q -o "$path" -d "$extract_dir" > /dev/null 2>&1
                    else
                        python3 -I -m zipfile -e "$path" "$extract_dir" > /dev/null 2>&1
                    fi
                    ;;
                *)
                    if [[ -t 2 || -n "${PG_PROGRESS_HTML:-}" ]] && command -v python3 > /dev/null 2>&1
                    then
                        # read through progress.py cat: a bar in the terminal for a large archive. From a pipe, GNU tar
                        # needs the compression flag
                        local tar_z=""
                        case "$path" in
                            *.tar.gz|*.tgz) tar_z="z" ;;
                            *.tar.bz2|*.tbz2) tar_z="j" ;;
                            *.tar.xz|*.txz) tar_z="J" ;;
                        esac
                        PG_PROGRESS_STEP="📦 extracting $label" python3 -I "$root_folder/tools/log-analyzer/progress.py" cat --label "$label" --size "$(file_size "$path")" < "$path" \
                            | tar -x${tar_z}f - -C "$extract_dir" > /dev/null 2>&1
                        test "${PIPESTATUS[1]}" -eq 0
                    else
                        tar -xf "$path" -C "$extract_dir" > /dev/null 2>&1
                    fi
                    ;;
            esac
            extract_rc=$?
            if [ $extract_rc -ne 0 ]
            then
                note_incomplete "$label" "could not fully extract the archive (exit $extract_rc): files may be missing"
            fi
            progress_add_extracted "$path" "$extract_dir"
            analyze_logs_path "$extract_dir" "$label:"
            ;;
        *.docx|*.DOCX|*.odt|*.xlsx|*.XLSX|*.xlsm|*.ods)
            # logs pasted in a document, or exported to a spreadsheet: converted back to log lines
            if ! is_duplicate_file "$path" "$label"
            then
                analyze_logs_office "$path" "$label"
            fi
            ;;
        *.json|*.jsonl|*.ndjson|*.json.gz|*.jsonl.gz|*.ndjson.gz|*.csv|*.csv.gz)
            # a JSON or CSV export of log events (CloudWatch Logs Insights, Elasticsearch / OpenSearch, Kibana Discover CSV, structured JSON logs):
            # converted back to log lines, oldest first, so that the records, their stack traces and the line numbers
            # of the HTML report are those of a log file; any other JSON (connector configs…) is read as it is
            if is_duplicate_file "$path" "$label"
            then
                return
            fi
            local export_format=JSON
            case "$path" in
                *.csv|*.csv.gz) export_format=CSV ;;
            esac
            if analyze_logs_export "$path" "$label" "$export_format"
            then
                :
            elif [[ "$path" == *.gz ]]
            then
                analyze_logs_gzip "$label" "$path"
            else
                analyze_logs_digest "$label" "$path"
                append_config_file "$path" "$label"
            fi
            ;;
        *.gz)
            if ! is_duplicate_file "$path" "$label"
            then
                analyze_logs_gzip "$label" "$path"
            fi
            ;;
        *)
            if grep -Iq . "$path" 2>/dev/null
            then
                if ! is_duplicate_file "$path" "$label"
                then
                    # JSON lines whatever the extension (a fluentd / Kubernetes / logstash dump saved as .log): converted
                    # back to log lines, the level of {"log":"[ERROR] …"} is not seen in the raw JSON
                    if [[ "$(head -c 4096 "$path" 2>/dev/null | LC_ALL=C tr -d ' \t\r\n' | head -c 1)" == "{" ]] && analyze_logs_export "$path" "$label" "JSON lines"
                    then
                        return
                    fi
                    analyze_logs_digest "$label" "$path"
                    append_config_file "$path" "$label"
                fi
            else
                case "$path" in
                    *.rar|*.bz2|*.xz|*.zst|*.lz4)
                        logwarn "⚠️ $label: archive format not supported, extract it and pass the folder" ;;
                esac
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
collect_digests
cat "$config_records_file" >> "$records_file"
set -e

if [ ${#cfk_bundles[@]} -eq 0 ] && [[ -n "$severity" || ${#component_array[@]} -gt 0 || -n "$problem" ]]
then
    logwarn "⚠️ --component, --severity and --problem only apply to a CFK support bundle, and none was found"
fi
# --problem: matched against each CFK support bundle (cfk-analysis/problem.py)
CFK_ANALYSIS_PROBLEM="$problem"

# ── CFK support bundles: cfk-analysis (pods, custom resources, events, versions, recent changes, logs) ──
cfk_exit=0
cfk_json_files=()
# JSON of the analysis of each bundle, written next to its HTML report: compared when there are several bundles
cfk_compare_files=()
# the reports of the bundles and of their comparison are not opened one by one (6 bundles: 8 tabs): the log report links
# them, or the one entry point (the report of a single bundle, the comparison of several) is opened at the end
CFK_ANALYSIS_NO_OPEN=1
# one report: each bundle writes only its JSON and the file pages of its issues (CFK_ANALYSIS_EMBEDDED, <bundle>-cfk-files/
# next to the report), the log report shows its ☸️ sections right after its verdict (from --cluster-events)
CFK_ANALYSIS_EMBEDDED=1
cfk_reports=()
cfk_report_labels=()
# the bundles are analyzed in parallel (a container each, PLAYGROUND_CFK_PARALLELISM at a time, 4 by default): the output of
# each one goes to a file, printed in the order of the bundles as soon as it and the ones before it are done
cfk_parallelism="${PLAYGROUND_CFK_PARALLELISM:-4}"
[[ "$cfk_parallelism" =~ ^[1-9][0-9]*$ ]] || cfk_parallelism=4
if [ ${#cfk_bundles[@]} -gt 0 ]
then
    # built once, not by each job. Without a container engine (a laptop without Docker): the ☸️ sections of the bundles
    # are left out, their pod logs are in the report all the same (walk_cfk_bundle_logs), not a failure
    if ! command -v docker > /dev/null 2>&1 || ! docker info > /dev/null 2>&1
    then
        logwarn "⚠️ no container engine (docker): the ☸️ sections of the CFK support bundle(s) (pods, custom resources, events, versions) are left out, their pod and operator logs are in the report"
        cfk_bundles=()
    elif ! cfk_analyzer_image > /dev/null
    then
        cfk_exit=1
        cfk_bundles=()
    fi
fi
if [ ${#cfk_bundles[@]} -gt 1 ]
then
    log "☸️ Analyzing ${#cfk_bundles[@]} CFK support bundles, $cfk_parallelism at a time (PLAYGROUND_CFK_PARALLELISM)"
fi
if [ ${#cfk_bundles[@]} -gt 0 ]
then
    progress_step "☸️ analyzing ${#cfk_bundles[@]} CFK support bundle(s)"
    # the records of the pod and operator logs of each bundle, from the log digest (walk_cfk_bundle_logs): the CFK
    # analyzer makes its issues of the log records from them (CFK_ANALYSIS_LOG_RECORDS), the same records as the log
    # report. {path in the bundle: [records]}, raw (the CFK analyzer sanitizes its own output)
    if [ "$nb_cfk_log_files" -gt 0 ]
    then
        under_args=()
        for i in "${!cfk_bundles[@]}"
        do
            under_args+=(--records-under "${cfk_labels[$i]}")
        done
        # without the files converted from an export of log events (JSON lines): their line numbers are not those of the file
        exported=$(cut -f1 "$exports_file" | jq -R . | jq -s . 2> /dev/null || echo "[]")
        i=0
        while IFS= read -r line
        do
            printf '%s\n' "$line" | jq --argjson exported "$exported" --arg p "${cfk_labels[$i]}" \
                'with_entries(select(([$p + "/" + .key, $p + ":" + .key] - $exported | length) == 2))' > "$tmp_dir/cfk-records-$i.json" 2> /dev/null \
                || rm -f "$tmp_dir/cfk-records-$i.json"
            i=$((i+1))
        done < <(python3 -I "$root_folder/tools/log-analyzer/log_report.py" --records "$records_file" "${under_args[@]}" 2> /dev/null)
    fi
fi
# bundles of the same name (two "bundle" folders): their reports get a -<n> suffix, written in the same second
declare -A cfk_name_count=()
for i in "${!cfk_bundles[@]}"
do
    cfk_name=$(basename "${cfk_bundles[$i]}")
    cfk_name_count[$cfk_name]=$(( ${cfk_name_count[$cfk_name]:-0} + 1 ))
done
cfk_next=0
cfk_done=0
# prints the output and takes the result of the bundles done, in order
function flush_cfk_bundles () {
    local rc json html
    while [ $cfk_next -lt ${#cfk_bundles[@]} ] && [ -f "$tmp_dir/cfk-$cfk_next.result" ]
    do
        IFS=$'\t' read -r rc json html < "$tmp_dir/cfk-$cfk_next.result"
        if [[ -n "$json_out" ]]
        then
            log "📦 CFK support bundle detected: ${cfk_labels[$cfk_next]} (--logs-only for the plain log digest)"
            cat "$tmp_dir/cfk-$cfk_next.out"
            if [ "$rc" -eq 0 ]
            then
                jq --arg label "${cfk_labels[$cfk_next]}" '. + {label: $label}' "$tmp_dir/cfk-$cfk_next.json" > "$tmp_dir/cfk-$cfk_next.json.labelled" && cfk_json_files+=("$tmp_dir/cfk-$cfk_next.json.labelled")
            fi
        else
            log "📦 CFK support bundle detected: ${cfk_labels[$cfk_next]}: pods, custom resources, events, versions, recent changes and logs (--logs-only for the plain log digest)"
            cat "$tmp_dir/cfk-$cfk_next.out"
            if [ "$rc" -eq 0 ] && [ -n "$json" ] && [ -f "$json" ]
            then
                cfk_compare_files+=("$json")
            fi
            if [ -n "$html" ]
            then
                cfk_reports+=("$html")
                cfk_report_labels+=("${cfk_labels[$cfk_next]}")
            fi
        fi
        if [ "$rc" -ne 0 ]
        then
            cfk_exit=$rc
        fi
        progress_add_done_folder "${cfk_bundles[$cfk_next]}"
        cfk_next=$((cfk_next+1))
    done
}
for i in "${!cfk_bundles[@]}"
do
    # at most cfk_parallelism jobs: wait for one to end (the jobs always exit 0, their result is in a file)
    while [ "$(jobs -rp | wc -l | tr -d ' ')" -ge "$cfk_parallelism" ]
    do
        wait -n 2> /dev/null || true
        flush_cfk_bundles
    done
    (
        CFK_ANALYSIS_LABEL="${cfk_labels[$i]}"
        # extracted from an archive: deleted at the end, the report copies its files for the editor
        CFK_ANALYSIS_TEMPORARY=""
        if [[ "${cfk_bundles[$i]}" == "$tmp_dir/"* ]]
        then
            CFK_ANALYSIS_TEMPORARY=1
        fi
        CFK_ANALYSIS_REPORT_SUFFIX=""
        if [ "${cfk_name_count[$(basename "${cfk_bundles[$i]}")]}" -gt 1 ]
        then
            CFK_ANALYSIS_REPORT_SUFFIX="-$((i+1))"
        fi
        CFK_ANALYSIS_JSON=""
        CFK_ANALYSIS_HTML=""
        CFK_ANALYSIS_LOG_RECORDS=""
        if [ -s "$tmp_dir/cfk-records-$i.json" ]
        then
            CFK_ANALYSIS_LOG_RECORDS="$tmp_dir/cfk-records-$i.json"
        fi
        if [[ -n "$json_out" ]]
        then
            analyze_cfk_bundle "${cfk_bundles[$i]}" "1" "$no_sanitize" "$severity" "" "$output_dir" "$cfk_include_warnings" "${component_array[@]}" > "$tmp_dir/cfk-$i.json" 2> "$tmp_dir/cfk-$i.out"
        else
            analyze_cfk_bundle "${cfk_bundles[$i]}" "" "$no_sanitize" "$severity" "" "$output_dir" "$cfk_include_warnings" "${component_array[@]}" > "$tmp_dir/cfk-$i.out" 2>&1
        fi
        rc=$?
        printf '%s\t%s\t%s\n' "$rc" "$CFK_ANALYSIS_JSON" "$CFK_ANALYSIS_HTML" > "$tmp_dir/cfk-$i.result.tmp"
        mv "$tmp_dir/cfk-$i.result.tmp" "$tmp_dir/cfk-$i.result"
        exit 0
    ) &
done
while [ $cfk_next -lt ${#cfk_bundles[@]} ]
do
    wait -n 2> /dev/null || sleep 0.2
    # a job gone without its result (killed): the bundle counts as failed, instead of waiting for it forever
    if [ -z "$(jobs -rp)" ] && [ ! -f "$tmp_dir/cfk-$cfk_next.result" ]
    then
        echo "❌ the analysis of this bundle ended without a result" >> "$tmp_dir/cfk-$cfk_next.out"
        printf '1\t\t\n' > "$tmp_dir/cfk-$cfk_next.result"
    fi
    flush_cfk_bundles
    progress_step "☸️ CFK support bundles: $cfk_next of ${#cfk_bundles[@]} analyzed"
done

# several CFK bundles: compared, each one with the previous one (by collection time)
cfk_comparison="$tmp_dir/cfk-comparison.json"
echo "[]" > "$cfk_comparison"
if [ ${#cfk_compare_files[@]} -ge 2 ]
then
    log "🔁 Comparing the ${#cfk_compare_files[@]} CFK support bundles (sorted by collection time)"
    progress_step "🔁 comparing the ${#cfk_compare_files[@]} CFK support bundles"
    CFK_COMPARISON_HTML=""
    compare_cfk_bundles "" "$output_dir" "${cfk_compare_files[@]}"
elif [ ${#cfk_json_files[@]} -ge 2 ]
then
    compare_cfk_bundles "1" "" "${cfk_json_files[@]}" > "$cfk_comparison" || echo "[]" > "$cfk_comparison"
fi
# only CFK bundles: the report of the bundle (or the comparison of several) stays the entry point, and the JSON keeps the
# shape of cfk-analysis ("type": "cfk-bundle"), with the log analysis of their pod logs in .log_analysis. Their logs went
# through the log digest too (walk_cfk_bundle_logs): the log report is written below, without opening it
cfk_only=""
if [ ${#cfk_bundles[@]} -gt 0 ] && [ -z "$other_inputs" ]
then
    cfk_only=1
fi
if [ -n "$cfk_only" ] && [ $nb_files -eq 0 ] && [[ -n "$json_out" ]]
then
    if [[ -n "$json_out" ]]
    then
        if [ ${#cfk_json_files[@]} -eq 1 ] && [ ${#cfk_bundles[@]} -eq 1 ]
        then
            jq 'del(.label)' "${cfk_json_files[0]}" >&3
        else
            jq -s --slurpfile comparison "$cfk_comparison" '{type: "cfk-bundles", cfk_bundles: ., comparison: $comparison[0]}' \
                "${cfk_json_files[@]}" >&3
        fi
    fi
    exit $cfk_exit
fi

duplicates_msg=""
if [ $nb_duplicates -gt 0 ]
then
    duplicates_msg=", copies skipped: $nb_duplicates"
fi
levels="ERROR/FATAL"
if [[ -n "$include_warnings" ]]
then
    levels="ERROR/FATAL/WARN"
fi
read_msg="$(python3 -I "$root_folder/tools/log-analyzer/progress.py" human "$nb_bytes" 2>/dev/null || echo "$nb_bytes bytes") read in $(( (SECONDS-analyze_started) / 60 )) min $(( (SECONDS-analyze_started) % 60 )) s"
nb_incomplete=$(grep -c . "$incomplete_file" || true)
if [ $nb_files_with_findings -eq 0 ] && [ "$nb_incomplete" -gt 0 ]
then
    logwarn "⚠️ no $levels record found in $nb_files file(s), but $nb_incomplete input(s) were not fully read: the missing part may hold errors, $read_msg (binary files skipped: $nb_skipped${duplicates_msg})"
elif [ $nb_files_with_findings -eq 0 ]
then
    log "✅ no $levels record found in $nb_files file(s), $read_msg (binary files skipped: $nb_skipped${duplicates_msg})"
else
    log "📊 $nb_files_with_findings file(s) with findings out of $nb_files scanned, $read_msg (binary files skipped: $nb_skipped${duplicates_msg})"
fi
if [ "$nb_incomplete" -gt 0 ]
then
    logwarn "⚠️ Not fully read (ask for a complete copy):"
    while IFS=$'\t' read -r incomplete_label incomplete_reason
    do
        logwarn "   • $incomplete_label: $incomplete_reason"
    done < "$incomplete_file"
fi
# nothing could be read at all (an archive that does not extract, a gzip that does not decompress): a failure, not a ✅
incomplete_exit=0
if [ $nb_files -eq 0 ] && [ "$nb_incomplete" -gt 0 ]
then
    incomplete_exit=1
fi

if ! command -v python3 &>/dev/null
then
    logwarn "⚠️ python3 is not on PATH: no HTML report"
    exit 0
fi
sanitize_file "$records_file"
sanitize_file "$incomplete_file"

# 🔭 no finding: what the logs contain (period covered, levels, top messages and loggers) and what to ask for next,
# instead of a bare "no record found" (tools/log-analyzer/log_overview.py)
overview_json="null"
overview_text_file="$tmp_dir/overview.txt"
if [ $nb_files_with_findings -eq 0 ] && [ $nb_files -gt 0 ]
then
    overview_args=(--records "$records_file" --sources "$sources_file" --exports "$exports_file" --levels "$levels")
    progress_step "🔭 overview of the logs (no $levels record)"
    if python3 -I "$root_folder/tools/log-analyzer/log_overview.py" "${overview_args[@]}" --json-out "$tmp_dir/overview.json" > "$overview_text_file" 2>/dev/null
    then
        overview_json=$(cat "$tmp_dir/overview.json" 2>/dev/null || echo null)
        if [[ -n "$sanitize" ]]
        then
            python3 -I "$sanitizer" --state "$sanitize_state" --no-count < "$overview_text_file" > "$overview_text_file.sanitized" && mv "$overview_text_file.sanitized" "$overview_text_file"
            overview_json=$(printf '%s\n' "$overview_json" | python3 -I "$sanitizer" --state "$sanitize_state" --no-count)
        fi
        echo ""
        cat "$overview_text_file"
    else
        overview_json="null"
        rm -f "$overview_text_file"
    fi
fi

# 🌊 Kafka Streams: state transitions, rebalances, task assignment, restoration and known errors of the Kafka Streams
# applications of the logs (tools/streams-analyzer/streams_report.py, also used by playground streams status). Only the
# files with Kafka Streams lines are read again
streams_json="null"
streams_text_file="$tmp_dir/kafka-streams.txt"
streams_sources_file="$tmp_dir/streams-sources"
: > "$streams_sources_file"
while IFS=$'\t' read -r streams_label streams_path streams_rest
do
    if [ -f "$streams_path" ] && grep -q -m1 -F -e 'stream-client [' -e 'stream-thread [' "$streams_path" 2>/dev/null
    then
        printf '%s\t%s\n' "$streams_label" "$streams_path" >> "$streams_sources_file"
    fi
done < "$sources_file"
if [ -s "$streams_sources_file" ]
then
    progress_step "🌊 Kafka Streams applications of the logs"
    # one pass for the text and the JSON (a large log is read once)
    if python3 -I "$root_folder/tools/streams-analyzer/streams_report.py" --sources "$streams_sources_file" --json-out "$tmp_dir/kafka-streams-raw.json" > "$streams_text_file" 2>/dev/null
    then
        streams_json=$(cat "$tmp_dir/kafka-streams-raw.json" 2>/dev/null || echo null)
        if [[ -n "$sanitize" ]]
        then
            python3 -I "$sanitizer" --state "$sanitize_state" --no-count < "$streams_text_file" > "$streams_text_file.sanitized" && mv "$streams_text_file.sanitized" "$streams_text_file"
            streams_json=$(printf '%s\n' "$streams_json" | python3 -I "$sanitizer" --state "$sanitize_state" --no-count)
        fi
        # the HTML section, from the JSON (sanitized with --sanitize, never the raw files)
        printf '%s\n' "$streams_json" > "$tmp_dir/kafka-streams.json"
        python3 -I "$root_folder/tools/streams-analyzer/streams_report.py" --from-json "$tmp_dir/kafka-streams.json" --html-fragment "$tmp_dir/kafka-streams.html" 2>/dev/null || rm -f "$tmp_dir/kafka-streams.html"
        if [[ -z "$json_out" ]]
        then
            echo ""
            log "🌊 Kafka Streams applications of the logs (playground streams status for a running example)"
            cat "$streams_text_file"
        fi
    else
        streams_json="null"
        rm -f "$streams_text_file"
    fi
fi

redaction='{}'
if [[ -n "$sanitize" ]]
then
    redaction=$(python3 -I "$sanitizer" --state "$sanitize_state" --summary)
    log "🔒 Sanitized (best effort, review before sharing): $(jq -r '"\(.secrets) secret(s), \(.ip_addresses) IP(s), \(.hostnames) hostname(s), \(.emails) email(s), \(.ldap_dns) LDAP DN(s)"' <<< "$redaction") (--sanitize)"
fi
title="${file_array[*]}${since:+ · since ${since/T/ }}${until_ts:+ · until ${until_ts/T/ }}"
if [[ ${#sample_array[@]} -gt 0 ]]
then
    title="sample ${sample_array[*]}"
fi
report_args=(--records "$records_file" --title "$title" --levels "$levels" --skipped "$nb_skipped" --incomplete "$incomplete_file" --bytes-read "$nb_bytes")
# the files of the input, read again by the report: the file pages and 🔎 Search every log line of the HTML report, and
# the check of the connector context (MDC) of the Connect logs, also in the summary and --json
report_args+=(--sources "$sources_file")
# the changes of the cluster of each CFK bundle (pods terminated or restarted, custom resources edited, rollouts) join the
# incident timeline of the log report: 🔗 and 💥 link the errors of the pod logs to them
for cfk_events_json in "${cfk_json_files[@]}" "${cfk_compare_files[@]}"
do
    if [ -s "$cfk_events_json" ]
    then
        report_args+=(--cluster-events "$cfk_events_json")
    fi
done
# --compare (repeatable, oldest first): each other input as the JSON of analyze logs (given, or written by this command run
# again on it, with the same filters and the same sanitizer state), compared by log_report.py --compare (the last one) and
# drawn as a trend (all of them)
compare_json=""
compare_index=0
# the CFK support bundles of the inputs of --compare: compared with the bundles of this run (cfk-analysis/compare.py)
compare_cfk_files=()
# the JSON of analyze logs of an input of --compare as a log analysis: a CFK bundle gives "type": "cfk-bundle" (or
# cfk-bundles) with the log analysis of its pod logs in .log_analysis, its analysis is kept for the bundle comparison.
# $1: JSON, $2: label, $3: where to write the log analysis
function compare_input_logs () {
    local type n k
    type=$(jq -r '.type // ""' "$1" 2> /dev/null)
    case "$type" in
        logs)
            cp "$1" "$3"
            n=$(jq '.cfk_bundles // [] | length' "$1")
            ;;
        cfk-bundle)
            jq '.log_analysis // empty' "$1" > "$3" || return 1
            jq --arg label "$2" 'del(.log_analysis) + {label: ("before: " + $label)}' "$1" > "$3.cfk-0.json" && compare_cfk_files+=("$3.cfk-0.json")
            n=0
            ;;
        cfk-bundles)
            jq '.log_analysis // empty' "$1" > "$3" || return 1
            n=$(jq '.cfk_bundles | length' "$1")
            ;;
        *) return 1 ;;
    esac
    for (( k=0; k<${n:-0}; k++ ))
    do
        jq --argjson k "$k" --arg label "$2" '.cfk_bundles[$k] | . + {label: ("before: " + (.label // $label))}' "$1" > "$3.cfk-$k.json" \
            && compare_cfk_files+=("$3.cfk-$k.json")
    done
    jq -e '.type == "logs"' "$3" > /dev/null 2>&1
}
for compare in "${compare_array[@]}"
do
    compare_index=$((compare_index+1))
    one_json="$tmp_dir/compare-$compare_index.json"
    if [[ "$compare" == *.json ]] && compare_input_logs "$compare" "${compare#"$root_folder"/}" "$one_json"
    then
        :
    elif [ -e "$compare" ]
    then
        progress_step "🔁 analyzing $compare for the comparison"
        log "🔁 Analyzing $compare for the comparison (same filters)"
        # the same mode as this run: a CFK bundle is analyzed as a bundle (its pod logs only in the log analysis, like
        # here), with --logs-only every file of it
        compare_cmd=("$root_folder/scripts/cli/playground" analyze logs -f "$compare" --json --max-findings "$max_findings")
        [[ -n "$logs_only" ]] && compare_cmd+=(--logs-only)
        [[ -n "$errors_only" ]] && compare_cmd+=(--errors-only)
        [[ -n "$with_worker" ]] && compare_cmd+=(--with-worker)
        [[ -n "$sanitize" ]] && compare_cmd+=(--sanitize)
        for connector in "${connector_array[@]}"
        do
            compare_cmd+=(--connector "$connector")
        done
        # no progress page of its own, the sanitizer state of this run
        if ! PG_PROGRESS_HTML="" PG_SANITIZE_STATE="$sanitize_state" "${compare_cmd[@]}" > "$one_json.raw" 2> "$tmp_dir/compare.log" \
            || ! compare_input_logs "$one_json.raw" "${compare#"$root_folder"/}" "$one_json"
        then
            logwarn "⚠️ --compare: no log analysis of $compare (the last lines of its run below), left out of the comparison"
            tail -n 5 "$tmp_dir/compare.log" | sed 's/^/   /' >&2
            continue
        fi
    else
        logwarn "⚠️ --compare: $compare does not exist, left out of the comparison"
        continue
    fi
    compare_json="$one_json"
    # a sample of the repository by its path in it (the same on every machine, no user folder in the report)
    report_args+=(--compare "$one_json" --compare-label "${compare#"$root_folder"/}")
done
# the CFK bundles of --compare and of this run: one bundle comparison (versions, changes of the CRs, issues fixed / new /
# still there), sorted by collection time, next to the log comparison
current_cfk_files=("${cfk_compare_files[@]}" "${cfk_json_files[@]}")
if [ ${#compare_cfk_files[@]} -gt 0 ] && [ ${#current_cfk_files[@]} -gt 0 ]
then
    log "🔁 Comparing the CFK support bundles of --compare with the ones of this run (sorted by collection time)"
    if [[ -n "$json_out" ]]
    then
        compare_cfk_bundles "1" "" "${compare_cfk_files[@]}" "${current_cfk_files[@]}" > "$cfk_comparison" 2> /dev/null || echo "[]" > "$cfk_comparison"
    else
        CFK_COMPARISON_HTML=""
        compare_cfk_bundles "" "$output_dir" "${compare_cfk_files[@]}" "${current_cfk_files[@]}"
    fi
fi
for connector in "${connector_array[@]}"
do
    report_args+=(--connector "$connector")
done
if [[ -n "$with_worker" ]]
then
    report_args+=(--with-worker)
fi
# 🧰 the files of the input for another analyzer (GC logs, thread dumps, heap dumps, flight recordings, network captures,
# XStream reports), with the command to run on each. The ones extracted from an archive are kept next to the report
# (<stem>-other-files/): the tmp dir is deleted at the end. Not with --json, which writes nothing in --output-dir
other_files_json="$tmp_dir/other-files.json"
triage_args=(--walked "$walked_file" --tmp-dir "$tmp_dir" --sources "$sources_file")
if [[ -z "$json_out" ]]
then
    triage_stem=$(basename "${file_array[0]%/}")
    triage_stem="${triage_stem%%.*}"
    if [[ ${#sample_array[@]} -gt 0 ]]
    then
        triage_stem="${sample_array[0]}"
    fi
    triage_args+=(--keep-dir "$(mkdir -p "$output_dir" && cd "$output_dir" && pwd)/${triage_stem}-other-files")
fi
if python3 -I "$root_folder/tools/log-analyzer/bundle_triage.py" "${triage_args[@]}" > "$other_files_json" 2>/dev/null \
    && [ "$(jq '.files | length' "$other_files_json" 2>/dev/null)" -gt 0 ] 2>/dev/null
then
    report_args+=(--other-files "$other_files_json")
else
    rm -f "$other_files_json"
fi
# bounded summary of what the HTML report says first (known causes, root causes, connectors, configuration and its
# changes), on stderr with --json; then the configs asked with --show-config
if [ $nb_files_with_findings -gt 0 ] || [ -n "$show_config" ] || [ -n "${compare_json:-}" ] || [ -f "$other_files_json" ] || grep -q '^@@PGCFG@@' "$records_file"
then
    progress_step "🧭 summary: known causes, root causes, configuration"
    echo ""
    python3 -I "$root_folder/tools/log-analyzer/log_report.py" "${report_args[@]}" --text-summary
    echo ""
fi
if [[ -n "$show_config" ]]
then
    python3 -I "$root_folder/tools/log-analyzer/log_report.py" "${report_args[@]}" --show-config "$show_config"
    echo ""
fi
if [[ -n "$json_out" ]]
then
    json_args=(--json)
    if [[ -n "$json_sections" ]]
    then
        json_args+=(--json-sections "$json_sections")
    fi
    python3 -I "$root_folder/tools/log-analyzer/log_report.py" "${report_args[@]}" "${json_args[@]}" > "$tmp_dir/logs.json" || exit $?
    # what was redacted (same key as the JSON of cfk-analysis), and the analysis of each CFK bundle
    jq --argjson redaction "$redaction" --argjson streams "$streams_json" --argjson overview "$overview_json" '. + {redaction_summary: $redaction} + (if $streams != null then {kafka_streams: $streams} else {} end) + (if $overview != null then {overview: $overview} else {} end)' "$tmp_dir/logs.json" > "$tmp_dir/logs-redacted.json"
    if [ -n "$cfk_only" ] && [ ${#cfk_json_files[@]} -eq 1 ] && [ ${#cfk_bundles[@]} -eq 1 ]
    then
        # one CFK bundle: its JSON as before, the log analysis of its pod logs in .log_analysis
        jq --slurpfile logs "$tmp_dir/logs-redacted.json" --slurpfile comparison "$cfk_comparison" \
            'del(.label) + {log_analysis: ($logs[0] | del(.redaction_summary))} + (if ($comparison[0] | length) > 0 then {cfk_comparison: $comparison[0]} else {} end)' \
            "${cfk_json_files[0]}" >&3
    elif [ -n "$cfk_only" ] && [ ${#cfk_json_files[@]} -gt 0 ]
    then
        jq -s --slurpfile comparison "$cfk_comparison" --slurpfile logs "$tmp_dir/logs-redacted.json" \
            '{type: "cfk-bundles", cfk_bundles: ., comparison: $comparison[0], log_analysis: ($logs[0] | del(.redaction_summary))}' \
            "${cfk_json_files[@]}" >&3
    elif [ ${#cfk_json_files[@]} -eq 0 ]
    then
        cat "$tmp_dir/logs-redacted.json" >&3
    else
        jq --slurpfile cfk <(jq -s . "${cfk_json_files[@]}") --slurpfile comparison "$cfk_comparison" \
            '. + {cfk_bundles: $cfk[0]} + (if ($comparison[0] | length) > 0 then {cfk_comparison: $comparison[0]} else {} end)' \
            "$tmp_dir/logs-redacted.json" >&3
    fi
    exit $(( cfk_exit != 0 ? cfk_exit : incomplete_exit ))
fi

mkdir -p "$output_dir"
output_dir=$(cd "$output_dir" && pwd)
stem=$(basename "${file_array[0]%/}")
stem="${stem%%.*}"
if [[ ${#sample_array[@]} -gt 0 ]]
then
    stem="${sample_array[0]}"
fi
if [[ -n "$sanitize" ]]
then
    jq -r '"Secrets, IPs, hostnames, emails and LDAP DNs of the logs are replaced by placeholders (<REDACTED>, <IP-1>, <HOST-1>…), best effort: review the report before sharing it. Redacted: \(.secrets) secret(s), \(.ip_addresses) IP(s), \(.hostnames) hostname(s), \(.emails) email(s), \(.ldap_dns) LDAP DN(s)."' <<< "$redaction" > "$tmp_dir/sanitization.txt"
    report_args+=(--section "🔒 Sanitization" "$tmp_dir/sanitization.txt")
else
    echo "Not sanitized (--sanitize to redact them): this report may contain passwords, IPs and hostnames of the logs." > "$tmp_dir/sanitization.txt"
    report_args+=(--section "⚠️ Not sanitized" "$tmp_dir/sanitization.txt")
fi
if [ -f "$overview_text_file" ]
then
    report_args+=(--section "🔭 Overview" "$overview_text_file")
fi
# the comparison of several bundles: its own page, linked
if [ -n "${CFK_COMPARISON_HTML:-}" ]
then
    {
        printf '%s\t%s\n' "🔁 comparison of the ${#cfk_compare_files[@]} bundles" "$CFK_COMPARISON_HTML"
    } | python3 -I -c '
import html, os, sys, urllib.parse
rows = [l.rstrip("\n").split("\t", 1) for l in sys.stdin if l.strip()]
print("<p>The comparison of the CFK support bundles of the input (same cluster?, versions, changes of the CRs, issues fixed / new / still there):</p><ul>")
for label, path in rows:
    if path:
        # next to the report (the output dir): a relative link, which keeps working in the .zip of the report, on a
        # website, and holds no local path
        same = os.path.dirname(os.path.realpath(path)) == os.path.realpath(sys.argv[1])
        href = html.escape(urllib.parse.quote(os.path.basename(path)) if same else "file://" + urllib.parse.quote(path))
        print(f"<li><a href=\"{href}\" target=\"_blank\" rel=\"noopener\">{html.escape(label)}</a></li>")
print("</ul>")' "$output_dir" > "$tmp_dir/cfk-reports.html" && report_args+=(--html-section "🔁 CFK support bundles compared" "$tmp_dir/cfk-reports.html")
fi
# a page per file with findings in <report>-files/, its ✏️ open the file in the editor of playground config editor
if [ -f "$tmp_dir/kafka-streams.html" ]
then
    report_args+=(--html-section "🌊 Kafka Streams" "$tmp_dir/kafka-streams.html")
elif [ -f "$streams_text_file" ]
then
    report_args+=(--section "🌊 Kafka Streams" "$streams_text_file")
fi
export PLAYGROUND_EDITOR="$(playground config get editor 2>/dev/null)"
progress_step "📝 writing the HTML report"
# 📤 Share in the report: the .zip of the report and its file pages, written next to it (when zip is there)
share_zip="${stem}-log-report.zip"
if command -v zip > /dev/null 2>&1
then
    report_args+=(--share-zip "$share_zip")
fi
# the progress page already open in the browser becomes the report (same path): not opened a second time
report_no_open=""
if [ -n "$progress_page" ] && [ "$progress_page" == "$output_dir/${stem}-log-report.html" ]
then
    report_no_open=1
fi
# 📋 the summary for a ticket (Markdown, always sanitized), next to the report (also 📤 Share > Copy for a ticket)
report_args+=(--ticket-out "$output_dir/${stem}-ticket.md")
write_log_records_report "$records_file" "$output_dir/${stem}-log-report.html" "$report_no_open" "${report_args[@]:2}"
if [ -s "$output_dir/${stem}-ticket.md" ]
then
    log "📋 For a ticket (Markdown, sanitized: review it): $output_dir/${stem}-ticket.md"
fi
# the .zip to send to a colleague (📤 Share of the report): only when the file pages are under 200 MB (a page holds a
# whole log file: 1 GB of logs makes 1 GB of pages), else the command to make it
if command -v zip > /dev/null 2>&1 && [ -f "$output_dir/${stem}-log-report.html" ]
then
    share_files="${stem}-log-report-files"
    share_kb=$(du -sk "$output_dir/$share_files" 2>/dev/null | cut -f1)
    rm -f "$output_dir/$share_zip"
    if [ "${share_kb:-0}" -lt $((200 * 1024)) ]
    then
        # one top folder in the zip (<name>-log-report/): unzipped by a colleague, the report and its pages stay together
        # instead of landing loose in the current folder. Staged with symlinks, zip stores the files they point to
        share_stage="$tmp_dir/share/${stem}-log-report"
        mkdir -p "$share_stage"
        ln -s "$output_dir/${stem}-log-report.html" "$share_stage/${stem}-log-report.html"
        if [ -d "$output_dir/$share_files" ]
        then
            ln -s "$output_dir/$share_files" "$share_stage/$share_files"
        fi
        # the file pages of the issues of the CFK bundles (their sections are in the report)
        for cfk_json in "${cfk_compare_files[@]}"
        do
            if [ -d "${cfk_json%.json}-files" ]
            then
                ln -s "${cfk_json%.json}-files" "$share_stage/$(basename "${cfk_json%.json}-files")"
            fi
        done
        # the comparison of the CFK bundles, linked from the report by its name
        if [ -n "${CFK_COMPARISON_HTML:-}" ] && [ -f "$CFK_COMPARISON_HTML" ]
        then
            ln -s "$CFK_COMPARISON_HTML" "$share_stage/$(basename "$CFK_COMPARISON_HTML")"
        fi
        if (cd "$tmp_dir/share" && zip -qr "$output_dir/$share_zip" "${stem}-log-report") 2>/dev/null
        then
            log "📤 To share it: $output_dir/$share_zip (the report and its file pages, 📤 Share in the report)"
        fi
    else
        log "📤 To share it with its file pages ($(( share_kb / 1024 )) MB, not zipped automatically): cd \"$output_dir\" && zip -qr \"$share_zip\" \"${stem}-log-report.html\" \"$share_files\""
    fi
fi
exit $(( cfk_exit != 0 ? cfk_exit : incomplete_exit ))
