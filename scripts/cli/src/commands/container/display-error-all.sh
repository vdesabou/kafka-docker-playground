since="${args[--since]}"
include_warnings="${args[--include-warnings]}"
max_findings="${args[--max-findings]}"

get_environment_used

since_opt=()
if [[ -n "$since" ]]
then
    since_opt=(--since "$since")
fi

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
        log "☸️ kubectl get pods -o wide"
        kubectl -n confluent get pods -o wide
        log "####################################################"
        log "☸️ kubectl get events (latest 20)"
        kubectl -n confluent get events --sort-by=.metadata.creationTimestamp | tail -n 20

        while IFS= read -r container
        do
            if [ -z "$container" ]; then
                continue
            fi

            if [[ "$container" == *"schemaregistry"* ]]
            then
                continue
            fi

            ready_status=$(kubectl -n confluent get pod "$container" -o jsonpath='{.status.containerStatuses[*].ready}' 2>/dev/null)
            phase=$(kubectl -n confluent get pod "$container" -o jsonpath='{.status.phase}' 2>/dev/null)

            if [[ "$phase" != "Running" ]] || [[ "$ready_status" == *"false"* ]]
            then
                log "####################################################"
                log "☸️ kubectl describe pod $container"
                kubectl -n confluent describe pod "$container"
                log "####################################################"
                if [[ "$container" == connect* ]]
                then
                    log "☸️ kubectl logs $container --all-containers --tail=150"
                    kubectl -n confluent logs "$container" --all-containers --tail=150
                    log "####################################################"
                    log "☸️ kubectl logs $container --all-containers --previous --tail=150"
                    kubectl -n confluent logs "$container" --all-containers --previous --tail=150
                else
                    log "☸️ kubectl logs $container --all-containers --tail=100"
                    kubectl -n confluent logs "$container" --all-containers --tail=100
                    log "####################################################"
                    log "☸️ kubectl logs $container --all-containers --previous --tail=100"
                    kubectl -n confluent logs "$container" --all-containers --previous --tail=100
                fi
            fi
        done <<< "$containers"

        log "####################################################"
        log "☸️ kubectl get connect,connector"
        kubectl -n confluent get connect,connector 2>/dev/null || true
    else
        log "🐳 docker ps"
        docker ps
    fi
    log "####################################################"

    while IFS= read -r container
    do
        if [ -z "$container" ]; then
            continue
        fi
        log "####################################################"
        log "🔥 ERROR/FATAL digest for $container logs${since:+ since $since}"
        if [[ "$environment" == "cfk" ]]
        then
            kubectl -n confluent logs "$container" --all-containers=true "${since_opt[@]}" 2>&1 | summarize_log_errors "$max_findings" "$include_warnings"
        else
            docker container logs "${since_opt[@]}" "$container" 2>&1 | summarize_log_errors "$max_findings" "$include_warnings"
        fi
        # a failed assertion (no record received, wrong count) usually logs no error at all
        if [[ "$container" == connect* ]]
        then
            log "📜 last 50 lines of $container logs"
            if [[ "$environment" == "cfk" ]]
            then
                kubectl -n confluent logs "$container" --tail=50
            else
                docker container logs --tail=50 "$container"
            fi
        fi
        log "####################################################"
    done <<< "$containers"
fi