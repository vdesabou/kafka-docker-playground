get_environment_used

set +e
if [[ "$environment" == "cfk" ]]
then
    containers=$(kubectl -n confluent get pods -o name 2>/dev/null | sed 's#pod/##')
else
    containers=$(docker ps --format="{{.Names}}")
fi
if [ -z "$containers" ]; then
    logwarn "💤 no running containers"
else
    log "####################################################"
    if [[ "$environment" == "cfk" ]]
    then
        log "☸️ kubectl get pods"
        kubectl -n confluent get pods
    else
        log "🐳 docker ps"
        docker ps
    fi
    log "####################################################"

    while IFS= read -r container
    do
        log "####################################################"
        log "$container logs"
        if [[ "$environment" == "cfk" ]]
        then
            kubectl -n confluent logs "$container" 2>&1 | grep -E "ERROR|FATAL"
        else
            docker container logs "$container" 2>&1 | grep -E "ERROR|FATAL"
        fi
        log "####################################################"
    done <<< "$containers"
fi