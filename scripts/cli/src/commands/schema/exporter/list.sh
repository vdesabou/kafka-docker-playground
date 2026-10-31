# errexit can be left on by a filter or a library function: the checks below handle the failures themselves
set +e
json="${args[--json]}"
verbose="${args[--verbose]}"

get_sr_url_and_security
sr_exporter_check_available || exit 1
sr_request GET "/exporters" || sr_exit_on_error
names=$(echo "$sr_response" | jq -r '.[]')
rows="[]"
for name in $names
do
    status="{}"
    sr_request GET "/exporters/${name}/status" && status="$sr_response"
    info="{}"
    sr_request GET "/exporters/${name}" && info="$sr_response"
    rows=$(echo "$rows" | jq --argjson s "$status" --argjson i "$info" '. + [$i + {status: $s}]')
done
if [[ -n "$json" ]]
then
    echo "$rows" | jq .
    exit 0
fi
if [ -z "$names" ]
then
    log "no exporter on this registry (playground schema exporter create --name <name>)"
    exit 0
fi
echo "$rows" | jq -r '.[] | "🔗 \(.name)  \(.status.state // "?")  subjects \(.subjects | join(","))  → \(.config["schema.registry.url"] // "?")  context \(.contextType)\(if .context then " ." + .context else "" end)  \(.status.objectsExported // 0) exported\(if .status.trace and .status.trace != "" then "\n   🔥 " + (.status.trace | split("\n")[0]) else "" end)"'
