test_file=$(playground state get run.test_file)

connector_type=$(playground state get run.connector_type)
if [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
then
    logerror "❌ connector versions command is not supported with $connector_type connector"
    exit 1
fi

# fully managed: no Confluent Hub version, the connector version comes with the cc-connect image
if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ]
then
    connectors=$(playground get-connector-list)
    if [ -z "$connectors" ]
    then
        log "💤 No $connector_type connector is running !"
        exit 1
    fi
    failed=0
    for connector in $connectors
    do
        connector_class=""
        if get_connector_config_json "$connector" > /dev/null 2>&1
        then
            connector_class=$(echo "$curl_output" | jq -r '."connector.class" // empty' 2> /dev/null)
        fi
        if [ -z "$connector_class" ] && [ -f "$test_file" ]
        then
            connector_class=$(grep "connector.class" "$test_file" | head -1 | cut -d '"' -f4)
        fi
        if [ -z "$connector_class" ]
        then
            logerror "❌ could not find the connector.class of $connector_type connector $connector"
            failed=1
            continue
        fi
        log "☁️ $connector_type connector $connector ($connector_class): connector version shipped by the last cc-connect images (Confluent employees: gh logged in and Confluent VPN)"
        playground connector-plugin fm-versions --connector-plugin "confluentinc/$connector_class" --last 5 || failed=1
    done
    exit $failed
fi

if [ ! -f "$test_file" ]
then
    logerror "File $test_file retrieved from $root_folder/playground.ini does not exist!"
    exit 1
fi
get_connector_paths
if [ "$connector_paths" == "" ]
then
    logwarn "❌ skipping as $test_file is not an example with a connector plugin"
    exit 1
else
    # works whatever the connect container is named (connect, connect-us/connect-europe in mdc, connect-0 in cfk)
    current_tag=$(get_running_cp_tag)
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
            # logwarn "skipping as plugin $owner/$name does not appear to be coming from confluent hub"
            continue
        fi

        # release notes under each version: Confluent plugins only, the others have no changelog feed
        with_changelog_flag=()
        if [ "$owner" == "confluentinc" ]
        then
            with_changelog_flag=(--with-changelog)
        fi
        playground connector-plugin versions --connector-plugin $owner/$name --last 5 "${with_changelog_flag[@]}"

        # latest
        latest=$(playground connector-plugin versions --connector-plugin $owner/$name --last 1)
        latest_to_compare=$(echo "$latest" | head -n 1 | sed 's/ ([0-9]* days ago)//')

        ## current version
        manifest_file="$root_folder/confluent-hub/$full_connector_name/manifest.json"
        if [ -f "$manifest_file" ]
        then
            version=$(jq -r '.version' "$manifest_file")
            release_date=$(jq -r '.release_date' "$manifest_file")
        else
            logwarn "file $manifest_file does not exist, could not retrieve version of $owner/$name"
            continue
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
            if [ "$owner" == "confluentinc" ]
            then
                log "📜 To see everything that changed since v$version: playground connector-plugin changelog --connector-plugin $owner/$name --from $version"
            fi
        fi 
    done
fi