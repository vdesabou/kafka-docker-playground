connector_plugin="${args[--connector-plugin]}"
from="${args[--from]}"
to="${args[--to]}"
grep="${args[--grep]}"
json="${args[--json]}"
force_refresh="${args[--force-refresh]}"

if [[ $connector_plugin == *"@"* ]]
then
  connector_plugin=$(echo "$connector_plugin" | cut -d "@" -f 2)
fi

if [[ "$connector_plugin" == confluentinc/* ]] && [[ "${connector_plugin#*/}" != *"-"* ]]
then
    # fully managed: no release notes feed, but the versions shipped by each cc-connect image and their commits
    log "☁️ $connector_plugin is a fully managed connector: there is no release notes feed for it"
    log "💡 the connector versions of the last cc-connect images, and the commits between them: playground connector-plugin fm-versions --connector-plugin $connector_plugin --with-log"
    exit 0
fi

if ! command -v python3 > /dev/null 2>&1
then
    logerror "❌ python3 is required"
    exit 1
fi

changelog_args=(--connector-plugin "$connector_plugin")
[[ -n "$from" ]] && changelog_args+=(--from "$from")
[[ -n "$to" ]] && changelog_args+=(--to "$to")
[[ -n "$grep" ]] && changelog_args+=(--grep "$grep")
[[ -n "$force_refresh" ]] && changelog_args+=(--force-refresh)

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
trap 'rm -rf $tmp_dir' EXIT

if ! python3 -I "$root_folder/tools/connector-changelog/changelog.py" "${changelog_args[@]}" > $tmp_dir/changelog.json 2> $tmp_dir/stderr
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

to=$(jq -r '.to' $tmp_dir/changelog.json)
nb_feeds=$(jq '.feeds | length' $tmp_dir/changelog.json)
nb_versions=$(jq '.versions | length' $tmp_dir/changelog.json)

if [ "$(jq -r '.up_to_date' $tmp_dir/changelog.json)" == "true" ]
then
    log "✅ $from is the latest version of $connector_plugin on Confluent Hub ($to), nothing newer"
    exit 0
fi

if [ "$nb_feeds" == "0" ]
then
    log "📜 no release notes found for $connector_plugin, check the documentation: $(jq -r '.documentation_url' $tmp_dir/changelog.json)"
    exit 0
fi

if [[ -n "$from" ]]
then
    range="after $from up to $to"
else
    range="of the $(echo "$to" | cut -d "." -f 1-2) line up to $to"
fi
if [[ -n "$grep" ]]
then
    log "📜 Release notes of $connector_plugin $range matching \"$grep\": $nb_versions version(s)"
else
    log "📜 Release notes of $connector_plugin $range: $nb_versions version(s)"
fi

if [ "$nb_versions" == "0" ]
then
    log "🤷 no matching change"
else
    jq -r '.versions[] |
      "🔢 v\(.version) - 📅 release date: \(.release_date // "<unknown>")",
      (.changes[] | "   • \(.)")' $tmp_dir/changelog.json
fi
jq -r '.feeds[] | "🌐 changelog: \(sub("\\.xml$"; ".html"))"' $tmp_dir/changelog.json
