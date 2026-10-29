broker="${args[--broker]}"
key="${args[--key]}"
verbose="${args[--verbose]}"

get_broker_config_ids "$broker" || exit 1

if [[ -n "$broker" ]]
then
    log "🗑️ Removing $key from broker $broker"
    get_args=(--broker "$broker")
else
    log "🗑️ Removing cluster-wide $key"
    get_args=()
fi
run_quota_kafka_configs "$(broker_config_entity "$broker")" --alter --delete-config "$key" || exit 1
playground broker config get --key "$key" "${get_args[@]}"
