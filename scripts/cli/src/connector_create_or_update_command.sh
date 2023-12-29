json=${args[json]}
level=${args[--level]}
package=${args[--package]}
validate=${args[--validate]}
verbose="${args[--verbose]}"

environment=$(playground state get run.environment_before_switch)
if [ "$environment" = "" ]
then
    environment=$(playground state get run.environment)
fi

if [ "$environment" = "" ]
then
    environment="plaintext"
fi

if [ "$json" = "-" ]
then
    # stdin
    json_content=$(cat "$json")
else
    json_content=$json
fi

tmp_dir=$(mktemp -d -t ci-XXXXXXXXXX)
trap 'rm -rf $tmp_dir' EXIT
json_file=$tmp_dir/json

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

get_connect_url_and_security

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

if [[ -n "$validate" ]]
then
    log "✅ --validate is set"
    set +e
    connector_class=$(echo "$json_content" | jq -r '."connector.class"')
    add_connector_config_based_on_environment "$environment" "$json_content"
    # add mandatory name field
    new_json_content=$(echo $json_content | jq ". + {\"name\": \"$connector\"}")
    if [[ -n "$verbose" ]]
    then
        log "🐞 curl command used"
        echo "curl $security -s -X PUT -H "Content-Type: application/json" --data "$new_json_content" $connect_url/connector-plugins/$connector_class/config/validate"
    fi
    curl_output=$(curl $security -s -X PUT -H "Content-Type: application/json" --data "$new_json_content" $connect_url/connector-plugins/$connector_class/config/validate)
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

            is_valid=1
            rows=()
            for row in $(echo "$curl_output" | jq -r '.configs[] | @base64'); do
                _jq() {
                    echo ${row} | base64 --decode | jq -r ${1}
                }

                name=$(_jq '.value.name')
                value=$(_jq '.value.value')
                errors=$(_jq '.value.errors')

                if [ "$(echo "$errors" | jq 'length')" -gt 0 ]
                then
                    is_valid=0
                    logerror "❌ validation error for config <$name=$value>" 
                    echo "$errors" | jq .
                fi
            done

            if [ $is_valid -eq 1 ]
            then
                log "✅ connector config is valid !" 
            else
                exit 1
            fi
        fi
    else
        logerror "❌ curl request failed with error code $ret!"
        exit 1
    fi
fi

if [ $is_create == 1 ]
then
    log "🛠️ Creating connector $connector"
else
    log "🔄 Updating connector $connector"
fi

set +e

add_connector_config_based_on_environment "$environment" "$json_content"
if [[ -n "$verbose" ]]
then
    log "🐞 curl command used"
    echo "curl $security -s -X PUT -H "Content-Type: application/json" --data "$json_content" $connect_url/connectors/$connector/config"
fi
curl_output=$(curl $security -s -X PUT -H "Content-Type: application/json" --data "$json_content" $connect_url/connectors/$connector/config)
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
        else
            log "✅ Connector $connector was successfully updated"
        fi
        if [ -z "$GITHUB_RUN_NUMBER" ]
        then
            playground connector show-config --connector "$connector"
        fi
        log "🥁 Waiting a few seconds to get new status"
        sleep 8
        playground connector status --connector $connector
    fi
else
    logerror "❌ curl request failed with error code $ret!"
    exit 1
fi