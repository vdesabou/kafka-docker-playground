log "💀 Kill all docker containers"
docker rm -f $(docker ps -qa)