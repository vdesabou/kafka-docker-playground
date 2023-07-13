ret=$(get_connect_url_and_security)

connect_url=$(echo "$ret" | cut -d "@" -f 1)
security=$(echo "$ret" | cut -d "@" -f 2)

connector="${args[--connector]}"

if [[ ! -n "$connector" ]]
then
    log "✨ --connector flag was not provided, applying command to all connectors"
    connector=$(playground get-connector-list)
    if [ "$connector" == "" ]
    then
        logerror "💤 No connector is running !"
        exit 1
    fi
fi

items=($connector)
for connector in ${items[@]}
do
    log "⏸️ Config connector $connector"
    json_config=$(curl $security -s -X GET -H "Content-Type: application/json" "$connect_url/connectors/$connector/config")
    connector_class=$(echo "$json_config" | jq -r '."connector.class"')

    set +e
    curl_output=$(curl $security -s -X PUT \
        -H "Content-Type: application/json" \
        --data "$json_config" \
        $connect_url/connector-plugins/$connector_class/config/validate)
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
        else

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

            # Build the table header
            header="| Parameter  | Group | Default Value | Required | Importance | Description |"
            divider=$(printf "| --%s-- | --%s-- | --%s-- | --%s-- | --%s-- | --%s-- |" $(printf '%.0s-' {1..9}))

            rows=""
            for row in $(echo "$curl_output" | jq -r '.configs[]| @base64'); do
                _jq() {
                echo ${row} | base64 --decode | jq -r ${1}
                }
                param=$(echo $(_jq '.definition.name'))
                group=$(echo $(_jq '.definition.group'))
                if [ "$group" == "Common" ] || [ "$group" == "Transforms" ] || [ "$group" == "Error Handling" ] || [ "$group" == "Topic Creation" ] || [ "$group" == "offsets.topic" ] || [ "$group" == "exactly.once.support" ] || [ "$group" == "Predicates" ]
                then
                    continue
                fi
                default=$(echo $(_jq '.definition.default_value'))
                required=$(echo $(_jq '.definition.required'))
                importance=$(echo $(_jq '.definition.importance'))
                description=$(echo $(_jq '.definition.documentation '))

                rows+="| $param | $group | $default | $required | $importance | $description |\n"
            done

            # Display the table
            echo -e "$header\n$divider\n$rows$divider"
        fi
    else
        logerror "❌ curl request failed with error code $ret!"
        exit 1
    fi

done
