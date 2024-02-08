test_file=$(playground state get run.test_file)

connector_type=$(playground state get run.connector_type)
if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
then
    log "connector versions command is not supported with $connector_type connector"
    exit 0
fi

if [ ! -f $test_file ]
then 
    logerror "File $test_file retrieved from $root_folder/playground.ini does not exist!"
    exit 1
fi
get_connector_paths
if [ "$connector_paths" == "" ]
then
    logwarn "❌ skipping as it is not an example with connector, but --connector-tag is set"
    exit 1
else
    current_tag=$(docker inspect -f '{{.Config.Image}}' broker 2> /dev/null | cut -d ":" -f 2)
    log "🎯 Version currently used for confluent platform"
    echo "$current_tag"

    for connector_path in ${connector_paths//,/ }
    do
        full_connector_name=$(basename "$connector_path")
        owner=$(echo "$full_connector_name" | cut -d'-' -f1)
        name=$(echo "$full_connector_name" | cut -d'-' -f2-)

        if [ "$owner" == "java" ] || [ "$name" == "hub-components" ] || [ "$owner" == "filestream" ]
        then
            # happens when plugin is not coming from confluent hub
            logwarn "skipping as plugin $owner/$name does not appear to be coming from confluent hub"
            continue
        fi

        playground connector-plugin versions --connector-plugin $owner/$name --last 10

        # latest
        latest=$(playground connector-plugin versions --connector-plugin $owner/$name --last 1)
        latest_to_compare=$(echo "$latest" | sed 's/ ([0-9]* days ago)//')

        ## current version
        manifest_file="$root_folder/confluent-hub/$full_connector_name/manifest.json"
        if [ -f $manifest_file ]
        then
            version=$(cat $manifest_file | jq -r '.version')
            release_date=$(cat $manifest_file | jq -r '.release_date')
        else
            logwarn "file $manifest_file does not exist, could not retrieve version"
            exit 0
        fi

        current="🔢 v$version - 📅 release date: $release_date"
        if [ "$current" == "$latest_to_compare" ]
        then
            log "👻 Version currently used for $owner/$name is latest"
            echo "$current"
        else
            log "🗯️ Version currently used for $owner/$name is not latest"
            log "Current"
            echo "$current"
            log "Latest on Hub"
            echo "$latest"
        fi 
    done
fi