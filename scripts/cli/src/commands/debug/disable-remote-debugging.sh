containers="${args[--container]}"

# Convert space-separated string to array
IFS=' ' read -ra container_array <<< "$containers"

for container in "${container_array[@]}"
do
    log "🛑 disable remote debugging for $container"
    if [[ "$container" == connect* ]]
    then
        # connect has KAFKA_DEBUG in the base compose: restoring the original values would keep JDWP on, and
        # kafka-run-class enables it for any non-empty value
        playground container set-environment-variables --container "${container}" --env "KAFKA_DEBUG: ''"
    else
        playground container set-environment-variables --container "${container}" --restore-original-values
    fi
done