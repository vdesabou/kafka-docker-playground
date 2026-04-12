connector_type=$(playground state get run.connector_type)
if [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ] || [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ]
then
    log "playground connector display-leader-name command is not supported with $connector_type connector"
    exit 0
fi

get_connect_container

leader_name=$(playground get-jmx-metrics --container "$connect_container" --domain kafka.connect | awk -F'=' '/leader-name/ {print $2}' | tr -d ' ;')

log "👑 leader name is:"
# Convert values like http://connect:8083/ to connect
echo "$leader_name" | sed -E 's#^[a-zA-Z]+://##' | cut -d'/' -f1 | cut -d':' -f1

