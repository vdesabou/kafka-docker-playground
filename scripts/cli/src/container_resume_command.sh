container="${args[--container]}"

log "Resuming docker container ${container}"
docker resume ${container}