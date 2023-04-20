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
    if [ ! -z $EDITOR ]
    then
      log "📖 Opening ${filename} using EDITOR environment variable"
      $EDITOR ${filename}
    else
      if [[ $(type code 2>&1) =~ "not found" ]]
      then
        logerror "Could not determine an editor to use, you can set EDITOR environment variable with your preferred choice"
        exit 1
      else
        log "📖 Opening ${filename} with code (you can change editor by setting EDITOR environment variable)"
        code ${filename}
      fi
    fi
  else
    logerror "Failed to get logs using container logs $container"
  fi
elif [[ -n "$log" ]]
then
  wait_for_log "$log" "$container" "$max_wait"
else 
  docker container logs --tail=200 -f "$container"
fi