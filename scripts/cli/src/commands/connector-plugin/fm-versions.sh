connector_plugin="${args[--connector-plugin]}"
last="${args[--last]}"
cc_connect_version="${args[--cc-connect-version]}"
find_first="${args[--find-first]}"
with_log="${args[--with-log]}"
json="${args[--json]}"
force_refresh="${args[--force-refresh]}"

# owner/name, a connector class or a fully managed type
if ! connector_plugin=$(resolve_connector_plugin "$connector_plugin")
then
    exit 1
fi

# with --json, the logs go to stderr
exec 3>&1
if [[ -n "$json" ]]
then
    exec 1>&2
fi

if [[ "$connector_plugin" == *"-"* ]]
then
    logerror "❌ $connector_plugin is a self-managed plugin: use playground connector-plugin versions"
    exit 1
fi

plugin_list="$root_folder/scripts/cli/confluent-hub-plugin-list.txt"
if [ ! -f "$plugin_list" ]
then
    log "file $plugin_list not found. Generating it now, it may take a while..."
    playground generate-connector-plugin-list
fi
if ! grep -q "CONFLUENT EMPLOYEE VERSION" "$plugin_list" 2>/dev/null
then
    logerror "❌ fully managed connectors need the Confluent employee version of the plugin list: set your AWS credentials, then run playground generate-connector-plugin-list"
    exit 1
fi
line=$(awk -F'|' -v plugin="$connector_plugin" '{ current = $1; sub(/^[^[:space:]]+[[:space:]]+/, "", current); if (current == plugin) { print $0; exit } }' "$plugin_list")
variable=$(echo "$line" | cut -d "|" -f 3)
repo_url=$(echo "$line" | cut -d "|" -f 2)
if [[ -z "$line" ]] || [[ -z "$variable" ]]
then
    logerror "❌ $connector_plugin is not a fully managed connector of the plugin list (no cache-versions.env variable)"
    exit 1
fi

# GET on the private repository confluentinc/cc-docker-connect: gh when logged in, else curl with GH_TOKEN / GITHUB_TOKEN
token="${GH_TOKEN:-$GITHUB_TOKEN}"
use_gh=0
if command -v gh > /dev/null 2>&1 && gh auth status > /dev/null 2>&1
then
    use_gh=1
    [[ -z "$token" ]] && token=$(gh auth token 2>/dev/null)
fi
if [ $use_gh -eq 0 ] && [[ -z "$token" ]]
then
    logerror "❌ confluentinc/cc-docker-connect is private: log in with gh auth login, or set GH_TOKEN (Confluent employees, VPN)"
    exit 1
fi

cache_dir="/tmp/connector-plugin-fm"
mkdir -p "$cache_dir"

# the cc-connect image versions: tags v0.<n>.<patch> of cc-docker-connect, cached one day (about 30 s to list)
tags_file="$cache_dir/cc-docker-connect-tags.txt"
if [[ -n "$force_refresh" ]] || [ ! -s "$tags_file" ] || [ -z "$(find "$tags_file" -mmin -1440 2>/dev/null)" ]
then
    log "🏷️ Listing the cc-connect versions (tags of confluentinc/cc-docker-connect, once a day)"
    if [ $use_gh -eq 1 ]
    then
        gh api --paginate "repos/confluentinc/cc-docker-connect/tags?per_page=100" --jq '.[].name' > "$tags_file.tmp" 2>/dev/null
    else
        : > "$tags_file.tmp"
        for page in $(seq 1 100)
        do
            names=$(curl -s -f -H "Authorization: Bearer $token" "https://api.github.com/repos/confluentinc/cc-docker-connect/tags?per_page=100&page=$page" | jq -r '.[].name' 2>/dev/null)
            [[ -z "$names" ]] && break
            echo "$names" >> "$tags_file.tmp"
        done
    fi
    grep -E '^v0\.[0-9]+\.[0-9]+$' "$tags_file.tmp" | sed 's/^v//' | sort -V -u > "$tags_file"
    rm -f "$tags_file.tmp"
    if [ ! -s "$tags_file" ]
    then
        logerror "❌ could not list the tags of confluentinc/cc-docker-connect (VPN? token?)"
        rm -f "$tags_file"
        exit 1
    fi
fi

# connector version in cc-connect version $1 (cache-versions.env at that tag, cached forever: a tag doesn't move)
function fm_connector_version_in () {
    local tag="$1" file="$cache_dir/cache-versions-$1.env"
    if [ ! -s "$file" ]
    then
        if [ $use_gh -eq 1 ]
        then
            gh api "repos/confluentinc/cc-docker-connect/contents/cc-connect/cache-versions.env?ref=v$tag" -H "Accept: application/vnd.github.raw" > "$file" 2>/dev/null || rm -f "$file"
        else
            curl -s -f -H "Authorization: Bearer $token" "https://raw.githubusercontent.com/confluentinc/cc-docker-connect/refs/tags/v$tag/cc-connect/cache-versions.env" -o "$file" || rm -f "$file"
        fi
    fi
    # always succeeds (empty when unknown): it is called in $(...) under set -e
    if [ -s "$file" ]
    then
        grep -E "^export ${variable}=" "$file" | head -1 | cut -d "=" -f 2 || true
    fi
    return 0
}

# numeric part of a connector version: 3.2.0-rc-4be74dd8-cloud -> 3.2.0
function fm_numeric () {
    echo "$1" | grep -oE '^[0-9]+(\.[0-9]+)*'
}

tags=()
while IFS= read -r t
do
    tags+=("$t")
done < "$tags_file"
nb_tags=${#tags[@]}

if [[ -n "$cc_connect_version" ]]
then
    cc_connect_version="${cc_connect_version#v}"
    version=$(fm_connector_version_in "$cc_connect_version")
    if [[ -z "$version" ]]
    then
        logerror "❌ no $variable in cache-versions.env of cc-connect $cc_connect_version (unknown version, or connector not in it)"
        exit 1
    fi
    if [[ -n "$json" ]]
    then
        jq -n --arg p "$connector_plugin" --arg cc "$cc_connect_version" --arg v "$version" '{connector_plugin: $p, cc_connect_version: $cc, connector_version: $v}' >&3
    else
        log "☁️ cc-connect $cc_connect_version ships $connector_plugin $version"
        echo "$version" >&3
    fi
    exit 0
fi

if [[ -n "$find_first" ]]
then
    target=$(fm_numeric "$find_first")
    if [[ -z "$target" ]]
    then
        logerror "❌ --find-first $find_first is not a version (for example 3.2.0)"
        exit 1
    fi
    # true when cc-connect version $1 ships the connector in version >= target
    function fm_ships () {
        local v n
        v=$(fm_connector_version_in "$1")
        n=$(fm_numeric "$v")
        if [[ -z "$n" ]] || version_gt "$target" "$n"
        then
            log "   🔍 cc-connect $1: ${v:-not in it}" >&2
            return 1
        fi
        log "   🔍 cc-connect $1: $v ✅" >&2
        return 0
    }
    log "🔎 First cc-connect version shipping $connector_plugin ≥ $target, among $nb_tags versions (binary search)"
    lo=0
    hi=$((nb_tags - 1))
    if ! fm_ships "${tags[$hi]}"
    then
        if [[ -n "$json" ]]
        then
            jq -n --arg p "$connector_plugin" --arg t "$target" --arg latest "${tags[$hi]}" '{connector_plugin: $p, target: $t, first_cc_connect_version: null, latest_cc_connect_version: $latest}' >&3
        else
            logwarn "🤷 even the latest cc-connect version ${tags[$hi]} doesn't ship $connector_plugin ≥ $target"
        fi
        exit 0
    fi
    while [ $lo -lt $hi ]
    do
        mid=$(( (lo + hi) / 2 ))
        if fm_ships "${tags[$mid]}"
        then
            hi=$mid
        else
            lo=$((mid + 1))
        fi
    done
    found=$(fm_connector_version_in "${tags[$lo]}")
    if [[ -n "$json" ]]
    then
        jq -n --arg p "$connector_plugin" --arg t "$target" --arg cc "${tags[$lo]}" --arg v "$found" '{connector_plugin: $p, target: $t, first_cc_connect_version: $cc, connector_version: $v}' >&3
    else
        log "✅ cc-connect ${tags[$lo]} is the first version shipping $connector_plugin ≥ $target ($found)"
        log "💡 that's the image version, not a deployment: the cc-connect version of a cluster is in its connect logs (chewie)"
    fi
    exit 0
fi

# the last --last cc-connect versions, grouped by connector version
last="${last:-10}"
start=$(( nb_tags > last ? nb_tags - last : 0 ))
: > "$cache_dir/rows.$$"
for (( i=start; i<nb_tags; i++ ))
do
    printf '%s\t%s\n' "${tags[$i]}" "$(fm_connector_version_in "${tags[$i]}")" >> "$cache_dir/rows.$$"
done
rows_json=$(jq -R -s 'split("\n") | map(select(. != "") | split("\t") | {cc_connect_version: .[0], connector_version: (.[1] | if . == "" then null else . end)})' "$cache_dir/rows.$$")
rm -f "$cache_dir/rows.$$"
# consecutive cc-connect versions shipping the same connector version
groups_json=$(echo "$rows_json" | jq 'reduce .[] as $r ([]; if (length > 0 and .[-1].connector_version == $r.connector_version) then .[-1].to = $r.cc_connect_version else . + [{connector_version: $r.connector_version, from: $r.cc_connect_version, to: $r.cc_connect_version}] end)')

if [[ -n "$json" ]]
then
    jq -n --arg p "$connector_plugin" --arg var "$variable" --arg repo "$repo_url" --argjson rows "$rows_json" --argjson groups "$groups_json" \
        '{connector_plugin: $p, variable: $var, repository: $repo, cc_connect_versions: $rows, changes: $groups}' >&3
    exit 0
fi

log "☁️ $connector_plugin ($variable) in the last $((nb_tags - start)) cc-connect versions, newest first"
echo "$groups_json" | jq -r 'reverse[] | "   \(if .from == .to then .from else "\(.from) … \(.to)" end)  →  \(.connector_version // "not in it")"'
log "🧑‍💻 source code: playground connector-plugin sourcecode -c $connector_plugin --connector-tag <cc-connect version> --only-show-url"

if [[ -n "$with_log" ]]
then
    # the commits between two consecutive connector versions (sourcecode --log maps the cc-connect versions to repository tags)
    nb_groups=$(echo "$groups_json" | jq length)
    for (( g=nb_groups-1; g>0; g-- ))
    do
        old_cc=$(echo "$groups_json" | jq -r ".[$((g-1))].to")
        new_cc=$(echo "$groups_json" | jq -r ".[$g].from")
        old_v=$(echo "$groups_json" | jq -r ".[$((g-1))].connector_version // empty")
        new_v=$(echo "$groups_json" | jq -r ".[$g].connector_version // empty")
        [[ -z "$old_v" ]] || [[ -z "$new_v" ]] && continue
        log "📜 $old_v → $new_v (cc-connect $old_cc → $new_cc)"
        GH_TOKEN="$token" playground --output-level WARN connector-plugin sourcecode -c "$connector_plugin" --connector-tag "$old_cc" --connector-tag "$new_cc" --log 2>&1 | grep -E "^   [0-9]{4}-" || logwarn "   no commit found (tags missing in $repo_url?)"
    done
fi
