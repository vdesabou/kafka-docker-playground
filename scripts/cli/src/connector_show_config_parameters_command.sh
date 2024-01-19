connector="${args[--connector]}"
open="${args[--open]}"
force_refresh="${args[--force-refresh]}"
only_show_file_path="${args[--only-show-file-path]}"
only_show_json="${args[--only-show-json]}"
verbose="${args[--verbose]}"

get_connect_url_and_security

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
    curl_output=$(curl $security -s -X GET -H "Content-Type: application/json" "$connect_url/connectors/$connector/config")
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
            connector_class=$(echo "$curl_output" | jq -r '."connector.class"')
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

            mkdir -p $root_folder/.connector_config
            filename="$root_folder/.connector_config/config-$connector_class-$version.txt"
            json_filename="$root_folder/.connector_config/config-$connector_class-$version.json"

            class=$(echo $connector_class | rev | cut -d '.' -f 1 | rev)

            if [[ -n "$only_show_json" ]]
            then
                log "🔩 list of all available parameters for connector $connector ($class) and version $version (with default value when applicable)"
            else
                log "🔩 getting parameters for connector $connector ($class) and version $version"
            fi

            if [[ -n "$force_refresh" ]]
            then
                if [ -f $filename ]
                then
                    rm -f $filename
                fi
                if [ -f $json_filename ]
                then
                    rm -f $json_filename
                fi
            fi
            if [ ! -f $filename ] || [ ! -f $json_filename ]
            then
                set +e
                if [[ -n "$verbose" ]]
                then
                    log "🐞 curl command used"
                    echo "curl $security -s -X PUT -H "Content-Type: application/json" --data "$json_config" $connect_url/connector-plugins/$connector_class/config/validate"
                fi
                curl_output=$(curl $security -s -X PUT -H "Content-Type: application/json" --data "$json_config" $connect_url/connector-plugins/$connector_class/config/validate)
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
                        configs=$(echo "$curl_output" | jq -r '.configs')
                        while IFS= read -r row; do
                            
                            IFS=$'\n'
                            arr=($(echo "$row" | jq -r '.definition.group, .definition.name, .definition.default_value, .definition.type, .definition.required, .definition.importance, .definition.documentation'))
                            group="${arr[0]}"
                                                set +x
                            if [[ "$group" == "Common" || "$group" == "Transforms" || "$group" == "Error Handling" || "$group" == "Topic Creation" || "$group" == "offsets.topic" || "$group" == "Exactly Once Support" || "$group" == "Predicates" || "$group" == "Confluent Licensing" ]] ; then
                                continue
                            fi

                            if [ "$group" != "$current_group" ]
                            then
                                echo -e "==========================" >> "$filename"
                                echo -e "$group"                     >> "$filename"
                                echo -e "==========================" >> "$filename"
                                current_group=$group
                            fi

                            param="${arr[1]}"
                            default="${arr[2]}"
                            type="${arr[3]}"
                            required="${arr[4]}"
                            importance="${arr[5]}"
                            description="${arr[6]}"

                            echo -e "🔘 $param" >> "$filename"
                            echo -e "" >> "$filename"
                            echo -e "$description" >> "$filename"
                            echo -e "" >> "$filename"
                            echo -e "\t - Type: $type" >> "$filename"
                            echo -e "\t - Default: $default" >> "$filename"
                            echo -e "\t - Importance: $importance" >> "$filename"
                            echo -e "\t - Required: $required" >> "$filename"
                            echo -e "" >> "$filename"

                            if [ "$default" == "null" ]
                            then
                                default=""
                            fi
                            echo -e "    \"$param\": \"$default\"," >> "$json_filename"
                            sort "$json_filename" -o /tmp/tmp
                            mv /tmp/tmp "$json_filename"
                        done <<< "$(echo "$configs" | jq -c '.[]')"
                    fi
                else
                    logerror "❌ curl request failed with error code $ret!"
                    exit 1
                fi
            fi

            if [[ -n "$open" ]]
            then
                if [[ -n "$only_show_json" ]]
                then
                    filename=$json_filename
                else
                    cat $filename > "/tmp/config-$connector_class-$version.txt"
                    filename="/tmp/config-$connector_class-$version.txt"
                    echo "🔩 list of all available parameters for connector $connector ($class) and version $version (with default value when applicable)" >> $filename
                    cat $json_filename >> $filename
                fi

                editor=$(playground config get editor)
                if [ "$editor" != "" ]
                then
                    log "📖 Opening ${filename} using configured editor $editor"
                    $editor ${filename}
                else
                    if [[ $(type code 2>&1) =~ "not found" ]]
                    then
                        logerror "Could not determine an editor to use as default code is not found - you can change editor by using playground config editor <editor>"
                        exit 1
                    else
                        log "📖 Opening ${filename} with code (default) - you can change editor by using playground config editor <editor>"
                        code ${filename}
                    fi
                fi
            else
                if [[ -n "$only_show_json" ]]
                then
                    cat $json_filename
                    return
                fi

                if [[ -n "$only_show_file_path" ]]
                then
                    echo "$filename"
                else
                    cat $filename
                    log "🔩 list of all available parameters for connector $connector ($class) and version $version (with default value when applicable)"
                    cat $json_filename
                fi
            fi
        fi
    else
        logerror "❌ curl request failed with error code $ret!"
        exit 1
    fi
done