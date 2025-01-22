container="${args[--container]}"
open="${args[--open]}"
log="${args[--wait-for-log]}"
max_wait="${args[--max-wait]}"

if [[ -n "$open" ]]
then
  filename="/tmp/${container}-`date '+%Y-%m-%d-%H-%M-%S'`.log"
  docker container logs "$container" > "$filename" 2>&1
  if [ $? -eq 0 ]
  then
    open_file_with_editor "${filename}"
  else
    logerror "❌ failed to get logs using container logs $container"
  fi
elif [[ -n "$log" ]]
then
  wait_for_log "$log" "$container" "$max_wait"
else 
  docker container logs --tail=200 -f "$container"
fi