connector="${args[--connector]}"
json=${args[json]}
connector_plugin="${args[--connector-plugin]}"
from="${args[--from]}"
to="${args[--to]}"
cp_version="${args[--cp-version]}"
with_cve="${args[--with-cve]}"
verbose="${args[--verbose]}"
output_json="${args[--json]}"

# --json: the JSON verdict is the only thing on stdout (fd 3), the log lines go to stderr
if [[ -n "$output_json" ]]
then
    exec 3>&1 1>&2
fi

if ! command -v python3 > /dev/null 2>&1
then
    logerror "❌ python3 is required to compare the versions"
    exit 2
fi

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

if [ "$json" = "-" ]
then
    json_content=$(read_stdin_if_any)
else
    json_content=$json
fi

running=""
if [[ -z "$json_content" ]]
then
    # no config on stdin: the config of the running connector
    if [[ -z "$connector" ]]
    then
        logerror "❌ give the config on stdin, or --connector for the config of a running connector"
        exit 2
    fi
    connector_type=$(playground state get run.connector_type)
    if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
    then
        logerror "❌ $connector is a fully managed connector: Confluent upgrades it (playground connector-plugin fm-versions shows the version of each cc-connect image)"
        exit 2
    fi
    if ! get_connector_config_json "$connector"
    then
        logerror "❌ could not get the config of connector $connector"
        exit 2
    fi
    json_content="$curl_output"
    running=1
else
    # json, or one of the formats customers send (CFK / Strimzi custom resource, terraform, .properties, REST API dump...)
    if ! normalize_connector_config "$json_content" "$connector"
    then
        logerror "❌ $NORMALIZED_ERROR"
        exit 2
    fi
    if [ "$NORMALIZED_FORMAT" != "JSON" ]
    then
        log "📦 detected: $NORMALIZED_FORMAT"
    fi
    json_content="$NORMALIZED_CONFIG"
    connector="${connector:-${NORMALIZED_NAME:-connector}}"
fi
echo "$json_content" > "$tmp_dir/config.json"

connector_class=$(jq -r '.["connector.class"] // empty' "$tmp_dir/config.json")
if [[ -z "$connector_class" ]]
then
    logerror "❌ the config has no connector.class"
    exit 2
fi

# the plugin: --connector-plugin, else the plugin of the class in the examples
if [[ -z "$connector_plugin" ]]
then
    connector_plugin="$connector_class"
fi
if ! connector_plugin=$(resolve_connector_plugin "$connector_plugin")
then
    exit 2
fi
if [[ "$connector_plugin" != */* ]] || [[ "$connector_plugin" == confluentinc/[A-Z]* ]]
then
    logerror "❌ $connector_plugin is not a plugin of Confluent Hub: fully managed connectors are upgraded by Confluent"
    exit 2
fi

# the version in use: --from, else the version of the plugin in the running worker
if [[ -z "$from" ]]
then
    if [[ -n "$running" ]]
    then
        from=$(benchmark_plugin_version "$connector_class" "" 2>/dev/null)
        if [[ -z "$from" ]] || [ "$from" == "unknown" ] || [ "$from" == "null" ]
        then
            # a plugin that reports no version (HTTP source: "unknown"): the manifest of the installed plugin
            get_connect_container
            from=$(docker exec "${connect_container:-connect}" cat "/usr/share/confluent-hub-components/${connector_plugin/\//-}/manifest.json" 2>/dev/null | jq -r '.version // empty' 2>/dev/null)
        fi
    fi
    if [[ -z "$from" ]]
    then
        logerror "❌ pass --from with the version the customer runs (it is only detected for a running connector)"
        exit 2
    fi
    log "🔎 $connector_class runs version $from in the worker"
fi
if [[ -z "$to" ]] || [ "$to" == "latest" ]
then
    to=$(playground connector-plugin versions --connector-plugin "$connector_plugin" --latest 2>/dev/null)
    if [[ -z "$to" ]]
    then
        logerror "❌ could not find the latest version of $connector_plugin on Confluent Hub: set --to"
        exit 2
    fi
fi
if [ "$from" == "$to" ]
then
    log "✅ $connector_plugin $from is already the target version"
    [[ -n "$output_json" ]] && jq -n --arg p "$connector_plugin" --arg v "$from" '{connector_plugin: $p, from: $v, to: $v, verdict: "safe", findings: []}' >&3
    exit 0
fi

if [ "$connector" == "connector" ]
then
    log "🔼 Checking $connector_plugin $from → $to for this config (nothing is created)"
else
    log "🔼 Checking $connector_plugin $from → $to for connector $connector (nothing is created)"
fi

# the configuration of the connector class in both versions (downloaded and read once, then cached)
for version in "$from" "$to"
do
    if ! get_connector_plugin_configs "$connector_plugin" "$version" "$connector_class"
    then
        logerror "❌ could not read the configuration of $connector_class in $connector_plugin $version"
        exit 2
    fi
    if [ ! -s "$plugin_configs_dir/config-$connector_class.json" ]
    then
        logerror "❌ $connector_class is not in $connector_plugin $version"
        exit 2
    fi
    cp "$plugin_configs_dir/config-$connector_class.json" "$tmp_dir/config-$version.json"
done

# the release notes, the bundled libraries and how far behind (best effort: each part is optional)
log "📜 Reading the release notes, the libraries and the versions"
playground connector-plugin changelog --connector-plugin "$connector_plugin" --from "$from" --to "$to" --json > "$tmp_dir/changelog.json" 2> "$tmp_dir/changelog.err" || rm -f "$tmp_dir/changelog.json"
playground connector-plugin dependencies --connector-plugin "$connector_plugin" --connector-tag "$from" --connector-tag "$to" --json > "$tmp_dir/dependencies.json" 2> "$tmp_dir/dependencies.err" || rm -f "$tmp_dir/dependencies.json"
playground connector-plugin info --connector-plugin "$connector_plugin" --from "$from" --json > "$tmp_dir/info.json" 2> /dev/null || rm -f "$tmp_dir/info.json"
if [[ -n "$with_cve" ]]
then
    log "🛡️ Scanning both versions for CVEs (the first scan downloads the grype database)"
    playground connector-plugin cve-scan --connector-plugin "$connector_plugin" --connector-tag "$from" --compare-with "$to" --no-open --json > "$tmp_dir/cve.json" 2> "$tmp_dir/cve.err" || rm -f "$tmp_dir/cve.json"
fi

check_args=(--old "$tmp_dir/config-$from.json" --new "$tmp_dir/config-$to.json" --config "$tmp_dir/config.json"
    --changelog "$tmp_dir/changelog.json" --dependencies "$tmp_dir/dependencies.json" --info "$tmp_dir/info.json"
    --repo "$root_folder" --plugin "$connector_plugin" --connector-class "$connector_class"
    --from "$from" --to "$to" --name "$connector")
[[ -n "$cp_version" ]] && check_args+=(--cp-version "$cp_version")
[[ -n "$with_cve" ]] && check_args+=(--cve "$tmp_dir/cve.json")

set +e
if [[ -n "$output_json" ]]
then
    python3 -I "$root_folder/tools/connector-upgrade-check/upgrade_check.py" "${check_args[@]}" --json >&3
else
    python3 -I "$root_folder/tools/connector-upgrade-check/upgrade_check.py" "${check_args[@]}"
fi
ret=$?
set -e
if [[ $ret -eq 1 ]] && [[ -z "$output_json" ]]
then
    log "🎓 try it: playground run -f <example of $connector_plugin> --connector-tag $to, or playground repro bisect --from $from --to $to on a repro model"
fi
exit $ret
