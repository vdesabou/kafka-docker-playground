broker="${args[--broker]}"
key="${args[--key]}"
value="${args[--value]}"
verbose="${args[--verbose]}"

get_broker_config_ids "$broker" || exit 1

# kafka-configs splits --add-config on commas: a list goes between brackets
if [[ "$value" == *,* ]] && [[ "$value" != \[*\] ]]
then
    value="[$value]"
fi

if [[ -n "$broker" ]]
then
    log "⚙️ Setting $key=${args[--value]} on broker $broker"
    get_args=(--broker "$broker")
else
    log "⚙️ Setting $key=${args[--value]} cluster-wide"
    get_args=()
fi
run_quota_kafka_configs "$(broker_config_entity "$broker")" --alter --add-config "$key=$value" || exit 1
playground broker config get --key "$key" "${get_args[@]}"
