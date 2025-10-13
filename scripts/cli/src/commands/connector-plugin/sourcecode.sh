connector_plugin="${args[--connector-plugin]}"
connector_tags="${args[--connector-tag]}"
only_show_url="${args[--only-show-url]}"

# Convert space-separated string to array
IFS=' ' read -ra connector_tag_array <<< "$connector_tags"

if [[ $connector_plugin == *"@"* ]]
then
  connector_plugin=$(echo "$connector_plugin" | cut -d "@" -f 2)
fi

if [ ! -f $root_folder/scripts/cli/confluent-hub-plugin-list.txt ]
then
    log "file $root_folder/scripts/cli/confluent-hub-plugin-list.txt not found. Generating it now, it may take a while..."
    playground generate-connector-plugin-list
fi

if [ ! -f $root_folder/scripts/cli/confluent-hub-plugin-list.txt ]
then
    logerror "❌ file $root_folder/scripts/cli/confluent-hub-plugin-list.txt could not be generated"
    exit 1
fi

is_fully_managed=0
if [[ "$connector_plugin" == *"confluentinc"* ]] && [[ "$connector_plugin" != *"-"* ]]
then
    log "🌥️ connector was identified as fully managed connector"
    is_fully_managed=1
fi

set +e
is_confluent_employee=0
output=$(grep "CONFLUENT EMPLOYEE VERSION" $root_folder/scripts/cli/confluent-hub-plugin-list.txt)
if [ $ret -eq 0 ]
then
    is_confluent_employee=1
else
    logerror "❌ playground connector-plugin sourcecode is not working with fully managed connectors"
    logerror "❌ if you're a Confluent employee, make sure your aws creds are set and then run <playground generate-connector-plugin-list>"
    exit 1
fi

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
    if [[ "$sourcecode_url" == *"confluentinc"* ]]
    then
        if [ $is_confluent_employee -eq 1 ]
        then
            logerror "❌ if you're a Confluent employee, make sure your aws creds are set and then run <playground generate-connector-plugin-list>"
            exit 1
        fi
    fi
    exit 1
fi

if [ $is_confluent_employee -eq 1 ] || [ $is_fully_managed -eq 1 ]
then
    connector_name_cache_versions=$(echo "$output" | cut -d "|" -f 3)
fi

function get_latest_version_from_cc_docker_connect_cache_versions_env () {
    tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
    if [ -z "$PG_VERBOSE_MODE" ]
    then
        trap 'rm -rf $tmp_dir' EXIT
    else
        log "🐛📂 not deleting tmp dir $tmp_dir"
    fi
    # confluent only
    cd $tmp_dir > /dev/null
    get_3rdparty_file "cache-versions.env" > /dev/null
    cd - > /dev/null
    if [ -f $tmp_dir/cache-versions.env ]
    then
        last_version=$(grep "$connector_name_cache_versions" $tmp_dir/cache-versions.env  | cut -d "=" -f 2)
        if [ $ret -eq 0 ]
        then
            log "✨ --connector-tag was not set, using latest version on cc-docker-connect (cache-versions.env file https://github.com/confluentinc/cc-docker-connect/blob/master/cc-connect/cache-versions.env) which is $last_version"
            connector_tag="$last_version"
        else
            logerror "❌ could not find $connector_name_cache_versions in $tmp_dir/cache-versions.env"
            exit 1
        fi
    else
        logerror "❌ file cache-versions.env could not be downloaded from s3 bucket"
        exit 1
    fi
}

function get_latest_version_from_confluent_hub () {
    output=$(playground connector-plugin versions --connector-plugin "$connector_plugin" --last 1 | head -n 1)
    last_version=$(echo "$output" | grep -v "<unknown>" | cut -d " " -f 2 | cut -d "v" -f 2)
    if [[ -n "$last_version" ]]
    then
        log "✨ --connector-tag was not set, using latest version on hub $last_version"
        connector_tag="$last_version"
    else
        logwarn "could not find latest version using <playground connector-plugin versions --connector-plugin \"$connector_plugin\" --last 1>"
        logerror "❌ --connector-tag flag is set 2 times, but one of them is set to latest. Comparison between version can only works when providing versions"
        exit 1
    fi
}

comparison_mode_versions=""
length=${#connector_tag_array[@]}
if ((length > 1))
then
    if ((length > 2))
    then
        logerror "❌ --connector-tag can only be set 2 times"
        exit 1
    fi
    if [[ "$sourcecode_url" != *"github.com"* ]]
    then
        logerror "❌ --connector-tag flag is set 2 times, but sourcecode is not hosted on github, comparison between version can only works with github"
        exit 1
    fi
    connector_tag1="${connector_tag_array[0]}"
    connector_tag2="${connector_tag_array[1]}"

    if [ "$connector_tag1" == "latest" ]
    then
        if [ $is_fully_managed -eq 1 ]
        then
            get_latest_version_from_cc_docker_connect_cache_versions_env
            connector_tag1=$connector_tag
        else
            get_latest_version_from_confluent_hub
            connector_tag1=$connector_tag
        fi
    fi
    if [ "$connector_tag2" == "latest" ]
    then
        if [ $is_fully_managed -eq 1 ]
        then
            get_latest_version_from_cc_docker_connect_cache_versions_env
            connector_tag2=$connector_tag
        else
            get_latest_version_from_confluent_hub
            connector_tag2=$connector_tag
        fi
    fi

    if [ "$connector_tag1" == "\\" ]
    then
        if [ $is_fully_managed -eq 1 ]
        then
            logerror "❌ --connector-tag set with \" \" cannot work when using fully managed connector plugin"
            exit 1
        fi
        ret=$(choose_connector_tag "$connector_plugin")
        connector_tag1=$(echo "$ret" | cut -d ' ' -f 2 | sed 's/^v//')
    fi

    if [ "$connector_tag2" == "\\" ]
    then
        if [ $is_fully_managed -eq 1 ]
        then
            logerror "❌ --connector-tag set with \" \" cannot work when using fully managed connector plugin"
            exit 1
        fi
        ret=$(choose_connector_tag "$connector_plugin")
        connector_tag2=$(echo "$ret" | cut -d ' ' -f 2 | sed 's/^v//')
    fi
    log "✨ --connector-tag flag is set 2 times, comparison mode will be opened with versions v$connector_tag1 and v$connector_tag2"
    comparison_mode_versions="v$connector_tag1...v$connector_tag2"
else
    connector_tag="${connector_tag_array[0]}"
    if [[ -n "$connector_tag" ]]
    then
        if [ "$connector_tag" == "\\" ]
        then
            if [ $is_fully_managed -eq 1 ]
            then
                logerror "❌ --connector-tag set with \" \" cannot work when using fully managed connector plugin"
                exit 1
            fi
            ret=$(choose_connector_tag "$connector_plugin")
            connector_tag=$(echo "$ret" | cut -d ' ' -f 2 | sed 's/^v//')
        fi
    else
        if [ $is_fully_managed -eq 0 ]
        then
            output=$(playground connector-plugin versions --connector-plugin "$connector_plugin" --last 1 | head -n 1)
            last_version=$(echo "$output" | grep -v "<unknown>" | cut -d " " -f 2 | cut -d "v" -f 2)
            if [[ -n "$last_version" ]]
            then
                log "✨ --connector-tag was not set, using latest version on hub $last_version"
                connector_tag="$last_version"
            else
                logwarn "could not find latest version using <playground connector-plugin versions --connector-plugin \"$connector_plugin\" --last 1>, using latest"
                connector_tag="latest"
            fi
        else
            get_latest_version_from_cc_docker_connect_cache_versions_env
        fi
    fi
fi

if [ "$comparison_mode_versions" != "" ]
then
    additional_text=", comparing v$connector_tag1 and v$connector_tag2"
    sourcecode_url="$sourcecode_url/compare/$comparison_mode_versions"
else
    additional_text=" for $connector_tag version"
    if [ "$connector_tag" != "latest" ] && [[ "$sourcecode_url" == *"github.com"* ]]
    then
        sourcecode_url="$sourcecode_url/tree/v$connector_tag"
    fi
fi

if [[ -n "$only_show_url" ]] || [[ $(type -f open 2>&1) =~ "not found" ]]
then
    log "🧑‍💻🌐 sourcecode for plugin $connector_plugin$additional_text is available at:"
    echo "$sourcecode_url"
else
    log "🧑‍💻 Opening sourcecode url $sourcecode_url for plugin $connector_plugin in browser$additional_text"
    open "$sourcecode_url"
fi