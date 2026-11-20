verbose="${args[--verbose]}"
json="${args[--json]}"
fail_on_error="${args[--fail-on-error]}"

# --json: only the JSON goes to stdout (fd 3)
if [[ -n "$json" ]]
then
    exec 3>&1 1>&2
fi

if ! command -v python3 > /dev/null 2>&1
then
    logerror "❌ python3 is required to show the flow"
    exit 1
fi

connector_type=$(playground state get run.connector_type)
environment_used=$(playground state get run.environment)

connectors=$(playground get-connector-list)
if [ -z "$connectors" ]
then
    log "💤 No $connector_type connector is running !"
    exit 1
fi
items=($connectors)
log "🗺️ flow of the ${#items[@]} $connector_type connectors"

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
trap 'rm -rf $tmp_dir' EXIT

set +e
# state of every connector
statuses=$(PG_SKIP_ERROR_RECOMMENDATIONS=1 PG_SKIP_DIAGNOSE_HINT=1 playground connector status --json 2> /dev/null)
echo "$statuses" | jq -e 'type == "array"' > /dev/null 2>&1 || statuses='[]'
# lag of the sinks (one call, every connector: sources come back with an error, left out below)
lags=$(playground connector show-lag --json 2> /dev/null)
echo "$lags" | jq -e 'type == "array"' > /dev/null 2>&1 || lags='[]'
# topics written / read, tracked by the worker (self-managed, KIP-558)
active='{}'
if [ "$connector_type" != "$CONNECTOR_TYPE_FULLY_MANAGED" ] && [ "$connector_type" != "$CONNECTOR_TYPE_CUSTOM" ] && [[ "$environment_used" != cfk* ]]
then
    active=$(playground connector topics --json 2> /dev/null)
    echo "$active" | jq -e 'type == "object"' > /dev/null 2>&1 || active='{}'
fi

echo '[]' > $tmp_dir/connectors.json
for c in "${items[@]}"
do
    config='{}'
    if get_connector_config_json "$c" > /dev/null 2>&1
    then
        config="$curl_output"
    fi
    jq --arg name "$c" --argjson config "$config" --argjson statuses "$statuses" --argjson lags "$lags" --argjson active "$active" '
        . + [{name: $name, config: $config,
              status: ($statuses | map(select(.name == $name)) | first // null),
              lag: ($lags | map(select(.connector == $name)) | first // null),
              active_topics: ($active[$name] // [])}]' $tmp_dir/connectors.json > $tmp_dir/c.json && mv $tmp_dir/c.json $tmp_dir/connectors.json
done
jq -n --arg type "$connector_type" --slurpfile c $tmp_dir/connectors.json '{type: $type, connectors: $c[0], counts: {}}' > $tmp_dir/data.json

# records of each topic
echo '{}' > $tmp_dir/counts.json
while IFS= read -r topic
do
    [ -z "$topic" ] && continue
    n=$(playground --output-level WARN topic get-number-records --topic "$topic" 2> /dev/null | tail -1 | tr -d '[:space:]')
    if [[ "$n" =~ ^[0-9]+$ ]]
    then
        jq --arg t "$topic" --argjson n "$n" '. + {($t): $n}' $tmp_dir/counts.json > $tmp_dir/n.json && mv $tmp_dir/n.json $tmp_dir/counts.json
    fi
done < <(python3 -I "$root_folder/tools/pipeline-builder/flow.py" topics < $tmp_dir/data.json)
jq --slurpfile n $tmp_dir/counts.json '.counts = $n[0]' $tmp_dir/data.json > $tmp_dir/d.json && mv $tmp_dir/d.json $tmp_dir/data.json

if [[ -n "$verbose" ]]
then
    log "🐞 data used:"
    jq . $tmp_dir/data.json
fi

if [[ -n "$json" ]]
then
    python3 -I "$root_folder/tools/pipeline-builder/flow.py" render --json < $tmp_dir/data.json >&3
    rc=$?
else
    python3 -I "$root_folder/tools/pipeline-builder/flow.py" render < $tmp_dir/data.json
    rc=$?
fi
set -e

if [ $rc -ne 0 ]
then
    logwarn "🛑 a connector or one of its tasks is not RUNNING: playground connector status, playground connector diagnose"
    if [[ -n "$fail_on_error" ]]
    then
        exit 1
    fi
fi
