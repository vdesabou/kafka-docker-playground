connector_plugin="${args[--connector-plugin]}"
from="${args[--from]}"
max_examples="${args[--max-examples]}"
json="${args[--json]}"
force_refresh="${args[--force-refresh]}"

if [[ $connector_plugin == *"@"* ]]
then
  connector_plugin=$(echo "$connector_plugin" | cut -d "@" -f 2)
fi

owner=$(echo "$connector_plugin" | cut -d "/" -f 1)
name=$(echo "$connector_plugin" | cut -d "/" -f 2)

if [[ "$name" != *"-"* ]]
then
    logerror "❌ $connector_plugin looks like a fully managed connector: it is not on Confluent Hub, use playground connector-plugin sourcecode --connector-plugin $connector_plugin"
    exit 1
fi

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
trap 'rm -rf $tmp_dir' EXIT

# 1. the plugin on Confluent Hub
if ! curl -s --max-time 30 -o $tmp_dir/plugin.json "https://api.hub.confluent.io/api/plugins/$owner/$name" || ! jq -e '.name' $tmp_dir/plugin.json > /dev/null 2>&1
then
    logerror "❌ $connector_plugin was not found on Confluent Hub"
    exit 1
fi

# 2. its versions (cached one day by connector-plugin versions)
versions_args=(--connector-plugin "$owner/$name" --json)
[[ -n "$from" ]] && versions_args+=(--from "$from")
[[ -n "$force_refresh" ]] && versions_args+=(--force-refresh)
if ! playground connector-plugin versions "${versions_args[@]}" > $tmp_dir/versions.json 2> /dev/null || ! jq -e '.latest' $tmp_dir/versions.json > /dev/null 2>&1
then
    echo '{}' > $tmp_dir/versions.json
fi
# all versions, for the count and the first release (--from keeps only the newer ones)
all_versions_args=(--connector-plugin "$owner/$name" --json)
playground connector-plugin versions "${all_versions_args[@]}" > $tmp_dir/all_versions.json 2> /dev/null || echo '{"versions": []}' > $tmp_dir/all_versions.json

# 3. examples of this repository using the plugin, and their connector classes
cd "$root_folder" > /dev/null
git grep -l -E "confluent-hub-components/${owner}-${name}([^A-Za-z0-9-]|$)" -- '*docker-compose*.yml' 2>/dev/null | xargs -n1 dirname 2>/dev/null | sort -u > $tmp_dir/example_dirs || true
# only from the examples that use this plugin alone: the others record the classes of their other plugins too
classes=$(while read -r dir
do
    nb_plugins=$(grep -ohE "confluent-hub-components/[A-Za-z0-9_.-]+" "$dir"/docker-compose*.yml 2>/dev/null | sort -u | wc -l | tr -d ' ')
    [ "$nb_plugins" == "1" ] || continue
    for f in "$dir"/config-*.txt
    do
        [ -f "$f" ] || continue
        c=$(basename "$f" .txt)
        c="${c#config-}"
        [[ "$c" == *.* ]] && echo "$c"
    done
done < $tmp_dir/example_dirs | sort -u)

# 4. fully managed examples whose folder name has the words of the plugin name (a heuristic: there is no mapping)
short_name=$(echo "$name" | sed -E 's/^(kafka-connect-|kafka-connector-|connect-)//; s/^debezium-connector-//; s/-(connector|kafka-connector|kafka-connect)$//')
fm_words=$(echo "$short_name" | tr '-' ' ')
if [ "$owner" != "confluentinc" ]
then
    fm_words="$owner $fm_words"
fi
fm_types=""
fm_dirs=""
for dir in ccloud/fm-*/
do
    dir="${dir%/}"
    folder=$(basename "$dir")
    match=1
    for w in $fm_words
    do
        if [[ "$folder" != *"$w"* ]]
        then
            match=0
            break
        fi
    done
    [ $match -eq 1 ] || continue
    [[ "$folder" == fm-custom-* ]] && continue
    fm_dirs="$fm_dirs$dir"$'\n'
    for f in "$dir"/config-*.txt
    do
        [ -f "$f" ] || continue
        t=$(basename "$f" .txt)
        fm_types="$fm_types${t#config-}"$'\n'
    done
done
fm_types=$(echo "$fm_types" | grep -v '^$' | sort -u)
fm_dirs=$(echo "$fm_dirs" | grep -v '^$' | sort -u)

# 5. CI status of each example, from the badges of the published content page (cached one hour)
content_file="/tmp/connector-plugin-info-content.md"
if [[ -n "$force_refresh" ]] || [ ! -s "$content_file" ] || [ -z "$(find "$content_file" -mmin -60 2>/dev/null)" ]
then
    curl -s --max-time 30 -o "$content_file.tmp" https://kafka-docker-playground.io/content.md && mv "$content_file.tmp" "$content_file" || rm -f "$content_file.tmp"
fi
: > $tmp_dir/examples.tsv
while read -r dir
do
    [[ -z "$dir" ]] && continue
    status="unknown"
    if [ -s "$content_file" ]
    then
        line=$(grep -F "tree/master/$dir)" "$content_file" | head -1)
        if [[ "$line" == *"[CI ok]"* ]] || [[ "$line" == *"[![CI ok]"* ]]
        then
            status="ok"
        elif [[ "$line" == *"CI fail"* ]]
        then
            status="fail"
        elif [[ "$line" == *"not tested"* ]]
        then
            status="not tested"
        fi
    fi
    printf '%s\t%s\n' "$dir" "$status" >> $tmp_dir/examples.tsv
done < $tmp_dir/example_dirs

# 6. release notes feed and source code (best effort)
changelog_url=""
if [ "$owner" == "confluentinc" ] && command -v python3 > /dev/null 2>&1
then
    latest=$(jq -r '.latest // empty' $tmp_dir/all_versions.json)
    if [[ -n "$latest" ]] && python3 -I "$root_folder/tools/connector-changelog/changelog.py" --connector-plugin "$owner/$name" --version "$latest" > $tmp_dir/changelog.json 2> /dev/null
    then
        changelog_url=$(jq -r '.feeds[0] // empty | sub("\\.xml$"; ".html")' $tmp_dir/changelog.json)
    fi
fi
sourcecode_url=$(playground connector-plugin sourcecode --connector-plugin "$owner/$name" --only-show-url 2>/dev/null | grep -E "^https?://" | tail -1)

jq -n \
    --slurpfile p $tmp_dir/plugin.json \
    --slurpfile v $tmp_dir/versions.json \
    --slurpfile all $tmp_dir/all_versions.json \
    --arg plugin "$owner/$name" \
    --arg from "$from" \
    --arg classes "$classes" \
    --arg fm_types "$fm_types" \
    --arg fm_dirs "$fm_dirs" \
    --arg fm_words "$fm_words" \
    --rawfile examples $tmp_dir/examples.tsv \
    --arg changelog "$changelog_url" \
    --arg sourcecode "$sourcecode_url" '
    def lines($s): $s | split("\n") | map(select(. != ""));
    $p[0] as $p | $all[0] as $all | $v[0] as $v |
    {
        connector_plugin: $plugin,
        title: $p.title,
        owner: $p.owner.name,
        license: [($p.license // [])[].name],
        component_types: ($p.component_types // []),
        latest: ($all.latest // $p.version),
        latest_release_date: ($all.versions[-1].release_date // $p.release_date),
        latest_days_ago: $all.versions[-1].days_ago,
        nb_versions: ($all.versions | length),
        first_release_date: ([$all.versions[] | .release_date | select(. != null)] | min),
        requirements: $p.requirements,
        docker_image: (if $p.docker_image.name then ([$p.docker_image.namespace, $p.docker_image.name] | map(select(. != null)) | join("/")) else null end),
        documentation_url: $p.documentation_url,
        changelog_url: (if $changelog == "" then null else $changelog end),
        sourcecode_url: (if $sourcecode == "" then null else $sourcecode end),
        examples: [lines($examples)[] | split("\t") | {dir: .[0], ci: .[1]}],
        connector_classes: lines($classes),
        fully_managed: {heuristic: "ccloud/fm-* folders with the words \"\($fm_words)\" in their name", types: lines($fm_types), examples: lines($fm_dirs)}
    }
    + (if $from != "" then {from: $from, versions_behind: $v.versions_behind} else {} end)' > $tmp_dir/info.json

if [[ -n "$json" ]]
then
    cat $tmp_dir/info.json
    exit 0
fi

i=$tmp_dir/info.json
jq -r '"🔌 \(.connector_plugin): \(.title)",
    "   🏢 \(.owner // "?")   📜 \(.license | join(", ") | if . == "" then "license unknown" else . end)   🧩 \(.component_types | join(", "))",
    "   🔢 latest \(.latest) (\(.latest_release_date // "release date unknown")\(if .latest_days_ago != null then ", \(.latest_days_ago) days ago" else "" end)), \(.nb_versions) version(s)\(if .first_release_date then " since \(.first_release_date)" else "" end)"' $i
if [[ -n "$from" ]]
then
    behind=$(jq -r '.versions_behind // empty' $i)
    if [ "$behind" == "0" ]
    then
        echo "   ✅ $from is the latest version"
    elif [[ -n "$behind" ]]
    then
        echo "   📌 $from is $behind version(s) behind the latest (playground connector-plugin changelog --connector-plugin $owner/$name --from $from)"
    fi
fi
jq -r 'if .requirements then "   ✅ requirements: \(.requirements | tostring)" else empty end,
    if .docker_image then "   🐳 docker image: \(.docker_image)" else empty end' $i

nb_examples=$(jq '.examples | length' $i)
if [ "$nb_examples" == "0" ]
then
    log "🧪 no example of this repository uses $owner/$name"
else
    log "🧪 $nb_examples example(s) use it, CI: $(jq -r '[.examples[] | select(.ci == "ok")] | length' $i) 🟢 ok, $(jq -r '[.examples[] | select(.ci == "fail")] | length' $i) 🔴 fail, $(jq -r '[.examples[] | select(.ci != "ok" and .ci != "fail")] | length' $i) 🤷 not tested or unknown"
    jq -r --argjson max "$max_examples" '.examples[0:$max][] | "   \(if .ci == "ok" then "🟢" elif .ci == "fail" then "🔴" else "🤷" end) \(.dir)"' $i
    if [ "$nb_examples" -gt "$max_examples" ]
    then
        echo "   … $((nb_examples - max_examples)) more (--max-examples), or playground find-example \"$short_name\""
    fi
    jq -r 'if (.connector_classes | length) > 0 then "   🔌 connector classes: \(.connector_classes | join(", "))" else empty end' $i
fi
if [ "$(jq '.fully_managed.types | length' $i)" != "0" ]
then
    log "☁️ fully managed examples named like it ($(jq -r '.fully_managed.examples | length' $i) folder(s) with \"$fm_words\"): $(jq -r '.fully_managed.types | join(", ")' $i)"
fi
jq -r '"🌐 documentation: \(.documentation_url // "<not available>")",
    if .changelog_url then "📜 changelog: \(.changelog_url)" else empty end,
    if .sourcecode_url then "🧑‍💻 source code: \(.sourcecode_url)" else empty end' $i
