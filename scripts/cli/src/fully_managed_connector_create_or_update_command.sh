json=${args[json]}
validate=${args[--validate]}
verbose="${args[--verbose]}"

get_ccloud_connect

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
if ! echo "$json_content" | jq -e . > /dev/null 2>&1
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

connector="${args[--connector]}"

is_create=1
connectors=$(playground get-fully-managed-connector-list)
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

    if [[ -n "$verbose" ]]
    then
        log "🐞 curl command used"
        echo "curl $security -s -X PUT -H "Content-Type: application/json" -H "authorization: Basic $authorization" --data @$json_file https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connector-plugins/$connector_class/config/validate"
    fi
    curl_output=$(curl $security -s -X PUT -H "Content-Type: application/json" -H "authorization: Basic $authorization" --data @$json_file https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connector-plugins/$connector_class/config/validate)

    ret=$?
    set -e
    if [ $ret -eq 0 ]
    then
        if echo "$curl_output" | jq 'if .error then .error | has("error_code") else has("error_code") end' 2> /dev/null | grep -q true 
        then
            if echo "$curl_output" | jq '.error | has("error_code")' 2> /dev/null | grep -q true 
            then
                code=$(echo "$curl_output" | jq -r .error.code)
                message=$(echo "$curl_output" | jq -r .error.message)
            else
                code=$(echo "$curl_output" | jq -r .error_code)
                message=$(echo "$curl_output" | jq -r .message)
            fi
            logerror "Command failed with error code $code"
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
if [[ -n "$verbose" ]]
then
    log "🐞 curl command used"
    echo "curl $security -s -X PUT -H "Content-Type: application/json" -H "authorization: Basic $authorization" --data @$json_file https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector/config"
fi
curl_output=$(curl $security -s -X PUT \
     -H "Content-Type: application/json" \
     -H "authorization: Basic $authorization" \
     --data @$json_file \
     https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector/config)

ret=$?
set -e
if [ $ret -eq 0 ]
then
    if echo "$curl_output" | jq 'if .error then .error | has("error_code") else has("error_code") end' 2> /dev/null | grep -q true 
    then
        if echo "$curl_output" | jq '.error | has("error_code")' 2> /dev/null | grep -q true 
        then
            code=$(echo "$curl_output" | jq -r .error.code)
            message=$(echo "$curl_output" | jq -r .error.message)
        else
            code=$(echo "$curl_output" | jq -r .error_code)
            message=$(echo "$curl_output" | jq -r .message)
        fi
        logerror "Command failed with error code $code"
        logerror "$message"
        exit 1
    else
        if [ $is_create == 1 ]
        then
            log "✅ Connector $connector was successfully created"
        else
            log "✅ Connector $connector was successfully updated"
        fi
        if [ -z "$GITHUB_RUN_NUMBER" ]
        then
            playground fully-managed-connector show-config --connector "$connector"
        fi
        playground fully-managed-connector show-config-parameters --connector "$connector" --only-show-json
        log "🥁 Waiting a few seconds to get new status"
        sleep 5
        playground fully-managed-connector status --connector $connector
    fi
else
    logerror "❌ curl request failed with error code $ret!"
    exit 1
fi