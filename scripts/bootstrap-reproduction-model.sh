#!/bin/bash

IGNORE_CHECK_FOR_DOCKER_COMPOSE=true
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../scripts/utils.sh

root_folder=${DIR}/..
root_folder=${root_folder//\/scripts\/\.\./}

test_file="$PWD/$1"
description="$2"
schema_format="$3"
nb_producers="$4"

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

topic_name="customer-$schema_format"
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
  
if [ "$schema_format" != "" ]
then
  case "${schema_format}" in
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
    *)
      logerror "ERROR: schema_format name not valid ! Should be one of avro, avro-with-key, json-schema, json-schema-with-key, protobuf or protobuf-with-key"
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
        cp -Ra ../../other/schema-format-$schema_format/producer/* $repro_dir/$producer_hostname/

        # update docker compose with producer container
        if [[ "$dir1" = *connect ]]
        then
        cat << EOF >> $tmp_dir/producer

  $producer_hostname:
    build:
      context: ../../$output_folder/$final_dir/$producer_hostname/
    hostname: producer
    container_name: $producer_hostname
    environment:
      KAFKA_BOOTSTRAP_SERVERS: broker:9092
      TOPIC: "$topic_name"
      REPLICATION_FACTOR: 1
      NUMBER_OF_PARTITIONS: 1
      NB_MESSAGES: 10 # -1 for MAX_VALUE
      MESSAGE_BACKOFF: 100 # Frequency of message injection
      KAFKA_ACKS: "all" # default: "1"
      KAFKA_REQUEST_TIMEOUT_MS: 20000
      KAFKA_RETRY_BACKOFF_MS: 500
      KAFKA_CLIENT_ID: "my-java-$producer_hostname"
      KAFKA_SCHEMA_REGISTRY_URL: "http://schema-registry:8081"
      JAVA_OPTS: \${GRAFANA_AGENT_PRODUCER}
    volumes:
      - ../../environment/plaintext/jmx-exporter:/usr/share/jmx_exporter/


EOF
fi

        if [[ "$dir1" = *ccloud ]]
        then
        cat << EOF >> $tmp_dir/producer

  $producer_hostname:
    build:
      context: ../../$output_folder/$final_dir/$producer_hostname/
    hostname: producer
    container_name: $producer_hostname
    environment:
      KAFKA_BOOTSTRAP_SERVERS: \$BOOTSTRAP_SERVERS
      KAFKA_SSL_ENDPOINT_IDENTIFICATION_ALGORITHM: "https"
      KAFKA_SASL_MECHANISM: "PLAIN"
      KAFKA_SASL_JAAS_CONFIG: \$SASL_JAAS_CONFIG
      KAFKA_SECURITY_PROTOCOL: "SASL_SSL"
      TOPIC: "$topic_name"
      REPLICATION_FACTOR: 3
      NUMBER_OF_PARTITIONS: 1
      NB_MESSAGES: 10 # -1 for MAX_VALUE
      MESSAGE_BACKOFF: 100 # Frequency of message injection
      KAFKA_ACKS: "all" # default: "1"
      KAFKA_REQUEST_TIMEOUT_MS: 20000
      KAFKA_RETRY_BACKOFF_MS: 500
      KAFKA_CLIENT_ID: "my-java-$producer_hostname"
      KAFKA_SCHEMA_REGISTRY_URL: \$SCHEMA_REGISTRY_URL
      KAFKA_BASIC_AUTH_CREDENTIALS_SOURCE: \$BASIC_AUTH_CREDENTIALS_SOURCE
      KAFKA_SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO: \$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO
      JAVA_OPTS: \${GRAFANA_AGENT_PRODUCER}
      EXTRA_ARGS: 
    volumes:
      - ../../environment/plaintext/jmx-exporter:/usr/share/jmx_exporter/


EOF
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
    log "✨ Adding Java $schema_format producer in $repro_dir/$producer_hostname"
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
    cat << EOF > $tmp_dir/build_producer
for component in $list
do
    set +e
    log "🏗 Building jar for \${component}"
    docker run -i --rm -e KAFKA_CLIENT_TAG=\$KAFKA_CLIENT_TAG -e TAG=\$TAG_BASE -v "\${DIR}/\${component}":/usr/src/mymaven -v "\$HOME/.m2":/root/.m2 -v "\${DIR}/\${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -Dkafka.tag=\$TAG -Dkafka.client.tag=\$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
    if [ \$? != 0 ]
    then
        logerror "ERROR: failed to build java component $component"
        tail -500 /tmp/result.log
        exit 1
    fi
    set -e
done

EOF
  # log "✨ Adding command to build jar for $producer_hostname to $repro_test_file"
  cp $repro_test_file $tmp_dir/tmp_file
  line=$(grep -n '${DIR}/../../environment' $repro_test_file | cut -d ":" -f 1 | tail -n1)
  
  { head -n $(($line-1)) $tmp_dir/tmp_file; cat $tmp_dir/build_producer; tail -n +$line $tmp_dir/tmp_file; } > $repro_test_file

    cat << EOF > $tmp_dir/java_producer

# 🚨🚨🚨 FIXTHIS: move it to the correct place 🚨🚨🚨
EOF

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
    cat << EOF >> $tmp_dir/java_producer
log "✨ Run the $schema_format java producer v$i which produces to topic $topic_name"
docker exec $producer_hostname bash -c "java \${JAVA_OPTS} -jar producer-1.0.0-jar-with-dependencies.jar"
EOF
  done
    cat << EOF >> $tmp_dir/java_producer
# 🚨🚨🚨 FIXTHIS: move it to the correct place 🚨🚨🚨

EOF
  # log "✨ Adding command to run producer to $repro_test_file"
  cp $repro_test_file $tmp_dir/tmp_file
  { head -n $(($line-1)) $tmp_dir/tmp_file; cat $tmp_dir/java_producer; tail -n +$line $tmp_dir/tmp_file; } > $repro_test_file
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
