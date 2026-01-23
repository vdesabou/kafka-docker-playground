log "💀 kill all docker containers (this also removes volumes)"
docker rm -f $(docker ps -qa) > /dev/null 2>&1
docker volume prune -f > /dev/null 2>&1