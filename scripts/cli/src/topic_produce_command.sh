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

if grep -q "proto3" $schema_file
then
    log "schema was detected as protobuf"
    value_type=protobuf
elif grep -q "\$schema" $schema_file
then
    log "schema was detected as json schema"
    value_type=json-schema
elif grep -q "_meta" $schema_file
then
    log "schema was detected as json"
    value_type=json
elif grep -q "\"type\"\s*:\s*\"record\"" $schema_file
then
    log "schema was detected as avro"
    value_type=avro
else
    logerror "Could not detect schema type for $schema_file"
    cat $schema_file
    exit 1
fi

case "${value_type}" in
json)
    # https://github.com/MaterializeInc/datagen
    docker run --rm -i -v $schema_file:/app/schema.json materialize/datagen -s schema.json -n $nb_messages --dry-run | grep "Payload: " | awk '{print $2}' > $tmp_dir/out.json
    #--record-size 104
;;

avro)
    docker run --rm -v $tmp_dir:/tmp/ vdesabou/avro-tools random /tmp/out.avro --schema-file /tmp/value_schema --count $nb_messages
    docker run --rm -v $tmp_dir:/tmp/ vdesabou/avro-tools tojson /tmp/out.avro > $tmp_dir/out.json
;;
avro-with-key)

;;
json-schema)
    docker run --rm -v $tmp_dir:/tmp/ -e NB_MESSAGES=$nb_messages vdesabou/json-schema-faker > $tmp_dir/out.json
;;
json-schema-with-key)

;;
protobuf)
    # https://github.com/JasonkayZK/mock-protobuf.js
    docker run --rm -v $tmp_dir:/tmp/ -v $schema_file:/app/schema.proto -e NB_MESSAGES=$nb_messages vdesabou/protobuf-faker  > $tmp_dir/out.json
;;
protobuf-with-key)

;;
none)
;;
*)
    logerror "value_type name not valid ! Should be one of json, avro, avro-with-key, json-schema, json-schema-with-key, protobuf or protobuf-with-key"
    exit 1
;;
esac

log "payload is"
cat $tmp_dir/out.json

log "Producing data"
case "${value_type}" in
json)
    cat $tmp_dir/out.json | docker exec -i $container kafka-console-producer --broker-list $bootstrap_server --topic $topic $security
;;
*)
    cat $tmp_dir/out.json | docker exec -e SCHEMA_REGISTRY_LOG4J_OPTS="-Dlog4j.configuration=file:/etc/kafka/tools-log4j.properties" -i $container kafka-$value_type-console-producer --broker-list $bootstrap_server --property schema.registry.url=$sr_url_cli --topic $topic $security --property value.schema="$(cat $schema_file)"
;;
esac