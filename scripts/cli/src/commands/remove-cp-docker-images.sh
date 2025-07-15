version=${args[--version]}

if [[ -n "$version" ]]
then
    log "🧹 removing Confluent Platform docker images: $version"
    check_if_continue
    docker image ls | grep confluentinc | grep $version | awk '{print $3}' | xargs docker rmi -f
    exit 0
fi

LATEST_TAG=$(grep "export TAG" $root_folder/scripts/utils.sh | head -1 | cut -d "=" -f 2 | cut -d " " -f 1)
if [ -z "$LATEST_TAG" ]
then
    logerror "❌ error while getting default TAG "
    exit 1
fi

for version in $(docker image ls | grep confluentinc | grep -v "<none>" | grep -Ev "latest|2.0.0|$LATEST_TAG"  | awk '{print $2}' | sort | uniq);
do
    log "🧹 removing Confluent Platform docker images: $version (skipping default TAG $LATEST_TAG)"
    check_if_continue
    docker image ls | grep confluentinc | grep $version | awk '{print $3}' | xargs docker rmi -f
done
