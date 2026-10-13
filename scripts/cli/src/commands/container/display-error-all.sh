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
if [[ "$environment" == cfk* ]]
then
    containers=$(kubectl -n confluent get pods -o name 2>/dev/null | sed 's#pod/##')
else
    containers=$(docker ps --format="{{.Names}}")
fi
if [ -z "$containers" ]; then
    logwarn "💤 no running containers"
else
    log "####################################################"
    if [[ "$environment" == cfk* ]]
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

                    # extra services are bare pods (no owner) whose files come from Secret mounts: when one
                    # keeps crashing, show what the container really sees at those mount paths
                    owner=$(kubectl -n confluent get pod "$container" -o jsonpath='{.metadata.ownerReferences[*].kind}' 2>/dev/null)
                    restarts=$(kubectl -n confluent get pod "$container" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null)
                    mount_paths=$(kubectl -n confluent get pod "$container" -o jsonpath='{range .spec.containers[0].volumeMounts[*]}{.mountPath}{" "}{end}' 2>/dev/null | sed 's#/var/run/secrets/kubernetes.io/serviceaccount##')
                    if [[ -z "$owner" ]] && [[ "${restarts:-0}" -gt 0 ]] && [[ -n "${mount_paths// /}" ]]
                    then
                        main_container=$(kubectl -n confluent get pod "$container" -o jsonpath='{.spec.containers[0].name}' 2>/dev/null)
                        diag_pod="${container}-diag"
                        log "####################################################"
                        log "☸️ mounts of $container seen by its own image and user (kubectl debug --copy-to=$diag_pod)"
                        kubectl -n confluent delete pod "$diag_pod" --force --grace-period=0 > /dev/null 2>&1
                        # shellcheck disable=SC2016,SC2086
                        if kubectl -n confluent debug "pod/$container" --copy-to="$diag_pod" --container="$main_container" --quiet -- \
                            sh -c 'id; echo "security context: $(cat /proc/self/attr/current 2>/dev/null)"; for p in "$@"; do echo "--- $p"; ls -lnd "$p"; ls -lnZd "$p" 2>/dev/null; if [ -f "$p" ]; then head -c 1 "$p" > /dev/null && echo "readable" || echo "NOT readable"; else ls -ln "$p"; fi; mount | grep -F " $p "; done' \
                            diag $mount_paths > /dev/null 2>&1
                        then
                            for _ in $(seq 1 15)
                            do
                                diag_state=$(kubectl -n confluent get pod "$diag_pod" -o jsonpath='{.status.containerStatuses[0].state.terminated.reason}{.status.containerStatuses[0].lastState.terminated.reason}' 2>/dev/null)
                                if [[ -n "$diag_state" ]]
                                then
                                    break
                                fi
                                sleep 2
                            done
                            kubectl -n confluent logs "$diag_pod" 2>&1 | head -n 60
                        else
                            logwarn "could not create $diag_pod with kubectl debug"
                        fi
                        kubectl -n confluent delete pod "$diag_pod" --force --grace-period=0 > /dev/null 2>&1
                    fi
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

    clean_containers=()
    while IFS= read -r container
    do
        if [ -z "$container" ]; then
            continue
        fi
        if [[ "$environment" == cfk* ]]
        then
            digest=$(kubectl -n confluent logs "$container" --all-containers=true "${since_opt[@]}" 2>&1 | summarize_log_errors "$max_findings" "$include_warnings")
        else
            digest=$(docker container logs "${since_opt[@]}" "$container" 2>&1 | summarize_log_errors "$max_findings" "$include_warnings")
        fi
        # a failed assertion (no record received, wrong count) usually logs no error at all, so connect tail is always shown
        if [[ "$digest" == "✅"* ]] && [[ "$container" != connect* ]]
        then
            clean_containers+=("$container")
            continue
        fi
        log "####################################################"
        if [[ "$digest" == "✅"* ]]
        then
            clean_containers+=("$container")
        else
            log "🔥 ERROR/FATAL digest for $container logs${since:+ since $since}"
            echo "$digest"
        fi
        if [[ "$container" == connect* ]]
        then
            log "📜 last 50 lines of $container logs"
            if [[ "$environment" == cfk* ]]
            then
                kubectl -n confluent logs "$container" --tail=50
            else
                docker container logs --tail=50 "$container"
            fi
        fi
        log "####################################################"
    done <<< "$containers"
    if [ ${#clean_containers[@]} -gt 0 ]
    then
        log "✅ no $([[ -n "$include_warnings" ]] && echo "ERROR/FATAL/WARN" || echo "ERROR/FATAL") record${since:+ since $since} in: ${clean_containers[*]}"
    fi
fi