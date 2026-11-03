connector_type=$(playground state get run.connector_type)
if [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ] || [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ]
then
    log "playground connector display-leader-name command is not supported with $connector_type connector"
    exit 0
fi

get_environment_used

# Build list of connect containers to try: the running workers, rather than the ENABLE_CONNECT_NODES flag (same
# detection as playground connector status)
connect_containers=()
if [[ "$environment" == cfk* ]]
then
    # CFK uses numbered pods: connect-0, connect-1, connect-2, etc.
    connect_containers=($(kubectl -n confluent get pods -o name 2>/dev/null | sed 's#pod/##' | grep -E '^connect-[0-9]+$' || true))
    if [ ${#connect_containers[@]} -eq 0 ]
    then
        connect_containers=("connect-0")
    fi
else
    # Docker uses: connect, connect2, connect3, etc.
    get_connect_container
    connect_containers=("$connect_container")
    if ! is_mdc_environment && is_multiple_connect_workers_running
    then
        for worker in connect2 connect3
        do
            if is_container_running "$worker"
            then
                connect_containers+=("$worker")
            fi
        done
    fi
fi

# Try to get leader name from available connect pods
leader_name=""
for container in "${connect_containers[@]}"
do
    resolved_container=$(resolve_container_name_for_environment "$container")
    if leader_name=$(playground get-jmx-metrics --container "$resolved_container" --domain kafka.connect 2>/dev/null | awk -F'=' '/leader-name/ {print $2}' | tr -d ' ;')
    then
        if [[ -n "$leader_name" ]]
        then
            break
        fi
    fi
done

if [[ -z "$leader_name" ]]
then
    logerror "❌ Could not retrieve leader name from connect cluster"
    exit 1
fi

log "👑 leader name is:"
# Convert values like http://connect:8083/ to connect
# Also handle Kubernetes DNS names like connect-1.connect.confluent.svc.cluster.local
echo "$leader_name" | sed -E 's#^[a-zA-Z]+://##' | cut -d'/' -f1 | cut -d':' -f1 | cut -d'.' -f1

