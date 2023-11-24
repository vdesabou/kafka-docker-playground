open="${args[--open]}"
force_refresh="${args[--force-refresh]}"
only_show_file_path="${args[--only-show-file-path]}"

get_connect_url_and_security

connector="${args[--connector]}"

if [[ ! -n "$connector" ]]
then
    connector=$(playground get-connector-list)
    if [ "$connector" == "" ]
    then
        logerror "💤 No connector is running !"
        exit 1
    fi
fi

items=($connector)
length=${#items[@]}
if ((length > 1))
then
    log "✨ --connector flag was not provided, applying command to all connectors"
fi
for connector in ${items[@]}
do
    json_config=$(curl $security -s -X GET -H "Content-Type: application/json" "$connect_url/connectors/$connector/config")
    connector_class=$(echo "$json_config" | jq -r '."connector.class"')
    version="unknown"
    set +e
    curl_output=$(curl $security -s -X GET \
        -H "Content-Type: application/json" \
        $connect_url/connector-plugins/)
    ret=$?
    set -e
    if [ $ret -eq 0 ]
    then
        current_group=""
        rows=()
        for row in $(echo "$curl_output" | jq -r '.[] | @base64'); do
            _jq() {
                echo ${row} | base64 --decode | jq -r ${1}
            }

            class=$(_jq '.class')

            if [ "$class" != "$connector_class" ]
            then
                version=$(_jq '.version')
            fi
        done
    else
        logerror "❌ curl request failed with error code $ret!"
        exit 1
    fi

    filename="/tmp/config-$connector_class-$version.txt"

    class=$(echo $connector_class | rev | cut -d '.' -f 1 | rev)
    log "🔩 getting parameters for connector $connector ($class) and version $version"

    if [[ -n "$force_refresh" ]]
    then
        if [ -f $filename ]
        then
            rm -f $filename
        fi
    fi
    if [ ! -f $filename ]
    then
        set +e
        curl_output=$(curl $security -s -X PUT \
            -H "Content-Type: application/json" \
            --data "$json_content" \
            $connect_url/connector-plugins/$connector_class/config/validate)
        ret=$?
        set -e
        if [ $ret -eq 0 ]
        then
            if echo "$curl_output" | jq '. | has("error_code")' 2> /dev/null | grep -q true 
            then
                error_code=$(echo "$curl_output" | jq -r .error_code)
                message=$(echo "$curl_output" | jq -r .message)
                logerror "Command failed with error code $error_code"
                logerror "$message"
                exit 1
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
                        echo -e "==========================" >> $filename
                        echo -e "$group"                     >> $filename
                        echo -e "==========================" >> $filename
                        current_group=$group
                    fi

                    param=$(_jq '.definition.name')
                    default=$(_jq '.definition.default_value')
                    type=$(_jq '.definition.type')
                    required=$(_jq '.definition.required')
                    importance=$(_jq '.definition.importance')
                    description=$(_jq '.definition.documentation')

                    echo -e "🔘 $param" >> $filename
                    echo -e "" >> $filename
                    echo -e "$description" >> $filename
                    echo -e "" >> $filename
                    echo -e "\t - Type: $type" >> $filename
                    echo -e "\t - Default: $default" >> $filename
                    echo -e "\t - Importance: $importance" >> $filename
                    echo -e "\t - Required: $required" >> $filename
                    echo -e "" >> $filename
                done
            fi
        else
            logerror "❌ curl request failed with error code $ret!"
            exit 1
        fi
    fi

    if [[ -n "$open" ]]
    then
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
    else
        if [[ -n "$only_show_file_path" ]]
        then
            echo "$filename"
        else
            cat $filename
        fi
    fi
done