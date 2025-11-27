topic="${args[--topic]}"
verbose="${args[--verbose]}"
debug="${args[--debug]}"
nb_messages="${args[--nb-messages]}"
nb_partitions="${args[--nb-partitions]}"
value="${args[--value]}"
key="${args[--key]}"
headers="${args[--headers]}"
forced_key="${args[--forced-key]}"
forced_value="${args[--forced-value]}"
generate_only="${args[--generate-only]}"
tombstone="${args[--tombstone]}"
compatibility="${args[--compatibility]}"
key_subject_name_strategy="${args[--key-subject-name-strategy]}"
value_subject_name_strategy="${args[--value-subject-name-strategy]}"
validate="${args[--validate]}"
record_size="${args[--record-size]}"
max_nb_messages_per_batch="${args[--max-nb-messages-per-batch]}"
max_nb_messages_to_generate="${args[--max-nb-messages-to-generate]}"
sleep_time_between_batch="${args[--sleep-time-between-batch]}"
compression_codec="${args[--compression-codec]}"
value_schema_id="${args[--value-schema-id]}"
no_null="${args[--no-null]}"
consume="${args[--consume]}"
delete_topic="${args[--delete-topic]}"
derive_key_schema_as="${args[--derive-key-schema-as]}"
derive_value_schema_as="${args[--derive-value-schema-as]}"

# Convert the space delimited string to an array
eval "validate_config=(${args[--validate-config]})"
eval "producer_property=(${args[--producer-property]})"
eval "references=(${args[--reference]})"

function identify_schema() {
    schema_file=$1
    type=$2

    if grep -q "proto3" $schema_file
    then
        log "🔮 $type schema was identified as protobuf"
        schema_type=protobuf
    elif grep -q "\"type\"\s*:\s*\"object\"" $schema_file
    then
        log "🔮 $type schema was identified as json schema"
        schema_type=json-schema
    elif grep -q "\"_meta" $schema_file
    then
        log "🔮 $type schema was identified as json"
        schema_type=json
    elif grep -q "CREATE TABLE" $schema_file
    then
        log "🔮 $type schema was identified as sql"
        schema_type=sql
    elif grep -q "arg.properties" $schema_file
    then
        log "🔮 $type schema was identified as datagen"
        schema_type=datagen
    elif grep -q "\"type\"\s*:\s*\"record\"" $schema_file
    then
        log "🔮 $type schema was identified as avro"
        schema_type=avro
    elif grep -xq "\".*\"" $schema_file
    then
        log "🔮 $type schema was identified as avro (single line surrounded by double quotes)"
        schema_type=avro
    else
        log "📢 $type no known schema could be identified, payload will be sent as raw data"
        schema_type=raw
    fi
}

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

# debug
if [[ -n "$debug" ]]
then
    log "🐞 debug mode is on"
    trap 'code $tmp_dir' EXIT
fi

ref_schema_file=$tmp_dir/ref_schema
key_schema_file=$tmp_dir/key_schema
value_schema_file=$tmp_dir/value_schema

if [ "$value" = "-" ]
then
    if [[ ! -n "$tombstone" ]]
    then
        # stdin
        if [ -t 0 ]
        then
            logerror "❌ stdin is empty you probably forgot to set --value !"
            exit 1
        else
            value_content=$(cat "$value")
            echo "$value_content" > $value_schema_file
        fi
    fi
else
    if [[ $value == @* ]] || [[ $value == *predefined-schemas/* ]]
    then
        # this is a predefined schema file
        predefined_folder="$root_folder/scripts/cli/"
        predefined_selection=$(echo "$value" | cut -d "@" -f 2)
        cp "$predefined_folder/$predefined_selection" "$value_schema_file"
    elif [ -f "$value" ]
    then
        cp "$value" "$value_schema_file"
    else
        value_content=$value
        echo "$value_content" > "$value_schema_file"
    fi
fi

is_value_datagen=0
identify_schema "$value_schema_file" "value" > /dev/null 2>&1
if [[ "$schema_type" == "datagen" ]]
then
    is_value_datagen=1
fi

get_environment_used
get_sr_url_and_security

get_broker_container
bootstrap_server="$broker_container:9092"
get_connect_container
container=$connect_container
sr_url_cli="http://schema-registry:8081"
security=""
if [[ "$environment" == "kerberos" ]] || [[ "$environment" == "ssl_kerberos" ]]
then
    container="client"
    security="--producer.config /etc/kafka/producer.properties"

    docker exec -i client kinit -k -t /var/lib/secret/kafka-connect.key connect
elif [[ "$environment" == *"ssl"* ]]
then
    sr_url_cli="https://schema-registry:8081"
    security="--property schema.registry.ssl.truststore.location=/etc/kafka/secrets/kafka.client.truststore.jks --property schema.registry.ssl.truststore.password=confluent --property schema.registry.ssl.keystore.location=/etc/kafka/secrets/kafka.client.keystore.jks --property schema.registry.ssl.keystore.password=confluent --producer.config /etc/kafka/secrets/client_without_interceptors.config"
elif [[ "$environment" == "rbac-sasl-plain" ]]
then
    security="--property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info=clientAvroCli:clientAvroCli --producer.config /etc/kafka/secrets/client_without_interceptors.config"
elif [[ "$environment" == "ldap-authorizer-sasl-plain" ]]
then
    security="--producer.config /service/kafka/users/client.properties"
elif [[ "$environment" == "sasl-plain" ]] || [[ "$environment" == "sasl-scram" ]] || [[ "$environment" == "ldap-sasl-plain" ]]
then
    security="--producer.config /tmp/client.properties"
elif [[ "$environment" == "ccloud" ]]
then
    get_kafka_docker_playground_dir
    DELTA_CONFIGS_ENV=$KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/env.delta

    if [ -f $DELTA_CONFIGS_ENV ]
    then
        source $DELTA_CONFIGS_ENV
    else
        logerror "❌ $DELTA_CONFIGS_ENV has not been generated"
        exit 1
    fi
    if [ ! -f $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta ]
    then
        logerror "❌ $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta has not been generated"
        exit 1
    fi
fi

if [[ -n "$delete_topic" ]]
then
    if [[ ! -n "$generate_only" ]]
    then
        log "❌ --delete-topic is set, delete topic if applicable"
        playground topic delete --topic $topic
    fi
fi

if [[ -n "$tombstone" ]]
then
    if [[ ! -n "$key" ]] && [[ ! -n "$forced_key" ]]
    then
        logwarn "--tombstone is set but neither --key or --forced-key are set, forcing key to NULL."
        key="NULL"
    fi
    get_connect_image
    if ! version_gt $CP_CONNECT_TAG "7.1.99"
    then
        logerror "❌ --tombstone is set but it can be produced only with CP 7.2+"
        exit 1
    fi
    if [[ -n "$forced_key" ]]
    then
        key=$forced_key
    fi
fi

if [[ -n "$headers" ]]
then
    get_connect_image
    if ! version_gt $CP_CONNECT_TAG "7.1.99"
    then
        logerror "❌ --headers is set but it can be produced only with CP 7.2+"
        exit 1
    fi
fi

if [ "$record_size" != 0 ]
then
    log "💫 --record-size is set, forcing --no-null"
    no_null="true"

    if [ $nb_messages -ge 100000 ] && [ $record_size -ge 10000 ]
    then
        if [ $record_size -ge 100000 ]
        then
            max_nb_messages_to_generate=1
            max_nb_messages_per_batch=1000
            logwarn "💫 --record-size is set with high value $record_size and --nb-messages $nb_messages is also high, forcing --max-nb-messages-to-generate to $max_nb_messages_to_generate and --max-nb-messages-per-batch to $max_nb_messages_per_batch"
        else
            max_nb_messages_to_generate=100
            logwarn "💫 --record-size is set with high value $record_size and --nb-messages $nb_messages is also high, forcing --max-nb-messages-to-generate to $max_nb_messages_to_generate"
        fi
    fi
fi

ref_array_schema_file=$tmp_dir/ref_array_schema
  if [ ${#references[@]} -ne 0 ]
  then
    declare -a array_ref_name=()
    i=0
    list_file=""
    for ref in "${references[@]}"
    do
        log "🖇️ ref is $ref"

        if [[ $ref == @* ]]
        then
            # this is a schema file
            argument_schema_file=$(echo "$ref" | cut -d "@" -f 2)
            cp $argument_schema_file $ref_schema_file
        elif [ -f "$ref" ]
        then
            cp $ref $ref_schema_file
        else
            echo "$ref" > "$ref_schema_file"
        fi

        cp $ref_schema_file $tmp_dir/schema_ref_$i
        list_file="$list_file $tmp_dir/schema_ref_$i"

        identify_schema "$ref_schema_file" "ref"
        ref_schema_type=$schema_type

        ref_name=$(cat $ref_schema_file | jq -r '.["$id"]')

        log "🔖 registering schema reference with subject $ref_name"
        playground schema register --subject "$ref_name" < "$ref_schema_file"

        array_ref_name+=("$ref_name")
        ((i=i+1))
    done

    jq -s '.' $list_file > $ref_array_schema_file

    json_new_file=$tmp_dir/json_new_file
    json="{\"schemaType\":\"JSON\"}"
    content=$(cat $value_schema_file | tr -d '\n' | tr -s ' ')
    json_new=$(echo $json | jq --arg content "$content" '. + { "schema": $content }')
    echo "$json_new" > $json_new_file
    references=""
    curl_tmp_ref_schema=$tmp_dir/curl_tmp_ref_schema
    curl_ref_array_schema_file=$tmp_dir/curl_ref_array_schema

    i=0
    list_file=""
    for ref_name in "${array_ref_name[@]}"
    do
        reference="{\"name\":\"$ref_name\",\"subject\":\"$ref_name\",\"version\":1}"
        echo "$reference" > $curl_tmp_ref_schema
        cp $curl_tmp_ref_schema $tmp_dir/ref_$i
        list_file="$list_file $tmp_dir/ref_$i"
        ((i=i+1))
    done

    jq -s '.' $list_file > $curl_ref_array_schema_file

    references=$(cat $curl_ref_array_schema_file | tr -d '\n' | tr -s ' ')

    register_ref_array_schema=$tmp_dir/register_ref_array_schema

    jq --argjson addition "$(cat $curl_ref_array_schema_file)" '. + {references: $addition}' $json_new_file > $register_ref_array_schema

    log "🔖 registering schema with subject $topic-value and reference"
    playground schema register --subject "${topic}-value" < $register_ref_array_schema

    value_schema_id=$(playground schema get --subject "${topic}-value" | grep "subject" | cut -d "(" -f 2 | cut -d " " -f 2 | cut -d ")" -f 1)

    if [[ "$value_schema_id" =~ ^-?[0-9]+$ ]]
    then
        :
    else
        logerror "❌ value schema id $value_schema_id is not valid"
        exit 1
    fi
    
fi

if [[ -n "$key" ]]
then
    if [[ $key == @* ]] || [[ $key == *predefined-schemas/* ]]
    then
        # this is a predefined schema file
        predefined_folder="$root_folder/scripts/cli"
        predefined_selection=$(echo "$key" | cut -d "@" -f 2)
        cp "$predefined_folder/$predefined_selection" "$key_schema_file"
    elif [ -f "$key" ]
    then
        cp "$key" "$key_schema_file"
    else
        echo "$key" > "$key_schema_file"
    fi

    is_key_datagen=0
    identify_schema "$key_schema_file" "key" > /dev/null 2>&1
    if [[ "$schema_type" == "datagen" ]]
    then
        is_key_datagen=1
    fi

    if [[ "$is_key_datagen" == "1" ]]
    then
        log "🍦 --derive-key-schema-as $derive_key_schema_as is used with datagen schema, generating a payload:"
        cp "${key_schema_file}" "$tmp_dir/original_key_datagen.avro"
        schema_file_name="$(basename "${key_schema_file}")"
        docker run --quiet --rm -v "$tmp_dir:/tmp/" vdesabou/avro-random-generator -f "/tmp/$schema_file_name" -i 1 -c > "$tmp_dir/tmp_datagen_key.json" 2> /dev/null
        cat "$tmp_dir/tmp_datagen_key.json"
        set +e
        output=$(playground --output-level ERROR schema derive-schema --schema-type "${derive_key_schema_as}" < "$tmp_dir/tmp_datagen_key.json")
        if [ $? -ne 0 ]
        then
            logerror "❌ schema derivation failed"
            echo "$output"
            exit 1
        else
            log "🪄 generated $derive_key_schema_as schema:"
            echo "$output"
        fi
        set -e
        echo "$output" > ${key_schema_file}
    else 
        if [[ -n "$derive_key_schema_as" ]]
        then
            log "🪄 --derive-key-schema-as $derive_key_schema_as is used"
            set +e
            output=$(playground --output-level ERROR  schema derive-schema --schema-type "${derive_key_schema_as}" < "$key_schema_file")
            if [ $? -ne 0 ]
            then
                logerror "❌ schema derivation failed"
                echo "$output"
                exit 1
            else
                log "🪄 generated $derive_key_schema_as schema:"
                echo "$output"
            fi
            set -e
            echo "$output" > "$key_schema_file"
        fi
    fi
    identify_schema "$key_schema_file" "key"
    key_schema_type=$schema_type
fi

if [[ ! -n "$tombstone" ]]
then
    if [[ -n "$derive_value_schema_as" ]]
    then
        if [[ "$is_value_datagen" == "1" ]]
        then
            log "🍦 --derive-value-schema-as $derive_value_schema_as is used with datagen schema, generating a payload:"
            cp "${value_schema_file}" "$tmp_dir/original_value_datagen.avro"
            schema_file_name="$(basename "${value_schema_file}")"
            docker run --quiet --rm -v "$tmp_dir:/tmp/" vdesabou/avro-random-generator -f "/tmp/$schema_file_name" -i 1 -c > "$tmp_dir/tmp_datagen_value.json" 2> /dev/null
            cat "$tmp_dir/tmp_datagen_value.json"
            set +e
            output=$(playground --output-level ERROR schema derive-schema --schema-type "${derive_value_schema_as}" < "$tmp_dir/tmp_datagen_value.json")
            if [ $? -ne 0 ]
            then
                logerror "❌ schema derivation failed"
                echo "$output"
                exit 1
            else
                log "🪄 generated $derive_value_schema_as schema:"
                echo "$output"
            fi
            set -e
            echo "$output" > $value_schema_file
        else
            log "🪄 --derive-value-schema-as $derive_value_schema_as is used"
            set +e
            output=$(playground --output-level ERROR schema derive-schema --schema-type "${derive_value_schema_as}" < "$value_schema_file")
            if [ $? -ne 0 ]
            then
                logerror "❌ schema derivation failed"
                echo "$output"
                exit 1
            else
                log "🪄 generated $derive_value_schema_as schema:"
                echo "$output"
            fi
            set -e
            echo "$output" > $value_schema_file
        fi
    fi
    identify_schema "$value_schema_file" "value"
    value_schema_type=$schema_type
fi

if [[ -n "$key" ]]
then
    if ([ "$key_schema_type" = "avro" ] || [ "$key_schema_type" = "protobuf" ] || [ "$key_schema_type" = "json-schema" ]) && 
        ([ "$value_schema_type" = "avro" ] || [ "$value_schema_type" = "protobuf" ] || [ "$value_schema_type" = "json-schema" ])
    then
        if [ "$key_schema_type" != "$value_schema_type" ]
        then
            logerror "❌ both key and schemas are set with schema registry aware converters, but they are not the same"
            exit 1
        fi
    fi

    if ([ "$key_schema_type" = "avro" ] || [ "$key_schema_type" = "protobuf" ] || [ "$key_schema_type" = "json-schema" ]) && 
        ([ "$value_schema_type" = "raw" ] || [ "$value_schema_type" = "json" ] || [ "$value_schema_type" = "sql" ])
    then
        logerror "❌ key is set with schema registry aware converter, but not value"
        exit 1
    fi
fi

if [[ -n "$validate" ]]
then
    if [ $nb_messages != 1 ]
    then
        logwarn "--validate is set, ignoring --nb-messages"
        nb_messages=1
    fi
fi

function generate_data() {
    schema_type=$1
    schema_file=$2
    output_file=$3
    type="$4"
    input_file=""

    if [[ -n "$max_nb_messages_to_generate" ]]
    then
        log "🔨 --max-nb-messages-to-generate is set with $max_nb_messages_to_generate (it can be slow if number is high)"
        nb_max_messages_to_generate=$max_nb_messages_to_generate
    else 
        if [ "$schema_type" == "protobuf" ]
        then
            nb_max_messages_to_generate=50
        elif [ "$schema_type" == "json" ] || [ "$schema_type" == "sql" ]
        then
            nb_max_messages_to_generate=1000
        else
            if [ "$record_size" != 0 ] && [ "$type" == "VALUE" ]
            then
                nb_max_messages_to_generate=100
            else
                nb_max_messages_to_generate=100000
            fi
        fi
        if [ $nb_messages = -1 ]
        then
            nb_messages_to_generate=1000
        fi
    fi
    if [ $nb_messages = -1 ]
    then
        nb_messages_to_generate=$nb_max_messages_to_generate
    elif [ $nb_messages -lt $nb_max_messages_to_generate ]
    then
        nb_messages_to_generate=$nb_messages
    else
        nb_messages_to_generate=$nb_max_messages_to_generate
    fi

    if [[ -n "$forced_value" ]] && [ "$type" == "VALUE" ]
    then
        log "☢️ --forced-value is set"
        echo "$forced_value" > $tmp_dir/out.json
    elif [[ -n "$forced_key" ]] && [ "$type" == "KEY" ]
    then
        log "☢️ --forced-key is set"
        echo "$forced_key" > $tmp_dir/out.json
    else
        if [[ -n "$no_null" ]]
        then
            no_null="true"
        else
            no_null="false"
        fi
        case "${schema_type}" in
            json|sql)
                # https://github.com/MaterializeInc/datagen
                set +e
                docker run --quiet --rm -i -v $schema_file:/app/schema.$schema_type materialize/datagen -s schema.$schema_type -n $nb_messages_to_generate --dry-run > $tmp_dir/result.log
                
                nb=$(grep -c "Payload: " $tmp_dir/result.log)
                if [ $nb -eq 0 ]
                then
                    logerror "❌ materialize/datagen failed to produce $schema_type "
                    cat $tmp_dir/result.log
                    exit 1
                fi
                set -e
                cat $tmp_dir/result.log | grep "Payload: " | sed 's/  Payload: //' > $tmp_dir/out.json
            ;;
            avro)
                schema_file_name="$(basename "${schema_file}")"
                docker run --quiet --rm -v $tmp_dir:/tmp/ vdesabou/avro-tools random /tmp/out.avro --schema-file /tmp/$schema_file_name --count $nb_messages_to_generate --no-null "$no_null"
                docker run --quiet --rm -v $tmp_dir:/tmp/ vdesabou/avro-tools tojson /tmp/out.avro > $tmp_dir/out.json
            ;;
            datagen)
                schema_file_name="$(basename "${schema_file}")"
                docker run --quiet --rm -v $tmp_dir:/tmp/ vdesabou/avro-random-generator -f /tmp/$schema_file_name -i $nb_messages_to_generate -c > $tmp_dir/out.json 2> /dev/null
            ;;
            json-schema)
                # https://github.com/json-schema-faker/json-schema-faker/tree/master/docs
                schema_file_name="$(basename "${schema_file}")"
                if [ -f $ref_array_schema_file ]
                then
                    ref_array_schema_file_name="$(basename "${ref_array_schema_file}")"
                    docker run --quiet --rm -v $tmp_dir:/tmp/ -e NB_MESSAGES=$nb_messages_to_generate -e SCHEMA=/tmp/$schema_file_name -e REFS=/tmp/$ref_array_schema_file_name -e NO_NULL="$no_null" vdesabou/json-schema-faker > $tmp_dir/out.json
                else
                    docker run --quiet --rm -v $tmp_dir:/tmp/ -e NB_MESSAGES=$nb_messages_to_generate -e SCHEMA=/tmp/$schema_file_name -e NO_NULL="$no_null" vdesabou/json-schema-faker > $tmp_dir/out.json
                fi
            ;;
            protobuf)
                # https://github.com/JasonkayZK/mock-protobuf.js
                docker run -u0 --rm -v $tmp_dir:/tmp/ -v $schema_file:/app/schema.proto -e NB_MESSAGES=$nb_messages_to_generate vdesabou/protobuf-faker bash -c "bash /app/produce.sh && chown -R $(id -u $USER):$(id -g $USER) /tmp/" > $tmp_dir/out.json
            ;;
            raw)
                if jq -e . >/dev/null 2>&1 <<< "$(head -1 "$schema_file")"
                then
                    log "💫 payload is one json per line, one json record per line will be sent"
                    set +e
                    LINE=$(<"$schema_file")
                    for ((i=0; i<nb_messages_to_generate; i++)); do
                        printf "%s\n" "$LINE" > $tmp_dir/out.json
                    done
                    set -e
                elif jq -e . >/dev/null 2>&1 <<< "$(cat "$schema_file")"
                then
                    log "💫 payload is single json, it will be sent as one record"
                    jq -c . "$schema_file" > $tmp_dir/minified.json
                    set +e
                    LINE=$(<"$tmp_dir/minified.json")
                    for ((i=0; i<nb_messages_to_generate; i++)); do
                        printf "%s\n" "$LINE" > $tmp_dir/out.json
                    done
                    set -e
                else
                    log "💫 payload is not single json, one record per line will be sent"
                    set +e
                    LINE=$(<"$schema_file")
                    for ((i=0; i<nb_messages_to_generate; i++)); do
                        printf "%s\n" "$LINE" > $tmp_dir/out.json
                    done
                    set -e
                fi
            ;;
            *)
                logerror "❌ schema_type name not valid ! Should be one of raw, json, avro, json-schema or protobuf"
                exit 1
            ;;
        esac
    fi
    
    if [ "$input_file" = "" ]
    then
        input_file=$tmp_dir/out.json
    fi

    input2_file=$tmp_dir/input2.json
    if [ -f $input2_file ]
    then
        rm -f $input2_file
    fi
    record_size_temp_file_line=$tmp_dir/line.json
    record_size_temp_file_output=$tmp_dir/output.json
    lines_count=0
    counter=0

    while IFS= read -r line
    do
        if [ $record_size != 0 ] && [ "$type" == "VALUE" ]
        then
            if ! echo "$line" | jq -e .  > /dev/null 2>&1
            then
                echo "${line}PLACEHOLDER" > $record_size_temp_file_output
            else
                echo $line > $record_size_temp_file_line
                new_value="PLACEHOLDER"
                
                first_string_field=$(echo "$line" | jq -r 'path(.. | select(type == "string")) | .[-1]' | head -1)

                if [ "$first_string_field" != "" ]
                then
                    if [ $lines_count -eq 0 ]
                    then
                        log "🔮 Replacing first string field $first_string_field value with long payload"
                    fi
                    if [ "$first_string_field" == "string" ]
                    then
                        jq -c --arg new_val "$new_value" 'walk(if type == "object" and has("string") then .string = $new_val else . end)' $record_size_temp_file_line > $record_size_temp_file_output
                    else
                        jq -c --arg new_val "$new_value" ".${first_string_field} |= \$new_val" $record_size_temp_file_line > $record_size_temp_file_output
                    fi
                else 
                    cat "$record_size_temp_file_line" > $record_size_temp_file_output
                    logwarn "😕 could not find string field, that record will not have expected --record-size !"
                fi
            fi

            # The size needed for the new_value
            size_with_placeholder=$(wc -c < $record_size_temp_file_output)

            # The size needed for the new_value
            new_value_size=$((record_size - size_with_placeholder))

            if [[ $new_value_size -gt 0 ]]
            then
                # Create a string of '-' characters with length equivalent to new_value_size
                new_value_string=$(LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c$new_value_size)

                echo -n "$new_value_string" > temp.txt

                # Replace placeholder with the content of temp.txt file in $record_size_temp_file_output
                # Perl can handle very large arguments and perform replacement effectively
                perl -pi -e 'BEGIN{undef $/;} s/PLACEHOLDER/`cat temp.txt`/gse' $record_size_temp_file_output

                cat $record_size_temp_file_output >> "$input2_file"
                # Remove temp file
                rm temp.txt
            else
                log "❌ record-size is too small"
                exit 1
            fi
        else
            echo "$line" >> "$input2_file"
        fi

        lines_count=$((lines_count+1))
        if [ $nb_messages != -1 ]
        then
            if [ $lines_count -ge $nb_messages ]
            then
                break
            fi
        fi
        counter=$((counter+1))
    done < "$input_file"

    if [ $nb_messages -gt $max_nb_messages_per_batch ] || [ $nb_messages = -1 ]
    then
        set +e
        awk '
        {
            # Store each line in an array indexed by the line number (NR)
            lines[NR] = $0
        }
        END {
            # NR now holds the total number of lines read
            while (1) {
                for (i = 1; i <= NR; i++) {
                    print lines[i]
                }
            }
        }
        ' "$input2_file" | head -n "$max_nb_messages_per_batch" > "$output_file"
        set -e
    elif [ $lines_count -lt $nb_messages ]
    then
        set +e
        awk '
        {
            # Store each line in an array indexed by the line number (NR)
            lines[NR] = $0
        }
        END {
            # NR now holds the total number of lines read
            while (1) {
                for (i = 1; i <= NR; i++) {
                    print lines[i]
                }
            }
        }
        ' "$input2_file" | head -n "$nb_messages" > "$output_file"
        set -e
    else
        cp $input2_file $output_file
    fi
}

output_key_file=$tmp_dir/out_key_final.json
output_value_file=$tmp_dir/out_value_final.json
output_final_file=$tmp_dir/out_final.json
SECONDS=0
if [[ -n "$key" ]]
then
    if [[ -n "$derive_key_schema_as" ]] && [[ "$is_key_datagen" == "1" ]]
    then
        log "✨🍟 generating key data using datagen..."
        generate_data "datagen" "$tmp_dir/original_key_datagen.avro" "$output_key_file" "KEY"
    else
        log "✨ generating key data..."
        generate_data "$key_schema_type" "$key_schema_file" "$output_key_file" "KEY"
    fi
fi
if [[ ! -n "$tombstone" ]]
then
    if [[ -n "$derive_value_schema_as" ]] && [[ "$is_value_datagen" == "1" ]]
    then
        log "✨🍟 generating value data using datagen..."
        generate_data "datagen" "$tmp_dir/original_value_datagen.avro" "$output_value_file" "VALUE"
    else
        log "✨ generating value data..."
        generate_data "$value_schema_type" "$value_schema_file" "$output_value_file" "VALUE"
    fi
    
    nb_generated_messages=$(wc -l < $output_value_file)
else
    nb_generated_messages=$(wc -l < $output_key_file)
fi
nb_generated_messages=${nb_generated_messages// /}

if [ "$nb_generated_messages" == "0" ]
then
    logerror "❌ records could not be generated!"
    exit 1
fi

if [[ -n "$key" ]] && [ "$key_schema_type" = "raw" ]
then
    if [[ $key =~ ^([^0-9]*)([0-9]+)([^0-9]*)$ ]]; then
        prefix="${BASH_REMATCH[1]}"
        number="${BASH_REMATCH[2]}"
        suffix="${BASH_REMATCH[3]}"
        
        log "🗝️ key $key is set with a number $number, it will be used as starting point"
        while read -r line
        do
            new_key="${prefix}${number}${suffix}"
            echo "${new_key}" >> "$tmp_dir/temp_value_file"
            number=$((number + 1))
        done < "$output_key_file"

        mv "$tmp_dir/temp_value_file" "$output_key_file"
    else
        counter=1
        log "🗝️ key is set with a string $key, it will be used for all records"
        while read -r line
        do
            echo "${key}" >> "$tmp_dir/temp_value_file"
        done < "$output_key_file"

        mv "$tmp_dir/temp_value_file" "$output_key_file"
    fi
fi

if [[ -n "$key" ]]
then
    if [[ ! -n "$tombstone" ]]
    then
        # merging key and value files
        paste -d "|" $output_key_file $output_value_file > $output_final_file
    else
        touch "$output_value_file"
        while read -r line; do
            echo "NULL" >> "$output_value_file"
        done < "$output_key_file"
        # merging key and value files
        paste -d "|" $output_key_file $output_value_file > $output_final_file
    fi
else
    cp $output_value_file $output_final_file
fi

# headers need to be set first
if [[ -n "$headers" ]]
then
    log "🚏 headers are set $headers"
    while read line
    do
        echo "${headers}|${line}" >> $tmp_dir/temp_headers_file
    done < $output_final_file

    mv $tmp_dir/temp_headers_file $output_final_file
fi

value_str=""
if [[ -n "$forced_value" ]]
then
    value_str=" based on --forced-value "
fi

ELAPSED="took: $((($SECONDS / 60) % 60))min $(($SECONDS % 60))sec"

size_limit_to_show=3000
if [ $record_size -gt $size_limit_to_show ]
then
    log "✨ $nb_generated_messages records were generated$value_str (only showing first 1 as record size is $record_size), $ELAPSED"
    log "✨ only showing first $size_limit_to_show characters"
    head -n 1 "$output_final_file" | awk -v counter=1 '{gsub("%g", counter); counter++; print}' | cut -c 1-${size_limit_to_show} | awk "{print \$0 \"...<truncated, only showing first $size_limit_to_show characters, out of $record_size>...\"}"
else
    if (( nb_generated_messages < 10 ))
    then
        log "✨ $nb_generated_messages records were generated$value_str"
        cat "$output_final_file" | awk -v counter=1 '{gsub("%g", counter); counter++; print}'
    else
        log "✨ $nb_generated_messages records were generated$value_str (only showing first 10), $ELAPSED"
        head -n 10 "$output_final_file" | awk -v counter=1 '{gsub("%g", counter); counter++; print}'
    fi
fi

if [[ -n "$generate_only" ]]
then
  log "🚪 --generate-only is set, exiting now."
  exit 0
fi

if [[ -n "$validate" ]]
then
    log "✔️ --validate is set, validating schema now..."

    if [ "$value_schema_type" == "json-schema" ]
    then
        log "✨ also validating with https://raw.githubusercontent.com/conan-goldsmith/Python-Scripts/main/json_type_validator.py"
        curl -s -L https://raw.githubusercontent.com/conan-goldsmith/Python-Scripts/main/json_type_validator.py -o /tmp/json_type_validator.py
        docker run -i --rm -v "/tmp/json_type_validator.py:/tmp/json_type_validator.py" -v "$value_schema_file:/tmp/schema" python:3.7-slim python /tmp/json_type_validator.py -f /tmp/schema
    fi

    set +e
    tag=$(docker ps --format '{{.Image}}' | grep -E 'confluentinc/cp-.*-connect-.*:' | awk -F':' '{print $2}')
    if [ $? != 0 ] || [ "$tag" == "" ]
    then
        logerror "❌ Could not find current CP version from docker ps"
        exit 1
    fi
    log "🏗 Building jar for schema-validator"
    docker run -i --rm -e TAG=$tag -v "${root_folder}/scripts/cli/src/schema-validator":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "$root_folder/scripts/settings.xml:/tmp/settings.xml" -v "${root_folder}/scripts/cli/src/schema-validator/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.9.11-eclipse-temurin-11 mvn -s /tmp/settings.xml -Dkafka.tag=$tag package > /tmp/result.log 2>&1
    if [ $? != 0 ]
    then
        logerror "❌ failed to build java component schema-validator"
        tail -500 /tmp/result.log
        exit 1
    fi
    set -e

    docker cp ${root_folder}/scripts/cli/src/schema-validator/target/schema-validator-1.0.0-jar-with-dependencies.jar connect:/tmp/schema-validator-1.0.0-jar-with-dependencies.jar > /dev/null 2>&1
    docker cp $value_schema_file connect:/tmp/schema > /dev/null 2>&1
    docker cp $output_value_file connect:/tmp/message.json > /dev/null 2>&1
    env_list=""
    for conf in "${validate_config[@]}"
    do
        case "${conf}" in

            "connect.meta.data=false")
                env_list="$env_list -e KAFKA_CONNECT_META_DATA=false"
            ;;

            # avro specifics
            "scrub.invalid.names=true")
                env_list="$env_list -e KAFKA_SCRUB_INVALID_NAMES=true"
            ;;
            "enhanced.avro.schema.support=true")
                env_list="$env_list -e KAFKA_ENHANCED_AVRO_SCHEMA_SUPPORT=true"
            ;;

            # json-schema specifics
            "use.optional.for.nonrequired=true")
                env_list="$env_list -e KAFKA_USE_OPTIONAL_FOR_NONREQUIRED=true"
            ;;
            "ignore.default.for.nullables=true")
                env_list="$env_list -e KAFKA_IGNORE_DEFAULT_FOR_NULLABLES=true"
            ;;
            "generalized.sum.type.support=true")
                env_list="$env_list -e KAFKA_GENERALIZED_SUM_TYPE_SUPPORT=true"
            ;;

            # protobuf specifics
            "enhanced.protobuf.schema.support=true")
                env_list="$env_list -e KAFKA_ENHANCED_PROTOBUF_SCHEMA_SUPPORT=true"
            ;;
            "generate.index.for.unions=false")
                env_list="$env_list -e KAFKA_GENERATE_INDEX_FOR_UNIONS=false"
            ;;
            "int.for.enums=true")
                env_list="$env_list -e KAFKA_INT_FOR_ENUMS=true"
            ;;
            "optional.for.nullables=true")
                env_list="$env_list -e KAFKA_OPTIONAL_FOR_NULLABLES=true"
            ;;
            "generate.struct.for.nulls=true")
                env_list="$env_list -e KAFKA_GENERATE_STRUCT_FOR_NULLS=true"
            ;;
            "wrapper.for.nullables=true")
                env_list="$env_list -e KAFKA_WRAPPER_FOR_NULLABLES=true"
            ;;
            "wrapper.for.raw.primitives=false")
                env_list="$env_list -e KAFKA_WRAPPER_FOR_RAW_PRIMITIVES=false"
            ;;
            *)
                logerror "default (none of above)"
            ;;
        esac
    done

    docker exec $env_list -e SCHEMA_TYPE=$value_schema_type connect bash -c "java -jar /tmp/schema-validator-1.0.0-jar-with-dependencies.jar" > $tmp_dir/result.log
    set +e
    nb=$(grep -c "ERROR" $tmp_dir/result.log)
    if [ $nb -ne 0 ]
    then
        logerror "❌ schema is not valid according to $value_schema_type converter"
        cat $tmp_dir/result.log
        exit 1
    else
        log "👌 schema is valid according to $value_schema_type converter"
    fi
    set -e
fi

set +e
existing_topics=$(playground get-topic-list)
if ! echo "$existing_topics" | grep -qFw "$topic"
then
    log "✨ topic $topic does not exist, it will be created.."
    if [[ "$environment" == "ccloud" ]]
    then
        if [ "$nb_partitions" != "1" ]
        then
            log "⛅ creating topic in confluent cloud with $nb_partitions partitions"
            playground topic create --topic $topic --nb-partitions $nb_partitions
        else
            log "⛅ creating topic in confluent cloud"
            playground topic create --topic $topic --nb-partitions 1
        fi
    else
        if [ "$nb_partitions" != "1" ]
        then
            log "--nb-partitions is set, creating topic with $nb_partitions partitions"
            playground topic create --topic $topic --nb-partitions $nb_partitions
        else
            playground topic create --topic $topic
        fi
    fi
else
    if [ "$nb_partitions" != "1" ]
    then
        nb=$(playground topic get-number-records -t $topic | tail -1)
        if [ $nb == 0 ]
        then
            log "--nb-partitions is set and topic is empty, re-creating it with $nb_partitions partitions..."
            playground topic delete --topic $topic
            playground topic create --topic $topic --nb-partitions $nb_partitions
        else
            logerror "--nb-partitions is set, but topic is not empty, delete it first and retry"
            echo "playground topic delete --topic $topic"
            exit 0
        fi
    fi
fi

if [ "$compatibility" != "" ]
then
    playground topic set-schema-compatibility --topic $topic --compatibility $compatibility
fi

if [[ ! -n "$key" ]] && [[ -n "$key_subject_name_strategy" ]]
then
    logerror "❌ --key-subject-name-strategy is set but not --key"
    exit 1 
fi

if [ "$key_schema_type" != "" ]
then
    case "${key_schema_type}" in
        avro|json-schema|protobuf)

        ;;
        *)
            if [[ -n "$validate" ]]
            then
                logerror "❌ --validate is set but $key_schema_type is used. This is only valid for avro|json-schema|protobuf"
                exit 1
            fi
            if [[ -n "$key_subject_name_strategy" ]]
            then
                logerror "❌ --key-subject-name-strategy is set but $key_schema_type is used. This is only valid for avro|json-schema|protobuf"
                exit 1 
            fi
        ;;
    esac
fi

case "${value_schema_type}" in
    avro|json-schema|protobuf)

    ;;
    *)
        if [[ -n "$validate" ]]
        then
            logerror "❌ --validate is set but $value_schema_type is used. This is only valid for avro|json-schema|protobuf"
            exit 1
        fi
        if [[ -n "$value_subject_name_strategy" ]]
        then
            logerror "❌ --value-subject-name-strategy is set but $value_schema_type is used. This is only valid for avro|json-schema|protobuf"
            exit 1 
        fi
    ;;
esac

compression=""
producer_properties=""

set -e
SECONDS=0
if [ $nb_messages = -1 ]
then
    log "📤 producing infinite records to topic $topic (--nb-messages is set to -1)"
else
    log "📤 producing $nb_messages records to topic $topic"
fi
sleep_msg=""
if [[ $sleep_time_between_batch -gt 0 ]]
then
    sleep_msg=" with $sleep_time_between_batch seconds between each batch"
fi
if [ $nb_messages -gt $max_nb_messages_per_batch ] || [ $nb_messages = -1 ]
then
    log "✨ it will be done in batches of maximum $max_nb_messages_per_batch records$sleep_msg"

    log "✨ setting --producer-property linger.ms=100 and --producer-property batch.size=500000"
    producer_properties="$producer_properties --producer-property linger.ms=1000 --producer-property batch.size=500000"
fi

if [ $record_size -ge 1048576 ]
then
    log "✨ record-size $record_size is greater than 1Mb (1048576), setting --producer-property max.request.size=$((record_size + 1000)) and --producer-property buffer.memory=67108864"
    producer_properties="$producer_properties --producer-property max.request.size=$((record_size + 1000)) --producer-property buffer.memory=67108864"
    log "✨ topic $topic max.message.bytes is also set to $((record_size + 1000))"
    playground topic alter --topic $topic --add-config max.message.bytes=$((record_size + 1000))
fi

for producer_prop in "${producer_property[@]}"
do
    producer_properties="$producer_properties --producer-property $producer_prop"
done

if [ "$producer_properties" != "" ]
then
    log "⚙️  following producer properties will be used: $producer_properties"
fi

if [[ -n "$compression_codec" ]]
then
    log "🤐 --compression-codec $compression_codec will be used"
    compression="--compression-codec $compression_codec"
fi

if [[ -n "$tombstone" ]]
then
    log "🧟 Sending tombstone(s)"
    tombstone="--property null.marker=NULL"
fi

function handle_signal {
  echo "Stopping..."
  stop=1
}
# Set the signal handler
trap handle_signal SIGINT

parameter_for_list_broker="--bootstrap-server"
set +e
tag=$(docker ps --format '{{.Image}}' | grep -E 'confluentinc/cp-.*-connect-.*:' | awk -F':' '{print $2}')
if [ $? != 0 ] || [ "$tag" == "" ]
then
    # default to --bootstrap-server
    parameter_for_list_broker="--bootstrap-server"
fi
set -e
if [ "$tag" != "" ]
then
    if ! version_gt $tag "5.4.99"
    then
        parameter_for_list_broker="--broker-list"
    fi
fi 

nb_messages_sent=0
nb_messages_to_send=0
stop=0
should_stop=0
while [ $stop != 1 ]
do
    if [ $nb_messages -eq -1 ]
    then
        nb_messages_to_send=$nb_generated_messages
    elif [ $((nb_messages_sent + nb_generated_messages)) -le $nb_messages ]
    then
        nb_messages_to_send=$nb_generated_messages
    else
        nb_messages_to_send=$((nb_messages - nb_messages_sent))
        should_stop=1
    fi
    if [ $nb_messages_to_send -eq 0 ]
    then
        stop=1
        continue
    fi
    if [ $nb_messages -gt $max_nb_messages_per_batch ] || [ $nb_messages = -1 ]
    then
        if [ $nb_messages -eq -1 ]
        then
            log "📤 producing a batch of $nb_messages_to_send records to topic $topic (press ctrl-c to stop)"
            log "💯 $nb_messages_sent records sent so far..."
        else
            log "📤 producing a batch of $nb_messages_to_send records to topic $topic"
            log "💯 $nb_messages_sent/$nb_messages records sent so far..."
        fi
    fi
    
    if [[ -n "$verbose" ]]
    then
        head -n $nb_messages_to_send $output_final_file | awk -v counter=1 '{gsub("%g", counter); counter++; print}' > /tmp/verbose_input_file.txt
    fi
    get_connect_image
    if version_gt $CP_CONNECT_TAG "7.9.99"
    then
        tool_log4j_jvm_arg="-Dlog4j2.configurationFile=file:/etc/kafka/tools-log4j2.yaml"
    else
        tool_log4j_jvm_arg="-Dlog4j.configuration=file:/etc/kafka/tools-log4j.properties"
    fi
    switch_schema_type=""
    if [[ -n "$tombstone" ]]
    then
        switch_schema_type="${key_schema_type}"
    else
        switch_schema_type="${value_schema_type}"
    fi
    case "${switch_schema_type}" in
        json|sql|raw|datagen)
            if [[ "$environment" == "ccloud" ]]
            then
                if [[ -n "$key" ]]
                then
                    if [[ -n "$headers" ]]
                    then
                        get_connect_image
                        if [[ -n "$verbose" ]]
                        then
                            log "🐞 CLI command used to produce data"
                            echo "cat /tmp/verbose_input_file.txt | docker run -i --rm -v $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta:/tmp/configuration/ccloud.properties -e BOOTSTRAP_SERVERS=\"$BOOTSTRAP_SERVERS\" ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} kafka-console-producer $parameter_for_list_broker $BOOTSTRAP_SERVERS --topic $topic --producer.config /tmp/configuration/ccloud.properties $security $producer_properties $compression $tombstone --property parse.key=true --property key.separator=\"|\" --property parse.headers=true --property headers.delimiter=\"|\" --property headers.separator=\",\" --property headers.key.separator=\":\""
                        fi
                        head -n $nb_messages_to_send $output_final_file | awk -v counter=1 '{gsub("%g", counter); counter++; print}' | docker run -i --rm -v $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta:/tmp/configuration/ccloud.properties -e BOOTSTRAP_SERVERS=\"$BOOTSTRAP_SERVERS\" ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} kafka-console-producer $parameter_for_list_broker $BOOTSTRAP_SERVERS --topic $topic --producer.config /tmp/configuration/ccloud.properties $security $producer_properties $compression $tombstone --property parse.key=true --property key.separator="|" --property parse.headers=true --property headers.delimiter="|" --property headers.separator="," --property headers.key.separator=":"
                    else
                        get_connect_image
                        if [[ -n "$verbose" ]]
                        then
                            log "🐞 CLI command used to produce data"
                            echo "cat /tmp/verbose_input_file.txt | docker run -i --rm -v $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta:/tmp/configuration/ccloud.properties -e BOOTSTRAP_SERVERS=\"$BOOTSTRAP_SERVERS\" ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} kafka-console-producer $parameter_for_list_broker $BOOTSTRAP_SERVERS --topic $topic --producer.config /tmp/configuration/ccloud.properties $security $producer_properties $compression $tombstone --property parse.key=true --property key.separator=\"|\" "
                        fi
                        head -n $nb_messages_to_send $output_final_file | awk -v counter=1 '{gsub("%g", counter); counter++; print}' | docker run -i --rm -v $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta:/tmp/configuration/ccloud.properties -e BOOTSTRAP_SERVERS=\"$BOOTSTRAP_SERVERS\" ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} kafka-console-producer $parameter_for_list_broker $BOOTSTRAP_SERVERS --topic $topic --producer.config /tmp/configuration/ccloud.properties $security $producer_properties $compression $tombstone --property parse.key=true --property key.separator="|" 
                    fi
                else
                    if [[ -n "$headers" ]]
                    then
                        get_connect_image
                        if [[ -n "$verbose" ]]
                        then
                            log "🐞 CLI command used to produce data"
                            echo "cat /tmp/verbose_input_file.txt | docker run -i --rm -v $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta:/tmp/configuration/ccloud.properties -e BOOTSTRAP_SERVERS=\"$BOOTSTRAP_SERVERS\" ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} kafka-console-producer $parameter_for_list_broker $BOOTSTRAP_SERVERS --topic $topic --producer.config /tmp/configuration/ccloud.properties $security $producer_properties $compression $tombstone --property parse.headers=true --property headers.delimiter=\"|\" --property headers.separator=\",\" --property headers.key.separator=\":\""
                        fi
                        head -n $nb_messages_to_send $output_final_file | awk -v counter=1 '{gsub("%g", counter); counter++; print}' | docker run -i --rm -v $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta:/tmp/configuration/ccloud.properties -e BOOTSTRAP_SERVERS=\"$BOOTSTRAP_SERVERS\" ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} kafka-console-producer $parameter_for_list_broker $BOOTSTRAP_SERVERS --topic $topic --producer.config /tmp/configuration/ccloud.properties $security $producer_properties $compression $tombstone --property parse.headers=true --property headers.delimiter="|" --property headers.separator="," --property headers.key.separator=":"
                    else
                        get_connect_image
                        if [[ -n "$verbose" ]]
                        then
                            log "🐞 CLI command used to produce data"
                            echo "cat /tmp/verbose_input_file.txt | docker run -i --rm -v $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta:/tmp/configuration/ccloud.properties -e BOOTSTRAP_SERVERS=\"$BOOTSTRAP_SERVERS\" ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} kafka-console-producer $parameter_for_list_broker $BOOTSTRAP_SERVERS --topic $topic --producer.config /tmp/configuration/ccloud.properties $security $producer_properties $compression $tombstone"
                        fi
                        head -n $nb_messages_to_send $output_final_file | awk -v counter=1 '{gsub("%g", counter); counter++; print}' | docker run -i --rm -v $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta:/tmp/configuration/ccloud.properties -e BOOTSTRAP_SERVERS=\"$BOOTSTRAP_SERVERS\" ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} kafka-console-producer $parameter_for_list_broker $BOOTSTRAP_SERVERS --topic $topic --producer.config /tmp/configuration/ccloud.properties $security $producer_properties $compression $tombstone
                    fi
                fi
            else
                if [[ -n "$key" ]]
                then
                    if [[ -n "$headers" ]]
                    then
                        if [[ -n "$verbose" ]]
                        then
                            log "🐞 CLI command used to produce data"
                            echo "cat /tmp/verbose_input_file.txt | docker exec -i $container kafka-console-producer $parameter_for_list_broker $bootstrap_server --topic $topic $security $producer_properties $compression $tombstone --property parse.key=true --property key.separator=\"|\" --property parse.headers=true --property headers.delimiter=\"|\" --property headers.separator=\",\" --property headers.key.separator=\":\""
                        fi
                        head -n $nb_messages_to_send $output_final_file | awk -v counter=1 '{gsub("%g", counter); counter++; print}' | docker exec -i $container kafka-console-producer $parameter_for_list_broker $bootstrap_server --topic $topic $security $producer_properties $compression $tombstone --property parse.key=true --property key.separator="|" --property parse.headers=true --property headers.delimiter="|" --property headers.separator="," --property headers.key.separator=":"
                    else
                        if [[ -n "$verbose" ]]
                        then
                            log "🐞 CLI command used to produce data"
                            echo "cat /tmp/verbose_input_file.txt | docker exec -i $container kafka-console-producer $parameter_for_list_broker $bootstrap_server --topic $topic $security $producer_properties $compression $tombstone --property parse.key=true --property key.separator=\"|\""
                        fi
                        head -n $nb_messages_to_send $output_final_file | awk -v counter=1 '{gsub("%g", counter); counter++; print}' | docker exec -i $container kafka-console-producer $parameter_for_list_broker $bootstrap_server --topic $topic $security $producer_properties $compression $tombstone --property parse.key=true --property key.separator="|"
                    fi
                else
                    if [[ -n "$headers" ]]
                    then
                        if [[ -n "$verbose" ]]
                        then
                            log "🐞 CLI command used to produce data"
                            echo "cat /tmp/verbose_input_file.txt | docker exec -i $container kafka-console-producer $parameter_for_list_broker $bootstrap_server --topic $topic $security $producer_properties $compression $tombstone --property parse.headers=true --property headers.delimiter=\"|\" --property headers.separator=\",\" --property headers.key.separator=\":\""
                        fi
                        head -n $nb_messages_to_send $output_final_file | awk -v counter=1 '{gsub("%g", counter); counter++; print}' | docker exec -i $container kafka-console-producer $parameter_for_list_broker $bootstrap_server --topic $topic $security $producer_properties $compression $tombstone --property parse.headers=true --property headers.delimiter="|" --property headers.separator="," --property headers.key.separator=":"
                    else
                        if [[ -n "$verbose" ]]
                        then
                            log "🐞 CLI command used to produce data"
                            echo "cat /tmp/verbose_input_file.txt | docker exec -i $container kafka-console-producer $parameter_for_list_broker $bootstrap_server --topic $topic $security $producer_properties $compression $tombstone"
                        fi
                        head -n $nb_messages_to_send $output_final_file | awk -v counter=1 '{gsub("%g", counter); counter++; print}' | docker exec -i $container kafka-console-producer $parameter_for_list_broker $bootstrap_server --topic $topic $security $producer_properties $compression $tombstone
                    fi
                fi
            fi
        ;;
        *)
            force_schema_id=""
            if [[ -n "$value_schema_id" ]]
            then
                log "🔰 --value-schema-id is set: adding --property value.schema.id=$value_schema_id --property auto.register=false --property use.latest.version=true"
                force_schema_id="--property value.schema.id=$value_schema_id --property auto.register=false --property use.latest.version=true"
            fi

            key_subject_name_strategy_property=""
            if [[ -n "$key_subject_name_strategy" ]]
            then
                key_subject_name_strategy_property="--property key.subject.name.strategy=io.confluent.kafka.serializers.subject.$key_subject_name_strategy"
            fi

            value_subject_name_strategy_property=""
            if [[ -n "$value_subject_name_strategy" ]]
            then
                value_subject_name_strategy_property="--property value.subject.name.strategy=io.confluent.kafka.serializers.subject.$value_subject_name_strategy"
            fi

            avro_use_logical_type_converters_property=""
            if [ "${value_schema_type}" == "avro" ]
            then
                avro_use_logical_type_converters_property=" --property avro.use.logical.type.converters=true"
            fi
            if [[ "$environment" == "ccloud" ]]
            then
                if [ -f $key_schema_file ]
                then
                    cp $key_schema_file /tmp/key_schema_file > /dev/null 2>&1
                fi
                if [ -f $value_schema_file ]
                then
                    cp $value_schema_file /tmp/value_schema_file > /dev/null 2>&1
                fi
                if [[ -n "$key" ]]
                then
                    if [[ -n "$headers" ]]
                    then
                        if [ "$key_schema_type" = "avro" ] || [ "$key_schema_type" = "protobuf" ] || [ "$key_schema_type" = "json-schema" ]
                        then
                            get_connect_image
                            if [[ -n "$verbose" ]]
                            then
                                log "🐞 CLI command used to produce data"
                                echo "cat /tmp/verbose_input_file.txt | docker run -i --rm -v /tmp:/tmp -e SCHEMA_REGISTRY_LOG4J_OPTS=\"$tool_log4j_jvm_arg\" -e key_schema_type=$key_schema_type -e BOOTSTRAP_SERVERS=\"$BOOTSTRAP_SERVERS\" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO=\"$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO\" -e SCHEMA_REGISTRY_URL=\"$SCHEMA_REGISTRY_URL\" ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} kafka-$key_schema_type-console-producer $parameter_for_list_broker $BOOTSTRAP_SERVERS --producer-property ssl.endpoint.identification.algorithm=https --producer-property sasl.mechanism=PLAIN --producer-property security.protocol=SASL_SSL --producer-property sasl.jaas.config=\"$SASL_JAAS_CONFIG\" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info=\"$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO\" --property schema.registry.url=$SCHEMA_REGISTRY_URL --topic $topic $security --property value.schema.file=/tmp/value_schema_file --property parse.key=true --property key.separator=\"|\" --property key.schema.file=\"/tmp/key_schema_file\" --property parse.headers=true --property headers.delimiter=\"|\" --property headers.separator=\",\" --property headers.key.separator=\":\" $force_schema_id $key_subject_name_strategy_property $value_subject_name_strategy_property $avro_use_logical_type_converters_property $producer_properties $compression $tombstone"
                            fi
                            head -n $nb_messages_to_send $output_final_file | awk -v counter=1 '{gsub("%g", counter); counter++; print}' | docker run -i --rm -v /tmp:/tmp -e SCHEMA_REGISTRY_LOG4J_OPTS="$tool_log4j_jvm_arg" -e key_schema_type=$key_schema_type -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} kafka-$key_schema_type-console-producer $parameter_for_list_broker $BOOTSTRAP_SERVERS --producer-property ssl.endpoint.identification.algorithm=https --producer-property sasl.mechanism=PLAIN --producer-property security.protocol=SASL_SSL --producer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --topic $topic $security --property value.schema.file="/tmp/value_schema_file" --property parse.key=true --property key.separator="|" --property key.schema.file="/tmp/key_schema_file" --property parse.headers=true --property headers.delimiter="|" --property headers.separator="," --property headers.key.separator=":" $force_schema_id $key_subject_name_strategy_property $value_subject_name_strategy_property $avro_use_logical_type_converters_property $producer_properties $compression $tombstone
                        else
                            get_connect_image
                            if [[ -n "$verbose" ]]
                            then
                                log "🐞 CLI command used to produce data"
                                echo "cat /tmp/verbose_input_file.txt | docker run -i --rm -v /tmp:/tmp -e SCHEMA_REGISTRY_LOG4J_OPTS=\"$tool_log4j_jvm_arg\" -e value_schema_type=$value_schema_type -e BOOTSTRAP_SERVERS=\"$BOOTSTRAP_SERVERS\" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO=\"$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO\" -e SCHEMA_REGISTRY_URL=\"$SCHEMA_REGISTRY_URL\" ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} kafka-$value_schema_type-console-producer $parameter_for_list_broker $BOOTSTRAP_SERVERS --producer-property ssl.endpoint.identification.algorithm=https --producer-property sasl.mechanism=PLAIN --producer-property security.protocol=SASL_SSL --producer-property sasl.jaas.config=\"$SASL_JAAS_CONFIG\" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info=\"$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO\" --property schema.registry.url=$SCHEMA_REGISTRY_URL --topic $topic $security --property value.schema.file=/tmp/value_schema_file --property parse.key=true --property key.separator=\"|\" --property key.serializer=org.apache.kafka.common.serialization.StringSerializer --property parse.headers=true --property headers.delimiter=\"|\" --property headers.separator=\",\" --property headers.key.separator=\":\" $force_schema_id $key_subject_name_strategy_property $value_subject_name_strategy_property $avro_use_logical_type_converters_property $producer_properties $compression $tombstone"
                            fi
                            head -n $nb_messages_to_send $output_final_file | awk -v counter=1 '{gsub("%g", counter); counter++; print}' | docker run -i --rm -v /tmp:/tmp -e SCHEMA_REGISTRY_LOG4J_OPTS="$tool_log4j_jvm_arg" -e value_schema_type=$value_schema_type -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} kafka-$value_schema_type-console-producer $parameter_for_list_broker $BOOTSTRAP_SERVERS --producer-property ssl.endpoint.identification.algorithm=https --producer-property sasl.mechanism=PLAIN --producer-property security.protocol=SASL_SSL --producer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --topic $topic $security --property value.schema.file="/tmp/value_schema_file" --property parse.key=true --property key.separator="|" --property key.serializer=org.apache.kafka.common.serialization.StringSerializer --property parse.headers=true --property headers.delimiter="|" --property headers.separator="," --property headers.key.separator=":" $force_schema_id $key_subject_name_strategy_property $value_subject_name_strategy_property $avro_use_logical_type_converters_property $producer_properties $compression $tombstone
                        fi
                    else
                        if [ "$key_schema_type" = "avro" ] || [ "$key_schema_type" = "protobuf" ] || [ "$key_schema_type" = "json-schema" ]
                        then
                            get_connect_image
                            if [[ -n "$verbose" ]]
                            then
                                log "🐞 CLI command used to produce data"
                                echo "cat /tmp/verbose_input_file.txt | docker run -i --rm -v /tmp:/tmp -e SCHEMA_REGISTRY_LOG4J_OPTS=\"$tool_log4j_jvm_arg\" -e key_schema_type=$key_schema_type -e BOOTSTRAP_SERVERS=\"$BOOTSTRAP_SERVERS\" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO=\"$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO\" -e SCHEMA_REGISTRY_URL=\"$SCHEMA_REGISTRY_URL\" ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} kafka-$key_schema_type-console-producer $parameter_for_list_broker $BOOTSTRAP_SERVERS --producer-property ssl.endpoint.identification.algorithm=https --producer-property sasl.mechanism=PLAIN --producer-property security.protocol=SASL_SSL --producer-property sasl.jaas.config=\"$SASL_JAAS_CONFIG\" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info=\"$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO\" --property schema.registry.url=$SCHEMA_REGISTRY_URL --topic $topic $security --property value.schema.file=/tmp/value_schema_file --property parse.key=true --property key.separator=\"|\" --property key.schema.file=\"/tmp/key_schema_file\" $force_schema_id $key_subject_name_strategy_property $value_subject_name_strategy_property $avro_use_logical_type_converters_property $producer_properties $compression $tombstone"
                            fi
                            head -n $nb_messages_to_send $output_final_file | awk -v counter=1 '{gsub("%g", counter); counter++; print}' | docker run -i --rm -v /tmp:/tmp -e SCHEMA_REGISTRY_LOG4J_OPTS="$tool_log4j_jvm_arg" -e key_schema_type=$key_schema_type -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} kafka-$key_schema_type-console-producer $parameter_for_list_broker $BOOTSTRAP_SERVERS --producer-property ssl.endpoint.identification.algorithm=https --producer-property sasl.mechanism=PLAIN --producer-property security.protocol=SASL_SSL --producer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --topic $topic $security --property value.schema.file="/tmp/value_schema_file" --property parse.key=true --property key.separator="|" --property key.schema.file="/tmp/key_schema_file" $force_schema_id $key_subject_name_strategy_property $value_subject_name_strategy_property $avro_use_logical_type_converters_property $producer_properties $compression $tombstone
                        else    
                            get_connect_image
                            if [[ -n "$verbose" ]]
                            then
                                log "🐞 CLI command used to produce data"
                                echo "cat /tmp/verbose_input_file.txt | docker run -i --rm -v /tmp:/tmp -e SCHEMA_REGISTRY_LOG4J_OPTS=\"$tool_log4j_jvm_arg\" -e value_schema_type=$value_schema_type -e BOOTSTRAP_SERVERS=\"$BOOTSTRAP_SERVERS\" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO=\"$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO\" -e SCHEMA_REGISTRY_URL=\"$SCHEMA_REGISTRY_URL\" ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} kafka-$value_schema_type-console-producer $parameter_for_list_broker $BOOTSTRAP_SERVERS --producer-property ssl.endpoint.identification.algorithm=https --producer-property sasl.mechanism=PLAIN --producer-property security.protocol=SASL_SSL --producer-property sasl.jaas.config=\"$SASL_JAAS_CONFIG\" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info=\"$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO\" --property schema.registry.url=$SCHEMA_REGISTRY_URL --topic $topic $security --property value.schema.file=/tmp/value_schema_file --property parse.key=true --property key.separator=\"|\" --property key.serializer=org.apache.kafka.common.serialization.StringSerializer $force_schema_id $key_subject_name_strategy_property $value_subject_name_strategy_property $avro_use_logical_type_converters_property $producer_properties $compression $tombstone"
                            fi
                            head -n $nb_messages_to_send $output_final_file | awk -v counter=1 '{gsub("%g", counter); counter++; print}' | docker run -i --rm -v /tmp:/tmp -e SCHEMA_REGISTRY_LOG4J_OPTS="$tool_log4j_jvm_arg" -e value_schema_type=$value_schema_type -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} kafka-$value_schema_type-console-producer $parameter_for_list_broker $BOOTSTRAP_SERVERS --producer-property ssl.endpoint.identification.algorithm=https --producer-property sasl.mechanism=PLAIN --producer-property security.protocol=SASL_SSL --producer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --topic $topic $security --property value.schema.file="/tmp/value_schema_file" --property parse.key=true --property key.separator="|" --property key.serializer=org.apache.kafka.common.serialization.StringSerializer $force_schema_id $key_subject_name_strategy_property $value_subject_name_strategy_property $avro_use_logical_type_converters_property $producer_properties $compression $tombstone
                        fi
                    fi
                else
                    if [[ -n "$headers" ]]
                    then
                        get_connect_image
                        if [[ -n "$verbose" ]]
                        then
                            log "🐞 CLI command used to produce data"
                            echo "cat /tmp/verbose_input_file.txt | docker run -i --rm -v /tmp:/tmp -e SCHEMA_REGISTRY_LOG4J_OPTS=\"$tool_log4j_jvm_arg\" -e value_schema_type=$value_schema_type -e BOOTSTRAP_SERVERS=\"$BOOTSTRAP_SERVERS\" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO=\"$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO\" -e SCHEMA_REGISTRY_URL=\"$SCHEMA_REGISTRY_URL\" ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} kafka-$value_schema_type-console-producer $parameter_for_list_broker $BOOTSTRAP_SERVERS --producer-property ssl.endpoint.identification.algorithm=https --producer-property sasl.mechanism=PLAIN --producer-property security.protocol=SASL_SSL --producer-property sasl.jaas.config=\"$SASL_JAAS_CONFIG\" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info=\"$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO\" --property schema.registry.url=$SCHEMA_REGISTRY_URL --topic $topic $security --property value.schema.file=/tmp/value_schema_file --property parse.headers=true --property headers.delimiter=\"|\" --property headers.separator=\",\" --property headers.key.separator=\":\" $force_schema_id $key_subject_name_strategy_property $value_subject_name_strategy_property $avro_use_logical_type_converters_property $producer_properties $compression $tombstone"
                        fi
                        head -n $nb_messages_to_send $output_final_file | awk -v counter=1 '{gsub("%g", counter); counter++; print}' | docker run -i --rm -v /tmp:/tmp -e SCHEMA_REGISTRY_LOG4J_OPTS="$tool_log4j_jvm_arg" -e value_schema_type=$value_schema_type -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} kafka-$value_schema_type-console-producer $parameter_for_list_broker $BOOTSTRAP_SERVERS --producer-property ssl.endpoint.identification.algorithm=https --producer-property sasl.mechanism=PLAIN --producer-property security.protocol=SASL_SSL --producer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --topic $topic $security --property value.schema.file="/tmp/value_schema_file" --property parse.headers=true --property headers.delimiter="|" --property headers.separator="," --property headers.key.separator=":" $force_schema_id $key_subject_name_strategy_property $value_subject_name_strategy_property $avro_use_logical_type_converters_property $producer_properties $compression $tombstone
                    else
                        get_connect_image
                        if [[ -n "$verbose" ]]
                        then
                            log "🐞 CLI command used to produce data"
                            echo "cat /tmp/verbose_input_file.txt | docker run -i --rm -v /tmp:/tmp -e SCHEMA_REGISTRY_LOG4J_OPTS=\"$tool_log4j_jvm_arg\" -e value_schema_type=$value_schema_type -e BOOTSTRAP_SERVERS=\"$BOOTSTRAP_SERVERS\" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO=\"$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO\" -e SCHEMA_REGISTRY_URL=\"$SCHEMA_REGISTRY_URL\" ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} kafka-$value_schema_type-console-producer $parameter_for_list_broker $BOOTSTRAP_SERVERS --producer-property ssl.endpoint.identification.algorithm=https --producer-property sasl.mechanism=PLAIN --producer-property security.protocol=SASL_SSL --producer-property sasl.jaas.config=\"$SASL_JAAS_CONFIG\" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info=\"$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO\" --property schema.registry.url=$SCHEMA_REGISTRY_URL --topic $topic $security --property value.schema.file=/tmp/value_schema_file $force_schema_id $key_subject_name_strategy_property $value_subject_name_strategy_property $avro_use_logical_type_converters_property $producer_properties $compression $tombstone"
                        fi
                        head -n $nb_messages_to_send $output_final_file | awk -v counter=1 '{gsub("%g", counter); counter++; print}' | docker run -i --rm -v /tmp:/tmp -e SCHEMA_REGISTRY_LOG4J_OPTS="$tool_log4j_jvm_arg" -e value_schema_type=$value_schema_type -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} kafka-$value_schema_type-console-producer $parameter_for_list_broker $BOOTSTRAP_SERVERS --producer-property ssl.endpoint.identification.algorithm=https --producer-property sasl.mechanism=PLAIN --producer-property security.protocol=SASL_SSL --producer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --topic $topic $security --property value.schema.file="/tmp/value_schema_file" $force_schema_id $key_subject_name_strategy_property $value_subject_name_strategy_property $avro_use_logical_type_converters_property $producer_properties $compression $tombstone
                    fi
                fi
            else
                # 🧠 remove SLF4J traces from topic produce #6254
                playground --output-level ERROR container exec --command "rm -f /usr/share/java/schema-registry/slf4j-reload4j-1.7.36.jar > /dev/null 2>&1" --root
                if [ -f $key_schema_file ]
                then
                    docker cp $key_schema_file $container:/tmp/key_schema_file > /dev/null 2>&1
                fi
                if [ -f $value_schema_file ]
                then
                    docker cp $value_schema_file $container:/tmp/value_schema_file > /dev/null 2>&1
                fi
                if [[ -n "$key" ]]
                then
                    if [[ -n "$headers" ]]
                    then
                        if [ "$key_schema_type" = "avro" ] || [ "$key_schema_type" = "protobuf" ] || [ "$key_schema_type" = "json-schema" ]
                        then
                            if [[ -n "$verbose" ]]
                            then
                                log "🐞 CLI command used to produce data"
                                echo "cat /tmp/verbose_input_file.txt | docker exec -e SCHEMA_REGISTRY_LOG4J_OPTS=\"$tool_log4j_jvm_arg\" -i $container kafka-$key_schema_type-console-producer $parameter_for_list_broker $bootstrap_server --property schema.registry.url=$sr_url_cli --topic $topic $security --property value.schema.file=/tmp/value_schema_file --property parse.key=true --property key.separator=\"|\" --property key.schema.file=\"/tmp/key_schema_file\" --property parse.headers=true --property headers.delimiter=\"|\" --property headers.separator=\",\" --property headers.key.separator=\":\" $force_schema_id $key_subject_name_strategy_property $value_subject_name_strategy_property $avro_use_logical_type_converters_property $producer_properties $compression $tombstone"
                            fi

                            head -n $nb_messages_to_send $output_final_file | awk -v counter=1 '{gsub("%g", counter); counter++; print}' | docker exec -e SCHEMA_REGISTRY_LOG4J_OPTS="$tool_log4j_jvm_arg" -i $container kafka-$key_schema_type-console-producer $parameter_for_list_broker $bootstrap_server --property schema.registry.url=$sr_url_cli --topic $topic $security --property value.schema.file="/tmp/value_schema_file" --property parse.key=true --property key.separator="|" --property key.schema.file="/tmp/key_schema_file" --property parse.headers=true --property headers.delimiter="|" --property headers.separator="," --property headers.key.separator=":" $force_schema_id $key_subject_name_strategy_property $value_subject_name_strategy_property $avro_use_logical_type_converters_property $producer_properties $compression $tombstone
                        else
                            if [[ -n "$verbose" ]]
                            then
                                log "🐞 CLI command used to produce data"
                                echo "cat /tmp/verbose_input_file.txt | docker exec -e SCHEMA_REGISTRY_LOG4J_OPTS=\"$tool_log4j_jvm_arg\" -i $container kafka-$value_schema_type-console-producer $parameter_for_list_broker $bootstrap_server --property schema.registry.url=$sr_url_cli --topic $topic $security --property value.schema.file=/tmp/value_schema_file --property parse.key=true --property key.separator=\"|\" --property key.serializer=org.apache.kafka.common.serialization.StringSerializer --property parse.headers=true --property headers.delimiter=\"|\" --property headers.separator=\",\" --property headers.key.separator=\":\" $force_schema_id $key_subject_name_strategy_property $value_subject_name_strategy_property $avro_use_logical_type_converters_property $producer_properties $compression $tombstone"
                            fi

                            head -n $nb_messages_to_send $output_final_file | awk -v counter=1 '{gsub("%g", counter); counter++; print}' | docker exec -e SCHEMA_REGISTRY_LOG4J_OPTS="$tool_log4j_jvm_arg" -i $container kafka-$value_schema_type-console-producer $parameter_for_list_broker $bootstrap_server --property schema.registry.url=$sr_url_cli --topic $topic $security --property value.schema.file="/tmp/value_schema_file" --property parse.key=true --property key.separator="|" --property key.serializer=org.apache.kafka.common.serialization.StringSerializer --property parse.headers=true --property headers.delimiter="|" --property headers.separator="," --property headers.key.separator=":" $force_schema_id $key_subject_name_strategy_property $value_subject_name_strategy_property $avro_use_logical_type_converters_property $producer_properties $compression $tombstone
                        fi
                    else
                        if [ "$key_schema_type" = "avro" ] || [ "$key_schema_type" = "protobuf" ] || [ "$key_schema_type" = "json-schema" ]
                        then
                            if [[ -n "$verbose" ]]
                            then
                                log "🐞 CLI command used to produce data"
                                echo "cat /tmp/verbose_input_file.txt | docker exec -e SCHEMA_REGISTRY_LOG4J_OPTS=\"$tool_log4j_jvm_arg\" -i $container kafka-$key_schema_type-console-producer $parameter_for_list_broker $bootstrap_server --property schema.registry.url=$sr_url_cli --topic $topic $security --property value.schema.file=/tmp/value_schema_file --property parse.key=true --property key.separator=\"|\" --property key.schema.file=\"/tmp/key_schema_file\" $force_schema_id $key_subject_name_strategy_property $value_subject_name_strategy_property $avro_use_logical_type_converters_property $producer_properties $compression $tombstone"
                            fi
                            head -n $nb_messages_to_send $output_final_file | awk -v counter=1 '{gsub("%g", counter); counter++; print}' | docker exec -e SCHEMA_REGISTRY_LOG4J_OPTS="$tool_log4j_jvm_arg" -i $container kafka-$key_schema_type-console-producer $parameter_for_list_broker $bootstrap_server --property schema.registry.url=$sr_url_cli --topic $topic $security --property value.schema.file="/tmp/value_schema_file" --property parse.key=true --property key.separator="|" --property key.schema.file="/tmp/key_schema_file" $force_schema_id $key_subject_name_strategy_property $value_subject_name_strategy_property $avro_use_logical_type_converters_property $producer_properties $compression $tombstone
                        else
                            if [[ -n "$verbose" ]]
                            then
                                log "🐞 CLI command used to produce data"
                                echo "cat /tmp/verbose_input_file.txt | docker exec -e SCHEMA_REGISTRY_LOG4J_OPTS=\"$tool_log4j_jvm_arg\" -i $container kafka-$value_schema_type-console-producer $parameter_for_list_broker $bootstrap_server --property schema.registry.url=$sr_url_cli --topic $topic $security --property value.schema.file=/tmp/value_schema_file --property parse.key=true --property key.separator=\"|\" --property key.serializer=org.apache.kafka.common.serialization.StringSerializer $force_schema_id $key_subject_name_strategy_property $value_subject_name_strategy_property $avro_use_logical_type_converters_property $producer_properties $compression $tombstone"
                            fi
                            head -n $nb_messages_to_send $output_final_file | awk -v counter=1 '{gsub("%g", counter); counter++; print}' | docker exec -e SCHEMA_REGISTRY_LOG4J_OPTS="$tool_log4j_jvm_arg" -i $container kafka-$value_schema_type-console-producer $parameter_for_list_broker $bootstrap_server --property schema.registry.url=$sr_url_cli --topic $topic $security --property value.schema.file="/tmp/value_schema_file" --property parse.key=true --property key.separator="|" --property key.serializer=org.apache.kafka.common.serialization.StringSerializer $force_schema_id $key_subject_name_strategy_property $value_subject_name_strategy_property $avro_use_logical_type_converters_property $producer_properties $compression $tombstone
                        fi
                    fi
                else
                    if [[ -n "$headers" ]]
                    then
                        if [[ -n "$verbose" ]]
                        then
                            log "🐞 CLI command used to produce data"
                            echo "cat /tmp/verbose_input_file.txt | docker exec -e SCHEMA_REGISTRY_LOG4J_OPTS=\"$tool_log4j_jvm_arg\" -i $container kafka-$key_schema_type-console-producer $parameter_for_list_broker $bootstrap_server --property schema.registry.url=$sr_url_cli --topic $topic $security --property value.schema.file=/tmp/value_schema_file --property parse.headers=true --property headers.delimiter=\"|\" --property headers.separator=\",\" --property headers.key.separator=\":\" $force_schema_id $key_subject_name_strategy_property $value_subject_name_strategy_property $avro_use_logical_type_converters_property $producer_properties $compression $tombstone"
                        fi
                        head -n $nb_messages_to_send $output_final_file | awk -v counter=1 '{gsub("%g", counter); counter++; print}' | docker exec -e SCHEMA_REGISTRY_LOG4J_OPTS="$tool_log4j_jvm_arg" -i $container kafka-$value_schema_type-console-producer $parameter_for_list_broker $bootstrap_server --property schema.registry.url=$sr_url_cli --topic $topic $security --property value.schema.file="/tmp/value_schema_file" --property parse.headers=true --property headers.delimiter="|" --property headers.separator="," --property headers.key.separator=":" $force_schema_id $key_subject_name_strategy_property $value_subject_name_strategy_property $avro_use_logical_type_converters_property $producer_properties $compression $tombstone
                    else
                        if [[ -n "$verbose" ]]
                        then
                            log "🐞 CLI command used to produce data"
                            echo "cat /tmp/verbose_input_file.txt | docker exec -e SCHEMA_REGISTRY_LOG4J_OPTS=\"$tool_log4j_jvm_arg\" -i $container kafka-$value_schema_type-console-producer $parameter_for_list_broker $bootstrap_server --property schema.registry.url=$sr_url_cli --topic $topic $security --property value.schema.file=/tmp/value_schema_file $force_schema_id $key_subject_name_strategy_property $value_subject_name_strategy_property $avro_use_logical_type_converters_property $producer_properties $compression $tombstone"
                        fi
                        head -n $nb_messages_to_send $output_final_file | awk -v counter=1 '{gsub("%g", counter); counter++; print}' | docker exec -e SCHEMA_REGISTRY_LOG4J_OPTS="$tool_log4j_jvm_arg" -i $container kafka-$value_schema_type-console-producer $parameter_for_list_broker $bootstrap_server --property schema.registry.url=$sr_url_cli --topic $topic $security --property value.schema.file="/tmp/value_schema_file" $force_schema_id $key_subject_name_strategy_property $value_subject_name_strategy_property $avro_use_logical_type_converters_property $producer_properties $compression $tombstone
                    fi
                fi
            fi
        ;;
    esac
    # Increment the number of sent messages
    nb_messages_sent=$((nb_messages_sent + nb_messages_to_send))

    if [[ $sleep_time_between_batch -gt 0 ]]
    then
        sleep $sleep_time_between_batch
    fi
    if [ $nb_messages != -1 ] && [ $should_stop -eq 1 ]
    then
        stop=1
    fi
done
ELAPSED="took: $((($SECONDS / 60) % 60))min $(($SECONDS % 60))sec"
log "📤 produced $nb_messages records to topic $topic, $ELAPSED"

if [[ -n "$consume" ]]
then
    log "📥 --consume is set, consuming topic $topic"
    playground topic consume --topic $topic
fi