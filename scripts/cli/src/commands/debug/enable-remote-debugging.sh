IGNORE_CHECK_FOR_DOCKER_COMPOSE=true

container="${args[--container]}"

log "Enable remote debugging for $container"

# For ccloud case
if [ -f $root_folder/.ccloud/env.delta ]
then
     source $root_folder/.ccloud/env.delta
fi

# keep TAG, CONNECT TAG and ORACLE_IMAGE
export TAG=$(docker inspect -f '{{.Config.Image}}' broker 2> /dev/null | cut -d ":" -f 2)
export CONNECT_TAG=$(docker inspect -f '{{.Config.Image}}' connect 2> /dev/null | cut -d ":" -f 2)
export ORACLE_IMAGE=$(docker inspect -f '{{.Config.Image}}' oracle 2> /dev/null)

# see heredocs.sh
get_remote_debugging_command_heredoc "$container"
load_env_variables
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