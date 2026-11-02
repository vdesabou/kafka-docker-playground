log "🧨 Remove all docker images (including docker volumes), except the Oracle database images (oracle/database, db-prebuilt-*: long to build)"
check_if_continue

set +e
playground container kill-all
images=$(docker image ls --format '{{.Repository}}:{{.Tag}} {{.ID}}' | grep -v "^oracle/database" | grep -v "^db-prebuilt" | awk '{print $2}' | sort -u)
if [ -n "$images" ]
then
    docker image rm -f $images
fi
# no -a: 'docker system prune -a' removes every unused image, the Oracle ones included
docker system prune -f
volumes=$(docker volume ls -qf dangling=true)
if [ -n "$volumes" ]
then
    docker volume rm $volumes
fi
