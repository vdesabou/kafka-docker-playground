container="${args[--container]}"
filename="/tmp/thread-dump-$container-`date '+%Y-%m-%d-%H-%M-%S'`.log"

set +e
docker exec $container type jstack > /dev/null 2>&1
if [ $? != 0 ]
then
    logerror "❌ jstack is not installed on container $container"
    exit 1
fi
set -e
log "🎯 Taking thread dump on container ${container} for pid 1"
docker exec $container jstack 1 > "$filename" 2>&1
if [ $? -eq 0 ]
then
    open_file_with_editor "${filename}"
else
    logerror "❌ Failed to take thread dump"
fi