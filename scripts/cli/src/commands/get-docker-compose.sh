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
sed -e "s|up -d|config|g" \
    -e "s|--quiet-pull||g" \
    /tmp/tmp > /tmp/playground-command-config

bash /tmp/playground-command-config 