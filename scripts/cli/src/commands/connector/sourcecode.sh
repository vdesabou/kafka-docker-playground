connector_tags="${args[--connector-tag]}"
only_show_url="${args[--only-show-url]}"
compile="${args[--compile]}"
compile_jdk_version="${args[--compile-jdk-version]}"
compile_verbose="${args[--compile-verbose]}"
enable_remote_debugging="${args[--enable-remote-debugging]}"
checkout_only="${args[--checkout-only]}"
grep_regex="${args[--grep]}"

# Convert space-separated string to array
IFS=' ' read -ra connector_tag_array <<< "$connector_tags"

test_file=$(playground state get run.test_file)

connector_type=$(playground state get run.connector_type)
if [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
then
    log "playground connector sourcecode command is not supported with $connector_type connector"
    exit 0
fi

if [ ! -f "$test_file" ]
then
    logerror "File $test_file retrieved from $root_folder/playground.ini does not exist!"
    exit 1
fi

maybe_only_show_url=""
if [[ -n "$only_show_url" ]]
then
    maybe_only_show_url="--only-show-url"
fi

# passed through to playground connector-plugin sourcecode (as an array, the regex may contain spaces)
passthrough_flags=()
if [[ -n "$checkout_only" ]]
then
    passthrough_flags+=(--checkout-only)
fi
if [[ -n "$grep_regex" ]]
then
    passthrough_flags+=(--grep "$grep_regex")
fi
# with 2 --connector-tag, --grep filters the commits between the two versions (connector-plugin sourcecode --log)
comparison_flags=()
if [[ -n "$checkout_only" ]] && ((${#connector_tag_array[@]} > 1))
then
    logwarn "--checkout-only is ignored when --connector-tag is set twice"
fi
if [[ -n "$grep_regex" ]]
then
    comparison_flags+=(--log --grep "$grep_regex")
fi

# Compile related optional flags
maybe_compile=""
if [[ -n "$compile" ]]; then
    maybe_compile="--compile"
    if [[ -n "$compile_jdk_version" ]]; then
        maybe_compile_jdk_version="--compile-jdk-version $compile_jdk_version"
    fi
    if [[ -n "$compile_verbose" ]]; then
        maybe_compile_verbose="--compile-verbose"
    fi
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
        [ "$connector_tag1" = "\\" ] && connector_tag1=" "
        connector_tag2="${connector_tag_array[1]}"
        [ "$connector_tag2" = "\\" ] && connector_tag2=" "
        playground connector-plugin sourcecode --connector-plugin "$owner/$name" --connector-tag "$connector_tag1" --connector-tag "$connector_tag2" $maybe_only_show_url "${comparison_flags[@]}"
    else
        if ((length == 1))
        then
            connector_tag="${connector_tag_array[0]}"
            [ "$connector_tag" = "\\" ] && connector_tag=" "
            playground connector-plugin sourcecode --connector-plugin "$owner/$name" --connector-tag "$connector_tag" $maybe_only_show_url "${passthrough_flags[@]}"
        else
            playground connector-plugin sourcecode --connector-plugin "$owner/$name" $maybe_only_show_url "${passthrough_flags[@]}"
        fi
    fi
    exit 0
fi

get_connector_paths
if [ "$connector_paths" == "" ]; then
    logwarn "❌ skipping as $test_file is not an example with a connector plugin"
    exit 1
fi

# Build list of eligible (hub) connector paths (exclude java/hub-components/filestream)
eligible_paths=()
for connector_path in ${connector_paths//,/ }; do
    full_connector_name=$(basename "$connector_path")
    owner=${full_connector_name%%-*}
    name=${full_connector_name#*-}
    if [ "$owner" == "java" ] || [ "$name" == "hub-components" ] || [ "$owner" == "filestream" ]; then
        continue
    fi
    eligible_paths+=("$connector_path")
done

if [ ${#eligible_paths[@]} -eq 0 ]; then
    logwarn "❌ no eligible hub connector found"
    exit 1
fi

chosen_path="${eligible_paths[0]}"
if [ ${#eligible_paths[@]} -gt 1 ]; then
    if [[ -n "$only_show_url" ]] || [[ -n "$checkout_only" ]] || [[ -n "$grep_regex" ]] || [ ! -t 0 ]
    then
        chosen_path="${eligible_paths[0]}"
        log "🔌 multiple connectors detected, using the first one: $(basename "$chosen_path")"
    else
        log "🔌 multiple connectors detected, please choose one"
        if command -v fzf >/dev/null 2>&1; then
            chosen_path=$(printf '%s\n' "${eligible_paths[@]}" | fzf --prompt="Select connector path: ")
        else
            PS3="Enter number of connector to use: "
            select cp in "${eligible_paths[@]}"; do
                if [ -n "$cp" ]; then chosen_path="$cp"; break; fi
            done
        fi
    fi
fi

full_connector_name=$(basename "$chosen_path")
owner=${full_connector_name%%-*}
name=${full_connector_name#*-}

length=${#connector_tag_array[@]}
if ((length > 1)); then
    if ((length > 2)); then
        logerror "❌ --connector-tag can only be set 2 times"
        exit 1
    fi
    if [[ -n "$compile" ]]; then
        logerror "❌ --compile does not work when --connector-tag is set twice"
        exit 1
    fi
    connector_tag1="${connector_tag_array[0]}"
    [ "$connector_tag1" = "\\" ] && connector_tag1=" "
    connector_tag2="${connector_tag_array[1]}"
    [ "$connector_tag2" = "\\" ] && connector_tag2=" "
    playground connector-plugin sourcecode --connector-plugin "$owner/$name" --connector-tag "$connector_tag1" --connector-tag "$connector_tag2" $maybe_only_show_url "${comparison_flags[@]}"
else
    if ((length == 1)); then
        connector_tag="${connector_tag_array[0]}"
        [ "$connector_tag" = "\\" ] && connector_tag=" "
        playground connector-plugin sourcecode --connector-plugin "$owner/$name" --connector-tag "$connector_tag" $maybe_only_show_url $maybe_compile $maybe_compile_jdk_version $maybe_compile_verbose "${passthrough_flags[@]}"
    else
        manifest_file="$root_folder/confluent-hub/$full_connector_name/manifest.json"
        if [ -f "$manifest_file" ]; then
            version=$(jq -r '.version' "$manifest_file")
            playground connector-plugin sourcecode --connector-plugin "$owner/$name" --connector-tag "$version" $maybe_only_show_url $maybe_compile $maybe_compile_jdk_version $maybe_compile_verbose "${passthrough_flags[@]}"
        else
            logerror "❌ file $manifest_file does not exist, could not retrieve version"
            exit 1
        fi
    fi
    if [[ -n "$compile" ]] && [[ -n "$enable_remote_debugging" ]]; then
        playground debug enable-remote-debugging --skip-vs-code-config-display
    fi
fi