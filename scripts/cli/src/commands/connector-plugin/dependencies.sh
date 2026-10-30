connector_plugin="${args[--connector-plugin]}"
connector_zip="${args[--connector-zip]}"
grep="${args[--grep]}"
find_first="${args[--find-first]}"
json="${args[--json]}"
force_refresh="${args[--force-refresh]}"
eval "connector_tags=(${args[--connector-tag]:-})"

if [[ $connector_plugin == *"@"* ]]
then
  connector_plugin=$(echo "$connector_plugin" | cut -d "@" -f 2)
fi

if ! command -v python3 > /dev/null 2>&1
then
    logerror "❌ python3 is required"
    exit 1
fi
if [[ -z "$connector_plugin" ]] && [[ -z "$connector_zip" ]]
then
    logerror "❌ --connector-plugin or --connector-zip is required"
    exit 1
fi
if [ ${#connector_tags[@]} -gt 2 ]
then
    logerror "❌ --connector-tag can be set 2 times at most (to compare 2 versions)"
    exit 1
fi

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
trap 'rm -rf $tmp_dir' EXIT
deps="$root_folder/tools/connector-plugin-jars/dependencies.py"

# --find-first <artifact>:<version>: binary search over the versions of the plugin on the Hub
if [[ -n "$find_first" ]]
then
    if [[ -z "$connector_plugin" ]] || [[ -n "$connector_zip" ]]
    then
        logerror "❌ --find-first needs --connector-plugin (versions of Confluent Hub)"
        exit 1
    fi
    artifact="${find_first%%:*}"
    target="${find_first#*:}"
    if [[ -z "$artifact" ]] || [[ -z "$target" ]] || [ "$artifact" == "$find_first" ]
    then
        logerror "❌ --find-first must be <artifact>:<version>, for example jackson-databind:2.18.0"
        exit 1
    fi
    # release versions in version order (previews, betas and release candidates left out), from --connector-tag if set
    playground connector-plugin versions --connector-plugin "$connector_plugin" --json 2> /dev/null | jq -r '.versions[].version' | grep -viE "preview|alpha|beta|rc|snapshot" | sort -V > $tmp_dir/versions || true
    if [ ${#connector_tags[@]} -gt 0 ]
    then
        awk -v from="${connector_tags[0]}" 'found || $0 == from { found = 1; print }' $tmp_dir/versions > $tmp_dir/versions.from
        mv $tmp_dir/versions.from $tmp_dir/versions
    fi
    versions=()
    while IFS= read -r v
    do
        versions+=("$v")
    done < $tmp_dir/versions
    if [ ${#versions[@]} -eq 0 ]
    then
        logerror "❌ no version of $connector_plugin to search${connector_tags[0]:+ from ${connector_tags[0]}}"
        exit 1
    fi

    # prints the version of $artifact shipped in version $1 (empty when absent)
    function artifact_version_in () {
        get_connector_plugin_lib_dir "$connector_plugin" "$1" "" "" 2> /dev/null > /dev/null || return 1
        python3 -I "$deps" --lib-dir "$plugin_lib_dir" --grep "(^|:)${artifact}$" | jq -r --arg a "$artifact" '[.libraries[] | select((.artifact | ascii_downcase) == ($a | ascii_downcase)) | .version] | sort_by(split(".") | map(tonumber? // 0)) | last // empty'
    }
    # true when version $1 of the plugin ships $artifact >= $target
    function ships_target () {
        local found
        found=$(artifact_version_in "$1")
        if [[ -z "$found" ]]
        then
            log "   🔍 $connector_plugin $1: no $artifact" >&2
            return 1
        fi
        if version_gt "$target" "$found"
        then
            log "   🔍 $connector_plugin $1: $artifact $found" >&2
            return 1
        fi
        log "   🔍 $connector_plugin $1: $artifact $found ✅" >&2
        return 0
    }

    log "🔎 First version of $connector_plugin shipping $artifact ≥ $target, among ${#versions[@]} version(s) from ${versions[0]} to ${versions[${#versions[@]}-1]} (binary search, each version downloaded once)" >&2
    lo=0
    hi=$((${#versions[@]} - 1))
    if ! ships_target "${versions[$hi]}"
    then
        if [[ -n "$json" ]]
        then
            jq -n --arg p "$connector_plugin" --arg a "$artifact" --arg t "$target" --arg latest "${versions[$hi]}" '{connector_plugin: $p, artifact: $a, target: $t, first_version: null, latest: $latest}'
        else
            logwarn "🤷 even the latest version ${versions[$hi]} doesn't ship $artifact ≥ $target"
        fi
        exit 0
    fi
    while [ $lo -lt $hi ]
    do
        mid=$(( (lo + hi) / 2 ))
        if ships_target "${versions[$mid]}"
        then
            hi=$mid
        else
            lo=$((mid + 1))
        fi
    done
    first="${versions[$lo]}"
    found=$(artifact_version_in "$first")
    if [[ -n "$json" ]]
    then
        jq -n --arg p "$connector_plugin" --arg a "$artifact" --arg t "$target" --arg first "$first" --arg found "$found" '{connector_plugin: $p, artifact: $a, target: $t, first_version: $first, artifact_version: $found}'
    else
        log "✅ $connector_plugin $first is the first version shipping $artifact ≥ $target ($found)"
        log "💡 versions of several minor lines are interleaved: check the line of the customer with --connector-tag <first version of that line>"
    fi
    exit 0
fi

# one version (or a zip), or the diff of two versions
lib_dirs=()
labels=()
if [[ -n "$connector_zip" ]]
then
    get_connector_plugin_lib_dir "" "" "$connector_zip" "$force_refresh" || exit 1
    lib_dirs+=("$plugin_lib_dir")
    labels+=("$plugin_label")
fi
if [[ -n "$connector_plugin" ]]
then
    if [ ${#connector_tags[@]} -eq 0 ]
    then
        connector_tags=("latest")
    fi
    for tag in "${connector_tags[@]}"
    do
        get_connector_plugin_lib_dir "$connector_plugin" "$tag" "" "$force_refresh" || exit 1
        lib_dirs+=("$plugin_lib_dir")
        labels+=("$plugin_label")
    done
fi
if [ ${#lib_dirs[@]} -gt 2 ]
then
    logerror "❌ compare 2 things at most: --connector-zip and one --connector-tag, or two --connector-tag"
    exit 1
fi

deps_args=()
for i in "${!lib_dirs[@]}"
do
    deps_args+=(--lib-dir "${lib_dirs[$i]}" --label "${labels[$i]}")
done
[[ -n "$grep" ]] && deps_args+=(--grep "$grep")
if ! python3 -I "$deps" "${deps_args[@]}" > $tmp_dir/result.json 2> $tmp_dir/stderr
then
    logerror "❌ could not read the libraries: $(cat $tmp_dir/stderr)"
    exit 1
fi
while IFS= read -r line
do
    [[ -n "$line" ]] && logwarn "$line"
done < $tmp_dir/stderr

if [[ -n "$json" ]]
then
    cat $tmp_dir/result.json
    exit 0
fi

r=$tmp_dir/result.json
if [ ${#lib_dirs[@]} -eq 1 ]
then
    nb=$(jq '.libraries | length' $r)
    log "📚 $nb librar(y/ies) in ${labels[0]}${grep:+ matching \"$grep\"}"
    if [ "$nb" == "0" ]
    then
        exit 0
    fi
    jq -r '.libraries[] | [ (if .group then "\(.group):\(.artifact)" else .artifact end), (.version // "?"), (if .shaded then "inside \(.jar)" else .jar end) ] | @tsv' $r | column -t -s $'\t'
    exit 0
fi

nb=$(jq '.changes | length' $r)
log "📚 ${labels[0]} → ${labels[1]}: $nb change(s)${grep:+ matching \"$grep\"}, $(jq .nb_unchanged $r) librar(y/ies) unchanged"
jq -r '
    (.changes[] | select(.change == "upgraded" or .change == "downgraded") | [ (if .change == "upgraded" then "⬆️" else "⬇️" end), .artifact, "\(.from) → \(.to)" ] | @tsv),
    (.changes[] | select(.change == "added") | [ "➕", .artifact, (.to // "?") ] | @tsv),
    (.changes[] | select(.change == "removed") | [ "➖", .artifact, (.from // "?") ] | @tsv)' $r | column -t -s $'\t'
