# keep CONNECT TAG and ORACLE_IMAGE
export CONNECT_TAG=$(docker inspect -f '{{.Config.Image}}' connect | cut -d ":" -f 2)
export ORACLE_IMAGE=$(docker inspect -f '{{.Config.Image}}' oracle | cut -d ":" -f 2)

if [ ! -f /tmp/playground-command ]
then
  logerror "File containing restart command /tmp/playground-command does not exist!"
  exit 1
fi

sed -e "s|up -d|config|g" \
    /tmp/playground-command > /tmp/playground-command-config

bash /tmp/playground-command-config 