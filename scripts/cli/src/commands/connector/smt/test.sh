connector="${args[--connector]}"
config_arg="${args[--config]}"
record_arg="${args[--record]}"
from_topic="${args[--from-topic]}"
offset="${args[--offset]}"
partition="${args[--partition]}"
type="${args[--type]}"
json="${args[--json]}"
no_open="${args[--no-open]}"
output_dir="${args[--output-dir]:-/tmp/playground-smt-test}"
verbose="${args[--verbose]}"
eval "cp_versions=(${args[--cp-version]:-})"
eval "smt_plugins=(${args[--smt-plugin]:-})"
eval "smt_jars=(${args[--smt-jar]:-})"

# --json: the json document is the only thing on stdout (fd 3), the logs go to stderr and the harness output is dropped
# the harness writes to fd 4, a copy of the descriptor: '> /dev/stdout' would reopen the file with O_TRUNC on linux
# and wipe what was printed before when stdout is a file ('smt test ... > out.log', the deep dive lab)
if [[ -n "$json" ]]
then
    exec 3>&1 1>&2
    exec 4>/dev/null
else
    exec 4>&1
fi

# docker desktop does not share every temporary folder: work under $HOME
mkdir -p "$SMT_TESTER_CACHE"
work=$(mktemp -d "$SMT_TESTER_CACHE/run-XXXXXX")
trap 'rm -rf "$work"' EXIT

connect_running=0
smt_connect_container="connect"
if is_mdc_environment
then
    get_connect_container
    smt_connect_container="$connect_container"
fi
if docker inspect -f '{{.State.Running}}' "$smt_connect_container" 2> /dev/null | grep -q true
then
    connect_running=1
fi
if [ $connect_running -eq 0 ] && [ ${#cp_versions[@]} -eq 0 ]
then
    logerror "❌ the connect container is not running: start an example, or use --cp-version to test in throwaway cp-server-connect containers"
    exit 1
fi

# ---- connector config: transforms, predicates, converters
if [[ -n "$connector" ]]
then
    connector_type=$(playground state get run.connector_type)
    if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
    then
        logerror "❌ the transforms of a $connector_type connector run in Confluent Cloud: give its config with --config @file (the result on a self managed worker is indicative)"
        exit 1
    fi
    get_connect_url_and_security
    handle_onprem_connect_rest_api "curl -s $security \"$connect_url/connectors/$connector/config\""
    echo "$curl_output" > "$work/config.json"
    if [[ ! -n "$type" ]]
    then
        handle_onprem_connect_rest_api "curl -s $security \"$connect_url/connectors/$connector/status\""
        type=$(echo "$curl_output" | jq -r '.type // "sink"')
    fi
elif [[ -n "$config_arg" ]]
then
    if [[ "$config_arg" == @* ]]
    then
        cp "${config_arg#@}" "$work/config.json" || exit 1
    else
        echo "$config_arg" > "$work/config.json"
    fi
elif [ ! -t 0 ]
then
    cat > "$work/config.json"
else
    logerror "❌ no transforms: use --connector, --config, or give a connector config on stdin"
    exit 1
fi
if ! jq -e 'type == "object"' "$work/config.json" > /dev/null 2>&1
then
    logerror "❌ the connector config is not a json object"
    exit 1
fi
if [ "$(jq -r '.transforms // empty' "$work/config.json")" == "" ]
then
    logwarn "⚠️ the connector config has no transforms: the record goes through unchanged"
fi
type="${type:-sink}"

# ---- record
if [[ -n "$from_topic" ]]
then
    jq -n --arg t "$from_topic" --argjson p "$partition" --argjson o "$offset" '{fromTopic: $t, partition: $p, offset: $o}' > "$work/record.json"
elif [[ -n "$record_arg" ]]
then
    if [[ "$record_arg" == @* ]]
    then
        cp "${record_arg#@}" "$work/record.json" || exit 1
    else
        echo "$record_arg" > "$work/record.json"
    fi
    if ! jq -e 'type == "object"' "$work/record.json" > /dev/null 2>&1
    then
        logerror "❌ --record is not a json object"
        exit 1
    fi
else
    # the first topic of a sink connector, if any
    default_topic=$(jq -r '(.topics // "test-topic") | split(",")[0]' "$work/config.json")
    jq -n --arg t "$default_topic" '{topic: $t, key: "k1", value: {id: 1, name: "foo"}}' > "$work/record.json"
    log "🧾 no --record: using a schemaless record $(jq -c . "$work/record.json")"
fi

# ---- extra plugins for the test only
plugin_dirs=()
hub_image="confluentinc/cp-server-connect:${cp_versions[0]:-8.3.2}"
if [ $connect_running -eq 1 ]
then
    hub_image=$(docker inspect -f '{{.Config.Image}}' "$smt_connect_container")
    if is_ansible_host "$smt_connect_container"
    then
        # environment/ansible: the worker is not a cp image, confluent-hub runs in the cp image of the same version
        hub_image="confluentinc/cp-server-connect:$(get_container_cp_tag "$smt_connect_container")"
    fi
fi
for spec in "${smt_plugins[@]}"
do
    log "🧩 installing $spec for the test (the worker is not changed)"
    dir=$(smt_tester_hub_plugin "$spec" "$hub_image") || exit 1
    plugin_dirs+=("$dir")
done
# all the jars in one plugin, like the lib folder of a plugin: the transform and its dependencies
if [ ${#smt_jars[@]} -gt 0 ]
then
    dir="$work/plugins/custom-smt"
    mkdir -p "$dir"
    cp "${smt_jars[@]}" "$dir/"
    plugin_dirs+=("$dir")
fi

harness_args=(--type "$type")

# the files keep their mode and owner when copied into a container: a --config @file or --record @file made by
# mktemp (0600) could not be read by the user of the image (AccessDeniedException on /tmp/smt-tester/config.json)
chmod -R a+rX "$work"
# with --cp-version, the throwaway container writes result-<version>.json in it as appuser (uid 1000): on Linux, where
# bind mounts keep the owner (uid 1001 on GitHub runners), the folder must be writable or every version gives "no result"
chmod a+w "$work"

# ---- run in the connect worker
function run_in_worker () {
    local jar_dir java_version release classes classpath worker_config plugin_path container_plugins=""
    jar_dir=$(smt_tester_jars_from_container "$smt_connect_container")
    java_version=$(playground --output-level ERROR container exec --container "$smt_connect_container" --command "java -version 2>&1 | head -1" 2> /dev/null)
    release=$(smt_tester_java_release "$java_version")
    classes=$(smt_tester_classes "$jar_dir" "$release") || return 1
    # the classpath and the properties file of the running worker jvm
    classpath=$(playground --output-level ERROR container exec --container "$smt_connect_container" --command "tr '\\0' '\\n' < /proc/$(container_java_pid "$smt_connect_container" || echo 1)/cmdline | grep -A1 '^-cp' | tail -1" 2> /dev/null)
    worker_config=$(playground --output-level ERROR container exec --container "$smt_connect_container" --command "tr '\\0' '\\n' < /proc/$(container_java_pid "$smt_connect_container" || echo 1)/cmdline | tail -1" 2> /dev/null)
    plugin_path=$(playground --output-level ERROR container exec --container "$smt_connect_container" --command "grep -E '^plugin.path=' '$worker_config' | cut -d= -f2-" 2> /dev/null)
    playground --output-level ERROR container exec --container "$smt_connect_container" --command "rm -rf /tmp/smt-tester && mkdir -p /tmp/smt-tester/plugins" > /dev/null 2>&1
    playground --output-level ERROR container cp --source "$classes/SmtTester.class" --destination "$smt_connect_container":/tmp/smt-tester/SmtTester.class > /dev/null 2>&1
    playground --output-level ERROR container cp --source "$work/config.json" --destination "$smt_connect_container":/tmp/smt-tester/config.json > /dev/null 2>&1
    playground --output-level ERROR container cp --source "$work/record.json" --destination "$smt_connect_container":/tmp/smt-tester/record.json > /dev/null 2>&1
    local dir
    for dir in "${plugin_dirs[@]}"
    do
        playground --output-level ERROR container cp --source "$dir" --destination "$smt_connect_container:/tmp/smt-tester/plugins/$(basename "$dir")" > /dev/null 2>&1
        container_plugins="$container_plugins,/tmp/smt-tester/plugins/$(basename "$dir")"
    done
    # the test plugins are given apart: their classes win over the worker plugins
    local priority="${container_plugins#,}"
    local stderr_target="/dev/null"
    [[ -n "$verbose" ]] && stderr_target="/dev/stderr"
    playground --output-level ERROR container exec --container "$smt_connect_container" --command "SMT_TESTER_VERBOSE=${verbose} java -cp '/tmp/smt-tester:$classpath' SmtTester --config /tmp/smt-tester/config.json --record /tmp/smt-tester/record.json --worker-config '$worker_config' --plugin-path '$plugin_path' --priority-plugin-path '$priority' --label 'worker $(docker inspect -f '{{.Config.Image}}' $smt_connect_container)' --json-out /tmp/smt-tester/result.json ${harness_args[*]} 2> $stderr_target" >&4
    local ret=$?
    playground --output-level ERROR container cp --source "$smt_connect_container":/tmp/smt-tester/result.json --destination "$work/result-worker.json" > /dev/null 2>&1
    return $ret
}

# ---- run in a throwaway cp-server-connect container of another version
function run_in_image () {
    local version="$1" image="confluentinc/cp-server-connect:$1" jar_dir java_version release classes network="" mounts=() plugin_path="" dir
    log "🔢 CP $version: throwaway $image"
    jar_dir=$(smt_tester_jars_from_image "$image") || return 1
    java_version=$(docker run --rm --entrypoint java "$image" -version 2>&1 | head -1)
    release=$(smt_tester_java_release "$java_version")
    classes=$(smt_tester_classes "$jar_dir" "$release") || return 1
    if [ $connect_running -eq 1 ]
    then
        # same network and worker settings as the running example, for --from-topic and schema registry
        network=$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$smt_connect_container" | awk '{print $1}')
        worker_config=$(playground --output-level ERROR container exec --container "$smt_connect_container" --command "tr '\\0' '\\n' < /proc/$(container_java_pid "$smt_connect_container" || echo 1)/cmdline | tail -1" 2> /dev/null)
        playground --output-level ERROR container cp --source "$smt_connect_container:$worker_config" --destination "$work/worker.properties" > /dev/null 2>&1
    fi
    [ -f "$work/worker.properties" ] || echo "bootstrap.servers=broker:9092" > "$work/worker.properties"
    for dir in "${plugin_dirs[@]}"
    do
        mounts+=(-v "$dir:/smt-plugins/$(basename "$dir")")
        plugin_path="$plugin_path,/smt-plugins/$(basename "$dir")"
    done
    plugin_path="${plugin_path#,}"
    # fd 5: stderr with --verbose, /dev/null otherwise (a copy of the descriptor, never the /dev/stderr path)
    if [[ -n "$verbose" ]]
    then
        exec 5>&2
    else
        exec 5>/dev/null
    fi
    docker run --rm ${network:+--network "$network"} -e "SMT_TESTER_VERBOSE=${verbose}" -v "$classes:/smt-tester" -v "$work:/smt-work" "${mounts[@]}" --entrypoint java "$image" \
        -cp "/smt-tester:/etc/kafka-connect/jars/*:/usr/share/java/confluent-security/connect/*:/usr/share/java/kafka/*:/usr/share/java/confluent-common/*:/usr/share/java/kafka-serde-tools/*:/usr/share/java/monitoring-interceptors/*" \
        SmtTester --config /smt-work/config.json --record /smt-work/record.json --worker-config /smt-work/worker.properties --plugin-path "$plugin_path" --priority-plugin-path "$plugin_path" --label "CP $version" --json-out "/smt-work/result-$version.json" "${harness_args[@]}" 2>&5 >&4
}

# html report of the run(s), opened in the browser in an interactive terminal
function smt_report () {
    local results=() file report_dir="$output_dir" report title="SMT test"
    for file in "$@"
    do
        [ -f "$file" ] && results+=(--result "$file")
    done
    [ ${#results[@]} -eq 0 ] && return
    mkdir -p "$report_dir"
    [[ -n "$connector" ]] && title="SMT test of $connector"
    report="$report_dir/smt-test-${connector:-chain}-$(date +%Y%m%d-%H%M%S).html"
    if python3 -I "$root_folder/tools/smt-tester/smt_report.py" "${results[@]}" --output "$report" --title "$title" > /dev/null
    then
        [[ -n "$json" ]] && return
        log "📊 report: $report"
        if [[ -t 1 ]] && [ -z "$GITHUB_RUN_NUMBER" ] && [[ ! -n "$no_open" ]]
        then
            if command -v open > /dev/null 2>&1
            then
                open "$report"
            elif command -v xdg-open > /dev/null 2>&1
            then
                xdg-open "$report" > /dev/null 2>&1 || true
            fi
        fi
    else
        logwarn "⚠️ the html report could not be generated"
    fi
}

# --json: one result as a json object, or an array of them with several --cp-version (a version without a
# result file is {"label": "CP <version>", "error": "no result"})
function print_json_results () {
    local file label
    {
        for file in "$@"
        do
            if [ -f "$file" ]
            then
                cat "$file"
            else
                label=$(basename "$file" .json)
                label="${label#result-}"
                [ "$label" == "worker" ] || label="CP $label"
                jq -n --arg l "$label" '{label: $l, error: "no result"}'
            fi
        done
    } | if [ $# -gt 1 ]; then jq -s .; else jq .; fi >&3
}

ret=0
if [ ${#cp_versions[@]} -eq 0 ]
then
    run_in_worker || ret=$?
    [ -f "$work/result-worker.json" ] || ret=1
    smt_report "$work/result-worker.json"
    [[ -n "$json" ]] && print_json_results "$work/result-worker.json"
    exit $ret
fi

for version in "${cp_versions[@]}"
do
    echo ""
    run_in_image "$version" || ret=1
done

# the final result of each version, to see at a glance whether they differ (values compared as json with sorted
# keys: the key order of a schemaless map changed between kafka versions, without changing the record)
if [ ${#cp_versions[@]} -gt 1 ] && [[ ! -n "$json" ]]
then
    echo ""
    log "⚖️ final result per CP version"
    for version in "${cp_versions[@]}"
    do
        result_file="$work/result-$version.json"
        if [ -f "$result_file" ]
        then
            jq -r --arg v "$version" '
                ([.steps[] | select(.error)] | first) as $err
                | ([.steps[] | select(.dropped)] | first) as $drop
                | ([.steps[] | select(.record)] | last | .record) as $r
                | "   CP \($v) (Kafka \(.kafka_version)): " +
                  (if $err then "❌ step \($err.index) \($err.alias): \($err.error | .[0:160])"
                   elif $drop then "🗑️ dropped by step \($drop.index) \($drop.alias)"
                   else "topic \($r.topic), key \($r.key), value \($r.value)" end)' "$result_file"
        else
            echo "   CP $version: no result"
        fi
    done
    missing_results=0
    for version in "${cp_versions[@]}"
    do
        [ -f "$work/result-$version.json" ] || missing_results=1
    done
    if [ $missing_results -eq 1 ]
    then
        # a version without a result cannot be compared: never report it as the same result
        logwarn "⚠️ the CP versions give different results (at least one version has no result)"
    elif [ "$(for v in "${cp_versions[@]}"; do [ -f "$work/result-$v.json" ] && jq -S -c '[.steps[] | {alias, error: (.error // null | if . then (. | split(":")[0]) else null end), dropped, record: (.record // null | if . then {topic, key: (.key | try fromjson catch .), value: (.value | try fromjson catch .), headers} else null end)}]' "$work/result-$v.json"; done | sort -u | wc -l | tr -d ' ')" -le 1 ]
    then
        log "✅ same result with all the CP versions"
    else
        logwarn "⚠️ the CP versions give different results"
    fi
fi
report_files=()
for version in "${cp_versions[@]}"
do
    report_files+=("$work/result-$version.json")
    [ -f "$work/result-$version.json" ] || ret=1
done
smt_report "${report_files[@]}"
[[ -n "$json" ]] && print_json_results "${report_files[@]}"
exit $ret
