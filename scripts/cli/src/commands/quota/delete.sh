user="${args[--user]}"
client_id="${args[--client-id]}"
connector="${args[--connector]}"
all_users="${args[--all-users]}"
all_client_ids="${args[--all-client-ids]}"
verbose="${args[--verbose]}"

keys=()
[[ -n "${args[--producer-byte-rate]}" ]] && keys+=("producer_byte_rate")
[[ -n "${args[--consumer-byte-rate]}" ]] && keys+=("consumer_byte_rate")
[[ -n "${args[--request-percentage]}" ]] && keys+=("request_percentage")
[[ -n "${args[--controller-mutation-rate]}" ]] && keys+=("controller_mutation_rate")

rc=0
get_quota_entities "$user" "$client_id" "$connector" "$all_users" "$all_client_ids" || rc=$?
if [ $rc -eq 2 ]
then
    logerror "❌ set the entity of the quota: --user, --client-id, --connector, --all-users or --all-client-ids"
    exit 1
elif [ $rc -ne 0 ]
then
    exit 1
fi

for i in "${!quota_entities[@]}"
do
    # kafka-configs refuses to delete a quota that is not set (Invalid config(s)), and then deletes none: only delete
    # the ones the entity has, read from "Quota configs for ... are consumer_byte_rate=1024.0, request_percentage=50.0"
    current=$(run_quota_kafka_configs "${quota_entities[$i]}" --describe) || exit 1
    current_keys=$(echo "$current" | sed -n 's/.* are //p' | tr ',' '\n' | sed -n 's/^ *\([a-z_]*\)=.*/\1/p')
    to_delete=()
    if [ ${#keys[@]} -eq 0 ]
    then
        while IFS= read -r key
        do
            [[ -n "$key" ]] && to_delete+=("$key")
        done <<< "$current_keys"
    else
        for key in "${keys[@]}"
        do
            if echo "$current_keys" | grep -qx "$key"
            then
                to_delete+=("$key")
            else
                logwarn "🤷 $key is not set on ${quota_entity_labels[$i]}"
            fi
        done
    fi
    if [ ${#to_delete[@]} -eq 0 ]
    then
        log "🤷 no quota to remove from ${quota_entity_labels[$i]}"
        continue
    fi
    delete_config=$(IFS=,; echo "${to_delete[*]}")
    log "🗑️ Removing $delete_config from ${quota_entity_labels[$i]}"
    run_quota_kafka_configs "${quota_entities[$i]}" --alter --delete-config "$delete_config" || exit 1
done
log "✅ Done"
