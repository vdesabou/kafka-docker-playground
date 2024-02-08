connector="${args[--connector]}"

connector_type=$(playground state get run.connector_type)

if [[ ! -n "$connector" ]]
then
    connector=$(playground get-connector-list)
    if [ "$connector" == "" ]
    then
        logerror "💤 No $connector_type connector is running !"
        exit 1
    fi
fi

tmp_dir=$(mktemp -d -t ci-XXXXXXXXXX)
trap 'rm -rf $tmp_dir' EXIT

items=($connector)
length=${#items[@]}
if ((length > 1))
then
    log "✨ --connector flag was not provided, applying command to all connectors"
fi
for connector in ${items[@]}
do
    log "🛠️ Updating $connector_type connector $connector"
    file=$tmp_dir/config-$connector.sh

    set +e
    echo "#!/bin/bash" > $file
    echo -e "" >> $file
    echo -e "##########################" >> $file
    echo "# this is the part to edit" >> $file
    playground connector show-config --connector "$connector" --no-clipboard | grep -v "Current config for" >> $file
    if [ $? -ne 0 ]
    then
        logerror "❌ playground connector show-config --connector $connector failed with:"
        cat $file
        exit 1
    fi
    set -e
    echo "# end of part to edit" >> $file
    echo -e "##########################" >> $file
    echo -e "" >> $file
    echo "exit 0" >> $file

    echo -e "" >> $file
    docs_links=$(playground state get run.connector_docs_links)
    if [ "$docs_links" != "" ]
    then
        for docs_link in $(echo "${docs_links}" | tr '|' ' ')
        do
            name=$(echo "$docs_link" | cut -d "@" -f 1)
            url=$(echo "$docs_link" | cut -d "@" -f 2)
            echo "🌐⚡ documentation for $connector_type connector $name is available at:" >> $file
            echo "$url" >> $file
        done
    else
        playground connector open-docs --only-show-url | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g" >> $file
    fi

    echo -e "" >> $file
    playground connector show-config-parameters --connector $connector  | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g" >> $file

    editor=$(playground config get editor)
    if [ "$editor" != "" ]
    then
        log "✨ Update the connector config as per your needs, save and close the file to continue"
        if [ "$editor" = "code" ]
        then
            code --wait $file
        else
            $editor $file
        fi
    else
        if [[ $(type code 2>&1) =~ "not found" ]]
        then
            logerror "Could not determine an editor to use as default code is not found - you can change editor by using playground config editor <editor>"
            exit 1
        else
            log "✨ Update the connector config as per your needs, save and close the file to continue"
            code --wait $file
        fi
    fi

    bash $file
done
