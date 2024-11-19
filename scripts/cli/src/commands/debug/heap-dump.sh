container="${args[--container]}"
live="${args[--live]}"
histo="${args[--histo]}"

set +e
docker exec $container type jmap > /dev/null 2>&1
if [ $? != 0 ]
then
    logerror "❌ jmap is not installed on container $container"
    exit 1
fi

if [[ -n "$histo" ]]
then
    filename="heap-dump-$container-histo-`date '+%Y-%m-%d-%H-%M-%S'`.txt"
    set -e
    if [[ -n "$live" ]]
    then
        log "📊 Taking histo (with live option) heap dump on container ${container}"
        docker exec $container jmap -histo:live 1 > /tmp/${filename}
    else
        log "📊 Taking histo (without live option) heap dump on container ${container}"
        docker exec $container jmap -histo 1 > /tmp/${filename}
    fi
    if [ $? -eq 0 ]
    then
        log "👻 heap dump is available at /tmp/${filename}"
    else
        logerror "❌ Failed to take heap dump"
    fi
else
    filename="heap-dump-$container-`date '+%Y-%m-%d-%H-%M-%S'`.hprof"
    set -e
    if [[ -n "$live" ]]
    then
        log "🎯 Taking heap dump (with live option) on container ${container}"
        docker exec $container jmap -dump:live,format=b,file=/tmp/${filename} 1
    else
        log "🎯 Taking heap dump (without live option) on container ${container}"
        docker exec $container jmap -dump:format=b,file=/tmp/${filename} 1
    fi
    if [ $? -eq 0 ]
    then
        log "👻 heap dump is available at ${filename}"
        docker cp ${container}:/tmp/${filename} ${filename}
    else
        logerror "❌ Failed to take heap dump"
    fi
fi
