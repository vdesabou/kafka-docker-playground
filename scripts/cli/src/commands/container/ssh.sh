containers="${args[--container]}"
shell="${args[--shell]}"

get_environment_used

# Convert space-separated string to array
IFS=' ' read -ra container_array <<< "$containers"

for container in "${container_array[@]}"
do
	log "🛬 SSH into container: opening shell $shell on container $container"
	resolved_container=$(resolve_container_name_for_environment "$container")
	if [[ "$environment" == "cfk" ]]
	then
		kubectl -n confluent exec -it "$resolved_container" -- "$shell"
	else
	    docker exec -it "$resolved_container" "$shell"
	fi
done