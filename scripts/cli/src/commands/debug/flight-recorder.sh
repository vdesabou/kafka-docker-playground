container="${args[--container]}"
action="${args[--action]}"
filename="flight-recorder-$container-`date '+%Y-%m-%d-%H-%M-%S'`.jfr"

set +e
docker exec $container type jcmd > /dev/null 2>&1
if [ $? != 0 ]
then
    tag=$(docker ps --format '{{.Image}}' | grep -E 'confluentinc/cp-.*-connect-.*:' | awk -F':' '{print $2}')
    if [ $? != 0 ] || [ "$tag" == "" ]
    then
        logerror "Could not find current CP version from docker ps"
        exit 1
    fi

    logwarn "jcmd is not installed on container $container, attempting to install it"

    if [[ "$tag" == *ubi8 ]] || version_gt $tag "5.9.0"
    then
      docker exec --privileged --user root $container bash -c "yum -y install --disablerepo='Confluent*' openjdk"
    else
      docker exec --privileged --user root $container bash -c "apt-get update && echo openjdk | xargs -n 1 apt-get install --force-yes -y && rm -rf /var/lib/apt/lists/*"
    fi
fi
docker exec $container type jcmd > /dev/null 2>&1
if [ $? != 0 ]
then
    logerror "❌ jcmd could not be installed"
    exit 1
fi
set -e

case "${action}" in
    start)
        set +e
        output=$(docker exec ${container} jcmd 1 JFR.check)
        echo "$output" | grep "running" | grep "dump1"
        if [ $? -eq 0 ]
        then
            logwarn "🛩️ flight recorder is already started !"
            exit 0
        fi
        set -e

        docker cp ${root_folder}/scripts/cli/all.jfc ${container}:/tmp/all.jfc > /dev/null 2>&1
        docker exec ${container} jcmd 1 JFR.start name=dump1 filename=/tmp/${filename} settings=/tmp/all.jfc
        if [ $? -eq 0 ]
        then
            log "🛩️ flight recorder is now started"
        else
            logerror "❌ Failed to start flight recorder"
        fi
    ;;
    stop)
        set +e
        output=$(docker exec ${container} jcmd 1 JFR.check)
        echo "$output" | grep "running" | grep "dump1"
        if [ $? -ne 0 ]
        then
            logerror "🛩️ flight recorder is not started !"
            exit 1
        fi
        set -e
        docker exec ${container} jcmd 1 JFR.stop name=dump1 filename=/tmp/${filename}
        if [ $? -eq 0 ]
        then
            log "🛩️ flight recorder is available at ${filename}"
            log "use JDK Mission Control JMC (https://jdk.java.net/jmc/) to open it"
            docker cp ${container}:/tmp/${filename} ${filename}
        else
            logerror "❌ Failed to stop flight recorder"
        fi
    ;;
    *)
        logerror "should not happen"
        exit 1
    ;;
esac