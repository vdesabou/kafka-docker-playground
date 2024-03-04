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

docker_command=$(playground state get run.docker_command)
if [ "$docker_command" == "" ]
then
  logerror "docker_command retrieved from $root_folder/playground.ini is empty !"
  exit 1
fi
echo "$docker_command" > /tmp/tmp
tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
trap 'rm -rf $tmp_dir' EXIT
cat << EOF > $tmp_dir/docker-compose-remote-debugging.yml
version: '3.5'
services:
  $container:
    environment:
      # https://kafka-docker-playground.io/#/reusables?id=✨-remote-debugging
      KAFKA_DEBUG: 'true'
      # With JDK9+, need to specify address=*:5005, see https://www.baeldung.com/java-application-remote-debugging#from-java9
      JAVA_DEBUG_OPTS: '-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=0.0.0.0:5005'
EOF

sed -e "s|up -d|-f $tmp_dir/docker-compose-remote-debugging.yml up -d|g" \
    /tmp/tmp > /tmp/playground-command-debugging

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