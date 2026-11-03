user="${args[--user]}"
client_id="${args[--client-id]}"
connector="${args[--connector]}"
all_users="${args[--all-users]}"
all_client_ids="${args[--all-client-ids]}"
json="${args[--json]}"
verbose="${args[--verbose]}"

rc=0
get_quota_entities "$user" "$client_id" "$connector" "$all_users" "$all_client_ids" || rc=$?
if [ $rc -eq 1 ]
then
    exit 1
fi

# "Quota configs for <entity> are <key>=<value>, ..." lines of kafka-configs ($1) as a JSON array: user and client_id
# are the name, "<default>" for the default quota, or null when the quota is not for this type of entity
function quota_lines_to_json () {
    echo -n "$1" | jq -R -s 'split("\n") | map(capture("^Quota configs for (?<entity>.*) are (?<configs>.*)$")? // empty | {
        entity: (.entity | split(", ") | map(
            (capture("^(?<type>[a-z-]+) '\''(?<name>.*)'\''$") // (capture("^the default (?<type>[a-z-]+)$") | .name = "<default>"))
            | { (if .type == "user-principal" then "user" elif .type == "client-id" then "client_id" else .type end): .name }) | add),
        quotas: (.configs | split(", ") | map(split("=") | { (.[0]): (.[1] | tonumber? // .) }) | add)
    } | { user: (.entity.user // null), client_id: (.entity.client_id // null), quotas })'
}

if [ $rc -eq 2 ]
then
    all_output=""
    for entity in $'--entity-type\tusers' $'--entity-type\tclients' $'--entity-type\tusers\t--entity-type\tclients'
    do
        output=$(run_quota_kafka_configs "$entity" --describe) || exit 1
        [[ -n "$output" ]] && all_output+="$output"$'\n'
    done
    if [[ -n "$json" ]]
    then
        quota_lines_to_json "$all_output"
        exit 0
    fi
    log "🔎 Displaying all client quotas"
    if [[ -n "$all_output" ]]
    then
        echo -n "$all_output"
    else
        log "🤷 no client quota, set one with playground quota set"
    fi
    exit 0
fi

all_output=""
for i in "${!quota_entities[@]}"
do
    output=$(run_quota_kafka_configs "${quota_entities[$i]}" --describe) || exit 1
    if [[ -n "$json" ]]
    then
        [[ -n "$output" ]] && all_output+="$output"$'\n'
        continue
    fi
    log "🔎 Displaying client quotas of ${quota_entity_labels[$i]}"
    if [[ -n "$output" ]]
    then
        echo "$output"
    else
        log "🤷 no quota"
    fi
done
if [[ -n "$json" ]]
then
    quota_lines_to_json "$all_output"
fi
