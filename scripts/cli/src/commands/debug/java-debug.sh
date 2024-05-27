container="${args[--container]}"
type="${args[--type]}"
action="${args[--action]}"

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

if [[ "$action" == "enable" ]]
then
    case "${type}" in
        "ssl_all")
            OPTS="-Djavax.net.debug=all"
        ;;
        "ssl_handshake")
            OPTS="-Djavax.net.debug=ssl:handshake"
        ;;
        "class_loading")
            OPTS="-verbose:class"
        ;;
        "kerberos")
            OPTS="-Dsun.security.krb5.debug=true"
        ;;
    esac
    
    cat << EOF > /tmp/docker-compose.override.java.debug.yml
services:
  $container:
    environment:
      KAFKA_OPTS: "$OPTS"
      DUMMY: $RANDOM
EOF
    log "🟢 enabling container $container with JVM arguments KAFKA_OPTS: $OPTS"
    echo "$docker_command" > /tmp/playground-command-java-debug
    sed -i -E -e "s|up -d --quiet-pull|-f /tmp/docker-compose.override.java.debug.yml up -d --quiet-pull|g" /tmp/playground-command-java-debug
    bash /tmp/playground-command-java-debug

else
    log "🔴 restoring previous JVM arguments for container $container"
    echo "$docker_command" > /tmp/playground-command
    bash /tmp/playground-command
fi