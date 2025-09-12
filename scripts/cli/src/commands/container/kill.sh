containers="${args[--container]}"

# Convert space-separated string to array
IFS=' ' read -ra container_array <<< "$containers"

for container in "${container_array[@]}"
do
    log "🔫 Killing docker container ${container}"
    docker kill ${container}
done