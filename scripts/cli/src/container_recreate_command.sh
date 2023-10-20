ignore_current_versions="${args[--ignore-current-versions]}"

export IGNORE_CHECK_FOR_DOCKER_COMPOSE=true

if [[ ! -n "$ignore_current_versions" ]]
then
  # keep TAG and CONNECT_TAG
  export TAG=$(docker inspect -f '{{.Config.Image}}' broker 2> /dev/null | cut -d ":" -f 2)
  export CONNECT_TAG=$(docker inspect -f '{{.Config.Image}}' connect 2> /dev/null | cut -d ":" -f 2)
fi

export ORACLE_IMAGE=$(docker inspect -f '{{.Config.Image}}' oracle 2> /dev/null)

if [ ! -f /tmp/playground-command ]
then
  logerror "File containing restart command /tmp/playground-command does not exist!"
  exit 1
fi
set +e
log "💫 Recreate container(s)"
bash /tmp/playground-command