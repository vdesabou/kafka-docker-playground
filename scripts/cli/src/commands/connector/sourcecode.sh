connector_tags="${args[--connector-tag]}"
only_show_url="${args[--only-show-url]}"

# Convert space-separated string to array
IFS=' ' read -ra connector_tag_array <<< "$connector_tags"

test_file=$(playground state get run.test_file)

connector_type=$(playground state get run.connector_type)
if [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
then
    log "connector versions command is not supported with $connector_type connector"
    exit 0
fi

if [ ! -f $test_file ]
then 
    logerror "File $test_file retrieved from $root_folder/playground.ini does not exist!"
    exit 1
fi

maybe_only_show_url=""
if [[ -n "$only_show_url" ]]
then
    maybe_only_show_url="--only-show-url"
fi
if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ]
then
    owner="confluentinc"
    name=$(grep "connector.class" $test_file | head -1 | cut -d '"' -f4)

    length=${#connector_tag_array[@]}
    if ((length > 1))
    then
        if ((length > 2))
        then
            logerror "❌ --connector-tag can only be set 2 times"
            exit 1
        fi
        connector_tag1="${connector_tag_array[0]}"
        connector_tag2="${connector_tag_array[1]}"
        playground connector-plugin sourcecode --connector-plugin "$owner/$name" --connector-tag "$connector_tag1" --connector-tag "$connector_tag2" $maybe_only_show_url
    else
        if ((length == 1))
        then
            connector_tag="${connector_tag_array[0]}"
            playground connector-plugin sourcecode --connector-plugin "$owner/$name" --connector-tag "$connector_tag" $maybe_only_show_url
        else
            playground connector-plugin sourcecode --connector-plugin "$owner/$name" $maybe_only_show_url
        fi
    fi
    exit 0
fi


get_connector_paths
if [ "$connector_paths" == "" ]
then
    logwarn "❌ skipping as it is not an example with connector, but --connector-tag is set"
    exit 1
else
    for connector_path in ${connector_paths//,/ }
    do
        full_connector_name=$(basename "$connector_path")
        owner=$(echo "$full_connector_name" | cut -d'-' -f1)
        name=$(echo "$full_connector_name" | cut -d'-' -f2-)

        if [ "$owner" == "java" ] || [ "$name" == "hub-components" ] || [ "$owner" == "filestream" ]
        then
            # happens when plugin is not coming from confluent hub
            # logwarn "skipping as plugin $owner/$name does not appear to be coming from confluent hub"
            continue
        fi

        # # latest
        # latest=$(playground connector-plugin versions --connector-plugin $owner/$name --last 1)
        # latest_to_compare=$(echo "$latest" | head -n 1 | sed 's/ ([0-9]* days ago)//')

        length=${#connector_tag_array[@]}
        if ((length > 1))
        then
            if ((length > 2))
            then
                logerror "❌ --connector-tag can only be set 2 times"
                exit 1
            fi
            connector_tag1="${connector_tag_array[0]}"
            if [ "$connector_tag1" == "\\" ]
            then
                connector_tag1=" "
            fi
            connector_tag2="${connector_tag_array[1]}"
            if [ "$connector_tag2" == "\\" ]
            then
                connector_tag2=" "
            fi
            playground connector-plugin sourcecode --connector-plugin "$owner/$name" --connector-tag "$connector_tag1" --connector-tag "$connector_tag2" $maybe_only_show_url
        else
            if ((length == 1))
            then
                connector_tag="${connector_tag_array[0]}"
                if [ "$connector_tag" == "\\" ]
                then
                    connector_tag=" "
                fi
                playground connector-plugin sourcecode --connector-plugin "$owner/$name" --connector-tag "$connector_tag" $maybe_only_show_url
            else
                ## current version
                manifest_file="$root_folder/confluent-hub/$full_connector_name/manifest.json"
                if [ -f $manifest_file ]
                then
                    version=$(cat $manifest_file | jq -r '.version')
                    playground connector-plugin sourcecode --connector-plugin "$owner/$name" --connector-tag "$version" $maybe_only_show_url
                else
                    logwarn "file $manifest_file does not exist, could not retrieve version"
                    exit 0
                fi
            fi
        fi
    done
fi