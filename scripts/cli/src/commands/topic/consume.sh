topic="${args[--topic]}"
verbose="${args[--verbose]}"
max_messages="${args[--max-messages]}"
grep_string="${args[--grep]}"
min_expected_messages="${args[--min-expected-messages]}"
timeout="${args[--timeout]}"
tail="${args[--tail]}"
timestamp_field="${args[--plot-latencies-timestamp-field]}"
key_subject="${args[--key-subject]}"
value_subject="${args[--value-subject]}"
max_characters="${args[--max-characters]}"
open="${args[--open]}"

# Optimized helpers (reduce repeated external calls and parsing) with caching
declare -A SUBJECT_CACHE
get_subject_info() {
  local subject="$1"
  if [ -n "${SUBJECT_CACHE[$subject]}" ]; then
    echo "${SUBJECT_CACHE[$subject]}"; return 0
  fi
  local json version schema_type out
  json=$(curl $sr_security -s "${sr_url}/subjects/${subject}/versions/latest" 2>/dev/null) || { SUBJECT_CACHE[$subject]=""; echo ""; return 0; }
  version=$(jq -r .version <<< "$json" 2>/dev/null)
  [ "$version" = "null" ] && { SUBJECT_CACHE[$subject]=""; echo ""; return 0; }
  schema_type=$(jq -r '.schemaType // ""' <<< "$json" 2>/dev/null)
  case "$schema_type" in
    JSON) out="json-schema" ;;
    PROTOBUF) out="protobuf" ;;
    AVRO|""|null) out="avro" ;;
    *) out="" ;;
  esac
  SUBJECT_CACHE[$subject]="$out"
  echo "$out"
}

if [[ -n "$key_subject" ]]
then
  original_key_subject=$key_subject
fi

if [[ -n "$value_subject" ]]
then
  original_value_subject=$value_subject
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
    security="--consumer.config /etc/kafka/consumer.properties"

    docker exec -i client kinit -k -t /var/lib/secret/kafka-connect.key connect
elif [[ "$environment" == *"ssl"* ]]
then
    sr_url_cli="https://schema-registry:8081"
    security="--property schema.registry.ssl.truststore.location=/etc/kafka/secrets/kafka.client.truststore.jks --property schema.registry.ssl.truststore.password=confluent --property schema.registry.ssl.keystore.location=/etc/kafka/secrets/kafka.client.keystore.jks --property schema.registry.ssl.keystore.password=confluent --consumer.config /etc/kafka/secrets/client_without_interceptors.config"
elif [[ "$environment" == "rbac-sasl-plain" ]]
then
    security="--property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info=clientAvroCli:clientAvroCli --consumer.config /etc/kafka/secrets/client_without_interceptors.config"
elif [[ "$environment" == "ldap-authorizer-sasl-plain" ]]
then
    security="--group test-consumer-group --consumer.config /service/kafka/users/client.properties"
elif [[ "$environment" == "sasl-plain" ]] || [[ "$environment" == "sasl-scram" ]] || [[ "$environment" == "ldap-sasl-plain" ]]
then
    security="--consumer.config /tmp/client.properties" 
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

if [[ -n "$timeout" ]] && [ "$timeout" != "60" ]
then
  if [[ ! -n "$min_expected_messages" ]] || [ "$min_expected_messages" == "0" ]
  then
    logerror "❌ --timeout was provided without specifying --min-expected-messages"
    exit 1
  fi
fi

if [[ ! -n "$topic" ]]
then
    if [[ -n "$min_expected_messages" ]] && [ "$min_expected_messages" != "0" ]
    then
      logerror "--min-expected-messages was provided without specifying --topic"
      exit 1
    fi
    if [[ -n "$key_subject" ]]
    then
      logerror "--key-subject was provided without specifying --topic"
      exit 1
    fi
    if [[ -n "$value_subject" ]]
    then
      logerror "--value-subject was provided without specifying --topic"
      exit 1
    fi
    if [[ -n "$tail" ]]
    then
      logerror "--tail was provided without specifying --topic"
      exit 1
    fi
    if [[ -n "$timestamp_field" ]]
    then
      logerror "--plot-latencies-timestamp-field was provided without specifying --topic"
      exit 1
    fi
    log "✨ --topic flag was not provided, applying command to all topics"
    topic=$(playground get-topic-list --skip-connect-internal-topics)
    if [ "$topic" == "" ]
    then
        logerror "❌ no topic found !"
        exit 1
    fi
fi

get_connect_image
if version_gt $CP_CONNECT_TAG "7.9.99"
then
    tool_log4j_jvm_arg="-Dlog4j2.configurationFile=file:/etc/kafka/tools-log4j2.yaml"
else
    tool_log4j_jvm_arg="-Dlog4j.configuration=file:/etc/kafka/tools-log4j.properties"
fi

items=($topic)
for topic in ${items[@]}
do
  key_subject=""
  value_subject=""
  if [ ! -n "$tail" ]
  then
    if [[ -n "$min_expected_messages" ]] && [ "$min_expected_messages" != "0" ]
    then 
      start_time=$(date +%s)

      while true; do
        nb_messages=$(playground topic get-number-records -t $topic | tail -1)
        
        if [[ ! $nb_messages =~ ^[0-9]+$ ]]
        then
          echo $nb_messages | grep "does not exist" > /dev/null 2>&1
          if [ $? == 0 ]
          then
            logwarn "❌ topic $topic does not exist !"
          else
            logwarn "❌ problem while getting number of messages: $nb_messages"
          fi
          exit 1
        fi

        if [ $nb_messages -ge $min_expected_messages ]
        then
          break
        fi
        
        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))
        
        if [ $elapsed_time -ge $timeout ]
        then
          logerror "❌ overall timeout of $timeout seconds exceeded. --min-expected-messages is set with $min_expected_messages but topic $topic contains $nb_messages messages"
          exit 1
        fi
        
        sleep 1
      done
    else
      nb_messages=$(playground topic get-number-records -t $topic | tail -1)

      if [[ ! $nb_messages =~ ^[0-9]+$ ]]
      then
        echo $nb_messages | grep "does not exist" > /dev/null 2>&1
        if [ $? == 0 ]
        then
          logwarn "❌ topic $topic does not exist !"
        else
          logwarn "❌ problem while getting number of messages: $nb_messages"
        fi
        break
      fi
    fi
  fi

  if [[ -n "$open" ]]
  then
    filename="/tmp/dump-${topic}-$(date '+%Y-%m-%d-%H-%M-%S').log"

    log "📄 dumping topic content to $filename"
    playground topic consume --topic $topic --max-messages -1 > $filename
    if [ $? -eq 0 ]
    then
      playground open --file "${filename}"
    else
      logerror "❌ failed to dump topic $topic"
    fi
    exit 0
  fi

  if [ -n "$tail" ]
  then
    log "✨ Tailing content of topic $topic"
  elif [[ -n "$max_messages" ]] && [ $max_messages -eq -1 ] && [[ ! -n "$timestamp_field" ]]
  then
    log "✨ --max-messages is set to -1, display full content of topic $topic, it contains $nb_messages messages"
    max_messages=$nb_messages
  elif [[ -n "$max_messages" ]] && [ $nb_messages -ge $max_messages ] && [[ ! -n "$timestamp_field" ]]
  then
    log "✨ Display content of topic $topic, it contains $nb_messages messages, but displaying only --max-messages=$max_messages"
    nb_messages=$max_messages
  else
    log "✨ Display content of topic $topic, it contains $nb_messages messages"
  fi

  if [[ -n "$grep_string" ]]
  then
    logwarn "--grep is set so only matched results will be displayed !"
  fi

  if [[ -n "$timestamp_field" ]]
  then
    log "📈 plotting results.."
  fi
  if [[ -n "$original_key_subject" ]]; then
    log "📛 key subject is set with $original_key_subject"
    key_subject=$original_key_subject
  else
    key_subject="${topic}-key"
  fi
  key_type=$(get_subject_info "$key_subject")

  if [ "$key_type" != "" ]
  then
    log "🔮🔰 topic is using $key_type for key"
    playground schema get --subject ${key_subject}
  else
    log "🔮🙅 topic is not using any schema for key"
  fi

  if [[ -n "$original_value_subject" ]]
  then
    log "📛 value subject is set with $original_value_subject"
    value_subject=$original_value_subject
  else
    value_subject="${topic}-value"
  fi

  value_type=$(get_subject_info "$value_subject")

  if [ "$value_type" != "" ]
  then
    log "🔮🔰 topic is using $value_type for value"
    playground schema get --subject ${value_subject}
  else
    log "🔮🙅 topic is not using any schema for value"
  fi

  type=""
  tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
  if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi
  fifo_path="$tmp_dir/kafka_output_fifo"
  mkfifo "$fifo_path"

  nottailing1=""
  nottailing2=""
  if [ ! -n "$tail" ]
  then
    nottailing1="--from-beginning --max-messages $nb_messages"
    if [[ ! -n "$timestamp_field" ]]
    then
      nottailing2="timeout $timeout"
    fi
  fi

  if [ "$max_messages" != "10" ]
  then
    nottailing2=""
  fi
  case "${value_type}" in
    avro|protobuf|json-schema)
        if [ "$key_type" == "avro" ] || [ "$key_type" == "protobuf" ] || [ "$key_type" == "json-schema" ]
        then
            if [[ "$environment" == "ccloud" ]]
            then
              if [[ -n "$verbose" ]]
              then
                log "🐞 CLI command used to consume data"
                echo "kafka-$value_type-console-consumer --bootstrap-server $BOOTSTRAP_SERVERS --topic $topic --consumer-property ssl.endpoint.identification.algorithm=https --consumer-property sasl.mechanism=PLAIN --consumer-property security.protocol=SASL_SSL --consumer-property sasl.jaas.config=\"$SASL_JAAS_CONFIG\" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info=\"$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO\" --property schema.registry.url=$SCHEMA_REGISTRY_URL --property print.schema.ids=true --property schema.id.separator=\"|\" --property print.partition=true --property print.offset=true --property print.headers=true --property headers.separator=, --property headers.deserializer=org.apache.kafka.common.serialization.StringDeserializer --property print.timestamp=true --property print.key=true --property key.separator=\"|\" --skip-message-on-error $security $nottailing1"
              fi
              get_connect_image
              docker run -i --rm -e SCHEMA_REGISTRY_LOG4J_OPTS="$tool_log4j_jvm_arg" -e value_type=$value_type -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} $nottailing2 kafka-$value_type-console-consumer --bootstrap-server $BOOTSTRAP_SERVERS --topic $topic --consumer-property ssl.endpoint.identification.algorithm=https --consumer-property sasl.mechanism=PLAIN --consumer-property security.protocol=SASL_SSL --consumer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --property print.schema.ids=true --property schema.id.separator="|" --property print.partition=true --property print.offset=true --property print.headers=true --property headers.separator=, --property headers.deserializer=org.apache.kafka.common.serialization.StringDeserializer --property print.timestamp=true --property print.key=true --property key.separator="|" --skip-message-on-error $security $nottailing1 > "$fifo_path" 2>&1 &
            else
              if [[ -n "$verbose" ]]
              then
                log "🐞 CLI command used to consume data"
                echo "kafka-$value_type-console-consumer -bootstrap-server $bootstrap_server --property schema.registry.url=$sr_url_cli --topic $topic  --property print.schema.ids=true --property schema.id.separator=\"|\" --property print.partition=true --property print.offset=true --property print.headers=true --property headers.separator=, --property headers.deserializer=org.apache.kafka.common.serialization.StringDeserializer --property print.timestamp=true --property print.key=true --property key.separator=\"|\" --skip-message-on-error $security $nottailing1"
              fi
              docker exec -e SCHEMA_REGISTRY_LOG4J_OPTS="$tool_log4j_jvm_arg" $container $nottailing2 kafka-$value_type-console-consumer -bootstrap-server $bootstrap_server --property schema.registry.url=$sr_url_cli --topic $topic  --property print.schema.ids=true --property schema.id.separator="|" --property print.partition=true --property print.offset=true --property print.headers=true --property headers.separator=, --property headers.deserializer=org.apache.kafka.common.serialization.StringDeserializer --property print.timestamp=true --property print.key=true --property key.separator="|" --skip-message-on-error $security $nottailing1 > "$fifo_path" 2>&1 &
            fi
        else
            if [[ "$environment" == "ccloud" ]]
            then
              if [[ -n "$verbose" ]]
              then
                log "🐞 CLI command used to consume data"
                echo "kafka-$value_type-console-consumer --bootstrap-server $BOOTSTRAP_SERVERS --topic $topic --consumer-property ssl.endpoint.identification.algorithm=https --consumer-property sasl.mechanism=PLAIN --consumer-property security.protocol=SASL_SSL --consumer-property sasl.jaas.config=\"$SASL_JAAS_CONFIG\" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info=\"$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO\" --property schema.registry.url=$SCHEMA_REGISTRY_URL --property print.schema.ids=true --property schema.id.separator=\"|\" --property print.partition=true --property print.offset=true --property print.headers=true --property headers.separator=, --property headers.deserializer=org.apache.kafka.common.serialization.StringDeserializer --property print.timestamp=true --property print.key=true --property key.separator=\"|\" --property key.deserializer=org.apache.kafka.common.serialization.StringDeserializer --skip-message-on-error $security $nottailing1"
              fi
              get_connect_image
              docker run -i --rm -e SCHEMA_REGISTRY_LOG4J_OPTS="$tool_log4j_jvm_arg" -e value_type=$value_type -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} $nottailing2 kafka-$value_type-console-consumer --bootstrap-server $BOOTSTRAP_SERVERS --topic $topic --consumer-property ssl.endpoint.identification.algorithm=https --consumer-property sasl.mechanism=PLAIN --consumer-property security.protocol=SASL_SSL --consumer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --property print.schema.ids=true --property schema.id.separator="|" --property print.partition=true --property print.offset=true --property print.headers=true --property headers.separator=, --property headers.deserializer=org.apache.kafka.common.serialization.StringDeserializer --property print.timestamp=true --property print.key=true --property key.separator="|" --property key.deserializer=org.apache.kafka.common.serialization.StringDeserializer --skip-message-on-error $security $nottailing1 > "$fifo_path" 2>&1 &
            else
              if [[ -n "$verbose" ]]
              then
                log "🐞 CLI command used to consume data"
                echo "kafka-$value_type-console-consumer --bootstrap-server $bootstrap_server --property schema.registry.url=$sr_url_cli --topic $topic --property print.partition=true  --property print.schema.ids=true --property schema.id.separator=\"|\" --property print.offset=true --property print.headers=true --property headers.separator=, --property headers.deserializer=org.apache.kafka.common.serialization.StringDeserializer --property print.timestamp=true --property print.key=true --property key.separator=\"|\" --property key.deserializer=org.apache.kafka.common.serialization.StringDeserializer --skip-message-on-error $security $nottailing1"
              fi
              docker exec -e SCHEMA_REGISTRY_LOG4J_OPTS="$tool_log4j_jvm_arg" $container $nottailing2  kafka-$value_type-console-consumer --bootstrap-server $bootstrap_server --property schema.registry.url=$sr_url_cli --topic $topic --property print.partition=true  --property print.schema.ids=true --property schema.id.separator="|" --property print.offset=true --property print.headers=true --property headers.separator=, --property headers.deserializer=org.apache.kafka.common.serialization.StringDeserializer --property print.timestamp=true --property print.key=true --property key.separator="|" --property key.deserializer=org.apache.kafka.common.serialization.StringDeserializer --skip-message-on-error $security $nottailing1 > "$fifo_path" 2>&1 &
            fi
        fi
        ;;
    *)
      if [[ "$environment" == "ccloud" ]]
      then
        if [[ -n "$verbose" ]]
        then
          log "🐞 CLI command used to consume data"
          echo "kafka-console-consumer --bootstrap-server $BOOTSTRAP_SERVERS --topic $topic --consumer.config /tmp/configuration/ccloud.properties --property print.partition=true --property print.offset=true --property print.headers=true --property headers.separator=, --property headers.deserializer=org.apache.kafka.common.serialization.StringDeserializer --property print.timestamp=true --property print.key=true --property key.separator=\"|\" $security $nottailing1"
        fi
        get_connect_image
        docker run -i --rm -v $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta:/tmp/configuration/ccloud.properties -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} $nottailing2 kafka-console-consumer --bootstrap-server $BOOTSTRAP_SERVERS --topic $topic --consumer.config /tmp/configuration/ccloud.properties --property print.partition=true --property print.offset=true --property print.headers=true --property headers.separator=, --property headers.deserializer=org.apache.kafka.common.serialization.StringDeserializer --property print.timestamp=true --property print.key=true --property key.separator="|" $security $nottailing1 > "$fifo_path" 2>&1 &
      else
        if [[ -n "$verbose" ]]
        then
          log "🐞 CLI command used to consume data"
          echo "kafka-console-consumer --bootstrap-server $bootstrap_server --topic $topic --property print.partition=true --property print.offset=true --property print.headers=true --property headers.separator=, --property headers.deserializer=org.apache.kafka.common.serialization.StringDeserializer --property print.timestamp=true --property print.key=true --property key.separator=\"|\" $security $nottailing1"
        fi
        docker exec $container $nottailing2 kafka-console-consumer --bootstrap-server $bootstrap_server --topic $topic --property print.partition=true --property print.offset=true --property print.headers=true --property headers.separator=, --property headers.deserializer=org.apache.kafka.common.serialization.StringDeserializer --property print.timestamp=true --property print.key=true --property key.separator="|" $security $nottailing1 > "$fifo_path" 2>&1  &
      fi
    ;;
  esac
  # Detect the platform (macOS or Linux) and set the date command accordingly
  if [[ "$(uname)" == "Darwin" ]]; then
    # macOS
    date_command="date -r "
  else
    # Linux
    date_command="date -d @"
  fi

  if [[ -n "$timestamp_field" ]]
  then
    rm -rf /tmp/latency
    mkdir -p /tmp/latency
    latency_csv="/tmp/latency/latency.csv"
    latency_png="/tmp/latency/latency.png"
  fi
  found=0
  first_record=1
  is_base64=0
  export LC_ALL=C
  # Loop through each line in the named pipe
  while read -r line
  do
    display_line=1
    if [[ $line =~ "CreateTime:" ]]
    then
      # Extract the timestamp from the line
      # Extract millisecond timestamp without external cut pipelines
      timestamp_ms_part=${line#CreateTime:}
      timestamp_ms=${timestamp_ms_part%%|*}
      # Convert milliseconds to seconds
      timestamp_sec=$((timestamp_ms / 1000))
      milliseconds=$((timestamp_ms % 1000))
      readable_date="$(${date_command}${timestamp_sec} "+%Y-%m-%d %H:%M:%S.${milliseconds}")"
      original_prefix="CreateTime:${timestamp_ms}"
      line_with_date="${line/$original_prefix/$(printf 'CreateTime:%s' "$readable_date")}" || line_with_date="$line"

      if [ $first_record -eq 1 ]
      then
        payload=$(echo "$line" | cut -d "|" -f 6)

        if [ ${#payload} -lt 1000 ]
        then
          # check if it is base64 encoded
          set +e
          base64=$(echo "$payload" | tr -d '"' | base64 -d 2>/dev/null)
          if [ $? -eq 0 ]
          then
            if [ "$base64" != "" ]
            then
              decoded=$(echo "$base64" | iconv -t UTF-8//IGNORE 2>/dev/null)
              if [ "$decoded" == "$base64" ]
              then
                logwarn "🤖 Data is base64 encoded, payload will be decoded"
                is_base64=1
              fi
            fi
          fi
          set -e
        fi

        first_record=0
      fi

      if [ $is_base64 -eq 1 ]
      then
        base64=$(echo "$payload" | tr -d '"' | base64 -d 2>/dev/null)
        if [ -n "$base64" ]; then
          line_with_date=$(awk -v new_value="$base64" -v l="$line_with_date" 'BEGIN{FS=OFS="|"} {
            split(l,a,"|"); a[6]=new_value;
            for(i=1;i<=length(a);i++){printf i==length(a)?a[i]"\n":a[i]"|"}
          }')
        fi
      fi

      if [[ -n "$grep_string" ]]
      then
        if [[ $line =~ "$grep_string" ]]
        then
          log "✅ found $grep_string in topic $topic"
          found=1
        else
          display_line=0
        fi
      fi

      if [[ ! -n "$timestamp_field" ]]
      then
        if [ $display_line -eq 1 ]
        then
          payload_field=${line_with_date#*|*|*|*|*|}
          payload=${payload_field%%|*}
          if [ ${#payload} -lt $max_characters ]
          then
            if [ "$key_type" == "avro" ] || [ "$key_type" == "protobuf" ] || [ "$key_type" == "json-schema" ]
            then
              echo "$line_with_date" | awk 'BEGIN{FS=OFS="|"} {$4="Headers:"$4; $5="Key:"$5; $6="KeySchemaId:"$6; $7="Value:"$7; $8="ValueSchemaId:"$8} 1'
            else
              echo "$line_with_date" | awk 'BEGIN{FS=OFS="|"} {$4="Headers:"$4; $5="Key:"$5; $6="Value:"$6; $7="ValueSchemaId:"$7} 1'
            fi
          else
            if [ "$key_type" == "avro" ] || [ "$key_type" == "protobuf" ] || [ "$key_type" == "json-schema" ]
            then
              echo "$line_with_date" | awk 'BEGIN{FS=OFS="|"} {$4="Headers:"$4; $5="Key:"$5; $6="KeySchemaId:"$6; $7="Value:"$7; $8="ValueSchemaId:"$8} 1' | cut -c 1-$max_characters | awk "{print \$0 \"...<truncated, only showing first $max_characters characters, out of ${#payload}>...\"}"
            else
              echo "$line_with_date" | awk 'BEGIN{FS=OFS="|"} {$4="Headers:"$4; $5="Key:"$5; $6="Value:"$6; $7="ValueSchemaId:"$7} 1' | cut -c 1-$max_characters | awk "{print \$0 \"...<truncated, only showing first $max_characters characters, out of ${#payload}>...\"}"
            fi
          fi
        fi
      fi

      if [[ -n "$timestamp_field" ]]
      then
        payload_field=${line#*|*|*|*|*|}
        payload=${payload_field%%|*}
        # JSON is invalid
        if ! echo "$payload" | jq -e .  > /dev/null 2>&1
        then
            logerror "--plot-latencies-timestamp-field is set but value content is not in json representation"
            exit 1
        else
          timestamp_source=$(echo "$payload" | jq -r .${timestamp_field})
          echo "$readable_date,$timestamp_ms,$timestamp_source" >> $latency_csv
        fi
      fi
    elif [[ $line =~ "Unable to find FetchSessionHandler" ]]
    then
      continue
    elif [[ $line =~ "Processed a total of" ]]
    then
      continue
    elif [[ $line =~ "SLF4J" ]]
    then
      continue
    else
      if [[ -n "$grep_string" ]]
      then
        if [[ $line =~ "$grep_string" ]]
        then
          log "✅ found $grep_string in topic $topic"
          found=1
        else
          display_line=0
        fi
      fi

      if [ $display_line -eq 1 ]
      then
        payload_field=${line#*|*|*|*|*|}
        payload=${payload_field%%|*}
        if [ ${#payload} -lt $max_characters ]
        then
          echo "$line"
        else
          echo "$line" | cut -c 1-$max_characters | awk "{print \$0 \"...<truncated, only showing first $max_characters characters, out of ${#payload}>...\"}"
        fi
      fi
    fi
  done < "$fifo_path"

  if [[ -n "$grep_string" ]]
  then
    if [ $found != 1 ]
    then
      logerror "❌ could not find $grep_string in topic $topic"
      exit 1
    fi
  fi
done

if [[ -n "$timestamp_field" ]]
then
  log "Plot data using gnuplot, see ${latency_png}"
  docker run --quiet --rm -i -v /tmp/latency:/work remuslazar/gnuplot -e \
  "
  set grid;
  set datafile separator ',';
  set timefmt \"%Y-%m-%d %H:%M:%S.%s\";
  set format x '%H:%M:%S';
  set term png size 1200,600;
  set output 'latency.png';
  set xdata time;
  set autoscale;
  set xlabel 'Time';
  set ylabel 'Latency in ms';
  plot 'latency.csv' using 1:(\$2-\$3) with points;"

  # open $latency_csv
  if [[ $(type -f open 2>&1) =~ "not found" ]]
  then
    :
  else
    open $latency_png
  fi
fi