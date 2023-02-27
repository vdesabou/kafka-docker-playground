function get_properties_command_heredoc () {
docker exec -i "$1" sh << EOF
ps -ef | grep properties | grep java | grep -v grep | awk '{ print \$NF }' > /tmp/propertie_file
propertie_file=\$(cat /tmp/propertie_file)
if [ ! -f \$propertie_file ]
then
  logerror 'ERROR: Could not determine properties file!'
  exit 1
fi
cat \$propertie_file | grep -v None | grep . | sort
EOF
}

function get_producer_heredoc () {
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
}

function get_producer_ccloud_heredoc () {
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
}

function get_producer_build_heredoc () {
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
}

function get_producer_fixthis_heredoc () {
    cat << EOF > $tmp_dir/java_producer

# 🚨🚨🚨 FIXTHIS: move it to the correct place 🚨🚨🚨
EOF
}

function get_producer_run_heredoc () {
    cat << EOF >> $tmp_dir/java_producer
log "✨ Run the $schema_format java producer v$i which produces to topic $topic_name"
docker exec $producer_hostname bash -c "java \${JAVA_OPTS} -jar producer-1.0.0-jar-with-dependencies.jar"
EOF
}

function get_producer_run_heredoc () {
    cat << EOF >> $tmp_dir/java_producer
log "✨ Run the $schema_format java producer v$i which produces to topic $topic_name"
docker exec $producer_hostname bash -c "java \${JAVA_OPTS} -jar producer-1.0.0-jar-with-dependencies.jar"
EOF
}

function get_number_records_topic_command_heredoc () {
docker exec -i broker bash << EOF
kafka-run-class kafka.tools.GetOffsetShell --broker-list broker:9092 --topic "$1" --time -1 | awk -F ":" '{sum += \$3} END {print sum}'
EOF
}

function get_remote_debugging_command_heredoc () {
tmp_dir=$(mktemp -d -t ci-XXXXXXXXXX)
cat << EOF > $tmp_dir/docker-compose-remote-debugging.yml
version: '3.5'
services:
  $1:
    environment:
      # https://kafka-docker-playground.io/#/reusables?id=✨-remote-debugging
      KAFKA_DEBUG: 'true'
      # With JDK9+, need to specify address=*:5005, see https://www.baeldung.com/java-application-remote-debugging#from-java9
      JAVA_DEBUG_OPTS: '-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=0.0.0.0:5005'
EOF

sed -e "s|up -d|-f $tmp_dir/docker-compose-remote-debugging.yml up -d|g" \
    /tmp/playground-command > /tmp/playground-command-debugging
}