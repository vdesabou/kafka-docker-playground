containers="${args[--container]}"

get_environment_used

# Convert space-separated string to array
IFS=' ' read -ra container_array <<< "$containers"

for container in "${container_array[@]}"
do
    resolved_container=$(resolve_container_name_for_environment "$container")
    if [[ "$environment" == "cfk" ]]
    then
        log "🔫 Deleting pod ${resolved_container}"
        kubectl -n confluent delete pod "${resolved_container}" --grace-period=0 --force
    else
        log "🔫 Killing docker container ${container}"
        docker kill ${resolved_container}
    fi
done