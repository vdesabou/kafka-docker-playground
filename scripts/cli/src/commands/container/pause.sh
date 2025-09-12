containers="${args[--container]}"

# Convert space-separated string to array
IFS=' ' read -ra container_array <<< "$containers"

for container in "${container_array[@]}"
do
	log "⏸️ Pausing docker container ${container}"
	docker pause ${container}
done