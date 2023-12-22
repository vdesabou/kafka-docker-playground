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
    editor=$(playground config get editor)
    if [ "$editor" != "" ]
    then
        log "📖 Opening ${filename} using configured editor $editor"
        $editor ${filename}
    else
        if [[ $(type code 2>&1) =~ "not found" ]]
        then
            logerror "Could not determine an editor to use as default code is not found - you can change editor by using playground config editor <editor>"
            exit 1
        else
            log "📖 Opening ${filename} with code (default) - you can change editor by using playground config editor <editor>"
            code ${filename}
        fi
    fi
else
    logerror "❌ Failed to take thread dump"
fi