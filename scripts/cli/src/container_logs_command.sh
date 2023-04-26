container="${args[--container]}"
open="${args[--open]}"
log="${args[--wait-for-log]}"
max_wait="${args[--max-wait]}"

if [[ -n "$open" ]]
then
  filename="/tmp/${container}-`date '+%Y-%m-%d-%H-%M-%S'`.log"
  log "Opening $filename with editor $editor"
  docker container logs "$container" > "$filename" 2>&1
  if [ $? -eq 0 ]
  then
    if config_has_key "editor"
    then
      editor=$(config_get "editor")
      log "📖 Opening ${filename} using configured editor $editor"
      $editor $filename
    else
      if [[ $(type code 2>&1) =~ "not found" ]]
      then
        logerror "Could not determine an editor to use as default code is not found - you can change editor by updating config.ini"
        exit 1
      else
        log "📖 Opening ${filename} with code (default) - you can change editor by updating config.ini"
        code $filename
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