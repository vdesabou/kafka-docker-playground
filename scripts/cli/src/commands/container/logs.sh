containers="${args[--container]}"
open="${args[--open]}"
log="${args[--wait-for-log]}"
grep="${args[--grep]}"
max_wait="${args[--max-wait]}"

get_environment_used

# Convert space-separated string to array
IFS=' ' read -ra container_array <<< "$containers"

for container in "${container_array[@]}"
do
	resolved_container=$(resolve_container_name_for_environment "$container")
	if [[ "$environment" == "cfk" ]]
	then
		if [[ -n "$open" ]]
		then
			filename="/tmp/${container}-$(date '+%Y-%m-%d-%H-%M-%S').log"
			kubectl -n confluent logs "$resolved_container" > "$filename" 2>&1
			if [ $? -eq 0 ]
			then
				playground open --file "${filename}"
			else
				logerror "❌ failed to get logs using kubectl logs $resolved_container"
			fi
		elif [[ -n "$log" ]]
		then
			cur_wait=0
			log "⌛ Waiting up to $max_wait seconds for message $log to be present in $resolved_container pod logs..."
			while true
			do
				kubectl -n confluent logs "$resolved_container" > /tmp/out.txt 2>&1
				if grep "$log" /tmp/out.txt > /dev/null
				then
					grep "$log" /tmp/out.txt
					log "The log is there !"
					break
				fi
				sleep 10
				cur_wait=$(( cur_wait+10 ))
				if [[ "$cur_wait" -gt "$max_wait" ]]
				then
					logerror "The logs in $resolved_container pod do not show '$log' after $max_wait seconds."
					exit 1
				fi
			done
		elif [[ -n "$grep" ]]
		then
			if [ ${#container_array[@]} -gt 1 ]; then
				kubectl -n confluent logs --tail=200 -f "$resolved_container" 2>&1 | grep --line-buffered "$grep" | sed "s/^/[$container] /" &
			else
				kubectl -n confluent logs --tail=200 -f "$resolved_container" 2>&1 | grep --line-buffered "$grep"
			fi
		else
			if [ ${#container_array[@]} -gt 1 ]; then
				kubectl -n confluent logs --tail=200 -f "$resolved_container" 2>&1 | sed "s/^/[$container] /" &
			else
				kubectl -n confluent logs --tail=200 -f "$resolved_container"
			fi
		fi
		continue
	fi
	if [[ -n "$open" ]]
	then
		filename="/tmp/${container}-$(date '+%Y-%m-%d-%H-%M-%S').log"
		docker container logs "$resolved_container" > "$filename" 2>&1
		if [ $? -eq 0 ]
		then
			playground open --file "${filename}"
		else
			logerror "❌ failed to get logs using container logs $container"
		fi
	elif [[ -n "$log" ]]
	then
		wait_for_log "$log" "$resolved_container" "$max_wait"
	elif [[ -n "$grep" ]]
	then
		if [ ${#container_array[@]} -gt 1 ]; then
			# For multiple containers, filter and prefix each stream in parallel.
			docker container logs --tail=200 -f "$resolved_container" 2>&1 | grep --line-buffered "$grep" | sed "s/^/[$container] /" &
		else
			docker container logs --tail=200 -f "$resolved_container" 2>&1 | grep --line-buffered "$grep"
		fi
	else 
		# For multiple containers, run docker logs in parallel in background
		if [ ${#container_array[@]} -gt 1 ]; then
			# Add container prefix to distinguish logs from different containers
			docker container logs --tail=200 -f "$resolved_container" 2>&1 | sed "s/^/[$container] /" &
		else
			# For single container, use normal behavior without prefix
			docker container logs --tail=200 -f "$resolved_container"
		fi
	fi
done

# If multiple containers, wait for all background processes
if [ ${#container_array[@]} -gt 1 ]; then
	wait
fi