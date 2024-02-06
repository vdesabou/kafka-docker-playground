connector="${args[--connector]}"

get_ccloud_connect

if [[ ! -n "$connector" ]]
then
    set +e
    connector=$(playground get-fully-managed-connector-list)
    if [ $? -ne 0 ]
    then
        logerror "❌ Could not get list of connectors"
        echo "$connector"
        exit 1
    fi
    if [ "$connector" == "" ]
    then
        logerror "💤 No ccloud connector is running !"
        exit 1
    fi
    set -e
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
    log "🛠️ Updating connector $connector"
    file=$tmp_dir/config-$connector.sh

    set +e
    echo "#!/bin/bash" > $file
    echo -e "" >> $file
    echo -e "##########################" >> $file
    echo "# this is the part to edit" >> $file
    playground fully-managed-connector show-config --connector "$connector" --no-clipboard | grep -v "Current config for connector" >> $file
    if [ $? -ne 0 ]
    then
        logerror "❌ playground fully-managed-connector show-config --connector $connector failed with:"
        cat $file
        exit 1
    fi
    set -e
    echo "# end of part to edit" >> $file
    echo -e "##########################" >> $file
    echo -e "" >> $file
    echo "exit 0" >> $file

    echo -e "" >> $file
    playground fully-managed-connector show-config-parameters --only-show-json --connector $connector  | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g" >> $file

    echo -e "" >> $file
    playground fully-managed-connector show-config-parameters --connector $connector  | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g" >> $file

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
