log "💀 kill all docker containers"
docker rm -f $(docker ps -qa) > /dev/null 2>&1
docker volume prune -f > /dev/null 2>&1