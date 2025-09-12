containers="${args[--container]}"

# Convert space-separated string to array
IFS=' ' read -ra container_array <<< "$containers"

for container in "${container_array[@]}"
do
	log "🔁 Restarting docker container ${container}"
	docker restart ${container}

	if [[ ${container} == connect* ]]
	then
		wait_container_ready
	fi
done