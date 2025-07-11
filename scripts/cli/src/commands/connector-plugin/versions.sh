connector_plugin="${args[--connector-plugin]}"
last="${args[--last]}"
force_refresh="${args[--force-refresh]}"

if [[ $connector_plugin == *"@"* ]]
then
  connector_plugin=$(echo "$connector_plugin" | cut -d "@" -f 2)
fi

owner=$(echo "$connector_plugin" | cut -d "/" -f 1)
name=$(echo "$connector_plugin" | cut -d "/" -f 2)

filename="/tmp/version_$owner_$name"
if [[ -n "$force_refresh" ]]
then
    if [ -f $filename ]
    then
        rm -f $filename
    fi
fi

if [[ -n "$last" ]]
then
    if [ "$last" != "1" ]
    then
        log "💯 Listing last $last versions for connector plugin $connector_plugin"
    fi
else
    log "💯 Listing all versions for connector plugin $connector_plugin"
fi

if [ ! -f $filename ]
then
    curl_output=$(curl -s https://api.hub.confluent.io/api/plugins/$owner/$name/versions)
    ret=$?
    set -e
    if [ $ret -eq 0 ]
    then
        if ! echo "$curl_output" | jq -e .  > /dev/null 2>&1
        then
            set +e
            json_file=/tmp/json
            echo "$curl_output" > $json_file
            jq_output=$(jq . "$json_file" 2>&1)
            error_line=$(echo "$jq_output" | grep -oE 'parse error.*at line [0-9]+' | grep -oE '[0-9]+')

            if [[ -n "$error_line" ]]; then
                logerror "❌ Invalid JSON at line $error_line"
            fi
            set -e

            if [ -z "$GITHUB_RUN_NUMBER" ]
            then
                if [[ $(type -f bat 2>&1) =~ "not found" ]]
                then
                    cat -n $json_file
                else
                    bat $json_file --highlight-line $error_line
                fi
            fi
            exit 1
        fi

        if [ "$curl_output" == "[]" ]
        then
            logwarn "❌ could not get versions for connector plugin $connector_plugin"
            exit 0
        fi

        if [[ "$(uname)" == "Darwin" ]]; then
            # macOS
            current_date=$(date -j -f "%Y-%m-%d" "$(date "+%Y-%m-%d")" "+%s")
        else
            # Linux
            current_date=$(date +%s)
        fi
        while IFS= read -r row; do
            IFS=$'\n'
            arr=($(echo "$row" | jq -r '.version, .manifest_url, .release_date'))
            version="${arr[0]}"
            manifest_url="${arr[1]}"
            release_date="${arr[2]}"
            if [ "$release_date" != "null" ]
            then
                if [[ "$(uname)" == "Darwin" ]]; then
                    # macOS
                    release_date_sec=$(date -j -f "%Y-%m-%d" "$release_date" "+%s")
                else
                    # Linux
                    release_date_sec=$(date -d "$release_date" "+%s")
                fi

                # Calculate the difference in days
                diff=$(( (current_date - release_date_sec) / 60 / 60 / 24 ))
                echo "🔢 v$version - 📅 release date: $release_date ($diff days ago)" >> $filename
            else
                echo "🔢 v$version - 📅 release date: <unknown>" >> $filename
            fi
        done <<< "$(echo "$curl_output" | jq -c '.[]')"

        # documentation_url
        set +e
        curl_output=$(curl -s $manifest_url)
        ret=$?
        if [ $ret -eq 0 ]
        then
            documentation_url=$(echo "$curl_output" | jq -r '.documentation_url')
        fi
        set -e
        if [[ -n "$documentation_url" && "$documentation_url" != "null" ]]
        then
            echo "🌐 documentation: $documentation_url" >> $filename
        else
            echo "🌐 documentation: <not available>" >> $filename
        fi
    else
        logerror "❌ curl request failed with error code $ret!"
        exit 1
    fi

    if [ ! -f $filename ]
    then
        logerror "❌ could not get versions for connector plugin $connector_plugin"
        exit 1
    fi
fi

if [[ -n "$last" ]]
then
    last=$((last + 1))
    tail -${last} $filename
else
    cat $filename
fi