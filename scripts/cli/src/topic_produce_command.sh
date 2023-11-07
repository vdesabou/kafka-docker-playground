topic="${args[--topic]}"
verbose="${args[--verbose]}"
nb_messages="${args[--nb-messages]}"
nb_partitions="${args[--nb-partitions]}"
schema="${args[--input]}"
key="${args[--key]}"
headers="${args[--headers]}"
forced_value="${args[--forced-value]}"
generate_only="${args[--generate-only]}"
tombstone="${args[--tombstone]}"
compatibility="${args[--compatibility]}"
value_subject_name_strategy="${args[--value-subject-name-strategy]}"
validate="${args[--validate]}"
record_size="${args[--record-size]}"
# Convert the space delimited string to an array
eval "validate_config=(${args[--validate-config]})"
eval "producer_property=(${args[--producer-property]})"


tmp_dir=$(mktemp -d -t ci-XXXXXXXXXX)
trap 'rm -rf $tmp_dir' EXIT
#log "tmp_dir is $tmp_dir"
schema_file=$tmp_dir/value_schema

if [ "$schema" = "-" ]
then
    if [[ ! -n "$tombstone" ]]
    then
        # stdin
        schema_content=$(cat "$schema")
        echo "$schema_content" > $schema_file
    fi
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

environment=`get_environment_used`

if [ "$environment" == "error" ]
then
  logerror "File containing restart command /tmp/playground-command does not exist!"
  exit 1 
fi

ret=$(get_sr_url_and_security)

sr_url=$(echo "$ret" | cut -d "@" -f 1)
sr_security=$(echo "$ret" | cut -d "@" -f 2)

bootstrap_server="broker:9092"
container="connect"
sr_url_cli="http://schema-registry:8081"
security=""
if [[ "$environment" == *"ssl"* ]]
then
    sr_url_cli="https://schema-registry:8081"
    security="--property schema.registry.ssl.truststore.location=/etc/kafka/secrets/kafka.client.truststore.jks --property schema.registry.ssl.truststore.password=confluent --property schema.registry.ssl.keystore.location=/etc/kafka/secrets/kafka.client.keystore.jks --property schema.registry.ssl.keystore.password=confluent --producer.config /etc/kafka/secrets/client_without_interceptors.config"
elif [[ "$environment" == "rbac-sasl-plain" ]]
then
    sr_url_cli="http://schema-registry:8081"
    security="--property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info=clientAvroCli:clientAvroCli --producer.config /etc/kafka/secrets/client_without_interceptors.config"
elif [[ "$environment" == "ldap-authorizer-sasl-plain" ]]
then
    sr_url_cli="http://schema-registry:8081"
    security="--producer.config /service/kafka/users/alice.properties"
elif [[ "$environment" == "sasl-plain" ]]
then
    sr_url_cli="http://schema-registry:8081"
    security="--producer.config /tmp/client.properties"
elif [[ "$environment" == "kerberos" ]]
then
    container="client"
    sr_url_cli="http://schema-registry:8081"
    security="--producer.config /etc/kafka/producer.properties"

    docker exec -i client kinit -k -t /var/lib/secret/kafka-connect.key connect
elif [[ "$environment" == "environment" ]]
then
  if [ -f /tmp/delta_configs/env.delta ]
  then
      source /tmp/delta_configs/env.delta
  else
      logerror "ERROR: /tmp/delta_configs/env.delta has not been generated"
      exit 1
  fi
  if [ ! -f /tmp/delta_configs/ak-tools-ccloud.delta ]
  then
      logerror "ERROR: /tmp/delta_configs/ak-tools-ccloud.delta has not been generated"
      exit 1
  fi
fi

DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
dir1=$(echo ${DIR_CLI%/*})
root_folder=$(echo ${dir1%/*})
IGNORE_CHECK_FOR_DOCKER_COMPOSE=true
source $root_folder/scripts/utils.sh

if [[ -n "$tombstone" ]]
then
    if [[ ! -n "$key" ]]
    then
        logerror "❌ --tombstone is set but not --key !"
        exit 1
    fi
    if ! version_gt $CONNECT_TAG "7.1.99"
    then
        logerror "❌ --tombstone is set but it can be produced only with CP 7.2+"
        exit 1
    fi
    log "🧟 Sending tombstone for key $key in topic $topic"
    if [[ -n "$verbose" ]]
    then
        set -x
    fi
    if [[ "$environment" == "environment" ]]
    then
        echo "$key|NULL" | docker run -i --rm -v /tmp/delta_configs/ak-tools-ccloud.delta:/tmp/configuration/ccloud.properties -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" ${CP_CONNECT_IMAGE}:${CONNECT_TAG} kafka-console-producer --broker-list $BOOTSTRAP_SERVERS --topic $topic --producer.config /tmp/configuration/ccloud.properties $security --property parse.key=true --property key.separator="|" --property null.marker=NULL
    else
        echo "$key|NULL" | docker exec -i $container kafka-console-producer --broker-list $bootstrap_server --topic $topic $security --property parse.key=true --property key.separator="|" --property null.marker=NULL
    fi
    # nothing else to do
    exit 0
fi

if [[ -n "$headers" ]]
then
    if ! version_gt $CONNECT_TAG "7.1.99"
    then
        logerror "❌ --headers is set but it can be produced only with CP 7.2+"
        exit 1
    fi
fi

if grep -q "proto3" $schema_file
then
    log "🔮 schema was identified as protobuf"
    schema_type=protobuf
elif grep -q "\"type\"\s*:\s*\"object\"" $schema_file
then
    log "🔮 schema was identified as json schema"
    schema_type=json-schema
elif grep -q "_meta" $schema_file
then
    log "🔮 schema was identified as json"
    schema_type=json
elif grep -q "CREATE TABLE" $schema_file
then
    log "🔮 schema was identified as sql"
    schema_type=sql
elif grep -q "\"type\"\s*:\s*\"record\"" $schema_file
then
    log "🔮 schema was identified as avro"
    schema_type=avro
else
    log "📢 no known schema could be identified, payload will be sent as raw data"
    schema_type=raw
fi
log "✨ generating data..."
if [ "$schema_type" == "protobuf" ]
then
    nb_max_messages_to_generate=50
else
    nb_max_messages_to_generate=1000
fi
if [ $nb_messages -lt $nb_max_messages_to_generate ]
then
    nb_messages_to_generate=$nb_messages
else
    nb_messages_to_generate=$nb_max_messages_to_generate
fi
if [[ -n "$validate" ]]
then
    if [ $nb_messages != 1 ]
    then
        logwarn "--validate is set, ignoring --nb-messages"
        nb_messages=1
    fi
fi
input_file=""

if [[ -n "$forced_value" ]]
then
    log "☢️ --forced-value is set"
    echo "$forced_value" > $tmp_dir/out.json
else
    SECONDS=0
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
            cat $tmp_dir/result.log | grep "Payload: " | sed 's/Payload: //' > $tmp_dir/out.json
        ;;
        avro)
            docker run --rm -v $tmp_dir:/tmp/ vdesabou/avro-tools random /tmp/out.avro --schema-file /tmp/value_schema --count $nb_messages_to_generate
            docker run --rm -v $tmp_dir:/tmp/ vdesabou/avro-tools tojson /tmp/out.avro > $tmp_dir/out.json
        ;;
        json-schema)
            docker run --rm -v $tmp_dir:/tmp/ -e NB_MESSAGES=$nb_messages_to_generate vdesabou/json-schema-faker > $tmp_dir/out.json
        ;;
        protobuf)
            # https://github.com/JasonkayZK/mock-protobuf.js
            docker run --rm -v $tmp_dir:/tmp/ -v $schema_file:/app/schema.proto -e NB_MESSAGES=$nb_messages_to_generate vdesabou/protobuf-faker  > $tmp_dir/out.json
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
output_file=$tmp_dir/out_final.json
record_size_temp_file_line=$tmp_dir/line.json
record_size_temp_file_output=$tmp_dir/output.json

max_batch=300000
lines_count=0
stop=0
counter=1
while [ $stop != 1 ]
do
    while IFS= read -r line
    do
        if [[ $line == *"%g"* ]]
        then
            line=${line/\%g/$counter}
        fi

        if [ $record_size != 0 ]
        then
            if ! echo "$line" | jq -e .  > /dev/null 2>&1
            then
                echo "${line}PLACEHOLDER" > $record_size_temp_file_output
            else
                echo $line > $record_size_temp_file_line
                new_value="PLACEHOLDER"
                
                first_string_field=$(echo "$line" | jq -r 'path(.. | select(type == "string")) | .[-1]' | tail -1)

                log "🔮 Replacing first string field $first_string_field value with long payload"
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

                cat $record_size_temp_file_output >> "$output_file"
                # Remove temp file
                rm temp.txt
            else
                log "❌ record-size is too small"
                exit 1
            fi
        else
            echo "$line" >> "$output_file"
        fi

        lines_count=$((lines_count+1))
        if [ $lines_count -ge $max_batch ]
        then
            stop=1
            break
        fi
        if [ $lines_count -ge $nb_messages ]
        then
            stop=1
            break
        fi
        counter=$((counter+1))
    done < "$input_file"
done

nb_generated_messages=$(wc -l < $output_file)
nb_generated_messages=${nb_generated_messages// /}

if [ "$nb_generated_messages" == "0" ]
then
    logerror "❌ records could not be generated!"
    exit 1
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
    head -n 1 "$output_file" | cut -c 1-${size_limit_to_show} | awk "{print \$0 \"...<truncated, only showing first $size_limit_to_show characters, out of $record_size>...\"}"
else
    if (( nb_generated_messages < 10 ))
    then
        log "✨ $nb_generated_messages records were generated$value_str"
        cat "$output_file"
    else
        log "✨ $nb_generated_messages records were generated$value_str (only showing first 10), $ELAPSED"
        head -n 10 "$output_file"
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

    set +e
    log "🏗 Building jar for schema-validator"
    docker run -i --rm -e TAG=$TAG_BASE -v "${root_folder}/scripts/cli/src/schema-validator":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "$root_folder/scripts/settings.xml:/tmp/settings.xml" -v "${root_folder}/scripts/cli/src/schema-validator/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -s /tmp/settings.xml -Dkafka.tag=$TAG package > /tmp/result.log 2>&1
    if [ $? != 0 ]
    then
        logerror "ERROR: failed to build java component schema-validator"
        tail -500 /tmp/result.log
        exit 1
    fi
    set -e

    docker cp ${root_folder}/scripts/cli/src/schema-validator/target/schema-validator-1.0.0-jar-with-dependencies.jar connect:/tmp/schema-validator-1.0.0-jar-with-dependencies.jar > /dev/null 2>&1
    docker cp $schema_file connect:/tmp/schema > /dev/null 2>&1
    docker cp $tmp_dir/out.json connect:/tmp/message.json > /dev/null 2>&1
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

    docker exec $env_list -e SCHEMA_TYPE=$schema_type connect bash -c "java -jar /tmp/schema-validator-1.0.0-jar-with-dependencies.jar" > $tmp_dir/result.log
    set +e
    nb=$(grep -c "ERROR" $tmp_dir/result.log)
    if [ $nb -ne 0 ]
    then
        logerror "❌ schema is not valid according to $schema_type converter"
        cat $tmp_dir/result.log
        exit 1
    else
        log "👌 schema is valid according to $schema_type converter"
    fi
    set -e
fi

playground topic get-number-records --topic $topic > $tmp_dir/result.log 2>$tmp_dir/result.log
set +e
grep "does not exist" $tmp_dir/result.log > /dev/null 2>&1
if [ $? == 0 ]
then
    log "✨ topic $topic does not exist, it will be created.."
    if [[ "$environment" == "environment" ]]
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

case "${schema_type}" in
    avro|json-schema|protobuf)

    ;;
    *)
        if [[ -n "$validate" ]]
        then
            logerror "❌ --validate is set but $schema_type is used. This is only valid for avro|json-schema|protobuf"
            exit 1
        fi
        if [[ -n "$value_subject_name_strategy" ]]
        then
            logerror "❌ --value-subject-name-strategy is set but $schema_type is used. This is only valid for avro|json-schema|protobuf"
            exit 1 
        fi
    ;;
esac

if [[ -n "$key" ]]
then
    if [[ $key =~ ^([^0-9]*)([0-9]+)([^0-9]*)$ ]]; then
        prefix="${BASH_REMATCH[1]}"
        number="${BASH_REMATCH[2]}"
        suffix="${BASH_REMATCH[3]}"
        
        log "🗝️ key $key is set with a number $number, it will be used as starting point"
        while read -r line
        do
            new_key="${prefix}${number}${suffix}"
            echo "${new_key}|${line}" >> "$tmp_dir/tempfile"
            number=$((number + 1))
        done < "$output_file"

        mv "$tmp_dir/tempfile" "$output_file"
    else
        counter=1
        log "🗝️ key is set with a string $key, it will be used for all records"
        while read -r line
        do
            if [[ $key == *"%g"* ]]
            then
                key=${key/\%g/$counter}
            fi
            echo "${key}|${line}" >> "$tmp_dir/tempfile"
        done < "$output_file"

        mv "$tmp_dir/tempfile" "$output_file"
    fi
fi

if [[ -n "$headers" ]]
then
    log "🚏 headers are set $headers"
    while read line
    do
        echo "${headers}|${line}" >> $tmp_dir/tempfile
    done < $output_file

    mv $tmp_dir/tempfile $output_file
fi

producer_properties=""

if [ $record_size -gt 1048576 ]
then
    log "✨ record-size $record_size is greater than 1Mb (1048576), setting --producer-property max.request.size=$((record_size + 1000)) and --producer-property buffer.memory=67108864"
    producer_properties="--producer-property max.request.size=$((record_size + 1000)) --producer-property buffer.memory=67108864"
    log "✨ topic $topic max.message.bytes is also set to $((record_size + 1000))"
    playground topic alter --topic $topic --add-config max.message.bytes=$((record_size + 1000))
fi

for producer_prop in "${producer_property[@]}"
do
    producer_properties="$producer_properties --producer-property $producer_prop"
done

if [ "$producer_properties" != "" ]
then
    log "Following producer properties will be used: $producer_properties"
fi

set -e
SECONDS=0
log "📤 producing $nb_messages records to topic $topic"
if [ $nb_messages -gt $max_batch ]
then
    log "✨ it will be done in batches of maximum $max_batch records"
fi
nb_messages_sent=0
nb_messages_to_send=0
stop=0
should_stop=0
while [ $stop != 1 ]
do
    if [ $((nb_messages_sent + nb_generated_messages)) -le $nb_messages ]
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
    if [ $nb_messages -gt $max_batch ]
    then
        log "📤 producing a batch of $nb_messages_to_send records to topic $topic"
        log "💯 $nb_messages_sent/$nb_messages records sent so far..."
    fi
    case "${schema_type}" in
        json|sql|raw)
            if [[ "$environment" == "environment" ]]
            then
                if [[ -n "$key" ]]
                then
                    if [[ -n "$headers" ]]
                    then
                        if [[ -n "$verbose" ]]
                        then
                            set -x
                        fi
                        head -n $nb_messages_to_send $output_file | docker run -i --rm -v /tmp/delta_configs/ak-tools-ccloud.delta:/tmp/configuration/ccloud.properties -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" ${CP_CONNECT_IMAGE}:${CONNECT_TAG} kafka-console-producer --broker-list $BOOTSTRAP_SERVERS --topic $topic --producer.config /tmp/configuration/ccloud.properties $security $producer_properties --property parse.key=true --property key.separator="|" --property parse.headers=true --property headers.delimiter="|" --property headers.separator="," --property headers.key.separator=":"
                    else
                        if [[ -n "$verbose" ]]
                        then
                            set -x
                        fi
                        head -n $nb_messages_to_send $output_file | docker run -i --rm -v /tmp/delta_configs/ak-tools-ccloud.delta:/tmp/configuration/ccloud.properties -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" ${CP_CONNECT_IMAGE}:${CONNECT_TAG} kafka-console-producer --broker-list $BOOTSTRAP_SERVERS --topic $topic --producer.config /tmp/configuration/ccloud.properties $security $producer_properties --property parse.key=true --property key.separator="|" 
                    fi
                else
                    if [[ -n "$headers" ]]
                    then
                        if [[ -n "$verbose" ]]
                        then
                            set -x
                        fi
                        head -n $nb_messages_to_send $output_file | docker run -i --rm -v /tmp/delta_configs/ak-tools-ccloud.delta:/tmp/configuration/ccloud.properties -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" ${CP_CONNECT_IMAGE}:${CONNECT_TAG} kafka-console-producer --broker-list $BOOTSTRAP_SERVERS --topic $topic --producer.config /tmp/configuration/ccloud.properties $security $producer_properties --property parse.headers=true --property headers.delimiter="|" --property headers.separator="," --property headers.key.separator=":"
                    else
                        if [[ -n "$verbose" ]]
                        then
                            set -x
                        fi
                        head -n $nb_messages_to_send $output_file | docker run -i --rm -v /tmp/delta_configs/ak-tools-ccloud.delta:/tmp/configuration/ccloud.properties -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" ${CP_CONNECT_IMAGE}:${CONNECT_TAG} kafka-console-producer --broker-list $BOOTSTRAP_SERVERS --topic $topic --producer.config /tmp/configuration/ccloud.properties $security $producer_properties
                    fi
                fi
            else
                if [[ -n "$key" ]]
                then
                    if [[ -n "$headers" ]]
                    then
                        if [[ -n "$verbose" ]]
                        then
                            set -x
                        fi
                        head -n $nb_messages_to_send $output_file | docker exec -i $container kafka-console-producer --broker-list $bootstrap_server --topic $topic $security $producer_properties --property parse.key=true --property key.separator="|" --property parse.headers=true --property headers.delimiter="|" --property headers.separator="," --property headers.key.separator=":"
                    else
                        if [[ -n "$verbose" ]]
                        then
                            set -x
                        fi
                        head -n $nb_messages_to_send $output_file | docker exec -i $container kafka-console-producer --broker-list $bootstrap_server --topic $topic $security $producer_properties --property parse.key=true --property key.separator="|"
                    fi
                else
                    if [[ -n "$headers" ]]
                    then
                        if [[ -n "$verbose" ]]
                        then
                            set -x
                        fi
                        head -n $nb_messages_to_send $output_file | docker exec -i $container kafka-console-producer --broker-list $bootstrap_server --topic $topic $security $producer_properties --property parse.headers=true --property headers.delimiter="|" --property headers.separator="," --property headers.key.separator=":"
                    else
                        if [[ -n "$verbose" ]]
                        then
                            set -x
                        fi
                        head -n $nb_messages_to_send $output_file | docker exec -i $container kafka-console-producer --broker-list $bootstrap_server --topic $topic $security $producer_properties
                    fi
                fi
            fi
        ;;
        *)
            value_subject_name_strategy_property=""
            if [[ -n "$value_subject_name_strategy" ]]
            then
                value_subject_name_strategy_property="--property value.subject.name.strategy=io.confluent.kafka.serializers.subject.$value_subject_name_strategy"
            fi
            if [[ "$environment" == "environment" ]]
            then
                if [[ -n "$key" ]]
                then
                    if [[ -n "$headers" ]]
                    then
                        if [[ -n "$verbose" ]]
                        then
                            set -x
                        fi
                        head -n $nb_messages_to_send $output_file | docker run -i --rm -e SCHEMA_REGISTRY_LOG4J_OPTS="-Dlog4j.configuration=file:/etc/kafka/tools-log4j.properties" -e schema_type=$schema_type -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" ${CP_CONNECT_IMAGE}:${CONNECT_TAG} kafka-$schema_type-console-producer --broker-list $BOOTSTRAP_SERVERS --producer-property ssl.endpoint.identification.algorithm=https --producer-property sasl.mechanism=PLAIN --producer-property security.protocol=SASL_SSL --producer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --topic $topic $security --property value.schema="$(cat $schema_file)" --property parse.key=true --property key.separator="|" --property key.serializer=org.apache.kafka.common.serialization.StringSerializer --property parse.headers=true --property headers.delimiter="|" --property headers.separator="," --property headers.key.separator=":" $value_subject_name_strategy_property $producer_properties
                    else
                        if [[ -n "$verbose" ]]
                        then
                            set -x
                        fi
                        head -n $nb_messages_to_send $output_file | docker run -i --rm -e SCHEMA_REGISTRY_LOG4J_OPTS="-Dlog4j.configuration=file:/etc/kafka/tools-log4j.properties" -e schema_type=$schema_type -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" ${CP_CONNECT_IMAGE}:${CONNECT_TAG} kafka-$schema_type-console-producer --broker-list $BOOTSTRAP_SERVERS --producer-property ssl.endpoint.identification.algorithm=https --producer-property sasl.mechanism=PLAIN --producer-property security.protocol=SASL_SSL --producer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --topic $topic $security --property value.schema="$(cat $schema_file)" --property parse.key=true --property key.separator="|" --property key.serializer=org.apache.kafka.common.serialization.StringSerializer $value_subject_name_strategy_property $producer_properties
                    fi
                else
                    if [[ -n "$headers" ]]
                    then
                        if [[ -n "$verbose" ]]
                        then
                            set -x
                        fi
                        head -n $nb_messages_to_send $output_file | docker run -i --rm -e SCHEMA_REGISTRY_LOG4J_OPTS="-Dlog4j.configuration=file:/etc/kafka/tools-log4j.properties" -e schema_type=$schema_type -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" ${CP_CONNECT_IMAGE}:${CONNECT_TAG} kafka-$schema_type-console-producer --broker-list $BOOTSTRAP_SERVERS --producer-property ssl.endpoint.identification.algorithm=https --producer-property sasl.mechanism=PLAIN --producer-property security.protocol=SASL_SSL --producer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --topic $topic $security --property value.schema="$(cat $schema_file)" --property parse.headers=true --property headers.delimiter="|" --property headers.separator="," --property headers.key.separator=":" $value_subject_name_strategy_property $producer_properties
                    else
                        if [[ -n "$verbose" ]]
                        then
                            set -x
                        fi
                        head -n $nb_messages_to_send $output_file | docker run -i --rm -e SCHEMA_REGISTRY_LOG4J_OPTS="-Dlog4j.configuration=file:/etc/kafka/tools-log4j.properties" -e schema_type=$schema_type -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" ${CP_CONNECT_IMAGE}:${CONNECT_TAG} kafka-$schema_type-console-producer --broker-list $BOOTSTRAP_SERVERS --producer-property ssl.endpoint.identification.algorithm=https --producer-property sasl.mechanism=PLAIN --producer-property security.protocol=SASL_SSL --producer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --topic $topic $security --property value.schema="$(cat $schema_file)" $value_subject_name_strategy_property $producer_properties
                    fi
                fi
            else
                if [[ -n "$key" ]]
                then
                    if [[ -n "$headers" ]]
                    then
                        if [[ -n "$verbose" ]]
                        then
                            set -x
                        fi
                        head -n $nb_messages_to_send $output_file | docker exec -e SCHEMA_REGISTRY_LOG4J_OPTS="-Dlog4j.configuration=file:/etc/kafka/tools-log4j.properties" -i $container kafka-$schema_type-console-producer --broker-list $bootstrap_server --property schema.registry.url=$sr_url_cli --topic $topic $security --property value.schema="$(cat $schema_file)" --property parse.key=true --property key.separator="|" --property key.serializer=org.apache.kafka.common.serialization.StringSerializer --property parse.headers=true --property headers.delimiter="|" --property headers.separator="," --property headers.key.separator=":" $value_subject_name_strategy_property $producer_properties
                    else
                        if [[ -n "$verbose" ]]
                        then
                            set -x
                        fi
                        head -n $nb_messages_to_send $output_file | docker exec -e SCHEMA_REGISTRY_LOG4J_OPTS="-Dlog4j.configuration=file:/etc/kafka/tools-log4j.properties" -i $container kafka-$schema_type-console-producer --broker-list $bootstrap_server --property schema.registry.url=$sr_url_cli --topic $topic $security --property value.schema="$(cat $schema_file)" --property parse.key=true --property key.separator="|" --property key.serializer=org.apache.kafka.common.serialization.StringSerializer $value_subject_name_strategy_property $producer_properties
                    fi
                else
                    if [[ -n "$headers" ]]
                    then
                        if [[ -n "$verbose" ]]
                        then
                            set -x
                        fi
                        head -n $nb_messages_to_send $output_file | docker exec -e SCHEMA_REGISTRY_LOG4J_OPTS="-Dlog4j.configuration=file:/etc/kafka/tools-log4j.properties" -i $container kafka-$schema_type-console-producer --broker-list $bootstrap_server --property schema.registry.url=$sr_url_cli --topic $topic $security --property value.schema="$(cat $schema_file)" --property parse.headers=true --property headers.delimiter="|" --property headers.separator="," --property headers.key.separator=":" $value_subject_name_strategy_property $producer_properties
                    else
                        if [[ -n "$verbose" ]]
                        then
                            set -x
                        fi
                        head -n $nb_messages_to_send $output_file | docker exec -e SCHEMA_REGISTRY_LOG4J_OPTS="-Dlog4j.configuration=file:/etc/kafka/tools-log4j.properties" -i $container kafka-$schema_type-console-producer --broker-list $bootstrap_server --property schema.registry.url=$sr_url_cli --topic $topic $security --property value.schema="$(cat $schema_file)" $value_subject_name_strategy_property $producer_properties
                    fi
                fi
            fi
        ;;
    esac
    if [[ -n "$verbose" ]]
    then
        set +x
    fi
    # Increment the number of sent messages
    nb_messages_sent=$((nb_messages_sent + nb_messages_to_send))
    if [ $should_stop -eq 1 ]
    then
        stop=1
    fi
done
ELAPSED="took: $((($SECONDS / 60) % 60))min $(($SECONDS % 60))sec"
log "📤 produced $nb_messages records to topic $topic, $ELAPSED"
set +x
playground topic get-number-records --topic $topic