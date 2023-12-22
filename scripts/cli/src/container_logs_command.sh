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
    editor=$(playground config get editor)
    if [ "$editor" != "" ]
    then
        log "📖 Opening ${filename} using configured editor $editor"
        $editor ${filename}
    else
        if [[ $(type code 2>&1) =~ "not found" ]]
        then
            logerror "Could not determine an editor to use as default code is not found - you can change editor by using playground config editor <editor>"
            exit 1
        else
            log "📖 Opening ${filename} with code (default) - you can change editor by using playground config editor <editor>"
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