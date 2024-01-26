get_connect_url_and_security

connector="${args[--connector]}"
verbose="${args[--verbose]}"

if [[ ! -n "$connector" ]]
then
    connector=$(playground get-connector-list)
    if [ "$connector" == "" ]
    then
        logerror "💤 No connector is running !"
        exit 1
    fi
fi

tag=$(docker ps --format '{{.Image}}' | egrep 'confluentinc/cp-.*-connect-base:' | awk -F':' '{print $2}')
if [ $? != 0 ] || [ "$tag" == "" ]
then
    logerror "Could not find current CP version from docker ps"
    exit 1
fi

items=($connector)
length=${#items[@]}
if ((length > 1))
then
    log "✨ --connector flag was not provided, applying command to all connectors"
fi
for connector in ${items[@]}
do
    log "🔄 Restarting connector $connector"
    if ! version_gt $tag "6.9.9"
    then
        task_ids=$(curl $security -s -X GET "$connect_url/connectors/$connector/tasks" | jq -r '.[].id.task')

        for task_id in $task_ids
        do
            log "🤹‍♂️ Restart task $task_id"
            if [[ -n "$verbose" ]]
            then
                log "🐞 curl command used"
                echo "curl $security -s -X POST -H "Content-Type: application/json" "$connect_url/connectors/$connector/tasks/$task_id/restart""
            fi
            curl $security -s -X POST -H "Content-Type: application/json" "$connect_url/connectors/$connector/tasks/$task_id/restart"
        done
    else
        if [[ -n "$verbose" ]]
        then
            log "🐞 curl command used"
            echo "curl $security -s -X POST -H "Content-Type: application/json" "$connect_url/connectors/$connector/restart?includeTasks=true&onlyFailed=false""
        fi
        curl $security -s -X POST -H "Content-Type: application/json" "$connect_url/connectors/$connector/restart?includeTasks=true&onlyFailed=false" | jq .
    fi
done
sleep 3
playground connector status --connector $connector