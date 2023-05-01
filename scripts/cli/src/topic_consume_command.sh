topic="${args[--topic]}"

environment=`get_environment_used`

if [ "$environment" == "error" ]
then
  logerror "File containing restart command /tmp/playground-command does not exist!"
  exit 1 
fi

ret=$(get_sr_url_and_security)

sr_url=$(echo "$ret" | cut -d "@" -f 1)
sr_security=$(echo "$ret" | cut -d "@" -f 2)

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

log "✨ Display content of topic $topic, press crtl-c to stop..."
type=""
tmp_dir=$(mktemp -d -t ci-XXXXXXXXXX)
fifo_path="$tmp_dir/kafka_output_fifo"
mkfifo "$fifo_path"
case "${value_type}" in
  avro|protobuf|json-schema)
      if [ "$key_type" == "avro" ] || [ "$key_type" == "protobuf" ] || [ "$key_type" == "json-schema" ]
      then
          docker exec $container kafka-$value_type-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=$sr_url --topic $topic --property print.partition=true --property print.offset=true --property print.headers=true --property print.timestamp=true --property print.key=true --property key.separator="|" $security --from-beginning > "$fifo_path" &
      else
          docker exec $container kafka-$value_type-console-consumer --bootstrap-server broker:9092 --property schema.registry.url=$sr_url --topic $topic --property print.partition=true --property print.offset=true --property print.headers=true --property print.timestamp=true --property print.key=true --property key.separator="|" --property key.deserializer=org.apache.kafka.common.serialization.StringDeserializer $security --from-beginning > "$fifo_path" &
      fi
      ;;
  *)
      docker exec $container kafka-console-consumer --bootstrap-server broker:9092 --topic $topic --property print.partition=true --property print.offset=true --property print.headers=true --property print.timestamp=true --property print.key=true --property key.separator="|" $security --from-beginning > "$fifo_path" &
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