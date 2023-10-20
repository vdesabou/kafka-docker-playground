json=${args[json]}
level=${args[--level]}
package=${args[--package]}

if [ "$json" = "-" ]
then
    # stdin
    json_content=$(cat "$json")
else
    json_content=$json
fi

json_file=/tmp/json
trap 'rm -f /tmp/json' EXIT
echo "$json_content" > $json_file

# JSON is invalid
if ! echo "$json_content" | jq -e .  > /dev/null 2>&1
then
    set +e
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

ret=$(get_connect_url_and_security)

connect_url=$(echo "$ret" | cut -d "@" -f 1)
security=$(echo "$ret" | cut -d "@" -f 2)

connector="${args[--connector]}"

is_create=1
connectors=$(playground get-connector-list)
items=($connectors)
for con in ${items[@]}
do
    if [[ "$con" == "$connector" ]]
    then
        is_create=0
    fi
done

if [ $is_create == 1 ]
then
    log "🛠️ Creating connector $connector"
else
    log "🔄 Updating connector $connector"
fi

set +e
curl_output=$(curl $security -s -X PUT \
     -H "Content-Type: application/json" \
     --data "$json_content" \
     $connect_url/connectors/$connector/config)
ret=$?
set -e
if [ $ret -eq 0 ]
then
    error_code=$(echo "$curl_output" | jq -r .error_code)
    if [ "$error_code" != "null" ]
    then
        message=$(echo "$curl_output" | jq -r .message)
        logerror "Command failed with error code $error_code"
        logerror "$message"
        exit 1
    else
        if [[ -n "$level" ]]
        then
            if [[ -n "$package" ]]
            then
                playground debug log-level set --level $level --package $package
            else
                playground connector log-level --connector $connector --level $level
            fi
        fi
        if [ $is_create == 1 ]
        then
            log "✅ Connector $connector was successfully created"
            if [ -z "$GITHUB_RUN_NUMBER" ]
            then
                log "💈 Configuration is "
                echo "$json_content" | jq -S .
            fi
            log "🥁 Waiting a few seconds to get new status"
        else
            log "✅ Connector $connector was successfully updated"
            if [ -z "$GITHUB_RUN_NUMBER" ]
            then
                log "💈 Configuration is "
                echo "$json_content" | jq -S .
            fi
            log "🥁 Waiting a few seconds to get new status"
        fi
        sleep 8
        playground connector status --connector $connector
    fi
else
    logerror "❌ curl request failed with error code $ret!"
    exit 1
fi