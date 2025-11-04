containers="${args[--container]}"

# Convert space-separated string to array
IFS=' ' read -ra container_array <<< "$containers"

for container in "${container_array[@]}"
do
    log "🛑 disable remote debugging for $container"
    playground container set-environment-variables --container "${container}" --restore-original-values
done