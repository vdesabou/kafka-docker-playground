connector_plugin="${args[--connector-plugin]}"
last="${args[--last]}"
from="${args[--from]}"
latest="${args[--latest]}"
json="${args[--json]}"
force_refresh="${args[--force-refresh]}"
with_changelog="${args[--with-changelog]}"

if [[ $connector_plugin == *"@"* ]]
then
  connector_plugin=$(echo "$connector_plugin" | cut -d "@" -f 2)
fi

owner=$(echo "$connector_plugin" | cut -d "/" -f 1)
name=$(echo "$connector_plugin" | cut -d "/" -f 2)

# raw answer of the Hub API, kept one day: the text below is rendered from it on every call, so "days ago" is never stale
json_cache="/tmp/version_${owner}_${name}.json"
# text rendering, read by the --connector-tag picker and repro bisect
filename="/tmp/version_${owner}_${name}"

if [[ -n "$force_refresh" ]]
then
    rm -f "$json_cache"
fi

if [[ -z "$latest" ]] && [[ -z "$json" ]]
then
    if [[ -n "$from" ]]
    then
        log "💯 Listing versions after $from for connector plugin $connector_plugin"
    elif [[ -n "$last" ]]
    then
        if [ "$last" != "1" ]
        then
            log "💯 Listing last $last versions for connector plugin $connector_plugin"
        fi
    else
        log "💯 Listing all versions for connector plugin $connector_plugin"
    fi
fi

if [ ! -f "$json_cache" ] || [ -z "$(find "$json_cache" -mmin -1440 2>/dev/null)" ]
then
    set +e
    curl_output=$(curl -s --max-time 30 "https://api.hub.confluent.io/api/plugins/$owner/$name/versions")
    ret=$?
    set -e
    if [ $ret -ne 0 ] || ! echo "$curl_output" | jq -e 'type == "array"' > /dev/null 2>&1
    then
        if [ -f "$json_cache" ]
        then
            logwarn "⚠️ could not refresh the versions of $connector_plugin from Confluent Hub, using the cache of $(date -r "$json_cache" "+%Y-%m-%d")"
        elif [ $ret -ne 0 ]
        then
            logerror "❌ curl request to Confluent Hub failed with error code $ret!"
            exit 1
        else
            logerror "❌ invalid answer from Confluent Hub for $connector_plugin:"
            echo "$curl_output" | head -20
            exit 1
        fi
    else
        if [ "$curl_output" == "[]" ]
        then
            logwarn "❌ could not get versions for connector plugin $connector_plugin"
            exit 0
        fi
        # documentation_url is in the manifest of the latest version
        set +e
        manifest_url=$(echo "$curl_output" | jq -r '.[-1].manifest_url')
        documentation_url=$(curl -s --max-time 30 "$manifest_url" | jq -r '.documentation_url // empty' 2>/dev/null)
        set -e
        echo "$curl_output" | jq --arg doc "$documentation_url" '{versions: ., documentation_url: (if $doc == "" then null else $doc end)}' > "$json_cache"
    fi
fi

# versions with their age in days, oldest first (the order of the Hub)
all_json=$(jq '{
    documentation_url,
    versions: [.versions[] | {
        version,
        release_date,
        days_ago: (if .release_date then ((now - (.release_date | strptime("%Y-%m-%d") | mktime)) / 86400 | floor) else null end)
    }]
}' "$json_cache")

# text rendering of every version, for the readers of $filename
render_text='(.versions[] | if .release_date then "🔢 v\(.version) - 📅 release date: \(.release_date) (\(.days_ago) days ago)" else "🔢 v\(.version) - 📅 release date: <unknown>" end),
    "🌐 documentation: \(.documentation_url // "<not available>")"'
echo "$all_json" | jq -r "$render_text" > "$filename"

latest_version=$(echo "$all_json" | jq -r '.versions[-1].version')

if [[ -n "$latest" ]]
then
    echo "$latest_version"
    exit 0
fi

selected_json="$all_json"
if [[ -n "$from" ]]
then
    if ! echo "$all_json" | jq -e --arg v "$from" '.versions | any(.version == $v)' > /dev/null
    then
        logwarn "⚠️ $from is not a version of $connector_plugin on Confluent Hub"
    fi
    # the versions sorted after $from
    newer_json=$({ echo "$from"; echo "$all_json" | jq -r '.versions[].version'; } | sort -V -u | awk -v from="$from" 'found { print } $0 == from { found = 1 }' | jq -R . | jq -s .)
    selected_json=$(echo "$all_json" | jq --argjson newer "$newer_json" '.versions |= map(select(.version as $v | $newer | index($v)))')
    nb_behind=$(echo "$selected_json" | jq '.versions | length')
fi
if [[ -n "$last" ]]
then
    selected_json=$(echo "$selected_json" | jq --argjson n "$last" '.versions |= .[-$n:]')
fi

# release notes, from the docs.confluent.io changelog feeds (see connector-plugin changelog)
changelog_json=""
if [[ -n "$with_changelog" ]] && [ "$(echo "$selected_json" | jq '.versions | length')" != "0" ]
then
    first_version=$(echo "$selected_json" | jq -r '.versions[0].version')
    changelog_json=$(mktemp -t pg-XXXXXXXXXX)
    trap 'rm -f $changelog_json' EXIT
    changelog_args=(--connector-plugin "$owner/$name" --from "$first_version" --include-from)
    [[ -n "$force_refresh" ]] && changelog_args+=(--force-refresh)
    if ! command -v python3 > /dev/null 2>&1 || ! python3 -I "$root_folder/tools/connector-changelog/changelog.py" "${changelog_args[@]}" > $changelog_json 2> /dev/null || [ "$(jq '.feeds | length' $changelog_json)" == "0" ]
    then
        if [[ -z "$json" ]]
        then
            logwarn "📜 no changelog feed for connector plugin $owner/$name, release notes are not shown"
        fi
        changelog_json=""
    fi
fi

if [[ -n "$json" ]]
then
    if [[ -n "$changelog_json" ]]
    then
        selected_json=$(echo "$selected_json" | jq --slurpfile cl "$changelog_json" '
            .versions |= map(. as $v | . + {changes: [$cl[0].versions[] | select(.version == $v.version) | .changes[]]})
            | .changelog = [$cl[0].feeds[] | sub("\\.xml$"; ".html")]')
    fi
    echo "$selected_json" | jq --arg plugin "$owner/$name" --arg latest "$latest_version" --arg from "$from" --arg nb_behind "${nb_behind:-0}" \
        '{connector_plugin: $plugin, latest: $latest} + (if $from != "" then {from: $from, versions_behind: ($nb_behind | tonumber)} else {} end) + .'
    exit 0
fi

if [[ -n "$from" ]]
then
    if [ "$nb_behind" == "0" ] && [ "$from" != "$latest_version" ]
    then
        logwarn "⚠️ $from is newer than the latest version of $connector_plugin on Confluent Hub ($latest_version)"
    elif [ "$nb_behind" == "0" ]
    then
        log "✅ $from is the latest version of $connector_plugin on Confluent Hub ($latest_version)"
    else
        latest_line=$(echo "$all_json" | jq -r '.versions[-1] | if .release_date then "released \(.release_date), \(.days_ago) days ago" else "release date unknown" end')
        log "📌 $from is $nb_behind version(s) behind the latest $latest_version ($latest_line)"
    fi
fi

while IFS= read -r line
do
    echo "$line"
    if [[ -n "$changelog_json" ]] && [[ "$line" == "🔢 v"* ]]
    then
        version=$(echo "$line" | sed -E 's/^🔢 v([^ ]+) .*/\1/')
        jq -r --arg v "$version" '.versions[] | select(.version == $v) | .changes[] | "   • \(.)"' $changelog_json
    fi
done < <(echo "$selected_json" | jq -r "$render_text")

if [[ -n "$changelog_json" ]]
then
    jq -r '.feeds[] | "📜 changelog: \(sub("\\.xml$"; ".html"))"' $changelog_json
fi
