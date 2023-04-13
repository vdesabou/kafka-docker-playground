if [ ! -f /tmp/playground-run ]
then
  logerror "File containing re-run command /tmp/playground-run does not exist!"
  logerror "Make sure to run playground run command !"
  exit 1
fi

test_file=$(cat /tmp/playground-run |tr '\t' ' ' |cut -d' ' -f4)
if [ ! -f $test_file ]
then
  logerror "Could not find test file in /tmp/playground-run"
  cat /tmp/playground-run
  exit 1
fi

tmp_dir=$(mktemp -d -t ci-XXXXXXXXXX)
awk -F'--topic ' '{print $2}' $test_file > $tmp_dir/tmp
sed '/^$/d' $tmp_dir/tmp > $tmp_dir/tmp2
topic_name=$(head -1 $tmp_dir/tmp2 | cut -d " " -f1)

if [ "$topic_name" != "" ]
then
  log "Consuming topic $topic_name"

  # deal with converters

  key_converter=$(grep "\"key.converter\"" $test_file | cut -d '"' -f 4)
  if [ "$key_converter" == "" ]
  then
    log "💱 connector is using default key.converter, i.e org.apache.kafka.connect.storage.StringConverter"
    key_converter="io.confluent.connect.avro.AvroConverter"
  else
    log "💱 connector is using key.converter $key_converter"
  fi

  value_converter=$(grep "\"value.converter\"" $test_file | cut -d '"' -f 4)
  if [ "$value_converter" == "" ]
  then
    log "💱 connector is using default value.converter, i.e io.confluent.connect.avro.AvroConverter"
    value_converter="io.confluent.connect.avro.AvroConverter"
  else
    log "💱 connector is using value.converter $value_converter"
  fi
  log "Display content of topic $topic_name, press crtl-c to stop..."
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

  case "${type}" in
    avro|protobuf|json-schema)
        if [ "$key_converter" == "io.confluent.connect.avro.AvroConverter" ]
        then
            docker exec connect kafka-$type-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic $topic_name --property print.partition=true --property print.offset=true --property print.headers=true --property print.timestamp=true --property print.key=true --property key.separator="|" --from-beginning
        else
            docker exec connect kafka-$type-console-consumer --bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic $topic_name --property print.partition=true --property print.offset=true --property print.headers=true --property print.timestamp=true --property print.key=true --property key.separator="|" --property key.deserializer=org.apache.kafka.common.serialization.StringDeserializer --from-beginning
        fi
        ;;
    *)
        docker exec connect kafka-console-consumer --bootstrap-server broker:9092 --topic $topic_name --property print.partition=true --property print.offset=true --property print.headers=true --property print.timestamp=true --property print.key=true --property key.separator="|" --from-beginning
    ;;
  esac
else    
  logwarn "Could not find topic name !"
  exit 1
fi