container="${args[--container]}"

log "Pausing docker container ${container}"
docker pause ${container}