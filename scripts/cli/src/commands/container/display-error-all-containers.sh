set +e
containers=$(docker ps --format="{{.Names}}")
if [ -z "$containers" ]; then
    logwarn "💤 no running containers"
else
    log "####################################################"
    log "🐳 docker ps"
    docker ps
    log "####################################################"

    while IFS= read -r container
    do
        log "####################################################"
        log "$container logs"
        docker container logs "$container" 2>&1 | grep -E "ERROR|FATAL"
        log "####################################################"
    done <<< "$containers"
fi