container="${args[--container]}"
editor="${args[--open]}"
log="${args[--wait-for-log]}"
max_wait="${args[--max-wait]}"

if [[ -n "$editor" ]]
then
  filename="/tmp/${container}-`date '+%Y-%m-%d-%H-%M-%S'`.log"
  log "Opening $filename with editor $editor"
  docker container logs "$container" > "$filename" 2>&1
  if [ $? -eq 0 ]
  then
    $editor "$filename"
  fi
elif [[ -n "$log" ]]
then
  wait_for_log "$log" "$container" "$max_wait"
else 
  docker container logs --tail=200 -f "$container"
fi