days="${args[--days]}"
vendor="${args[--vendor]}"
with_changelog="${args[--with-changelog]}"
json="${args[--json]}"

if [[ -z "$json" ]]
then
    if [[ -n "$vendor" ]]
    then
        log "🆕 Listing last updated connector plugins (within $days days) for $vendor vendor"
    else
        log "🆕 Listing last updated connector plugins (within $days days) for all vendors"
    fi
fi

# one request: the Hub lists every plugin with its latest version and release date
tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
trap 'rm -rf $tmp_dir' EXIT
set +e
curl -s --max-time 60 -D $tmp_dir/headers -o $tmp_dir/plugins.json "https://api.hub.confluent.io/api/plugins?per_page=1000"
ret=$?
set -e
if [ $ret -ne 0 ] || ! jq -e 'type == "array"' $tmp_dir/plugins.json > /dev/null 2>&1
then
    logerror "❌ could not list the connector plugins of Confluent Hub (curl exit code $ret)"
    exit 1
fi
total=$(grep -i "^x-pagination-count:" $tmp_dir/headers | tr -dc '0-9')
if [[ -n "$total" ]] && [ "$total" -gt "$(jq length $tmp_dir/plugins.json)" ]
then
    logwarn "⚠️ Confluent Hub returned $(jq length $tmp_dir/plugins.json) plugins out of $total"
fi

# released within --days, newest first (a release date in the future is a typo of the vendor: skipped)
jq --argjson days "$days" --arg vendor "$vendor" '
    [ .[]
      | select(.release_date != null)
      | {
          connector_plugin: "\(.owner.username)/\(.name)",
          version,
          release_date,
          days_ago: ((now - (.release_date | strptime("%Y-%m-%d") | mktime)) / 86400 | floor),
          documentation_url
        }
      | select(.days_ago >= 0 and .days_ago <= $days)
      | select($vendor == "" or (.connector_plugin | test($vendor)))
    ] | sort_by(.release_date) | reverse' $tmp_dir/plugins.json > $tmp_dir/recent.json

# release notes of the new version, from the docs.confluent.io changelog feeds (Confluent plugins only)
if [[ -n "$with_changelog" ]] && command -v python3 > /dev/null 2>&1
then
    echo "{}" > $tmp_dir/changes.json
    for row in $(jq -r '.[] | select(.connector_plugin | startswith("confluentinc/")) | "\(.connector_plugin)@\(.version)"' $tmp_dir/recent.json)
    do
        plugin="${row%@*}"
        version="${row#*@}"
        if python3 -I "$root_folder/tools/connector-changelog/changelog.py" --connector-plugin "$plugin" --version "$version" > $tmp_dir/one.json 2> /dev/null
        then
            jq --arg p "$plugin" --slurpfile one $tmp_dir/one.json '. + {($p): [$one[0].versions[].changes[]]}' $tmp_dir/changes.json > $tmp_dir/changes.tmp && mv $tmp_dir/changes.tmp $tmp_dir/changes.json
        fi
    done
    jq --slurpfile changes $tmp_dir/changes.json 'map(. + (if $changes[0][.connector_plugin] then {changes: $changes[0][.connector_plugin]} else {} end))' $tmp_dir/recent.json > $tmp_dir/recent.tmp && mv $tmp_dir/recent.tmp $tmp_dir/recent.json
fi

if [[ -n "$json" ]]
then
    cat $tmp_dir/recent.json
    exit 0
fi

if [ "$(jq length $tmp_dir/recent.json)" == "0" ]
then
    log "🤷 no connector plugin released in the last $days days"
    exit 0
fi

jq -r '.[] |
    "🔌 \(.connector_plugin) - 🔢 v\(.version) - 📅 release date: \(.release_date) (\(.days_ago) days ago) - 🌐 documentation: \(.documentation_url // "<not available>")",
    ((.changes // [])[] | "   • \(.)")' $tmp_dir/recent.json
