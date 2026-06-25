containers="${args[--container]}"
command="${args[--command]}"
root="${args[--root]}"
shell="${args[--shell]}"

get_environment_used

# Convert space-separated string to array
IFS=' ' read -ra container_array <<< "$containers"

for container in "${container_array[@]}"
do
	resolved_container=$(resolve_container_name_for_environment "$container")
	if [[ "$environment" == "cfk" ]]
	then
		if [[ -n "$root" ]]
		then
			logwarn "👑 --root flag is ignored in cfk mode"
		fi
		log "🪄 Executing command in pod $resolved_container with $shell"
		kubectl -n confluent exec "$resolved_container" -- "$shell" -c "$command"
	elif [[ -n "$root" ]]
	then
	log "🪄👑 Executing command as root in container $container with $shell"
	docker exec --privileged --user root $resolved_container $shell -c "$command"
	else
	log "🪄 Executing command in container $container with $shell"
	docker exec $resolved_container $shell -c "$command"
	fi
done