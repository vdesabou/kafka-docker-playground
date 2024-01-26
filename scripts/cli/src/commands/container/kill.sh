container="${args[--container]}"

log "Killing docker container ${container}"
docker kill ${container}