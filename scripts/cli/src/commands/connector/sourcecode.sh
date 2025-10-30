connector_tags="${args[--connector-tag]}"
only_show_url="${args[--only-show-url]}"
compile="${args[--compile]}"
compile_jdk_version="${args[--compile-jdk-version]}"
compile_verbose="${args[--compile-verbose]}"

# Convert space-separated string to array
IFS=' ' read -ra connector_tag_array <<< "$connector_tags"

test_file=$(playground state get run.test_file)

connector_type=$(playground state get run.connector_type)
if [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
then
    log "playground connector sourcecode command is not supported with $connector_type connector"
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
    if [[ -n "$compile" ]]
    then
        logerror "❌ --compile does not work when using fully managed connectors"
        exit 1
    fi

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


maybe_compile=""
if [[ -n "$compile" ]]
then
    maybe_compile="--compile"

    if [[ -n "$compile_jdk_version" ]]
    then
        maybe_compile_jdk_version="--compile_jdk_version $compile_jdk_version"
    fi

    if [[ -n "$compile_verbose" ]]
    then
        maybe_compile_verbose="--compile-verbose"
    fi
fi

function choosezip()
{
  log "🧩 select the zip to use:"
  select zip
  do
    # Check the selected menu jar number
    if [ 1 -le "$REPLY" ] && [ "$REPLY" -le $# ];
    then
      break;
    else
      logwarn "wrong selection <$zip>! select any number from 1-$#"
      choosezip
    fi
  done
}

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

        length=${#connector_tag_array[@]}
        if ((length > 1))
        then
            if ((length > 2))
            then
                logerror "❌ --connector-tag can only be set 2 times"
                exit 1
            fi

            if [[ -n "$compile" ]]
            then
                logerror "❌ --compile does not work when --connector-tag is set twice"
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
                playground connector-plugin sourcecode --connector-plugin "$owner/$name" --connector-tag "$connector_tag" $maybe_only_show_url $maybe_compile $maybe_compile_jdk_version $maybe_compile_verbose
            else
                ## current version
                manifest_file="$root_folder/confluent-hub/$full_connector_name/manifest.json"
                if [ -f "$manifest_file" ]
                then
                    version=$(cat $manifest_file | jq -r '.version')
                    playground connector-plugin sourcecode --connector-plugin "$owner/$name" --connector-tag "$version" $maybe_only_show_url $maybe_compile $maybe_compile_jdk_version $maybe_compile_verbose
                else
                    logerror "❌ file $manifest_file does not exist, could not retrieve version"
                    exit 1
                fi
            fi

            if [[ -n "$compile" ]]
            then
                declare -a array_zip_file_list=()
                encoded_array="$(playground state get run.array_zip_file_list_base64)"
                eval "$(echo "$encoded_array" | base64 -d)"

                zip_list_length=${#array_zip_file_list[@]}
                if ((zip_list_length > 1))
                then
                    log "🧩 multiple zip files have been compiled, which one do you want to use ?"
                    choosezip "${array_zip_file_list[@]}"
                else
                    zip="${array_zip_file_list[0]}"
                fi

                log "💫 executing playground update-version --connector-zip $zip"
                playground update-version --connector-zip "$zip"
            fi
        fi
    done
fi