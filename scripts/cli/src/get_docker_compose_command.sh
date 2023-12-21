# keep TAG, CONNECT TAG and ORACLE_IMAGE
export TAG=$(docker inspect -f '{{.Config.Image}}' broker 2> /dev/null | cut -d ":" -f 2)
export CONNECT_TAG=$(docker inspect -f '{{.Config.Image}}' connect 2> /dev/null | cut -d ":" -f 2)
export ORACLE_IMAGE=$(docker inspect -f '{{.Config.Image}}' oracle 2> /dev/null)

docker_command=$(playground state get docker_command)
echo "$docker_command" > /tmp/tmp
sed -e "s|up -d|config|g" \
    /tmp/tmp > /tmp/playground-command-config

bash /tmp/playground-command-config 