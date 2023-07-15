open="${args[--open]}"

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
    json_config=$(curl $security -s -X GET -H "Content-Type: application/json" "$connect_url/connectors/$connector/config")
    connector_class=$(echo "$json_config" | jq -r '."connector.class"')

    class=$(echo $connector_class | rev | cut -d '.' -f 1 | rev)
    log "🔩 parameters for connector $connector ($class)"
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

            if [[ -n "$open" ]]
            then
                filename="/tmp/config-$connector.txt"
            fi
            current_group=""
            rows=()
            for row in $(echo "$curl_output" | jq -r '.configs[] | @base64'); do
                _jq() {
                    echo ${row} | base64 --decode | jq -r ${1}
                }

                group=$(_jq '.definition.group')
                if [[ "$group" == "Common" || "$group" == "Transforms" || "$group" == "Error Handling" || "$group" == "Topic Creation" || "$group" == "offsets.topic" || "$group" == "Exactly Once Support" || "$group" == "Predicates" || "$group" == "Confluent Licensing" ]] ; then
                    continue
                fi

                if [ "$group" != "$current_group" ]
                then
                    if [[ -n "$open" ]]
                    then
                        echo -e "==========================" > $filename
                        echo -e "$group"                     >> $filename
                        echo -e "==========================" >> $filename
                    else
                        echo -e "=========================="
                        echo -e "$group"
                        echo -e "=========================="
                    fi
                    current_group=$group
                fi

                param=$(_jq '.definition.name')
                default=$(_jq '.definition.default_value')
                type=$(_jq '.definition.type')
                required=$(_jq '.definition.required')
                importance=$(_jq '.definition.importance')
                description=$(_jq '.definition.documentation')

                if [[ -n "$open" ]]
                then
                    echo -e "🔘 $param" >> $filename
                    echo -e "" >> $filename
                    echo -e "$description" >> $filename
                    echo -e "" >> $filename
                    echo -e "\t - Type: $type" >> $filename
                    echo -e "\t - Default: $default" >> $filename
                    echo -e "\t - Importance: $importance" >> $filename
                    echo -e "\t - Required: $required" >> $filename
                    echo -e "" >> $filename
                else
                    echo -e "🔘 $param"
                    echo -e ""
                    echo -e "$description"
                    echo -e ""
                    echo -e "\t - Type: $type"
                    echo -e "\t - Default: $default"
                    echo -e "\t - Importance: $importance"
                    echo -e "\t - Required: $required"
                    echo -e ""
                fi
            done
        fi
    else
        logerror "❌ curl request failed with error code $ret!"
        exit 1
    fi

    if [[ -n "$open" ]]
    then
        filename="/tmp/config-$connector.txt"
        if config_has_key "editor"
        then
            editor=$(config_get "editor")
        log "📖 Opening ${filename} using configured editor $editor"
        $editor $filename
        else
            if [[ $(type code 2>&1) =~ "not found" ]]
            then
            logerror "Could not determine an editor to use as default code is not found - you can change editor by updating config.ini"
            exit 1
            else
            log "📖 Opening ${filename} with code (default) - you can change editor by updating config.ini"
            code $filename
            fi
        fi
    fi
done