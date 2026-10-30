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
eval "connector_array=(${args[--connector]})"
with_worker="${args[--with-worker]}"
show_config="${args[--show-config]}"
json_sections="${args[--json-sections]}"
problem="${args[--problem]}"

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
        cfk_kraft_migration) file_array+=("$root_folder/cfk-analysis/samples/cfk-support-bundle-kraft-migration.tar.gz") ;;
        cfk_rollout) file_array+=("$root_folder/cfk-analysis/samples/cfk-support-bundle-rollout.tar.gz") ;;
        cfk_rollout_after) file_array+=("$root_folder/cfk-analysis/samples/cfk-support-bundle-rollout-after.tar.gz") ;;
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

if [[ -n "$with_worker" && ${#connector_array[@]} -eq 0 ]]
then
    logwarn "⚠️ --with-worker only applies with --connector"
    with_worker=""
fi
# --connector: the digest of each file (summarize_log_errors) prints only the records of these connectors
export PG_LOG_DIGEST_CONNECTORS="${connector_array[*]}"
export PG_LOG_DIGEST_WITH_WORKER="$with_worker"

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
# label<tab>path on disk<tab>1 when the file stays there after the command (not extracted to $tmp_dir) of each file
# analyzed: the HTML report writes a page per file with findings next to it, its locations (connect.log:33) link to
# them, and its ✏️ open the file in the editor (a copy for the extracted ones)
sources_file="$tmp_dir/sources"
: > "$sources_file"
nb_files=0
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
# $1: label to display, $2: path of the file
function analyze_logs_digest () {
    label="$1"
    printf '%s\t%s\t%s\n' "$label" "$2" "$([[ "$2" == "$tmp_dir/"* ]] || echo 1)" >> "$sources_file"
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

# config files of the input for the ⚙️ Configuration section of the report (see summarize_log_errors): a .properties
# file, or a JSON file with connector configs (a connector config, {name, config}, the output of /connectors?expand=info)
# $1: path, $2: label
function append_config_file () {
    local path="$1"
    local label="$2"
    case "$path" in
        *.properties)
            printf '@@PGCFG@@\t%s\tfile\t\t\t\n' "$(basename "$path")" >> "$records_file"
            grep -v '^[[:space:]]*[#!]' "$path" 2>/dev/null | grep '=' | sed 's/^[[:space:]]*//; s/[[:space:]]*=[[:space:]]*/=/; s/^/@@PGCFGL@@\t/' >> "$records_file"
            ;;
        *.json)
            # a big JSON is data, not a config
            [ "$(wc -c < "$path" | tr -d ' ')" -lt 5000000 ] || return 0
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
            ' "$path" >> "$records_file" 2>/dev/null
            ;;
    esac
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
            if ! is_duplicate_cfk_bundle "$path" "${label%:}"
            then
                cfk_bundles+=("$path")
                cfk_labels+=("${label%:}")
            fi
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
            if ! is_duplicate_file "$path" "$label"
            then
                analyze_logs_digest "$label" "$path" < <(gzip -dc "$path" 2>/dev/null)
            fi
            ;;
        *)
            if grep -Iq . "$path" 2>/dev/null
            then
                if ! is_duplicate_file "$path" "$label"
                then
                    analyze_logs_digest "$label" "$path" < "$path"
                    append_config_file "$path" "$label"
                fi
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
for i in "${!cfk_bundles[@]}"
do
    CFK_ANALYSIS_LABEL="${cfk_labels[$i]}"
    # extracted from an archive: deleted at the end, the report copies its files for the editor
    CFK_ANALYSIS_TEMPORARY=""
    if [[ "${cfk_bundles[$i]}" == "$tmp_dir/"* ]]
    then
        CFK_ANALYSIS_TEMPORARY=1
    fi
    CFK_ANALYSIS_JSON=""
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
        if [ $rc -eq 0 ] && [ -f "$CFK_ANALYSIS_JSON" ]
        then
            cfk_compare_files+=("$CFK_ANALYSIS_JSON")
        fi
    fi
    if [ $rc -ne 0 ]
    then
        cfk_exit=$rc
    fi
done
# several CFK bundles: compared, each one with the previous one (by collection time)
cfk_comparison="$tmp_dir/cfk-comparison.json"
echo "[]" > "$cfk_comparison"
if [ ${#cfk_compare_files[@]} -ge 2 ]
then
    log "🔁 Comparing the ${#cfk_compare_files[@]} CFK support bundles (sorted by collection time)"
    compare_cfk_bundles "" "$output_dir" "${cfk_compare_files[@]}"
elif [ ${#cfk_json_files[@]} -ge 2 ]
then
    compare_cfk_bundles "1" "" "${cfk_json_files[@]}" > "$cfk_comparison" || echo "[]" > "$cfk_comparison"
fi
# only CFK bundles: their JSON (one bundle) and no log digest
if [ ${#cfk_bundles[@]} -gt 0 ] && [ $nb_files -eq 0 ]
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
if [ $nb_files_with_findings -eq 0 ]
then
    log "✅ no $levels record found in $nb_files file(s) (binary files skipped: $nb_skipped${duplicates_msg})"
else
    log "📊 $nb_files_with_findings file(s) with findings out of $nb_files scanned (binary files skipped: $nb_skipped${duplicates_msg})"
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
for connector in "${connector_array[@]}"
do
    report_args+=(--connector "$connector")
done
if [[ -n "$with_worker" ]]
then
    report_args+=(--with-worker)
fi
# bounded summary of what the HTML report says first (known causes, root causes, connectors, configuration and its
# changes), on stderr with --json; then the configs asked with --show-config
if [ $nb_files_with_findings -gt 0 ] || [ -n "$show_config" ] || grep -q '^@@PGCFG@@' "$records_file"
then
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
    jq --argjson redaction "$redaction" '. + {redaction_summary: $redaction}' "$tmp_dir/logs.json" > "$tmp_dir/logs-redacted.json"
    if [ ${#cfk_json_files[@]} -eq 0 ]
    then
        cat "$tmp_dir/logs-redacted.json" >&3
    else
        jq --slurpfile cfk <(jq -s . "${cfk_json_files[@]}") --slurpfile comparison "$cfk_comparison" \
            '. + {cfk_bundles: $cfk[0]} + (if ($comparison[0] | length) > 0 then {cfk_comparison: $comparison[0]} else {} end)' \
            "$tmp_dir/logs-redacted.json" >&3
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
# a page per file with findings in <report>-files/, its ✏️ open the file in the editor of playground config editor
report_args+=(--sources "$sources_file")
export PLAYGROUND_EDITOR="$(playground config get editor 2>/dev/null)"
write_log_records_report "$records_file" "$output_dir/${stem}-log-report.html" "" "${report_args[@]:2}"
exit $cfk_exit
