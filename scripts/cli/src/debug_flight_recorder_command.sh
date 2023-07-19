container="${args[--container]}"
action="${args[--action]}"
filename="flight-recorder-$container-`date '+%Y-%m-%d-%H-%M-%S'`.jfr"

set +e
docker exec $container type jcmd > /dev/null 2>&1
if [ $? != 0 ]
then
    logwarn "jcmd is not installed on container $container, attempting to install it"

    DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
    dir1=$(echo ${DIR_CLI%/*})
    root_folder=$(echo ${dir1%/*})
    IGNORE_CHECK_FOR_DOCKER_COMPOSE=true
    source $root_folder/scripts/utils.sh

    if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
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

        docker exec ${container} jcmd 1 JFR.start name=dump1 filename=/tmp/${filename}
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