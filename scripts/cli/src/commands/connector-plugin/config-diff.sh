connector_plugin="${args[--connector-plugin]}"
from="${args[--from]}"
to="${args[--to]}"
connector_class="${args[--connector-class]}"
file="${args[--file]}"
with_docs="${args[--with-docs]}"
json="${args[--json]}"

# owner/name, a connector class or a fully managed type
if ! connector_plugin=$(resolve_connector_plugin "$connector_plugin")
then
    exit 1
fi
if [[ $file == *"@"* ]]
then
  file=$(echo "$file" | cut -d "@" -f 2)
fi

if ! command -v python3 > /dev/null 2>&1
then
    logerror "❌ python3 is required"
    exit 1
fi

if [[ -z "$to" ]] || [ "$to" == "latest" ]
then
    to=$(playground connector-plugin versions --connector-plugin "$connector_plugin" --latest 2>/dev/null)
    if [[ -z "$to" ]]
    then
        logerror "❌ could not find the latest version of $connector_plugin on Confluent Hub: set --to"
        exit 1
    fi
fi
if [ "$from" == "$to" ]
then
    logerror "❌ --from and --to are the same version ($from)"
    exit 1
fi

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
trap 'rm -rf $tmp_dir' EXIT

# with --file, the connector class of the customer config, when --connector-class is not set
config_file=""
if [[ -n "$file" ]]
then
    if ! jq -e 'type == "object"' "$file" > /dev/null 2>&1
    then
        # CFK / Strimzi / terraform / properties: the formats connector validate and diff accept
        if ! playground connector convert "$file" --to json > $tmp_dir/config.json 2> /dev/null || ! jq -e 'type == "object"' $tmp_dir/config.json > /dev/null 2>&1
        then
            logerror "❌ --file $file is not a connector configuration this command can read (JSON, or a format of playground connector convert)"
            exit 1
        fi
        config_file=$tmp_dir/config.json
    else
        config_file="$file"
    fi
    if [[ -z "$connector_class" ]]
    then
        connector_class=$(jq -r '(.config // .)["connector.class"] // empty' "$config_file")
    fi
fi

for version in "$from" "$to"
do
    if ! get_connector_plugin_configs "$connector_plugin" "$version" "$connector_class"
    then
        exit 1
    fi
    echo "$plugin_config_classes" > "$tmp_dir/classes-$version"
    echo "$plugin_configs_dir" > "$tmp_dir/dir-$version"
done

old_dir=$(cat "$tmp_dir/dir-$from")
new_dir=$(cat "$tmp_dir/dir-$to")
classes=$(sort -u "$tmp_dir/classes-$from" "$tmp_dir/classes-$to")

echo "[]" > $tmp_dir/result.json
for class in $classes
do
    old_file="$old_dir/config-$class.json"
    new_file="$new_dir/config-$class.json"
    if [ ! -s "$old_file" ] || [ ! -s "$new_file" ]
    then
        jq --arg c "$class" --arg in "$( [ -s "$old_file" ] && echo "$from" || echo "$to")" '. + [{connector_class: $c, only_in: $in}]' $tmp_dir/result.json > $tmp_dir/r.tmp && mv $tmp_dir/r.tmp $tmp_dir/result.json
        continue
    fi
    diff_args=(--old "$old_file" --new "$new_file")
    [[ -n "$config_file" ]] && diff_args+=(--config "$config_file")
    [[ -n "$with_docs" ]] && diff_args+=(--with-docs)
    if ! python3 -I "$root_folder/tools/connector-plugin-jars/config_diff.py" "${diff_args[@]}" > $tmp_dir/one.json 2> $tmp_dir/stderr
    then
        logerror "$(cat $tmp_dir/stderr)"
        exit 1
    fi
    jq --arg c "$class" --slurpfile one $tmp_dir/one.json '. + [{connector_class: $c} + $one[0]]' $tmp_dir/result.json > $tmp_dir/r.tmp && mv $tmp_dir/r.tmp $tmp_dir/result.json
done

if [[ -n "$json" ]]
then
    jq --arg p "$connector_plugin" --arg from "$from" --arg to "$to" '{connector_plugin: $p, from: $from, to: $to, connectors: .}' $tmp_dir/result.json
    exit 0
fi

r=$tmp_dir/result.json
for i in $(seq 0 $(( $(jq length $r) - 1 )))
do
    class=$(jq -r ".[$i].connector_class" $r)
    only_in=$(jq -r ".[$i].only_in // empty" $r)
    if [[ -n "$only_in" ]]
    then
        log "🔌 $class only exists in $only_in"
        continue
    fi
    if [ "$(jq ".[$i].nb_keys_old + .[$i].nb_keys_new" $r)" == "0" ]
    then
        # a helper class of the plugin without configuration (S3's SchemaSourceConnector)
        continue
    fi
    nb_changes=$(jq ".[$i] | (.added | length) + (.removed | length) + (.changed | length)" $r)
    scope=""
    [[ -n "$config_file" ]] && scope=", among the $(jq ".[$i].config_keys" $r) keys of $(basename "$file")"
    log "🔧 $class $from → $to: $(jq ".[$i].nb_keys_old" $r) → $(jq ".[$i].nb_keys_new" $r) keys, $nb_changes change(s)$scope"
    jq -r ".[$i] |
        (.added[] | \"   ➕ \(.key) (\(.type), default \(.default_value // \"none\"), \(.importance)): \(.documentation | gsub(\"\\n\"; \" \") | if length > 160 then .[0:160] + \"…\" else . end)\"),
        (.removed[] | \"   ➖ \(.key) (\(.type), default was \(.default_value // \"none\"))\"),
        (.changed[] | .key as \$k | .changes | to_entries[] |
            if .key == \"documentation\" then \"   📝 \(\$k): documentation changed\"
            elif .key == \"default_value\" then \"   ✏️ \(\$k): default \(.value.from // \"none\") → \(.value.to // \"none\")\"
            else \"   🔀 \(\$k): \(.key) \(.value.from // \"none\") → \(.value.to // \"none\")\" end)" $r
    if [[ -n "$config_file" ]]
    then
        jq -r ".[$i].unknown_in_new[]? | \"   ❗ \(.) is set in $(basename "$file") but $class $to doesn't know it (removed, renamed, or a typo)\"" $r
    fi
    if [ "$nb_changes" == "0" ] && [[ -z "$config_file" ]]
    then
        log "✅ no configuration change for $class between $from and $to"
    fi
done
log "💡 the release notes of the versions in between: playground connector-plugin changelog --connector-plugin $connector_plugin --from $from --to $to"
