if [ ! -f /tmp/playground-run ]
then
  logerror "File containing re-run command /tmp/playground-run does not exist!"
  logerror "Make sure to use <playground run> command !"
  exit 1
fi

test_file=$(cat /tmp/playground-run |tr '\t' ' ' |cut -d' ' -f4)
if [ ! -f $test_file ]
then
  logerror "Could not find test file in /tmp/playground-run"
  cat /tmp/playground-run
  exit 1
fi

environment=`get_environment_used`

if [ "$environment" == "error" ]
then
  logerror "File containing restart command /tmp/playground-command does not exist!"
  exit 1 
fi

container="connect"
sr_url="http://schema-registry:8081"
security=""
if [[ "$environment" == *"ssl"* ]]
then
    sr_url="https://schema-registry:8081"
    security="--property schema.registry.ssl.truststore.location=/etc/kafka/secrets/kafka.client.truststore.jks --property schema.registry.ssl.truststore.password=confluent --property schema.registry.ssl.keystore.location=/etc/kafka/secrets/kafka.client.keystore.jks --property schema.registry.ssl.keystore.password=confluent --consumer.config /etc/kafka/secrets/client_without_interceptors.config"
elif [[ "$environment" == "rbac-sasl-plain" ]]
then
    sr_url="http://schema-registry:8081"
    security="--property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info=clientAvroCli:clientAvroCli --consumer.config /etc/kafka/secrets/client_without_interceptors.config"
elif [[ "$environment" == "kerberos" ]]
then
    container="client"
    sr_url="http://schema-registry:8081"
    security="--consumer.config /etc/kafka/consumer.properties"

    docker exec -i client kinit -k -t /var/lib/secret/kafka-connect.key connect
fi

tmp_dir=$(mktemp -d -t ci-XXXXXXXXXX)
awk -F'--topic ' '{print $2}' $test_file > $tmp_dir/tmp
sed '/^$/d' $tmp_dir/tmp > $tmp_dir/tmp2
topic_name=$(head -1 $tmp_dir/tmp2 | cut -d " " -f1)

if [ "$topic_name" != "" ]
then
  key_converter=$(grep "\"key.converter\"" $test_file | cut -d '"' -f 4)
  if [ "$key_converter" == "" ]
  then
    log "🔮 connector is using default key.converter, i.e org.apache.kafka.connect.storage.StringConverter"
    key_converter="io.confluent.connect.avro.AvroConverter"
  else
    log "🔮 connector is using key.converter $key_converter"
  fi

  value_converter=$(grep "\"value.converter\"" $test_file | cut -d '"' -f 4)
  if [ "$value_converter" == "" ]
  then
    log "🔮 connector is using default value.converter, i.e io.confluent.connect.avro.AvroConverter"
    value_converter="io.confluent.connect.avro.AvroConverter"
  else
    log "🔮 connector is using value.converter $value_converter"
  fi
  log "✨ Display content of topic $topic_name, press crtl-c to stop..."
  type=""
  case "${value_converter}" in
    io.confluent.connect.json.JsonSchemaConverter)
        type="json-schema"
    ;;
    io.confluent.connect.protobuf.ProtobufConverter)
        type="protobuf"
    ;;
    io.confluent.connect.avro.AvroConverter)
        type="avro"
        ;;
    *)
    ;;
  esac

  fifo_path="$tmp_dir/kafka_output_fifo"
  mkfifo "$fifo_path"
  case "${type}" in
    avro|protobuf|json-schema)
        if [ "$key_converter" == "io.confluent.connect.avro.AvroConverter" ]
        then
            docker exec $container kafka-$type-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=$sr_url --topic $topic_name --property print.partition=true --property print.offset=true --property print.headers=true --property print.timestamp=true --property print.key=true --property key.separator="|" $security --from-beginning > "$fifo_path" &
        else
            docker exec $container kafka-$type-console-consumer --bootstrap-server broker:9092 --property schema.registry.url=$sr_url --topic $topic_name --property print.partition=true --property print.offset=true --property print.headers=true --property print.timestamp=true --property print.key=true --property key.separator="|" --property key.deserializer=org.apache.kafka.common.serialization.StringDeserializer $security --from-beginning > "$fifo_path" &
        fi
        ;;
    *)
        docker exec $container kafka-console-consumer --bootstrap-server broker:9092 --topic $topic_name --property print.partition=true --property print.offset=true --property print.headers=true --property print.timestamp=true --property print.key=true --property key.separator="|" $security --from-beginning > "$fifo_path" &
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

  # Loop through each line in the named pipe
  while read -r line; do
    # Extract the timestamp from the line
    timestamp_ms=$(echo "$line" | cut -d ":" -f 2 | cut -d "|" -f 1)
    
    # Convert milliseconds to seconds
    timestamp_sec=$((timestamp_ms / 1000))
    milliseconds=$((timestamp_ms % 1000))
    
    readable_date="$(${date_command}${timestamp_sec} "+%Y-%m-%d %H:%M:%S.${milliseconds}")"

    line_with_date=$(echo "$line" | sed -E "s/CreateTime:[0-9]{13}/CreateTime: ${readable_date}/")

    echo "$line_with_date"
  done < "$fifo_path"
else    
  logwarn "Could not find topic name !"
  exit 1
fi