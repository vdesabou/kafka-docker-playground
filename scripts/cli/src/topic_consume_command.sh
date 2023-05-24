topic="${args[--topic]}"
max_messages="${args[--max-messages]}"
grep_string="${args[--grep]}"
min_expected_messages="${args[--min-expected-messages]}"
timeout="${args[--timeout]}"

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
    security="--property schema.registry.ssl.truststore.location=/etc/kafka/secrets/kafka.client.truststore.jks --property schema.registry.ssl.truststore.password=confluent --property schema.registry.ssl.keystore.location=/etc/kafka/secrets/kafka.client.keystore.jks --property schema.registry.ssl.keystore.password=confluent --consumer.config /etc/kafka/secrets/client_without_interceptors.config"
elif [[ "$environment" == "rbac-sasl-plain" ]]
then
    sr_url_cli="http://schema-registry:8081"
    security="--property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info=clientAvroCli:clientAvroCli --consumer.config /etc/kafka/secrets/client_without_interceptors.config"
elif [[ "$environment" == "kerberos" ]]
then
    container="client"
    sr_url_cli="http://schema-registry:8081"
    security="--consumer.config /etc/kafka/consumer.properties"

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
  DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
  dir1=$(echo ${DIR_CLI%/*})
  root_folder=$(echo ${dir1%/*})
  IGNORE_CHECK_FOR_DOCKER_COMPOSE=true
  source $root_folder/scripts/utils.sh
fi

if [[ ! -n "$topic" ]]
then
    if [[ -n "$min_expected_messages" ]]
    then
      logerror "--min-expected-messages was provided without specifying --topic"
      exit 1
    fi
    log "✨ --topic flag was not provided, applying command to all topics"
    topic=$(playground get-topic-list --skip-connect-internal-topics)
    if [ "$topic" == "" ]
    then
        logerror "❌ No topic found !"
        exit 1
    fi
fi

items=($topic)
for topic in ${items[@]}
do
  if [[ -n "$min_expected_messages" ]]
  then
    nb_messages=$(playground topic get-number-records -t $topic | tail -1)
    if [ $nb_messages -lt $min_expected_messages ]
    then
      logerror "❌ --min-expected-messages is set with $min_expected_messages but topic $topic contains $nb_messages messages"
      exit 1
    fi
  else
    nb_messages=$(playground topic get-number-records -t $topic | tail -1)
  fi

  if [[ -n "$max_messages" ]]
  then
    log "✨ Display content of topic $topic, it contains $nb_messages messages, but displaying only --max-messages=$max_messages"
    nb_messages=$max_messages
  else
    log "✨ Display content of topic $topic, it contains $nb_messages messages"
  fi

  key_type=""
  version=$(curl $sr_security -s "${sr_url}/subjects/${topic}-key/versions/1" | jq -r .version)
  if [ "$version" != "null" ]
  then
    schema_type=$(curl $sr_security -s "${sr_url}/subjects/${topic}-key/versions/1"  | jq -r .schemaType)
    case "${schema_type}" in
      JSON)
        key_type="json-schema"
      ;;
      PROTOBUF)
        key_type="protobuf"
      ;;
      null)
        key_type="avro"
      ;;
    esac
  fi

  if [ "$key_type" != "" ]
  then
    log "🔮🔰 topic is using $key_type for key"
  else
    log "🔮🙅 topic is not using any schema for key"
  fi

  value_type=""
  version=$(curl $sr_security -s "${sr_url}/subjects/${topic}-value/versions/1" | jq -r .version)
  if [ "$version" != "null" ]
  then
    schema_type=$(curl $sr_security -s "${sr_url}/subjects/${topic}-value/versions/1"  | jq -r .schemaType)
    case "${schema_type}" in
      JSON)
        value_type="json-schema"
      ;;
      PROTOBUF)
        value_type="protobuf"
      ;;
      null)
        value_type="avro"
      ;;
    esac
  fi

  if [ "$value_type" != "" ]
  then
    log "🔮🔰 topic is using $value_type for value"
  else
    log "🔮🙅 topic is not using any schema for value"
  fi

  type=""
  tmp_dir=$(mktemp -d -t ci-XXXXXXXXXX)
  fifo_path="$tmp_dir/kafka_output_fifo"
  mkfifo "$fifo_path"
  case "${value_type}" in
    avro|protobuf|json-schema)
        if [ "$key_type" == "avro" ] || [ "$key_type" == "protobuf" ] || [ "$key_type" == "json-schema" ]
        then
            if [[ "$environment" == "environment" ]]
            then
              timeout $timeout docker run --rm -e SCHEMA_REGISTRY_LOG4J_OPTS="-Dlog4j.configuration=file:/etc/kafka/tools-log4j.properties" -e value_type=$value_type -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" ${CP_CONNECT_IMAGE}:${CONNECT_TAG} kafka-$value_type-console-consumer --bootstrap-server $BOOTSTRAP_SERVERS --topic $topic --consumer-property ssl.endpoint.identification.algorithm=https --consumer-property sasl.mechanism=PLAIN --consumer-property security.protocol=SASL_SSL --consumer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --property print.partition=true --property print.offset=true --property print.headers=true --property print.timestamp=true --property print.key=true --property key.separator="|" --skip-message-on-error $security --from-beginning --max-messages $nb_messages > "$fifo_path" 2>&1 &
            else
              timeout $timeout docker exec -e SCHEMA_REGISTRY_LOG4J_OPTS="-Dlog4j.configuration=file:/etc/kafka/tools-log4j.properties" $container kafka-$value_type-console-consumer -bootstrap-server $bootstrap_server --property schema.registry.url=$sr_url_cli --topic $topic --property print.partition=true --property print.offset=true --property print.headers=true --property print.timestamp=true --property print.key=true --property key.separator="|" --skip-message-on-error $security --from-beginning --max-messages $nb_messages > "$fifo_path" 2>&1 &
            fi
        else
            if [[ "$environment" == "environment" ]]
            then
              timeout $timeout docker run --rm -e SCHEMA_REGISTRY_LOG4J_OPTS="-Dlog4j.configuration=file:/etc/kafka/tools-log4j.properties" -e value_type=$value_type -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" ${CP_CONNECT_IMAGE}:${CONNECT_TAG} kafka-$value_type-console-consumer --bootstrap-server $BOOTSTRAP_SERVERS --topic $topic --consumer-property ssl.endpoint.identification.algorithm=https --consumer-property sasl.mechanism=PLAIN --consumer-property security.protocol=SASL_SSL --consumer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --property print.partition=true --property print.offset=true --property print.headers=true --property print.timestamp=true --property print.key=true --property key.separator="|"  --property key.deserializer=org.apache.kafka.common.serialization.StringDeserializer --skip-message-on-error $security --from-beginning --max-messages $nb_messages > "$fifo_path" 2>&1 &
            else
              timeout $timeout docker exec -e SCHEMA_REGISTRY_LOG4J_OPTS="-Dlog4j.configuration=file:/etc/kafka/tools-log4j.properties" $container kafka-$value_type-console-consumer --bootstrap-server $bootstrap_server --property schema.registry.url=$sr_url_cli --topic $topic --property print.partition=true --property print.offset=true --property print.headers=true --property print.timestamp=true --property print.key=true --property key.separator="|" --property key.deserializer=org.apache.kafka.common.serialization.StringDeserializer --skip-message-on-error $security --from-beginning --max-messages $nb_messages > "$fifo_path" 2>&1 &
            fi
        fi
        ;;
    *)
      if [[ "$environment" == "environment" ]]
      then
        timeout $timeout docker run --rm -v /tmp/delta_configs/ak-tools-ccloud.delta:/tmp/configuration/ccloud.properties -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" ${CP_CONNECT_IMAGE}:${CONNECT_TAG} kafka-console-consumer --bootstrap-server $BOOTSTRAP_SERVERS --topic $topic --consumer.config  --property print.partition=true --property print.offset=true --property print.headers=true --property print.timestamp=true --property print.key=true --property key.separator="|" $security --from-beginning --max-messages $nb_messages > "$fifo_path" 2>&1 &
      else
        timeout $timeout docker exec $container kafka-console-consumer --bootstrap-server $bootstrap_server --topic $topic --property print.partition=true --property print.offset=true --property print.headers=true --property print.timestamp=true --property print.key=true --property key.separator="|" $security --from-beginning --max-messages $nb_messages > "$fifo_path" 2>&1  &
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

  found=0
  # Loop through each line in the named pipe
  while read -r line
  do
    if [[ $line =~ "CreateTime:" ]]
    then
      # Extract the timestamp from the line
      timestamp_ms=$(echo "$line" | cut -d ":" -f 2 | cut -d "|" -f 1)
      # Convert milliseconds to seconds
      timestamp_sec=$((timestamp_ms / 1000))
      milliseconds=$((timestamp_ms % 1000))
      readable_date="$(${date_command}${timestamp_sec} "+%Y-%m-%d %H:%M:%S.${milliseconds}")"
      line_with_date=$(echo "$line" | sed -E "s/CreateTime:[0-9]{13}/CreateTime: ${readable_date}/")
      echo "$line_with_date"
    elif [[ $line =~ "Processed a total of" ]]
    then
      continue
    else
      echo "$line"
    fi
    if [[ -n "$grep_string" ]]
    then
      if [[ $line =~ "$grep_string" ]]
      then
        log "✅ found $grep_string in topic $topic"
        found=1
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