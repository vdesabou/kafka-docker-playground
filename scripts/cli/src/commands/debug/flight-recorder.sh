containers="${args[--container]}"
action="${args[--action]}"

# Convert space-separated string to array
IFS=' ' read -ra container_array <<< "$containers"

for container in "${container_array[@]}"
do
    filename="flight-recorder-$container-$(date '+%Y-%m-%d-%H-%M-%S').jfr"

    set +e
    docker exec $container type jcmd > /dev/null 2>&1
    if [ $? != 0 ]
    then
        logwarn "jcmd is not installed on container $container, attempting to install jdk 17"
        playground container change-jdk --version 17

        docker exec $container type jcmd > /dev/null 2>&1
        if [ $? != 0 ]
        then
            logerror "❌ jcmd could not be installed on container $container"
            exit 1
        fi
    fi

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
done