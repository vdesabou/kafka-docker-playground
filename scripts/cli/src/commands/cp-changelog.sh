from="${args[--from]}"
to="${args[--to]}"
grep="${args[--grep]}"
security="${args[--security]}"
json="${args[--json]}"
force_refresh="${args[--force-refresh]}"
eval "components=(${args[--component]})"

if ! command -v python3 > /dev/null 2>&1
then
    logerror "❌ python3 is required"
    exit 1
fi

# the fzf completion of --from/--to returns "<query>@8.3.0 - already installed 💻"
from=${from#*@}
from=${from%% *}
to=${to#*@}
to=${to%% *}

changelog_args=()
[[ -n "$from" ]] && changelog_args+=(--from "$from")
[[ -n "$to" ]] && changelog_args+=(--to "$to")
[[ -n "$grep" ]] && changelog_args+=(--grep "$grep")
[[ -n "$security" ]] && changelog_args+=(--security)
[[ -n "$force_refresh" ]] && changelog_args+=(--force-refresh)
for component in "${components[@]}"
do
    changelog_args+=(--component "$component")
done

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
trap 'rm -rf $tmp_dir' EXIT

if ! python3 -I "$root_folder/tools/cp-changelog/cp_changelog.py" "${changelog_args[@]}" > $tmp_dir/changelog.json 2> $tmp_dir/stderr
then
    logerror "$(cat $tmp_dir/stderr)"
    exit 1
fi
while IFS= read -r line
do
    [[ -n "$line" ]] && logwarn "$line"
done < $tmp_dir/stderr

if [[ -n "$json" ]]
then
    cat $tmp_dir/changelog.json
    exit 0
fi

to=$(jq -r '.to // empty' $tmp_dir/changelog.json)
nb_feeds=$(jq '.feeds | length' $tmp_dir/changelog.json)
nb_versions=$(jq '.versions | length' $tmp_dir/changelog.json)
nb_changes=$(jq '[.versions[].changes | length] | add // 0' $tmp_dir/changelog.json)

if [ "$(jq -r '.up_to_date' $tmp_dir/changelog.json)" == "true" ]
then
    log "✅ $from is the latest Confluent Platform version with a changelog ($(jq -r '.latest' $tmp_dir/changelog.json)), nothing newer"
    exit 0
fi

if [ "$nb_feeds" == "0" ]
then
    log "📜 no changelog feed found (they exist from Confluent Platform 7.4 onwards), check https://docs.confluent.io/platform/current/release-notes/changelog.html"
    exit 0
fi

if [[ -n "$from" ]]
then
    range="after $from up to $to"
else
    range="of the $(echo "$to" | cut -d "." -f 1-2) line up to $to"
fi
filters=""
if [ ${#components[@]} -gt 0 ]
then
    filters=" in ${components[*]}"
fi
if [[ -n "$security" ]]
then
    filters="$filters, security related"
elif [[ -n "$grep" ]]
then
    filters="$filters matching \"$grep\""
fi
log "📜 Changes of Confluent Platform $range$filters: $nb_changes change(s) in $nb_versions version(s)"

if [ "$nb_versions" == "0" ]
then
    log "🤷 no matching change"
else
    jq -r '.versions[] |
      "🔢 \(.version) - 📅 released: \(.released // "<unknown>") - \(.changes | length) change(s)",
      (.changes | group_by(.component) | .[] |
        "  🧩 \(.[0].component) (\(length))",
        (.[] | "     • \(if .security then "🔐 " else "" end)\(.title)\(if .commit != "" and .commit != null then " (\(.commit))" else "" end)"))' $tmp_dir/changelog.json
fi
jq -r '.feeds[] | "🌐 changelog: \(sub("\\.xml$"; ".html"))"' $tmp_dir/changelog.json
log "⚠️ only the community components are covered (Common, Kafka, ksqlDB, REST Proxy, Schema Registry), not Confluent Server or Control Center"
