subject="${args[--subject]}"
schema="${args[--input]}"
verbose="${args[--verbose]}"

ret=$(get_sr_url_and_security)

sr_url=$(echo "$ret" | cut -d "@" -f 1)
sr_security=$(echo "$ret" | cut -d "@" -f 2)

tmp_dir=$(mktemp -d -t ci-XXXXXXXXXX)
#trap 'rm -rf $tmp_dir' EXIT
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

log "⏺️ Registering schema to subject ${subject}"
if [[ -n "$verbose" ]]
then
    set -x
fi
curl $sr_security --request POST -s "${sr_url}/subjects/${subject}/versions" \
    --header 'Content-Type: application/vnd.schemaregistry.v1+json' \
    --data "$json_new" | jq .
