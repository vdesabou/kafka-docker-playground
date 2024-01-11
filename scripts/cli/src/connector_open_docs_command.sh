test_file=$(playground state get run.test_file)
only_show_url="${args[--only-show-url]}"

if [ ! -f $test_file ]
then 
    logerror "❌ File $test_file retrieved from $root_folder/playground.ini does not exist!"
    exit 1
fi

# determining the docker-compose file from from test_file
docker_compose_file=$(grep "start-environment" "$test_file" |  awk '{print $6}' | cut -d "/" -f 2 | cut -d '"' -f 1 | tail -n1 | xargs)
test_file_directory="$(dirname "${test_file}")"
docker_compose_file="${test_file_directory}/${docker_compose_file}"

if [ "${docker_compose_file}" != "" ] && [ ! -f "${docker_compose_file}" ]
then
    logwarn "Skipping as docker-compose override file could not be detemined"
    exit 0
fi

connector_paths=$(grep "CONNECT_PLUGIN_PATH" "${docker_compose_file}" | grep -v "KSQL_CONNECT_PLUGIN_PATH" | cut -d ":" -f 2  | tr -s " " | head -1)
if [ "$connector_paths" == "" ]
then
    logwarn "Skipping as it is not an example with connector"
    exit 0
else
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
                    log "🌐 documentation for connector $name is available at:"
                    echo "$short_url"
                else
                    log "🌐 opening documentation for connector $name $short_url"
                    open "$short_url"
                fi
            else
                logerror "❌ Could not find documentation link in manifest file $manifest_file"
                exit 1
            fi
        else
            logerror "❌ file $manifest_file does not exist"
            exit 1
        fi
    done
fi