connector_plugin="${args[--connector-plugin]}"
connector_tag="${args[--connector-tag]}"

if [[ $connector_plugin == *"@"* ]]
then
  connector_plugin=$(echo "$connector_plugin" | cut -d "@" -f 2)
fi

if [[ -n "$connector_tag" ]]
then
    if [ "$connector_tag" == " " ]
    then
        ret=$(choose_connector_tag "$connector_plugin")
        connector_tag=$(echo "$ret" | cut -d ' ' -f 2 | sed 's/^v//')
    fi
else
    connector_tag="latest"
fi

if [ ! -f $root_folder/scripts/cli/confluent-hub-plugin-list.txt ]
then
    log "file $root_folder/scripts/cli/confluent-hub-plugin-list.txt not found. Generating it now, it may take a while..."
    playground generate-connector-plugin-list
fi

if [ ! -f $root_folder/scripts/cli/confluent-hub-plugin-list.txt ]
then
    logerror "file $root_folder/scripts/cli/confluent-hub-plugin-list.txt could not be generated"
    exit 1
fi

set +e
output=$(grep "$connector_plugin|" $root_folder/scripts/cli/confluent-hub-plugin-list.txt)
ret=$?
set -e
if [ $ret -ne 0 ]
then
    logerror "❌ could not found $connector_plugin in $root_folder/scripts/cli/confluent-hub-plugin-list.txt"
    exit 1
fi

sourcecode_url=$(echo "$output" | cut -d "|" -f 2)
if [ "$sourcecode_url" == "null" ] || [ "$sourcecode_url" == "" ]
then
    logerror "❌ could not found sourcecode url for plugin $connector_plugin. It is probably proprietary"
    exit 1
fi

if [ "$connector_tag" != "latest" ] && [[ "$sourcecode_url" == *"github.com"* ]]
then
    sourcecode_url="$sourcecode_url/tree/v$connector_tag"
fi

if [[ $(type -f open 2>&1) =~ "not found" ]]
then
    log "🔗 Cannot open browser, use url:"
    echo "$sourcecode_url"
else
    log "🧑‍💻🌐 Openening sourcecode url $sourcecode_url for plugin $connector_plugin in browser for $connector_tag version"
    open "$sourcecode_url"
fi