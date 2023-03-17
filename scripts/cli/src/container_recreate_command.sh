IGNORE_CHECK_FOR_DOCKER_COMPOSE=true

# keep CONNECT TAG
export CONNECT_TAG=$(docker inspect -f '{{.Config.Image}}' connect | cut -d ":" -f 2)

if [ ! -f /tmp/playground-command ]
then
  logerror "File containing restart command /tmp/playground-command does not exist!"
  exit 1
fi

bash /tmp/playground-command