eval "file_array=(${args[--file]})"
eval "sample_array=(${args[--sample]})"
include_warnings="${args[--include-warnings]}"
max_findings="${args[--max-findings]}"
output_dir="${args[--output-dir]}"
json_out="${args[--json]}"
logs_only="${args[--logs-only]}"
severity="${args[--severity]}"
no_sanitize="${args[--no-sanitize]}"
eval "component_array=(${args[--component]})"

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
        cfk_bundle) file_array+=("$root_folder/cfk-analysis/samples/cfk-support-bundle-synthetic.tar.gz") ;;
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
# secrets, IPs, hostnames, emails and LDAP DNs of the digests and of the records file are redacted (best effort), with
# the same placeholder for a value everywhere (state file of tools/report-common/sanitizer.py)
sanitizer="$root_folder/tools/report-common/sanitizer.py"
sanitize_state="$tmp_dir/sanitize-state.json"
sanitize=1
if [[ -n "$no_sanitize" ]]
then
    sanitize=""
    logwarn "⚠️  Sanitization DISABLED. Do not share this output for customer logs."
elif ! command -v python3 &>/dev/null
then
    sanitize=""
    logwarn "⚠️ python3 is not on PATH: the output is NOT sanitized (passwords, IPs, hostnames…), review it before sharing"
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

# a folder written by kubectl confluent support-bundle (or playground debug cfk generate-bundle): cluster-details.txt
# and cluster-resources/ at the top, or operator/ next to a <namespace>/ folder with them (older layout)
# $1: folder
function is_cfk_bundle () {
    local d
    [ -f "$1/cluster-details.txt" ] && return 0
    [ -d "$1/operator" ] || return 1
    [ -d "$1/cluster-resources" ] && return 0
    for d in "$1"/*/cluster-details.txt
    do
        [ -f "$d" ] && return 0
    done
    return 1
}

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

# analyzes a file, a folder or an archive, recursively
# $1: path, $2: label to display
function analyze_logs_path () {
    local path="$1"
    local label="$2"
    local extract_dir
    local f

    if [ -d "$path" ]
    then
        if [[ -z "$logs_only" ]] && is_cfk_bundle "$path"
        then
            cfk_bundles+=("$path")
            cfk_labels+=("${label%:}")
            return
        fi
        # CFK bundles in sub folders: analyzed on their own, their files are left out of the log digest
        local prune=()
        local bundle_dir
        if [[ -z "$logs_only" ]]
        then
            while IFS= read -r -d '' f
            do
                bundle_dir=$(dirname "$f")
                # <bundle>/<namespace>/cluster-details.txt (older layout): the bundle is the folder above
                if [ "$(dirname "$bundle_dir")" != "$path" ] && is_cfk_bundle "$(dirname "$bundle_dir")"
                then
                    bundle_dir=$(dirname "$bundle_dir")
                fi
                if is_cfk_bundle "$bundle_dir"
                then
                    case " ${prune[*]} " in *" -path $bundle_dir "*) continue ;; esac
                    [ ${#prune[@]} -gt 0 ] && prune+=(-o)
                    prune+=(-path "$bundle_dir")
                    if [[ "$label" == *":" ]]
                    then
                        analyze_logs_path "$bundle_dir" "${label}${bundle_dir#$path/}"
                    else
                        analyze_logs_path "$bundle_dir" "${label%/}/${bundle_dir#$path/}"
                    fi
                fi
            done < <(find "$path" -mindepth 2 \( -name cluster-details.txt -o -name cluster-resources \) ! -path "*/__MACOSX/*" -print0 | sort -z)
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

    case "$path" in
        *.zip|*.tar|*.tar.gz|*.tgz)
            nb_extracted=$((nb_extracted+1))
            # named after the archive: it names the report of a CFK bundle archived without a top folder
            extract_dir=$(basename "$path")
            extract_dir="$tmp_dir/$nb_extracted/${extract_dir%%.*}"
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

if [ ${#cfk_bundles[@]} -eq 0 ] && [[ -n "$severity" || ${#component_array[@]} -gt 0 ]]
then
    logwarn "⚠️ --component and --severity only apply to a CFK support bundle, and none was found"
fi

# ── CFK support bundles: cfk-analysis (pods, custom resources, events, versions, recent changes, logs) ──
cfk_exit=0
cfk_json_files=()
for i in "${!cfk_bundles[@]}"
do
    if [[ -n "$json_out" ]]
    then
        log "📦 CFK support bundle detected: ${cfk_labels[$i]} (--logs-only for the plain log digest)"
        cfk_json="$tmp_dir/cfk-$i.json"
        analyze_cfk_bundle "${cfk_bundles[$i]}" "1" "$no_sanitize" "$severity" "" "$output_dir" "$include_warnings" "${component_array[@]}" > "$cfk_json"
        rc=$?
        if [ $rc -eq 0 ]
        then
            jq --arg label "${cfk_labels[$i]}" '. + {label: $label}' "$cfk_json" > "$cfk_json.labelled" && cfk_json_files+=("$cfk_json.labelled")
        fi
    else
        log "📦 CFK support bundle detected: ${cfk_labels[$i]}: pods, custom resources, events, versions, recent changes and logs (--logs-only for the plain log digest)"
        analyze_cfk_bundle "${cfk_bundles[$i]}" "" "$no_sanitize" "$severity" "" "$output_dir" "$include_warnings" "${component_array[@]}"
        rc=$?
    fi
    if [ $rc -ne 0 ]
    then
        cfk_exit=$rc
    fi
done
# only CFK bundles: their JSON (one bundle) and no log digest
if [ ${#cfk_bundles[@]} -gt 0 ] && [ $nb_files -eq 0 ]
then
    if [[ -n "$json_out" ]]
    then
        if [ ${#cfk_json_files[@]} -eq 1 ] && [ ${#cfk_bundles[@]} -eq 1 ]
        then
            jq 'del(.label)' "${cfk_json_files[0]}" >&3
        else
            jq -s '{type: "cfk-bundles", cfk_bundles: .}' "${cfk_json_files[@]}" >&3
        fi
    fi
    exit $cfk_exit
fi

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
sanitize_file "$records_file"
redaction='{}'
if [[ -n "$sanitize" ]]
then
    redaction=$(python3 -I "$sanitizer" --state "$sanitize_state" --summary)
    log "🔒 Sanitized (best effort, review before sharing): $(jq -r '"\(.secrets) secret(s), \(.ip_addresses) IP(s), \(.hostnames) hostname(s), \(.emails) email(s), \(.ldap_dns) LDAP DN(s)"' <<< "$redaction"), --no-sanitize to keep them"
fi
title="${file_array[*]}"
if [[ ${#sample_array[@]} -gt 0 ]]
then
    title="sample ${sample_array[*]}"
fi
report_args=(--records "$records_file" --title "$title" --levels "$levels" --skipped "$nb_skipped")
if [[ -n "$json_out" ]]
then
    python3 -I "$root_folder/tools/log-analyzer/log_report.py" "${report_args[@]}" --json > "$tmp_dir/logs.json" || exit $?
    # what was redacted (same key as the JSON of cfk-analysis), and the analysis of each CFK bundle
    jq --argjson redaction "$redaction" '. + {redaction_summary: $redaction}' "$tmp_dir/logs.json" > "$tmp_dir/logs-redacted.json"
    if [ ${#cfk_json_files[@]} -eq 0 ]
    then
        cat "$tmp_dir/logs-redacted.json" >&3
    else
        jq --slurpfile cfk <(jq -s . "${cfk_json_files[@]}") '. + {cfk_bundles: $cfk[0]}' "$tmp_dir/logs-redacted.json" >&3
    fi
    exit $cfk_exit
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
    echo "Not sanitized (--no-sanitize): this report may contain passwords, IPs and hostnames of the logs." > "$tmp_dir/sanitization.txt"
    report_args+=(--section "⚠️ Not sanitized" "$tmp_dir/sanitization.txt")
fi
write_log_records_report "$records_file" "$output_dir/${stem}-log-report.html" "" "${report_args[@]:2}"
exit $cfk_exit
