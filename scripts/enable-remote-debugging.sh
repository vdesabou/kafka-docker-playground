#!/bin/bash

IGNORE_CHECK_FOR_DOCKER_COMPOSE=true
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../scripts/utils.sh

# For ccloud case
if [ -f /tmp/delta_configs/env.delta ]
then
     source /tmp/delta_configs/env.delta
fi

component=${1:-connect}

if [ ! -f /tmp/playground-command ]
then
  logerror "File containing restart command /tmp/playground-command does not exist!"
  exit 1
fi

tmp_dir=$(mktemp -d -t ci-XXXXXXXXXX)
cat << EOF > $tmp_dir/docker-compose-remote-debugging.yml
version: '3.5'
services:
  $component:
    environment:
      # https://kafka-docker-playground.io/#/reusables?id=✨-remote-debugging
      KAFKA_DEBUG: 'true'
      # With JDK9+, need to specify address=*:5005, see https://www.baeldung.com/java-application-remote-debugging#from-java9
      JAVA_DEBUG_OPTS: '-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=0.0.0.0:5005'
EOF

sed -e "s|up -d|-f $tmp_dir/docker-compose-remote-debugging.yml up -d|g" \
    /tmp/playground-command > /tmp/playground-command-debugging

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