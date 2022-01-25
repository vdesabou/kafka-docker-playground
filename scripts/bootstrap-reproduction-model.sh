#!/bin/bash

IGNORE_CHECK_FOR_DOCKER_COMPOSE=true
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../scripts/utils.sh

test_file="$PWD/$1"
description="$2"
schema_format="$3"

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

if [ "$description" = "" ]
then
  logerror "ERROR: description is not provided as argument!"
  exit 1
fi

test_file_directory="$(dirname "${test_file}")"

# determining the connector from test_file
docker_compose_file=$(grep "environment" "$test_file" | grep DIR | grep start.sh | cut -d "/" -f 7 | cut -d '"' -f 1 | head -n1)
description_kebab_case="${description// /-}"
description_kebab_case=$(echo "$description_kebab_case" | tr '[:upper:]' '[:lower:]')

if [ "${docker_compose_file}" != "" ] && [ -f "${docker_compose_file}" ]
then
  topic_name="customer-$schema_format"
  topic_name=$(echo $topic_name | tr '-' '_')
  filename=$(basename -- "$test_file")
  extension="${filename##*.}"
  filename="${filename%.*}"

  repro_test_file="$test_file_directory/$filename-repro-$description_kebab_case.$extension"

  filename=$(basename -- "$PWD/$docker_compose_file")
  extension="${filename##*.}"
  filename="${filename%.*}"

  docker_compose_test_file="$test_file_directory/$filename.repro-$description_kebab_case.$extension"
  log "🎩 Creating file $(basename -- $docker_compose_test_file)"
  rm -f $docker_compose_test_file
  cp $PWD/$docker_compose_file $docker_compose_test_file

  docker_compose_test_file_name=$(basename -- "$docker_compose_test_file")

  log "🎩 Creating file $(basename -- $repro_test_file)"
  rm -f $repro_test_file
  sed -e "s|$docker_compose_file|$docker_compose_test_file_name|g" \
      $test_file > $repro_test_file

  original_topic_name=$(grep "\"topics\"" $repro_test_file | cut -d "\"" -f 4)
  if [ "$original_topic_name" != "" ]
  then
    sed -e "s|$original_topic_name|$topic_name|g" \
        $repro_test_file > /tmp/tmp

    mv /tmp/tmp $repro_test_file
    chmod u+x $repro_test_file
    log "🎩 Replacing topic $original_topic_name with $topic_name"
  fi

  if [ "$schema_format" != "" ]
  then
    case "${schema_format}" in
      avro)
      ;;
      json-schema)
      ;;
      protobuf)
      ;;
      *)
        logerror "ERROR: schema_format name not valid ! Should be one of avro, json-schema or protobuf"
        exit 1
      ;;
    esac
        # looks like there is a maximum size for hostname in docker (container init caused: sethostname: invalid argument: unknown)
        producer_hostname="producer-repro-$description_kebab_case"
        producer_hostname=${producer_hostname:0:20} 
        
        rm -rf $producer_hostname
        cp -Ra ../../other/schema-format-$schema_format/producer $producer_hostname
        
        # update docker compose with producer container
        base1="${test_file_directory##*/}"
        dir1="${test_file_directory%/*}"
        test_file_directory_2_levels="${dir1##*/}/$base1"

        tmp_dir=$(mktemp -d -t ci-XXXXXXXXXX)
        cat << EOF > $tmp_dir/producer

  $producer_hostname:
    build:
      context: ../../$test_file_directory_2_levels/$producer_hostname/
    hostname: $producer_hostname
    container_name: $producer_hostname
    environment:
      KAFKA_BOOTSTRAP_SERVERS: broker:9092
      TOPIC: "$topic_name"
      REPLICATION_FACTOR: 1
      NUMBER_OF_PARTITIONS: 1
      MESSAGE_BACKOFF: 1000 # Frequency of message injection
      KAFKA_ACKS: "all" # default: "1"
      KAFKA_REQUEST_TIMEOUT_MS: 20000
      KAFKA_RETRY_BACKOFF_MS: 500
      KAFKA_CLIENT_ID: "my-java-$producer_hostname"
      KAFKA_SCHEMA_REGISTRY_URL: "http://schema-registry:8081"
EOF
      log "🎩 Adding $producer_hostname container to $docker_compose_test_file_name"
      cat $tmp_dir/producer >> $docker_compose_test_file_name

        cat << EOF > $tmp_dir/build_producer
for component in $producer_hostname
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
      log "🎩 Adding command to build jar for $producer_hostname to $repro_test_file"
      cp $repro_test_file $tmp_dir/tmp_file
      line=$(grep -n '${DIR}/../../environment' $repro_test_file | cut -d ":" -f 1)
      
      { head -n $(($line-1)) $tmp_dir/tmp_file; cat $tmp_dir/build_producer; tail -n +$line $tmp_dir/tmp_file; } > $repro_test_file

        cat << EOF > $tmp_dir/java_producer

# 🚨🚨🚨 FIXTHIS: move it to the correct place 🚨🚨🚨
log "✨ Run the $schema_format java producer which produces to topic $topic_name"
docker exec $producer_hostname bash -c "java -jar producer-1.0.0-jar-with-dependencies.jar"

EOF
      log "🎩 Adding command to run producer to $repro_test_file"
      cp $repro_test_file $tmp_dir/tmp_file      
      { head -n $(($line-1)) $tmp_dir/tmp_file; cat $tmp_dir/java_producer; tail -n +$line $tmp_dir/tmp_file; } > $repro_test_file

  fi
else
  logerror "📁 Could not determine docker-compose override file from $test_file !"
  exit 1
fi