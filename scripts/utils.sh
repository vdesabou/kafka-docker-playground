function log() {
  YELLOW='\033[0;33m'
  NC='\033[0m' # No Color
  echo -e "$YELLOW`date +"%H:%M:%S"` $@$NC"
}

function logerror() {
  RED='\033[0;31m'
  NC='\033[0m' # No Color
  echo -e "$RED`date +"%H:%M:%S"` $@$NC"
}

function logwarn() {
  PURPLE='\033[0;35m'
  NC='\033[0m' # No Color
  echo -e "$PURPLE`date +"%H:%M:%S"` $@$NC"
}

# https://stackoverflow.com/a/24067243
function version_gt() {
  test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1";
}

function set_kafka_client_tag()
{
    if [ "$TAG_BASE" = "6.0.0" ]
    then
      export KAFKA_CLIENT_TAG="2.6.0"
    fi

    if [ "$TAG_BASE" = "5.5.2" ] || [ "$TAG_BASE" = "5.5.1" ] || [ "$TAG_BASE" = "5.5.0" ]
    then
      export KAFKA_CLIENT_TAG="2.5.0"
    fi

    if [ "$TAG_BASE" = "5.4.1" ] || [ "$TAG_BASE" = "5.4.0" ]
    then
      export KAFKA_CLIENT_TAG="2.4.0"
    fi

    if [ "$TAG_BASE" = "5.3.2" ] || [ "$TAG_BASE" = "5.3.1" ]
    then
      export KAFKA_CLIENT_TAG="2.3.1"
    fi

    if [ "$TAG_BASE" = "5.3.0" ]
    then
      export KAFKA_CLIENT_TAG="2.3.0"
    fi

    if [ "$TAG_BASE" = "5.2.3" ] || [ "$TAG_BASE" = "5.2.2" ]
    then
      export KAFKA_CLIENT_TAG="2.2.2"
    fi

    if [ "$TAG_BASE" = "5.2.1" ]
    then
      export KAFKA_CLIENT_TAG="2.2.1"
    fi

    if [ "$TAG_BASE" = "5.2.0" ]
    then
      export KAFKA_CLIENT_TAG="2.2.0"
    fi

    if [ "$TAG_BASE" = "5.1.3" ] || [ "$TAG_BASE" = "5.1.2" ] || [ "$TAG_BASE" = "5.1.1" ]
    then
      export KAFKA_CLIENT_TAG="2.1.1"
    fi

    if [ "$TAG_BASE" = "5.1.0" ]
    then
      export KAFKA_CLIENT_TAG="2.1.0"
    fi

    if [ "$TAG_BASE" = "5.0.3" ] || [ "$TAG_BASE" = "5.0.2" ] || [ "$TAG_BASE" = "5.0.1" ]
    then
      export KAFKA_CLIENT_TAG="2.0.1"
    fi

    if [ "$TAG_BASE" = "5.0.0" ]
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

# Setting up TAG environment variable
#
if [ -z "$TAG" ]
then
    # TAG is not set, use defaults:
    export TAG=6.0.0
    # to handle ubi8 images
    export TAG_BASE=$TAG
    if [ -z "$CP_KAFKA_IMAGE" ]
    then
      log "Using Confluent Platform version default tag $TAG, you can use other version by exporting TAG environment variable, example export TAG=5.5.1"
    fi
    export CP_KAFKA_IMAGE=cp-server
    export CP_BASE_IMAGE=cp-base-new
    export CP_KSQL_IMAGE=cp-ksqldb-server
    export CP_KSQL_CLI_IMAGE=ksqldb-cli:latest
    set_kafka_client_tag
else
    if [ -z "$CP_KAFKA_IMAGE" ]
    then
      log "Using Confluent Platform version tag $TAG"
    fi
    # to handle ubi8 images
    export TAG_BASE=$(echo $TAG | cut -d "-" -f1)
    first_version=${TAG_BASE}
    second_version=5.3.0
    if version_gt $first_version $second_version; then
        export CP_KAFKA_IMAGE=cp-server
    else
        export CP_KAFKA_IMAGE=cp-enterprise-kafka
    fi
    second_version=5.3.10
    if version_gt $first_version $second_version; then
        export CP_BASE_IMAGE=cp-base-new
    else
        export CP_BASE_IMAGE=cp-base
    fi
    second_version=5.4.10
    if version_gt $first_version $second_version; then
        export CP_KSQL_IMAGE=cp-ksqldb-server
        export CP_KSQL_CLI_IMAGE=ksqldb-cli:latest
    else
        export CP_KSQL_IMAGE=cp-ksql-server
        export CP_KSQL_CLI_IMAGE=cp-ksql-cli:${TAG_BASE}
    fi
    set_kafka_client_tag
fi

function verify_installed()
{
  local cmd="$1"
  if [[ $(type $cmd 2>&1) =~ "not found" ]]; then
    echo -e "\nERROR: This script requires '$cmd'. Please install '$cmd' and run again.\n"
    exit 1
  fi
}

if [ ! -z "$TRAVIS" ]
then
  # log "DEBUG: called from $PWD $0"
  TMP_DIR=/tmp/playground_connector_tag$TRAVIS_JOB_NUMBER
  if [[ $0 == *"wait-for-connect-and-controlcenter.sh"* ]]
  then
    # log "DEBUG: wait-for-connect-and-controlcenter.sh from environment folder. Skipping..."
    # noop
    :
  elif [[ $0 == *"environment"* ]]
  then
    # log "DEBUG: start.sh from environment folder. Skipping..."
    # noop
    :
  elif [[ $0 == *"stop"* ]] || [[ $0 == *"run-tests"* ]] || [[ $0 == *"launch-github-action"* ]] || [[ $0 == *"cleanup-resources"* ]]
  then
    # log "DEBUG: stop.sh or run-tests.sh. Skipping..."
    # noop
    :
  else
    THE_CONNECTOR_TAG=""
    docker_compose_file=$(grep "environment" "$PWD/$0" | grep DIR | grep start.sh | cut -d "/" -f 7 | cut -d '"' -f 1 | head -n1)
    if [ "${docker_compose_file}" != "" ] && [ -f "${docker_compose_file}" ]
    then
      connector_path=$(grep "CONNECT_PLUGIN_PATH" "${docker_compose_file}" | cut -d "/" -f 5)
      # remove any extra comma at the end (when there are multiple connectors used, example S3 source)
      connector_path=$(echo "$connector_path" | cut -d "," -f 1)
      owner=$(echo "$connector_path" | cut -d "-" -f 1)
      name=$(echo "$connector_path" | cut -d "-" -f 2-)

      THE_CONNECTOR_TAG=$(docker run vdesabou/kafka-docker-playground-connect:${TAG} cat /usr/share/confluent-hub-components/$connector_path/manifest.json | jq -r '.version')
    fi
    file="$TAG-$THE_CONNECTOR_TAG-${0##*/}"
    s3_file="s3://kafka-docker-playground/travis/$file"
    set +e
    exists=$(aws s3 ls $s3_file)
    if [ -z "$exists" ]; then
      # log "DEBUG: $s3_file does not exist, run the test"
      :
    else
      aws s3 cp $s3_file /tmp/
      last_success_time=$(cat /tmp/$file)
      now=$(date +%s)
      elapsed_time=$((now-last_success_time))
      if [[ $elapsed_time -gt 604800 ]]
      then
        log "####################################################"
        log "Test with CP $TAG and connector $THE_CONNECTOR_TAG has already been executed successfully $(displaytime $elapsed_time) ago, re-running"
        log "####################################################"
      else
        logwarn "####################################################"
        logwarn "skipping as test with CP $TAG and connector $THE_CONNECTOR_TAG has already been executed successfully $(displaytime $elapsed_time) ago"
        logwarn "####################################################"
        exit 0
      fi
    fi
    set -e
  fi
fi

if [ ! -z "$CONNECTOR_TAG" ]
then
  log "CONNECTOR_TAG is set"
  # log "DEBUG: called from $PWD $0"
  TMP_DIR=/tmp/playground_connector_tag$TRAVIS_JOB_NUMBER
  if [[ $0 == *"wait-for-connect-and-controlcenter.sh"* ]]
  then
    if [ -f ${TMP_DIR}/connector_path ]
    then
      connector_path=$(cat ${TMP_DIR}/connector_path)
      connector=$(cat ${TMP_DIR}/connector)
      log "Installing connector $connector on container connect"
      docker cp ${TMP_DIR}/${connector_path} connect:/usr/share/confluent-hub-components/
      log "Verifying connector version installed in /usr/share/confluent-hub-components/${connector_path}"
      docker exec connect cat /usr/share/confluent-hub-components/${connector_path}/manifest.json | jq -r '.version'
      log "Restarting container connect"
      docker container restart connect
    else
      logerror "ERROR: ${TMP_DIR}/connector_path does not exist !"
      exit 1
    fi
  elif [[ $0 == *"environment"* ]]
  then
    # log "DEBUG: start.sh from environment folder. Skipping..."
    # noop
    :
  elif [[ $0 == *"couchbase"* ]]
  then
    log "Setting CONNECTOR_TAG with couchbase is not supported as it is not available on Confluent Hub"
    exit 0
  elif [[ $0 == *"stop"* ]] || [[ $0 == *"run-tests"* ]]
  then
    # log "DEBUG: stop.sh or run-tests.sh. Skipping..."
    # noop
    :
  else
    docker_compose_file=$(grep "environment" "$PWD/$0" | grep DIR | grep start.sh | cut -d "/" -f 7 | cut -d '"' -f 1 | head -n1)
    if [ "${docker_compose_file}" != "" ] && [ -f "${docker_compose_file}" ]
    then
      set +e
      if [ ! -z "$TRAVIS" ]
      then
          # running with travis
          sudo rm -rf ${TMP_DIR}
          sudo mkdir -p ${TMP_DIR}
          sudo chown travis ${TMP_DIR}
      else
          rm -rf ${TMP_DIR}
          mkdir -p ${TMP_DIR}
      fi
      set -e

      connector_path=$(grep "CONNECT_PLUGIN_PATH" "${docker_compose_file}" | cut -d "/" -f 5)
      # remove any extra comma at the end (when there are multiple connectors used, example S3 source)
      connector_path=$(echo "$connector_path" | cut -d "," -f 1)
      # save it
      echo "${connector_path}" > ${TMP_DIR}/connector_path
      owner=$(echo "$connector_path" | cut -d "-" -f 1)
      name=$(echo "$connector_path" | cut -d "-" -f 2-)
      # save it
      echo "$owner/$name:$CONNECTOR_TAG" > ${TMP_DIR}/connector
      log "Downloading connector $owner/$name:$CONNECTOR_TAG"
      docker run -v ${TMP_DIR}/${connector_path}:/usr/share/confluent-hub-components/$connector_path vdesabou/kafka-docker-playground-connect:$TAG confluent-hub install --no-prompt "$owner/$name:$CONNECTOR_TAG"
      if [ $? -ne 0 ]
      then
          logerror "ERROR: connector $owner/$name:$CONNECTOR_TAG is not available on Confluent Hub"
          exit 1
      fi
    else
      logerror "ERROR: could not determine docker-compose override file from $PWD/$0 !"
      logerror "ERROR: please check you're running a connector test"
      exit 1
    fi
  fi
fi



function verify_memory()
{
  # Verify Docker memory is increased to at least 8GB
  DOCKER_MEMORY=$(docker system info | grep Memory | grep -o "[0-9\.]\+")
  if (( $(echo "$DOCKER_MEMORY 7.0" | awk '{print ($1 < $2)}') )); then
      logerror "WARNING: Did you remember to increase the memory available to Docker to at least 8GB (default is 2GB)? Demo may otherwise not work properly"
      exit 1
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
    logerror "ERROR: This script requires ccloud to be logged in. Please execute 'ccloud login' and run again."
    exit 1
  fi
}

function verify_ccloud_details()
{
    if [ "$(ccloud prompt -f "%E")" = "(none)" ]
    then
        logerror "ERROR: ccloud command is badly configured: environment is not set"
        log "Example: ccloud kafka environment list"
        log "then: ccloud kafka environment use <environment id>"
        exit 1
    fi

    if [ "$(ccloud prompt -f "%K")" = "(none)" ]
    then
        logerror "ERROR: ccloud command is badly configured: cluster is not set"
        log "Example: ccloud kafka cluster list"
        log "then: ccloud kafka cluster use <cluster id>"
        exit 1
    fi

    if [ "$(ccloud prompt -f "%a")" = "(none)" ]
    then
        logerror "ERROR: ccloud command is badly configured: api key is not set"
        log "Example: ccloud api-key store <api key> <password>"
        log "then: ccloud api-key use <api key>"
        exit 1
    fi

    CCLOUD_PROMPT_FMT='You will be using Confluent Cloud config: user={{color "green" "%u"}}, environment={{color "red" "%E"}}, cluster={{color "cyan" "%K"}}, api key={{color "yellow" "%a"}}'
    ccloud prompt -f "$CCLOUD_PROMPT_FMT"
}

function check_if_continue()
{
    if [ ! -z "$TRAVIS" ] || [ ! -z "$CLOUDFORMATION" ]
    then
        # running with travis or cloudformation, continue
        return
    fi
    read -p "Continue (y/n)?" choice
    case "$choice" in
    y|Y ) ;;
    n|N ) exit 0;;
    * ) logerror "ERROR: invalid response!";exit 1;;
    esac
}

function create_topic()
{
  local topic="$1"
  log "Check if topic $topic exists"
  ccloud kafka topic create $topic --dry-run 2>/dev/null
  if [[ $? == 0 ]]; then
    log "Create topic $topic"
    log "ccloud kafka topic create $topic"
    ccloud kafka topic create $topic || true
  else
    log "Topic $topic already exists"
  fi
}

function delete_topic()
{
  local topic="$1"
  log "Check if topic $topic exists"
  ccloud kafka topic create $topic --dry-run 2>/dev/null
  if [[ $? != 0 ]]; then
    log "Delete topic $topic"
    log "ccloud kafka topic delete $topic"
    ccloud kafka topic delete $topic || true
  else
    log "Topic $topic does not exist"
  fi
}

function version_gt() {
  test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1";
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
    if [ ! -d $HOME/.aws ]
    then
      log 'ERROR: $HOME/.aws does now exist. AWS credentials must be set !'
      return 1
    fi
    if [ ! -f $HOME/.aws/config ]
    then
      log 'ERROR: $HOME/.aws/config does now exist. AWS credentials must be set !'
      return 1
    fi
    if [ ! -f $HOME/.aws/credentials ]
    then
      log 'ERROR: $HOME/.aws/credentials does now exist. AWS credentials must be set !'
      return 1
    fi
    docker run --rm -tiv $HOME/.aws:/root/.aws -v $(pwd):/aws -v /tmp:/tmp mikesir87/aws-cli:v1 aws "$@"
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

function jq() {
    docker run --rm -i imega/jq "$@"
}

function az() {
    docker run -v /tmp:/tmp -v $HOME/.azure:/home/az/.azure -e HOME=/home/az --rm -i mcr.microsoft.com/azure-cli az "$@"
}

function retry() {
  local n=1
  local max=2
  while true; do
    "$@" && break || {
      if [[ $n -lt $max ]]; then
        ((n++))
        logwarn "Command failed. Attempt $n/$max:"
        logwarn "####################################################"
        logwarn "docker ps"
        docker ps
        logwarn "####################################################"
        for container in broker broker2 schema-registry connect broker-us broker-europe connect-us connect-europe
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
    }
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
            logerror "ERROR: Failed after $attempt_num attempts. Please troubleshoot and run again."
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
  FOUND=$(docker container logs broker | grep "Started NetworkTrafficServerConnector")
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