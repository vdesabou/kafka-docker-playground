container="${args[--container]}"

log "Restarting docker container ${container}"
docker restart ${container}