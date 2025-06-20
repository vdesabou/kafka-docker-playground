version=${args[--version]}

if [[ -n "$version" ]]
then
    log "🔄 Pulling Confluent Platform docker images for $version"
    docker image ls | grep confluentinc | grep $version | awk '{print $1":"$2}' | xargs -I {} docker pull {}
    exit 0
fi