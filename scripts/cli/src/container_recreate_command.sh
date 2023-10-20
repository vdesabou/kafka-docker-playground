export IGNORE_CHECK_FOR_DOCKER_COMPOSE=true

# keep CONNECT TAG and ORACLE_IMAGE
set +e
export CONNECT_TAG=$(docker inspect -f '{{.Config.Image}}' connect | cut -d ":" -f 2) 2> /dev/null
export ORACLE_IMAGE=$(docker inspect -f '{{.Config.Image}}' oracle) 2> /dev/null
set -e
if [ ! -f /tmp/playground-command ]
then
  logerror "File containing restart command /tmp/playground-command does not exist!"
  exit 1
fi

log "💫 Recreate container(s)"
bash /tmp/playground-command