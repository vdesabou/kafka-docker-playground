file="${args[--file]}"
eval "connector_tags=(${args[--connector-tag]:-})"
eval "cp_tags=(${args[--tag]:-})"
from="${args[--from]}"
to="${args[--to]}"
all="${args[--all]}"
run_flags="${args[--run-flags]}"
json="${args[--json]}"

# with --json, only the summary goes to stdout
if [[ -n "$json" ]]
then
    exec 3>&1 1>&2
fi

if [ -z "$file" ]
then
    file=$(playground state get run.test_file)
fi
if [[ $file == *"@"* ]]
then
    file=$(echo "$file" | cut -d "@" -f 2)
fi
if [ -z "$file" ] || [ ! -f "$file" ]
then
    logerror "❌ no reproduction model (run.test_file is <$file>), use --file"
    exit 1
fi
file=$(repro_model_path "$file")
if ! grep -q "playground repro assert" <(grep -v "^#" "$file")
then
    logerror "❌ $file does not call 'playground repro assert': bisect reads the verdict of each run, end the scenario with it (playground repro assert --help)"
    exit 1
fi

# the connector plugin of the model (the first one from Confluent Hub), for the versions and the changelog
test_file="$file"
connector_plugin=""
get_connector_paths
for connector_path in ${connector_paths//,/ }
do
    full_connector_name=$(basename "$connector_path")
    owner=$(echo "$full_connector_name" | cut -d'-' -f1)
    name=$(echo "$full_connector_name" | cut -d'-' -f2-)
    if [ "$owner" == "java" ] || [ "$name" == "hub-components" ] || [ "$owner" == "filestream" ]
    then
        continue
    fi
    connector_plugin="$owner/$name"
    break
done

# 1. what varies: the connector versions (listed, or a range of the Hub versions) or the CP versions
dimension="connector"
declare -a versions=()
if [ -n "$from" ] || [ -n "$to" ]
then
    if [ ${#connector_tags[@]} -gt 0 ] || [ ${#cp_tags[@]} -gt 1 ]
    then
        logerror "❌ --from / --to take the versions of Confluent Hub: don't combine them with --connector-tag, nor with several --tag"
        exit 1
    fi
    if [ -z "$connector_plugin" ]
    then
        logerror "❌ no connector plugin from Confluent Hub in $file: list the versions with --connector-tag"
        exit 1
    fi
    owner=${connector_plugin%%/*}
    name=${connector_plugin#*/}
    playground connector-plugin versions --connector-plugin "$connector_plugin" > /dev/null 2>&1 || true
    if [ ! -f "/tmp/version_${owner}_${name}" ]
    then
        logerror "❌ could not get the versions of $connector_plugin"
        exit 1
    fi
    while IFS= read -r version
    do
        if [ -n "$from" ] && version_gt "$from" "$version"
        then
            continue
        fi
        if [ -n "$to" ] && version_gt "$version" "$to"
        then
            continue
        fi
        versions+=("$version")
    done < <(grep -oE 'v[0-9][0-9A-Za-z.-]*' "/tmp/version_${owner}_${name}" | sed 's/^v//' | sort -V -u)
    if [ ${#versions[@]} -lt 2 ]
    then
        logerror "❌ less than 2 versions of $connector_plugin between ${from:-the first one} and ${to:-the last one}: $(echo ${versions[*]})"
        exit 1
    fi
elif [ ${#connector_tags[@]} -gt 0 ]
then
    if [ ${#cp_tags[@]} -gt 1 ]
    then
        logerror "❌ give several --connector-tag or several --tag, not both (one --tag with several --connector-tag is fine)"
        exit 1
    fi
    versions=("${connector_tags[@]}")
elif [ ${#cp_tags[@]} -gt 1 ]
then
    dimension="cp"
    versions=("${cp_tags[@]}")
else
    logerror "❌ give the versions to try: several --connector-tag, --from / --to (Confluent Hub versions of the connector), or several --tag (CP versions)"
    exit 1
fi
fixed_flags=""
if [ "$dimension" == "connector" ] && [ ${#cp_tags[@]} -eq 1 ]
then
    fixed_flags="--tag ${cp_tags[0]}"
fi

if [ -n "$from$to" ] && [ -z "$all" ]
then
    mode="bisect"
else
    mode="all"
fi

output_dir="/tmp/playground-repro-bisect"
mkdir -p "$output_dir"
model_name=$(basename "$file" .sh)
started_at=$(date +%Y-%m-%d-%H-%M-%S)
results_file="$output_dir/${model_name}-${started_at}.jsonl"
: > "$results_file"

if [ ${#versions[@]} -gt 8 ]
then
    version_list="${versions[0]} ${versions[1]} ${versions[2]} … ${versions[$((${#versions[@]} - 2))]} ${versions[$((${#versions[@]} - 1))]}"
else
    version_list="${versions[*]}"
fi
log "🔎 $mode over ${#versions[@]} $( [ "$dimension" == "cp" ] && echo "CP" || echo "${connector_plugin:-connector}") version(s) of $(basename "$file"): $version_list"
if [ "$mode" == "bisect" ]
then
    log "   binary search: the first and the last version, then the middle until the verdict changes (assumes it changes once)"
fi
log "   ⚠️ each run is a 'playground run' of the model: it stops the running environment"

# 2. one run: the verdict recorded by 'playground repro assert' during it
declare -A verdict_of=()
function run_version () {
    local version="$1"
    local log_file="$output_dir/${model_name}-${version}.log"
    local start_epoch nb_before rc verdict_json verdict reason duration
    local version_flag="--connector-tag"
    if [ "$dimension" == "cp" ]
    then
        version_flag="--tag"
    fi
    log "▶️  $version_flag $version: playground run -f $file $version_flag $version $fixed_flags $run_flags"
    log "   📜 tail -f $log_file"
    start_epoch=$(date +%s)
    # the verdicts recorded during this run are the lines added to the file
    nb_before=0
    if [ -f "$root_folder/playground-repro-verdicts" ]
    then
        nb_before=$(wc -l < "$root_folder/playground-repro-verdicts" | tr -d ' ')
    fi
    set +e
    # shellcheck disable=SC2086
    playground run -f "$file" $version_flag "$version" $fixed_flags $run_flags < /dev/null > "$log_file" 2>&1
    rc=$?
    set -e
    duration=$(( $(date +%s) - start_epoch ))
    verdict_json=""
    if [ -f "$root_folder/playground-repro-verdicts" ]
    then
        verdict_json=$(tail -n +$((nb_before + 1)) "$root_folder/playground-repro-verdicts" | jq -c --arg script "$file" 'select(.script == $script)' 2>/dev/null | tail -1)
    fi
    if [ -n "$verdict_json" ]
    then
        verdict=$(echo "$verdict_json" | jq -r '.verdict')
        reason=$(echo "$verdict_json" | jq -r '.reason')
    else
        verdict="no verdict"
        reason="the run ended with exit code $rc before 'playground repro assert' (see $log_file)"
    fi
    verdict_of[$version]="$verdict"
    jq -cn --arg version "$version" --arg verdict "$verdict" --arg reason "$reason" --argjson duration "$duration" --argjson exit_code "$rc" --arg log "$log_file" \
        '{version: $version, verdict: $verdict, reason: $reason, duration_seconds: $duration, exit_code: $exit_code, log: $log}' >> "$results_file"
    case "$verdict" in
        reproduced) log "   🐞 $version: reproduced ($((duration / 60))m$((duration % 60))s): $reason" ;;
        "not reproduced") log "   ✅ $version: not reproduced ($((duration / 60))m$((duration % 60))s): $reason" ;;
        *) logwarn "   ❓ $version: no verdict ($((duration / 60))m$((duration % 60))s): $reason" ;;
    esac
}

# 3. the runs
if [ "$mode" == "all" ]
then
    for version in "${versions[@]}"
    do
        run_version "$version"
    done
else
    lo=0
    hi=$((${#versions[@]} - 1))
    run_version "${versions[$lo]}"
    run_version "${versions[$hi]}"
    if [ "${verdict_of[${versions[$lo]}]}" == "no verdict" ] || [ "${verdict_of[${versions[$hi]}]}" == "no verdict" ]
    then
        logerror "❌ no verdict at one end of the range: fix the model (or the range) first"
    elif [ "${verdict_of[${versions[$lo]}]}" == "${verdict_of[${versions[$hi]}]}" ]
    then
        log "🟰 same verdict for ${versions[$lo]} and ${versions[$hi]} (${verdict_of[${versions[$lo]}]}): nothing to bisect in this range"
    else
        while [ $((hi - lo)) -gt 1 ]
        do
            mid=$(( (lo + hi) / 2 ))
            run_version "${versions[$mid]}"
            if [ "${verdict_of[${versions[$mid]}]}" == "no verdict" ]
            then
                logerror "❌ no verdict for ${versions[$mid]}: stopping, run it again or narrow the range with --from / --to"
                break
            fi
            if [ "${verdict_of[${versions[$mid]}]}" == "${verdict_of[${versions[$lo]}]}" ]
            then
                lo=$mid
            else
                hi=$mid
            fi
        done
    fi
fi

# 4. summary, in the order of the versions
summary=$(jq -s --arg model "$file" --arg plugin "$connector_plugin" --arg dimension "$dimension" --arg mode "$mode" '
    {model: $model, connector_plugin: $plugin, dimension: $dimension, mode: $mode,
     runs: sort_by(.version | split(".") | map(tonumber? // 0))}' "$results_file")
# the versions where the verdict changes, between two consecutive versions that were run
changes=$(echo "$summary" | jq -c '[.runs | map(select(.verdict != "no verdict")) | . as $r | range(1; length) | select($r[.].verdict != $r[. - 1].verdict) | {from: $r[. - 1].version, from_verdict: $r[. - 1].verdict, to: $r[.].version, to_verdict: $r[.].verdict}]')
summary=$(echo "$summary" | jq --argjson changes "$changes" '. + {changes: $changes}')
summary_file="$output_dir/${model_name}-${started_at}.json"
echo "$summary" > "$summary_file"

if [[ -n "$json" ]]
then
    echo "$summary" >&3
    exit 0
fi

log "📊 verdicts of $(basename "$file"):"
echo "$summary" | jq -r '.runs[] | [.version, (if .verdict == "reproduced" then "🐞 reproduced" elif .verdict == "not reproduced" then "✅ not reproduced" else "❓ no verdict" end), "\(.duration_seconds / 60 | floor)m\(.duration_seconds % 60)s", .reason] | @tsv' \
    | awk -F'\t' '{ printf "   %-14s %-20s %-8s %s\n", $1, $2, $3, $4 }'
if [ "$(echo "$changes" | jq 'length')" -eq 0 ]
then
    log "🟰 the verdict does not change between the versions that ran"
else
    echo "$changes" | jq -r '.[] | "\(.from) (\(.from_verdict)) → \(.to) (\(.to_verdict))"' | while IFS= read -r change
    do
        log "🔀 the verdict changes between $change"
    done
    if [ "$dimension" == "connector" ] && [[ "$connector_plugin" == confluentinc/* ]]
    then
        echo "$changes" | jq -r '.[] | "\(.from) \(.to)"' | while read -r change_from change_to
        do
            log "📰 what changed between $change_from and $change_to:"
            playground connector-plugin changelog --connector-plugin "$connector_plugin" --from "$change_from" --to "$change_to" 2>&1 | sed 's/^/   /' || true
        done
    fi
fi
log "💾 $summary_file"
