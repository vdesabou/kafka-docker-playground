connector_type=$(playground state get run.connector_type)
if [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ] || [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ]
then
    log "playground connector display-leader-name command is not supported with $connector_type connector"
    exit 0
fi

get_environment_used

# Check if multiple connect workers are enabled
enable_connect_nodes=$(playground state get flags.ENABLE_CONNECT_NODES)

# Build list of connect containers to try
connect_containers=()
if [[ "$environment" == "cfk" ]]
then
    # CFK uses numbered pods: connect-0, connect-1, connect-2, etc.
    connect_containers=("connect-0")
    if [[ -n "$enable_connect_nodes" ]]
    then
        connect_containers+=("connect-1" "connect-2")
    fi
else
    # Docker uses: connect, connect2, connect3, etc.
    get_connect_container
    connect_containers=("$connect_container")
    if [[ -n "$enable_connect_nodes" ]]
    then
        connect_containers+=("connect2" "connect3")
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

