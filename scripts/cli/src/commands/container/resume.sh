container="${args[--container]}"

log "Resuming docker container ${container}"
docker unpause ${container}