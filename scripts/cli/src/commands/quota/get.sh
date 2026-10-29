user="${args[--user]}"
client_id="${args[--client-id]}"
connector="${args[--connector]}"
all_users="${args[--all-users]}"
all_client_ids="${args[--all-client-ids]}"
verbose="${args[--verbose]}"

rc=0
get_quota_entities "$user" "$client_id" "$connector" "$all_users" "$all_client_ids" || rc=$?
if [ $rc -eq 1 ]
then
    exit 1
fi

if [ $rc -eq 2 ]
then
    log "🔎 Displaying all client quotas"
    found=0
    for entity in $'--entity-type\tusers' $'--entity-type\tclients' $'--entity-type\tusers\t--entity-type\tclients'
    do
        output=$(run_quota_kafka_configs "$entity" --describe) || exit 1
        if [[ -n "$output" ]]
        then
            echo "$output"
            found=1
        fi
    done
    if [ $found -eq 0 ]
    then
        log "🤷 no client quota, set one with playground quota set"
    fi
    exit 0
fi

for i in "${!quota_entities[@]}"
do
    log "🔎 Displaying client quotas of ${quota_entity_labels[$i]}"
    output=$(run_quota_kafka_configs "${quota_entities[$i]}" --describe) || exit 1
    if [[ -n "$output" ]]
    then
        echo "$output"
    else
        log "🤷 no quota"
    fi
done
