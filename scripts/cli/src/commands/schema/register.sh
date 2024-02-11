subject="${args[--subject]}"
schema="${args[--schema]}"
verbose="${args[--verbose]}"

get_sr_url_and_security

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
trap 'rm -rf $tmp_dir' EXIT
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

if grep -q "proto3" $schema_file
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

json="{\"schemaType\":\"$schema_type\"}"

content=$(cat $schema_file | tr -d '\n' | tr -s ' ')
json_new=$(echo $json | jq --arg content "$content" '. + { "schema": $content }')

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
