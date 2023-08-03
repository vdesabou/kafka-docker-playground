ret=$(get_connect_url_and_security)

connect_url=$(echo "$ret" | cut -d "@" -f 1)
security=$(echo "$ret" | cut -d "@" -f 2)

connector="${args[--connector]}"

if [[ ! -n "$connector" ]]
then
    log "✨ --connector flag was not provided, applying command to all connectors"
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
for connector in ${items[@]}
do
    log "🔄 Restarting connector $connector"
    if ! version_gt $tag "6.9.9"
    then
        task_ids=$(curl $security -s -X GET "$connect_url/connectors/$connector/tasks" | jq -r '.[].id.task')

        for task_id in $task_ids
        do
            log "🤹‍♂️ Restart task $task_id"
            curl $security -s -X POST -H "Content-Type: application/json" "$connect_url/connectors/$connector/tasks/$task_id/restart"
        done
    else
        curl $security -s -X POST -H "Content-Type: application/json" "$connect_url/connectors/$connector/restart?includeTasks=true&onlyFailed=false" | jq .
    fi
done
sleep 3
playground connector status --connector $connector