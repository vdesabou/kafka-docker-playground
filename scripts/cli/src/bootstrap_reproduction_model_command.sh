IGNORE_CHECK_FOR_DOCKER_COMPOSE=true

DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

root_folder=${DIR_CLI}/../..

test_file="$PWD/${args[--file]}"
description="${args[--description]}"
producer="${args[--producer]}"
nb_producers="${args[--nb-producers]}"
add_custom_smt="${args[--custom-smt]}"

if [ "$test_file" = "" ]
then
  logerror "ERROR: test_file is not provided as argument!"
  exit 1
fi

if [ ! -f "$test_file" ]
then
  logerror "ERROR: test_file $test_file does not exist!"
  exit 1
fi

if [[ "$test_file" != *".sh" ]]
then
  logerror "ERROR: test_file $test_file is not a .sh file!"
  exit 1
fi

if [[ "$(dirname $test_file)" == *. ]]
then
  logerror "ERROR: do not use './' for the test file!"
  exit 1
fi

if [ "$description" = "" ]
then
  logerror "ERROR: description is not provided as argument!"
  exit 1
fi

if [ "$nb_producers" == "" ]
then
  nb_producers=1
fi

test_file_directory="$(dirname "${test_file}")"


# determining the connector from test_file
docker_compose_file=$(grep "environment" "$test_file" | grep DIR | grep start.sh | cut -d "/" -f 7 | cut -d '"' -f 1 | tail -n1 | xargs)
description_kebab_case="${description// /-}"
description_kebab_case=$(echo "$description_kebab_case" | tr '[:upper:]' '[:lower:]')

if [ "${docker_compose_file}" != "" ] && [ ! -f "${docker_compose_file}" ]
then
  docker_compose_file=""
  logwarn "📁 Could not determine docker-compose override file from $test_file !"
fi

topic_name="customer-$producer"
topic_name=$(echo $topic_name | tr '-' '_')
filename=$(basename -- "$test_file")
extension="${filename##*.}"
filename="${filename%.*}"

base1="${test_file_directory##*/}" # connect-cdc-oracle12-source
dir1="${test_file_directory%/*}" #connect
dir2="${dir1##*/}/$base1" # connect/connect-cdc-oracle12-source
final_dir=$(echo $dir2 | tr '/' '-') # connect-connect-cdc-oracle12-source

output_folder="reproduction-models"
if [ ! -z "$OUTPUT_FOLDER" ]
then
    log "📂 Output folder is set with OUTPUT_FOLDER environment variable"
    output_folder="$OUTPUT_FOLDER"
else
    log "📂 Output folder is default $output_folder (you can change it by setting OUTPUT_FOLDER environment variable)"
fi

repro_dir=$root_folder/$output_folder/$final_dir
mkdir -p $repro_dir

repro_test_file="$repro_dir/$filename-repro-$description_kebab_case.$extension"

if [ "${docker_compose_file}" != "" ]
then
  filename=$(basename -- "$PWD/$docker_compose_file")
  extension="${filename##*.}"
  filename="${filename%.*}"

  docker_compose_test_file="$repro_dir/$filename.repro-$description_kebab_case.$extension"
  log "✨ Creating file $docker_compose_test_file"
  rm -f $docker_compose_test_file
  cp $PWD/$docker_compose_file $docker_compose_test_file

  docker_compose_test_file_name=$(basename -- "$docker_compose_test_file")
fi

log "✨ Creating file $repro_test_file"
rm -f $repro_test_file
if [ "${docker_compose_file}" != "" ]
then
  sed -e "s|$docker_compose_file|$docker_compose_test_file_name|g" \
    $test_file > $repro_test_file
else
  cp $test_file $repro_test_file
fi

for file in README.md docker-compose*.yml keyfile.json stop.sh .gitignore oracle-datagen
do
  if [ -f $file ]
  then
    cd $repro_dir > /dev/null
    ln -sf ../../$dir2/$file .
    cd - > /dev/null
  fi
done
  
if [ "$producer" != "none" ]
then
  case "${producer}" in
    avro)
      log "value converter should be set with:"
      echo "\"value.converter\": \"io.confluent.connect.avro.AvroConverter\","
      echo "\"value.converter.schema.registry.url\": \"http://schema-registry:8081\","

      echo ""
      log "Examples to consume:"
      log "1️⃣ Simplest"
      echo "docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic a-topic --from-beginning --max-messages 1"
      log "2️⃣ Displaying key:"
      echo "docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic a-topic --property print.key=true --property key.separator=, --from-beginning --max-messages 1"
    ;;
    avro-with-key)
      log "key converter should be set with:"
      echo "\"key.converter\": \"io.confluent.connect.avro.AvroConverter\","
      echo "\"key.converter.schema.registry.url\": \"http://schema-registry:8081\","
      echo ""
      log "value converter should be set with:"
      echo "\"value.converter\": \"io.confluent.connect.avro.AvroConverter\","
      echo "\"value.converter.schema.registry.url\": \"http://schema-registry:8081\","

      echo ""
      log "Examples to consume:"
      log "1️⃣ Simplest"
      echo "docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic a-topic --from-beginning --max-messages 1"
      log "2️⃣ Displaying key:"
      echo "docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic a-topic --property print.key=true --property key.separator=, --from-beginning --max-messages 1"
    ;;
    json-schema)
      echo ""
      log "value converter should be set with:"
      echo "\"value.converter\": \"io.confluent.connect.json.JsonSchemaConverter\","
      echo "\"value.converter.schema.registry.url\": \"http://schema-registry:8081\","

      echo ""
      log "Examples to consume:"
      log "1️⃣ Simplest"
      echo "docker exec connect kafka-json-schema-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic a-topic --from-beginning --max-messages 1"
      log "2️⃣ Displaying key:"
      echo "docker exec connect kafka-json-schema-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic a-topic --property print.key=true --property key.separator=, --from-beginning --max-messages 1"
    ;;
    json-schema-with-key)
      log "key converter should be set with:"
      echo "\"key.converter\": \"io.confluent.connect.json.JsonSchemaConverter\","
      echo "\"key.converter.schema.registry.url\": \"http://schema-registry:8081\","
      echo ""
      log "value converter should be set with:"
      echo "\"value.converter\": \"io.confluent.connect.json.JsonSchemaConverter\","
      echo "\"value.converter.schema.registry.url\": \"http://schema-registry:8081\","

      echo ""
      log "Examples to consume:"
      log "1️⃣ Simplest"
      echo "docker exec connect kafka-json-schema-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic a-topic --from-beginning --max-messages 1"
      log "2️⃣ Displaying key:"
      echo "docker exec connect kafka-json-schema-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic a-topic --property print.key=true --property key.separator=, --from-beginning --max-messages 1"
    ;;
    protobuf)
      log "value converter should be set with:"
      echo "\"value.converter\": \"io.confluent.connect.protobuf.ProtobufConverter\","
      echo "\"value.converter.schema.registry.url\": \"http://schema-registry:8081\","

      echo ""
      log "Examples to consume:"
      log "1️⃣ Simplest"
      echo "docker exec connect kafka-protobuf-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic a-topic --from-beginning --max-messages 1"
      log "2️⃣ Displaying key:"
      echo "docker exec connect kafka-protobuf-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic a-topic --property print.key=true --property key.separator=, --from-beginning --max-messages 1"
    ;;
    protobuf-with-key)
      log "key converter should be set with:"
      echo "\"key.converter\": \"io.confluent.connect.protobuf.ProtobufConverter\","
      echo "\"key.converter.schema.registry.url\": \"http://schema-registry:8081\","
      log "value converter should be set with:"
      echo "\"value.converter\": \"io.confluent.connect.protobuf.ProtobufConverter\","
      echo "\"value.converter.schema.registry.url\": \"http://schema-registry:8081\","

      echo ""
      log "Examples to consume:"
      log "1️⃣ Simplest"
      echo "docker exec connect kafka-protobuf-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic a-topic --from-beginning --max-messages 1"
      log "2️⃣ Displaying key:"
      echo "docker exec connect kafka-protobuf-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic a-topic --property print.key=true --property key.separator=, --from-beginning --max-messages 1"
    ;;
    none)
    ;;
    *)
      logerror "ERROR: producer name not valid ! Should be one of avro, avro-with-key, json-schema, json-schema-with-key, protobuf or protobuf-with-key"
      exit 1
    ;;
  esac
      original_topic_name=$(grep "\"topics\"" $repro_test_file | cut -d "\"" -f 4 | head -1)
      if [ "$original_topic_name" != "" ]
      then
        tmp=$(echo $original_topic_name | tr '-' '\-')
        sed -e "s|$tmp|$topic_name|g" \
            $repro_test_file > /tmp/tmp

        mv /tmp/tmp $repro_test_file
        # log "✨ Replacing topic $original_topic_name with $topic_name"
      fi

      tmp_dir=$(mktemp -d -t ci-XXXXXXXXXX)
      for((i=1;i<=$nb_producers;i++)); do
        # looks like there is a maximum size for hostname in docker (container init caused: sethostname: invalid argument: unknown)
        producer_hostname=""
        producer_hostname="producer-repro-$description_kebab_case"
        producer_hostname=${producer_hostname:0:21}
        if [ $nb_producers -eq 1 ]
        then
          producer_hostname="${producer_hostname}"
        else
          producer_hostname="${producer_hostname}$i"
        fi

        rm -rf $producer_hostname
        mkdir -p $repro_dir/$producer_hostname/
        cp -Ra ../../other/schema-format-$producer/producer/* $repro_dir/$producer_hostname/

        # update docker compose with producer container
        if [[ "$dir1" = *connect ]]
        then
          get_producer_heredoc
        fi

        if [[ "$dir1" = *ccloud ]]
        then
          get_producer_ccloud_heredoc
        fi
      done

  if [ "${docker_compose_file}" != "" ]
  then
    cp $docker_compose_test_file $tmp_dir/tmp_file
    line=$(grep -n 'services:' $docker_compose_test_file | cut -d ":" -f 1 | tail -n1)
    
    { head -n $(($line)) $tmp_dir/tmp_file; cat $tmp_dir/producer; tail -n +$(($line+1)) $tmp_dir/tmp_file; } > $docker_compose_test_file

  else 
    logwarn "As docker-compose override file could not be determined, you will need to add this manually:"
    cat $tmp_dir/producer
  fi

  for((i=1;i<=$nb_producers;i++)); do
    log "✨ Adding Java $producer producer in $repro_dir/$producer_hostname"
    producer_hostname=""
    producer_hostname="producer-repro-$description_kebab_case"
    producer_hostname=${producer_hostname:0:21} 
    if [ $nb_producers -eq 1 ]
    then
      producer_hostname="${producer_hostname}"
    else
      producer_hostname="${producer_hostname}$i"
    fi

    list="$list $producer_hostname"

  done
  get_producer_build_heredoc
  # log "✨ Adding command to build jar for $producer_hostname to $repro_test_file"
  cp $repro_test_file $tmp_dir/tmp_file
  line=$(grep -n '${DIR}/../../environment' $repro_test_file | cut -d ":" -f 1 | tail -n1)
  
  { head -n $(($line-1)) $tmp_dir/tmp_file; cat $tmp_dir/build_producer; tail -n +$line $tmp_dir/tmp_file; } > $repro_test_file

  line_kafka_cli_producer=$(egrep -n "kafka-console-producer|kafka-avro-console-producer|kafka-json-schema-console-producer|kafka-protobuf-console-producer" $repro_test_file | cut -d ":" -f 1 | tail -n1)
  kafka_cli_producer_error=0
  kafka_cli_producer_eof=0
  set +e
  egrep "kafka-console-producer|kafka-avro-console-producer|kafka-json-schema-console-producer|kafka-protobuf-console-producer" $repro_test_file | grep EOF > /dev/null
  if [ $? = 0 ]
  then
      kafka_cli_producer_eof=1

      sed -n "$line_kafka_cli_producer,$(($line_kafka_cli_producer + 10))p" $repro_test_file > /tmp/tmp
      tmp=$(grep -n "^EOF" /tmp/tmp | cut -d ":" -f 1 | tail -n1)
      if [ $tmp == "" ]
      then
        logwarn "Could not determine EOF for kafka cli producer!"
        kafka_cli_producer_error=1
      fi
      line_kafka_cli_producer_end=$(($line_kafka_cli_producer + $tmp))
  else
      logwarn "Could not find kafka cli producer!"
      kafka_cli_producer_error=1
  fi
  set -e
  if [ $kafka_cli_producer_error = 1 ]
  then
    get_producer_fixthis_heredoc
  fi

  for((i=1;i<=$nb_producers;i++)); do
    producer_hostname=""
    producer_hostname="producer-repro-$description_kebab_case"
    producer_hostname=${producer_hostname:0:21} 
    if [ $nb_producers -eq 1 ]
    then
      producer_hostname="${producer_hostname}"
    else
      producer_hostname="${producer_hostname}$i"
    fi
    get_producer_run_heredoc
  done
  if [ $kafka_cli_producer_error = 1 ]
  then
    get_producer_fixthis_heredoc
  fi
  # log "✨ Adding command to run producer to $repro_test_file"
  cp $repro_test_file $tmp_dir/tmp_file

  if [ $kafka_cli_producer_error == 1 ]
  then
      { head -n $(($line-1)) $tmp_dir/tmp_file; cat $tmp_dir/java_producer; tail -n +$line $tmp_dir/tmp_file; } > $repro_test_file
  else
    if [ $kafka_cli_producer_eof == 0 ]
    then
      line_kafka_cli_producer_end=$(($line_kafka_cli_producer + 1))
    fi
    { head -n $(($line_kafka_cli_producer - 2)) $tmp_dir/tmp_file; cat $tmp_dir/java_producer; tail -n +$line_kafka_cli_producer_end $tmp_dir/tmp_file; } > $repro_test_file
  fi
fi

if [[ -n "$add_custom_smt" ]]
then
  custom_smt_name=""
  custom_smt_name="MyCustomSMT-$description_kebab_case"
  custom_smt_name=${custom_smt_name:0:18}
  mkdir -p $repro_dir/$custom_smt_name/
  cp -Ra ../../other/custom-smt/MyCustomSMT/* $repro_dir/$custom_smt_name/

  tmp_dir=$(mktemp -d -t ci-XXXXXXXXXX)

  get_custom_smt_build_heredoc
  # log "✨ Adding command to build jar for $custom_smt_name to $repro_test_file"
  cp $repro_test_file $tmp_dir/tmp_file
  line=$(grep -n '${DIR}/../../environment' $repro_test_file | cut -d ":" -f 1 | tail -n1)
  
  { head -n $(($line-1)) $tmp_dir/tmp_file; cat $tmp_dir/build_custom_smt; tail -n +$line $tmp_dir/tmp_file; } > $repro_test_file


  connector_paths=$(grep "CONNECT_PLUGIN_PATH" "${docker_compose_file}" | grep -v "KSQL_CONNECT_PLUGIN_PATH" | cut -d ":" -f 2  | tr -s " " | head -1)
  if [ "$connector_paths" == "" ]
  then
    logerror "ERROR: not a connector test"
    exit 1
  else
    ###
    #  Loop on all connectors in CONNECT_PLUGIN_PATH and install custom SMT jar in lib folder
    ###
    my_array_connector_tag=($(echo $CONNECTOR_TAG | tr "," "\n"))
    for connector_path in ${connector_paths//,/ }
    do
      echo "log \"📂 Copying custom jar to connector folder $connector_path/lib/\"" >> $tmp_dir/build_custom_docker_cp_smt
      echo "docker cp $repro_dir/$custom_smt_name/target/MyCustomSMT-1.0.0-SNAPSHOT-jar-with-dependencies.jar connect:$connector_path/lib/" >> $tmp_dir/build_custom_docker_cp_smt
    done
    echo "log \"♻️ Restart connect worker to load\"" >> $tmp_dir/build_custom_docker_cp_smt
    echo "docker restart connect" >> $tmp_dir/build_custom_docker_cp_smt
    echo "sleep 45" >> $tmp_dir/build_custom_docker_cp_smt
  fi

  cp $repro_test_file $tmp_dir/tmp_file
  line=$(grep -n '${DIR}/../../environment' $repro_test_file | cut -d ":" -f 1 | tail -n1)
  
  { head -n $(($line+2)) $tmp_dir/tmp_file; cat $tmp_dir/build_custom_docker_cp_smt; tail -n +$(($line+2)) $tmp_dir/tmp_file; } > $repro_test_file

  echo "              \"transforms\": \"MyCustomSMT\"," >> $tmp_dir/build_custom_smt_json_config
  echo "              \"transforms.MyCustomSMT.type\": \"com.github.vdesabou.kafka.connect.transforms.MyCustomSMT\"," >> $tmp_dir/build_custom_smt_json_config

  cp $repro_test_file $tmp_dir/tmp_file
  line=$(grep -n 'connector.class' $repro_test_file | cut -d ":" -f 1 | tail -n1)
  
  { head -n $(($line)) $tmp_dir/tmp_file; cat $tmp_dir/build_custom_smt_json_config; tail -n +$(($line+1)) $tmp_dir/tmp_file; } > $repro_test_file

fi

chmod u+x $repro_test_file
repro_test_filename=$(basename -- "$repro_test_file")

log "📂 The reproduction files are now available in:\n$repro_dir"
log "🚀 Copy/paste the following to get it right away:"
echo ""
echo "cd $repro_dir"
echo "code $repro_test_filename"
if [ "$(whoami)" != "vsaboulin" ] && [ "$(whoami)" != "ec2-user" ]
then
  echo ""

  log "🆗 Once ready, run it with:"
fi
echo "./$repro_test_filename"

