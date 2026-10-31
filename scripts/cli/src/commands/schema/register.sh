subject="${args[--subject]}"
schema="${args[--schema]}"
id="${args[--id]}"
normalize="${args[--normalize]}"
verbose="${args[--verbose]}"

eval "metadata_property=(${args[--metadata-property]})"
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

sr_read_schema_arg "$schema" "$schema_file" || exit 1

if ! sr_schema_request_body "$schema_file"
then
    logerror "❌ no known schema could be identified"
    exit 1
fi
json_new="$sr_body"
if grep -q "\"references\"\s*:" $schema_file
then
    log "🔮 schema was identified with references, sending as is"
else
    case "$sr_schema_type" in
        PROTOBUF) log "🔮 schema was identified as protobuf" ;;
        JSON) log "🔮 schema was identified as json schema" ;;
        AVRO) log "🔮 schema was identified as avro" ;;
    esac
fi

# Check if the array contains multiple results
if [ "${#metadata_property[@]}" -gt 1 ]
then
    log "🟡 schema metadata are present, adding them"
    # Construct metadata_json using jq
    metadata_json=$(jq -n --argjson props "$(printf '%s\n' "${metadata_property[@]}" | jq -R 'split("=") | { (.[0]): .[1] }' | jq -s 'add')" '{properties: $props}')
    json_new=$(echo $json_new | jq --argjson metadata "$metadata_json" '. + { "metadata": $metadata }')
fi

if [[ -n "$id" ]]
then
    function set_back_read_write {
        set +e
        curl $sr_security --request PUT -s "${sr_url}/mode/${subject}" --header 'Content-Type: application/json' --data '{"mode": "READWRITE"}' > /dev/null 2>&1
        set -e
    }
    trap set_back_read_write EXIT

    # backup
    playground schema get --subject "${subject}" --store-in-tmp "$tmp_dir" > /dev/null 2>&1

    log "Deleting subject 🔰 ${subject}"
    playground schema delete --subject "${subject}" --permanent > /dev/null 2>&1

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

    # https://docs.confluent.io/platform/current/schema-registry/installation/migrate.html#migrate-an-individual-schema-to-an-already-populated-sr-subject-level-migration
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

    for schema_file in $tmp_dir/schema_*.txt
    do
        [ -e "$schema_file" ] || continue
        log "Restoring schema from $schema_file"
        playground schema register --subject "${subject}" --schema "$(cat $schema_file)"
    done
    exit 0
fi

# check if schema already exists
# https://docs.confluent.io/platform/current/schema-registry/develop/api.html#post--subjects-(string-%20subject)
# curl_output=$(curl $sr_security --request POST -s "${sr_url}/subjects/${subject}" \
# --header 'Content-Type: application/vnd.schemaregistry.v1+json' \
# --data "$json_new" | jq .)
# ret=$?
# if [ $ret -eq 0 ]
# then
#     if echo "$curl_output" | jq '. | has("error_code")' 2> /dev/null | grep -q true 
#     then
#         error_code=$(echo "$curl_output" | jq -r .error_code)
#         if [ "$error_code" != "40403" ] && [ "$error_code" != "40401" ]
#         then
#             message=$(echo "$curl_output" | jq -r .message)
#             logerror "Command failed with error code $error_code"
#             logerror "$message"
#             exit 1
#         fi
#     else
#         id=$(echo "$curl_output" | jq -r .id)
#         version=$(echo "$curl_output" | jq -r .version)
#         log "🚪 Skipping as schema already exists with id $id (version $version)"
#         exit 0
#     fi
# else
#     logerror "❌ curl request failed with error code $ret!"
#     exit 1
# fi

maybe_normalize=""
if [[ -n "$normalize" ]]
then
    maybe_normalize="?normalize=true"
    log "⏺️ Registering schema to subject ${subject} with normalization"
else
    log "⏺️ Registering schema to subject ${subject}"
fi
#url encode subject
subject=$(urlencode "${subject}")
if [[ -n "$verbose" ]]
then
    log "🐞 curl command used"
    echo "curl $sr_security --request POST -s "${sr_url}/subjects/${subject}/versions${maybe_normalize}" --header 'Content-Type: application/vnd.schemaregistry.v1+json' --data "$json_new""
fi
curl_output=$(curl $sr_security --request POST -s "${sr_url}/subjects/${subject}/versions${maybe_normalize}" --header 'Content-Type: application/vnd.schemaregistry.v1+json' --data "$json_new" | jq .)
echo "$curl_output"
# a refused schema (incompatible: 40901, invalid: 42201…) comes back as an error json: fail, so that scripts can tell
if echo "$curl_output" | jq -e 'has("error_code")' > /dev/null 2>&1
then
    logerror "❌ schema registry refused the schema for subject ${subject} (error code $(echo "$curl_output" | jq -r .error_code))"
    exit 1
fi
