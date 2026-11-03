test_file=$(playground state get run.test_file)
only_show_url="${args[--only-show-url]}"

connector_type=$(playground state get run.connector_type)

if [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
then
    logerror "❌ connector open-docs command is not supported with $connector_type connector"
    exit 1
fi

if [ ! -f "$test_file" ]
then
    logerror "❌ File $test_file retrieved from $root_folder/playground.ini does not exist!"
    exit 1
fi

# fully managed: the README of every ccloud/fm-* example links the Confluent Cloud page of its connector
if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ]
then
    readme="$(dirname "$test_file")/README.md"
    short_url=""
    if [ -f "$readme" ]
    then
        short_url=$(grep -oE 'https://docs\.confluent\.io/cloud/current/connectors/cc-[^ )"#]*' "$readme" | head -1)
        if [ -z "$short_url" ]
        then
            short_url=$(grep -oE 'https://docs\.confluent\.io/cloud/current/connectors/[^ )"#]*' "$readme" | head -1)
        fi
    fi
    if [ -z "$short_url" ]
    then
        logerror "❌ documentation could not be retrieved: no Confluent Cloud connector page in $readme"
        exit 1
    fi
    if [[ -n "$only_show_url" ]] || ! can_open_url
    then
        log "🌐 documentation for $connector_type connector is available at:"
        echo "$short_url"
    else
        log "🌐 opening documentation for $connector_type connector $short_url"
        open_url "$short_url"
    fi
    # name@url entries separated by | and read word by word (connector update): no space in the name
    playground state set run.connector_docs_links "fully-managed@$short_url"
    exit 0
fi

get_connector_paths
if [ "$connector_paths" == "" ]
then
    logwarn "❌ skipping as $test_file is not an example with a connector plugin"
    exit 1
else
    doc_available=1
    doc_links=""
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
                if [[ -n "$only_show_url" ]] || ! can_open_url
                then
                    log "🌐 documentation for $connector_type connector $name is available at:"
                    echo "$short_url"
                    doc_links="${doc_links}|$name@$short_url"
                else
                    log "🌐 opening documentation for $connector_type connector $name $short_url"
                    open_url "$short_url"
                fi
            else
                doc_available=0
            fi
        else
            doc_available=0
        fi
    done
    if [ $doc_available -eq 0 ]
    then
        log "🌐 documentation could not be retrieved"

    else
        doc_links="${doc_links#|}"
        doc_links=$(echo "${doc_links}" | tr -d '${}')
        playground state set run.connector_docs_links "$doc_links"
    fi
fi