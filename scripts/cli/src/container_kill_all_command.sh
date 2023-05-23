log "💀 Kill all docker containers"
set +e
docker rm -f $(docker ps -qa) > /dev/null 2>&1