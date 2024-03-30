subject="${args[--subject]}"
schema="${args[--schema]}"
id="${args[--id]}"
verbose="${args[--verbose]}"

get_sr_url_and_security

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi
#log "tmp_dir is $tmp_dir"
schema_file=$tmp_dir/value_schema

if [ "$schema" = "-" ]
then
    schema_content=$(cat "$schema")
    echo "$schema_content" > $schema_file
else
    if [[ $schema == @* ]]
    then
        # this is a schema file
        argument_schema_file=$(echo "$schema" | cut -d "@" -f 2)
        cp $argument_schema_file $schema_file
    elif [ -f "$schema" ]
    then
        cp $schema $schema_file
    else
        schema_content=$schema
        echo "$schema_content" > $schema_file
    fi
fi

if grep -q "\"references\"\s*:" $schema_file
then
    :
elif grep -q "proto3" $schema_file
then
    log "🔮 schema was identified as protobuf"
    schema_type=PROTOBUF
elif grep -q "\"type\"\s*:\s*\"object\"" $schema_file
then
    log "🔮 schema was identified as json schema"
    schema_type=JSON
elif grep -q "\"type\"\s*:\s*\"record\"" $schema_file
then
    log "🔮 schema was identified as avro"
    schema_type=AVRO
else
    logerror "❌ no known schema could be identified"
    exit 1
fi

if grep -q "\"references\"\s*:" $schema_file
then
    log "🔮 schema was identified with references, sending as is"
    json_new=$(cat $schema_file | tr -d '\n' | tr -s ' ')
else
    json="{\"schemaType\":\"$schema_type\"}"
    content=$(cat $schema_file | tr -d '\n' | tr -s ' ')
    json_new=$(echo $json | jq --arg content "$content" '. + { "schema": $content }')
fi

if [[ -n "$id" ]]
then
    function set_back_read_write {
        set +e
        curl $sr_security --request PUT -s "${sr_url}/mode/${subject}" --header 'Content-Type: application/json' --data '{"mode": "READWRITE"}' > /dev/null 2>&1
        set -e
    }
    trap set_back_read_write EXIT

    log "Deleting 🫵 id ${id} for subject 🔰 ${subject} permanently"
    playground schema delete --subject "${subject}" --id ${id} --permanent > /dev/null 2>&1

    log "Setting mode to IMPORT"
    curl_output=$(curl $sr_security --request PUT -s "${sr_url}/mode/${subject}" --header 'Content-Type: application/json' --data '{"mode": "IMPORT"}' | jq .)
    ret=$?
    if [ $ret -eq 0 ]
    then
        if echo "$curl_output" | jq '. | has("error_code")' 2> /dev/null | grep -q true 
        then
            error_code=$(echo "$curl_output" | jq -r .error_code)
            if [ "$error_code" != "40403" ] && [ "$error_code" != "40401" ]
            then
                message=$(echo "$curl_output" | jq -r .message)
                logerror "Command failed with error code $error_code"
                logerror "$message"
                exit 1
            fi
        fi
    else
        logerror "❌ curl request failed with error code $ret!"
        exit 1
    fi
    echo "$curl_output"

    log "⏺️☢️ Registering schema to subject ${subject} with id $id"
    json_new_force_id=$(echo $json_new | jq --arg id "$id" '. + { "id": $id }')
    curl_output=$(curl $sr_security --request POST -s "${sr_url}/subjects/${subject}/versions" --header 'Content-Type: application/vnd.schemaregistry.v1+json' --data "$json_new_force_id" | jq .)
    ret=$?
    if [ $ret -eq 0 ]
    then
        if echo "$curl_output" | jq '. | has("error_code")' 2> /dev/null | grep -q true 
        then
            error_code=$(echo "$curl_output" | jq -r .error_code)
            if [ "$error_code" != "40403" ] && [ "$error_code" != "40401" ]
            then
                message=$(echo "$curl_output" | jq -r .message)
                logerror "Command failed with error code $error_code"
                logerror "$message"
                exit 1
            fi
        fi
    else
        logerror "❌ curl request failed with error code $ret!"
        exit 1
    fi
    echo "$curl_output"

    log "Setting mode to READWRITE"
    curl_output=$(curl $sr_security --request PUT -s "${sr_url}/mode/${subject}" --header 'Content-Type: application/json' --data '{"mode": "READWRITE"}' | jq .)
    ret=$?
    if [ $ret -eq 0 ]
    then
        if echo "$curl_output" | jq '. | has("error_code")' 2> /dev/null | grep -q true 
        then
            error_code=$(echo "$curl_output" | jq -r .error_code)
            if [ "$error_code" != "40403" ] && [ "$error_code" != "40401" ]
            then
                message=$(echo "$curl_output" | jq -r .message)
                logerror "Command failed with error code $error_code"
                logerror "$message"
                exit 1
            fi
        fi
    else
        logerror "❌ curl request failed with error code $ret!"
        exit 1
    fi
    echo "$curl_output"
    exit 0
fi

# check if schema already exists
# https://docs.confluent.io/platform/current/schema-registry/develop/api.html#post--subjects-(string-%20subject)
curl_output=$(curl $sr_security --request POST -s "${sr_url}/subjects/${subject}" \
--header 'Content-Type: application/vnd.schemaregistry.v1+json' \
--data "$json_new" | jq .)
ret=$?
if [ $ret -eq 0 ]
then
    if echo "$curl_output" | jq '. | has("error_code")' 2> /dev/null | grep -q true 
    then
        error_code=$(echo "$curl_output" | jq -r .error_code)
        if [ "$error_code" != "40403" ] && [ "$error_code" != "40401" ]
        then
            message=$(echo "$curl_output" | jq -r .message)
            logerror "Command failed with error code $error_code"
            logerror "$message"
            exit 1
        fi
    else
        id=$(echo "$curl_output" | jq -r .id)
        version=$(echo "$curl_output" | jq -r .version)
        log "🚪 Skipping as schema already exists with id $id (version $version)"
        exit 0
    fi
else
    logerror "❌ curl request failed with error code $ret!"
    exit 1
fi

log "⏺️ Registering schema to subject ${subject}"
if [[ -n "$verbose" ]]
then
    log "🐞 curl command used"
    echo "curl $sr_security --request POST -s "${sr_url}/subjects/${subject}/versions" --header 'Content-Type: application/vnd.schemaregistry.v1+json' --data "$json_new""
fi
curl $sr_security --request POST -s "${sr_url}/subjects/${subject}/versions" --header 'Content-Type: application/vnd.schemaregistry.v1+json' --data "$json_new" | jq .
