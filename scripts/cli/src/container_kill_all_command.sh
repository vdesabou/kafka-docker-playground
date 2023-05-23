log "💀 Kill all docker containers"
docker rm -f $(docker ps -qa) > /dev/null 2>&1