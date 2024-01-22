log "🧨 Remove all docker images (including docker volumes)"
check_if_continue

playground container kill-all
docker image rm $(docker image list | grep -v "oracle/database"  | grep -v "db-prebuilt" | awk 'NR>1 {print $3}') -f
docker system prune -a -f
docker volume rm $(docker volume ls -qf dangling=true)