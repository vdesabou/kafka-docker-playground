user="${args[--user]}"
client_id="${args[--client-id]}"
connector="${args[--connector]}"
all_users="${args[--all-users]}"
all_client_ids="${args[--all-client-ids]}"
verbose="${args[--verbose]}"

configs=()
[[ -n "${args[--producer-byte-rate]}" ]] && configs+=("producer_byte_rate=${args[--producer-byte-rate]}")
[[ -n "${args[--consumer-byte-rate]}" ]] && configs+=("consumer_byte_rate=${args[--consumer-byte-rate]}")
[[ -n "${args[--request-percentage]}" ]] && configs+=("request_percentage=${args[--request-percentage]}")
[[ -n "${args[--controller-mutation-rate]}" ]] && configs+=("controller_mutation_rate=${args[--controller-mutation-rate]}")
if [[ -n "${args[--request-percentage]}" ]] && ! [[ "${args[--request-percentage]}" =~ ^[0-9]+(\.[0-9]+)?$ ]]
then
    logerror "❌ --request-percentage must be a number, e.g. 50 or 0.2"
    exit 1
fi
if [ ${#configs[@]} -eq 0 ]
then
    logerror "❌ set at least one of --producer-byte-rate, --consumer-byte-rate, --request-percentage, --controller-mutation-rate"
    exit 1
fi
add_config=$(IFS=,; echo "${configs[*]}")

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
    log "🚦 Setting $add_config on ${quota_entity_labels[$i]}"
    run_quota_kafka_configs "${quota_entities[$i]}" --alter --add-config "$add_config" || exit 1
    run_quota_kafka_configs "${quota_entities[$i]}" --describe || exit 1
done
if [[ -n "$connector" ]]
then
    log "🎓 the quota follows the client ids of the tasks that exist now: run it again if tasks.max changes"
fi
