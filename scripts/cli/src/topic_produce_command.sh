topic="${args[--topic]}"
nb_messages="${args[--nb-messages]}"

schema=${args[schema]}

if [ "$schema" = "-" ]
then
    # stdin
    schema_content=$(cat "$schema")
else
    schema_content=$schema
fi
tmp_dir=$(mktemp -d -t ci-XXXXXXXXXX)
schema_file=$tmp_dir/value_schema
echo "$schema_content" > $schema_file

# JSON is invalid
if ! echo "$json_content" | jq -e .  > /dev/null 2>&1
then
    set +e
    jq_output=$(jq . "$json_file" 2>&1)
    error_line=$(echo "$jq_output" | grep -oE 'parse error.*at line [0-9]+' | grep -oE '[0-9]+')

    if [[ -n "$error_line" ]]; then
        logerror "❌ Invalid JSON at line $error_line"
    fi
    set -e

    if [[ $(type -f bat 2>&1) =~ "not found" ]]
    then
        cat -n $json_file
    else
        bat $json_file --highlight-line $error_line
    fi

    exit 1
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

# value_type
value_type=json-schema
case "${value_type}" in
avro)
    docker run --rm -v $tmp_dir:/tmp/ vdesabou/avro-tools random /tmp/out.avro --schema-file /tmp/value_schema --count $nb_messages
    docker run --rm -v $tmp_dir:/tmp/ vdesabou/avro-tools tojson /tmp/out.avro > $tmp_dir/out.json

    log "payload is"
    cat $tmp_dir/out.json

    cat $tmp_dir/out.json | docker exec -e SCHEMA_REGISTRY_LOG4J_OPTS="-Dlog4j.configuration=file:/etc/kafka/tools-log4j.properties" -i $container kafka-$value_type-console-producer --broker-list $bootstrap_server --property schema.registry.url=$sr_url_cli --topic $topic $security --property value.schema="$(cat $schema_file)"

;;
avro-with-key)

;;
json-schema)

    docker run --rm -v $tmp_dir:/tmp/ -e NB_MESSAGES=$nb_messages vdesabou/json-schema-faker > $tmp_dir/out.json

    log "payload is"
    cat $tmp_dir/out.json

    cat $tmp_dir/out.json | docker exec -e SCHEMA_REGISTRY_LOG4J_OPTS="-Dlog4j.configuration=file:/etc/kafka/tools-log4j.properties" -i $container kafka-$value_type-console-producer --broker-list $bootstrap_server --property schema.registry.url=$sr_url_cli --topic $topic $security --property value.schema="$(cat $schema_file)"
;;
json-schema-with-key)

;;
protobuf)

;;
protobuf-with-key)

;;
none)
;;
*)
    logerror "producer name not valid ! Should be one of avro, avro-with-key, json-schema, json-schema-with-key, protobuf or protobuf-with-key"
    exit 1
;;
esac