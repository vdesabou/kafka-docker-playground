key="${args[--key]}"
connector_class_filter="${args[--connector-class]}"
max_examples="${args[--max-examples]}"

# prints the entry of $1 (a config-<class>.txt reference) for key $2: group, documentation, type, default...
function config_key_entry () {
    awk -v key="$2" '
    $0 == "==========================" { header = !header; next }
    header { group = $0; next }
    $0 == "🔘 " key { found = 1; print "group: " group; next }
    found && /^🔘 / { exit }
    found { print }
    ' "$1"
}

# connector class (or fully managed type) of a config-<class>.txt or config-<class>-<version>.txt file
function config_key_class () {
    local name
    name=$(basename "$1" .txt)
    echo "${name#config-}"
}

cd "$root_folder" > /dev/null

# configuration references recorded by CI, one per tested connector
reference_files=()
while IFS= read -r file
do
    reference_files+=("$file")
done < <(git ls-files -- '*/config-*.txt' | sort)

if [ ${#reference_files[@]} -eq 0 ]
then
    logerror "❌ no connector configuration reference (config-<class>.txt) found in $root_folder"
    exit 1
fi

if [[ -n "$connector_class_filter" ]]
then
    filtered=()
    for file in "${reference_files[@]}"
    do
        if [[ "$(config_key_class "$file" | tr '[:upper:]' '[:lower:]')" == *"$(echo "$connector_class_filter" | tr '[:upper:]' '[:lower:]')"* ]]
        then
            filtered+=("$file")
        fi
    done
    if [ ${#filtered[@]} -eq 0 ]
    then
        logerror "❌ no connector matching --connector-class $connector_class_filter, connectors with a configuration reference are:"
        for file in "${reference_files[@]}"
        do
            config_key_class "$file"
        done | sort -u | column -c 160
        exit 1
    fi
    reference_files=("${filtered[@]}")
fi

# several examples of the same connector carry the same reference: keep one file per class
declare -A file_by_class=()
for file in "${reference_files[@]}"
do
    class=$(config_key_class "$file")
    if [ -z "${file_by_class[$class]}" ] && grep -q -x -F "🔘 $key" "$file"
    then
        file_by_class[$class]="$file"
    fi
done

# key also searched in the versions cached locally by 'playground connector show-config-parameters'
cached_only_classes=""
if [ -d "$root_folder/.connector_config" ]
then
    for file in $(grep -l -x -F "🔘 $key" "$root_folder"/.connector_config/config-*.txt 2>/dev/null)
    do
        class=$(config_key_class "$file")
        class="${class%-*}"
        if [[ -n "$connector_class_filter" ]] && [[ "$(echo "$class" | tr '[:upper:]' '[:lower:]')" != *"$(echo "$connector_class_filter" | tr '[:upper:]' '[:lower:]')"* ]]
        then
            continue
        fi
        if [ -z "${file_by_class[$class]}" ] && [[ " $cached_only_classes " != *" $class "* ]]
        then
            cached_only_classes="$cached_only_classes $class"
        fi
    done
fi

# keys handled by the Kafka Connect framework itself, common to every connector:
# self-managed plugins do not list them in their own configuration
framework_key_regex='^(name|connector\.class|tasks\.max|topics|topics\.regex|(key|value|header)\.converter(\..*)?|transforms(\..*)?|predicates(\..*)?|errors\..*|config\.action\.reload|(consumer|producer|admin)\.override\..*|exactly\.once\.support|transaction\.boundary(\..*)?|offsets\.storage\.topic|topic\.creation\..*)$'

key_found=1
if [ ${#file_by_class[@]} -eq 0 ] && [ -z "$cached_only_classes" ]
then
    key_found=0
fi

if [ $key_found -eq 0 ] && [[ "$key" =~ $framework_key_regex ]]
then
    log "🧩 $key is a Kafka Connect framework key, common to every connector${connector_class_filter:+: $connector_class_filter does not list it in its own configuration}"
    echo "   📗 https://docs.confluent.io/platform/current/installation/configuration/connect/sink-connect-configs.html"
    echo "   📗 https://docs.confluent.io/platform/current/installation/configuration/connect/source-connect-configs.html"
    echo ""
elif [ $key_found -eq 0 ]
then
    logwarn "🤷 key $key not found${connector_class_filter:+ for connector $connector_class_filter}"
    suggestions=$(grep -h "^🔘 .*$(echo "$key" | sed 's/[][\.*^$/]/\\&/g')" "${reference_files[@]}" 2>/dev/null | sed 's/^🔘 //' | sort | uniq -c | sort -rn | head -10)
    if [ -z "$suggestions" ]
    then
        # no key containing it: try with its last segment (s3.part.size -> size)
        last_segment="${key##*.}"
        suggestions=$(grep -h "^🔘 .*$(echo "$last_segment" | sed 's/[][\.*^$/]/\\&/g')" "${reference_files[@]}" 2>/dev/null | sed 's/^🔘 //' | sort | uniq -c | sort -rn | head -10)
    fi
    if [ -n "$suggestions" ]
    then
        log "💡 similar keys (number of connectors having it):"
        echo "$suggestions"
    fi
fi

classes=""
if [ ${#file_by_class[@]} -gt 0 ]
then
    classes=$(printf '%s\n' "${!file_by_class[@]}" | sort)
fi
nb_classes=${#file_by_class[@]}

if [ $nb_classes -gt 1 ] && [[ ! -n "$connector_class_filter" ]]
then
    log "🔌 $nb_classes connector(s) have key $key, use --connector-class to see the details of one"
    rows=""
    for class in $classes
    do
        entry=$(config_key_entry "${file_by_class[$class]}" "$key")
        type=$(echo "$entry" | sed -n 's/^[[:space:]]*- Type: //p')
        default=$(echo "$entry" | sed -n 's/^[[:space:]]*- Default: //p' | cut -c1-40)
        importance=$(echo "$entry" | sed -n 's/^[[:space:]]*- Importance: //p')
        rows="$rows$class|$type|$default|$importance"$'\n'
    done
    echo "   defaults: $(echo -n "$rows" | cut -d'|' -f3 | sort | uniq -c | sort -rn | awk '{ c = $1; $1 = ""; sub(/^ /, ""); printf "%s%s (x%d)", (NR > 1 ? ", " : ""), $0, c }')"
    echo ""
    { echo "CONNECTOR|TYPE|DEFAULT|IMPORTANCE"; echo -n "$rows" | head -20; } | column -t -s '|'
    if [ $nb_classes -gt 20 ]
    then
        echo "✂️ $((nb_classes - 20)) more connector(s) not shown, use --connector-class to narrow"
    fi
    echo ""
fi

shown=0
for class in $classes
do
    # without filter, details are only shown when a single connector has the key
    if [ $nb_classes -gt 1 ] && [[ ! -n "$connector_class_filter" ]]
    then
        break
    fi
    file="${file_by_class[$class]}"
    entry=$(config_key_entry "$file" "$key")
    group=$(echo "$entry" | sed -n '1s/^group: //p')

    log "🔑 $key in $class (group: $group)"
    echo "$entry" | sed '1d' | sed '/^$/d' | sed -E 's/^[[:space:]]+- /- /' | fold -s -w 120 | sed 's/^/   /'
    echo "   📄 $file"

    # when did CI first record the key: the commit where it appeared in the reference
    file_first=$(git log --reverse --format='%ad %h' --date=short -- "$file" | head -1)
    key_first=$(git log --reverse --format='%ad %h' --date=short -S"🔘 $key" -- "$file" | head -1)
    if [ -z "$key_first" ] || [ "$key_first" == "$file_first" ]
    then
        echo "   📅 present since CI first recorded this connector's configuration (${file_first%% *})"
    else
        echo "   📅 first recorded by CI on ${key_first%% *} (commit ${key_first##* }), absent from the earlier recordings since ${file_first%% *}: introduced by the connector version CI tested then"
    fi

    # versions run locally
    if [ -d "$root_folder/.connector_config" ]
    then
        versions=""
        for cached in $(ls "$root_folder"/.connector_config/config-"$class"-*.txt 2>/dev/null | sort -V)
        do
            version=$(config_key_class "$cached")
            version="${version##*-}"
            if grep -q -x -F "🔘 $key" "$cached"
            then
                cached_default=$(config_key_entry "$cached" "$key" | sed -n 's/^[[:space:]]*- Default: //p')
                versions="$versions $version ✅ ($cached_default)"
            else
                versions="$versions $version ❌"
            fi
        done
        if [ -n "$versions" ]
        then
            echo "   🗂️  versions run locally (default):$versions"
        fi
    fi
    echo ""
    shown=$((shown+1))
done

# without filter, only worth mentioning when CI recorded the key for no connector
if [[ ! -n "$connector_class_filter" ]] && [ ${#file_by_class[@]} -gt 0 ]
then
    cached_only_classes=""
fi
for class in $cached_only_classes
do
    versions=""
    for cached in $(ls "$root_folder"/.connector_config/config-"$class"-*.txt 2>/dev/null | sort -V)
    do
        version=$(config_key_class "$cached")
        version="${version##*-}"
        if grep -q -x -F "🔘 $key" "$cached"
        then
            versions="$versions $version ✅"
        else
            versions="$versions $version ❌"
        fi
    done
    logwarn "🗂️  $key only found in versions of $class run locally, not in the configuration recorded by CI (removed, or connector not tested by CI):$versions"
done

# examples setting the key, with their value
examples=$(grep -rn -F "\"$key\"" --include="*.sh" connect ccloud ksqldb flink schema-registry rest-proxy multi-data-center other operator academy environment reproduction-models 2>/dev/null | grep -v "/stop.sh:" || true)
examples_all="$examples"
if [[ -n "$connector_class_filter" ]] && [ -n "$examples" ]
then
    files_with_class=$(echo "$examples" | cut -d: -f1 | sort -u | xargs grep -l -i -F "$connector_class_filter" 2>/dev/null || true)
    examples=""
    if [ -n "$files_with_class" ]
    then
        examples=$(echo "$examples_all" | grep -F -f <(echo "$files_with_class" | sed 's/$/:/') 2>/dev/null || true)
    fi
fi
if [ -z "$examples" ]
then
    log "🧪 no example sets $key${connector_class_filter:+ with connector $connector_class_filter}"
else
    nb_examples=$(echo "$examples" | wc -l | tr -d ' ')
    log "🧪 $nb_examples line(s) in examples set $key${connector_class_filter:+ with connector $connector_class_filter}, values used (most frequent first):"
    echo "$examples" | sed -E "s/^([^:]+:[0-9]+):.*\"$(echo "$key" | sed 's/[][\.*^$/]/\\&/g')\"[[:space:]]*:[[:space:]]*(\"[^\"]*\"|[^,}]*).*/\2|\1/" \
        | awk -F'|' '{ count[$1]++; if (!($1 in where)) where[$1] = $2 } END { for (v in count) printf "%d|%s|%s\n", count[v], v, where[v] }' \
        | sort -t'|' -k1,1 -rn | head -n "$max_examples" \
        | awk -F'|' '{ printf "   %-30s x%-3d e.g. %s\n", $2, $1, $3 }'
fi

if [ $key_found -eq 0 ] && [ -z "$examples" ] && [[ ! "$key" =~ $framework_key_regex ]]
then
    exit 1
fi
