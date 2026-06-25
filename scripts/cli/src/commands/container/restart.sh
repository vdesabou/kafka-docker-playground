containers="${args[--container]}"

get_environment_used

# Convert space-separated string to array
IFS=' ' read -ra container_array <<< "$containers"

for container in "${container_array[@]}"
do
	resolved_container=$(resolve_container_name_for_environment "$container")
	if [[ "$environment" == "cfk" ]]
	then
		log "🔁 Restarting pod ${resolved_container}"
		kubectl -n confluent delete pod "${resolved_container}"
	else
		log "🔁 Restarting docker container ${container}"
		docker restart ${resolved_container}

		if [[ ${resolved_container} == connect* ]]
		then
			wait_container_ready
		fi
	fi
done