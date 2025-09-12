containers="${args[--container]}"

# Convert space-separated string to array
IFS=' ' read -ra container_array <<< "$containers"

for container in "${container_array[@]}"
do
	log "⏯️ Resuming docker container ${container}"
	docker unpause ${container}
done