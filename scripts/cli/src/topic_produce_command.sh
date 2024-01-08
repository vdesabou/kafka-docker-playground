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
sleep_time_between_batch="${args[--sleep-time-between-batch]}"
compression_codec="${args[--compression-codec]}"
# Convert the space delimited string to an array
eval "validate_config=(${args[--validate-config]})"
eval "producer_property=(${args[--producer-property]})"


tmp_dir=$(mktemp -d -t ci-XXXXXXXXXX)
trap 'rm -rf $tmp_dir' EXIT

# debug
if [[ -n "$debug" ]]
then
    log "🐞 debug mode is on"
    trap 'code $tmp_dir' EXIT
fi
key_schema_file=$tmp_dir/key_schema
value_schema_file=$tmp_dir/value_schema

if [ "$value" = "-" ]
then
    if [[ ! -n "$tombstone" ]]
    then
        # stdin
        value_content=$(cat "$value")
        echo "$value_content" > $value_schema_file
    fi
else
    if [[ $value == @* ]]
    then
        # this is a schema file
        argument_schema_file=$(echo "$value" | cut -d "@" -f 2)
        cp $argument_schema_file $value_schema_file
    elif [ -f "$value" ]
    then
        cp $value $value_schema_file
    else
        value_content=$value
        echo "$value_content" > $value_schema_file
    fi
fi

get_environment_used



get_sr_url_and_security

bootstrap_server="broker:9092"
container="connect"
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
        logerror "ERROR: $DELTA_CONFIGS_ENV has not been generated"
        exit 1
    fi
    if [ ! -f $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta ]
    then
        logerror "ERROR: $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta has not been generated"
        exit 1
    fi
fi

if [[ -n "$tombstone" ]]
then
    if [[ ! -n "$key" ]] && [[ ! -n "$forced_key" ]]
    then
        logerror "❌ --tombstone is set but neither --key or --forced-key are set!"
        exit 1
    fi
    get_connect_image
    if ! version_gt $CONNECT_TAG "7.1.99"
    then
        logerror "❌ --tombstone is set but it can be produced only with CP 7.2+"
        exit 1
    fi
    if [[ -n "$forced_key" ]]
    then
        key=$forced_key
    fi
    log "🧟 Sending tombstone for key $key in topic $topic"
    if [[ -n "$verbose" ]]
    then
        set -x
    fi
    if [[ "$environment" == "ccloud" ]]
    then
        get_connect_image
        echo "$key|NULL" | docker run -i --rm -v $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta:/tmp/configuration/ccloud.properties -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" ${CP_CONNECT_IMAGE}:${CONNECT_TAG} kafka-console-producer --broker-list $BOOTSTRAP_SERVERS --topic $topic --producer.config /tmp/configuration/ccloud.properties $security --property parse.key=true --property key.separator="|" --property null.marker=NULL
    else
        echo "$key|NULL" | docker exec -i $container kafka-console-producer --broker-list $bootstrap_server --topic $topic $security --property parse.key=true --property key.separator="|" --property null.marker=NULL
    fi
    # nothing else to do
    exit 0
fi

if [[ -n "$headers" ]]
then
    get_connect_image
    if ! version_gt $CONNECT_TAG "7.1.99"
    then
        logerror "❌ --headers is set but it can be produced only with CP 7.2+"
        exit 1
    fi
fi

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
    elif grep -q "_meta" $schema_file
    then
        log "🔮 $type schema was identified as json"
        schema_type=json
    elif grep -q "CREATE TABLE" $schema_file
    then
        log "🔮 $type schema was identified as sql"
        schema_type=sql
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

if [[ -n "$key" ]]
then
    if [[ $key == @* ]]
    then
        # this is a schema file
        argument_schema_file=$(echo "$key" | cut -d "@" -f 2)
        cp $argument_schema_file $key_schema_file
    elif [ -f "$key" ]
    then
        cp $key $key_schema_file
    else
        echo "$key" > "$key_schema_file"
    fi
    
    identify_schema "$key_schema_file" "key"
    key_schema_type=$schema_type
fi

identify_schema "$value_schema_file" "value"
value_schema_type=$schema_type

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

# https://stackoverflow.com/questions/22818814/repeat-a-file-content-until-reach-a-defined-line-count
function repcat() {
    while cat "$1"
    do 
        :
    done
}

function generate_data() {
    schema_type=$1
    schema_file=$2
    output_file=$3
    type="$4"
    input_file=""

    if [ "$value_schema_type" == "protobuf" ]
    then
        nb_max_messages_to_generate=50
    else
        if [ $record_size != 0 ]
        then
            nb_max_messages_to_generate=10
        else
            nb_max_messages_to_generate=500
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
        case "${schema_type}" in
            json|sql)
                # https://github.com/MaterializeInc/datagen
                set +e
                docker run --rm -i -v $schema_file:/app/schema.$schema_type materialize/datagen -s schema.$schema_type -n $nb_messages_to_generate --dry-run > $tmp_dir/result.log
                
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
                docker run --rm -v $tmp_dir:/tmp/ vdesabou/avro-tools random /tmp/out.avro --schema-file /tmp/$schema_file_name --count $nb_messages_to_generate
                docker run --rm -v $tmp_dir:/tmp/ vdesabou/avro-tools tojson /tmp/out.avro > $tmp_dir/out.json
            ;;
            json-schema)
                schema_file_name="$(basename "${schema_file}")"
                docker run --rm -v $tmp_dir:/tmp/ -e NB_MESSAGES=$nb_messages_to_generate -e SCHEMA=/tmp/$schema_file_name vdesabou/json-schema-faker > $tmp_dir/out.json
            ;;
            protobuf)
                # https://github.com/JasonkayZK/mock-protobuf.js
                docker run -u0 --rm -v $tmp_dir:/tmp/ -v $schema_file:/app/schema.proto -e NB_MESSAGES=$nb_messages_to_generate vdesabou/protobuf-faker bash -c "bash /app/produce.sh && chown -R $(id -u $USER):$(id -g $USER) /tmp/" > $tmp_dir/out.json
            ;;
            raw)
                if jq -e . >/dev/null 2>&1 <<< "$(cat "$schema_file")"
                then
                    log "💫 payload is single json, it will be sent as one record"
                    jq -c . "$schema_file" > $tmp_dir/minified.json
                    input_file=$tmp_dir/minified.json
                else
                    log "💫 payload is not single json, one record per line will be sent"
                    input_file=$schema_file
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

    while IFS= read -r line
    do
        if [ $record_size != 0 ]
        then
            if ! echo "$line" | jq -e .  > /dev/null 2>&1
            then
                echo "${line}PLACEHOLDER" > $record_size_temp_file_output
            else
                echo $line > $record_size_temp_file_line
                new_value="PLACEHOLDER"
                
                first_string_field=$(echo "$line" | jq -r 'path(.. | select(type == "string")) | .[-1]' | tail -1)

                if [ $lines_count -eq 0 ]
                then
                    log "🔮 Replacing first string field $first_string_field value with long payload"
                fi
                jq -c --arg new_val "$new_value" ".${first_string_field} |= \$new_val" $record_size_temp_file_line > $record_size_temp_file_output
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
        repcat "$input2_file" | head -n "$max_nb_messages_per_batch" > "$output_file"
        set -e
    elif [ $lines_count -lt $nb_messages ]
    then
        set +e
        repcat "$input2_file" | head -n "$nb_messages" > "$output_file"
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
    log "✨ generating key data..."
    generate_data "$key_schema_type" "$key_schema_file" "$output_key_file" "KEY"
fi
log "✨ generating value data..."
generate_data "$value_schema_type" "$value_schema_file" "$output_value_file" "VALUE"

nb_generated_messages=$(wc -l < $output_value_file)
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
    # merging key and value files
    paste -d "|" $output_key_file $output_value_file > $output_final_file
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

size_limit_to_show=2500
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
    tag=$(docker ps --format '{{.Image}}' | egrep 'confluentinc/cp-.*-connect-base:' | awk -F':' '{print $2}')
    if [ $? != 0 ] || [ "$tag" == "" ]
    then
        logerror "Could not find current CP version from docker ps"
        exit 1
    fi
    log "🏗 Building jar for schema-validator"
    docker run -i --rm -e TAG=$tag -v "${root_folder}/scripts/cli/src/schema-validator":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "$root_folder/scripts/settings.xml:/tmp/settings.xml" -v "${root_folder}/scripts/cli/src/schema-validator/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -s /tmp/settings.xml -Dkafka.tag=$tag package > /tmp/result.log 2>&1
    if [ $? != 0 ]
    then
        logerror "ERROR: failed to build java component schema-validator"
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

playground topic get-number-records --topic $topic > $tmp_dir/result.log 2>$tmp_dir/result.log
set +e
grep "does not exist" $tmp_dir/result.log > /dev/null 2>&1
if [ $? == 0 ]
then
    log "✨ topic $topic does not exist, it will be created.."
    if [[ "$environment" == "ccloud" ]]
    then
        if [ "$nb_partitions" != "" ]
        then
            log "⛅ creating topic in confluent cloud with $nb_partitions partitions"
            playground topic create --topic $topic --nb-partitions $nb_partitions
        else
            log "⛅ creating topic in confluent cloud"
            playground topic create --topic $topic
        fi
    else
        if [ "$nb_partitions" != "" ]
        then
            log "--nb-partitions is set, creating topic with $nb_partitions partitions"
            playground topic create --topic $topic --nb-partitions $nb_partitions
        else
            playground topic create --topic $topic
        fi
    fi
else
    if [ "$nb_partitions" != "" ]
    then
        logwarn "--nb-partitions is set, re-creating topic with $nb_partitions partitions ?"
        check_if_continue
        playground topic delete --topic $topic
        playground topic create --topic $topic --nb-partitions $nb_partitions
    else
        log "💯 Get number of records in topic $topic"
        tail -1 $tmp_dir/result.log
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

if [ $record_size -gt 1048576 ]
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
    log "⚙️ following producer properties will be used: $producer_properties"
fi

if [[ -n "$compression_codec" ]]
then
    log "🤐 --compression-codec $compression_codec will be used"
    compression="--compression-codec $compression_codec"
fi

function handle_signal {
  echo "Stopping..."
  stop=1
}
# Set the signal handler
trap handle_signal SIGINT

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
    case "${value_schema_type}" in
        json|sql|raw)
            if [[ "$environment" == "ccloud" ]]
            then
                if [[ -n "$key" ]]
                then
                    if [[ -n "$headers" ]]
                    then
                        if [[ -n "$verbose" ]]
                        then
                            log "🐞 CLI command used to produce data"
                            echo "cat /tmp/verbose_input_file.txt | kafka-console-producer --broker-list $BOOTSTRAP_SERVERS --topic $topic --producer.config /tmp/configuration/ccloud.properties $security $producer_properties $compression --property parse.key=true --property key.separator=\"|\" --property parse.headers=true --property headers.delimiter=\"|\" --property headers.separator=\",\" --property headers.key.separator=\":\""
                        fi
                        get_connect_image
                        head -n $nb_messages_to_send $output_final_file | awk -v counter=1 '{gsub("%g", counter); counter++; print}' | docker run -i --rm -v $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta:/tmp/configuration/ccloud.properties -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" ${CP_CONNECT_IMAGE}:${CONNECT_TAG} kafka-console-producer --broker-list $BOOTSTRAP_SERVERS --topic $topic --producer.config /tmp/configuration/ccloud.properties $security $producer_properties $compression --property parse.key=true --property key.separator="|" --property parse.headers=true --property headers.delimiter="|" --property headers.separator="," --property headers.key.separator=":"
                    else
                        if [[ -n "$verbose" ]]
                        then
                            log "🐞 CLI command used to produce data"
                            echo "cat /tmp/verbose_input_file.txt | kafka-console-producer --broker-list $BOOTSTRAP_SERVERS --topic $topic --producer.config /tmp/configuration/ccloud.properties $security $producer_properties $compression --property parse.key=true --property key.separator=\"|\" "
                        fi
                        get_connect_image
                        head -n $nb_messages_to_send $output_final_file | awk -v counter=1 '{gsub("%g", counter); counter++; print}' | docker run -i --rm -v $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta:/tmp/configuration/ccloud.properties -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" ${CP_CONNECT_IMAGE}:${CONNECT_TAG} kafka-console-producer --broker-list $BOOTSTRAP_SERVERS --topic $topic --producer.config /tmp/configuration/ccloud.properties $security $producer_properties $compression --property parse.key=true --property key.separator="|" 
                    fi
                else
                    if [[ -n "$headers" ]]
                    then
                        if [[ -n "$verbose" ]]
                        then
                            log "🐞 CLI command used to produce data"
                            echo "cat /tmp/verbose_input_file.txt | kafka-console-producer --broker-list $BOOTSTRAP_SERVERS --topic $topic --producer.config /tmp/configuration/ccloud.properties $security $producer_properties $compression --property parse.headers=true --property headers.delimiter=\"|\" --property headers.separator=\",\" --property headers.key.separator=\":\""
                        fi
                        get_connect_image
                        head -n $nb_messages_to_send $output_final_file | awk -v counter=1 '{gsub("%g", counter); counter++; print}' | docker run -i --rm -v $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta:/tmp/configuration/ccloud.properties -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" ${CP_CONNECT_IMAGE}:${CONNECT_TAG} kafka-console-producer --broker-list $BOOTSTRAP_SERVERS --topic $topic --producer.config /tmp/configuration/ccloud.properties $security $producer_properties $compression --property parse.headers=true --property headers.delimiter="|" --property headers.separator="," --property headers.key.separator=":"
                    else
                        if [[ -n "$verbose" ]]
                        then
                            log "🐞 CLI command used to produce data"
                            echo "cat /tmp/verbose_input_file.txt | kafka-console-producer --broker-list $BOOTSTRAP_SERVERS --topic $topic --producer.config /tmp/configuration/ccloud.properties $security $producer_properties $compression"
                        fi
                        get_connect_image
                        head -n $nb_messages_to_send $output_final_file | awk -v counter=1 '{gsub("%g", counter); counter++; print}' | docker run -i --rm -v $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta:/tmp/configuration/ccloud.properties -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" ${CP_CONNECT_IMAGE}:${CONNECT_TAG} kafka-console-producer --broker-list $BOOTSTRAP_SERVERS --topic $topic --producer.config /tmp/configuration/ccloud.properties $security $producer_properties $compression
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
                            echo "cat /tmp/verbose_input_file.txt | kafka-console-producer --broker-list $bootstrap_server --topic $topic $security $producer_properties $compression --property parse.key=true --property key.separator=\"|\" --property parse.headers=true --property headers.delimiter=\"|\" --property headers.separator=\",\" --property headers.key.separator=\":\""
                        fi
                        head -n $nb_messages_to_send $output_final_file | awk -v counter=1 '{gsub("%g", counter); counter++; print}' | docker exec -i $container kafka-console-producer --broker-list $bootstrap_server --topic $topic $security $producer_properties $compression --property parse.key=true --property key.separator="|" --property parse.headers=true --property headers.delimiter="|" --property headers.separator="," --property headers.key.separator=":"
                    else
                        if [[ -n "$verbose" ]]
                        then
                            log "🐞 CLI command used to produce data"
                            echo "cat /tmp/verbose_input_file.txt | kafka-console-producer --broker-list $bootstrap_server --topic $topic $security $producer_properties $compression --property parse.key=true --property key.separator=\"|\""
                        fi
                        head -n $nb_messages_to_send $output_final_file | awk -v counter=1 '{gsub("%g", counter); counter++; print}' | docker exec -i $container kafka-console-producer --broker-list $bootstrap_server --topic $topic $security $producer_properties $compression --property parse.key=true --property key.separator="|"
                    fi
                else
                    if [[ -n "$headers" ]]
                    then
                        if [[ -n "$verbose" ]]
                        then
                            log "🐞 CLI command used to produce data"
                            echo "cat /tmp/verbose_input_file.txt | kafka-console-producer --broker-list $bootstrap_server --topic $topic $security $producer_properties $compression --property parse.headers=true --property headers.delimiter=\"|\" --property headers.separator=\",\" --property headers.key.separator=\":\""
                        fi
                        head -n $nb_messages_to_send $output_final_file | awk -v counter=1 '{gsub("%g", counter); counter++; print}' | docker exec -i $container kafka-console-producer --broker-list $bootstrap_server --topic $topic $security $producer_properties $compression --property parse.headers=true --property headers.delimiter="|" --property headers.separator="," --property headers.key.separator=":"
                    else
                        if [[ -n "$verbose" ]]
                        then
                            log "🐞 CLI command used to produce data"
                            echo "cat /tmp/verbose_input_file.txt | kafka-console-producer --broker-list $bootstrap_server --topic $topic $security $producer_properties $compression"
                        fi
                        head -n $nb_messages_to_send $output_final_file | awk -v counter=1 '{gsub("%g", counter); counter++; print}' | docker exec -i $container kafka-console-producer --broker-list $bootstrap_server --topic $topic $security $producer_properties $compression
                    fi
                fi
            fi
        ;;
        *)
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
            if [[ "$environment" == "ccloud" ]]
            then
                cp $root_folder/scripts/cli/src/tools-log4j.properties /tmp/tools-log4j.properties > /dev/null 2>&1
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
                            if [[ -n "$verbose" ]]
                            then
                                log "🐞 CLI command used to produce data"
                                echo "cat /tmp/verbose_input_file.txt | kafka-$value_schema_type-console-producer --broker-list $BOOTSTRAP_SERVERS --producer-property ssl.endpoint.identification.algorithm=https --producer-property sasl.mechanism=PLAIN --producer-property security.protocol=SASL_SSL --producer-property sasl.jaas.config=\"$SASL_JAAS_CONFIG\" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info=\"$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO\" --property schema.registry.url=$SCHEMA_REGISTRY_URL --topic $topic $security --property value.schema.file="/tmp/value_schema_file" --property parse.key=true --property key.separator=\"|\" --property key.schema.file="/tmp/key_schema_file" --property parse.headers=true --property headers.delimiter=\"|\" --property headers.separator=\",\" --property headers.key.separator=\":\" $key_subject_name_strategy_property $value_subject_name_strategy_property $producer_properties $compression"
                            fi
                            get_connect_image
                            head -n $nb_messages_to_send $output_final_file | awk -v counter=1 '{gsub("%g", counter); counter++; print}' | docker run -i --rm -v /tmp:/tmp -e SCHEMA_REGISTRY_LOG4J_OPTS="-Dlog4j.configuration=file:/tmp/tools-log4j.properties" -e value_schema_type=$value_schema_type -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" ${CP_CONNECT_IMAGE}:${CONNECT_TAG} kafka-$value_schema_type-console-producer --broker-list $BOOTSTRAP_SERVERS --producer-property ssl.endpoint.identification.algorithm=https --producer-property sasl.mechanism=PLAIN --producer-property security.protocol=SASL_SSL --producer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --topic $topic $security --property value.schema.file="/tmp/value_schema_file" --property parse.key=true --property key.separator="|" --property key.schema.file="/tmp/key_schema_file" --property parse.headers=true --property headers.delimiter="|" --property headers.separator="," --property headers.key.separator=":" $key_subject_name_strategy_property $value_subject_name_strategy_property $producer_properties $compression
                        else
                            if [[ -n "$verbose" ]]
                            then
                                log "🐞 CLI command used to produce data"
                                echo "cat /tmp/verbose_input_file.txt | kafka-$value_schema_type-console-producer --broker-list $BOOTSTRAP_SERVERS --producer-property ssl.endpoint.identification.algorithm=https --producer-property sasl.mechanism=PLAIN --producer-property security.protocol=SASL_SSL --producer-property sasl.jaas.config=\"$SASL_JAAS_CONFIG\" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info=\"$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO\" --property schema.registry.url=$SCHEMA_REGISTRY_URL --topic $topic $security --property value.schema.file="/tmp/value_schema_file" --property parse.key=true --property key.separator=\"|\" --property key.serializer=org.apache.kafka.common.serialization.StringSerializer --property parse.headers=true --property headers.delimiter=\"|\" --property headers.separator=\",\" --property headers.key.separator=\":\" $key_subject_name_strategy_property $value_subject_name_strategy_property $producer_properties $compression"
                            fi
                            get_connect_image
                            head -n $nb_messages_to_send $output_final_file | awk -v counter=1 '{gsub("%g", counter); counter++; print}' | docker run -i --rm -v /tmp:/tmp -e SCHEMA_REGISTRY_LOG4J_OPTS="-Dlog4j.configuration=file:/tmp/tools-log4j.properties" -e value_schema_type=$value_schema_type -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" ${CP_CONNECT_IMAGE}:${CONNECT_TAG} kafka-$value_schema_type-console-producer --broker-list $BOOTSTRAP_SERVERS --producer-property ssl.endpoint.identification.algorithm=https --producer-property sasl.mechanism=PLAIN --producer-property security.protocol=SASL_SSL --producer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --topic $topic $security --property value.schema.file="/tmp/value_schema_file" --property parse.key=true --property key.separator="|" --property key.serializer=org.apache.kafka.common.serialization.StringSerializer --property parse.headers=true --property headers.delimiter="|" --property headers.separator="," --property headers.key.separator=":" $key_subject_name_strategy_property $value_subject_name_strategy_property $producer_properties $compression
                        fi
                    else
                        if [ "$key_schema_type" = "avro" ] || [ "$key_schema_type" = "protobuf" ] || [ "$key_schema_type" = "json-schema" ]
                        then
                            if [[ -n "$verbose" ]]
                            then
                                log "🐞 CLI command used to produce data"
                                echo "cat /tmp/verbose_input_file.txt | kafka-$value_schema_type-console-producer --broker-list $BOOTSTRAP_SERVERS --producer-property ssl.endpoint.identification.algorithm=https --producer-property sasl.mechanism=PLAIN --producer-property security.protocol=SASL_SSL --producer-property sasl.jaas.config=\"$SASL_JAAS_CONFIG\" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info=\"$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO\" --property schema.registry.url=$SCHEMA_REGISTRY_URL --topic $topic $security --property value.schema.file="/tmp/value_schema_file" --property parse.key=true --property key.separator=\"|\" --property key.schema.file="/tmp/key_schema_file" $key_subject_name_strategy_property $value_subject_name_strategy_property $producer_properties $compression"
                            fi
                            get_connect_image
                            head -n $nb_messages_to_send $output_final_file | awk -v counter=1 '{gsub("%g", counter); counter++; print}' | docker run -i --rm -v /tmp:/tmp -e SCHEMA_REGISTRY_LOG4J_OPTS="-Dlog4j.configuration=file:/tmp/tools-log4j.properties" -e value_schema_type=$value_schema_type -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" ${CP_CONNECT_IMAGE}:${CONNECT_TAG} kafka-$value_schema_type-console-producer --broker-list $BOOTSTRAP_SERVERS --producer-property ssl.endpoint.identification.algorithm=https --producer-property sasl.mechanism=PLAIN --producer-property security.protocol=SASL_SSL --producer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --topic $topic $security --property value.schema.file="/tmp/value_schema_file" --property parse.key=true --property key.separator="|" --property key.schema.file="/tmp/key_schema_file" $key_subject_name_strategy_property $value_subject_name_strategy_property $producer_properties $compression
                        else
                            if [[ -n "$verbose" ]]
                            then
                                log "🐞 CLI command used to produce data"
                                echo "cat /tmp/verbose_input_file.txt | kafka-$value_schema_type-console-producer --broker-list $BOOTSTRAP_SERVERS --producer-property ssl.endpoint.identification.algorithm=https --producer-property sasl.mechanism=PLAIN --producer-property security.protocol=SASL_SSL --producer-property sasl.jaas.config=\"$SASL_JAAS_CONFIG\" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info=\"$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO\" --property schema.registry.url=$SCHEMA_REGISTRY_URL --topic $topic $security --property value.schema.file="/tmp/value_schema_file" --property parse.key=true --property key.separator=\"|\" --property key.serializer=org.apache.kafka.common.serialization.StringSerializer $key_subject_name_strategy_property $value_subject_name_strategy_property $producer_properties $compression"
                            fi
                            get_connect_image
                            head -n $nb_messages_to_send $output_final_file | awk -v counter=1 '{gsub("%g", counter); counter++; print}' | docker run -i --rm -v /tmp:/tmp -e SCHEMA_REGISTRY_LOG4J_OPTS="-Dlog4j.configuration=file:/tmp/tools-log4j.properties" -e value_schema_type=$value_schema_type -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" ${CP_CONNECT_IMAGE}:${CONNECT_TAG} kafka-$value_schema_type-console-producer --broker-list $BOOTSTRAP_SERVERS --producer-property ssl.endpoint.identification.algorithm=https --producer-property sasl.mechanism=PLAIN --producer-property security.protocol=SASL_SSL --producer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --topic $topic $security --property value.schema.file="/tmp/value_schema_file" --property parse.key=true --property key.separator="|" --property key.serializer=org.apache.kafka.common.serialization.StringSerializer $key_subject_name_strategy_property $value_subject_name_strategy_property $producer_properties $compression
                        fi
                    fi
                else
                    if [[ -n "$headers" ]]
                    then
                        if [[ -n "$verbose" ]]
                        then
                            log "🐞 CLI command used to produce data"
                            echo "cat /tmp/verbose_input_file.txt | kafka-$value_schema_type-console-producer --broker-list $BOOTSTRAP_SERVERS --producer-property ssl.endpoint.identification.algorithm=https --producer-property sasl.mechanism=PLAIN --producer-property security.protocol=SASL_SSL --producer-property sasl.jaas.config=\"$SASL_JAAS_CONFIG\" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info=\"$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO\" --property schema.registry.url=$SCHEMA_REGISTRY_URL --topic $topic $security --property value.schema.file="/tmp/value_schema_file" --property parse.headers=true --property headers.delimiter=\"|\" --property headers.separator=\",\" --property headers.key.separator=\":\" $key_subject_name_strategy_property $value_subject_name_strategy_property $producer_properties $compression"
                        fi
                        get_connect_image
                        head -n $nb_messages_to_send $output_final_file | awk -v counter=1 '{gsub("%g", counter); counter++; print}' | docker run -i --rm -v /tmp:/tmp -e SCHEMA_REGISTRY_LOG4J_OPTS="-Dlog4j.configuration=file:/tmp/tools-log4j.properties" -e value_schema_type=$value_schema_type -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" ${CP_CONNECT_IMAGE}:${CONNECT_TAG} kafka-$value_schema_type-console-producer --broker-list $BOOTSTRAP_SERVERS --producer-property ssl.endpoint.identification.algorithm=https --producer-property sasl.mechanism=PLAIN --producer-property security.protocol=SASL_SSL --producer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --topic $topic $security --property value.schema.file="/tmp/value_schema_file" --property parse.headers=true --property headers.delimiter="|" --property headers.separator="," --property headers.key.separator=":" $key_subject_name_strategy_property $value_subject_name_strategy_property $producer_properties $compression
                    else
                        if [[ -n "$verbose" ]]
                        then
                            log "🐞 CLI command used to produce data"
                            echo "cat /tmp/verbose_input_file.txt | kafka-$value_schema_type-console-producer --broker-list $BOOTSTRAP_SERVERS --producer-property ssl.endpoint.identification.algorithm=https --producer-property sasl.mechanism=PLAIN --producer-property security.protocol=SASL_SSL --producer-property sasl.jaas.config=\"$SASL_JAAS_CONFIG\" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info=\"$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO\" --property schema.registry.url=$SCHEMA_REGISTRY_URL --topic $topic $security --property value.schema.file="/tmp/value_schema_file" $key_subject_name_strategy_property $value_subject_name_strategy_property $producer_properties $compression"
                        fi
                        get_connect_image
                        head -n $nb_messages_to_send $output_final_file | awk -v counter=1 '{gsub("%g", counter); counter++; print}' | docker run -i --rm -v /tmp:/tmp -e SCHEMA_REGISTRY_LOG4J_OPTS="-Dlog4j.configuration=file:/tmp/tools-log4j.properties" -e value_schema_type=$value_schema_type -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" ${CP_CONNECT_IMAGE}:${CONNECT_TAG} kafka-$value_schema_type-console-producer --broker-list $BOOTSTRAP_SERVERS --producer-property ssl.endpoint.identification.algorithm=https --producer-property sasl.mechanism=PLAIN --producer-property security.protocol=SASL_SSL --producer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --topic $topic $security --property value.schema.file="/tmp/value_schema_file" $key_subject_name_strategy_property $value_subject_name_strategy_property $producer_properties $compression
                    fi
                fi
            else
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
                        docker cp $root_folder/scripts/cli/src/tools-log4j.properties $container:/tmp/tools-log4j.properties > /dev/null 2>&1
                        if [ "$key_schema_type" = "avro" ] || [ "$key_schema_type" = "protobuf" ] || [ "$key_schema_type" = "json-schema" ]
                        then
                            if [[ -n "$verbose" ]]
                            then
                                log "🐞 CLI command used to produce data"
                                echo "cat /tmp/verbose_input_file.txt | kafka-$value_schema_type-console-producer --broker-list $bootstrap_server --property schema.registry.url=$sr_url_cli --topic $topic $security --property value.schema.file="/tmp/value_schema_file" --property parse.key=true --property key.separator=\"|\" --property key.schema.file="/tmp/key_schema_file" --property parse.headers=true --property headers.delimiter=\"|\" --property headers.separator=\",\" --property headers.key.separator=\":\" $key_subject_name_strategy_property $value_subject_name_strategy_property $producer_properties $compression"
                            fi

                            head -n $nb_messages_to_send $output_final_file | awk -v counter=1 '{gsub("%g", counter); counter++; print}' | docker exec -e SCHEMA_REGISTRY_LOG4J_OPTS="-Dlog4j.configuration=file:/tmp/tools-log4j.properties" -i $container kafka-$value_schema_type-console-producer --broker-list $bootstrap_server --property schema.registry.url=$sr_url_cli --topic $topic $security --property value.schema.file="/tmp/value_schema_file" --property parse.key=true --property key.separator="|" --property key.schema.file="/tmp/key_schema_file" --property parse.headers=true --property headers.delimiter="|" --property headers.separator="," --property headers.key.separator=":" $key_subject_name_strategy_property $value_subject_name_strategy_property $producer_properties $compression
                        else
                            if [[ -n "$verbose" ]]
                            then
                                log "🐞 CLI command used to produce data"
                                echo "cat /tmp/verbose_input_file.txt | kafka-$value_schema_type-console-producer --broker-list $bootstrap_server --property schema.registry.url=$sr_url_cli --topic $topic $security --property value.schema.file="/tmp/value_schema_file" --property parse.key=true --property key.separator=\"|\" --property key.serializer=org.apache.kafka.common.serialization.StringSerializer --property parse.headers=true --property headers.delimiter=\"|\" --property headers.separator=\",\" --property headers.key.separator=\":\" $key_subject_name_strategy_property $value_subject_name_strategy_property $producer_properties $compression"
                            fi

                            head -n $nb_messages_to_send $output_final_file | awk -v counter=1 '{gsub("%g", counter); counter++; print}' | docker exec -e SCHEMA_REGISTRY_LOG4J_OPTS="-Dlog4j.configuration=file:/tmp/tools-log4j.properties" -i $container kafka-$value_schema_type-console-producer --broker-list $bootstrap_server --property schema.registry.url=$sr_url_cli --topic $topic $security --property value.schema.file="/tmp/value_schema_file" --property parse.key=true --property key.separator="|" --property key.serializer=org.apache.kafka.common.serialization.StringSerializer --property parse.headers=true --property headers.delimiter="|" --property headers.separator="," --property headers.key.separator=":" $key_subject_name_strategy_property $value_subject_name_strategy_property $producer_properties $compression
                        fi
                    else
                        docker cp $root_folder/scripts/cli/src/tools-log4j.properties $container:/tmp/tools-log4j.properties > /dev/null 2>&1
                        if [ "$key_schema_type" = "avro" ] || [ "$key_schema_type" = "protobuf" ] || [ "$key_schema_type" = "json-schema" ]
                        then
                            if [[ -n "$verbose" ]]
                            then
                                log "🐞 CLI command used to produce data"
                                echo "cat /tmp/verbose_input_file.txt | kafka-$value_schema_type-console-producer --broker-list $bootstrap_server --property schema.registry.url=$sr_url_cli --topic $topic $security --property value.schema.file="/tmp/value_schema_file" --property parse.key=true --property key.separator=\"|\" --property key.schema.file="/tmp/key_schema_file" $key_subject_name_strategy_property $value_subject_name_strategy_property $producer_properties $compression"
                            fi
                            head -n $nb_messages_to_send $output_final_file | awk -v counter=1 '{gsub("%g", counter); counter++; print}' | docker exec -e SCHEMA_REGISTRY_LOG4J_OPTS="-Dlog4j.configuration=file:/tmp/tools-log4j.properties" -i $container kafka-$value_schema_type-console-producer --broker-list $bootstrap_server --property schema.registry.url=$sr_url_cli --topic $topic $security --property value.schema.file="/tmp/value_schema_file" --property parse.key=true --property key.separator="|" --property key.schema.file="/tmp/key_schema_file" $key_subject_name_strategy_property $value_subject_name_strategy_property $producer_properties $compression
                        else
                            if [[ -n "$verbose" ]]
                            then
                                log "🐞 CLI command used to produce data"
                                echo "cat /tmp/verbose_input_file.txt | kafka-$value_schema_type-console-producer --broker-list $bootstrap_server --property schema.registry.url=$sr_url_cli --topic $topic $security --property value.schema.file="/tmp/value_schema_file" --property parse.key=true --property key.separator=\"|\" --property key.serializer=org.apache.kafka.common.serialization.StringSerializer $key_subject_name_strategy_property $value_subject_name_strategy_property $producer_properties $compression"
                            fi
                            head -n $nb_messages_to_send $output_final_file | awk -v counter=1 '{gsub("%g", counter); counter++; print}' | docker exec -e SCHEMA_REGISTRY_LOG4J_OPTS="-Dlog4j.configuration=file:/tmp/tools-log4j.properties" -i $container kafka-$value_schema_type-console-producer --broker-list $bootstrap_server --property schema.registry.url=$sr_url_cli --topic $topic $security --property value.schema.file="/tmp/value_schema_file" --property parse.key=true --property key.separator="|" --property key.serializer=org.apache.kafka.common.serialization.StringSerializer $key_subject_name_strategy_property $value_subject_name_strategy_property $producer_properties $compression
                        fi
                    fi
                else
                    docker cp $root_folder/scripts/cli/src/tools-log4j.properties $container:/tmp/tools-log4j.properties > /dev/null 2>&1
                    if [[ -n "$headers" ]]
                    then
                        if [[ -n "$verbose" ]]
                        then
                            log "🐞 CLI command used to produce data"
                            echo "cat /tmp/verbose_input_file.txt | kafka-$value_schema_type-console-producer --broker-list $bootstrap_server --property schema.registry.url=$sr_url_cli --topic $topic $security --property value.schema.file="/tmp/value_schema_file" --property parse.headers=true --property headers.delimiter=\"|\" --property headers.separator=\",\" --property headers.key.separator=\":\" $key_subject_name_strategy_property $value_subject_name_strategy_property $producer_properties $compression"
                        fi
                        head -n $nb_messages_to_send $output_final_file | awk -v counter=1 '{gsub("%g", counter); counter++; print}' | docker exec -e SCHEMA_REGISTRY_LOG4J_OPTS="-Dlog4j.configuration=file:/tmp/tools-log4j.properties" -i $container kafka-$value_schema_type-console-producer --broker-list $bootstrap_server --property schema.registry.url=$sr_url_cli --topic $topic $security --property value.schema.file="/tmp/value_schema_file" --property parse.headers=true --property headers.delimiter="|" --property headers.separator="," --property headers.key.separator=":" $key_subject_name_strategy_property $value_subject_name_strategy_property $producer_properties $compression
                    else
                        if [[ -n "$verbose" ]]
                        then
                            log "🐞 CLI command used to produce data"
                            echo "cat /tmp/verbose_input_file.txt | kafka-$value_schema_type-console-producer --broker-list $bootstrap_server --property schema.registry.url=$sr_url_cli --topic $topic $security --property value.schema.file="/tmp/value_schema_file" $key_subject_name_strategy_property $value_subject_name_strategy_property $producer_properties $compression"
                        fi
                        head -n $nb_messages_to_send $output_final_file | awk -v counter=1 '{gsub("%g", counter); counter++; print}' | docker exec -e SCHEMA_REGISTRY_LOG4J_OPTS="-Dlog4j.configuration=file:/tmp/tools-log4j.properties" -i $container kafka-$value_schema_type-console-producer --broker-list $bootstrap_server --property schema.registry.url=$sr_url_cli --topic $topic $security --property value.schema.file="/tmp/value_schema_file" $key_subject_name_strategy_property $value_subject_name_strategy_property $producer_properties $compression
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
playground topic get-number-records --topic $topic