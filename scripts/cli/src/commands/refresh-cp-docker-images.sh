version=${args[--version]}

if [[ -n "$version" ]]
then
    log "🔄 Pulling Confluent Platform docker images for $version"
    docker image ls | grep confluentinc | grep $version | awk '{print $1":"$2}' | xargs -I {} docker pull {}
    exit 0
fi

docker pull amazon/aws-cli
docker pull mcr.microsoft.com/azure-cli:azurelinux3.0
docker pull google/cloud-sdk:latest