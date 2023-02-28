container="${args[--container]}"
editor="${args[--open]}"

if [[ -n "$editor" ]]
then
  filename="/tmp/${container}-`date '+%Y-%m-%d-%H-%M-%S'`.log"
  log "Opening $filename with editor $editor"
  docker container logs "$container" > "$filename" 2>&1
  if [ $? -eq 0 ]
  then
    $editor "$filename"
  fi
else 
  docker container logs --tail=200 -f "$container"
fi