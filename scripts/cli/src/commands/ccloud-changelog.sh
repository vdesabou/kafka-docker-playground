since="${args[--since]}"
until="${args[--until]}"
around="${args[--around]}"
days="${args[--days]}"
grep="${args[--grep]}"
json="${args[--json]}"
force_refresh="${args[--force-refresh]}"
eval "connectors=(${args[--connector]})"
eval "categories=(${args[--category]})"

if ! command -v python3 > /dev/null 2>&1
then
    logerror "❌ python3 is required"
    exit 1
fi

changelog_args=()
[[ -n "$since" ]] && changelog_args+=(--since "$since")
[[ -n "$until" ]] && changelog_args+=(--until "$until")
[[ -n "$around" ]] && changelog_args+=(--around "$around")
[[ -n "$days" ]] && changelog_args+=(--days "$days")
[[ -n "$grep" ]] && changelog_args+=(--grep "$grep")
[[ -n "$force_refresh" ]] && changelog_args+=(--force-refresh)
for connector in "${connectors[@]}"
do
    changelog_args+=(--connector "$connector")
done
for category in "${categories[@]}"
do
    changelog_args+=(--category "$category")
done

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
trap 'rm -rf $tmp_dir' EXIT

if ! python3 -I "$root_folder/tools/ccloud-changelog/ccloud_changelog.py" "${changelog_args[@]}" > $tmp_dir/changelog.json 2> $tmp_dir/stderr
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

nb_days=$(jq '.days | length' $tmp_dir/changelog.json)
nb_changes=$(jq '[.days[].changes | length] | add // 0' $tmp_dir/changelog.json)
range=$(jq -r '
  if .since and .until then "from \(.since) to \(.until)"
  elif .since then "since \(.since)"
  elif .until then "up to \(.until)"
  else "since \(.oldest)" end' $tmp_dir/changelog.json)
filters=$(jq -r '[
  (if .connectors then "connector \(.connectors | join(" or "))" else empty end),
  (if .categories then "category \(.categories | join(" or "))" else empty end),
  (if .grep then "matching \"\(.grep)\"" else empty end)
  ] | if length > 0 then ", " + join(", ") else "" end' $tmp_dir/changelog.json)
log "📰 Confluent Cloud release notes $range$filters: $nb_changes change(s) in $nb_days day(s)"

if [ "$nb_days" == "0" ]
then
    log "🤷 no matching change (latest release notes: $(jq -r '.latest' $tmp_dir/changelog.json))"
else
    jq -r '.days[] |
      "📅 \(.date) - \(.changes | length) change(s) - 🌐 \(.link)",
      (.changes[] | "   • [\(.categories | join(", "))] \(if .section then "\(.section) → " else "" end)\(.text)")' $tmp_dir/changelog.json
fi
log "🌐 all release notes: $(jq -r '.page' $tmp_dir/changelog.json)"
