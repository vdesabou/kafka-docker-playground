containers="${args[--container]}"
open="${args[--open]}"
log="${args[--wait-for-log]}"
grep="${args[--grep]}"
max_wait="${args[--max-wait]}"

# Convert space-separated string to array
IFS=' ' read -ra container_array <<< "$containers"

for container in "${container_array[@]}"
do
	if [[ -n "$open" ]]
	then
		filename="/tmp/${container}-$(date '+%Y-%m-%d-%H-%M-%S').log"
		docker container logs "$container" > "$filename" 2>&1
		if [ $? -eq 0 ]
		then
			playground open --file "${filename}"
		else
			logerror "❌ failed to get logs using container logs $container"
		fi
	elif [[ -n "$log" ]]
	then
		wait_for_log "$log" "$container" "$max_wait"
	elif [[ -n "$grep" ]]
	then
		if [ ${#container_array[@]} -gt 1 ]; then
			# For multiple containers, filter and prefix each stream in parallel.
			docker container logs --tail=200 -f "$container" 2>&1 | grep --line-buffered "$grep" | sed "s/^/[$container] /" &
		else
			docker container logs --tail=200 -f "$container" 2>&1 | grep --line-buffered "$grep"
		fi
	else 
		# For multiple containers, run docker logs in parallel in background
		if [ ${#container_array[@]} -gt 1 ]; then
			# Add container prefix to distinguish logs from different containers
			docker container logs --tail=200 -f "$container" 2>&1 | sed "s/^/[$container] /" &
		else
			# For single container, use normal behavior without prefix
			docker container logs --tail=200 -f "$container"
		fi
	fi
done

# If multiple containers, wait for all background processes
if [ ${#container_array[@]} -gt 1 ]; then
	wait
fi