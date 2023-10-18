subject="${args[--subject]}"
schema="${args[--input]}"
verbose="${args[--verbose]}"
replace="${args[--replace]}"

ret=$(get_sr_url_and_security)

sr_url=$(echo "$ret" | cut -d "@" -f 1)
sr_security=$(echo "$ret" | cut -d "@" -f 2)

tmp_dir=$(mktemp -d -t ci-XXXXXXXXXX)
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
    elif [ -f $schema ]
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
set -e
if [ $ret -eq 0 ]
then
    error_code=$(echo "$curl_output" | jq -r .error_code)
    if [ "$error_code" != "null" ]
    then
        if [ "$error_code" != "40403" ]
        then
            message=$(echo "$curl_output" | jq -r .message)
            logerror "Command failed with error code $error_code"
            logerror "$message"
            exit 1
        fi
    else
        id=$(echo "$curl_output" | jq -r .id)
        version=$(echo "$curl_output" | jq -r .version)

        if [[ -n "$replace" ]]
        then
            playground schema delete --subject $subject --version $version --permanent
            
        else
            log "🚪 Skipping as schema already exists with id $id (version $version)"
            exit 0
        fi
    fi
else
    logerror "❌ curl request failed with error code $ret!"
    exit 1
fi

log "⏺️ Registering schema to subject ${subject}"
if [[ -n "$verbose" ]]
then
    set -x
fi
curl $sr_security --request POST -s "${sr_url}/subjects/${subject}/versions" \
    --header 'Content-Type: application/vnd.schemaregistry.v1+json' \
    --data "$json_new" | jq .


# # trying workaround

# log "Hard delete schema id 1"
# curl -X DELETE -H "Content-Type: application/json" http://localhost:8081/subjects/customer_avro-value/versions/1
# curl -X DELETE -H "Content-Type: application/json" http://localhost:8081/subjects/customer_avro-value/versions/1?permanent=true

# # https://docs.confluent.io/platform/6.2.4/schema-registry/develop/api.html#put--mode-(string-%20subject)
# log "Set the subject to IMPORT mode"
# curl --request PUT \
#   --url http://localhost:8081/mode/customer_avro-value \
#   --header 'Content-Type: application/vnd.schemaregistry.v1+json' \
#   --data '{
#     "mode": "IMPORT"
# }'

# log "Re-register schema with id 1 and removing "default": {}"
# escaped_json=$(jq -c -Rs '.' producer-repro-120245/src/main/resources/avro/customer-without-default.avsc)
# cat << EOF > /tmp/final.json
# {"schema":$escaped_json,"version": "1","id":"1"}
# EOF
# curl -X POST http://localhost:8081/subjects/customer_avro-value/versions \
# --header 'Content-Type: application/vnd.schemaregistry.v1+json' \
# --data @/tmp/final.json


# log "Set back the subject to READWRITE"
# curl --request PUT \
#   --url http://localhost:8081/mode/customer_avro-value \
#   --header 'Content-Type: application/vnd.schemaregistry.v1+json' \
#   --data '{
#     "mode": "READWRITE"
# }'