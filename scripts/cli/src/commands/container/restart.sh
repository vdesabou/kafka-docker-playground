container="${args[--container]}"

log "Restarting docker container ${container}"
docker restart ${container}

if [[ ${container} == connect* ]]
then
    wait_container_ready
fi