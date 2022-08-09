function log() {
  YELLOW='\033[0;33m'
  NC='\033[0m' # No Color
  echo -e "$YELLOW`date +"%H:%M:%S"` ℹ️ $@$NC"
}

function logerror() {
  RED='\033[0;31m'
  NC='\033[0m' # No Color
  echo -e "$RED`date +"%H:%M:%S"` 🔥 $@$NC"
}

function logwarn() {
  PURPLE='\033[0;35m'
  NC='\033[0m' # No Color
  echo -e "$PURPLE`date +"%H:%M:%S"` ❗ $@$NC"
}

function urlencode() {
  # https://gist.github.com/cdown/1163649
  # urlencode <string>

  old_lc_collate=$LC_COLLATE
  LC_COLLATE=C

  local length="${#1}"
  for (( i = 0; i < length; i++ )); do
      local c="${1:$i:1}"
      case $c in
          [a-zA-Z0-9.~_-]) printf '%s' "$c" ;;
          *) printf '%%%02X' "'$c" ;;
      esac
  done

  LC_COLLATE=$old_lc_collate
}

function jq() {
    if [[ $(type -f jq 2>&1) =~ "not found" ]]
    then
      docker run --rm -i imega/jq "$@"
    else
      $(which jq) "$@"
    fi
}

function yq() {
    if [[ $(type -f yq 2>&1) =~ "not found" ]]
    then
      docker run --rm -i mikefarah/yq "$@"
    else
      $(which yq) "$@"
    fi
}

# https://stackoverflow.com/a/24067243
function version_gt() {
  test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1";
}

function set_kafka_client_tag()
{
    if [[ $TAG_BASE = 7.2.* ]]
    then
      export KAFKA_CLIENT_TAG="3.2.0"
    fi

    if [[ $TAG_BASE = 7.1.* ]]
    then
      export KAFKA_CLIENT_TAG="3.1.0"
    fi

    if [[ $TAG_BASE = 7.0.* ]]
    then
      export KAFKA_CLIENT_TAG="3.0.0"
    fi

    if [[ $TAG_BASE = 6.2.* ]]
    then
      export KAFKA_CLIENT_TAG="2.8.0"
    fi

    if [[ $TAG_BASE = 6.1.* ]]
    then
      export KAFKA_CLIENT_TAG="2.7.0"
    fi

    if [[ $TAG_BASE = 6.0.* ]]
    then
      export KAFKA_CLIENT_TAG="2.6.0"
    fi

    if [[ $TAG_BASE = 5.5.* ]]
    then
      export KAFKA_CLIENT_TAG="2.5.0"
    fi

    if [[ $TAG_BASE = 5.4.* ]]
    then
      export KAFKA_CLIENT_TAG="2.4.0"
    fi

    if [[ $TAG_BASE = 5.3.* ]]
    then
      export KAFKA_CLIENT_TAG="2.3.0"
    fi

    if [[ $TAG_BASE = 5.2.* ]]
    then
      export KAFKA_CLIENT_TAG="2.2.0"
    fi

    if [[ $TAG_BASE = 5.1.* ]]
    then
      export KAFKA_CLIENT_TAG="2.1.0"
    fi

    if [[ $TAG_BASE = 5.0.* ]]
    then
      export KAFKA_CLIENT_TAG="2.0.0"
    fi
}

function displaytime {
  local T=$1
  local D=$((T/60/60/24))
  local H=$((T/60/60%24))
  local M=$((T/60%60))
  local S=$((T%60))
  (( $D > 0 )) && printf '%d days ' $D
  (( $H > 0 )) && printf '%d hours ' $H
  (( $M > 0 )) && printf '%d minutes ' $M
  (( $D > 0 || $H > 0 || $M > 0 )) && printf 'and '
  printf '%d seconds\n' $S
}

function choosejar()
{
  log "Select the jar to replace:"
  select jar
  do
    # Check the selected menu jar number
    if [ 1 -le "$REPLY" ] && [ "$REPLY" -le $# ];
    then
      break;
    else
      logwarn "Wrong selection: select any number from 1-$#"
    fi
  done
}

# Setting up TAG environment variable
#
if [ -z "$TAG" ]
then
    # TAG is not set, use default:
    export TAG=7.2.1
    # to handle ubi8 images
    export TAG_BASE=$TAG
    if [ -z "$CP_KAFKA_IMAGE" ]
    then
      if [ -z "$IGNORE_CHECK_FOR_DOCKER_COMPOSE" ]
      then
        log "💫 Using default CP version $TAG"
        log "🎓 set TAG environment variable to specify different version, see https://kafka-docker-playground.io/#/how-to-use?id=🎯-for-confluent-platform-cp"
      fi
    fi
    export CP_KAFKA_IMAGE=confluentinc/cp-server
    export CP_BASE_IMAGE=confluentinc/cp-base-new
    export CP_KSQL_IMAGE=confluentinc/cp-ksqldb-server
    export CP_KSQL_CLI_IMAGE=confluentinc/cp-ksqldb-cli:latest
    export LEGACY_CONNECT_VALUE_CONVERTER_SCHEMA_REGISTRY_SSL=""
    set_kafka_client_tag
else
    if [ -z "$CP_KAFKA_IMAGE" ]
    then
      if [ -z "$IGNORE_CHECK_FOR_DOCKER_COMPOSE" ]
      then
        log "🚀 Using specified CP version $TAG"
      fi
    fi
    # to handle ubi8 images
    export TAG_BASE=$(echo $TAG | cut -d "-" -f1)
    first_version=${TAG_BASE}
    second_version=5.2.99
    if version_gt $first_version $second_version; then
        if [ "$first_version" = "5.3.6" ]
        then
          logwarn "Workaround for 5.3.6 image broker, using custom image vdesabou/cp-server !"
          export CP_KAFKA_IMAGE=vdesabou/cp-server
        else
          export CP_KAFKA_IMAGE=confluentinc/cp-server
        fi
    else
        export CP_KAFKA_IMAGE=confluentinc/cp-enterprise-kafka
    fi
    second_version=5.3.99
    if version_gt $first_version $second_version; then
        export CP_BASE_IMAGE=confluentinc/cp-base-new
    else
        export CP_BASE_IMAGE=confluentinc/cp-base
    fi
    second_version=5.4.99
    if version_gt $first_version $second_version; then
        export CP_KSQL_IMAGE=confluentinc/cp-ksqldb-server
        export CP_KSQL_CLI_IMAGE=confluentinc/cp-ksqldb-cli:${TAG_BASE}
    else
        export CP_KSQL_IMAGE=confluentinc/cp-ksql-server
        export CP_KSQL_CLI_IMAGE=confluentinc/cp-ksql-cli:${TAG_BASE}
    fi
    second_version=5.3.99
    if version_gt $first_version $second_version; then
        export LEGACY_CONNECT_VALUE_CONVERTER_SCHEMA_REGISTRY_SSL=""
    else
        if [ -z "$LEGACY_CONNECT_VALUE_CONVERTER_SCHEMA_REGISTRY_SSL" ]
        then
          log "👴 Legacy config for client connecting to HTTPS SR is set, see https://docs.confluent.io/platform/current/schema-registry/security/index.html#additional-configurations-for-https"
          export LEGACY_CONNECT_VALUE_CONVERTER_SCHEMA_REGISTRY_SSL="-Djavax.net.ssl.trustStore=/etc/kafka/secrets/kafka.connect.truststore.jks -Djavax.net.ssl.trustStorePassword=confluent -Djavax.net.ssl.keyStore=/etc/kafka/secrets/kafka.connect.keystore.jks -Djavax.net.ssl.keyStorePassword=confluent"
        fi
    fi
    set_kafka_client_tag
fi

# Setting grafana agent based  
if [ -z "$ENABLE_JMX_GRAFANA" ]
then
  # defaulting to empty variable since this is default in kafka-run-class.sh & avoid warning
  export GRAFANA_AGENT_ZK=""
  export GRAFANA_AGENT_BROKER=""
  export GRAFANA_AGENT_CONNECT=""
  export GRAFANA_AGENT_PRODUCER=""
  export GRAFANA_AGENT_CONSUMER=""
else
  export GRAFANA_AGENT_ZK="-javaagent:/usr/share/jmx_exporter/jmx_prometheus_javaagent-0.16.1.jar=1234:/usr/share/jmx_exporter/zookeeper.yml"
  export GRAFANA_AGENT_BROKER="-javaagent:/usr/share/jmx_exporter/jmx_prometheus_javaagent-0.16.1.jar=1234:/usr/share/jmx_exporter/broker.yml"
  export GRAFANA_AGENT_CONNECT="-javaagent:/usr/share/jmx_exporter/jmx_prometheus_javaagent-0.16.1.jar=1234:/usr/share/jmx_exporter/connect.yml"
  export GRAFANA_AGENT_PRODUCER="-javaagent:/usr/share/jmx_exporter/jmx_prometheus_javaagent-0.16.1.jar=1234:/usr/share/jmx_exporter/kafka-producer.yml"
  export GRAFANA_AGENT_CONSUMER="-javaagent:/usr/share/jmx_exporter/jmx_prometheus_javaagent-0.16.1.jar=1234:/usr/share/jmx_exporter/kafka-consumer.yml"
fi

# Migrate SimpleAclAuthorizer to AclAuthorizer #1276
if version_gt $TAG "5.3.99"
then
  export KAFKA_AUTHORIZER_CLASS_NAME="kafka.security.authorizer.AclAuthorizer"
else
  export KAFKA_AUTHORIZER_CLASS_NAME="kafka.security.auth.SimpleAclAuthorizer"
fi

function verify_installed()
{
  local cmd="$1"
  if [[ $(type $cmd 2>&1) =~ "not found" ]]; then
    echo -e "\nERROR: This script requires '$cmd'. Please install '$cmd' and run again.\n"
    exit 1
  fi
}

if [ ! -z "$CONNECTOR_TAG" ] && [ ! -z "$CONNECTOR_ZIP" ]
then
  logerror "CONNECTOR_TAG and CONNECTOR_ZIP are both set, they cannot be used at same time!"
  exit 1
fi

###
#  CONNECTOR_TAG is set
###
if [ ! -z "$CONNECTOR_TAG" ]
then
  if [[ $0 == *"wait-for-connect-and-controlcenter.sh"* ]]
  then
    if [ -z "$CONNECT_TAG" ]
    then
      export CONNECT_TAG="$TAG"
    fi
    :
  elif [[ $0 == *"environment"* ]]
  then
    # log "DEBUG: start.sh from environment folder. Skipping..."
    if [ -z "$CONNECT_TAG" ]
    then
      export CONNECT_TAG="$TAG"
    fi
    :
  elif [[ $0 == *"stop"* ]]
  then
    if [ -z "$CONNECT_TAG" ]
    then
      export CONNECT_TAG="$TAG"
    fi
    :
  elif [[ $0 == *"run-tests"* ]]
  then
    :
  else
    if [ -z "$IGNORE_CHECK_FOR_DOCKER_COMPOSE" ]
    then
      log "🎯 CONNECTOR_TAG is set with version $CONNECTOR_TAG"
    fi
    # determining the connector from current path
    docker_compose_file=""
    if [ -f "$PWD/$0" ]
    then
      docker_compose_file=$(grep "environment" "$PWD/$0" | grep DIR | grep start.sh | cut -d "/" -f 7 | cut -d '"' -f 1 | head -n1)
    fi
    if [ "${docker_compose_file}" != "" ] && [ -f "${docker_compose_file}" ]
    then
      connector_paths=$(grep "CONNECT_PLUGIN_PATH" "${docker_compose_file}" | grep -v "KSQL_CONNECT_PLUGIN_PATH" | cut -d ":" -f 2  | tr -s " " | head -1)
      if [ "$connector_paths" == "" ]
      then
        # not a connector test
        if [ -z "$CONNECT_TAG" ]
        then
          export CONNECT_TAG="$TAG"
        fi
      else
        ###
        #  Loop on all connectors in CONNECT_PLUGIN_PATH and install latest version from Confluent Hub (except for JDBC and replicator)
        ###
        first_loop=true
        i=0
        my_array_connector_tag=($(echo $CONNECTOR_TAG | tr "," "\n"))
        for connector_path in ${connector_paths//,/ }
        do
          connector_path=$(echo "$connector_path" | cut -d "/" -f 5)
          owner=$(echo "$connector_path" | cut -d "-" -f 1)
          name=$(echo "$connector_path" | cut -d "-" -f 2-)

          CONNECTOR_VERSION="${my_array_connector_tag[$i]}"
          if [ "$CONNECTOR_VERSION" = "" ]
          then
            logwarn "CONNECTOR_TAG was not set for element $i, setting it to latest"
            CONNECTOR_VERSION="latest"
          fi
          if [ "$first_loop" = true ]
          then
            export CONNECT_TAG="$TAG"
          else
            export CONNECT_TAG="cp-$TAG-$(echo $CONNECTOR_TAG | tr "," "-")"
          fi

          tmp_dir=$(mktemp -d -t ci-XXXXXXXXXX)
cat << EOF > $tmp_dir/Dockerfile
FROM vdesabou/kafka-docker-playground-connect:${CONNECT_TAG}
RUN confluent-hub install --no-prompt $owner/$name:$CONNECTOR_VERSION
EOF
          export CONNECT_TAG="cp-$TAG-$(echo $CONNECTOR_TAG | tr "," "-")"
          log "👷 Building Docker image vdesabou/kafka-docker-playground-connect:${CONNECT_TAG}"
          docker build -t vdesabou/kafka-docker-playground-connect:$CONNECT_TAG $tmp_dir
          rm -rf $tmp_dir

          if [ "$first_loop" = true ]
          then
            first_loop=false
            ###
            #  CONNECTOR_JAR is set (and also CONNECTOR_TAG)
            ###
            if [ ! -z "$CONNECTOR_JAR" ]
            then
              if [ ! -f "$CONNECTOR_JAR" ]
              then
                logerror "CONNECTOR_JAR $CONNECTOR_JAR does not exist!"
                exit 1
              fi
              if [ -z "$IGNORE_CHECK_FOR_DOCKER_COMPOSE" ]
              then
                log "🎯 CONNECTOR_JAR is set with $CONNECTOR_JAR"
              fi
              connector_jar_name=$(basename ${CONNECTOR_JAR})
              current_jar_path="/usr/share/confluent-hub-components/$connector_path/lib/$name-$CONNECTOR_TAG.jar"
              set +e
              docker run vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} ls $current_jar_path
              if [ $? -ne 0 ]
              then
                logwarn "$connector_path/lib/$name-$CONNECTOR_TAG.jar does not exist, the jar name to replace could not be found automatically"
                array=($(docker run --rm vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} ls /usr/share/confluent-hub-components/$connector_path/lib | grep $CONNECTOR_TAG))
                choosejar "${array[@]}"
                current_jar_path="/usr/share/confluent-hub-components/$connector_path/lib/$jar"
              fi
              set -e
              NEW_CONNECT_TAG="$name-cp-$TAG-$CONNECTOR_TAG-$connector_jar_name"
              log "👷 Building Docker image vdesabou/kafka-docker-playground-connect:${NEW_CONNECT_TAG}"
              log "🔄 Remplacing $name-$CONNECTOR_TAG.jar by $connector_jar_name"
              tmp_dir=$(mktemp -d -t ci-XXXXXXXXXX)
              cp $CONNECTOR_JAR $tmp_dir/
cat << EOF > $tmp_dir/Dockerfile
FROM vdesabou/kafka-docker-playground-connect:${CONNECT_TAG}
COPY $connector_jar_name $current_jar_path
EOF
              docker build -t vdesabou/kafka-docker-playground-connect:$NEW_CONNECT_TAG $tmp_dir
              export CONNECT_TAG="$NEW_CONNECT_TAG"
              rm -rf $tmp_dir
            fi
          fi
          ((i=i+1))
        done
      fi
    else
      if [ -z "$IGNORE_CHECK_FOR_DOCKER_COMPOSE" ] && [ "$0" != "/tmp/playground-command" ] && [ "$0" != "/tmp/playground-command-debugging" ]
      then
        logerror "📁 Could not determine docker-compose override file from $PWD/$0 !"
        logerror "👉 Please check you're running a connector example !"
        logerror "🎓 Check the related documentation https://kafka-docker-playground.io/#/how-it-works?id=🐳-docker-override"
        exit 1
      else
        if [ -z "$CONNECT_TAG" ]
        then
          export CONNECT_TAG="$TAG"
        fi
      fi
    fi
  fi
else
  ###
  #  CONNECTOR_TAG is not set
  ###
  if [[ $0 == *"wait-for-connect-and-controlcenter.sh"* ]]
  then
    if [ -z "$CONNECT_TAG" ]
    then
      export CONNECT_TAG="$TAG"
    fi
    :
  elif [[ $0 == *"environment"* ]]
  then
    if [ -z "$CONNECT_TAG" ]
    then
      export CONNECT_TAG="$TAG"
    fi
    :
  elif [[ $0 == *"stop"* ]]
  then
    if [ -z "$CONNECT_TAG" ]
    then
      export CONNECT_TAG="$TAG"
    fi
    CONNECTOR_TAG=$version
    :
  elif [[ $0 == *"run-tests"* ]]
  then
    :
  else
    docker_compose_file=""
    if [ -f "$PWD/$0" ]
    then
      docker_compose_file=$(grep "environment" "$PWD/$0" | grep DIR | grep start.sh | cut -d "/" -f 7 | cut -d '"' -f 1 | head -n1)
    fi
    if [ "${docker_compose_file}" != "" ] && [ -f "${docker_compose_file}" ]
    then
      connector_paths=$(grep "CONNECT_PLUGIN_PATH" "${docker_compose_file}" | grep -v "KSQL_CONNECT_PLUGIN_PATH" | cut -d ":" -f 2  | tr -s " " | head -1)
      if [ "$connector_paths" == "" ]
      then
        # not a connector test
        if [ -z "$CONNECT_TAG" ]
        then
          export CONNECT_TAG="$TAG"
        fi
      else
        ###
        #  Loop on all connectors in CONNECT_PLUGIN_PATH and install latest version from Confluent Hub (except for JDBC and replicator)
        ###
        first_loop=true
        for connector_path in ${connector_paths//,/ }
        do
          connector_path=$(echo "$connector_path" | cut -d "/" -f 5)
          owner=$(echo "$connector_path" | cut -d "-" -f 1)
          name=$(echo "$connector_path" | cut -d "-" -f 2-)

          if [ "$name" == "" ]
          then
            # can happen for filestream
            if [ -z "$CONNECT_TAG" ]
            then
              export CONNECT_TAG="$TAG"
            fi
          else
            if [ -z "$CONNECT_TAG" ]
            then
              export CONNECT_TAG="$TAG"
            fi

            version_to_get_from_hub="latest"
            if [ "$name" = "kafka-connect-replicator" ]
            then
              if [ -z "$REPLICATOR_TAG" ]
              then
                version_to_get_from_hub="$TAG"
              else
                version_to_get_from_hub="$REPLICATOR_TAG"
                log "🌍 REPLICATOR_TAG is set with $REPLICATOR_TAG"
              fi
            fi
            if [ "$name" = "kafka-connect-jdbc" ]
            then
              if ! version_gt $TAG_BASE "5.9.0"; then
                # for version less than 6.0.0, use JDBC with same version
                # see https://github.com/vdesabou/kafka-docker-playground/issues/221
                version_to_get_from_hub="$TAG_BASE"
              fi

              if [ "$TAG_BASE" = "5.0.2" ] || [ "$TAG_BASE" = "5.0.3" ]
              then
                version_to_get_from_hub="5.0.1"
              fi
            fi

            log "👷🛠 Re-building Docker image vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} to include $owner/$name:$version_to_get_from_hub"
            tmp_dir=$(mktemp -d -t ci-XXXXXXXXXX)
cat << EOF > $tmp_dir/Dockerfile
FROM vdesabou/kafka-docker-playground-connect:${CONNECT_TAG}
RUN confluent-hub install --no-prompt $owner/$name:$version_to_get_from_hub
EOF
            docker build -t vdesabou/kafka-docker-playground-connect:$CONNECT_TAG $tmp_dir
            rm -rf $tmp_dir

            docker run --rm vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} cat /usr/share/confluent-hub-components/${connector_path}/manifest.json > /tmp/manifest.json
            version=$(cat /tmp/manifest.json | jq -r '.version')
            release_date=$(cat /tmp/manifest.json | jq -r '.release_date')
            documentation_url=$(cat /tmp/manifest.json | jq -r '.documentation_url')

            ###
            #  CONNECTOR_JAR is set
            ###
            if [ ! -z "$CONNECTOR_JAR" ] && [ "$first_loop" = true ]
            then
              if [ ! -f "$CONNECTOR_JAR" ]
              then
                logerror "CONNECTOR_JAR $CONNECTOR_JAR does not exist!"
                exit 1
              fi
              log "🎯 CONNECTOR_JAR is set with $CONNECTOR_JAR"
              connector_jar_name=$(basename ${CONNECTOR_JAR})
              export CONNECT_TAG="CP-$CONNECT_TAG-$connector_jar_name"
              current_jar_path="/usr/share/confluent-hub-components/$connector_path/lib/$name-$version.jar"
              set +e
              docker run vdesabou/kafka-docker-playground-connect:${TAG} ls $current_jar_path
              if [ $? -ne 0 ]
              then
                logwarn "$connector_path/lib/$name-$version.jar does not exist, the jar name to replace could not be found automatically"
                array=($(docker run vdesabou/kafka-docker-playground-connect:${TAG} ls /usr/share/confluent-hub-components/$connector_path/lib | grep $version))
                choosejar "${array[@]}"
                current_jar_path="/usr/share/confluent-hub-components/$connector_path/lib/$jar"
              fi
              set -e
              log "👷🎯 Building Docker image vdesabou/kafka-docker-playground-connect:${CONNECT_TAG}"
              log "Remplacing $name-$version.jar by $connector_jar_name"
              tmp_dir=$(mktemp -d -t ci-XXXXXXXXXX)
              cp $CONNECTOR_JAR $tmp_dir/
cat << EOF > $tmp_dir/Dockerfile
FROM vdesabou/kafka-docker-playground-connect:${TAG}
COPY $connector_jar_name $current_jar_path
EOF
              docker build -t vdesabou/kafka-docker-playground-connect:$CONNECT_TAG $tmp_dir
              rm -rf $tmp_dir
            ###
            #  CONNECTOR_ZIP is set
            ###
            elif [ ! -z "$CONNECTOR_ZIP" ] && [ "$first_loop" = true ]
            then
              if [ ! -f "$CONNECTOR_ZIP" ]
              then
                logerror "CONNECTOR_ZIP $CONNECTOR_ZIP does not exist!"
                exit 1
              fi
              log "🎯 CONNECTOR_ZIP is set with $CONNECTOR_ZIP"
              connector_zip_name=$(basename ${CONNECTOR_ZIP})
              export CONNECT_TAG="CP-$TAG-$connector_zip_name"

              log "👷 Building Docker image vdesabou/kafka-docker-playground-connect:${CONNECT_TAG}"
              tmp_dir=$(mktemp -d -t ci-XXXXXXXXXX)
              cp $CONNECTOR_ZIP $tmp_dir/
              if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
              then
                  export CONNECT_CONTAINER_USER="appuser"
              else
                  export CONNECT_CONTAINER_USER="root"
              fi
cat << EOF > $tmp_dir/Dockerfile
FROM vdesabou/kafka-docker-playground-connect:${TAG}
COPY --chown=$CONNECT_CONTAINER_USER:$CONNECT_CONTAINER_USER ${connector_zip_name} /tmp
RUN confluent-hub install --no-prompt /tmp/${connector_zip_name}
EOF
              docker build -t vdesabou/kafka-docker-playground-connect:$CONNECT_TAG $tmp_dir
              rm -rf $tmp_dir
            ###
            #  Neither CONNECTOR_ZIP or CONNECTOR_JAR are set
            ###
            else
              if [ -z "$CONNECT_TAG" ]
              then
                export CONNECT_TAG="$TAG"
              fi
              if [ "$first_loop" = true ]
              then
                log "💫 Using 🔗connector: $owner/$name:$version 📅release date: $release_date 🌐documentation: $documentation_url"
                log "🎓 To specify different version, check the documentation https://kafka-docker-playground.io/#/how-to-use?id=🔗-for-connectors"
                CONNECTOR_TAG=$version  
              fi
            fi
            first_loop=false
          fi
        done
      fi
    fi
  fi
  if [ -z "$CONNECT_TAG" ]
  then
    export CONNECT_TAG="$TAG"
  fi
fi

function verify_docker_and_memory()
{
  set +e
  docker info > /dev/null 2>&1
  if [[ $? -ne 0 ]]
  then
    logerror "Cannot connect to the Docker daemon. Is the docker daemon running?"
    exit 1
  fi
  set -e
  # Check only with Mac OS
  if [[ "$OSTYPE" == "darwin"* ]]
  then
    # Verify Docker memory is increased to at least 8GB
    DOCKER_MEMORY=$(docker system info | grep Memory | grep -o "[0-9\.]\+")
    if (( $(echo "$DOCKER_MEMORY 7.0" | awk '{print ($1 < $2)}') )); then
        logerror "WARNING: Did you remember to increase the memory available to Docker to at least 8GB (default is 2GB)? Demo may otherwise not work properly"
        exit 1
    fi
  fi
  return 0
}


function verify_confluent_login()
{
  local cmd="$1"
  set +e
  output=$($cmd 2>&1)
  set -e
  if [ "${output}" = "Error: You must login to run that command." ] || [ "${output}" = "Error: Your session has expired. Please login again." ]; then
    logerror "This script requires confluent CLI to be logged in. Please execute 'confluent login' and run again."
    exit 1
  fi
}

function verify_confluent_details()
{
    if [ "$(confluent prompt -f "%E")" = "(none)" ]
    then
        logerror "confluent command is badly configured: environment is not set"
        logerror "Example: confluent kafka environment list"
        logerror "then: confluent kafka environment use <environment id>"
        exit 1
    fi

    if [ "$(confluent prompt -f "%K")" = "(none)" ]
    then
        logerror "confluent command is badly configured: cluster is not set"
        logerror "Example: confluent kafka cluster list"
        logerror "then: confluent kafka cluster use <cluster id>"
        exit 1
    fi

    if [ "$(confluent prompt -f "%a")" = "(none)" ]
    then
        logerror "confluent command is badly configured: api key is not set"
        logerror "Example: confluent api-key store <api key> <password>"
        logerror "then: confluent api-key use <api key>"
        exit 1
    fi

    CCLOUD_PROMPT_FMT='You will be using Confluent Cloud cluster with user={{fgcolor "green" "%u"}}, environment={{fgcolor "red" "%E"}}, cluster={{fgcolor "cyan" "%K"}}, api key={{fgcolor "yellow" "%a"}}'
    confluent prompt -f "$CCLOUD_PROMPT_FMT"
}

function check_if_continue()
{
    if [ ! -z "$CI" ] || [ ! -z "$CLOUDFORMATION" ]
    then
        # running with github actions or cloudformation, continue
        return
    fi
    read -p "Continue (y/n)?" choice
    case "$choice" in
    y|Y ) ;;
    n|N ) exit 0;;
    * ) logerror "invalid response!";exit 1;;
    esac
}

function create_topic()
{
  local topic="$1"
  log "Check if topic $topic exists"
  confluent kafka topic create "$topic" --dry-run 2>/dev/null
  if [[ $? == 0 ]]; then
    log "Create topic $topic"
    log "confluent kafka topic create $topic --partitions 1"
    confluent kafka topic create "$topic" --partitions 1 || true
  else
    log "Topic $topic already exists"
  fi
}

function delete_topic()
{
  local topic="$1"
  log "Check if topic $topic exists"
  confluent kafka topic create "$topic" --dry-run 2>/dev/null
  if [[ $? != 0 ]]; then
    log "Delete topic $topic"
    log "confluent kafka topic delete $topic"
    confluent kafka topic delete "$topic" || true
  else
    log "Topic $topic does not exist"
  fi
}

function version_gt() {
  test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1";
}

function get_docker_compose_version() {
  docker-compose version | grep "^docker-compose version" | cut -d' ' -f3 | cut -d',' -f1
}

function check_docker_compose_version() {
  REQUIRED_DOCKER_COMPOSE_VER=${1:-"1.28.0"}
  DOCKER_COMPOSE_VER=$(get_docker_compose_version)

  if version_gt $REQUIRED_DOCKER_COMPOSE_VER $DOCKER_COMPOSE_VER; then
    log "docker-compose version ${REQUIRED_DOCKER_COMPOSE_VER} or greater is required.  Current reported version: ${DOCKER_COMPOSE_VER}"
    exit 1
  fi
}

function get_confluent_version() {
  confluent version | grep "^Version:" | cut -d':' -f2 | cut -d'v' -f2
}

function get_ansible_version() {
  ansible --version | grep "core" | cut -d'[' -f2 | cut -d']' -f1 | cut -d' ' -f 2
}

function check_confluent_version() {
  REQUIRED_CONFLUENT_VER=${1:-"2.0.0"}
  CONFLUENT_VER=$(get_confluent_version)

  if version_gt $REQUIRED_CONFLUENT_VER $CONFLUENT_VER; then
    log "confluent version ${REQUIRED_CONFLUENT_VER} or greater is required.  Current reported version: ${CONFLUENT_VER}"
    echo 'To update run: confluent update'
    exit 1
  fi
}

function container_to_ip() {
    name=$1
    echo $(docker exec $name hostname -I)
}

function block_host() {
    name=$1
    shift 1

    # https://serverfault.com/a/906499
    docker exec --privileged -t $name bash -c "tc qdisc add dev eth0 root handle 1: prio" 2>&1

    for ip in $@; do
        docker exec --privileged -t $name bash -c "tc filter add dev eth0 protocol ip parent 1: prio 1 u32 match ip dst $ip flowid 1:1" 2>&1
    done

    docker exec --privileged -t $name bash -c "tc filter add dev eth0 protocol all parent 1: prio 2 u32 match ip dst 0.0.0.0/0 flowid 1:2" 2>&1
    docker exec --privileged -t $name bash -c "tc filter add dev eth0 protocol all parent 1: prio 2 u32 match ip protocol 1 0xff flowid 1:2" 2>&1
    docker exec --privileged -t $name bash -c "tc qdisc add dev eth0 parent 1:1 handle 10: netem loss 100%" 2>&1
    docker exec --privileged -t $name bash -c "tc qdisc add dev eth0 parent 1:2 handle 20: sfq" 2>&1
}

function remove_partition() {
    for name in $@; do
        docker exec --privileged -t $name bash -c "tc qdisc del dev eth0 root"
    done
}

function aws() {

    if [ -z "$AWS_ACCESS_KEY_ID" ] && [ -z "$AWS_SECRET_ACCESS_KEY" ] && [ ! -f $HOME/.aws/config ] && [ ! -f $HOME/.aws/credentials ]
    then
      logerror 'ERROR: Neither AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY or $HOME/.aws/credentials are set. AWS credentials must be set !'
      if [ -z "$AWS_ACCESS_KEY_ID" ]
      then
        log 'AWS_ACCESS_KEY_ID environment variable is not set.'
      fi
      if [ -z "$AWS_SECRET_ACCESS_KEY" ]
      then
        log 'AWS_SECRET_ACCESS_KEY environment variable is not set.'
      fi
      if [ ! -f $HOME/.aws/credentials ]
      then
        log '$HOME/.aws/credentials does not exist.'
      fi
      return 1
    fi

    if [ ! -f $HOME/.aws/config ]
    then
          tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
cat << EOF > $tmp_dir/config
[default]
region = $AWS_REGION
EOF
    fi

    if [ ! -f $HOME/.aws/credentials ]
    then
      #log "Using aws cli with environment variables AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY"
      docker run --rm -iv $tmp_dir/config:/root/.aws/config -e AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY -v $(pwd):/aws -v /tmp:/tmp mikesir87/aws-cli:v2 aws "$@"
      rm -rf $tmp_dir
    else
      #log "Using aws cli with credentials file"
      docker run --rm -iv $HOME/.aws:/root/.aws -v $(pwd):/aws -v /tmp:/tmp mikesir87/aws-cli:v2 aws "$@"
    fi
}

function timeout() {
  if [[ $(type -f timeout 2>&1) =~ "not found" ]]; then
    # ignore
    shift
    eval "$@"
  else
    $(which timeout) "$@"
  fi
}

function az() {
    docker run -v /tmp:/tmp -v $HOME/.azure:/home/az/.azure -e HOME=/home/az --rm -i mcr.microsoft.com/azure-cli az "$@"
}

function display_docker_container_error_log() {
  logerror "####################################################"
  logerror "🐳 docker ps"
  docker ps
  logerror "####################################################"
  for container in $(docker ps  --format="{{.Names}}")
  do
      logerror "####################################################"
      logerror "$container logs"
      if [[ "$container" == "connect" ]]
      then
          # always show all logs for connect
          docker container logs --tail=100 $container | grep -v "was supplied but isn't a known config"
      else
          docker container logs $container | egrep "ERROR|FATAL"
      fi
      logwarn "####################################################"
  done
}

function retry() {
  local n=1
  local max_retriable=4
  local max_default_retry=2
  while true; do
    "$@"
    ret=$?
    if [ $ret -eq 0 ]
    then
      return 0
    elif [ $ret -eq 111 ] # skipped
    then
      return 111
    elif [ $ret -eq 107 ] # known issue https://github.com/vdesabou/kafka-docker-playground/issues/907
    then
      return 107
    else
      script=$(echo "$@" | cut -d " " -f 2)
      # check for retriable scripts in scripts/tests-retriable.txt
      grep "$script" ${DIR}/tests-retriable.txt > /dev/null
      if [ $? = 0 ]
      then
        if [[ $n -lt $max_retriable ]]; then
          ((n++))
          logwarn "####################################################"
          logwarn "🧟‍♂️ The test $script (retriable) has failed. Retrying (attempt $n/$max)"
          logwarn "####################################################"
          display_docker_container_error_log
        else
          logerror "💀 The test $script (retriable) has failed after $n attempts."
          return 1
        fi
      else
        if [[ $n -lt $max_default_retry ]]; then
          ((n++))
          logwarn "####################################################"
          logwarn "🎰 The test $script (default_retry) has failed. Retrying (attempt $n/$max_default_retry)"
          logwarn "####################################################"
          display_docker_container_error_log
        else
          logerror "💀 The test $script (default_retry) has failed after $n attempts."
          return 1
        fi
      fi
    fi
  done
}

retrycmd() {
    local -r -i max_attempts="$1"; shift
    local -r -i sleep_interval="$1"; shift
    local -r cmd="$@"
    local -i attempt_num=1

    until $cmd
    do
        if (( attempt_num == max_attempts ))
        then
            display_docker_container_error_log
            logerror "Failed after $attempt_num attempts. Please troubleshoot and run again."
            return 1
        else
            printf "."
            ((attempt_num++))
            sleep $sleep_interval
        fi
    done
    printf "\n"
}

# for RBAC, taken from cp-demo
function host_check_kafka_cluster_registered() {
  KAFKA_CLUSTER_ID=$(docker container exec zookeeper zookeeper-shell zookeeper:2181 get /cluster/id 2> /dev/null | grep \"version\" | jq -r .id)
  if [ -z "$KAFKA_CLUSTER_ID" ]; then
    return 1
  fi
  echo $KAFKA_CLUSTER_ID
  return 0
}

# for RBAC, taken from cp-demo
function host_check_mds_up() {
  docker container logs broker > /tmp/out.txt 2>&1
  FOUND=$(cat /tmp/out.txt | grep "Started NetworkTrafficServerConnector")
  if [ -z "$FOUND" ]; then
    return 1
  fi
  return 0
}

# for RBAC, taken from cp-demo
function mds_login() {
  MDS_URL=$1
  SUPER_USER=$2
  SUPER_USER_PASSWORD=$3

  # Log into MDS
  if [[ $(type expect 2>&1) =~ "not found" ]]; then
    echo "'expect' is not found. Install 'expect' and try again"
    exit 1
  fi
  echo -e "\n# Login"
  OUTPUT=$(
  expect <<END
    log_user 1
    spawn confluent login --url $MDS_URL
    expect "Username: "
    send "${SUPER_USER}\r";
    expect "Password: "
    send "${SUPER_USER_PASSWORD}\r";
    expect "Logged in as "
    set result $expect_out(buffer)
END
  )
  echo "$OUTPUT"
  if [[ ! "$OUTPUT" =~ "Logged in as" ]]; then
    echo "Failed to log into MDS.  Please check all parameters and run again"
    exit 1
  fi
}

# https://raw.githubusercontent.com/zlabjp/kubernetes-scripts/master/wait-until-pods-ready

function __is_pod_ready() {
  [[ "$(kubectl get po "$1" -n $namespace -o 'jsonpath={.status.conditions[?(@.type=="Ready")].status}')" == 'True' ]]
}

function __pods_ready() {
  local pod

  [[ "$#" == 0 ]] && return 0

  for pod in $pods; do
    __is_pod_ready "$pod" || return 1
  done

  return 0
}

function wait-until-pods-ready() {
  local period interval i pods

  if [[ $# != 3 ]]; then
    echo "Usage: wait-until-pods-ready PERIOD INTERVAL NAMESPACE" >&2
    echo "" >&2
    echo "This script waits for all pods to be ready in the current namespace." >&2

    return 1
  fi

  period="$1"
  interval="$2"
  namespace="$3"

  sleep 10

  for ((i=0; i<$period; i+=$interval)); do
    pods="$(kubectl get po -n $namespace -o 'jsonpath={.items[*].metadata.name}')"
    if __pods_ready $pods; then
      return 0
    fi

    echo "Waiting for pods to be ready..."
    sleep "$interval"
  done

  echo "Waited for $period seconds, but all pods are not ready yet."
  return 1
}

function wait_for_datagen_connector_to_inject_data () {
  sleep 3
  connector_name="$1"
  datagen_tasks="$2"
  prefix_cmd="$3"
  set +e
  # wait for all tasks to be FAILED with org.apache.kafka.connect.errors.ConnectException: Stopping connector: generated the configured xxx number of messages
  MAX_WAIT=3600
  CUR_WAIT=0
  log "⌛ Waiting up to $MAX_WAIT seconds for connector $connector_name to finish injecting requested load"
  $prefix_cmd curl -s -X GET http://localhost:8083/connectors/datagen-${connector_name}/status | jq .tasks[].trace | grep "generated the configured" | wc -l > /tmp/out.txt 2>&1
  while [[ ! $(cat /tmp/out.txt) =~ "${datagen_tasks}" ]]; do
    sleep 5
    $prefix_cmd curl -s -X GET http://localhost:8083/connectors/datagen-${connector_name}/status | jq .tasks[].trace | grep "generated the configured" | wc -l > /tmp/out.txt 2>&1
    CUR_WAIT=$(( CUR_WAIT+10 ))
    if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
      echo -e "\nERROR: Please troubleshoot'.\n"
      $prefix_cmd curl -s -X GET http://localhost:8083/connectors/datagen-${connector_name}/status | jq
      exit 1
    fi
  done
  log "Connector $connector_name has finish injecting requested load"
  set -e
}

# https://gist.github.com/Fuxy22/da4b7ca3bcb0bfea2c582964eafeb4ed
# remove specified host from /etc/hosts
function removehost() {
    if [ ! -z "$1" ]
    then
        HOSTNAME=$1

        if [ -n "$(grep $HOSTNAME /etc/hosts)" ]
        then
            echo "$HOSTNAME Found in your /etc/hosts, Removing now...";
            sudo sed -i".bak" "/$HOSTNAME/d" /etc/hosts
        else
            echo "$HOSTNAME was not found in your /etc/hosts";
        fi
    else
        echo "Error: missing required parameters."
        echo "Usage: "
        echo "  removehost domain"
    fi
}

# https://gist.github.com/Fuxy22/da4b7ca3bcb0bfea2c582964eafeb4ed
#add new ip host pair to /etc/hosts
function addhost() {
    if [ $# -eq 2 ]
    then
        IP=$1
        HOSTNAME=$2

        if [ -n "$(grep $HOSTNAME /etc/hosts)" ]
            then
                echo "$HOSTNAME already exists:";
                echo $(grep $HOSTNAME /etc/hosts);
            else
                echo "Adding $HOSTNAME to your /etc/hosts";
                printf "%s\t%s\n" "$IP" "$HOSTNAME" | sudo tee -a /etc/hosts > /dev/null;

                if [ -n "$(grep $HOSTNAME /etc/hosts)" ]
                    then
                        echo "$HOSTNAME was added succesfully:";
                        echo $(grep $HOSTNAME /etc/hosts);
                    else
                        echo "Failed to Add $HOSTNAME, Try again!";
                fi
        fi
    else
        echo "Error: missing required parameters."
        echo "Usage: "
        echo "  addhost ip domain"
    fi
}

function stop_all() {
  current_dir="$1"
  cd ${current_dir}
  if ls docker-compose.* 1> /dev/null 2>&1;
  then
    for docker_compose_file in $(ls docker-compose.*)
    do
        environment=$(echo $docker_compose_file | cut -d "." -f 2)
        ${DIR}/../../environment/${environment}/stop.sh "${PWD}/${docker_compose_file}"
    done
  else
    ${DIR}/../../environment/plaintext/stop.sh
  fi
  cd -
}

function display_jmx_info() {
  if [ -z "$ENABLE_JMX_GRAFANA" ]
  then
    log "📊 JMX metrics are available locally on those ports:"
  else
    log "📊 Grafana is reachable at http://127.0.0.1:3000 or JMX metrics are available locally on those ports:"
  fi  
  log "    - zookeeper       : 9999"
  log "    - broker          : 10000"
  log "    - schema-registry : 10001"
  log "    - connect         : 10002"

  if [ -z "$DISABLE_KSQLDB" ]
  then
    log "    - ksqldb-server   : 10003"
  fi

  
}
function get_jmx_metrics() {
  JMXTERM_VERSION="1.0.2"
  JMXTERM_UBER_JAR="/tmp/jmxterm-$JMXTERM_VERSION-uber.jar"
  if [ ! -f $JMXTERM_UBER_JAR ]
  then
    curl -L https://github.com/jiaqi/jmxterm/releases/download/v$JMXTERM_VERSION/jmxterm-$JMXTERM_VERSION-uber.jar -o $JMXTERM_UBER_JAR -s
  fi

  rm -f /tmp/commands
  rm -f /tmp/jmx_metrics.log

  component="$1"
  domains="$2"
  if [ "$domains" = "" ]
  then
    # non existing domain: all domains will be in output !
    logwarn "You did not specify a list of domains, all domains will be exported!"
    domains="ALL"
  fi

  case "$component" in
  zookeeper )
    port=9999
  ;;
  broker )
    port=10000
  ;;
  schema-registry )
    port=10001
  ;;
  connect )
    port=10002
  ;;
  n|N ) ;;
  * ) logerror "invalid component $component! it should be one of zookeeper, broker, schema-registry or connect";exit 1;;
  esac

  docker cp $JMXTERM_UBER_JAR $component:$JMXTERM_UBER_JAR
  if [ "$domains" = "ALL" ]
  then

log "This is the list of domains for component $component"
docker exec -i $component java -jar $JMXTERM_UBER_JAR  -l localhost:$port -n -v silent << EOF
domains
exit
EOF
  fi

for domain in `echo $domains`
do
docker exec -i $component java -jar $JMXTERM_UBER_JAR  -l localhost:$port -n -v silent > /tmp/beans.log << EOF
domain $domain
beans
exit
EOF
  while read line; do echo "get *"  -b $line; done < /tmp/beans.log >> /tmp/commands

  echo "####### domain $domain ########" >> /tmp/jmx_metrics.log
  docker exec -i $component java -jar $JMXTERM_UBER_JAR  -l localhost:$port -n < /tmp/commands >> /tmp/jmx_metrics.log 2>&1
done

  log "JMX metrics are available in /tmp/jmx_metrics.log file"
}

# https://www.linuxjournal.com/content/validating-ip-address-bash-script
function valid_ip()
{
    local  ip=$1
    local  stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
            && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

function container_to_name() {
    container=$1
    echo "${PWD##*/}_${container}_1"
}

function container_to_ip() {
    if [ $# -lt 1 ]; then
        echo "Usage: container_to_ip container"
    fi
    echo $(docker inspect $1 -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
}

function clear_traffic_control() {
    if [ $# -lt 1 ]; then
        echo "Usage: clear_traffic_control src_container"
    fi

    src_container=$1

    echo "Removing all traffic control settings on $src_container"

    # Delete the entry from the tc table so the changes made to tc do not persist
    docker exec --privileged -u0 -t $src_container tc qdisc del dev eth0 root
}

function get_latency() {
    if [ $# -lt 2 ]; then
        echo "Usage: get_latency src_container dst_container"
    fi
    src_container=$1
    dst_container=$2
    docker exec --privileged -u0 -t $src_container ping $dst_container -c 4 -W 80 | tail -1 | awk -F '/' '{print $5}'
}

# https://serverfault.com/a/906499
function add_latency() {
    if [ $# -lt 3 ]; then
        echo "Usage: add_latency src_container dst_container (or ip address) latency"
        echo "Example: add_latency container-1 container-2 100ms"
    fi

    src_container=$1
    if valid_ip $2
    then 
      dst_ip=$2
    else 
      dst_ip=$(container_to_ip $2)
    fi
    latency=$3

    set +e
    clear_traffic_control $src_container
    set -e

    echo "Adding $latency latency from $src_container to $2"

    # Add a classful priority queue which lets us differentiate messages.
    # This queue is named 1:.
    # Three children classes, 1:1, 1:2 and 1:3, are automatically created.
    docker exec --privileged -u0 -t $src_container tc qdisc add dev eth0 root handle 1: prio


    # Add a filter to the parent queue 1: (also called 1:0). The filter has priority 1 (if we had more filters this would make a difference).
    # For all messages with the ip of dst_ip as their destination, it routes them to class 1:1, which
    # subsequently sends them to its only child, queue 10: (All messages need to  "end up" in a queue).
    docker exec --privileged -u0 -t $src_container tc filter add dev eth0 protocol ip parent 1: prio 1 u32 match ip dst $dst_ip flowid 1:1

    # Route the rest of the of the packets without any control.
    # Add a filter to the parent queue 1:. The filter has priority 2.
    docker exec --privileged -u0 -t $src_container tc filter add dev eth0 protocol all parent 1: prio 2 u32 match ip dst 0.0.0.0/0 flowid 1:2
    docker exec --privileged -u0 -t $src_container tc filter add dev eth0 protocol all parent 1: prio 2 u32 match ip protocol 1 0xff flowid 1:2

    # Add a child queue named 10: under class 1:1. All outgoing packets that will be routed to 10: will have delay applied them.
    docker exec --privileged -u0 -t $src_container tc qdisc add dev eth0 parent 1:1 handle 10: netem delay $latency

    # Add a child queue named 20: under class 1:2
    docker exec --privileged -u0 -t $src_container tc qdisc add dev eth0 parent 1:2 handle 20: sfq
}

function add_packet_corruption() {
    if [ $# -lt 3 ]; then
        echo "Usage: add_packet_corruption src_container dst_container (or ip address) corrupt"
        echo "Exemple: add_packet_corruption container-1 container-2 1%"
    fi

    src_container=$1
    if valid_ip $2
    then 
      dst_ip=$2
    else 
      dst_ip=$(container_to_ip $2)
    fi
    corruption=$3

    set +e
    clear_traffic_control $src_container
    set -e

    echo "Adding $corruption corruption from $src_container to $2"

    # Add a classful priority queue which lets us differentiate messages.
    # This queue is named 1:.
    # Three children classes, 1:1, 1:2 and 1:3, are automatically created.
    docker exec --privileged -u0 -t $src_container tc qdisc add dev eth0 root handle 1: prio 


    # Add a filter to the parent queue 1: (also called 1:0). The filter has priority 1 (if we had more filters this would make a difference).
    # For all messages with the ip of dst_ip as their destination, it routes them to class 1:1, which
    # subsequently sends them to its only child, queue 10: (All messages need to  "end up" in a queue).
    docker exec --privileged -u0 -t $src_container tc filter add dev eth0 protocol ip parent 1: prio 1 u32 match ip dst $dst_ip flowid 1:1 

    # Route the rest of the of the packets without any control.
    # Add a filter to the parent queue 1:. The filter has priority 2.
    docker exec --privileged -u0 -t $src_container tc filter add dev eth0 protocol all parent 1: prio 2 u32 match ip dst 0.0.0.0/0 flowid 1:2 
    docker exec --privileged -u0 -t $src_container tc filter add dev eth0 protocol all parent 1: prio 2 u32 match ip protocol 1 0xff flowid 1:2 

    # Add a child queue named 10: under class 1:1. All outgoing packets that will be routed to 10: will have corrupt applied them.
    docker exec --privileged -u0 -t $src_container tc qdisc add dev eth0 parent 1:1 handle 10: netem corrupt $corruption

    # Add a child queue named 20: under class 1:2
    docker exec --privileged -u0 -t $src_container tc qdisc add dev eth0 parent 1:2 handle 20: sfq 
}

function add_packet_loss() {
    if [ $# -lt 3 ]; then
        echo "Usage: add_packet_loss src_container dst_container (or ip address) corrupt"
        echo "Exemple: add_packet_loss container-1 container-2 1%"
    fi

    src_container=$1
    if valid_ip $2
    then 
      dst_ip=$2
    else 
      dst_ip=$(container_to_ip $2)
    fi
    loss=$3

    set +e
    clear_traffic_control $src_container
    set -e

    echo "Adding $loss loss from $src_container to $2"

    # Add a classful priority queue which lets us differentiate messages.
    # This queue is named 1:.
    # Three children classes, 1:1, 1:2 and 1:3, are automatically created.
    docker exec --privileged -u0 -t $src_container tc qdisc add dev eth0 root handle 1: prio 


    # Add a filter to the parent queue 1: (also called 1:0). The filter has priority 1 (if we had more filters this would make a difference).
    # For all messages with the ip of dst_ip as their destination, it routes them to class 1:1, which
    # subsequently sends them to its only child, queue 10: (All messages need to  "end up" in a queue).
    docker exec --privileged -u0 -t $src_container tc filter add dev eth0 protocol ip parent 1: prio 1 u32 match ip dst $dst_ip flowid 1:1 

    # Route the rest of the of the packets without any control.
    # Add a filter to the parent queue 1:. The filter has priority 2.
    docker exec --privileged -u0 -t $src_container tc filter add dev eth0 protocol all parent 1: prio 2 u32 match ip dst 0.0.0.0/0 flowid 1:2 
    docker exec --privileged -u0 -t $src_container tc filter add dev eth0 protocol all parent 1: prio 2 u32 match ip protocol 1 0xff flowid 1:2 

    # Add a child queue named 10: under class 1:1. All outgoing packets that will be routed to 10: will have loss applied them.
    docker exec --privileged -u0 -t $src_container tc qdisc add dev eth0 parent 1:1 handle 10: netem loss $loss

    # Add a child queue named 20: under class 1:2
    docker exec --privileged -u0 -t $src_container tc qdisc add dev eth0 parent 1:2 handle 20: sfq 
}

function get_3rdparty_file () {
  file="$1"

  if [ -f $file ]
  then
    log "$file already present, skipping"
    return
  fi

  folder="3rdparty"
  if [[ "$file" == *repro* ]]
  then
    folder="repro-files"
  fi
  set +e
  aws s3 ls s3://kafka-docker-playground/$folder/$file > /dev/null 2>&1
  if [ $? -eq 0 ]
  then
      log "Downloading <s3://kafka-docker-playground/$folder/$file> from S3 bucket"
      aws s3 cp --only-show-errors "s3://kafka-docker-playground/$folder/$file" .
      if [ $? -eq 0 ]; then
        log "📄 <s3://kafka-docker-playground/$folder/$file> was downloaded from S3 bucket"
      fi
      if [[ "$OSTYPE" == "darwin"* ]]
      then
          # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
          chmod a+rw $file
      else
          # on CI, docker is run as runneradmin user, need to use sudo
          sudo chmod a+rw $file
      fi
  fi
  set -e
}

function remove_cdb_oracle_image() {
  ZIP_FILE="$1"
  SETUP_FOLDER="$2"

  if [ "$ZIP_FILE" == "linuxx64_12201_database.zip" ]
  then
      ORACLE_VERSION="12.2.0.1-ee"
  else
      ORACLE_VERSION="19.3.0-ee"
  fi

  SETUP_FILE=${SETUP_FOLDER}/01_user-setup.sh
  SETUP_FILE_CKSUM=$(cksum $SETUP_FILE | awk '{ print $1 }')
  ORACLE_IMAGE="db-prebuilt-$SETUP_FILE_CKSUM:$ORACLE_VERSION"

  if ! test -z "$(docker images -q $ORACLE_IMAGE)"
  then
    log "🧹 Removing Oracle image $ORACLE_IMAGE"
    docker image rm $ORACLE_IMAGE
  fi
}

function create_or_get_oracle_image() {
  ZIP_FILE="$1"
  SETUP_FOLDER="$2"

  if [ "$ZIP_FILE" == "linuxx64_12201_database.zip" ]
  then
      ORACLE_VERSION="12.2.0.1-ee"
  else
      ORACLE_VERSION="19.3.0-ee"
  fi
  # used for docker-images repo
  DOCKERFILE_VERSION=$(echo "$ORACLE_VERSION" | cut -d "-" -f 1)

  # https://github.com/oracle/docker-images/tree/main/OracleDatabase/SingleInstance/samples/prebuiltdb
  SETUP_FILE=${SETUP_FOLDER}/01_user-setup.sh
  SETUP_FILE_CKSUM=$(cksum $SETUP_FILE | awk '{ print $1 }')
  export ORACLE_IMAGE="db-prebuilt-$SETUP_FILE_CKSUM:$ORACLE_VERSION"
  TEMP_CONTAINER="oracle-build-$ORACLE_VERSION-$(basename $SETUP_FOLDER)"

  if test -z "$(docker images -q $ORACLE_IMAGE)"
  then
    set +e
    aws s3 ls s3://kafka-docker-playground/3rdparty/$ORACLE_IMAGE.tar > /dev/null 2>&1
    if [ $? -eq 0 ]
    then
        log "Downloading <s3://kafka-docker-playground/3rdparty/$ORACLE_IMAGE.tar> from S3 bucket"
        aws s3 cp --only-show-errors "s3://kafka-docker-playground/3rdparty/$ORACLE_IMAGE.tar" /tmp/
        if [ $? -eq 0 ]
        then
          log "📄 <s3://kafka-docker-playground/3rdparty/$ORACLE_IMAGE.tar> was downloaded from S3 bucket"
          docker load -i /tmp/$ORACLE_IMAGE.tar
          if [ $? -eq 0 ]
          then
            log "📄 image $ORACLE_IMAGE has been installed locally"
          fi
          log "🧹 Removing /tmp/$ORACLE_IMAGE.tar"
          rm -f /tmp/$ORACLE_IMAGE.tar
        fi
    fi
    set -e
  fi

  if ! test -z "$(docker images -q $ORACLE_IMAGE)"
  then
    log "✨ Using Oracle prebuilt image $ORACLE_IMAGE (oracle version 🔢 $ORACLE_VERSION and 📂 setup folder $SETUP_FOLDER)"
    return
  fi

  BASE_ORACLE_IMAGE="oracle/database:$ORACLE_VERSION"

  if test -z "$(docker images -q $BASE_ORACLE_IMAGE)"
  then
    set +e
    aws s3 ls s3://kafka-docker-playground/3rdparty/oracle_database_$ORACLE_VERSION.tar > /dev/null 2>&1
    if [ $? -eq 0 ]
    then
        log "Downloading <s3://kafka-docker-playground/3rdparty/oracle_database_$ORACLE_VERSION.tar> from S3 bucket"
        aws s3 cp --only-show-errors "s3://kafka-docker-playground/3rdparty/oracle_database_$ORACLE_VERSION.tar" /tmp/
        if [ $? -eq 0 ]
        then
          log "📄 <s3://kafka-docker-playground/3rdparty/oracle_database_$ORACLE_VERSION.tar> was downloaded from S3 bucket"
          docker load -i /tmp/oracle_database_$ORACLE_VERSION.tar
          if [ $? -eq 0 ]
          then
            log "📄 image $BASE_ORACLE_IMAGE has been installed locally"
          fi
          log "🧹 Removing /tmp/$ORACLE_IMAGE.tar"
          rm -f /tmp/oracle_database_$ORACLE_VERSION.tar
        fi
    fi
    set -e
  fi

  if test -z "$(docker images -q $BASE_ORACLE_IMAGE)"
  then
      if [ ! -f ${ZIP_FILE} ]
      then
          set +e
          aws s3 ls s3://kafka-docker-playground/3rdparty/${ZIP_FILE} > /dev/null 2>&1
          if [ $? -eq 0 ]
          then
              log "Downloading <s3://kafka-docker-playground/3rdparty/${ZIP_FILE}> from S3 bucket"
              aws s3 cp --only-show-errors "s3://kafka-docker-playground/3rdparty/${ZIP_FILE}" .
              if [ $? -eq 0 ]; then
                    log "📄 <s3://kafka-docker-playground/3rdparty/${ZIP_FILE}> was downloaded from S3 bucket"
              fi
          fi
          set -e
      fi
      if [ ! -f ${ZIP_FILE} ]
      then
          logerror "ERROR: ${ZIP_FILE} is missing. It must be downloaded manually in order to acknowledge user agreement"
          exit 1
      fi
      log "👷 Building $BASE_ORACLE_IMAGE docker image..it can take a while...(more than 15 minutes!)"
      OLDDIR=$PWD
      rm -rf docker-images
      git clone https://github.com/oracle/docker-images.git

      mv ${ZIP_FILE} docker-images/OracleDatabase/SingleInstance/dockerfiles/$DOCKERFILE_VERSION/${ZIP_FILE}
      cd docker-images/OracleDatabase/SingleInstance/dockerfiles
      ./buildContainerImage.sh -v $DOCKERFILE_VERSION -e
      rm -rf docker-images
      cd ${OLDDIR}
  fi

  export ORACLE_IMAGE="db-prebuilt-$SETUP_FILE_CKSUM:$ORACLE_VERSION"

  if test -z "$(docker images -q $ORACLE_IMAGE)"
  then
      log "🏭 Prebuilt $ORACLE_IMAGE docker image does not exist, building it now..it can take a while..."
      log "🚦 Startup a container ${TEMP_CONTAINER} with setup folder $SETUP_FOLDER and create the database"
      cd $SETUP_FOLDER
      docker run -d -e ORACLE_PWD=Admin123 -v $PWD:/opt/oracle/scripts/setup --name ${TEMP_CONTAINER} ${BASE_ORACLE_IMAGE}
      cd -

      MAX_WAIT=2500
      CUR_WAIT=0
      log "⌛ Waiting up to $MAX_WAIT seconds for ${TEMP_CONTAINER} to start"
      docker container logs ${TEMP_CONTAINER} > /tmp/out.txt 2>&1
      while [[ ! $(cat /tmp/out.txt) =~ "Completed: ALTER DATABASE OPEN" ]]; do
      sleep 10
      docker container logs ${TEMP_CONTAINER} > /tmp/out.txt 2>&1
      CUR_WAIT=$(( CUR_WAIT+10 ))
      if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
            logerror "ERROR: The logs in ${TEMP_CONTAINER} container do not show 'DONE: Executing user defined scripts' after $MAX_WAIT seconds. Please troubleshoot with 'docker container ps' and 'docker container logs'.\n"
            exit 1
      fi
      done
      log "${TEMP_CONTAINER} has started! Check logs in /tmp/${TEMP_CONTAINER}.log"
      docker container logs ${TEMP_CONTAINER} > /tmp/${TEMP_CONTAINER}.log 2>&1
      log "🛑 Stop the running container"
      docker stop -t 600 ${TEMP_CONTAINER}
      log "🛠 Create the image with the prebuilt database"
      docker commit -m "Image with prebuilt database" ${TEMP_CONTAINER} ${ORACLE_IMAGE}
      log "🧹 Clean up ${TEMP_CONTAINER}"
      docker rm ${TEMP_CONTAINER}

      if [ ! -z "$CI" ]
      then
          set +e
          aws s3 ls s3://kafka-docker-playground/3rdparty/$ORACLE_IMAGE.tar > /dev/null 2>&1
          if [ $? -ne 0 ]
          then
              log "📄 Uploading </tmp/$ORACLE_IMAGE.tar> to S3 bucket"
              docker save -o /tmp/$ORACLE_IMAGE.tar $ORACLE_IMAGE
              aws s3 cp --only-show-errors "/tmp/$ORACLE_IMAGE.tar" "s3://kafka-docker-playground/3rdparty/"
              if [ $? -eq 0 ]; then
                    log "📄 </tmp/$ORACLE_IMAGE.tar> was uploaded to S3 bucket"
              fi
          fi
          set -e
      fi
  fi

  log "✨ Using Oracle prebuilt image $ORACLE_IMAGE (oracle version 🔢 $ORACLE_VERSION and 📂 setup folder $SETUP_FOLDER)"
}

function print_code_pass() {
  local MESSAGE=""
	local CODE=""
  OPTIND=1
  while getopts ":c:m:" opt; do
    case ${opt} in
			c ) CODE=${OPTARG};;
      m ) MESSAGE=${OPTARG};;
		esac
	done
  shift $((OPTIND-1))
	printf "${PRETTY_PASS}${PRETTY_CODE}%s\e[0m\n" "${CODE}"
	[[ -z "$MESSAGE" ]] || printf "\t$MESSAGE\n"			
}
function print_code_error() {
  local MESSAGE=""
	local CODE=""
  OPTIND=1
  while getopts ":c:m:" opt; do
    case ${opt} in
			c ) CODE=${OPTARG};;
      m ) MESSAGE=${OPTARG};;
		esac
	done
  shift $((OPTIND-1))
	printf "${PRETTY_ERROR}${PRETTY_CODE}%s\e[0m\n" "${CODE}"
	[[ -z "$MESSAGE" ]] || printf "\t$MESSAGE\n"			
}

function exit_with_error()
{
  local USAGE="\nUsage: exit_with_error -c code -n name -m message -l line_number\n"
  local NAME=""
  local MESSAGE=""
  local CODE=$UNSPECIFIED_ERROR
  local LINE=
  OPTIND=1
  while getopts ":n:m:c:l:" opt; do
    case ${opt} in
      n ) NAME=${OPTARG};;
      m ) MESSAGE=${OPTARG};;
      c ) CODE=${OPTARG};;
      l ) LINE=${OPTARG};;
      ? ) printf $USAGE;return 1;;
    esac
  done
  shift $((OPTIND-1))
  print_error "error ${CODE} occurred in ${NAME} at line $LINE"
	printf "\t${MESSAGE}\n"
  exit $CODE
}

function maybe_delete_ccloud_environment () {
  DELTA_CONFIGS_ENV=/tmp/delta_configs/env.delta

  if [ -f $DELTA_CONFIGS_ENV ]
  then
    source $DELTA_CONFIGS_ENV
  else
    logerror "ERROR: $DELTA_CONFIGS_ENV has not been generated"
    exit 1
  fi

  if [ -z "$CLUSTER_NAME" ]
  then
    # 
    # CLUSTER_NAME is not set
    #
    log "🧹❌ Confluent Cloud cluster will be deleted..."
    verify_installed "confluent"
    check_confluent_version 2.0.0 || exit 1
    verify_confluent_login  "confluent kafka cluster list"

    export QUIET=true

    if [ ! -z "$ENVIRONMENT" ]
    then
      log "🌐 ENVIRONMENT $ENVIRONMENT is set, it will not be deleted"
      export PRESERVE_ENVIRONMENT=true
    else
      export PRESERVE_ENVIRONMENT=false
    fi
    SERVICE_ACCOUNT_ID=$(ccloud:get_service_account_from_current_cluster_name)
    set +e
    ccloud::destroy_ccloud_stack $SERVICE_ACCOUNT_ID
    set -e
  fi
}

function bootstrap_ccloud_environment () {
  DELTA_CONFIGS_ENV=/tmp/delta_configs/env.delta

  if [ -z "$CI" ] && [ -z "$CLOUDFORMATION" ]
  then
    # not running with CI
    verify_installed "confluent"
    check_confluent_version 2.0.0 || exit 1
    verify_confluent_login  "confluent kafka cluster list"
  else
      log "Installing confluent CLI"
      curl -L --http1.1 https://cnfl.io/cli | sudo sh -s -- -b /usr/local/bin
      export PATH=$PATH:/usr/local/bin
      log "##################################################"
      log "Log in to Confluent Cloud"
      log "##################################################"
      confluent login --save
  fi

  if [ -z "$CLUSTER_NAME" ]
  then
    # 
    # CLUSTER_NAME is not set
    #
    log "🛠👷‍♀️ CLUSTER_NAME is not set, a new Confluent Cloud cluster will be created..."
    log "🎓 If you wanted to use an existing cluster, set CLUSTER_NAME, ENVIRONMENT, CLUSTER_CLOUD, CLUSTER_REGION and CLUSTER_CREDS (also optionnaly SCHEMA_REGISTRY_CREDS)"

    if [ -z "$CLUSTER_CLOUD" ] || [ -z "$CLUSTER_REGION" ]
    then
      logwarn "CLUSTER_CLOUD and/or CLUSTER_REGION are not set, the cluster will be created 🌤 AWS provider and 🗺 eu-west-2 region"
      export CLUSTER_CLOUD=aws 
      export CLUSTER_REGION=eu-west-2
    fi

    if [ ! -z $ENVIRONMENT ]
    then
      log "🌐 ENVIRONMENT is set with $ENVIRONMENT and will be used"
    fi
    log "🌤  CLUSTER_CLOUD is set with $CLUSTER_CLOUD"
    log "🗺  CLUSTER_REGION is set with $CLUSTER_REGION"

    export EXAMPLE=$(basename $PWD)
    export WARMUP_TIME=15
    export QUIET=true
  else
    # 
    # CLUSTER_NAME is set
    #
    log "🌱 CLUSTER_NAME is set, your existing Confluent Cloud cluster will be used..."
    if [ -z $ENVIRONMENT ] || [ -z $CLUSTER_CLOUD ] || [ -z $CLUSTER_CLOUD ] || [ -z $CLUSTER_REGION ] || [ -z $CLUSTER_CREDS ]
    then
      logerror "One mandatory environment variable to use your cluster is missing:"
      logerror "ENVIRONMENT=$ENVIRONMENT"
      logerror "CLUSTER_NAME=$CLUSTER_NAME"
      logerror "CLUSTER_CLOUD=$CLUSTER_CLOUD"
      logerror "CLUSTER_REGION=$CLUSTER_REGION"
      logerror "CLUSTER_CREDS=$CLUSTER_CREDS"
      exit 1
    fi

    log "🌐 ENVIRONMENT is set with $ENVIRONMENT"
    log "🎰 CLUSTER_NAME is set with $CLUSTER_NAME"
    log "🌤  CLUSTER_CLOUD is set with $CLUSTER_CLOUD"
    log "🗺  CLUSTER_REGION is set with $CLUSTER_REGION" 

    export WARMUP_TIME=0
  fi

  check_if_continue

  ccloud::create_ccloud_stack false  \
    && print_code_pass -c "ccloud::create_ccloud_stack false"

  CONFIG_FILE=/tmp/tmp.config
  export CONFIG_FILE=$CONFIG_FILE
  ccloud::validate_ccloud_config $CONFIG_FILE || exit 1

  ccloud::generate_configs $CONFIG_FILE \
    && print_code_pass -c "ccloud::generate_configs $CONFIG_FILE"

  if [ -f $DELTA_CONFIGS_ENV ]
  then
    source $DELTA_CONFIGS_ENV
  else
    logerror "ERROR: $DELTA_CONFIGS_ENV has not been generated"
    exit 1
  fi
}

function create_ccloud_connector() {
  file=$1

  log "Creating connector from $file"
  confluent connect create --config $file
  if [[ $? != 0 ]]
  then
    logerror "Exit status was not 0 while creating connector from $file.  Please troubleshoot and try again"
  fi

  return 0
}

function validate_ccloud_connector_up() {
  confluent connect list -o json | jq -e 'map(select(.name == "'"$1"'" and .status == "RUNNING")) | .[]' > /dev/null 2>&1
}

function get_ccloud_connector_lcc() {
  confluent connect list -o json | jq -r -e 'map(select(.name == "'"$1"'")) | .[].id'
}

function ccloud::retry() {
    local -r -i max_wait="$1"; shift
    local -r cmd="$@"

    local -i sleep_interval=5
    local -i curr_wait=0

    until $cmd
    do
        if (( curr_wait >= max_wait ))
        then
            echo "ERROR: Failed after $curr_wait seconds. Please troubleshoot and run again."
            return 1
        else
            printf "."
            curr_wait=$((curr_wait+sleep_interval))
            sleep $sleep_interval
        fi
    done
    printf "\n"
}

function wait_for_ccloud_connector_up() {
  filename=$1
  maxWait=$2

  connectorName=$(cat $filename | jq -r .name)
  connectorId=$(get_ccloud_connector_lcc $connectorName)
  log "Waiting up to $maxWait seconds for connector $connectorName ($connectorId) to be RUNNING"
  ccloud::retry $maxWait validate_ccloud_connector_up $connectorName || exit 1
  log "Connector $connectorName ($connectorId) is RUNNING"

  return 0
}


function delete_ccloud_connector() {
  filename=$1
  connectorName=$(cat $filename | jq -r .name)
  connectorId=$(get_ccloud_connector_lcc $connectorName)

  log "Deleting connector $connectorName ($connectorId)"
  confluent connect delete $connectorId
  return 0
}

function wait_for_log () {
     message="$1"
     container=${2:-connect}
     max_wait=${3:-600}
     cur_wait=0
     log "⌛ Waiting up to $max_wait seconds for message $message to be present in $container container logs..."
     docker container logs connect > /tmp/out.txt 2>&1
     while ! grep "$message" /tmp/out.txt > /dev/null;
     do
          sleep 10
          docker container logs connect > /tmp/out.txt 2>&1
          cur_wait=$(( cur_wait+10 ))
          if [[ "$cur_wait" -gt "$max_wait" ]]; then
               logerror "The logs in $container container do not show '$message' after $max_wait seconds. Please troubleshoot with 'docker container ps' and 'docker container logs'."
               return 1
          fi
     done
     grep "$message" /tmp/out.txt
     log "The message is there !"
}

###############
## ccloud-utils functions
## BEGIN
##############



CLI_MIN_VERSION=${CLI_MIN_VERSION:-2.5.0}

# --------------------------------------------------------------
# Library
# --------------------------------------------------------------

function ccloud::validate_expect_installed() {
  if [[ $(type expect 2>&1) =~ "not found" ]]; then
    echo "'expect' is not found. Install 'expect' and try again"
    exit 1
  fi

  return 0
}
function ccloud::validate_cli_installed() {
  if [[ $(type confluent 2>&1) =~ "not found" ]]; then
    echo "'confluent' is not found. Install the Confluent CLI (https://docs.confluent.io/confluent-cli/current/install.html) and try again."
    exit 1
  fi
}

function ccloud::validate_cli_v2() {
  ccloud::validate_cli_installed || exit 1

  if [[ -z $(confluent version 2>&1 | grep "Go") ]]; then
    echo "This example requires the new Confluent CLI. Please update your version and try again."
    exit 1
  fi

  return 0
}

function ccloud::validate_logged_in_cli() {
  ccloud::validate_cli_v2 || exit 1

  if [[ "$(confluent kafka cluster list 2>&1)" =~ "confluent login" ]]; then
    echo
    echo "ERROR: Not logged into Confluent Cloud."
    echo "Log in with the command 'confluent login --save' before running the example. The '--save' argument saves your Confluent Cloud user login credentials or refresh token (in the case of SSO) to the local netrc file."
    exit 1
  fi

  return 0
}

function ccloud::get_version_cli() {
  confluent version | grep "^Version:" | cut -d':' -f2 | cut -d'v' -f2
}

function ccloud::validate_version_cli() {
  ccloud::validate_cli_installed || exit 1

  CLI_VERSION=$(ccloud::get_version_cli)

  if ccloud::version_gt $CLI_MIN_VERSION $CLI_VERSION; then
    echo "confluent version ${CLI_MIN_VERSION} or greater is required. Current version: ${CLI_VERSION}"
    echo "To update, follow: https://docs.confluent.io/confluent-cli/current/migrate.html"
    exit 1
  fi
}

function ccloud::validate_psql_installed() {
  if [[ $(type psql 2>&1) =~ "not found" ]]; then
    echo "psql is not found. Install psql and try again"
    exit 1
  fi

  return 0
}

function ccloud::validate_aws_cli_installed() {
  if [[ $(type aws 2>&1) =~ "not found" ]]; then
    echo "AWS CLI is not found. Install AWS CLI and try again"
    exit 1
  fi

  return 0
}

function ccloud::get_version_aws_cli() {
  version_major=$(aws --version 2>&1 | awk -F/ '{print $2;}' | head -c 1)
  if [[ "$version_major" -eq 2 ]]; then
    echo "2"
  else
    echo "1"
  fi
  return 0
}

function ccloud::validate_gsutil_installed() {
  if [[ $(type gsutil 2>&1) =~ "not found" ]]; then
    echo "Google Cloud gsutil is not found. Install Google Cloud gsutil and try again"
    exit 1
  fi

  return 0
}

function ccloud::validate_az_installed() {
  if [[ $(type az 2>&1) =~ "not found" ]]; then
    echo "Azure CLI is not found. Install Azure CLI and try again"
    exit 1
  fi

  return 0
}

function ccloud::validate_cloud_source() {
  config=$1

  source $config

  if [[ "$DATA_SOURCE" == "kinesis" ]]; then
    ccloud::validate_aws_cli_installed || exit 1
    if [[ -z "$KINESIS_REGION" || -z "$AWS_PROFILE" ]]; then
      echo "ERROR: DATA_SOURCE=kinesis, but KINESIS_REGION or AWS_PROFILE is not set.  Please set these parameters in config/demo.cfg and try again."
      exit 1
    fi
    aws kinesis list-streams --profile $AWS_PROFILE --region $KINESIS_REGION > /dev/null \
      || { echo "Could not run 'aws kinesis list-streams'.  Check credentials and run again." ; exit 1; }
  elif [[ "$DATA_SOURCE" == "rds" ]]; then
    ccloud::validate_aws_cli_installed || exit 1
    if [[ -z "$RDS_REGION" || -z "$AWS_PROFILE" ]]; then
      echo "ERROR: DATA_SOURCE=rds, but RDS_REGION or AWS_PROFILE is not set.  Please set these parameters in config/demo.cfg and try again."
      exit 1
    fi
    aws rds describe-db-instances --profile $AWS_PROFILE --region $RDS_REGION > /dev/null \
      || { echo "Could not run 'aws rds describe-db-instances'.  Check credentials and run again." ; exit 1; }
  else
    echo "Cloud source $cloudsource is not valid.  Must be one of [kinesis|rds]."
    exit 1
  fi

  return 0
}

function ccloud::validate_cloud_storage() {
  config=$1

  source $config
  storage=$DESTINATION_STORAGE

  if [[ "$storage" == "s3" ]]; then
    ccloud::validate_aws_cli_installed || exit 1
    ccloud::validate_credentials_s3 $S3_PROFILE $S3_BUCKET || exit 1
    aws s3api list-buckets --profile $S3_PROFILE --region $STORAGE_REGION > /dev/null \
      || { echo "Could not run 'aws s3api list-buckets'.  Check credentials and run again." ; exit 1; }
  elif [[ "$storage" == "gcs" ]]; then
    ccloud::validate_gsutil_installed || exit 1
    ccloud::validate_credentials_gcp $GCS_CREDENTIALS_FILE $GCS_BUCKET || exit 1
  elif [[ "$storage" == "az" ]]; then
    ccloud::validate_az_installed || exit 1
    ccloud::validate_credentials_az $AZBLOB_STORAGE_ACCOUNT $AZBLOB_CONTAINER || exit 1
  else
    echo "Storage destination $storage is not valid.  Must be one of [s3|gcs|az]."
    exit 1
  fi

  return 0
}

function ccloud::validate_credentials_gcp() {
  GCS_CREDENTIALS_FILE=$1
  GCS_BUCKET=$2

  if [[ -z "$GCS_CREDENTIALS_FILE" || -z "$GCS_BUCKET" ]]; then
    echo "ERROR: DESTINATION_STORAGE=gcs, but GCS_CREDENTIALS_FILE or GCS_BUCKET is not set.  Please set these parameters in config/demo.cfg and try again."
    exit 1
  fi

  gcloud auth activate-service-account --key-file $GCS_CREDENTIALS_FILE || {
    echo "ERROR: Cannot activate service account with key file $GCS_CREDENTIALS_FILE. Verify your credentials and try again."
    exit 1
  }

  # Create JSON-formatted string of the GCS credentials
  export GCS_CREDENTIALS=$(python ./stringify-gcp-credentials.py $GCS_CREDENTIALS_FILE)
  # Remove leading and trailing double quotes, otherwise connector creation from CLI fails
  GCS_CREDENTIALS=$(echo "${GCS_CREDENTIALS:1:${#GCS_CREDENTIALS}-2}")

  return 0
}

function ccloud::validate_credentials_az() {
  AZBLOB_STORAGE_ACCOUNT=$1
  AZBLOB_CONTAINER=$2

  if [[ -z "$AZBLOB_STORAGE_ACCOUNT" || -z "$AZBLOB_CONTAINER" ]]; then
    echo "ERROR: DESTINATION_STORAGE=az, but AZBLOB_STORAGE_ACCOUNT or AZBLOB_CONTAINER is not set.  Please set these parameters in config/demo.cfg and try again."
    exit 1
  fi

  if [[ "$AZBLOB_STORAGE_ACCOUNT" == "default" ]]; then
    echo "ERROR: Azure Blob storage account name cannot be 'default'. Verify the value of the storage account name (did you create one?) in config/demo.cfg, as specified by the parameter AZBLOB_STORAGE_ACCOUNT, and try again."
    exit 1
  fi

  exists=$(az storage account check-name --name $AZBLOB_STORAGE_ACCOUNT | jq -r .reason)
  if [[ "$exists" != "AlreadyExists" ]]; then
    echo "ERROR: Azure Blob storage account name $AZBLOB_STORAGE_ACCOUNT does not exist. Check the value of AZBLOB_STORAGE_ACCOUNT in config/demo.cfg and try again."
    exit 1
  fi
  export AZBLOB_ACCOUNT_KEY=$(az storage account keys list --account-name $AZBLOB_STORAGE_ACCOUNT | jq -r '.[0].value')
  if [[ "$AZBLOB_ACCOUNT_KEY" == "" ]]; then
    echo "ERROR: Cannot get the key for Azure Blob storage account name $AZBLOB_STORAGE_ACCOUNT. Check the value of AZBLOB_STORAGE_ACCOUNT in config/demo.cfg, and your key, and try again."
    exit 1
  fi

  return 0
}

function ccloud::validate_credentials_s3() {
  S3_PROFILE=$1
  S3_BUCKET=$2

  if [[ -z "$S3_PROFILE" || -z "$S3_BUCKET" ]]; then
    echo "ERROR: DESTINATION_STORAGE=s3, but S3_PROFILE or S3_BUCKET is not set.  Please set these parameters in config/demo.cfg and try again."
    exit 1
  fi

  aws configure get aws_access_key_id --profile $S3_PROFILE 1>/dev/null || {
    echo "ERROR: Cannot determine aws_access_key_id from S3_PROFILE=$S3_PROFILE.  Verify your credentials and try again."
    exit 1
  }
  aws configure get aws_secret_access_key --profile $S3_PROFILE 1>/dev/null || {
    echo "ERROR: Cannot determine aws_secret_access_key from S3_PROFILE=$S3_PROFILE.  Verify your credentials and try again."
    exit 1
  }
  return 0
}

function ccloud::validate_schema_registry_up() {
  auth=$1
  sr_endpoint=$2

  curl --silent -u $auth $sr_endpoint > /dev/null || {
    echo "ERROR: Could not validate credentials to Confluent Cloud Schema Registry. Please troubleshoot"
    exit 1
  }

  echo "Validated credentials to Confluent Cloud Schema Registry at $sr_endpoint"
  return 0
}

function ccloud::get_environment_id_from_service_id() {
  SERVICE_ACCOUNT_ID=$1

  ENVIRONMENT_NAME_PREFIX=${ENVIRONMENT_NAME_PREFIX:-"pg-$SERVICE_ACCOUNT_ID"}
  local environment_id=$(confluent environment list -o json | jq -r 'map(select(.name | startswith("'"$ENVIRONMENT_NAME_PREFIX"'"))) | .[].id')

  echo $environment_id

  return 0
}


function ccloud::create_and_use_environment() {
  ENVIRONMENT_NAME=$1

  OUTPUT=$(confluent environment create $ENVIRONMENT_NAME -o json)
  (($? != 0)) && { echo "ERROR: Failed to create environment $ENVIRONMENT_NAME. Please troubleshoot and run again"; exit 1; }
  ENVIRONMENT=$(echo "$OUTPUT" | jq -r ".id")
  confluent environment use $ENVIRONMENT &>/dev/null

  echo $ENVIRONMENT

  return 0
}

function ccloud::find_cluster() {
  CLUSTER_NAME=$1
  CLUSTER_CLOUD=$2
  CLUSTER_REGION=$3

  local FOUND_CLUSTER=$(confluent kafka cluster list -o json | jq -c -r '.[] | select((.name == "'"$CLUSTER_NAME"'") and (.provider == "'"$CLUSTER_CLOUD"'") and (.region == "'"$CLUSTER_REGION"'"))')
  [[ ! -z "$FOUND_CLUSTER" ]] && {
      echo "$FOUND_CLUSTER" | jq -r .id
      return 0 
    } || {
      return 1
    }
}

function ccloud::create_and_use_cluster() {
  CLUSTER_NAME=$1
  CLUSTER_CLOUD=$2
  CLUSTER_REGION=$3
  CLUSTER_TYPE=$4

  OUTPUT=$(confluent kafka cluster create "$CLUSTER_NAME" --cloud $CLUSTER_CLOUD --region $CLUSTER_REGION --type $CLUSTER_TYPE --output json 2>&1)
  (($? != 0)) && { echo "$OUTPUT"; exit 1; }
  CLUSTER=$(echo "$OUTPUT" | jq -r .id)
  confluent kafka cluster use $CLUSTER 2>/dev/null
  echo $CLUSTER

  return 0
}

function ccloud::maybe_create_and_use_cluster() {
  CLUSTER_NAME=$1
  CLUSTER_CLOUD=$2
  CLUSTER_REGION=$3
  CLUSTER_TYPE=$4
  CLUSTER_ID=$(ccloud::find_cluster $CLUSTER_NAME $CLUSTER_CLOUD $CLUSTER_REGION)
  if [ $? -eq 0 ]
  then
    confluent kafka cluster use $CLUSTER_ID
    echo $CLUSTER_ID
  else

    # VINC: added
    if [[ ! -z "$CLUSTER_CREDS" ]]
    then
      echo "ERROR: Could not find your $CLUSTER_CLOUD cluster $CLUSTER_NAME in region $CLUSTER_REGION"
      echo "Make sure CLUSTER_CLOUD and CLUSTER_REGION are set with values that correspond to your cluster!"
      exit 1
    else
      OUTPUT=$(ccloud::create_and_use_cluster "$CLUSTER_NAME" "$CLUSTER_CLOUD" "$CLUSTER_REGION" "$CLUSTER_TYPE")
      (($? != 0)) && { echo "$OUTPUT"; exit 1; }
      echo "$OUTPUT"
    fi
  fi

  return 0
}

function ccloud::create_service_account() {
  SERVICE_NAME=$1

  CCLOUD_EMAIL=$(confluent prompt -f '%u')
  OUTPUT=$(confluent iam service-account create $SERVICE_NAME --description "SA for $EXAMPLE run by $CCLOUD_EMAIL"  -o json)
  SERVICE_ACCOUNT_ID=$(echo "$OUTPUT" | jq -r ".id")

  echo $SERVICE_ACCOUNT_ID

  return 0
}

function ccloud:get_service_account_from_current_cluster_name() {
  SERVICE_ACCOUNT_ID=$(confluent kafka cluster describe -o json | jq -r '.name' | awk -F'-' '{print $3 "-" $4;}')

  echo $SERVICE_ACCOUNT_ID

  return 0
}

function ccloud::enable_schema_registry() {
  SCHEMA_REGISTRY_CLOUD=$1
  SCHEMA_REGISTRY_GEO=$2

  OUTPUT=$(confluent schema-registry cluster enable --cloud $SCHEMA_REGISTRY_CLOUD --geo $SCHEMA_REGISTRY_GEO -o json)
  SCHEMA_REGISTRY=$(echo "$OUTPUT" | jq -r ".id")

  echo $SCHEMA_REGISTRY

  return 0
}

function ccloud::find_credentials_resource() {
  SERVICE_ACCOUNT_ID=$1
  RESOURCE=$2
  local FOUND_CRED=$(confluent api-key list -o json | jq -c -r 'map(select((.resource_id == "'"$RESOURCE"'") and (.owner_resource_id == "'"$SERVICE_ACCOUNT_ID"'")))')
  local FOUND_COUNT=$(echo "$FOUND_CRED" | jq 'length')
  [[ $FOUND_COUNT -ne 0 ]] && {
      echo "$FOUND_CRED" | jq -r '.[0].key'
      return 0 
    } || {
      return 1
    }
}
function ccloud::create_credentials_resource() {
  SERVICE_ACCOUNT_ID=$1
  RESOURCE=$2

  OUTPUT=$(confluent api-key create --service-account $SERVICE_ACCOUNT_ID --resource $RESOURCE -o json)
  API_KEY_SA=$(echo "$OUTPUT" | jq -r ".key")
  API_SECRET_SA=$(echo "$OUTPUT" | jq -r ".secret")
  echo "${API_KEY_SA}:${API_SECRET_SA}"

  # vinc
  sleep 30
  return 0
}
#####################################################################
# The return from this function will be a colon ':' delimited
#   list, if the api-key is created the second element of the
#   list will be the secret.  If the api-key is being reused
#   the second element of the list will be empty
#####################################################################
function ccloud::maybe_create_credentials_resource() {
  SERVICE_ACCOUNT_ID=$1
  RESOURCE=$2
  
  local KEY=$(ccloud::find_credentials_resource $SERVICE_ACCOUNT_ID $RESOURCE)
  [[ -z $KEY ]] && {
    ccloud::create_credentials_resource $SERVICE_ACCOUNT_ID $RESOURCE
  } || {
    echo "$KEY:"; # the secret cannot be retrieved from a found key, caller needs to handle this
    return 0
  }
}

function ccloud::find_ksqldb_app() {
  KSQLDB_NAME=$1
  CLUSTER=$2

  local FOUND_APP=$(confluent ksql cluster list -o json | jq -c -r 'map(select((.name == "'"$KSQLDB_NAME"'") and (.kafka == "'"$CLUSTER"'")))')
  local FOUND_COUNT=$(echo "$FOUND_APP" | jq 'length')
  [[ $FOUND_COUNT -ne 0 ]] && {
      echo "$FOUND_APP" | jq -r '.[].id'
      return 0 
    } || {
      return 1
    }
}

function ccloud::create_ksqldb_app() {
  KSQLDB_NAME=$1
  CLUSTER=$2
  # colon deliminated credentials (APIKEY:APISECRET)
  local ksqlDB_kafka_creds=$3
  local kafka_api_key=$(echo $ksqlDB_kafka_creds | cut -d':' -f1)
  local kafka_api_secret=$(echo $ksqlDB_kafka_creds | cut -d':' -f2)

  KSQLDB=$(confluent ksql cluster create --cluster $CLUSTER --api-key "$kafka_api_key" --api-secret "$kafka_api_secret" --csu 1 -o json "$KSQLDB_NAME" | jq -r ".id")
  echo $KSQLDB

  return 0
}
function ccloud::maybe_create_ksqldb_app() {
  KSQLDB_NAME=$1
  CLUSTER=$2
  # colon deliminated credentials (APIKEY:APISECRET)
  local ksqlDB_kafka_creds=$3
  
  APP_ID=$(ccloud::find_ksqldb_app $KSQLDB_NAME $CLUSTER)
  if [ $? -eq 0 ]
  then
    echo $APP_ID
  else
    ccloud::create_ksqldb_app "$KSQLDB_NAME" "$CLUSTER" "$ksqlDB_kafka_creds"
  fi

  return 0
}

function ccloud::create_acls_all_resources_full_access() {
  SERVICE_ACCOUNT_ID=$1
  # Setting default QUIET=false to surface potential errors
  QUIET="${QUIET:-false}"
  [[ $QUIET == "true" ]] &&
    local REDIRECT_TO="/dev/null" ||
    local REDIRECT_TO="/dev/tty"

  confluent kafka acl create --allow --service-account $SERVICE_ACCOUNT_ID --operation CREATE --topic '*' &>"$REDIRECT_TO"
  confluent kafka acl create --allow --service-account $SERVICE_ACCOUNT_ID --operation DELETE --topic '*' &>"$REDIRECT_TO"
  confluent kafka acl create --allow --service-account $SERVICE_ACCOUNT_ID --operation WRITE --topic '*' &>"$REDIRECT_TO"
  confluent kafka acl create --allow --service-account $SERVICE_ACCOUNT_ID --operation READ --topic '*' &>"$REDIRECT_TO"
  confluent kafka acl create --allow --service-account $SERVICE_ACCOUNT_ID --operation DESCRIBE --topic '*' &>"$REDIRECT_TO"
  confluent kafka acl create --allow --service-account $SERVICE_ACCOUNT_ID --operation DESCRIBE_CONFIGS --topic '*' &>"$REDIRECT_TO"

  confluent kafka acl create --allow --service-account $SERVICE_ACCOUNT_ID --operation READ --consumer-group '*' &>"$REDIRECT_TO"
  confluent kafka acl create --allow --service-account $SERVICE_ACCOUNT_ID --operation WRITE --consumer-group '*' &>"$REDIRECT_TO"
  confluent kafka acl create --allow --service-account $SERVICE_ACCOUNT_ID --operation CREATE --consumer-group '*' &>"$REDIRECT_TO"
  confluent kafka acl create --allow --service-account $SERVICE_ACCOUNT_ID --operation DESCRIBE --consumer-group '*' &>"$REDIRECT_TO"

  confluent kafka acl create --allow --service-account $SERVICE_ACCOUNT_ID --operation DESCRIBE --transactional-id '*' &>"$REDIRECT_TO"
  confluent kafka acl create --allow --service-account $SERVICE_ACCOUNT_ID --operation WRITE --transactional-id '*' &>"$REDIRECT_TO"
  
  confluent kafka acl create --allow --service-account $SERVICE_ACCOUNT_ID --operation IDEMPOTENT-WRITE --cluster-scope &>"$REDIRECT_TO"
  confluent kafka acl create --allow --service-account $SERVICE_ACCOUNT_ID --operation DESCRIBE --cluster-scope &>"$REDIRECT_TO"

  return 0
}

function ccloud::delete_acls_ccloud_stack() {
  SERVICE_ACCOUNT_ID=$1
  # Setting default QUIET=false to surface potential errors
  QUIET="${QUIET:-false}"
  [[ $QUIET == "true" ]] &&
    local REDIRECT_TO="/dev/null" ||
    local REDIRECT_TO="/dev/tty"

  echo "Deleting ACLs for service account ID $SERVICE_ACCOUNT_ID"

  confluent kafka acl delete --allow --service-account $SERVICE_ACCOUNT_ID --operation CREATE --topic '*' &>"$REDIRECT_TO"
  confluent kafka acl delete --allow --service-account $SERVICE_ACCOUNT_ID --operation DELETE --topic '*' &>"$REDIRECT_TO"
  confluent kafka acl delete --allow --service-account $SERVICE_ACCOUNT_ID --operation WRITE --topic '*' &>"$REDIRECT_TO"
  confluent kafka acl delete --allow --service-account $SERVICE_ACCOUNT_ID --operation READ --topic '*' &>"$REDIRECT_TO"
  confluent kafka acl delete --allow --service-account $SERVICE_ACCOUNT_ID --operation DESCRIBE --topic '*' &>"$REDIRECT_TO"
  confluent kafka acl delete --allow --service-account $SERVICE_ACCOUNT_ID --operation DESCRIBE_CONFIGS --topic '*' &>"$REDIRECT_TO"

  confluent kafka acl delete --allow --service-account $SERVICE_ACCOUNT_ID --operation READ --consumer-group '*' &>"$REDIRECT_TO"
  confluent kafka acl delete --allow --service-account $SERVICE_ACCOUNT_ID --operation WRITE --consumer-group '*' &>"$REDIRECT_TO"
  confluent kafka acl delete --allow --service-account $SERVICE_ACCOUNT_ID --operation CREATE --consumer-group '*' &>"$REDIRECT_TO"
  confluent kafka acl delete --allow --service-account $SERVICE_ACCOUNT_ID --operation DESCRIBE --consumer-group '*' &>"$REDIRECT_TO"

  confluent kafka acl delete --allow --service-account $SERVICE_ACCOUNT_ID --operation DESCRIBE --transactional-id '*' &>"$REDIRECT_TO"
  confluent kafka acl delete --allow --service-account $SERVICE_ACCOUNT_ID --operation WRITE --transactional-id '*' &>"$REDIRECT_TO"

  confluent kafka acl delete --allow --service-account $SERVICE_ACCOUNT_ID --operation IDEMPOTENT-WRITE --cluster-scope &>"$REDIRECT_TO"
  confluent kafka acl delete --allow --service-account $SERVICE_ACCOUNT_ID --operation DESCRIBE --cluster-scope &>"$REDIRECT_TO"

  return 0
}

function ccloud::validate_ccloud_config() {
  [ -z "$1" ] && {
    echo "ccloud::validate_ccloud_config expects one parameter (configuration file with Confluent Cloud connection information)"
    exit 1
  }

  local cfg_file="$1"
  local bootstrap=$(grep "bootstrap\.servers" "$cfg_file" | cut -d'=' -f2-)
  [ -z "$bootstrap" ] && {
    echo "ERROR: Cannot read the 'bootstrap.servers' key-value pair from $cfg_file."
    exit 1;
  }
  return 0;
}

function ccloud::validate_ksqldb_up() {
  [ -z "$1" ] && {
    echo "ccloud::validate_ksqldb_up expects one parameter (ksqldb endpoint)"
    exit 1
  }

  [ $# -gt 1 ] && echo "WARN: ccloud::validate_ksqldb_up function expects one parameter"

  local ksqldb_endpoint=$1

  ccloud::validate_logged_in_cli || exit 1

  local ksqldb_meta=$(confluent ksql cluster list -o json | jq -r 'map(select(.endpoint == "'"$ksqldb_endpoint"'")) | .[]')

  local ksqldb_appid=$(echo "$ksqldb_meta" | jq -r '.id')
  if [[ "$ksqldb_appid" == "" ]]; then
    echo "ERROR: Confluent Cloud ksqlDB endpoint $ksqldb_endpoint is not found. Provision a ksqlDB cluster via the Confluent Cloud UI and add the configuration parameter ksql.endpoint and ksql.basic.auth.user.info into your Confluent Cloud configuration file at $ccloud_config_file and try again."
    exit 1
  fi

  local ksqldb_status=$(echo "$ksqldb_meta" | jq -r '.status')
  if [[ $ksqldb_status != "UP" ]]; then
    echo "ERROR: Confluent Cloud ksqlDB endpoint $ksqldb_endpoint with id $ksqlDBAppId is not in UP state. Troubleshoot and try again."
    exit 1
  fi

  return 0
}

function ccloud::validate_azure_account() {
  AZBLOB_STORAGE_ACCOUNT=$1

  if [[ "$AZBLOB_STORAGE_ACCOUNT" == "default" ]]; then
    echo "ERROR: Azure Blob storage account name cannot be 'default'. Verify the value of the storage account name (did you create one?) in config/demo.cfg, as specified by the parameter AZBLOB_STORAGE_ACCOUNT, and try again."
    exit 1
  fi

  exists=$(az storage account check-name --name $AZBLOB_STORAGE_ACCOUNT | jq -r .reason)
  if [[ "$exists" != "AlreadyExists" ]]; then
    echo "ERROR: Azure Blob storage account name $AZBLOB_STORAGE_ACCOUNT does not exist. Check the value of STORAGE_PROFILE in config/demo.cfg and try again."
    exit 1
  fi
  export AZBLOB_ACCOUNT_KEY=$(az storage account keys list --account-name $AZBLOB_STORAGE_ACCOUNT | jq -r '.[0].value')
  if [[ "$AZBLOB_ACCOUNT_KEY" == "" ]]; then
    echo "ERROR: Cannot get the key for Azure Blob storage account name $AZBLOB_STORAGE_ACCOUNT. Check the value of STORAGE_PROFILE in config/demo.cfg, and your key, and try again."
    exit 1
  fi

  return 0
}

function ccloud::validate_credentials_ksqldb() {
  ksqldb_endpoint=$1
  ccloud_config_file=$2
  credentials=$3

  response=$(curl ${ksqldb_endpoint}/info \
             -H "Content-Type: application/vnd.ksql.v1+json; charset=utf-8" \
             --silent \
             -u $credentials)
  if [[ "$response" =~ "Unauthorized" ]]; then
    echo "ERROR: Authorization failed to the ksqlDB cluster. Check your ksqlDB credentials set in the configuration parameter ksql.basic.auth.user.info in your Confluent Cloud configuration file at $ccloud_config_file and try again."
    exit 1
  fi

  echo "Validated credentials to Confluent Cloud ksqlDB at $ksqldb_endpoint"
  return 0
}

function ccloud::create_connector() {
  file=$1

  echo -e "\nCreating connector from $file\n"

  # About the Confluent CLI command 'confluent connect create':
  # - Typical usage of this CLI would be 'confluent connect create --config <filename>'
  # - However, in this example, the connector's configuration file contains parameters that need to be first substituted
  #   so the CLI command includes eval and heredoc.
  # - The '-vvv' is added for verbose output
  confluent connect create -vvv --config <(eval "cat <<EOF
$(<$file)
EOF
")
  if [[ $? != 0 ]]; then
    echo "ERROR: Exit status was not 0 while creating connector from $file.  Please troubleshoot and try again"
    exit 1
  fi

  return 0
}

function ccloud::validate_connector_up() {
  confluent connect list -o json | jq -e 'map(select(.name == "'"$1"'" and .status == "RUNNING")) | .[]' > /dev/null 2>&1
}

function ccloud::wait_for_connector_up() {
  filename=$1
  maxWait=$2

  connectorName=$(cat $filename | jq -r .name)
  echo "Waiting up to $maxWait seconds for connector $filename ($connectorName) to be RUNNING"
  ccloud::retry $maxWait ccloud::validate_connector_up $connectorName || exit 1
  echo "Connector $filename ($connectorName) is RUNNING"

  return 0
}


function ccloud::validate_ccloud_ksqldb_endpoint_ready() {
  KSQLDB_ENDPOINT=$1

  STATUS=$(confluent ksql cluster list -o json | jq -r 'map(select(.endpoint == "'"$KSQLDB_ENDPOINT"'")) | .[].status' | grep UP)
  if [[ "$STATUS" == "" ]]; then
    return 1
  fi

  return 0
}

function ccloud::validate_ccloud_cluster_ready() {
  confluent kafka topic list &>/dev/null
  return $?
}

function ccloud::validate_topic_exists() {
  topic=$1

  confluent kafka topic describe $topic &>/dev/null
  return $?
}

function ccloud::validate_subject_exists() {
  subject=$1
  sr_url=$2
  sr_credentials=$3

  curl --silent -u $sr_credentials $sr_url/subjects/$subject/versions/latest | jq -r ".subject" | grep $subject > /dev/null
  return $?
}

function ccloud::login_cli(){
  URL=$1
  EMAIL=$2
  PASSWORD=$3

  ccloud::validate_expect_installed

  echo -e "\n# Login"
  OUTPUT=$(
  expect <<END
    log_user 1
    spawn confluent login --url $URL --prompt -vvvv
    expect "Email: "
    send "$EMAIL\r";
    expect "Password: "
    send "$PASSWORD\r";
    expect "Logged in as "
    set result $expect_out(buffer)
END
  )
  echo "$OUTPUT"
  if [[ ! "$OUTPUT" =~ "Logged in as" ]]; then
    echo "Failed to log into your cluster. Please check all parameters and run again."
  fi

  return 0
}

function ccloud::get_service_account() {

  [ -z "$1" ] && {
    echo "ccloud::get_service_account expects one parameter (API Key)"
    exit 1
  }

  [ $# -gt 1 ] && echo "WARN: ccloud::get_service_account function expects one parameter, received two"

  local key="$1"

  serviceAccount=$(confluent api-key list -o json | jq -r -c 'map(select((.key == "'"$key"'"))) | .[].owner_resource_id')
  if [[ "$serviceAccount" == "" ]]; then
    echo "ERROR: Could not associate key $key to a service account. Verify your credentials, ensure the API key has a set resource type, and try again."
    exit 1
  fi
  if ! [[ "$serviceAccount" =~ ^sa-[a-z0-9]+$ ]]; then
    echo "ERROR: $serviceAccount value is not a valid value for a service account. Verify your credentials, ensure the API key has a set resource type, and try again."
    exit 1
  fi

  echo "$serviceAccount"

  return 0
}

function ccloud::create_acls_connector() {
  serviceAccount=$1

  confluent kafka acl create --allow --service-account $serviceAccount --operation DESCRIBE --cluster-scope
  confluent kafka acl create --allow --service-account $serviceAccount --operation CREATE --prefix --topic dlq-lcc
  confluent kafka acl create --allow --service-account $serviceAccount --operation WRITE --prefix --topic dlq-lcc
  confluent kafka acl create --allow --service-account $serviceAccount --operation READ --prefix --consumer-group connect-lcc

  return 0
}

function ccloud::create_acls_control_center() {
  serviceAccount=$1

  echo "Confluent Control Center: creating _confluent-command and ACLs for service account $serviceAccount"
  confluent kafka topic create _confluent-command --partitions 1

  confluent kafka acl create --allow --service-account $serviceAccount --operation WRITE --topic _confluent --prefix
  confluent kafka acl create --allow --service-account $serviceAccount --operation READ --topic _confluent --prefix
  confluent kafka acl create --allow --service-account $serviceAccount --operation CREATE --topic _confluent --prefix

  confluent kafka acl create --allow --service-account $serviceAccount --operation READ --consumer-group _confluent --prefix
  confluent kafka acl create --allow --service-account $serviceAccount --operation WRITE --consumer-group _confluent --prefix
  confluent kafka acl create --allow --service-account $serviceAccount --operation CREATE --consumer-group _confluent --prefix

  return 0
}


function ccloud::create_acls_replicator() {
  serviceAccount=$1
  topic=$2

  confluent kafka acl create --allow --service-account $serviceAccount --operation CREATE --topic $topic
  confluent kafka acl create --allow --service-account $serviceAccount --operation WRITE --topic $topic
  confluent kafka acl create --allow --service-account $serviceAccount --operation READ --topic $topic
  confluent kafka acl create --allow --service-account $serviceAccount --operation DESCRIBE --topic $topic
  confluent kafka acl create --allow --service-account $serviceAccount --operation DESCRIBE-CONFIGS --topic $topic
  confluent kafka acl create --allow --service-account $serviceAccount --operation ALTER-CONFIGS --topic $topic
  confluent kafka acl create --allow --service-account $serviceAccount --operation DESCRIBE --cluster-scope

  return 0
}

function ccloud::create_acls_connect_topics() {
  serviceAccount=$1

  echo "Connect: creating topics and ACLs for service account $serviceAccount"

  TOPIC=connect-demo-configs
  confluent kafka topic create $TOPIC --partitions 1 --config "cleanup.policy=compact"
  confluent kafka acl create --allow --service-account $serviceAccount --operation WRITE --topic $TOPIC --prefix
  confluent kafka acl create --allow --service-account $serviceAccount --operation READ --topic $TOPIC --prefix

  TOPIC=connect-demo-offsets
  confluent kafka topic create $TOPIC --partitions 6 --config "cleanup.policy=compact"
  confluent kafka acl create --allow --service-account $serviceAccount --operation WRITE --topic $TOPIC --prefix
  confluent kafka acl create --allow --service-account $serviceAccount --operation READ --topic $TOPIC --prefix
  
  TOPIC=connect-demo-statuses 
  confluent kafka topic create $TOPIC --partitions 3 --config "cleanup.policy=compact"
  confluent kafka acl create --allow --service-account $serviceAccount --operation WRITE --topic $TOPIC --prefix
  confluent kafka acl create --allow --service-account $serviceAccount --operation READ --topic $TOPIC --prefix
  

  for TOPIC in _confluent-monitoring _confluent-command ; do
    confluent kafka topic create $TOPIC &>/dev/null
    confluent kafka acl create --allow --service-account $serviceAccount --operation WRITE --topic $TOPIC --prefix
    confluent kafka acl create --allow --service-account $serviceAccount --operation READ --topic $TOPIC --prefix
  done
 
  confluent kafka acl create --allow --service-account $serviceAccount --operation READ --consumer-group connect-cloud

  echo "Connectors: creating topics and ACLs for service account $serviceAccount"
  confluent kafka acl create --allow --service-account $serviceAccount --operation READ --consumer-group connect-replicator
  confluent kafka acl create --allow --service-account $serviceAccount --operation describe --cluster-scope

  return 0
}

function ccloud::validate_ccloud_stack_up() {
  CLOUD_KEY=$1
  CONFIG_FILE=$2
  enable_ksqldb=$3

  if [ -z "$enable_ksqldb" ]; then
    enable_ksqldb=true
  fi

  ccloud::validate_environment_set || exit 1
  ccloud::set_kafka_cluster_use_from_api_key "$CLOUD_KEY" || exit 1
  ccloud::validate_schema_registry_up "$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" "$SCHEMA_REGISTRY_URL" || exit 1
  if $enable_ksqldb ; then
    ccloud::validate_ksqldb_up "$KSQLDB_ENDPOINT" || exit 1
    ccloud::validate_credentials_ksqldb "$KSQLDB_ENDPOINT" "$CONFIG_FILE" "$KSQLDB_BASIC_AUTH_USER_INFO" || exit 1
  fi
}

function ccloud::validate_environment_set() {
  confluent environment list | grep '*' &>/dev/null || {
    echo "ERROR: could not determine if environment is set. Run 'confluent environment list' and set 'confluent environment use' and try again"
    exit 1
  }

  return 0
}

function ccloud::set_kafka_cluster_use_from_api_key() {
  [ -z "$1" ] && {
    echo "ccloud::set_kafka_cluster_use_from_api_key expects one parameter (API Key)"
    exit 1
  }

  [ $# -gt 1 ] && echo "WARN: ccloud::set_kafka_cluster_use_from_api_key function expects one parameter, received two"

  local key="$1"

  local kafkaCluster=$(confluent api-key list -o json | jq -r -c 'map(select((.key == "'"$key"'" and .resource_type == "kafka"))) | .[].resource_id')
  if [[ "$kafkaCluster" == "" ]]; then
    echo "ERROR: Could not associate key $key to a Confluent Cloud Kafka cluster. Verify your credentials, ensure the API key has a set resource type, and try again."
    exit 1
  fi

  confluent kafka cluster use $kafkaCluster
  local endpoint=$(confluent kafka cluster describe $kafkaCluster -o json | jq -r ".endpoint" | cut -c 12-)
  echo -e "\nAssociated key $key to Confluent Cloud Kafka cluster $kafkaCluster at $endpoint"

  return 0
}

###
# Deprecated 10/28/2020, use ccloud::set_kafka_cluster_use_from_api_key
###
function ccloud::set_kafka_cluster_use() {
  echo "WARN: set_kafka_cluster_use is deprecated, use ccloud::set_kafka_cluster_use_from_api_key"
  ccloud::set_kafka_cluster_use_from_api_key "$@"
}


#
# ccloud-stack documentation:
# https://docs.confluent.io/platform/current/tutorials/examples/ccloud/docs/ccloud-stack.html
#
function ccloud::create_ccloud_stack() {
  #ccloud::validate_version_cli $CLI_MIN_VERSION || exit 1
  QUIET="${QUIET:-false}"
  REPLICATION_FACTOR=${REPLICATION_FACTOR:-3}
  enable_ksqldb=${1:-false}
  EXAMPLE=${EXAMPLE:-ccloud-stack-function}
  CHECK_CREDIT_CARD="${CHECK_CREDIT_CARD:-false}"

  # Check if credit card is on file, which is required for cluster creation
  if $CHECK_CREDIT_CARD && [[ $(confluent admin payment describe) =~ "not found" ]]; then
    echo "ERROR: No credit card on file. Add a payment method and try again."
    echo "If you are using a cloud provider's Marketplace, see documentation for a workaround: https://docs.confluent.io/platform/current/tutorials/examples/ccloud/docs/ccloud-stack.html#running-with-marketplace"
    exit 1
  fi

  # VINC: added
  if [[ -z "$CLUSTER_CREDS" ]]
  then
    if [[ -z "$SERVICE_ACCOUNT_ID" ]]; then
      # Service Account is not received so it will be created
      local RANDOM_NUM=$((1 + RANDOM % 1000000))
      SERVICE_NAME=${SERVICE_NAME:-"pg-app-$RANDOM_NUM"}
      SERVICE_ACCOUNT_ID=$(ccloud::create_service_account $SERVICE_NAME)
    fi

    if [[ "$SERVICE_NAME" == "" ]]; then
      echo "ERROR: SERVICE_NAME is not defined. If you are providing the SERVICE_ACCOUNT_ID to this function please also provide the SERVICE_NAME"
      exit 1
    fi

    echo "Creating Confluent Cloud stack for service account $SERVICE_NAME, ID: $SERVICE_ACCOUNT_ID."
  fi
  
  if [[ -z "$ENVIRONMENT" ]]; 
  then
    # Environment is not received so it will be created
    ENVIRONMENT_NAME=${ENVIRONMENT_NAME:-"pg-$SERVICE_ACCOUNT_ID-$EXAMPLE"}
    ENVIRONMENT=$(ccloud::create_and_use_environment $ENVIRONMENT_NAME)
    (($? != 0)) && { echo "$ENVIRONMENT"; exit 1; }
  else
    confluent environment use $ENVIRONMENT || exit 1
  fi

  CLUSTER_NAME=${CLUSTER_NAME:-"pg-cluster-$SERVICE_ACCOUNT_ID"}
  CLUSTER_CLOUD="${CLUSTER_CLOUD:-aws}"
  CLUSTER_REGION="${CLUSTER_REGION:-us-west-2}"
  CLUSTER_TYPE="${CLUSTER_TYPE:-basic}"
  CLUSTER=$(ccloud::maybe_create_and_use_cluster "$CLUSTER_NAME" $CLUSTER_CLOUD $CLUSTER_REGION $CLUSTER_TYPE)
  (($? != 0)) && { echo "$CLUSTER"; exit 1; }
  if [[ "$CLUSTER" == "" ]] ; then
    echo "Kafka cluster id is empty"
    echo "ERROR: Could not create cluster. Please troubleshoot."
    exit 1
  fi

  BOOTSTRAP_SERVERS=$(confluent kafka cluster describe $CLUSTER -o json | jq -r ".endpoint" | cut -c 12-)
  NEED_ACLS=0
  # VINC: added
  if [[ -z "$CLUSTER_CREDS" ]]
  then
    CLUSTER_CREDS=$(ccloud::maybe_create_credentials_resource $SERVICE_ACCOUNT_ID $CLUSTER)
    NEED_ACLS=1
  fi

  MAX_WAIT=720
  echo ""
  echo "Waiting up to $MAX_WAIT seconds for Confluent Cloud cluster to be ready"
  ccloud::retry $MAX_WAIT ccloud::validate_ccloud_cluster_ready || exit 1

  # VINC: added
  if [[ $NEED_ACLS -eq 1 ]]
  then
    # Estimating another 80s wait still sometimes required
    WARMUP_TIME=${WARMUP_TIME:-80}
    echo "Sleeping an additional ${WARMUP_TIME} seconds to ensure propagation of all metadata"
    sleep $WARMUP_TIME 

    ccloud::create_acls_all_resources_full_access $SERVICE_ACCOUNT_ID
  fi

  SCHEMA_REGISTRY_GEO="${SCHEMA_REGISTRY_GEO:-us}"
  SCHEMA_REGISTRY=$(ccloud::enable_schema_registry $CLUSTER_CLOUD $SCHEMA_REGISTRY_GEO)
  SCHEMA_REGISTRY_ENDPOINT=$(confluent schema-registry cluster describe -o json | jq -r ".endpoint_url")
  # VINC: added
  if [[ -z "$SCHEMA_REGISTRY_CREDS" ]]
  then
    if [[ -z "$SERVICE_ACCOUNT_ID" ]]; then
      # Service Account is not received so it will be created
      local RANDOM_NUM=$((1 + RANDOM % 1000000))
      SERVICE_NAME=${SERVICE_NAME:-"pg-app-$RANDOM_NUM"}
      SERVICE_ACCOUNT_ID=$(ccloud::create_service_account $SERVICE_NAME)
    fi
    SCHEMA_REGISTRY_CREDS=$(ccloud::maybe_create_credentials_resource $SERVICE_ACCOUNT_ID $SCHEMA_REGISTRY)
  fi
  
  if $enable_ksqldb ; then
    KSQLDB_NAME=${KSQLDB_NAME:-"demo-ksqldb-$SERVICE_ACCOUNT_ID"}
    KSQLDB=$(ccloud::maybe_create_ksqldb_app "$KSQLDB_NAME" $CLUSTER "$CLUSTER_CREDS")
    KSQLDB_ENDPOINT=$(confluent ksql cluster describe $KSQLDB -o json | jq -r ".endpoint")
    KSQLDB_CREDS=$(ccloud::maybe_create_credentials_resource $SERVICE_ACCOUNT_ID $KSQLDB)
    confluent ksql cluster configure-acls $KSQLDB
  fi

  CLOUD_API_KEY=`echo $CLUSTER_CREDS | awk -F: '{print $1}'`
  CLOUD_API_SECRET=`echo $CLUSTER_CREDS | awk -F: '{print $2}'`
  # FIX THIS: added by me
  confluent api-key store "$CLOUD_API_KEY" "$CLOUD_API_SECRET" --resource ${CLUSTER} --force
  confluent api-key use $CLOUD_API_KEY --resource ${CLUSTER}

  if [[ -z "$SKIP_CONFIG_FILE_WRITE" ]]; then
    if [[ -z "$CONFIG_FILE" ]]; then
      CONFIG_FILE="/tmp/tmp.config"
    fi
  
    cat <<EOF > $CONFIG_FILE
# --------------------------------------
# Confluent Cloud connection information
# --------------------------------------
# ENVIRONMENT ID: ${ENVIRONMENT}
# SERVICE ACCOUNT ID: ${SERVICE_ACCOUNT_ID}
# KAFKA CLUSTER ID: ${CLUSTER}
# SCHEMA REGISTRY CLUSTER ID: ${SCHEMA_REGISTRY}
EOF
    if $enable_ksqldb ; then
      cat <<EOF >> $CONFIG_FILE
# KSQLDB APP ID: ${KSQLDB}
EOF
    fi
    cat <<EOF >> $CONFIG_FILE
# --------------------------------------
sasl.mechanism=PLAIN
security.protocol=SASL_SSL
bootstrap.servers=${BOOTSTRAP_SERVERS}
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username='${CLOUD_API_KEY}' password='${CLOUD_API_SECRET}';
basic.auth.credentials.source=USER_INFO
schema.registry.url=${SCHEMA_REGISTRY_ENDPOINT}
basic.auth.user.info=`echo $SCHEMA_REGISTRY_CREDS | awk -F: '{print $1}'`:`echo $SCHEMA_REGISTRY_CREDS | awk -F: '{print $2}'`
replication.factor=${REPLICATION_FACTOR}
EOF
    if $enable_ksqldb ; then
      cat <<EOF >> $CONFIG_FILE
ksql.endpoint=${KSQLDB_ENDPOINT}
ksql.basic.auth.user.info=`echo $KSQLDB_CREDS | awk -F: '{print $1}'`:`echo $KSQLDB_CREDS | awk -F: '{print $2}'`
EOF
    fi

    echo
    echo "Client configuration file saved to: $CONFIG_FILE"
  fi

  return 0
}

function ccloud::destroy_ccloud_stack() {
  if [ $# -eq 0 ];then
    echo "ccloud::destroy_ccloud_stack requires a single parameter, the service account id."
    exit 1
  fi

  SERVICE_ACCOUNT_ID=$1
  ENVIRONMENT=${ENVIRONMENT:-$(ccloud::get_environment_id_from_service_id $SERVICE_ACCOUNT_ID)}

  confluent environment use $ENVIRONMENT || exit 1

  PRESERVE_ENVIRONMENT="${PRESERVE_ENVIRONMENT:-false}"

  ENVIRONMENT_NAME_PREFIX=${ENVIRONMENT_NAME_PREFIX:-"pg-$SERVICE_ACCOUNT_ID"}
  CLUSTER_NAME=${CLUSTER_NAME:-"pg-cluster-$SERVICE_ACCOUNT_ID"}
  CONFIG_FILE=${CONFIG_FILE:-"/tmp/tmp.config"}
  KSQLDB_NAME=${KSQLDB_NAME:-"demo-ksqldb-$SERVICE_ACCOUNT_ID"}

  # Setting default QUIET=false to surface potential errors
  QUIET="${QUIET:-false}"
  [[ $QUIET == "true" ]] && 
    local REDIRECT_TO="/dev/null" ||
    local REDIRECT_TO="/dev/tty"

  echo "Destroying Confluent Cloud stack associated to service account id $SERVICE_ACCOUNT_ID"

  # Delete associated ACLs
  ccloud::delete_acls_ccloud_stack $SERVICE_ACCOUNT_ID

  ksqldb_id_found=$(confluent ksql cluster list -o json | jq -r 'map(select(.name == "'"$KSQLDB_NAME"'")) | .[].id')
  if [[ $ksqldb_id_found != "" ]]; then
    echo "Deleting KSQLDB: $KSQLDB_NAME : $ksqldb_id_found"
    confluent ksql cluster delete $ksqldb_id_found &> "$REDIRECT_TO"
  fi

  # Delete connectors associated to this Kafka cluster, otherwise cluster deletion fails
  local cluster_id=$(confluent kafka cluster list -o json | jq -r 'map(select(.name == "'"$CLUSTER_NAME"'")) | .[].id')
  confluent connect list --cluster $cluster_id -o json | jq -r '.[].id' | xargs -I{} confluent connect delete {}

  echo "Deleting CLUSTER: $CLUSTER_NAME : $cluster_id"
  confluent kafka cluster delete $cluster_id &> "$REDIRECT_TO"

  # Delete API keys associated to the service account
  confluent api-key list --service-account $SERVICE_ACCOUNT_ID -o json | jq -r '.[].key' | xargs -I{} confluent api-key delete {}

  # Delete service account
  confluent iam service-account delete $SERVICE_ACCOUNT_ID &>"$REDIRECT_TO" 

  if [[ $PRESERVE_ENVIRONMENT == "false" ]]; then
    local environment_id=$(confluent environment list -o json | jq -r 'map(select(.name | startswith("'"$ENVIRONMENT_NAME_PREFIX"'"))) | .[].id')
    if [[ "$environment_id" == "" ]]; then
      echo "WARNING: Could not find environment with name that starts with $ENVIRONMENT_NAME_PREFIX (did you create this ccloud-stack reusing an existing environment?)"
    else
      echo "Deleting ENVIRONMENT: prefix $ENVIRONMENT_NAME_PREFIX : $environment_id"
      confluent environment delete $environment_id &> "$REDIRECT_TO"
    fi
  fi
  
  rm -f $CONFIG_FILE

  return 0
}

###############################################################################
# Overview:
#
# This code reads a local Confluent Cloud configuration file
# and writes delta configuration files into ./delta_configs for
# Confluent Platform components and clients connecting to Confluent Cloud.
#
# Confluent Platform Components:
# - Confluent Schema Registry
# - KSQL Data Generator
# - ksqlDB server
# - Confluent Replicator (executable)
# - Confluent Control Center
# - Confluent Metrics Reporter
# - Confluent REST Proxy
# - Kafka Connect
# - Kafka connector
# - Kafka command line tools
#
# Kafka Clients:
# - Java (Producer/Consumer)
# - Java (Streams)
# - librdkafka config
# - Python
# - .NET
# - Go
# - Node.js (https://github.com/Blizzard/node-rdkafka)
# - C++
#
# Documentation for using this script:
#
#   https://docs.confluent.io/current/cloud/connect/auto-generate-configs.html
#
# Arguments:
#
#   CONFIG_FILE, defaults to ~/.ccloud/config
#
# Example CONFIG_FILE at ~/.ccloud/config
#
#   $ cat $HOME/.ccloud/config
#
#   bootstrap.servers=<BROKER ENDPOINT>
#   security.protocol=SASL_SSL
#   sasl.mechanism=PLAIN
#   sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username='<API KEY>' password='<API SECRET>';
#
# If you are using Confluent Cloud Schema Registry, add the following configuration parameters
#
#   basic.auth.credentials.source=USER_INFO
#   basic.auth.user.info=<SR API KEY>:<SR API SECRET>
#   schema.registry.url=https://<SR ENDPOINT>
#
# If you are using Confluent Cloud ksqlDB, add the following configuration parameters
#
#   ksql.endpoint=<ksqlDB ENDPOINT>
#   ksql.basic.auth.user.info=<ksqlDB API KEY>:<ksqlDB API SECRET>
#
################################################################################
function ccloud::generate_configs() {
  CONFIG_FILE=$1
  if [[ -z "$CONFIG_FILE" ]]; then
    CONFIG_FILE=~/.ccloud/config
  fi
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "File $CONFIG_FILE is not found.  Please create this properties file to connect to your Confluent Cloud cluster and then try again"
    echo "See https://docs.confluent.io/current/cloud/connect/auto-generate-configs.html for more information"
    return 1
  fi
  
  echo -e "\nGenerating component configurations from $CONFIG_FILE"
  echo -e "\n(If you want to run any of these components to talk to Confluent Cloud, these are the configurations to add to the properties file for each component)"
  
  # Set permissions
  PERM=600
  if ls --version 2>/dev/null | grep -q 'coreutils' ; then
    # GNU binutils
    PERM=$(stat -c "%a" $CONFIG_FILE)
  else
    # BSD
    PERM=$(stat -f "%OLp" $CONFIG_FILE)
  fi
  
  # Make destination
  DEST="/tmp/delta_configs"
  mkdir -p $DEST
  
  ################################################################################
  # Glean parameters from the Confluent Cloud configuration file
  ################################################################################
  
  # Kafka cluster
  BOOTSTRAP_SERVERS=$( grep "^bootstrap.server" $CONFIG_FILE | awk -F'=' '{print $2;}' )
  BOOTSTRAP_SERVERS=${BOOTSTRAP_SERVERS/\\/}
  SASL_JAAS_CONFIG=$( grep "^sasl.jaas.config" $CONFIG_FILE | cut -d'=' -f2- )
  SASL_JAAS_CONFIG_PROPERTY_FORMAT=${SASL_JAAS_CONFIG/username\\=/username=}
  SASL_JAAS_CONFIG_PROPERTY_FORMAT=${SASL_JAAS_CONFIG_PROPERTY_FORMAT/password\\=/password=}
  CLOUD_KEY=$( echo $SASL_JAAS_CONFIG | awk '{print $3}' | awk -F"'" '$0=$2' )
  CLOUD_SECRET=$( echo $SASL_JAAS_CONFIG | awk '{print $4}' | awk -F"'" '$0=$2' )
  
  # Schema Registry
  BASIC_AUTH_CREDENTIALS_SOURCE=$( grep "^basic.auth.credentials.source" $CONFIG_FILE | awk -F'=' '{print $2;}' )
  SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO=$( grep "^basic.auth.user.info" $CONFIG_FILE | awk -F'=' '{print $2;}' )
  SCHEMA_REGISTRY_URL=$( grep "^schema.registry.url" $CONFIG_FILE | awk -F'=' '{print $2;}' )
  
  # ksqlDB
  KSQLDB_ENDPOINT=$( grep "^ksql.endpoint" $CONFIG_FILE | awk -F'=' '{print $2;}' )
  KSQLDB_BASIC_AUTH_USER_INFO=$( grep "^ksql.basic.auth.user.info" $CONFIG_FILE | awk -F'=' '{print $2;}' )
  
  ################################################################################
  # Build configuration file with Confluent Cloud connection parameters and
  # Confluent Monitoring Interceptors for Streams Monitoring in Confluent Control Center
  ################################################################################
  INTERCEPTORS_CONFIG_FILE=$DEST/interceptors-ccloud.config
  rm -f $INTERCEPTORS_CONFIG_FILE
  echo "# Configuration derived from $CONFIG_FILE" > $INTERCEPTORS_CONFIG_FILE
  while read -r line
  do
    # Skip lines that are commented out
    if [[ ! -z $line && ${line:0:1} == '#' ]]; then
      continue
    fi
    # Skip lines that contain just whitespace
    if [[ -z "${line// }" ]]; then
      continue
    fi
    if [[ ${line:0:9} == 'bootstrap' ]]; then
      line=${line/\\/}
    fi
    echo $line >> $INTERCEPTORS_CONFIG_FILE
  done < "$CONFIG_FILE"
  echo -e "\n# Confluent Monitoring Interceptor specific configuration" >> $INTERCEPTORS_CONFIG_FILE
  while read -r line
  do
    # Skip lines that are commented out
    if [[ ! -z $line && ${line:0:1} == '#' ]]; then
      continue
    fi
    # Skip lines that contain just whitespace
    if [[ -z "${line// }" ]]; then
      continue
    fi
    if [[ ${line:0:9} == 'bootstrap' ]]; then
      line=${line/\\/}
    fi
    if [[ ${line:0:4} == 'sasl' ||
          ${line:0:3} == 'ssl' ||
          ${line:0:8} == 'security' ||
          ${line:0:9} == 'bootstrap' ]]; then
      echo "confluent.monitoring.interceptor.$line" >> $INTERCEPTORS_CONFIG_FILE
    fi
  done < "$CONFIG_FILE"
  chmod $PERM $INTERCEPTORS_CONFIG_FILE
  
  echo -e "\nConfluent Platform Components:"
  
  ################################################################################
  # Confluent Schema Registry instance (local) for Confluent Cloud
  ################################################################################
  SR_CONFIG_DELTA=$DEST/schema-registry-ccloud.delta
  echo "$SR_CONFIG_DELTA"
  rm -f $SR_CONFIG_DELTA
  while read -r line
  do
    if [[ ! -z $line && ${line:0:1} != '#' ]]; then
      if [[ ${line:0:29} != 'basic.auth.credentials.source' && ${line:0:15} != 'schema.registry' ]]; then
        echo "kafkastore.$line" >> $SR_CONFIG_DELTA
      fi
    fi
  done < "$CONFIG_FILE"
  chmod $PERM $SR_CONFIG_DELTA
  
  ################################################################################
  # Confluent Replicator (executable) for Confluent Cloud
  ################################################################################
  REPLICATOR_PRODUCER_DELTA=$DEST/replicator-to-ccloud-producer.delta
  echo "$REPLICATOR_PRODUCER_DELTA"
  rm -f $REPLICATOR_PRODUCER_DELTA
  cp $INTERCEPTORS_CONFIG_FILE $REPLICATOR_PRODUCER_DELTA
  echo -e "\n# Confluent Replicator (executable) specific configuration" >> $REPLICATOR_PRODUCER_DELTA
  echo "interceptor.classes=io.confluent.monitoring.clients.interceptor.MonitoringProducerInterceptor" >> $REPLICATOR_PRODUCER_DELTA
  REPLICATOR_SASL_JAAS_CONFIG=$SASL_JAAS_CONFIG
  REPLICATOR_SASL_JAAS_CONFIG=${REPLICATOR_SASL_JAAS_CONFIG//\\=/=}
  REPLICATOR_SASL_JAAS_CONFIG=${REPLICATOR_SASL_JAAS_CONFIG//\"/\\\"}
  chmod $PERM $REPLICATOR_PRODUCER_DELTA
  
  ################################################################################
  # ksqlDB Server runs locally and connects to Confluent Cloud
  ################################################################################
  KSQLDB_SERVER_DELTA=$DEST/ksqldb-server-ccloud.delta
  echo "$KSQLDB_SERVER_DELTA"
  rm -f $KSQLDB_SERVER_DELTA
  cp $INTERCEPTORS_CONFIG_FILE $KSQLDB_SERVER_DELTA
  echo -e "\n# ksqlDB Server specific configuration" >> $KSQLDB_SERVER_DELTA
  echo "producer.interceptor.classes=io.confluent.monitoring.clients.interceptor.MonitoringProducerInterceptor" >> $KSQLDB_SERVER_DELTA
  echo "consumer.interceptor.classes=io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor" >> $KSQLDB_SERVER_DELTA
  echo "ksql.streams.producer.retries=2147483647" >> $KSQLDB_SERVER_DELTA
  echo "ksql.streams.producer.confluent.batch.expiry.ms=9223372036854775807" >> $KSQLDB_SERVER_DELTA
  echo "ksql.streams.producer.request.timeout.ms=300000" >> $KSQLDB_SERVER_DELTA
  echo "ksql.streams.producer.max.block.ms=9223372036854775807" >> $KSQLDB_SERVER_DELTA
  echo "ksql.streams.replication.factor=3" >> $KSQLDB_SERVER_DELTA
  echo "ksql.internal.topic.replicas=3" >> $KSQLDB_SERVER_DELTA
  echo "ksql.sink.replicas=3" >> $KSQLDB_SERVER_DELTA
  echo -e "\n# Confluent Schema Registry configuration for ksqlDB Server" >> $KSQLDB_SERVER_DELTA
  while read -r line
  do
    if [[ ${line:0:29} == 'basic.auth.credentials.source' ]]; then
      echo "ksql.schema.registry.$line" >> $KSQLDB_SERVER_DELTA
    elif [[ ${line:0:15} == 'schema.registry' ]]; then
      echo "ksql.$line" >> $KSQLDB_SERVER_DELTA
    fi
  done < $CONFIG_FILE
  chmod $PERM $KSQLDB_SERVER_DELTA
  
  ################################################################################
  # KSQL DataGen for Confluent Cloud
  ################################################################################
  KSQL_DATAGEN_DELTA=$DEST/ksql-datagen.delta
  echo "$KSQL_DATAGEN_DELTA"
  rm -f $KSQL_DATAGEN_DELTA
  cp $INTERCEPTORS_CONFIG_FILE $KSQL_DATAGEN_DELTA
  echo -e "\n# KSQL DataGen specific configuration" >> $KSQL_DATAGEN_DELTA
  echo "interceptor.classes=io.confluent.monitoring.clients.interceptor.MonitoringProducerInterceptor" >> $KSQL_DATAGEN_DELTA
  echo -e "\n# Confluent Schema Registry configuration for KSQL DataGen" >> $KSQL_DATAGEN_DELTA
  while read -r line
  do
    if [[ ${line:0:29} == 'basic.auth.credentials.source' ]]; then
      echo "ksql.schema.registry.$line" >> $KSQL_DATAGEN_DELTA
    elif [[ ${line:0:15} == 'schema.registry' ]]; then
      echo "ksql.$line" >> $KSQL_DATAGEN_DELTA
    fi
  done < $CONFIG_FILE
  chmod $PERM $KSQL_DATAGEN_DELTA
  
  ################################################################################
  # Confluent Control Center runs locally, monitors Confluent Cloud, and uses Confluent Cloud cluster as the backstore
  ################################################################################
  C3_DELTA=$DEST/control-center-ccloud.delta
  echo "$C3_DELTA"
  rm -f $C3_DELTA
  echo -e "\n# Confluent Control Center specific configuration" >> $C3_DELTA
  while read -r line
    do
    if [[ ! -z $line && ${line:0:1} != '#' ]]; then
      if [[ ${line:0:9} == 'bootstrap' ]]; then
        line=${line/\\/}
        echo "$line" >> $C3_DELTA
      fi
      if [[ ${line:0:4} == 'sasl' || ${line:0:3} == 'ssl' || ${line:0:8} == 'security' ]]; then
        echo "confluent.controlcenter.streams.$line" >> $C3_DELTA
      fi
    fi
  done < "$CONFIG_FILE"
  # max.message.bytes is enforced to 8MB in Confluent Cloud
  echo "confluent.metrics.topic.max.message.bytes=8388608" >> $C3_DELTA
  echo -e "\n# Confluent Schema Registry configuration for Confluent Control Center" >> $C3_DELTA
  while read -r line
  do
    if [[ ${line:0:29} == 'basic.auth.credentials.source' ]]; then
      echo "confluent.controlcenter.schema.registry.$line" >> $C3_DELTA
    elif [[ ${line:0:15} == 'schema.registry' ]]; then
      echo "confluent.controlcenter.$line" >> $C3_DELTA
    fi
  done < $CONFIG_FILE
  chmod $PERM $C3_DELTA
  
  ################################################################################
  # Confluent Metrics Reporter to Confluent Cloud
  ################################################################################
  METRICS_REPORTER_DELTA=$DEST/metrics-reporter.delta
  echo "$METRICS_REPORTER_DELTA"
  rm -f $METRICS_REPORTER_DELTA
  echo "metric.reporters=io.confluent.metrics.reporter.ConfluentMetricsReporter" >> $METRICS_REPORTER_DELTA
  echo "confluent.metrics.reporter.topic.replicas=3" >> $METRICS_REPORTER_DELTA
  while read -r line
    do
    if [[ ! -z $line && ${line:0:1} != '#' ]]; then
      if [[ ${line:0:9} == 'bootstrap' || ${line:0:4} == 'sasl' || ${line:0:3} == 'ssl' || ${line:0:8} == 'security' ]]; then
        echo "confluent.metrics.reporter.$line" >> $METRICS_REPORTER_DELTA
      fi
    fi
  done < "$CONFIG_FILE"
  chmod $PERM $METRICS_REPORTER_DELTA
  
  ################################################################################
  # Confluent REST Proxy to Confluent Cloud
  ################################################################################
  REST_PROXY_DELTA=$DEST/rest-proxy.delta
  echo "$REST_PROXY_DELTA"
  rm -f $REST_PROXY_DELTA
  while read -r line
    do
    if [[ ! -z $line && ${line:0:1} != '#' ]]; then
      if [[ ${line:0:9} == 'bootstrap' || ${line:0:4} == 'sasl' || ${line:0:3} == 'ssl' || ${line:0:8} == 'security' ]]; then
        echo "$line" >> $REST_PROXY_DELTA
        echo "client.$line" >> $REST_PROXY_DELTA
      fi
    fi
  done < "$CONFIG_FILE"
  echo -e "\n# Confluent Schema Registry configuration for REST Proxy" >> $REST_PROXY_DELTA
  while read -r line
  do
    if [[ ${line:0:29} == 'basic.auth.credentials.source' || ${line:0:36} == 'schema.registry.basic.auth.user.info' ]]; then
      echo "client.$line" >> $REST_PROXY_DELTA
    elif [[ ${line:0:19} == 'schema.registry.url' ]]; then
      echo "$line" >> $REST_PROXY_DELTA
    fi
  done < $CONFIG_FILE
  chmod $PERM $REST_PROXY_DELTA
  
  ################################################################################
  # Kafka Connect runs locally and connects to Confluent Cloud
  ################################################################################
  CONNECT_DELTA=$DEST/connect-ccloud.delta
  echo "$CONNECT_DELTA"
  rm -f $CONNECT_DELTA
  cat <<EOF > $CONNECT_DELTA
# Configuration for embedded admin client
replication.factor=3
config.storage.replication.factor=3
offset.storage.replication.factor=3
status.storage.replication.factor=3

EOF
  while read -r line
    do
    if [[ ! -z $line && ${line:0:1} != '#' ]]; then
      if [[ ${line:0:9} == 'bootstrap' ]]; then
        line=${line/\\/}
        echo "$line" >> $CONNECT_DELTA
      fi
      if [[ ${line:0:4} == 'sasl' || ${line:0:3} == 'ssl' || ${line:0:8} == 'security' ]]; then
        echo "$line" >> $CONNECT_DELTA
      fi
    fi
  done < "$CONFIG_FILE"
  
  for prefix in "producer" "consumer" "producer.confluent.monitoring.interceptor" "consumer.confluent.monitoring.interceptor" ; do
  
  echo -e "\n# Configuration for embedded $prefix" >> $CONNECT_DELTA
  while read -r line
    do
    if [[ ! -z $line && ${line:0:1} != '#' ]]; then
      if [[ ${line:0:9} == 'bootstrap' ]]; then
        line=${line/\\/}
      fi
      if [[ ${line:0:4} == 'sasl' || ${line:0:3} == 'ssl' || ${line:0:8} == 'security' ]]; then
        echo "${prefix}.$line" >> $CONNECT_DELTA
      fi
    fi
  done < "$CONFIG_FILE"
  
  done
  
  
  cat <<EOF >> $CONNECT_DELTA

# Confluent Schema Registry for Kafka Connect
value.converter=io.confluent.connect.avro.AvroConverter
value.converter.basic.auth.credentials.source=$BASIC_AUTH_CREDENTIALS_SOURCE
value.converter.schema.registry.basic.auth.user.info=$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO
value.converter.schema.registry.url=$SCHEMA_REGISTRY_URL
EOF
  chmod $PERM $CONNECT_DELTA
  
  ################################################################################
  # Kafka connector
  ################################################################################
  CONNECTOR_DELTA=$DEST/connector-ccloud.delta
  echo "$CONNECTOR_DELTA"
  rm -f $CONNECTOR_DELTA
  cat <<EOF >> $CONNECTOR_DELTA
// Confluent Schema Registry for Kafka connectors
value.converter=io.confluent.connect.avro.AvroConverter
value.converter.basic.auth.credentials.source=$BASIC_AUTH_CREDENTIALS_SOURCE
value.converter.schema.registry.basic.auth.user.info=$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO
value.converter.schema.registry.url=$SCHEMA_REGISTRY_URL
EOF
  chmod $PERM $CONNECTOR_DELTA
  
  ################################################################################
  # AK command line tools
  ################################################################################
  AK_TOOLS_DELTA=$DEST/ak-tools-ccloud.delta
  echo "$AK_TOOLS_DELTA"
  rm -f $AK_TOOLS_DELTA
  cp $CONFIG_FILE $AK_TOOLS_DELTA
  chmod $PERM $AK_TOOLS_DELTA
  
  
  echo -e "\nKafka Clients:"
  
  ################################################################################
  # Java (Producer/Consumer)
  ################################################################################
  JAVA_PC_CONFIG=$DEST/java_producer_consumer.delta
  echo "$JAVA_PC_CONFIG"
  rm -f $JAVA_PC_CONFIG
  
  cat <<EOF >> $JAVA_PC_CONFIG
import java.util.Properties;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.clients.producer.ConsumerConfig;
import org.apache.kafka.common.config.SaslConfigs;

Properties props = new Properties();

// Basic Confluent Cloud Connectivity
props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, "$BOOTSTRAP_SERVERS");
props.put(ProducerConfig.REPLICATION_FACTOR_CONFIG, 3);
props.put(ProducerConfig.SECURITY_PROTOCOL_CONFIG, "SASL_SSL");
props.put(SaslConfigs.SASL_MECHANISM, "PLAIN");
props.put(SaslConfigs.SASL_JAAS_CONFIG, "$SASL_JAAS_CONFIG");

// Confluent Schema Registry for Java
props.put("basic.auth.credentials.source", "$BASIC_AUTH_CREDENTIALS_SOURCE");
props.put("schema.registry.basic.auth.user.info", "$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO");
props.put("schema.registry.url", "$SCHEMA_REGISTRY_URL");

// Optimize Performance for Confluent Cloud
props.put(ProducerConfig.RETRIES_CONFIG, 2147483647);
props.put("producer.confluent.batch.expiry.ms", 9223372036854775807);
props.put(ProducerConfig.REQUEST_TIMEOUT_MS_CONFIG, 300000);
props.put(ProducerConfig.MAX_BLOCK_MS_CONFIG, 9223372036854775807);

// Required for Streams Monitoring in Confluent Control Center
props.put(ProducerConfig.INTERCEPTOR_CLASSES_CONFIG, "io.confluent.monitoring.clients.interceptor.MonitoringProducerInterceptor");
props.put(ProducerConfig.INTERCEPTOR_CLASSES_CONFIG + ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, confluent.monitoring.interceptor.bootstrap.servers, "$BOOTSTRAP_SERVERS");
props.put(ProducerConfig.INTERCEPTOR_CLASSES_CONFIG + ProducerConfig.SECURITY_PROTOCOL_CONFIG, "SASL_SSL");
props.put(ProducerConfig.INTERCEPTOR_CLASSES_CONFIG + SaslConfigs.SASL_MECHANISM, "PLAIN");
props.put(ProducerConfig.INTERCEPTOR_CLASSES_CONFIG + SaslConfigs.SASL_JAAS_CONFIG, "$SASL_JAAS_CONFIG");
props.put(ConsumerConfig.INTERCEPTOR_CLASSES_CONFIG, "io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor");
props.put(ConsumerConfig.INTERCEPTOR_CLASSES_CONFIG + ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, confluent.monitoring.interceptor.bootstrap.servers, "$BOOTSTRAP_SERVERS");
props.put(ConsumerConfig.INTERCEPTOR_CLASSES_CONFIG + ProducerConfig.SECURITY_PROTOCOL_CONFIG, "SASL_SSL");
props.put(ConsumerConfig.INTERCEPTOR_CLASSES_CONFIG + SaslConfigs.SASL_MECHANISM, "PLAIN");
props.put(ConsumerConfig.INTERCEPTOR_CLASSES_CONFIG + SaslConfigs.SASL_JAAS_CONFIG, "$SASL_JAAS_CONFIG");

// .... additional configuration settings
EOF
  chmod $PERM $JAVA_PC_CONFIG
  
  ################################################################################
  # Java (Streams)
  ################################################################################
  JAVA_STREAMS_CONFIG=$DEST/java_streams.delta
  echo "$JAVA_STREAMS_CONFIG"
  rm -f $JAVA_STREAMS_CONFIG
  
  cat <<EOF >> $JAVA_STREAMS_CONFIG
import java.util.Properties;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.clients.producer.ConsumerConfig;
import org.apache.kafka.common.config.SaslConfigs;
import org.apache.kafka.streams.StreamsConfig;

Properties props = new Properties();

// Basic Confluent Cloud Connectivity
props.put(StreamsConfig.BOOTSTRAP_SERVERS_CONFIG, "$BOOTSTRAP_SERVERS");
props.put(StreamsConfig.REPLICATION_FACTOR_CONFIG, 3);
props.put(StreamsConfig.SECURITY_PROTOCOL_CONFIG, "SASL_SSL");
props.put(SaslConfigs.SASL_MECHANISM, "PLAIN");
props.put(SaslConfigs.SASL_JAAS_CONFIG, "$SASL_JAAS_CONFIG");

// Confluent Schema Registry for Java
props.put("basic.auth.credentials.source", "$BASIC_AUTH_CREDENTIALS_SOURCE");
props.put("schema.registry.basic.auth.user.info", "$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO");
props.put("schema.registry.url", "$SCHEMA_REGISTRY_URL");

// Optimize Performance for Confluent Cloud
props.put(StreamsConfig.producerPrefix(ProducerConfig.RETRIES_CONFIG), 2147483647);
props.put("producer.confluent.batch.expiry.ms", 9223372036854775807);
props.put(StreamsConfig.producerPrefix(ProducerConfig.REQUEST_TIMEOUT_MS_CONFIG), 300000);
props.put(StreamsConfig.producerPrefix(ProducerConfig.MAX_BLOCK_MS_CONFIG), 9223372036854775807);

// Required for Streams Monitoring in Confluent Control Center
props.put(StreamsConfig.PRODUCER_PREFIX + ProducerConfig.INTERCEPTOR_CLASSES_CONFIG, "io.confluent.monitoring.clients.interceptor.MonitoringProducerInterceptor");
props.put(StreamsConfig.PRODUCER_PREFIX + ProducerConfig.INTERCEPTOR_CLASSES_CONFIG + StreamsConfig.BOOTSTRAP_SERVERS_CONFIG, confluent.monitoring.interceptor.bootstrap.servers, "$BOOTSTRAP_SERVERS");
props.put(StreamsConfig.PRODUCER_PREFIX + ProducerConfig.INTERCEPTOR_CLASSES_CONFIG + StreamsConfig.SECURITY_PROTOCOL_CONFIG, "SASL_SSL");
props.put(StreamsConfig.PRODUCER_PREFIX + ProducerConfig.INTERCEPTOR_CLASSES_CONFIG + SaslConfigs.SASL_MECHANISM, "PLAIN");
props.put(StreamsConfig.PRODUCER_PREFIX + ProducerConfig.INTERCEPTOR_CLASSES_CONFIG + SaslConfigs.SASL_JAAS_CONFIG, "$SASL_JAAS_CONFIG");
props.put(StreamsConfig.CONSUMER_PREFIX + ConsumerConfig.INTERCEPTOR_CLASSES_CONFIG, "io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor");
props.put(StreamsConfig.CONSUMER_PREFIX + ConsumerConfig.INTERCEPTOR_CLASSES_CONFIG + StreamsConfig.BOOTSTRAP_SERVERS_CONFIG, confluent.monitoring.interceptor.bootstrap.servers, "$BOOTSTRAP_SERVERS");
props.put(StreamsConfig.CONSUMER_PREFIX + ConsumerConfig.INTERCEPTOR_CLASSES_CONFIG + StreamsConfig.SECURITY_PROTOCOL_CONFIG, "SASL_SSL");
props.put(StreamsConfig.CONSUMER_PREFIX + ConsumerConfig.INTERCEPTOR_CLASSES_CONFIG + SaslConfigs.SASL_MECHANISM, "PLAIN");
props.put(StreamsConfig.CONSUMER_PREFIX + ConsumerConfig.INTERCEPTOR_CLASSES_CONFIG + SaslConfigs.SASL_JAAS_CONFIG, "$SASL_JAAS_CONFIG");

// .... additional configuration settings
EOF
  chmod $PERM $JAVA_STREAMS_CONFIG
  
  ################################################################################
  # librdkafka
  ################################################################################
  LIBRDKAFKA_CONFIG=$DEST/librdkafka.delta
  echo "$LIBRDKAFKA_CONFIG"
  rm -f $LIBRDKAFKA_CONFIG
  
  cat <<EOF >> $LIBRDKAFKA_CONFIG
bootstrap.servers="$BOOTSTRAP_SERVERS"
security.protocol=SASL_SSL
sasl.mechanisms=PLAIN
sasl.username="$CLOUD_KEY"
sasl.password="$CLOUD_SECRET"
schema.registry.url="$SCHEMA_REGISTRY_URL"
basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO"
EOF
  chmod $PERM $LIBRDKAFKA_CONFIG
  
  ################################################################################
  # Python
  ################################################################################
  PYTHON_CONFIG=$DEST/python.delta
  echo "$PYTHON_CONFIG"
  rm -f $PYTHON_CONFIG
  
  cat <<EOF >> $PYTHON_CONFIG
from confluent_kafka import Producer, Consumer, KafkaError

producer = Producer({
           'bootstrap.servers': '$BOOTSTRAP_SERVERS',
           'broker.version.fallback': '0.10.0.0',
           'api.version.fallback.ms': 0,
           'sasl.mechanisms': 'PLAIN',
           'security.protocol': 'SASL_SSL',
           'sasl.username': '$CLOUD_KEY',
           'sasl.password': '$CLOUD_SECRET',
           // 'ssl.ca.location': '/usr/local/etc/openssl/cert.pem', // varies by distro
           'plugin.library.paths': 'monitoring-interceptor',
           // .... additional configuration settings
})

consumer = Consumer({
           'bootstrap.servers': '$BOOTSTRAP_SERVERS',
           'broker.version.fallback': '0.10.0.0',
           'api.version.fallback.ms': 0,
           'sasl.mechanisms': 'PLAIN',
           'security.protocol': 'SASL_SSL',
           'sasl.username': '$CLOUD_KEY',
           'sasl.password': '$CLOUD_SECRET',
           // 'ssl.ca.location': '/usr/local/etc/openssl/cert.pem', // varies by distro
           'plugin.library.paths': 'monitoring-interceptor',
           // .... additional configuration settings
})
EOF
  chmod $PERM $PYTHON_CONFIG
  
  ################################################################################
  # .NET 
  ################################################################################
  DOTNET_CONFIG=$DEST/dotnet.delta
  echo "$DOTNET_CONFIG"
  rm -f $DOTNET_CONFIG
  
  cat <<EOF >> $DOTNET_CONFIG
using Confluent.Kafka;

var producerConfig = new Dictionary<string, object>
{
    { "bootstrap.servers", "$BOOTSTRAP_SERVERS" },
    { "broker.version.fallback", "0.10.0.0" },
    { "api.version.fallback.ms", 0 },
    { "sasl.mechanisms", "PLAIN" },
    { "security.protocol", "SASL_SSL" },
    { "sasl.username", "$CLOUD_KEY" },
    { "sasl.password", "$CLOUD_SECRET" },
    // { "ssl.ca.location", "/usr/local/etc/openssl/cert.pem" }, // varies by distro
    { “plugin.library.paths”, “monitoring-interceptor”},
    // .... additional configuration settings
};

var consumerConfig = new Dictionary<string, object>
{
    { "bootstrap.servers", "$BOOTSTRAP_SERVERS" },
    { "broker.version.fallback", "0.10.0.0" },
    { "api.version.fallback.ms", 0 },
    { "sasl.mechanisms", "PLAIN" },
    { "security.protocol", "SASL_SSL" },
    { "sasl.username", "$CLOUD_KEY" },
    { "sasl.password", "$CLOUD_SECRET" },
    // { "ssl.ca.location", "/usr/local/etc/openssl/cert.pem" }, // varies by distro
    { “plugin.library.paths”, “monitoring-interceptor”},
    // .... additional configuration settings
};
EOF
  chmod $PERM $DOTNET_CONFIG
  
  ################################################################################
  # Go
  ################################################################################
  GO_CONFIG=$DEST/go.delta
  echo "$GO_CONFIG"
  rm -f $GO_CONFIG
  
  cat <<EOF >> $GO_CONFIG
import (
  "github.com/confluentinc/confluent-kafka-go/kafka"
  
 
producer, err := kafka.NewProducer(&kafka.ConfigMap{
           "bootstrap.servers": "$BOOTSTRAP_SERVERS",
          "broker.version.fallback": "0.10.0.0",
          "api.version.fallback.ms": 0,
          "sasl.mechanisms": "PLAIN",
          "security.protocol": "SASL_SSL",
          "sasl.username": "$CLOUD_KEY",
          "sasl.password": "$CLOUD_SECRET",
                 // "ssl.ca.location": "/usr/local/etc/openssl/cert.pem", // varies by distro
                 "plugin.library.paths": "monitoring-interceptor",
                 // .... additional configuration settings
                 })
 
consumer, err := kafka.NewConsumer(&kafka.ConfigMap{
     "bootstrap.servers": "$BOOTSTRAP_SERVERS",
       "broker.version.fallback": "0.10.0.0",
       "api.version.fallback.ms": 0,
       "sasl.mechanisms": "PLAIN",
       "security.protocol": "SASL_SSL",
       "sasl.username": "$CLOUD_KEY",
       "sasl.password": "$CLOUD_SECRET",
                 // "ssl.ca.location": "/usr/local/etc/openssl/cert.pem", // varies by distro
       "session.timeout.ms": 6000,
                 "plugin.library.paths": "monitoring-interceptor",
                 // .... additional configuration settings
                 })
EOF
  chmod $PERM $GO_CONFIG
  
  ################################################################################
  # Node.js
  ################################################################################
  NODE_CONFIG=$DEST/node.delta
  echo "$NODE_CONFIG"
  rm -f $NODE_CONFIG
  
  cat <<EOF >> $NODE_CONFIG
var Kafka = require('node-rdkafka');

var producer = new Kafka.Producer({
    'metadata.broker.list': '$BOOTSTRAP_SERVERS',
    'sasl.mechanisms': 'PLAIN',
    'security.protocol': 'SASL_SSL',
    'sasl.username': '$CLOUD_KEY',
    'sasl.password': '$CLOUD_SECRET',
     // 'ssl.ca.location': '/usr/local/etc/openssl/cert.pem', // varies by distro
    'plugin.library.paths': 'monitoring-interceptor',
    // .... additional configuration settings
  });

var consumer = Kafka.KafkaConsumer.createReadStream({
    'metadata.broker.list': '$BOOTSTRAP_SERVERS',
    'sasl.mechanisms': 'PLAIN',
    'security.protocol': 'SASL_SSL',
    'sasl.username': '$CLOUD_KEY',
    'sasl.password': '$CLOUD_SECRET',
     // 'ssl.ca.location': '/usr/local/etc/openssl/cert.pem', // varies by distro
    'plugin.library.paths': 'monitoring-interceptor',
    // .... additional configuration settings
  }, {}, {
    topics: '<topic name>',
    waitInterval: 0,
    objectMode: false
});
EOF
  chmod $PERM $NODE_CONFIG
  
  ################################################################################
  # C++
  ################################################################################
  CPP_CONFIG=$DEST/cpp.delta
  echo "$CPP_CONFIG"
  rm -f $CPP_CONFIG
  
  cat <<EOF >> $CPP_CONFIG
#include <librdkafka/rdkafkacpp.h>

RdKafka::Conf *producerConfig = RdKafka::Conf::create(RdKafka::Conf::CONF_GLOBAL);
if (producerConfig->set("metadata.broker.list", "$BOOTSTRAP_SERVERS", errstr) != RdKafka::Conf::CONF_OK ||
    producerConfig->set("sasl.mechanisms", "PLAIN", errstr) != RdKafka::Conf::CONF_OK ||
    producerConfig->set("security.protocol", "SASL_SSL", errstr) != RdKafka::Conf::CONF_OK ||
    producerConfig->set("sasl.username", "$CLOUD_KEY", errstr) != RdKafka::Conf::CONF_OK ||
    producerConfig->set("sasl.password", "$CLOUD_SECRET", errstr) != RdKafka::Conf::CONF_OK ||
    // producerConfig->set("ssl.ca.location", "/usr/local/etc/openssl/cert.pem", errstr) != RdKafka::Conf::CONF_OK || // varies by distro
    producerConfig->set("plugin.library.paths", "monitoring-interceptor", errstr) != RdKafka::Conf::CONF_OK ||
    // .... additional configuration settings
   ) {
        std::cerr << "Configuration failed: " << errstr << std::endl;
        exit(1);
}
RdKafka::Producer *producer = RdKafka::Producer::create(producerConfig, errstr);

RdKafka::Conf *consumerConfig = RdKafka::Conf::create(RdKafka::Conf::CONF_GLOBAL);
if (consumerConfig->set("metadata.broker.list", "$BOOTSTRAP_SERVERS", errstr) != RdKafka::Conf::CONF_OK ||
    consumerConfig->set("sasl.mechanisms", "PLAIN", errstr) != RdKafka::Conf::CONF_OK ||
    consumerConfig->set("security.protocol", "SASL_SSL", errstr) != RdKafka::Conf::CONF_OK ||
    consumerConfig->set("sasl.username", "$CLOUD_KEY", errstr) != RdKafka::Conf::CONF_OK ||
    consumerConfig->set("sasl.password", "$CLOUD_SECRET", errstr) != RdKafka::Conf::CONF_OK ||
    // consumerConfig->set("ssl.ca.location", "/usr/local/etc/openssl/cert.pem", errstr) != RdKafka::Conf::CONF_OK || // varies by distro
    consumerConfig->set("plugin.library.paths", "monitoring-interceptor", errstr) != RdKafka::Conf::CONF_OK ||
    // .... additional configuration settings
   ) {
        std::cerr << "Configuration failed: " << errstr << std::endl;
        exit(1);
}
RdKafka::Consumer *consumer = RdKafka::Consumer::create(consumerConfig, errstr);
EOF
  chmod $PERM $CPP_CONFIG
  
  ################################################################################
  # ENV
  ################################################################################
  ENV_CONFIG=$DEST/env.delta
  echo "$ENV_CONFIG"
  rm -f $ENV_CONFIG
  
  cat <<EOF >> $ENV_CONFIG
export BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS"
export SASL_JAAS_CONFIG="$SASL_JAAS_CONFIG"
export SASL_JAAS_CONFIG_PROPERTY_FORMAT="$SASL_JAAS_CONFIG_PROPERTY_FORMAT"
export REPLICATOR_SASL_JAAS_CONFIG="$REPLICATOR_SASL_JAAS_CONFIG"
export BASIC_AUTH_CREDENTIALS_SOURCE="$BASIC_AUTH_CREDENTIALS_SOURCE"
export SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO"
export SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL"
export CLOUD_KEY="$CLOUD_KEY"
export CLOUD_SECRET="$CLOUD_SECRET"
export KSQLDB_ENDPOINT="$KSQLDB_ENDPOINT"
export KSQLDB_BASIC_AUTH_USER_INFO="$KSQLDB_BASIC_AUTH_USER_INFO"
EOF
  chmod $PERM $ENV_CONFIG

  return 0
}

##############################################
# These are some duplicate functions from 
#  helper.sh to decouple the script files.  In 
#  the future we can work to remove this 
#  duplication if necessary
##############################################
function ccloud::retry() {
    local -r -i max_wait="$1"; shift
    local -r cmd="$@"

    local -i sleep_interval=5
    local -i curr_wait=0

    until $cmd
    do
        if (( curr_wait >= max_wait ))
        then
            echo "ERROR: Failed after $curr_wait seconds. Please troubleshoot and run again."
            return 1
        else
            printf "."
            curr_wait=$((curr_wait+sleep_interval))
            sleep $sleep_interval
        fi
    done
    printf "\n"
}
function ccloud::version_gt() { 
  test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1";
}


###############
## ccloud-utils functions
## END
##############
