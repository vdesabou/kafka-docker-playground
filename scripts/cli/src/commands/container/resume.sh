containers="${args[--container]}"

get_environment_used

# Convert space-separated string to array
IFS=' ' read -ra container_array <<< "$containers"

for container in "${container_array[@]}"
do
	resolved_container=$(resolve_container_name_for_environment "$container")
	if [[ "$environment" == "cfk" ]]
	then
		logerror "⏯️ resume is not supported in cfk mode for pod $resolved_container"
		exit 1
	fi
	log "⏯️ Resuming docker container ${container}"
	docker unpause ${resolved_container}
done