IGNORE_CHECK_FOR_DOCKER_COMPOSE=true

container="${args[--container]}"

log "Enable remote debugging for $container"

# For ccloud case
if [ -f /tmp/delta_configs/env.delta ]
then
     source /tmp/delta_configs/env.delta
fi

# keep CONNECT TAG
export CONNECT_TAG=$(docker inspect -f '{{.Config.Image}}' connect | cut -d ":" -f 2)

if [ ! -f /tmp/playground-command ]
then
  logerror "File containing restart command /tmp/playground-command does not exist!"
  exit 1
fi

# see heredocs.sh
get_remote_debugging_command_heredoc "$container"

bash /tmp/playground-command-debugging

log "If you use Visual Studio Code:"
log "Edit .vscode/launch.json with"

log "
{
    \"version\": \"0.2.0\",
    \"configurations\": [
    
        {
            \"type\": \"java\",
            \"name\": \"Debug $component container\",
            \"request\": \"attach\",
            \"hostName\": \"127.0.0.1\",
            \"port\": 5005,
            \"timeout\": 30000
        }
    ]
}
"

log "See https://kafka-docker-playground.io/#/reusables?id=✨-remote-debugging"