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

# https://stackoverflow.com/a/24067243
function version_gt() {
  test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1";
}

function set_kafka_client_tag()
{
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
    export TAG=6.2.1
    # to handle ubi8 images
    export TAG_BASE=$TAG
    if [ -z "$CP_KAFKA_IMAGE" ]
    then
      log "💫 Using default CP version $TAG"
      log "🎓 set TAG environment variable to specify different version, see https://kafka-docker-playground.io/#/how-to-use?id=🎯-for-confluent-platform-cp"
    fi
    export CP_KAFKA_IMAGE=cp-server
    export CP_BASE_IMAGE=cp-base-new
    export CP_KSQL_IMAGE=cp-ksqldb-server
    export CP_KSQL_CLI_IMAGE=ksqldb-cli:latest
    export CP_CONNECT_IMAGE=cp-server-connect-base
    set_kafka_client_tag
else
    if [ -z "$CP_KAFKA_IMAGE" ]
    then
      log "🚀 Using specified CP version $TAG"
    fi
    # to handle ubi8 images
    export TAG_BASE=$(echo $TAG | cut -d "-" -f1)
    first_version=${TAG_BASE}
    second_version=5.3.99
    if version_gt $first_version 5.3.99; then
        export CP_KAFKA_IMAGE=cp-server
        export CP_CONNECT_IMAGE=cp-server-connect-base
    else
        export CP_KAFKA_IMAGE=cp-enterprise-kafka
        export CP_CONNECT_IMAGE=cp-kafka-connect-base
    fi
    second_version=5.3.99
    if version_gt $first_version $second_version; then
        export CP_BASE_IMAGE=cp-base-new
    else
        export CP_BASE_IMAGE=cp-base
    fi
    second_version=5.4.99
    if version_gt $first_version $second_version; then
        export CP_KSQL_IMAGE=cp-ksqldb-server
        export CP_KSQL_CLI_IMAGE=ksqldb-cli:latest
    else
        export CP_KSQL_IMAGE=cp-ksql-server
        export CP_KSQL_CLI_IMAGE=cp-ksql-cli:${TAG_BASE}
    fi
    set_kafka_client_tag
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
    log "🎯 CONNECTOR_TAG is set with version $CONNECTOR_TAG"
    # determining the connector from current path
    docker_compose_file=$(grep "environment" "$PWD/$0" | grep DIR | grep start.sh | cut -d "/" -f 7 | cut -d '"' -f 1 | head -n1)
    if [ "${docker_compose_file}" != "" ] && [ -f "${docker_compose_file}" ]
    then
      connector_path=$(grep "CONNECT_PLUGIN_PATH" "${docker_compose_file}" | cut -d "/" -f 5 | head -1)
      # remove any extra comma at the end (when there are multiple connectors used, example S3 source)
      connector_path=$(echo "$connector_path" | cut -d "," -f 1)
      owner=$(echo "$connector_path" | cut -d "-" -f 1)
      name=$(echo "$connector_path" | cut -d "-" -f 2-)
      export CONNECT_TAG="$name-cp-$TAG-$CONNECTOR_TAG"
      log "👷 Building Docker image vdesabou/kafka-docker-playground-connect:${CONNECT_TAG}"
      tmp_dir=$(mktemp -d -t ci-XXXXXXXXXX)
cat << EOF > $tmp_dir/Dockerfile
FROM vdesabou/kafka-docker-playground-connect:${TAG}
RUN confluent-hub install --no-prompt $owner/$name:$CONNECTOR_TAG
EOF
      docker build -t vdesabou/kafka-docker-playground-connect:$CONNECT_TAG $tmp_dir
      rm -rf $tmp_dir
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
        log "🎯 CONNECTOR_JAR is set with $CONNECTOR_JAR"
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
    else
      logerror "📁 Could not determine docker-compose override file from $PWD/$0 !"
      logerror "👉 Please check you're running a connector example !"
      logerror "🎓 Check the related documentation https://kafka-docker-playground.io/#/how-it-works?id=🐳-docker-override"
      exit 1
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
    docker_compose_file=$(grep "environment" "$PWD/$0" | grep DIR | grep start.sh | cut -d "/" -f 7 | cut -d '"' -f 1 | head -n1)
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
        return
      fi

      
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
          return
        fi

        if [ -z "$CONNECT_TAG" ]
        then
          export CONNECT_TAG="$TAG"
        fi

        version_to_get_from_hub="latest"
        if [ "$name" = "kafka-connect-replicator" ]
        then
          version_to_get_from_hub="$TAG"
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

        log "👷♻️ Re-building Docker image vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} to include $owner/$name:$version_to_get_from_hub"
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
          fi
          CONNECTOR_TAG=$version
        fi
        first_loop=false
      done
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


function verify_ccloud_login()
{
  local cmd="$1"
  set +e
  output=$($cmd 2>&1)
  set -e
  if [ "${output}" = "Error: You must login to run that command." ] || [ "${output}" = "Error: Your session has expired. Please login again." ]; then
    logerror "This script requires ccloud to be logged in. Please execute 'ccloud login' and run again."
    exit 1
  fi
}

function verify_ccloud_details()
{
    if [ "$(ccloud prompt -f "%E")" = "(none)" ]
    then
        logerror "ccloud command is badly configured: environment is not set"
        log "Example: ccloud kafka environment list"
        log "then: ccloud kafka environment use <environment id>"
        exit 1
    fi

    if [ "$(ccloud prompt -f "%K")" = "(none)" ]
    then
        logerror "ccloud command is badly configured: cluster is not set"
        log "Example: ccloud kafka cluster list"
        log "then: ccloud kafka cluster use <cluster id>"
        exit 1
    fi

    if [ "$(ccloud prompt -f "%a")" = "(none)" ]
    then
        logerror "ccloud command is badly configured: api key is not set"
        log "Example: ccloud api-key store <api key> <password>"
        log "then: ccloud api-key use <api key>"
        exit 1
    fi

    CCLOUD_PROMPT_FMT='You will be using Confluent Cloud config: user={{color "green" "%u"}}, environment={{color "red" "%E"}}, cluster={{color "cyan" "%K"}}, api key={{color "yellow" "%a"}}'
    ccloud prompt -f "$CCLOUD_PROMPT_FMT"
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
  ccloud kafka topic create "$topic" --dry-run 2>/dev/null
  if [[ $? == 0 ]]; then
    log "Create topic $topic"
    log "ccloud kafka topic create $topic"
    ccloud kafka topic create "$topic" || true
  else
    log "Topic $topic already exists"
  fi
}

function delete_topic()
{
  local topic="$1"
  log "Check if topic $topic exists"
  ccloud kafka topic create "$topic" --dry-run 2>/dev/null
  if [[ $? != 0 ]]; then
    log "Delete topic $topic"
    log "ccloud kafka topic delete $topic"
    ccloud kafka topic delete "$topic" || true
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

function get_ccloud_version() {
  ccloud version | grep "^Version:" | cut -d':' -f2 | cut -d'v' -f2
}

function check_ccloud_version() {
  REQUIRED_CCLOUD_VER=${1:-"0.185.0"}
  CCLOUD_VER=$(get_ccloud_version)

  if version_gt $REQUIRED_CCLOUD_VER $CCLOUD_VER; then
    log "ccloud version ${REQUIRED_CCLOUD_VER} or greater is required.  Current reported version: ${CCLOUD_VER}"
    echo 'To update run: ccloud update'
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

    if [ -z "$AWS_ACCESS_KEY_ID" ] && [ -z "$AWS_SECRET_ACCESS_KEY" ] && [ ! -f $HOME/.aws/config ] && [ ! -f $HOME/.aws/$AWS_CREDENTIALS_FILE_NAME ]
    then
      logerror 'ERROR: Neither AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY or $HOME/.aws/$AWS_CREDENTIALS_FILE_NAME are set. AWS credentials must be set !'
      if [ -z "$AWS_ACCESS_KEY_ID" ]
      then
        log 'AWS_ACCESS_KEY_ID environment variable is not set.'
      fi
      if [ -z "$AWS_SECRET_ACCESS_KEY" ]
      then
        log 'AWS_SECRET_ACCESS_KEY environment variable is not set.'
      fi
      if [ ! -f $HOME/.aws/config ]
      then
        log '$HOME/.aws/config does not exist.'
      fi
      if [ ! -f $HOME/.aws/$AWS_CREDENTIALS_FILE_NAME ]
      then
        log '$HOME/.aws/$AWS_CREDENTIALS_FILE_NAME does not exist.'
      fi
      return 1
    fi

    docker run --rm -iv $HOME/.aws:/root/.aws -e AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY -v $(pwd):/aws -v /tmp:/tmp mikesir87/aws-cli:v2 aws "$@"
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

function retry() {
  local n=1
  local max=2
  while true; do
    "$@"
    ret=$?
    if [ $ret -eq 0 ]
    then
      return 0
    elif [ $ret -eq 123 ] # skipped
    then
      return 123
    elif [ $ret -eq 107 ] # known issue https://github.com/vdesabou/kafka-docker-playground/issues/907
    then
      return 107
    else
      if [[ $n -lt $max ]]; then
        ((n++))
        logwarn "Command failed. Attempt $n/$max:"
        logwarn "####################################################"
        logwarn "docker ps"
        docker ps
        logwarn "####################################################"
        for container in broker broker2 schema-registry connect broker-us broker-europe connect-us connect-europe replicator-us replicator-europe
        do
          if [[ $(docker ps -f "name=$container" --format '{{.Names}}') == $container ]]
          then
            logwarn "####################################################"
            logwarn "$container logs"
            docker container logs --tail=200 $container
            logwarn "####################################################"
          fi
        done
      else
        logerror "The command has failed after $n attempts."
        return 1
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
            logwarn "####################################################"
            logwarn "docker ps"
            docker ps
            logwarn "####################################################"
            for container in broker broker2 schema-registry connect broker-us broker-europe connect-us connect-europe replicator-us replicator-europe ibmmq
            do
              if [[ $(docker ps -f "name=$container" --format '{{.Names}}') == $container ]]
              then
                logwarn "####################################################"
                logwarn "$container logs"
                docker container logs --tail=200 $container
                logwarn "####################################################"
              fi
            done
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
  log "Waiting up to $MAX_WAIT seconds for connector $connector_name to finish injecting requested load"
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
  log "📊 JMX metrics are available locally on those ports:"
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

  if [ "$domains" = "ALL" ]
  then
log "This is the list of domains for component $component"
java -jar $JMXTERM_UBER_JAR  -l localhost:$port -n -v silent << EOF
domains
exit
EOF
  fi

for domain in `echo $domains`
do
java -jar $JMXTERM_UBER_JAR  -l localhost:$port -n -v silent > /tmp/beans.log << EOF
domain $domain
beans
exit
EOF
  while read line; do echo "get *"  -b $line; done < /tmp/beans.log >> /tmp/commands

  echo "####### domain $domain ########" >> /tmp/jmx_metrics.log
  java -jar $JMXTERM_UBER_JAR  -l localhost:$port -n < /tmp/commands >> /tmp/jmx_metrics.log 2>&1
done

  log "JMX metrics are available in /tmp/jmx_metrics.log file"
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
          docker container logs $container | egrep "ERROR|FATAL" | grep -v "was supplied but isn't a known config"
      fi
      logwarn "####################################################"
  done
}

container_to_name() {
    container=$1
    echo "${PWD##*/}_${container}_1"
}

container_to_ip() {
    if [ $# -lt 1 ]; then
        echo "Usage: container_to_ip container"
    fi
    echo $(docker inspect $1 -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
}

clear_traffic_control() {
    if [ $# -lt 1 ]; then
        echo "Usage: clear_traffic_control src_container"
    fi

    src_container=$1

    echo "Removing all traffic control settings on $src_container"

    # Delete the entry from the tc table so the changes made to tc do not persist
    docker exec --privileged -u0 -t $src_container tc qdisc del dev eth0 root 2>&1
}

get_latency() {
    if [ $# -lt 2 ]; then
        echo "Usage: get_latency src_container dst_container"
    fi
    src_container=$1
    dst_container=$2
    docker exec --privileged -u0 -t $src_container ping $dst_container -c 4 -W 80 | tail -1 | awk -F '/' '{print $5}'
}

# https://serverfault.com/a/906499
add_latency() {
    if [ $# -lt 3 ]; then
        echo "Usage: add_latency src_container dst_container latency"
        echo "Exemple: add_latency container-1 container-2 100ms"
    fi

    src_container=$1
    dst_container_ip=$(container_to_ip $2)
    latency=$3

    echo "Adding $latency from $src_container to $2"

    # Add a classful priority queue which lets us differentiate messages.
    # This queue is named 1:.
    # Three children classes, 1:1, 1:2 and 1:3, are automatically created.
    docker exec --privileged -u0 -t $src_container tc qdisc add dev eth0 root handle 1: prio 2>&1


    # Add a filter to the parent queue 1: (also called 1:0). The filter has priority 1 (if we had more filters this would make a difference).
    # For all messages with the ip of dst_container_ip as their destination, it routes them to class 1:1, which
    # subsequently sends them to its only child, queue 10: (All messages need to  "end up" in a queue).
    docker exec --privileged -u0 -t $src_container tc filter add dev eth0 protocol ip parent 1: prio 1 u32 match ip dst $dst_container_ip flowid 1:1 2>&1

    # Route the rest of the of the packets without any control.
    # Add a filter to the parent queue 1:. The filter has priority 2.
    docker exec --privileged -u0 -t $src_container tc filter add dev eth0 protocol all parent 1: prio 2 u32 match ip dst 0.0.0.0/0 flowid 1:2 2>&1
    docker exec --privileged -u0 -t $src_container tc filter add dev eth0 protocol all parent 1: prio 2 u32 match ip protocol 1 0xff flowid 1:2 2>&1

    # Add a child queue named 10: under class 1:1. All outgoing packets that will be routed to 10: will have delay applied them.
    docker exec --privileged -u0 -t $src_container tc qdisc add dev eth0 parent 1:1 handle 10: netem delay $latency 2>&1

    # Add a child queue named 20: under class 1:2
    docker exec --privileged -u0 -t $src_container tc qdisc add dev eth0 parent 1:2 handle 20: sfq 2>&1
}