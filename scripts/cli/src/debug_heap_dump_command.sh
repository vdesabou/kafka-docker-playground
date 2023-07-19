container="${args[--container]}"
filename="heap-dump-$container-`date '+%Y-%m-%d-%H-%M-%S'`.hprof"

set +e
docker exec $container type jmap > /dev/null 2>&1
if [ $? != 0 ]
then
    logerror "❌ jmap is not installed on container $container"
    exit 1
fi
set -e
log "🎯 Taking heap dump on container ${container} for pid 1"
docker exec $container jmap -dump:live,format=b,file=/tmp/${filename} 1
if [ $? -eq 0 ]
then
    log "👻 heap dump is available at ${filename}"
    docker cp ${container}:/tmp/${filename} ${filename}
    # if [[ $(type -f wireshark 2>&1) =~ "not found" ]]
    # then
    #     logwarn "🦈 wireshark is not installed, grab it at https://www.wireshark.org/"
    #     exit 0
    # else
    #     log "🦈 Opening ${filename} with wireshark"
    #     wireshark ${filename}
    # fi 
else
    logerror "❌ Failed to take heap dump"
fi


