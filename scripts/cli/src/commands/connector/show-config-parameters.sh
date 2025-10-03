connector="${args[--connector]}"
open="${args[--open]}"
force_refresh="${args[--force-refresh]}"
only_show_file_path="${args[--only-show-file-path]}"
only_show_json="${args[--only-show-json]}"
only_show_json_file_path="${args[--only-show-json-file-path]}"
verbose="${args[--verbose]}"

connector_type=$(playground state get run.connector_type)

if [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
then
    log "connector show-config-parameters command is not supported with $connector_type connector"
    exit 0
fi

if [[ ! -n "$connector" ]]
then
    connector=$(playground get-connector-list)
    if [ "$connector" == "" ]
    then
        log "💤 No $connector_type connector is running !"
        exit 1
    fi
fi

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi
json_file=$tmp_dir/connector.json

items=($connector)
length=${#items[@]}
if ((length > 1))
then
    log "✨ --connector flag was not provided, applying command to all connectors"
fi
for connector in "${items[@]}"
do
    if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
    then
        get_ccloud_connect
        handle_ccloud_connect_rest_api "curl -s --request GET \"https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector/config\" --header \"authorization: Basic $authorization\""
    else
        get_connect_url_and_security
        handle_onprem_connect_rest_api "curl $security -s -X GET -H \"Content-Type: application/json\" \"$connect_url/connectors/$connector/config\""
    fi

    echo "$curl_output" > $json_file

    connector_class=$(echo "$curl_output" | jq -r '."connector.class"')
    class=$(echo $connector_class | rev | cut -d '.' -f 1 | rev)

    version="unknown"
    if [ "$connector_type" == "$CONNECTOR_TYPE_ONPREM" ] || [ "$connector_type" == "$CONNECTOR_TYPE_SELF_MANAGED" ]
    then
        get_connect_url_and_security
        handle_onprem_connect_rest_api "curl $security -s -X GET -H \"Content-Type: application/json\" $connect_url/connector-plugins/"
        for row in $(echo "$curl_output" | jq -r '.[] | @base64'); do
            _jq() {
                echo ${row} | base64 -d | jq -r ${1}
            }

            class=$(_jq '.class')

            if [ "$class" == "$connector_class" ]
            then
                version=$(_jq '.version')
                break
            fi
        done
    fi

	if [ -z "$GITHUB_RUN_NUMBER" ]
	then
		mkdir -p $root_folder/.connector_config
		filename="$root_folder/.connector_config/config-$connector_class-$version.txt"
		json_filename="$root_folder/.connector_config/config-$connector_class-$version.json"
	else
		test_file=$(playground state get run.test_file)
		if [ ! -f $test_file ]
		then 
			logerror "File $test_file retrieved from $root_folder/playground.ini does not exist!"
			exit 1
		fi

		folder_of_test_file=$(dirname "$test_file")
		filename="$folder_of_test_file/config-$connector_class.txt"
		json_filename="$folder_of_test_file/config-$connector_class.json"
	fi

    if [[ ! -n "$only_show_json_file_path" ]]
    then
        if [[ -n "$only_show_json" ]]
        then
            log "🔩 list of all available parameters for $connector_type connector $connector ($class) and version $version (with default value when applicable)"
        else
            log "🔩 getting parameters for $connector_type connector $connector ($class) and version $version"
        fi
    fi

    if [[ -n "$force_refresh" ]] || [ ! -z "$GITHUB_RUN_NUMBER" ]
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
        if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
        then
            get_ccloud_connect
            handle_ccloud_connect_rest_api "curl -s --request PUT -H \"Content-Type: application/json\" --data @$json_file \"https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connector-plugins/$connector_class/config/validate\" --header \"authorization: Basic $authorization\""
        else
            get_connect_url_and_security
            handle_onprem_connect_rest_api "curl $security -s -X PUT -H \"Content-Type: application/json\" --data @$json_file $connect_url/connector-plugins/$connector_class/config/validate"
        fi

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

    if [ ! -f $filename ]
    then
        logwarn "❌ there was no specific config for this $connector_type connector"
        exit 0
    fi

    if [[ -n "$open" ]]
    then
        if [[ -n "$only_show_json" ]]
        then
            filename=$json_filename
        else
            cat $filename > "/tmp/config-$connector_class-$version.txt"
            filename="/tmp/config-$connector_class-$version.txt"
            cat $json_filename >> $filename
            echo "🔩 list of all available parameters for connector $connector ($class) and version $version (with default value when applicable)" >> $filename
        fi

        playground open --file "${filename}"
    else
        if [[ -n "$only_show_json" ]] || [[ -n "$only_show_json_file_path" ]]
        then
            if [[ -n "$only_show_json_file_path" ]]
            then
                echo "$json_filename"
            else
                cat $json_filename
            fi
            return
        fi

        if [[ -n "$only_show_file_path" ]]
        then
            echo "$filename"
        else
            cat $filename
            log "🔩 list of all available parameters for $connector_type connector $connector ($class) and version $version (with default value when applicable)"
            cat $json_filename
        fi
    fi
done