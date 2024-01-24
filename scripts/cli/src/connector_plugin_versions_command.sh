connector_plugin="${args[--connector-plugin]}"

if [[ $connector_plugin == *"@"* ]]
then
  connector_plugin=$(echo "$connector_plugin" | cut -d "@" -f 2)
fi

owner=$(echo "$connector_plugin" | cut -d "/" -f 1)
name=$(echo "$connector_plugin" | cut -d "/" -f 2)

log "💯 List all versions for connector plugin $connector_plugin"
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

        if [[ $(type -f bat 2>&1) =~ "not found" ]]
        then
            cat -n $json_file
        else
            bat $json_file --highlight-line $error_line
        fi

        exit 1
    fi

    while IFS= read -r row; do
        
        IFS=$'\n'
        arr=($(echo "$row" | jq -r '.version, .manifest_url, .release_date'))
        version="${arr[0]}"
        manifest_url="${arr[1]}"
        release_date="${arr[2]}"

        echo "$version 📅 $release_date"


    done <<< "$(echo "$curl_output" | jq -c '.[]')"
else
    logerror "❌ curl request failed with error code $ret!"
    exit 1
fi