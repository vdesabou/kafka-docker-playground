test_file=$(playground state get run.test_file)
only_show_url="${args[--only-show-url]}"

connector_type=$(playground state get run.connector_type)

if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
then
    logerror "❌ command not supported with $connector_type connector"
    exit 1
fi

if [ ! -f $test_file ]
then 
    logerror "❌ File $test_file retrieved from $root_folder/playground.ini does not exist!"
    exit 1
fi

get_connector_paths
if [ "$connector_paths" == "" ]
then
    logwarn "❌ skipping as it is not an example with connector, but --connector-tag is set"
    exit 1
else
    doc_available=1
    for connector_path in ${connector_paths//,/ }
    do
        full_connector_name=$(basename "$connector_path")

        manifest_file="$root_folder/confluent-hub/$full_connector_name/manifest.json"
        if [ -f $manifest_file ]
        then
            url=$(cat $manifest_file | jq -r '.documentation_url')
            name=$(cat $manifest_file | jq -r '.name')
            url=${url//)/}

            if [[ $url =~ "http" ]]
            then
                short_url=$(echo $url | cut -d '#' -f 1)
                if [[ -n "$only_show_url" ]]
                then
                    log "🌐 documentation for $connector_type connector $name is available at:"
                    echo "$short_url"
                else
                    log "🌐 opening documentation for $connector_type connector $name $short_url"
                    open "$short_url"
                fi
            else
                logerror "❌ Could not find documentation link in manifest file $manifest_file"
                exit 1
            fi
        else
            doc_available=0
        fi
    done
    if [ $doc_available -eq 0 ]
    then
        log "🌐 documentation could not be retrieved"
    fi
fi