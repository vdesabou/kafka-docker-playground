containers="${args[--container]}"
shell="${args[--shell]}"

# Convert space-separated string to array
IFS=' ' read -ra container_array <<< "$containers"

for container in "${container_array[@]}"
do
	log "🛬 SSH into container: opening shell $shell on container $container"
    docker exec -it "$container" "$shell"
done