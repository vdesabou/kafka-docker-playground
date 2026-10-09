function verbose_begin () {
  # Check if set -x is currently active
  if [[ $- = *x* ]]
  then
    # Disable set -x
    set +x
    was_x_set=1
  else
    was_x_set=0
  fi
}

function verbose_end () {
  return_code="$?"
  # If set -x was initially active, re-enable it
  if [[ $was_x_set -eq 1 ]]
  then
    set -x
  fi
  return $return_code
}

function log() {
  if [ ! -z $PG_LOG_LEVEL ]
  then
    case "${PG_LOG_LEVEL}" in
      WARN|ERROR)
        return
      ;;
    esac
  fi

  verbose_begin
  YELLOW='\033[0;33m'
  NC='\033[0m' # No Color
  echo -e "$YELLOW$(date +"%H:%M:%S") ℹ️ $@$NC"
  verbose_end
}

function logerror() {
  verbose_begin
  RED='\033[0;31m'
  NC='\033[0m' # No Color
  echo -e "$RED$(date +"%H:%M:%S") 🔥 $@$NC"
  verbose_end
}

function logwarn() {
  if [ ! -z $PG_LOG_LEVEL ]
  then
    case "${PG_LOG_LEVEL}" in
      INFO)
        return
      ;;
    esac
  fi
  verbose_begin
  PURPLE='\033[0;35m'
  NC='\033[0m' # No Color
  echo -e "$PURPLE`date +"%H:%M:%S"` ❗ $@$NC"
  verbose_end
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

function base64() {
  docker run -i --rm ddev/ddev-utilities:latest base64 -w 0 "$@"
}

function jq() {
  verbose_begin
  if [[ $(type -f jq 2>&1) =~ "not found" ]]
  then
    docker run --quiet --rm -i imega/jq "$@"
  else
    $(type -f jq | awk '{print $3}') "$@"
  fi
  verbose_end
}

function yq() {
  verbose_begin
  if [[ $(type -f yq 2>&1) =~ "not found" ]]
  then
    docker run --quiet  -u0 -v ${PLAYGROUND_HOST_TMP_DIR}:/tmp --rm -i mikefarah/yq "$@"
  else
    $(type -f yq | awk '{print $3}') "$@"
  fi
  verbose_end
}

function set_kafka_client_tag()
{
    if [[ $TAG_BASE = 8.3.* ]]
    then
      export KAFKA_CLIENT_TAG="4.2.0"
    fi

    if [[ $TAG_BASE = 8.2.* ]]
    then
      export KAFKA_CLIENT_TAG="4.2.0"
    fi

    if [[ $TAG_BASE = 8.1.* ]]
    then
      export KAFKA_CLIENT_TAG="4.1.0"
    fi

    if [[ $TAG_BASE = 8.0.* ]]
    then
      export KAFKA_CLIENT_TAG="4.0.0"
    fi

    if [[ $TAG_BASE = 7.9.* ]]
    then
      export KAFKA_CLIENT_TAG="3.9.0"
    fi
    
    if [[ $TAG_BASE = 7.8.* ]]
    then
      export KAFKA_CLIENT_TAG="3.8.0"
    fi

    if [[ $TAG_BASE = 7.7.* ]]
    then
      export KAFKA_CLIENT_TAG="3.7.0"
    fi
    
    if [[ $TAG_BASE = 7.6.* ]]
    then
      export KAFKA_CLIENT_TAG="3.6.0"
    fi

    if [[ $TAG_BASE = 7.5.* ]]
    then
      export KAFKA_CLIENT_TAG="3.5.0"
    fi

    if [[ $TAG_BASE = 7.4.* ]]
    then
      export KAFKA_CLIENT_TAG="3.4.0"
    fi

    if [[ $TAG_BASE = 7.3.* ]]
    then
      export KAFKA_CLIENT_TAG="3.3.0"
    fi

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
  log "☕ Select the jar to replace:"
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


function verify_installed()
{
  local cmd="$1"
  if [[ $(type $cmd 2>&1) =~ "not found" ]]; then
    logerror "❌ the script requires $cmd. Please install $cmd and run again"
    exit 1
  fi
}

function maybe_create_image()
{
  if [ ! -z "$DOCKER_COMPOSE_FILE_UPDATE_VERSION" ]
  then
    return
  fi
  # set below once the image is known to contain the tools: skips the docker run checks (~0.5s, utils.sh is
  # sourced twice per run). A new pull of the tag drops the label
  local tools_label="io.confluent.playground.tools"
  if [ "$(docker image inspect -f "{{ index .Config.Labels \"$tools_label\" }}" ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} 2> /dev/null)" == "1" ]
  then
    return
  fi
  local tools_ok="false"
  set +e
    if version_gt $TAG_BASE "8.2.99"
  then
    docker run --quiet --rm ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} type microdnf > /dev/null 2>&1
    if [ $? != 0 ]
    then
      log "🛠️ Restoring ubi minimal into ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG}"
      pm_tmp_dir=$(mktemp -d -t pg-pm-XXXXXXXXXX)
      cat << EOF > $pm_tmp_dir/Dockerfile
FROM redhat/ubi9-minimal:latest AS pm
RUN rm -f /etc/passwd /etc/group /etc/shadow /etc/gshadow /etc/subuid /etc/subgid

FROM ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG}
USER root
COPY --from=pm / /
RUN ldconfig
USER appuser
EOF
      (export_docker_config_without_cred_helpers; DOCKER_BUILDKIT=0 docker build -t ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} $pm_tmp_dir)
      rm -rf $pm_tmp_dir
    fi
  fi
  log "🧰 Checking if Docker image ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} contains additional tools"
  log "⏳ it can take a while if image is downloaded for the first time"
  docker run --quiet --rm ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} type unzip > /dev/null 2>&1
  if [ $? == 0 ]
  then
    tools_ok="true"
  else
    if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
    then
      export CONNECT_USER="appuser"
      if [ "$(uname -m)" = "arm64" ]
      then
        if version_gt $TAG_BASE "8.0.99"
        then
          CONNECT_3RDPARTY_INSTALL="if [ ! -f /tmp/done ]; then microdnf -y install bind-utils openssl unzip findutils net-tools nc jq which iptables libmnl krb5-workstation krb5-libs vim && microdnf clean all  && touch /tmp/done; fi"
        elif version_gt $TAG_BASE "7.9.99"
        then
          CONNECT_3RDPARTY_INSTALL="if [ ! -f /tmp/done ]; then yum -y install bind-utils openssl unzip findutils net-tools nc jq which iptables libmnl krb5-workstation krb5-libs vim && yum clean all && rm -rf /var/cache/yum && rpm -i --nosignature https://yum.oracle.com/repo/OracleLinux/OL9/appstream/aarch64/getPackage/tcpdump-4.99.0-9.el9.aarch64.rpm && touch /tmp/done; fi"
        else
          CONNECT_3RDPARTY_INSTALL="if [ ! -f /tmp/done ]; then yum -y install --disablerepo='Confluent*' bind-utils openssl unzip findutils net-tools nc jq which iptables libmnl krb5-workstation krb5-libs vim && yum clean all && rm -rf /var/cache/yum && rpm -i --nosignature https://yum.oracle.com/repo/OracleLinux/OL8/appstream/aarch64/getPackage/tcpdump-4.9.3-3.el8.aarch64.rpm && touch /tmp/done; fi"
        fi
      else
        if version_gt $TAG_BASE "8.0.99"
        then
          CONNECT_3RDPARTY_INSTALL="if [ ! -f /tmp/done ]; then microdnf -y install bind-utils openssl unzip findutils net-tools nc jq which iptables libmnl krb5-workstation krb5-libs vim && microdnf clean all  && touch /tmp/done; fi"
        elif version_gt $TAG_BASE "7.9.99"
        then
          CONNECT_3RDPARTY_INSTALL="if [ ! -f /tmp/done ]; then yum -y install bind-utils openssl unzip findutils net-tools nc jq which iptables libmnl krb5-workstation krb5-libs vim && yum clean all && rm -rf /var/cache/yum && rpm -i --nosignature https://yum.oracle.com/repo/OracleLinux/OL9/appstream/x86_64/getPackage/tcpdump-4.99.0-9.el9.x86_64.rpm && touch /tmp/done; fi"
        else
          CONNECT_3RDPARTY_INSTALL="if [ ! -f /tmp/done ]; then curl https://download.rockylinux.org/pub/rocky/8/AppStream/x86_64/kickstart/Packages/t/tcpdump-4.9.3-5.el8.x86_64.rpm -o tcpdump-4.9.3-1.el8.x86_64.rpm && rpm -Uvh tcpdump-4.9.3-1.el8.x86_64.rpm && yum -y install --disablerepo='Confluent*' bind-utils openssl unzip findutils net-tools nc jq which iptables libmnl krb5-workstation krb5-libs vim && yum clean all && rm -rf /var/cache/yum && touch /tmp/done; fi"
        fi
      fi
    else
      export CONNECT_USER="root"
      CONNECT_3RDPARTY_INSTALL="if [ ! -f /tmp/done ]; then apt-get update && echo bind-utils openssl unzip findutils net-tools nc jq which iptables tree | xargs -n 1 apt-get install --force-yes -y && rm -rf /var/lib/apt/lists/* && touch /tmp/done; fi"
    fi

    tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
    if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi
cat << EOF > $tmp_dir/Dockerfile
FROM ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG}
USER root
# https://github.com/confluentinc/common-docker/pull/743 and https://github.com/adoptium/adoptium-support/issues/1285
RUN if [ -f /etc/yum.repos.d/adoptium.repo ]; then sed -i "s/packages\.adoptium\.net/adoptium\.jfrog\.io/g" /etc/yum.repos.d/adoptium.repo; fi
RUN ${CONNECT_3RDPARTY_INSTALL}
USER ${CONNECT_USER}
EOF
    log "👷📦 Re-building Docker image ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} to include additional tools"
    docker build -t ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} $tmp_dir
    if [ $? == 0 ]
    then
      tools_ok="true"
    fi
    rm -rf $tmp_dir
  fi

  if [ "$tools_ok" == "true" ]
  then
    # metadata only layer
    printf 'FROM %s\nLABEL %s="1"\n' "${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG}" "$tools_label" | docker build --quiet -t ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} - > /dev/null 2>&1
  fi
  set -e
}


# 🐳 / 🦭 container engine
#
# The playground always drives the container engine through the `docker` CLI, so
# podman is supported the docker-compatible way: either DOCKER_HOST points at the
# podman socket, or `docker` is the shim from the podman-docker package. Nothing
# below changes what is executed, it only tells the user which engine they landed
# on so the error messages and `playground doctor` can be specific.
function get_container_engine()
{
  if [ ! -z "${PLAYGROUND_CONTAINER_ENGINE:-}" ]
  then
    echo "$PLAYGROUND_CONTAINER_ENGINE"
    return 0
  fi

  # every test below is inside an if, so it is safe under set -e and this function
  # must not touch the errexit state of its caller.
  # the two local checks come first so that the usual podman setups never pay for
  # a round trip to the engine
  local engine="docker"
  if [[ "${DOCKER_HOST:-}" == *podman* ]]
  then
    engine="podman"
  # podman-docker installs a `docker` shim whose --version says "podman version x.y.z"
  elif docker --version 2>/dev/null | grep -qi "podman"
  then
    engine="podman"
  # docker CLI talking to a podman socket: the compat /version endpoint advertises
  # a "Podman Engine" component
  elif docker version --format '{{json .Server}}' 2>/dev/null | grep -qi "podman"
  then
    engine="podman"
  elif docker info --format '{{json .}}' 2>/dev/null | grep -qi "podman"
  then
    engine="podman"
  fi

  export PLAYGROUND_CONTAINER_ENGINE="$engine"
  echo "$engine"
}

function container_engine_is_podman()
{
  [ "$(get_container_engine)" = "podman" ]
}

# the classic builder (DOCKER_BUILDKIT=0, for `docker build` and `docker compose build`)
# does not know which registries a build will pull from, so it asks every credHelpers
# entry of ~/.docker/config.json for credentials up front: with corporate helpers
# (ECR through granted/SSO...) that means browser prompts and 403 errors on each build.
# Point DOCKER_CONFIG at a mirror of the docker config without credHelpers: contexts,
# cli-plugins, credsStore and auths are kept, the helpers are simply never called.
function export_docker_config_without_cred_helpers()
{
  local src="${DOCKER_CONFIG:-$HOME/.docker}"
  local dst="${TMPDIR:-/tmp}"
  dst="${dst%/}/playground-docker-config-$(id -u)"

  # already mirrored (DOCKER_CONFIG is inherited by nested playground calls)
  if [ "$src" = "$dst" ] || [ ! -f "$src/config.json" ] || ! grep -q '"credHelpers"' "$src/config.json" || ! command -v jq > /dev/null 2>&1
  then
    return 0
  fi

  mkdir -p "$dst" || return 0
  local f
  for f in "$src"/* "$src"/.[!.]*
  do
    if [ -e "$f" ] && [ "$(basename "$f")" != "config.json" ]
    then
      ln -sfn "$f" "$dst/$(basename "$f")"
    fi
  done
  if jq 'del(.credHelpers)' "$src/config.json" > "$dst/config.json.tmp" 2>/dev/null
  then
    mv "$dst/config.json.tmp" "$dst/config.json"
    export DOCKER_CONFIG="$dst"
    # the mirror is a snapshot: anything that must persist, like the current docker
    # context set by switch-podman / switch-docker, has to be written to the original
    export PLAYGROUND_DOCKER_CONFIG_ORIGINAL="$src"
  fi
}

# with podman, `docker build` and `docker compose build` go through buildx, which
# runs BuildKit in its own container: it pulls FROM images from the registry instead
# of using podman's local ones (so images patched by maybe_create_image are ignored),
# and with that driver the result is never loaded back, it stays in the build cache.
# The classic builder goes through podman's own /build endpoint and has neither issue.
# Only the cheap DOCKER_HOST test here, this runs every time the file is sourced;
# `playground doctor` covers the other ways of reaching podman.
if [[ "${DOCKER_HOST:-}" == *podman* ]] || [ "${PLAYGROUND_CONTAINER_ENGINE:-}" = "podman" ]
then
  export DOCKER_BUILDKIT=0
  export_docker_config_without_cred_helpers
# podman reached through a docker context instead: only pay for `docker context
# inspect` (a local file read, no engine round trip) when a context is in use
elif [ -z "${DOCKER_HOST:-}" ] && { [ -n "${DOCKER_CONTEXT:-}" ] || grep -q '"currentContext"' "${DOCKER_CONFIG:-$HOME/.docker}/config.json" 2>/dev/null; }
then
  if docker context inspect --format '{{.Endpoints.docker.Host}}' 2>/dev/null | grep -q podman
  then
    export DOCKER_BUILDKIT=0
    export_docker_config_without_cred_helpers
  fi
fi

# 📂 host paths for bind mounts
#
# the docker CLI sends a bind mount source verbatim, and the engine resolves it on
# its side. On macOS /tmp is a symlink to /private/tmp: Docker Desktop shares both,
# but a podman machine cannot share /tmp (its VM needs its own), so `-v ${PLAYGROUND_HOST_TMP_DIR}:/tmp`
# silently mounts the VM's tmpfs, which the container cannot even write to.
# /private is shared by both, so always mount the resolved path. On Linux it is /tmp.
# Exported so that docker compose files can use ${PLAYGROUND_HOST_TMP_DIR:-/tmp}.
export PLAYGROUND_HOST_TMP_DIR="$(cd /tmp && pwd -P)"

# same thing for a path coming from a flag or a variable, which may live under /tmp:
# resolve its symlinks before using it as a bind mount source
function host_path()
{
  local path="$1"
  if [ -d "$path" ]
  then
    (cd "$path" && pwd -P)
  elif [ -d "$(dirname "$path")" ]
  then
    echo "$(cd "$(dirname "$path")" && pwd -P)/$(basename "$path")"
  else
    echo "$path"
  fi
}

# printed whenever the engine is unreachable, tailored to what is installed.
# pass any argument to drop the "run playground doctor" hint (doctor itself uses it)
function log_container_engine_not_running()
{
  logerror "Cannot connect to the container engine."
  if [ ! -z "${DOCKER_HOST:-}" ]
  then
    logerror "DOCKER_HOST is set to ${DOCKER_HOST}, make sure that socket is up."
  fi
  if command -v podman >/dev/null 2>&1 || [ "$(get_container_engine)" = "podman" ]
  then
    logerror "the playground talks to podman through the docker-compatible socket:"
    if [[ "$OSTYPE" == "darwin"* ]]
    then
      logerror "  podman machine start"
      logerror "  export DOCKER_HOST=\"unix://\$(podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}')\""
    else
      logerror "  sudo systemctl enable --now podman.socket   (rootful, see https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%a6%ad-using-podman-instead-of-docker)"
      logerror "  export DOCKER_HOST=\"unix:///run/podman-api/podman.sock\""
    fi
  else
    logerror "Is the docker daemon running?"
  fi
  if [ -z "${1:-}" ]
  then
    logerror "👉 run 'playground doctor' for a full check of the container engine"
  fi
}

function verify_docker_and_memory()
{
  set +e
  docker info > /dev/null 2>&1
  if [[ $? -ne 0 ]]
  then
    log_container_engine_not_running
    exit 1
  fi
  set -e
  # Check only with Mac OS
  # if [[ "$OSTYPE" == "darwin"* ]]
  # then
  #   # Verify Docker memory is increased to at least 8GB
  #   DOCKER_MEMORY=$(docker system info | grep Memory | grep -o "[0-9\.]\+")
  #   if (( $(echo "$DOCKER_MEMORY 7.0" | awk '{print ($1 < $2)}') )); then
  #       logerror "WARNING: Did you remember to increase the memory available to Docker to at least 8GB (default is 2GB)? Demo may otherwise not work properly"
  #       exit 1
  #   fi
  # fi
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
  if [ ! -z "$GITHUB_RUN_NUMBER" ]
  then
      # running with github actions, continue
      return
  fi
  read -p "Continue (y/n)?" choice
  case "$choice" in
  y|Y ) ;;
  n|N ) exit 0;;
  * ) logwarn "invalid response <$choice>! Please enter y or n."; check_if_continue;;
  esac
}

function check_if_skip() {

  if [[ -n "$force" ]] || [ ! -z "$GITHUB_RUN_NUMBER" ]
  then
    eval "$1"
  else
    read -p "Do you want to skip this command? (y/n) " reply

    case "$reply" in
    y|Y ) log "Skipping command...";;
    n|N ) eval "$1";;
    * ) logwarn "invalid response <$reply>! Please enter y or n."; check_if_skip;;
    esac
  fi
}

function create_topic()
{
  local topic="$1"
  # log "Check if topic $topic exists"
  confluent kafka topic create "$topic" --partitions 1 --dry-run > /dev/null 2>/dev/null
  if [[ $? == 0 ]]; then
    log "Create topic $topic"
    log "confluent kafka topic create $topic --partitions 1"
    confluent kafka topic create "$topic" --partitions 1 && record_ccloud_created_topic "$topic" || true
  else
    log "Topic $topic already exists"
  fi
}

function delete_topic()
{
  local topic="$1"
  # log "Check if topic $topic exists"
  confluent kafka topic create "$topic" --partitions 1 --dry-run > /dev/null 2>/dev/null
  if [[ $? != 0 ]]; then
    log "Delete topic $topic"
    log "confluent kafka topic delete $topic --force"
    confluent kafka topic delete "$topic" --force || true
  else
    log "Topic $topic does not exist"
  fi
}

# Confluent Cloud resources created by this user are recorded in a local ledger, one
# "<kafka cluster id> <entry> <run id>" per line, where <entry> is a topic name,
# "prefix:<topic prefix>" or "connector:<connector name>", and <run id> identifies the
# 'playground run' that created it (empty for lines written before run ids existed).
# 'playground cleanup-cloud-resources' uses it to delete only the user's topics when the cluster
# is shared with other people (topic names are generic, they can't be matched on the username),
# and the end-of-run cleanup to delete only what the last run created.
# Kept out of .ccloud, which 'playground cleanup-cloud-details' wipes.
function get_ccloud_created_topics_file () {
  get_kafka_docker_playground_dir
  ccloud_created_topics_file="$KAFKA_DOCKER_PLAYGROUND_DIR/playground-ccloud-created-topics"
}

function get_ccloud_kafka_cluster_id () {
  get_kafka_docker_playground_dir
  grep "KAFKA CLUSTER ID" $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta 2>/dev/null | cut -d " " -f 5
}

function get_ccloud_environment_id () {
  get_kafka_docker_playground_dir
  grep "ENVIRONMENT ID" $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta 2>/dev/null | cut -d " " -f 4
}

# $1 = topic, "prefix:<topic prefix>" or "connector:<connector name>"
function record_ccloud_created_topic () {
  local entry="$1"
  local cluster_id
  local run_id
  cluster_id=$(get_ccloud_kafka_cluster_id)
  if [ -z "$cluster_id" ]
  then
    return 0
  fi
  # set by 'playground run' for the example script, otherwise the last ccloud run
  run_id="${PG_CCLOUD_RUN_ID:-$(playground state get run.ccloud_run_id 2>/dev/null)}"
  get_ccloud_created_topics_file
  # re-recording moves the entry to the current run
  forget_ccloud_recorded_topic "$cluster_id" "$entry"
  echo "$cluster_id $entry $run_id" >> "$ccloud_created_topics_file"
}

function record_ccloud_created_connector () {
  record_ccloud_created_topic "connector:$1"
}

# Recorded entries of a cluster, optionally only those of run $2
function get_ccloud_recorded_entries () {
  local cluster_id="$1"
  local run_id="$2"
  get_ccloud_created_topics_file
  if [ -f "$ccloud_created_topics_file" ]
  then
    awk -v c="$cluster_id" -v r="$run_id" '$1 == c && (r == "" || $3 == r) {print $2}' "$ccloud_created_topics_file" | sort -u
  fi
}

# Recorded topics and topic prefixes of a cluster, optionally only those of run $2
function get_ccloud_recorded_topics () {
  get_ccloud_recorded_entries "$1" "$2" | grep -v '^connector:'
}

# Recorded connectors of a cluster, optionally only those of run $2
function get_ccloud_recorded_connectors () {
  get_ccloud_recorded_entries "$1" "$2" | grep '^connector:' | sed 's/^connector://'
}

# Recorded topics of a cluster (optionally only those of run $3) that exist in $2 (list of
# existing topics): exact entries, plus every existing topic starting with a recorded prefix
function get_ccloud_recorded_topics_matching () {
  local cluster_id="$1"
  local existing_topics="$2"
  local run_id="$3"
  local entry
  for entry in $(get_ccloud_recorded_topics "$cluster_id" "$run_id")
  do
    if [[ $entry == prefix:* ]]
    then
      echo "$existing_topics" | awk -v p="${entry#prefix:}" 'index($0, p) == 1'
    else
      echo "$existing_topics" | grep -Fx -- "$entry"
    fi
  done | sort -u
}

# Topics a fully managed or custom source connector writes to, as set in its config: recorded
# as exact names (kafka.topic, api1.topics, table1.topic...) or as prefixes (topic.prefix,
# dynamics365.topic.prefix, database.server.name). Names with a ${...} template are skipped,
# they can't be resolved without the source system.
# $1 = connector config as a JSON object
function record_ccloud_connector_output_topics () {
  local config="$1"
  local topic
  local prefix
  for topic in $(echo "$config" | jq -r 'to_entries[] | select(.key | test("^(kafka\\.topic|couchbase\\.topic|redo\\.log\\.topic\\.name|state\\.topic\\.name|[a-z]+[0-9]+\\.topics?)$")) | .value | strings' 2>/dev/null | tr ',' '\n' | tr -d ' ')
  do
    if [[ $topic != *'${'* ]]
    then
      record_ccloud_created_topic "$topic"
    fi
  done
  for prefix in $(echo "$config" | jq -r 'to_entries[] | select(.key | test("^(topic\\.prefix|[a-z0-9]+\\.topic\\.prefix|database\\.server\\.name)$")) | .value | strings' 2>/dev/null | tr -d ' ')
  do
    if [[ $prefix != *'${'* ]]
    then
      record_ccloud_created_topic "prefix:$prefix"
    fi
  done
}

function forget_ccloud_recorded_topic () {
  local cluster_id="$1"
  local entry="$2"
  get_ccloud_created_topics_file
  if [ -f "$ccloud_created_topics_file" ]
  then
    awk -v c="$cluster_id" -v e="$entry" '!($1 == c && $2 == e)' "$ccloud_created_topics_file" > "$ccloud_created_topics_file.tmp"
    mv "$ccloud_created_topics_file.tmp" "$ccloud_created_topics_file"
  fi
}

# Topics a fully managed connector creates on its own: dead letter queue and, for connectors
# with a reporter (HTTP, Lambda, Azure Functions, ServiceNow...), success and error topics.
# Defaults are dlq-<lcc id>, success-<lcc id> and error-<lcc id>, the config can override them
# and use ${connector} as a placeholder for the lcc id.
# $1 = connector id (lcc-xxxx), $2 = connector config as a JSON object
function get_ccloud_connector_related_topics () {
  local connector_id="$1"
  local config="$2"

  if [ -z "$connector_id" ]
  then
    return 0
  fi
  {
    echo "dlq-$connector_id"
    echo "success-$connector_id"
    echo "error-$connector_id"
    echo "$config" | jq -r '.["errors.deadletterqueue.topic.name", "reporter.error.topic.name", "reporter.result.topic.name"] // empty' 2>/dev/null | sed "s/\${connector}/$connector_id/g"
  } | grep -v '^$' | sort -u
}

function version_gt() {
  local v1=$(echo "$1" | cut -d'-' -f1 | tr -cd '0-9.' | sed 's/\.*$//')
  local v2=$(echo "$2" | cut -d'-' -f1 | tr -cd '0-9.' | sed 's/\.*$//')
  test "$(printf '%s\n' "$v1" "$v2" | sort -V | head -n 1)" != "$v1";
}

function get_docker_compose_version() {
  docker compose version --short
}

function check_docker_compose_version() {
  REQUIRED_DOCKER_COMPOSE_VER=${1:-"1.28.0"}
  DOCKER_COMPOSE_VER=$(get_docker_compose_version)

  if version_gt $REQUIRED_DOCKER_COMPOSE_VER $DOCKER_COMPOSE_VER; then
    logerror "docker compose version ${REQUIRED_DOCKER_COMPOSE_VER} or greater is required. Current reported version: ${DOCKER_COMPOSE_VER}"
    exit 1
  fi
}

function get_bash_version() {
  bash_major_version=$(bash --version | head -n1 | awk '{print $4}')
  major_version="${bash_major_version%%.*}"
  echo "$major_version"
}

function check_bash_version() {
  REQUIRED_BASH_VER=${1:-"4"}
  BASH_VER=$(get_bash_version)

  if version_gt $REQUIRED_BASH_VER $BASH_VER; then
    logerror "bash version ${REQUIRED_BASH_VER} or greater is required. Current reported version: ${BASH_VER}"
    exit 1
  fi
}

function check_and_update_playground_version() {
  check_repo_version=$(playground config get check-and-update-repo-version)
  if [ "$check_repo_version" == "" ]
  then
      playground config set check-and-update-repo-version true
  fi

  if [ "$check_repo_version" == "true" ] || [ "$check_repo_version" == "" ]
  then
    # git fetch costs from 0.5s to several seconds (VPN...): do it at most every 6 hours
    now=$(date +%s)
    last_check=$(playground state get repo.last_version_check)
    if [[ "$last_check" =~ ^[0-9]+$ ]] && [ $(( now - last_check )) -lt 21600 ]
    then
      return
    fi
    playground state set repo.last_version_check "$now"

    set +e
    X=3
    git fetch
    latest_commit_date=$(git log -1 --format=%cd --date=short)
    remote_commit_date=$(git log -1 --format=%cd --date=short origin/master)

    if [[ "$OSTYPE" == "darwin"* ]]
    then
      latest_commit_date_seconds=$(date -j -f "%Y-%m-%d" "$latest_commit_date" +%s)
      remote_commit_date_seconds=$(date -j -f "%Y-%m-%d" "$remote_commit_date" +%s)
    else
      latest_commit_date_seconds=$(date -d "$latest_commit_date" +%s)
      remote_commit_date_seconds=$(date -d "$remote_commit_date" +%s)
    fi

    difference=$(( (remote_commit_date_seconds - latest_commit_date_seconds) / (60*60*24) ))

    if [ $difference -gt $X ]
    then
        logwarn "🥶 The current repo version is older than $X days ($difference days), now trying to refresh your version using git pull (disable with 'playground config check-and-update-repo-version false')"
        set +e
        git pull
        if [ $? -ne 0 ]
        then
          logerror "❌ Error while pulling the latest version of the repo. Please check your git configuration/error message, do you still want to continue using outdated version ?"
          check_if_continue
        else
          log "🔄 The repo version is now up to date, calling <playground re-run> to restart your example now."
          playground re-run
        fi
    fi
    set -e
  fi
}

function get_ccs_or_ce_specifics() {
  if [[ $CP_CONNECT_IMAGE == *"cp-kafka-"* ]]
  then
    #log "Ⓜ️ detected connect community image used, disabling Monitoring Interceptors"
    export CONNECT_CONSUMER_INTERCEPTOR_CLASSES=""
    export CONNECT_PRODUCER_INTERCEPTOR_CLASSES=""
  elif version_gt $TAG_BASE "7.9.99"
  then
    #log "Ⓜ️ disabling Monitoring Interceptors as CP image is > 8"
    export CONNECT_CONSUMER_INTERCEPTOR_CLASSES=""
    export CONNECT_PRODUCER_INTERCEPTOR_CLASSES=""
  else
    export CONNECT_CONSUMER_INTERCEPTOR_CLASSES="io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor"
    export CONNECT_PRODUCER_INTERCEPTOR_CLASSES="io.confluent.monitoring.clients.interceptor.MonitoringProducerInterceptor"
  fi

  if [[ $CP_KAFKA_IMAGE == *"cp-kafka" ]]
  then
    log "Ⓜ️ detected kafka community image used, disabling Metrics Reporter"
    export KAFKA_METRIC_REPORTERS=""
  else
    export KAFKA_METRIC_REPORTERS="io.confluent.metrics.reporter.ConfluentMetricsReporter"
  fi
}

function determine_confluent_telemetry() {
  export TELEMETRY_DOCKER_COMPOSE_FILE_OVERRIDE=""
  if [ -z "$CONFLUENT_CLOUD_API_KEY" ] || [ -z "$CONFLUENT_CLOUD_API_SECRET" ]
  then
    return
  fi

  if [[ $CP_KAFKA_IMAGE == *"cp-kafka" ]] || [[ $CP_CONNECT_IMAGE == *"cp-kafka-"* ]]
  then
    logwarn "📡 Confluent Telemetry Reporter (proactive support) is not enabled as community images are used"
    return
  fi

  if ! version_gt $TAG_BASE "5.9.99"
  then
    logwarn "📡 Confluent Telemetry Reporter (proactive support) is not enabled as it requires CP version >= 6.0"
    return
  fi

  log "📡 Enabling Confluent Telemetry Reporter (proactive support) as CONFLUENT_CLOUD_API_KEY and CONFLUENT_CLOUD_API_SECRET environment variables are set"
  export TELEMETRY_DOCKER_COMPOSE_FILE_OVERRIDE="-f ${DIR_UTILS}/../environment/plaintext/docker-compose-telemetry.yml"
  if [ "$ENABLE_KRAFT" == "true" ]
  then
    export TELEMETRY_DOCKER_COMPOSE_FILE_OVERRIDE="${TELEMETRY_DOCKER_COMPOSE_FILE_OVERRIDE} -f ${DIR_UTILS}/../environment/plaintext/docker-compose-telemetry-kraft.yml"
  fi
}

# brokers only export metrics to prometheus-c3-v2 (control-center profile) when Control Center is enabled.
# Use the flag persisted by set_profiles rather than ENABLE_CONTROL_CENTER: it describes the running
# environment, also when run.docker_command is replayed later (container recreate...) from another shell
function determine_c3_telemetry() {
  export C3_TELEMETRY_ENABLED="false"
  if [ "$(playground state get flags.ENABLE_CONTROL_CENTER)" == "1" ]
  then
    export C3_TELEMETRY_ENABLED="true"
  fi
}

function determine_kraft_mode() {
  TAG_BASE=$(echo $TAG | cut -d "-" -f1)
  first_version=${TAG_BASE}
  if [[ -n $ENABLE_KRAFT ]] || version_gt $first_version "7.9.99"
  then
    if [[ -n $ENABLE_KRAFT ]]
    then
      log "🛰️ Starting up Confluent Platform in Kraft mode as ENABLE_KRAFT environment variable is set"
      if ! version_gt $TAG_BASE "7.3.99"
      then
        logerror "❌ Kraft mode is not supported with playground for CP version < 7.4, please use Zookeeper mode"
        exit 1
      fi
    else
      log "🛰️ Starting up Confluent Platform in Kraft mode as CP version is > 8"
    fi
    export ENABLE_KRAFT="true"
    export KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE="-f ${DIR_UTILS}/../environment/plaintext/docker-compose-kraft.yml"
    export MDC_KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE="-f ${DIR_UTILS}/../environment/mdc-plaintext/docker-compose-kraft.yml"
    export CONTROLLER_SECURITY_PROTOCOL_MAP=",CONTROLLER:PLAINTEXT"
    export KAFKA_AUTHORIZER_CLASS_NAME="org.apache.kafka.metadata.authorizer.StandardAuthorizer"
  else
    log "👨‍🦳 Starting up Confluent Platform in Zookeeper mode"
    export ENABLE_ZOOKEEPER="true"
    export KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE=""
    export MDC_KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE=""
    export CONTROLLER_SECURITY_PROTOCOL_MAP=""

    # Migrate SimpleAclAuthorizer to AclAuthorizer #1276
    if version_gt $TAG "5.3.99"
    then
      export KAFKA_AUTHORIZER_CLASS_NAME="kafka.security.authorizer.AclAuthorizer"
    else
      export KAFKA_AUTHORIZER_CLASS_NAME="kafka.security.auth.SimpleAclAuthorizer"
    fi
  fi
}

function set_profiles() {
  local nb_connect_services_value="${nb_connect_services:-0}"
  local docker_compose_file_override="${DOCKER_COMPOSE_FILE_OVERRIDE:-}"

  # https://docs.docker.com/compose/profiles/
  profile_zookeeper_command=""
  if [ -z "$ENABLE_ZOOKEEPER" ]
  then
    log "🛑 zookeeper is disabled"
    playground state del flags.ENABLE_ZOOKEEPER
  else
    log "👨‍⚕️ zookeeper is enabled"
    profile_zookeeper_command="--profile zookeeper"
    playground state set flags.ENABLE_ZOOKEEPER 1
  fi

  # profile_kraft_command=""
  # if [ -z "$ENABLE_KRAFT" ]
  # then
  #   log "🛑 kraft is disabled"
  #   playground state del flags.ENABLE_KRAFT
  # else
  #   log "🛰️ kraft is enabled"
  #   profile_kraft_command="--profile kraft"
  #   playground state set flags.ENABLE_KRAFT 1
  # fi


  profile_control_center_command=""
  if [ -z "$ENABLE_CONTROL_CENTER" ]
  then
    log "🛑 control-center is disabled"
    playground state del flags.ENABLE_CONTROL_CENTER
  else
    log "💠 control-center is enabled"
    log "Use http://localhost:9021 to login"
    profile_control_center_command="--profile control-center"
    playground state set flags.ENABLE_CONTROL_CENTER 1
  fi
  determine_c3_telemetry

  # Check if ENABLE_FLINK is set to true
  profile_flink=""
  if [ -z "$ENABLE_FLINK" ] 
  then
    log "🛑 Starting services without Flink"
    playground state del flags.ENABLE_FLINK
    export flink_connectors=""
  else
    log "🐿️ Starting services with Flink"
    profile_flink="--profile flink"
    playground state set flags.ENABLE_FLINK 1
    source ${DIR}/../../scripts/flink_download_connectors.sh
  fi

  profile_ksqldb_command=""
  if [ -z "$ENABLE_KSQLDB" ]
  then
    log "🛑 ksqldb is disabled"
    playground state del flags.ENABLE_KSQLDB
  else
    log "🚀 ksqldb is enabled"
    log "🔧 You can use ksqlDB with CLI using:"
    log "docker exec -i ksqldb-cli ksql http://ksqldb-server:8088"
    profile_ksqldb_command="--profile ksqldb"
    playground state set flags.ENABLE_KSQLDB 1
  fi

  profile_rest_proxy_command=""
  if [ -z "$ENABLE_RESTPROXY" ]
  then
    log "🛑 REST Proxy is disabled"
    playground state del flags.ENABLE_RESTPROXY
  else
    log "📲 REST Proxy is enabled"
    profile_rest_proxy_command="--profile rest-proxy"
    playground state set flags.ENABLE_RESTPROXY 1
  fi

  # defined grafana variable and when profile is included/excluded
  profile_grafana_command=""
  if [ -z "$ENABLE_JMX_GRAFANA" ]
  then
    log "🛑 Grafana is disabled"
    playground state del flags.ENABLE_JMX_GRAFANA
  else
    log "📊 Grafana is enabled"
    profile_grafana_command="--profile grafana"
    playground state set flags.ENABLE_JMX_GRAFANA 1
  fi
  profile_kcat_command=""
  if [ -z "$ENABLE_KCAT" ]
  then
    log "🛑 kcat is disabled"
    playground state del flags.ENABLE_KCAT
  else
    log "🧰 kcat is enabled"
    profile_kcat_command="--profile kcat"
    playground state set flags.ENABLE_KCAT 1
  fi
  profile_conduktor_command=""
  if [ -z "$ENABLE_CONDUKTOR" ]
  then
    log "🛑 conduktor is disabled"
    playground state del flags.ENABLE_CONDUKTOR
  else
    log "🐺 conduktor is enabled"
    log "Use http://localhost:8080/console to login"
    profile_conduktor_command="--profile conduktor"
    playground state set flags.ENABLE_CONDUKTOR 1
  fi
  profile_sql_datagen_command=""
  if [ ! -z "$SQL_DATAGEN" ]
  then
    profile_sql_datagen_command="--profile sql_datagen"
    playground state set flags.SQL_DATAGEN 1
  else
    playground state del flags.SQL_DATAGEN
  fi

  #define kafka_nodes variable and when profile is included/excluded
  profile_kafka_nodes_command=""
  if [ -z "$ENABLE_KAFKA_NODES" ]
  then
    profile_kafka_nodes_command=""
    playground state del flags.ENABLE_KAFKA_NODES
  else
    log "3️⃣  Multi broker nodes enabled"
    profile_kafka_nodes_command="--profile kafka_nodes"
    playground state set flags.ENABLE_KAFKA_NODES 1
  fi

  # defined 3 Connect variable and when profile is included/excluded
  profile_connect_nodes_command=""
  if [ -z "$ENABLE_CONNECT_NODES" ]
  then
    playground state del flags.ENABLE_CONNECT_NODES
  elif [ -n "$PLAYGROUND_CFK_MODE" ]
  then
    # CFK mode scales Connect via Kubernetes replicas, not docker-compose profiles.
    log "🥉 Multiple Connect nodes mode is enabled for CFK"
    playground state set flags.ENABLE_CONNECT_NODES 1
  elif [[ "$nb_connect_services_value" =~ ^[0-9]+$ ]] && [ "$nb_connect_services_value" -gt 1 ]
  then
    log "🥉 Multiple Connect nodes mode is enabled, connect2 and connect 3 containers will be started"
    profile_connect_nodes_command="--profile connect_nodes"
    export CONNECT_NODES_PROFILES="connect_nodes"
    playground state set flags.ENABLE_CONNECT_NODES 1
  else
    if [ -z "$docker_compose_file_override" ] || [ ! -f "$docker_compose_file_override" ]
    then
      log "🥉 Multiple connect nodes mode is enabled, connect2 and connect 3 containers will be started"
      profile_connect_nodes_command="--profile connect_nodes"
      playground state set flags.ENABLE_CONNECT_NODES 1
    else
      logerror "🛑 Could not find connect2 and connect3 in ${docker_compose_file_override}. Update the yaml files to contain the connect2 && connect3 in ${docker_compose_file_override}"
      exit 1
    fi
  fi
}

function get_confluent_version() {
  confluent version | grep "^Version:" | cut -d':' -f2 | cut -d'v' -f2
}

function get_ansible_version() {
  ansible --version | grep "core" | cut -d'[' -f2 | cut -d']' -f1 | cut -d' ' -f 2
}

function check_confluent_version() {
  REQUIRED_CONFLUENT_VER=${1:-"4.0.0"}
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
    if [ ! -z "$AWS_REGION" ]
    then
      if [ ! -f $HOME/.aws/config ]
      then
        aws_tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
        if [ -z "$PG_VERBOSE_MODE" ]
        then
            trap 'rm -rf $aws_tmp_dir' EXIT
        else
            log "🐛📂 not deleting aws tmp dir $aws_tmp_dir"
        fi
cat << EOF > $aws_tmp_dir/config
[default]
region = $AWS_REGION
EOF
      fi
    fi

    if [ ! -z "$AWS_ACCESS_KEY_ID" ] && [ ! -z "$AWS_SECRET_ACCESS_KEY" ]
    then
      AWS_ACCESS_KEY_ID=$(echo "$AWS_ACCESS_KEY_ID"| sed 's/[[:blank:]]//g')
      AWS_SECRET_ACCESS_KEY=$(echo "$AWS_SECRET_ACCESS_KEY"| sed 's/[[:blank:]]//g')
      AWS_SESSION_TOKEN=$(echo "$AWS_SESSION_TOKEN"| sed 's/[[:blank:]]//g')
      # log "💭 Using environment variables AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY"
      if [ -f $aws_tmp_dir/config ]
      then
        docker run --quiet --rm -iv $aws_tmp_dir/config:/root/.aws/config -e AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" -e AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" -e AWS_SESSION_TOKEN="$AWS_SESSION_TOKEN" -v $(pwd):/aws -v ${PLAYGROUND_HOST_TMP_DIR}:/tmp amazon/aws-cli "$@"
      else
        docker run --quiet --rm -iv $HOME/.aws/config:/root/.aws/config -e AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" -e AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" -e AWS_SESSION_TOKEN="$AWS_SESSION_TOKEN" -v $(pwd):/aws -v ${PLAYGROUND_HOST_TMP_DIR}:/tmp amazon/aws-cli "$@"
      fi
    else
      if [ ! -f $HOME/.aws/credentials ]
      then
        logerror "❌ $HOME/.aws/credentials does not exist"
      else
        # log "💭 AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY are set based on $HOME/.aws/credentials"
        docker run --quiet --rm -iv $HOME/.aws:/root/.aws -v $(pwd):/aws -v ${PLAYGROUND_HOST_TMP_DIR}:/tmp amazon/aws-cli "$@"
      fi
    fi
}

function timeout() {
  verbose_begin
  if [[ $(type -f timeout 2>&1) =~ "not found" ]]; then
    # ignore
    shift
    eval "$@"
  else
    $(type -f timeout | awk '{print $3}') "$@"
  fi
  verbose_end
}

function get_connect_image() {
  set +e
  CP_CONNECT_TAG=$(docker inspect -f '{{.Config.Image}}' connect 2> /dev/null | cut -d ":" -f 2)
  # If docker inspect failed, try kubectl for Kubernetes/CFK environment
  if [ -z "$CP_CONNECT_TAG" ] && command -v kubectl &> /dev/null; then
    CP_CONNECT_TAG=$(kubectl get pod -l app=connect -o jsonpath='{.items[0].spec.containers[0].image}' 2> /dev/null | cut -d ":" -f 2)
  fi
  set -e
  if [ "$CP_CONNECT_TAG" == "" ]
  then
    if [ -z "$TAG" ]
    then
      CP_CONNECT_TAG=$(grep "export TAG" $root_folder/scripts/utils.sh | head -1 | cut -d "=" -f 2 | cut -d " " -f 1)
    else
      CP_CONNECT_TAG=$TAG
    fi

    if [ "$CP_CONNECT_TAG" == "" ]
    then
      logerror "Error while getting default TAG in get_connect_image()"
      exit 1
    fi
  fi

  if [ -z "$CP_CONNECT_IMAGE" ]
  then
    if version_gt $CP_CONNECT_TAG 5.2.99
    then
      CP_CONNECT_IMAGE=confluentinc/cp-server-connect
    else
      CP_CONNECT_IMAGE=confluentinc/cp-kafka-connect
    fi
  fi
}

function az() {
  docker run --quiet --rm -v ${PLAYGROUND_HOST_TMP_DIR}:/tmp -v $HOME/.azure:/home/az/.azure -e HOME=/home/az --rm -i mcr.microsoft.com/azure-cli:azurelinux3.0 az "$@"
}

function retry() {
  local n=1
  local max_retriable=3
  local max_default_retry=1
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
      test_file=$(echo "$@" | awk '{ print $4}')
      script=$(basename $test_file)
      # check for retriable scripts in scripts/tests-retriable.txt
      grep "$script" ${DIR}/tests-retriable.txt > /dev/null
      if [ $? = 0 ]
      then
        if [[ $n -lt $max_retriable ]]; then
          ((n++))
          logwarn "####################################################"
          logwarn "🧟‍♂️ The test $script (retriable) has failed. Retrying (attempt $n/$max_retriable)"
          logwarn "####################################################"
          playground container display-error-all
        else
          logerror "💀 The test $script (retriable) has failed after $n attempts."
          playground container display-error-all
          return 1
        fi
      else
        if [[ $n -lt $max_default_retry ]]; then
          ((n++))
          logwarn "####################################################"
          logwarn "🎰 The test $script (default_retry) has failed. Retrying (attempt $n/$max_default_retry)"
          logwarn "####################################################"
          playground container display-error-all
        else
          logerror "💀 The test $script (default_retry) has failed after $n attempts."
          playground container display-error-all
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
            playground container display-error-all
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

# Build a java component, e.g. build_java_component_with_retry "${component}" docker run ... mvn ... package
# Maven Central occasionally rate-limits (HTTP 429) dependency resolution,
# so retry with backoff before treating it as a real failure.
function build_java_component_with_retry() {
  local component="$1"
  shift
  local max_attempts=3
  local attempt

  for attempt in $(seq 1 $max_attempts)
  do
    if "$@" > /tmp/result.log 2>&1
    then
      return 0
    fi
    if [ $attempt == $max_attempts ]
    then
      logerror "❌ failed to build java component $component after $max_attempts attempts"
      tail -100 /tmp/result.log
      exit 1
    fi
    logwarn "⚠️ failed to build java component $component (attempt $attempt/$max_attempts), retrying in case it's transient (e.g. Maven Central rate-limiting)"
    sleep $((attempt * 15))
  done
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
  playground stop
}

function wait_container_ready() {
  # Record the start time
  start_time=$SECONDS
  
  CONNECT_CONTAINER=${1:-"connect"}
  CONTROL_CENTER_CONTAINER=${2:-"control-center"}
  MAX_WAIT=300

  if [[ -n "$START_SERVICES" ]] \
     && [[ ! " $START_SERVICES " == *" ${CONNECT_CONTAINER}"* ]] \
     && [[ ! " $START_SERVICES " == *" ${CONTROL_CENTER_CONTAINER}"* ]]
  then
    log "🔍 Skipping readiness wait: START_SERVICES='${START_SERVICES}' does not include ${CONNECT_CONTAINER} or ${CONTROL_CENTER_CONTAINER}"
    return
  fi

  if [[ "$PLAYGROUND_ENVIRONMENT" == "cfk" ]]
  then
    if [ ! -z $WAIT_FOR_CONTROL_CENTER ]
    then
      CFK_POD_NAME="controlcenter-0"
    elif [[ $CONNECT_CONTAINER == connect* ]]
    then
      CFK_POD_NAME="connect-0"
    else
      CFK_POD_NAME="$CONNECT_CONTAINER"
    fi

    log "⌛ Waiting up to $MAX_WAIT seconds for CFK pod ${CFK_POD_NAME} to start"
    set +e
    CFK_WAIT_INTERVAL=5
    CFK_CUR_WAIT=0
    while true
    do
      if kubectl -n confluent get pod "${CFK_POD_NAME}" > /dev/null 2>&1
      then
        kubectl -n confluent wait --for=condition=Ready "pod/${CFK_POD_NAME}" --timeout="${CFK_WAIT_INTERVAL}s" > /dev/null 2>&1
        if [[ $? -eq 0 ]]
        then
          break
        fi
      fi

      CFK_CUR_WAIT=$(( CFK_CUR_WAIT + CFK_WAIT_INTERVAL ))
      if [[ "$CFK_CUR_WAIT" -ge "$MAX_WAIT" ]]
      then
        logwarn "Could not confirm readiness for pod ${CFK_POD_NAME}, listing current pods in namespace confluent"
        kubectl -n confluent get pods || true
        logerror "CFK pod ${CFK_POD_NAME} did not become ready in ${MAX_WAIT} seconds"
        exit 1
      fi
      sleep "$CFK_WAIT_INTERVAL"
    done
    set -e

    # Calculate elapsed time
    elapsed_time=$(( SECONDS - start_time ))
    log "🚦 CFK pod ${CFK_POD_NAME} is ready! (took $elapsed_time seconds)"
    return
  fi

  if [ ! -z $WAIT_FOR_CONTROL_CENTER ]
  then
    log "⌛ Waiting up to $MAX_WAIT seconds for ${CONTROL_CENTER_CONTAINER} to start"
    playground --output-level WARN container logs --container $CONTROL_CENTER_CONTAINER --wait-for-log "Started NetworkTrafficServerConnector" --max-wait $MAX_WAIT
  elif [[ $CONNECT_CONTAINER == connect* ]]
  then
    log "⌛ Waiting up to $MAX_WAIT seconds for ${CONNECT_CONTAINER} to start"
    playground container wait-for-connect-rest-api-ready --max-wait $MAX_WAIT
  else
    log "⌛ Waiting up to $MAX_WAIT seconds for ${CONNECT_CONTAINER} to start"
    playground container logs --container $CONNECT_CONTAINER --wait-for-log "Finished starting connectors and tasks" --max-wait $MAX_WAIT
  fi

  # Verify Docker containers started
  if [[ $(docker container ps) =~ "Exit 137" ]]
  then
    logerror "at least one Docker container did not start properly, see <docker container ps>"
    exit 1
  fi

  # Calculate elapsed time
  elapsed_time=$(( SECONDS - start_time ))

  log "🚦 containers have started! (took $elapsed_time seconds)"
}

function display_jmx_info() {
  if [[ "$PLAYGROUND_ENVIRONMENT" == "cfk" ]]
  then
    log "📊 CFK JMX metrics endpoints are available inside each pod:"
    log "    - JMX      : 7203"
    log "    - Jolokia  : 7777"
    log "    - Prometheus exporter : 7778"
    return
  fi

  if [ -z "$ENABLE_JMX_GRAFANA" ]
  then
    log "📊 JMX metrics are available locally on those ports:"
  else
    log "🛡️ Prometheus is reachable at http://127.0.0.1:9090"
    log "📛 Pyroscope is reachable at http://127.0.0.1:4040"
    log "📊 Grafana is reachable at http://127.0.0.1:3000 (login/password is admin/password) or JMX metrics are available locally on those ports:"
  fi
  if [ ! -z $ENABLE_KRAFT ]
  then
    log "    - kraft-controller : 10005"
  else
    log "    - zookeeper       : 9999"
  fi
  log "    - zookeeper       : 9999"
  log "    - broker          : 10000"
  log "    - schema-registry : 10001"
  log "    - connect         : 10002"

  if [ ! -z "$ENABLE_KSQLDB" ]
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

  container="$1"
  domains="$2"
  open="$3"
  get_environment_used

  target_container="$container"
  jmx_disabled_hint="See https://docs.confluent.io/operator/current/co-monitor-cp.html#jmx-metrics"
  jmx_exec() {
    local args="$1"
    if [[ "$environment" == "cfk" ]]
    then
      kubectl -n confluent exec -i "$target_container" -- java -jar "$JMXTERM_UBER_JAR" -l "localhost:$port" -n $args
    else
      docker exec -i "$container" java -jar "$JMXTERM_UBER_JAR" -l "localhost:$port" -n $args
    fi
  }

  if [[ "$environment" == "cfk" ]]
  then
    case "$container" in
      connect2)
        target_container="connect-1"
      ;;
      connect3)
        target_container="connect-2"
      ;;
      connect|connect-[0-9]*|broker|schema-registry|controller|zookeeper)
        target_container="$container"
      ;;
      *)
        target_container=$(resolve_container_name_for_environment "$container")
      ;;
    esac
  fi
  if [ "$domains" = "" ]
  then
    # non existing domain: all domains will be in output !
    logwarn "You did not specify a list of domains, all domains will be exported!"
    domains="ALL"
  fi

  case "$container" in
  zookeeper )
    port=9999
  ;;
  controller )
    port=10005
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
  connect2 )
    port=10022
  ;;
  connect3 )
    port=10032
  ;;
  connect-[0-9]* )
    port=10002
  ;;
  n|N ) ;;
  * ) logerror "invalid container $container! it should be one of zookeeper, broker, schema-registry, connect, connect2, connect3 or connect-<n>";exit 1;;
  esac

  if [[ "$environment" == "cfk" ]]
  then
    # CFK JMX defaults to 7203 on each component pod.
    port=7203
  fi

  playground container cp --source $JMXTERM_UBER_JAR --destination $target_container:$JMXTERM_UBER_JAR
  if [ "$domains" = "ALL" ]
  then

log "This is the list of domains for container $container"
if ! jmx_exec "-v silent" << EOF
domains
exit
EOF
then
  logwarn "JMX endpoint is unavailable for $container. JMX may be disabled. $jmx_disabled_hint"
  return 0
fi
  fi

for domain in `echo $domains`
do
if ! jmx_exec "-v silent" > /tmp/beans.log << EOF
domain $domain
beans
exit
EOF
then
  logwarn "JMX endpoint is unavailable for $container (domain: $domain). JMX may be disabled. $jmx_disabled_hint"
  return 0
fi
  while read line; do echo "get *"  -b $line; done < /tmp/beans.log >> /tmp/commands

  if [[ -n "$open" ]]
  then
    echo "####### domain $domain ########" >> /tmp/jmx_metrics.log
    if ! jmx_exec "" < /tmp/commands >> /tmp/jmx_metrics.log 2>&1
    then
      logwarn "JMX endpoint is unavailable for $container (domain: $domain). JMX may be disabled. $jmx_disabled_hint"
      return 0
    fi
  else
    echo "####### domain $domain ########"
    if ! jmx_exec "" < /tmp/commands 2>&1
    then
      logwarn "JMX endpoint is unavailable for $container (domain: $domain). JMX may be disabled. $jmx_disabled_hint"
      return 0
    fi
  fi
done

  if [[ -n "$open" ]]
  then
    playground open --file "/tmp/jmx_metrics.log"
  fi
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
  log "attempting to get the file $file from Confluent S3 bucket (only works for Confluent employees when aws creds are set)..."
  log "command is <aws s3 ls s3://kafka-docker-playground/$folder/$file"
  handle_aws_credentials
  aws s3 ls s3://kafka-docker-playground/$folder/$file > /dev/null 2>&1
  if [ $? -eq 0 ]
  then
      log "Downloading <s3://kafka-docker-playground/$folder/$file> from S3 bucket"
      if [ ! -z "$GITHUB_RUN_NUMBER" ]
      then
        aws s3 cp --only-show-errors "s3://kafka-docker-playground/$folder/$file" .
      else
        aws s3 cp "s3://kafka-docker-playground/$folder/$file" .
      fi
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
  elif [ "$ZIP_FILE" == "LINUX.X64_180000_db_home.zip" ]
  then
      ORACLE_VERSION="18.3.0-ee"
  elif [ "$ZIP_FILE" == "LINUX.X64_213000_db_home.zip" ]
  then
      ORACLE_VERSION="21.3.0-ee"
  else
      ORACLE_VERSION="19.3.0-ee"
  fi

  SETUP_FILE=${SETUP_FOLDER}/01_user-setup.sh
  SETUP_FILE_CKSUM=$(cksum $SETUP_FILE | awk '{ print $1 }')
  if [ "$(uname -m)" = "arm64" ]
  then
      export ORACLE_IMAGE="db-prebuilt-arm64-$SETUP_FILE_CKSUM:$ORACLE_VERSION"
  else
      export ORACLE_IMAGE="db-prebuilt-$SETUP_FILE_CKSUM:$ORACLE_VERSION"
  fi

  if ! test -z "$(docker images -q $ORACLE_IMAGE)"
  then
    log "🧹 Removing Oracle image $ORACLE_IMAGE"
    docker image rm $ORACLE_IMAGE
  fi
}

function create_or_get_oracle_image() {
  local ZIP_FILE="$1"
  local SETUP_FOLDER="$2"

  if [ "$ZIP_FILE" == "linuxx64_12201_database.zip" ]
  then
      ORACLE_VERSION="12.2.0.1-ee"
  elif [ "$ZIP_FILE" == "LINUX.X64_180000_db_home.zip" ]
  then
      ORACLE_VERSION="18.3.0-ee"
  elif [ "$ZIP_FILE" == "LINUX.X64_213000_db_home.zip" ]
  then
      ORACLE_VERSION="21.3.0-ee"
  else
      if [ "$(uname -m)" = "arm64" ]
      then
          ZIP_FILE="LINUX.ARM64_1919000_db_home.zip"
      else
          ZIP_FILE="LINUX.X64_193000_db_home.zip"
      fi
      ORACLE_VERSION="19.3.0-ee"
  fi
  # used for docker-images repo
  DOCKERFILE_VERSION=$(echo "$ORACLE_VERSION" | cut -d "-" -f 1)

  # https://github.com/oracle/docker-images/tree/main/OracleDatabase/SingleInstance/samples/prebuiltdb
  SETUP_FILE=${SETUP_FOLDER}/01_user-setup.sh
  SETUP_FILE_CKSUM=$(cksum $SETUP_FILE | awk '{ print $1 }')

  if [ "$(uname -m)" = "arm64" ]
  then
      export ORACLE_IMAGE="db-prebuilt-arm64-$SETUP_FILE_CKSUM:$ORACLE_VERSION"
  else
      export ORACLE_IMAGE="db-prebuilt-$SETUP_FILE_CKSUM:$ORACLE_VERSION"
  fi
  TEMP_CONTAINER="oracle-build-$ORACLE_VERSION-$(basename $SETUP_FOLDER)"

  if test -z "$(docker images -q $ORACLE_IMAGE)"
  then
    set +e
    log "attempting to get the Oracle prebuilt docker image from Confluent S3 bucket (only works for Confluent employees)..."
    log "command is <aws s3 ls s3://kafka-docker-playground/3rdparty/$ORACLE_IMAGE.tar>"
    handle_aws_credentials
    aws s3 ls s3://kafka-docker-playground/3rdparty/$ORACLE_IMAGE.tar
    if [ $? -eq 0 ]
    then
        log "Downloading prebuilt image <s3://kafka-docker-playground/3rdparty/$ORACLE_IMAGE.tar> from S3 bucket"
        if [ ! -z "$GITHUB_RUN_NUMBER" ]
        then
          aws s3 cp --only-show-errors "s3://kafka-docker-playground/3rdparty/$ORACLE_IMAGE.tar" .
        else
          aws s3 cp "s3://kafka-docker-playground/3rdparty/$ORACLE_IMAGE.tar" .
        fi
        if [ $? -eq 0 ]
        then
          log "📄 <s3://kafka-docker-playground/3rdparty/$ORACLE_IMAGE.tar> was downloaded from S3 bucket"
          docker load -i $ORACLE_IMAGE.tar
          if [ $? -eq 0 ]
          then
            log "📄 image $ORACLE_IMAGE has been installed locally"
          fi

          if [[ "$OSTYPE" == "darwin"* ]]
          then
            log "🧹 Removing prebuilt image $ORACLE_IMAGE.tar"
            rm -f $ORACLE_IMAGE.tar
          else
            log "🧹 Removing prebuilt image $ORACLE_IMAGE.tar with sudo"
            sudo rm -f $ORACLE_IMAGE.tar
          fi
        fi
    else
      logwarn "If you're a Confluent employee, please check this link https://confluent.slack.com/archives/C0116NM415F/p1636391410032900 and also here https://confluent.slack.com/archives/C0116NM415F/p1636389483030900"
      logwarn "re-run with <playground -v (or --vvv) run> to troubleshoot"
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
    handle_aws_credentials
    aws s3 ls s3://kafka-docker-playground/3rdparty/oracle_database_$ORACLE_VERSION.tar > /dev/null 2>&1
    if [ $? -eq 0 ]
    then
        log "Downloading <s3://kafka-docker-playground/3rdparty/oracle_database_$ORACLE_VERSION.tar> from S3 bucket"
        if [ ! -z "$GITHUB_RUN_NUMBER" ]
        then
          aws s3 cp --only-show-errors "s3://kafka-docker-playground/3rdparty/oracle_database_$ORACLE_VERSION.tar" .
        else
          aws s3 cp "s3://kafka-docker-playground/3rdparty/oracle_database_$ORACLE_VERSION.tar" .
        fi
        if [ $? -eq 0 ]
        then
          log "📄 <s3://kafka-docker-playground/3rdparty/oracle_database_$ORACLE_VERSION.tar> was downloaded from S3 bucket"
          docker load -i oracle_database_$ORACLE_VERSION.tar
          if [ $? -eq 0 ]
          then
            log "📄 image $BASE_ORACLE_IMAGE has been installed locally"
          fi

          if [[ "$OSTYPE" == "darwin"* ]]
          then
            log "🧹 Removing $ORACLE_IMAGE.tar"
            rm -f oracle_database_$ORACLE_VERSION.tar
          else
            log "🧹 Removing $ORACLE_IMAGE.tar with sudo"
            sudo rm -f oracle_database_$ORACLE_VERSION.tar
          fi
        fi
    fi
    set -e
  fi

  if test -z "$(docker images -q $BASE_ORACLE_IMAGE)"
  then
      if [ ! -f ${ZIP_FILE} ]
      then
          set +e
          handle_aws_credentials
          aws s3 ls s3://kafka-docker-playground/3rdparty/${ZIP_FILE} > /dev/null 2>&1
          if [ $? -eq 0 ]
          then
              log "Downloading <s3://kafka-docker-playground/3rdparty/${ZIP_FILE}> from S3 bucket"

              if [ ! -z "$GITHUB_RUN_NUMBER" ]
              then
                aws s3 cp --only-show-errors "s3://kafka-docker-playground/3rdparty/${ZIP_FILE}" .
              else
                aws s3 cp "s3://kafka-docker-playground/3rdparty/${ZIP_FILE}" .
              fi
              if [ $? -eq 0 ]
              then
                log "📄 <s3://kafka-docker-playground/3rdparty/${ZIP_FILE}> was downloaded from S3 bucket"
              fi
          fi
          set -e
      fi
      if [ ! -f ${ZIP_FILE} ]
      then
          logerror "❌ ${ZIP_FILE} is missing. It must be downloaded manually in order to acknowledge user agreement"
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
      while [[ ! $(cat /tmp/out.txt) =~ "DATABASE IS READY TO USE" ]]; do
      sleep 10
      docker container logs ${TEMP_CONTAINER} > /tmp/out.txt 2>&1
      CUR_WAIT=$(( CUR_WAIT+10 ))
      if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
            logerror "❌ The logs in ${TEMP_CONTAINER} container do not show 'DATABASE IS READY TO USE' after $MAX_WAIT seconds. Please troubleshoot with 'docker container ps' and 'playground container logs --open --container <container>'.\n"
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

      if [ ! -z "$GITHUB_RUN_NUMBER" ]
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

function get_kafka_docker_playground_dir () {
  DIR_UTILS="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
  KAFKA_DOCKER_PLAYGROUND_DIR="$(echo $DIR_UTILS | sed 's|\(.*kafka-docker-playground\).*|\1|')"
}

function maybe_delete_ccloud_environment () {
  get_kafka_docker_playground_dir
  DELTA_CONFIGS_ENV=$KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/env.delta

  if [ -f $DELTA_CONFIGS_ENV ]
  then
    source $DELTA_CONFIGS_ENV
  else
    logerror "❌ $DELTA_CONFIGS_ENV has not been generated"
    exit 1
  fi

  if [ -z "$CLUSTER_NAME" ]
  then
    #
    # CLUSTER_NAME is not set
    #
    log "🧹❌ Confluent Cloud cluster will be deleted..."
    verify_installed "confluent"
    check_confluent_version 4.32.0 || exit 1
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

function check_expected_ccloud_details () {
  local expected_cloud="$1"
  local expected_region="$2"

  if [ -n "$expected_cloud" ] && [ -n "$expected_region" ]
  then
    expected_failed=0
    if [ "$expected_cloud" != "$CLUSTER_CLOUD" ]
    then
      logerror "❌🌤 expected ccloud cloud provider for the example is $expected_cloud but you're using $CLUSTER_CLOUD"
      expected_failed=1
    fi

    if [ "$expected_region" != "$CLUSTER_REGION" ]
    then
      logerror "❌🗺 expected ccloud region for the example is $expected_region but you're using $CLUSTER_REGION"
      expected_failed=1
    fi

    if [ $expected_failed == 1 ]
    then
      exit 1
    fi
  fi
}

function bootstrap_ccloud_environment () {

  local expected_cloud="$1"
  local expected_region="$2"
  local connect_migration_utility="$3"
  local ccloud_cluster_list=""

  DIR_UTILS="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
  get_kafka_docker_playground_dir
  DELTA_CONFIGS_ENV=$KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/env.delta

  if [ -z "$GITHUB_RUN_NUMBER" ] && [ -z "$CLOUDFORMATION" ]
  then
    # not running with CI
    verify_installed "confluent"
    # list clusters in the background while the version is checked: the output is used both to verify the
    # CLI is logged in and to detect that CLUSTER_NAME is already the current cluster
    ccloud_cluster_list=$(mktemp)
    confluent kafka cluster list --output json > "$ccloud_cluster_list" 2>&1 &
    local ccloud_cluster_list_pid=$!
    check_confluent_version 4.32.0 || exit 1
    wait $ccloud_cluster_list_pid || true
    if grep -q -e "You must login to run that command" -e "Your session has expired" "$ccloud_cluster_list"
    then
      logerror "This script requires confluent CLI to be logged in. Please execute 'confluent login' and run again."
      exit 1
    fi
  else
    if [ ! -f /usr/local/bin/confluent ]
    then
      log "🚚 installing confluent CLI"
      # the installer runs "curl -n" and recent curl (8.18 on ubuntu 26.04) fails with "(26) .netrc error: no such file" when ~/.netrc is missing
      sudo sh -c 'touch "$HOME/.netrc"'
      for i in 1 2 3 4 5
      do
        curl -fsSL --http1.1 https://cnfl.io/cli | sudo sh -s -- -b /usr/local/bin && break
        logwarn "confluent CLI install failed (attempt $i/5), retrying in 10s..."
        sleep 10
      done
      if [ ! -f /usr/local/bin/confluent ]
      then
        logerror "❌ failed to install confluent CLI after 5 attempts"
        exit 1
      fi
    fi
    export PATH=$PATH:/usr/local/bin
    log "⛺ log in to Confluent Cloud"
    confluent login --save
  fi

  playground ccloud-costs-history > /tmp/ccloud-costs-history.txt &

  suggest_use_previous_example_ccloud=1
  test_file=$(playground state get run.test_file)

  if [ -f "$test_file" ]
  then
    if [[ $test_file == *"fm-databricks-delta-lake-sink"* ]] || ( [[ -n "$connect_migration_utility" ]] && [[ $test_file == *"connect-databricks"* ]] )
    then
      if [ ! -z "$AWS_DATABRICKS_CLUSTER_NAME" ]
      then
        log "AWS_DATABRICKS_CLUSTER_NAME environment variable is set, forcing the cluster $AWS_DATABRICKS_CLUSTER_NAME to be used !"
        suggest_use_previous_example_ccloud=0
        export CLUSTER_NAME=$AWS_DATABRICKS_CLUSTER_NAME
        export CLUSTER_REGION=$AWS_DATABRICKS_CLUSTER_REGION
        export CLUSTER_CLOUD=$AWS_DATABRICKS_CLUSTER_CLOUD
        export CLUSTER_CREDS=$AWS_DATABRICKS_CLUSTER_CREDS
      fi
    fi

    if [[ $test_file == *"fm-aws"* ]] || ( [[ -n "$connect_migration_utility" ]] && [[ $test_file == *"connect-aws"* ]] )
    then
      if [ ! -z "$AWS_CLUSTER_NAME" ]
      then
        log "🤖 AWS Fully managed example and AWS_CLUSTER_NAME environment variable is set, forcing the cluster $AWS_CLUSTER_NAME to be used !"
        suggest_use_previous_example_ccloud=0
        export CLUSTER_NAME=$AWS_CLUSTER_NAME
        export CLUSTER_REGION=$AWS_CLUSTER_REGION
        export CLUSTER_CLOUD=$AWS_CLUSTER_CLOUD
        export CLUSTER_CREDS=$AWS_CLUSTER_CREDS
      fi
    fi

    if [[ $test_file == *"fm-gcp"* ]] || [[ $test_file == *"fm-debezium-gcp"* ]] || ( [[ -n "$connect_migration_utility" ]] && [[ $test_file == *"connect-gcp"* ]] )
    then
      if [ ! -z "$GCP_CLUSTER_NAME" ]
      then
        log "🤖 GCP Fully managed example and GCP_CLUSTER_NAME environment variable is set, forcing the cluster $GCP_CLUSTER_NAME to be used !"
        suggest_use_previous_example_ccloud=0
        export CLUSTER_NAME=$GCP_CLUSTER_NAME
        export CLUSTER_REGION=$GCP_CLUSTER_REGION
        export CLUSTER_CLOUD=$GCP_CLUSTER_CLOUD
        export CLUSTER_CREDS=$GCP_CLUSTER_CREDS
      fi
    fi

    if [[ $test_file == *"fm-azure"* ]] || ( [[ -n "$connect_migration_utility" ]] && [[ $test_file == *"connect-azure"* ]] ) || ( [[ $test_file == *"fm-custom-smt"* ]] && ( [[ "$USER" == "vsaboulin" ]] || [[ "$USER" == "runner" ]] ) )
    then
      if [ ! -z "$AZURE_CLUSTER_NAME" ]
      then
        log "🤖 Azure Fully managed example and AZURE_CLUSTER_NAME environment variable is set, forcing the cluster $AZURE_CLUSTER_NAME to be used !"
        suggest_use_previous_example_ccloud=0
        export CLUSTER_NAME=$AZURE_CLUSTER_NAME
        export CLUSTER_REGION=$AZURE_CLUSTER_REGION
        export CLUSTER_CLOUD=$AZURE_CLUSTER_CLOUD
        export CLUSTER_CREDS=$AZURE_CLUSTER_CREDS
      fi
    fi
  fi
  
  for item in {ENVIRONMENT,CLUSTER_NAME,CLUSTER_CLOUD,CLUSTER_REGION,CLUSTER_CREDS}
  do
      i=$(playground state get "ccloud.${item}")
      if [ "$i" == "" ]
      then
        # at least one mandatory field is missing
        suggest_use_previous_example_ccloud=0
        break
      fi
  done

  if [ ! -z "$CLUSTER_NAME" ]
  then
    if [ "$(playground state get "ccloud.CLUSTER_NAME")" == "$CLUSTER_NAME" ]
    then
      suggest_use_previous_example_ccloud=0
    fi
  fi

  if [ "$(playground state get "ccloud.suggest_use_previous_example_ccloud")" == "0" ]
  then
    suggest_use_previous_example_ccloud=0
  fi

  if [ $suggest_use_previous_example_ccloud -eq 1 ] && [ -z "$GITHUB_RUN_NUMBER" ]
  then
    log "🙋 Use previously used ccloud cluster:"
    log "  🌐 ENVIRONMENT=$(playground state get ccloud.ENVIRONMENT)"
    log "  🎰 CLUSTER_NAME=$(playground state get ccloud.CLUSTER_NAME)"
    log "  🌤  CLUSTER_CLOUD=$(playground state get ccloud.CLUSTER_CLOUD)"
    log "  🗺  CLUSTER_REGION=$(playground state get ccloud.CLUSTER_REGION)"

    read -p "Continue (y/n)?" choice
    case "$choice" in
    y|Y ) 
      ENVIRONMENT=$(playground state get ccloud.ENVIRONMENT)
      CLUSTER_NAME=$(playground state get ccloud.CLUSTER_NAME)
      CLUSTER_CLOUD=$(playground state get ccloud.CLUSTER_CLOUD)
      CLUSTER_REGION=$(playground state get ccloud.CLUSTER_REGION)
      CLUSTER_CREDS=$(playground state get ccloud.CLUSTER_CREDS)
      SCHEMA_REGISTRY_CREDS=$(playground state get ccloud.SCHEMA_REGISTRY_CREDS)
      ;;
    n|N ) 
      playground state del ccloud.ENVIRONMENT
      playground state del ccloud.CLUSTER_NAME
      playground state del ccloud.CLUSTER_CLOUD
      playground state del ccloud.CLUSTER_REGION
      playground state del ccloud.CLUSTER_CREDS
      playground state del ccloud.SCHEMA_REGISTRY_CREDS
      ;;
    * ) 
      logerror "invalid response!";
      exit 1
      ;;
    esac
  fi

  if [ -z "$CLUSTER_NAME" ]
  then
    #
    # CLUSTER_NAME is not set
    #
    if [ -n "$ccloud_cluster_list" ]
    then
      rm -f "$ccloud_cluster_list"
    fi
    log "🛠👷‍♀️ CLUSTER_NAME is not set, a new Confluent Cloud cluster will be created..."
    log "🎓 If you wanted to use an existing cluster, set CLUSTER_NAME, ENVIRONMENT, CLUSTER_CLOUD, CLUSTER_REGION and CLUSTER_CREDS (also optionnaly SCHEMA_REGISTRY_CREDS)"

    if [ -z "$CLUSTER_CLOUD" ] || [ -z "$CLUSTER_REGION" ]
    then
      logwarn "CLUSTER_CLOUD and/or CLUSTER_REGION are not set, the cluster will be created 🌤 AWS provider and 🗺 eu-west-2 region"
      export CLUSTER_CLOUD=aws
      export CLUSTER_REGION=eu-west-2
      if [ -z "$CLUSTER_TYPE" ]
      then
        export CLUSTER_TYPE=basic
      fi
    fi

    if [ ! -z "$CLUSTER_CREDS" ]
    then
      # make sure it is unset
      unset CLUSTER_CREDS
    fi

    if [ ! -z $ENVIRONMENT ]
    then
      log "🌐 ENVIRONMENT is set with $ENVIRONMENT and will be used"
    else
      if [ ! -z "$SCHEMA_REGISTRY_CREDS" ]
      then
        # make sure it is unset
        unset SCHEMA_REGISTRY_CREDS
      fi
    fi
    log "🔋 CLUSTER_TYPE is set with $CLUSTER_TYPE"
    log "🌤  CLUSTER_CLOUD is set with $CLUSTER_CLOUD"
    log "🗺  CLUSTER_REGION is set with $CLUSTER_REGION"

    export EXAMPLE=$(basename $PWD)
    export QUIET=true

    log "💡 if you notice that the playground is using unexpected ccloud details, use <playground cleanup-cloud-details> to remove all caching and re-launch the example"
    check_if_continue
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

    check_expected_ccloud_details "$expected_cloud" "$expected_region"

    log "💡 if you notice that the playground is using unexpected ccloud details, use <playground cleanup-cloud-details> to remove all caching and re-launch the example"
    
    if [ -z "$ccloud_cluster_list" ]
    then
      ccloud_cluster_list=$(mktemp)
      confluent kafka cluster list --output json > "$ccloud_cluster_list"
    fi
    is_current=$(jq -r --arg name "$CLUSTER_NAME" 'any(.[]; .is_current == true and .name == $name)' "$ccloud_cluster_list" 2>/dev/null || echo false)
    rm -f "$ccloud_cluster_list"

    if [ "$is_current" == "true" ]
    then
      if [ -f $DELTA_CONFIGS_ENV ]
      then
        source $DELTA_CONFIGS_ENV
        log "🌱 cluster $CLUSTER_NAME is ready to be used!"

        if [[ ! -n "$connect_migration_utility" ]]
        then
          # trick
          playground state set run.environment "ccloud"
        fi
        return
      else
        logwarn "$DELTA_CONFIGS_ENV has not been generated, doing it now..."
      fi
    fi
  fi

  check_expected_ccloud_details "$expected_cloud" "$expected_region"

  ccloud::create_ccloud_stack false

  CCLOUD_CONFIG_FILE=/tmp/tmp.config
  export CCLOUD_CONFIG_FILE=$CCLOUD_CONFIG_FILE
  ccloud::validate_ccloud_config $CCLOUD_CONFIG_FILE || exit 1

  ccloud::generate_configs $CCLOUD_CONFIG_FILE

  if [ -f $DELTA_CONFIGS_ENV ]
  then
    source $DELTA_CONFIGS_ENV
  else
    logerror "❌ $DELTA_CONFIGS_ENV has not been generated"
    exit 1
  fi

  playground state set ccloud.ENVIRONMENT "$ENVIRONMENT"
  playground state set ccloud.CLUSTER_NAME "$CLUSTER_NAME"
  playground state set ccloud.CLUSTER_CLOUD "$CLUSTER_CLOUD"
  playground state set ccloud.CLUSTER_REGION "$CLUSTER_REGION"
  playground state set ccloud.CLUSTER_CREDS "$CLUSTER_CREDS"
  playground state set ccloud.SCHEMA_REGISTRY_CREDS "$SCHEMA_REGISTRY_CREDS"

  if [[ ! -n "$connect_migration_utility" ]]
  then
	# trick
	playground state set run.environment "ccloud"
  fi
}

function create_ccloud_connector() {
  file=$1

  log "🛠️ Creating connector from $file"
  confluent connect cluster create --config-file $file
  if [[ $? != 0 ]]
  then
    logerror "Exit status was not 0 while creating connector from $file.  Please troubleshoot and try again"
  fi

  return 0
}

function validate_ccloud_connector_up() {
  connector="$1"
  if [ -f "/tmp/config-$connector" ]
  then
    set +e
    PG_SKIP_ERROR_RECOMMENDATIONS=1 playground connector create-or-update --connector "$connector" --no-clipboard < "/tmp/config-$connector" > /tmp/output.log 2>&1
    if [ $? -ne 0 ]
    then
      echo "💀"
    else
      echo "🔁"
      cat /tmp/output.log | grep "$connector" | grep -v "\"name\"" | grep -v "ℹ️" | grep -v "playground connector create-or-update"
    fi
  else
    echo "❌"
  fi
  set -e

  connector_status=$(confluent connect cluster list -o json 2>/dev/null | jq -r 'map(select(.name == "'"$connector"'")) | .[0].status // empty' 2>/dev/null)
  if [ "$connector_status" == "RUNNING" ]
  then
    return 0
  fi

  if [ "$connector_status" == "FAILED" ]
  then
    # re-applying an identical config does not restart a failed connector or task, so a transient
    # failure at startup (e.g. 401 API_KEY_NOT_FOUND from Schema Registry right after provisioning)
    # would stay FAILED until the end of the wait: restart it explicitly
    set +e
    echo "🔄 connector $connector is FAILED, restarting it"
    playground connector restart --connector "$connector" > /dev/null 2>&1
    connector_id=$(get_ccloud_connector_lcc "$connector")
    for task_id in $(confluent connect cluster describe "$connector_id" -o json 2>/dev/null | jq -r '.tasks[]? | select(.state == "FAILED") | .task_id' 2>/dev/null)
    do
      echo "🔄 task $task_id of connector $connector is FAILED, restarting it"
      playground connector restart --connector "$connector" --task-id "$task_id" > /dev/null 2>&1
    done
    set -e
  fi

  return 1
}

function get_ccloud_connector_lcc() {
  confluent connect cluster list -o json | jq -r -e 'map(select(.name == "'"$1"'")) | .[].id'
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
            curr_wait=$((curr_wait+sleep_interval))
            sleep $sleep_interval
        fi
    done
}

function wait_for_ccloud_connector_up() {
  connectorName=$1
  maxWait=$2

  connectorId=$(get_ccloud_connector_lcc $connectorName)
  log "⏳ waiting up to $maxWait seconds for connector $connectorName ($connectorId) to be RUNNING"
  if ! ccloud::retry $maxWait validate_ccloud_connector_up $connectorName
  then
    logerror "❌ connector $connectorName ($connectorId) is not RUNNING after $maxWait seconds"
    set +e
    playground connector status --connector $connectorName
    set -e
    exit 1
  fi
  log "🟢 connector $connectorName ($connectorId) is RUNNING"

  if [ -z "$GITHUB_RUN_NUMBER" ]
  then
    automatically=$(playground config get open-ccloud-connector-in-browser.automatically)
    if [ "$automatically" == "" ]
    then
        playground config set open-ccloud-connector-in-browser.automatically true
    fi

    browser=$(playground config get open-ccloud-connector-in-browser.browser)
    if [ "$browser" == "" ]
    then
        playground config set open-ccloud-connector-in-browser.browser ""
    fi

    if [ "$automatically" == "true" ] || [ "$automatically" == "" ]
    then
      if [ "$browser" != "" ]
      then
        log "🤖 automatically (disable with 'playground config open-ccloud-connector-in-browser automatically false') open fully managed connector $connectorName in browser $browser (you can change browser with 'playground config open-ccloud-connector-in-browser browser <browser>')"
        playground connector open-ccloud-connector-in-browser --connector $connectorName --browser $browser
      else
        log "🤖 automatically (disable with 'playground config open-ccloud-connector-in-browser automatically false') open fully managed connector $connectorName in default browser (you can set browser with 'playground config open-ccloud-connector-in-browser browser <browser>')"
        playground connector open-ccloud-connector-in-browser --connector $connectorName
      fi
    fi
  fi

  return 0
}


function delete_ccloud_connector() {
  connectorName=$1
  connectorId=$(get_ccloud_connector_lcc $connectorName)

  log "Deleting connector $connectorName ($connectorId)"
  confluent connect cluster delete $connectorId --force
  return 0
}

function wait_for_log () {
  message="$1"
  container=${2:-connect}
  max_wait=${3:-600}
  cur_wait=0
  log "⌛ Waiting up to $max_wait seconds for message $message to be present in $container container logs..."
  docker container logs ${container} > /tmp/out.txt 2>&1
  while ! grep "$message" /tmp/out.txt > /dev/null;
  do
  sleep 10
  docker container logs ${container} > /tmp/out.txt 2>&1
  cur_wait=$(( cur_wait+10 ))
  if [[ "$cur_wait" -gt "$max_wait" ]]; then
    logerror "The logs in $container container do not show '$message' after $max_wait seconds. Please troubleshoot with 'docker container ps' and 'playground container logs --open --container <container>'."
    return 1
  fi
  done
  grep "$message" /tmp/out.txt
  log "The log is there !"
}

###############
## ccloud-utils functions
## BEGIN
##############



CLI_MIN_VERSION=${CLI_MIN_VERSION:-4.0.0}

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

  ENVIRONMENT_NAME_PREFIX=${ENVIRONMENT_NAME_PREFIX:-"pg-${USER}-$$SERVICE_ACCOUNT_ID"}
  local environment_id=$(confluent environment list -o json | jq -r 'map(select(.name | startswith("'"$ENVIRONMENT_NAME_PREFIX"'"))) | .[].id')

  echo $environment_id

  return 0
}


function ccloud::create_and_use_environment() {
  ENVIRONMENT_NAME=$1

  OUTPUT=$(confluent environment create $ENVIRONMENT_NAME --governance-package essentials -o json)
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

  local FOUND_CLUSTER=$(confluent kafka cluster list -o json | jq -c -r '.[] | select((.name == "'"$CLUSTER_NAME"'") and (.cloud == "'"$CLUSTER_CLOUD"'") and (.region == "'"$CLUSTER_REGION"'"))')
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

  # Wait until the cluster status is not PROVISIONING
  while true; do
    CLUSTER_STATUS=$(confluent kafka cluster describe $CLUSTER --output json | jq -r .status)
    if [ "$CLUSTER_STATUS" != "PROVISIONING" ]; then
      break
    fi
    sleep 5
  done

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

function ccloud::get_schema_registry() {
  OUTPUT=$(confluent schema-registry cluster describe -o json)
  SCHEMA_REGISTRY=$(echo "$OUTPUT" | jq -r ".cluster")

  echo $SCHEMA_REGISTRY

  return 0
}

function ccloud::find_credentials_resource() {
  SERVICE_ACCOUNT_ID=$1
  RESOURCE=$2
  local FOUND_CRED=$(confluent api-key list -o json | jq -c -r 'map(select((.resource == "'"$RESOURCE"'") and (.owner == "'"$SERVICE_ACCOUNT_ID"'")))')
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

  OUTPUT=$(confluent api-key create --service-account $SERVICE_ACCOUNT_ID --resource $RESOURCE ${ENVIRONMENT:+--environment $ENVIRONMENT} -o json)
  API_KEY_SA=$(echo "$OUTPUT" | jq -r ".api_key")
  API_SECRET_SA=$(echo "$OUTPUT" | jq -r ".api_secret")
  echo "${API_KEY_SA}:${API_SECRET_SA}"

  # no need to wait for the key to be propagated here: callers poll until it is usable
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

function ccloud::create_acl() {
  local -i curr_wait=0
  local output

  # retry: a service account created a few seconds ago may not be known by the cluster yet
  until output=$(confluent kafka acl create --allow --cluster "$CLUSTER" "$@" 2>&1)
  do
    if (( curr_wait >= 120 ))
    then
      echo "ERROR: could not create ACL $*: $output"
      return 1
    fi
    curr_wait=$((curr_wait+5))
    sleep 5
  done
}

function ccloud::create_acls_all_resources_full_access() {
  SERVICE_ACCOUNT_ID=$1
  local pids=()
  local pid
  local failed=0

  # the ACLs are independent: create them concurrently
  ccloud::create_acl --service-account $SERVICE_ACCOUNT_ID --operations CREATE,DELETE,WRITE,READ,DESCRIBE,DESCRIBE_CONFIGS --topic '*' &
  pids+=($!)
  ccloud::create_acl --service-account $SERVICE_ACCOUNT_ID --operations READ,WRITE,CREATE,DESCRIBE --consumer-group '*' &
  pids+=($!)
  ccloud::create_acl --service-account $SERVICE_ACCOUNT_ID --operations DESCRIBE,WRITE --transactional-id '*' &
  pids+=($!)
  ccloud::create_acl --service-account $SERVICE_ACCOUNT_ID --operations IDEMPOTENT-WRITE,DESCRIBE --cluster-scope &
  pids+=($!)

  for pid in "${pids[@]}"
  do
    wait $pid || failed=1
  done

  return $failed
}

function ccloud::delete_acls_ccloud_stack() {
  SERVICE_ACCOUNT_ID=$1
  # Setting default QUIET=false to surface potential errors
  QUIET="${QUIET:-false}"
  [[ $QUIET == "true" ]] &&
    local REDIRECT_TO="/dev/null" ||
    local REDIRECT_TO="/dev/tty"

  echo "Deleting ACLs for service account ID $SERVICE_ACCOUNT_ID"

  confluent kafka acl delete --allow --service-account $SERVICE_ACCOUNT_ID --operations CREATE,DELETE,WRITE,READ,DESCRIBE,DESCRIBE_CONFIGS --topic '*' &>"$REDIRECT_TO"

  confluent kafka acl delete --allow --service-account $SERVICE_ACCOUNT_ID --operations READ,WRITE,CREATE,DESCRIBE --consumer-group '*' &>"$REDIRECT_TO"

  confluent kafka acl delete --allow --service-account $SERVICE_ACCOUNT_ID --operations DESCRIBE,WRITE --transactional-id '*' &>"$REDIRECT_TO"

  confluent kafka acl delete --allow --service-account $SERVICE_ACCOUNT_ID --operations IDEMPOTENT-WRITE,DESCRIBE --cluster-scope &>"$REDIRECT_TO"

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

  # About the Confluent CLI command 'confluent connect cluster create':
  # - Typical usage of this CLI would be 'confluent connect cluster create --config-file <filename>'
  # - However, in this example, the connector's configuration file contains parameters that need to be first substituted
  #   so the CLI command includes eval and heredoc.
  # - The '-vvv' is added for verbose output
  confluent connect cluster create -vvv --config <(eval "cat <<EOF
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
  confluent connect cluster list -o json | jq -e 'map(select(.name == "'"$1"'" and .status == "RUNNING")) | .[]' > /dev/null 2>&1
}

function ccloud::wait_for_connector_up() {
  connectorName=$1
  maxWait=$2

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
  confluent kafka topic list --cluster "$CLUSTER" #&>/dev/null
  return $?
}

# cluster is ready AND the API key in CLUSTER_CREDS is usable (propagated), which is what clients and
# connectors need. Falls back to ccloud::validate_ccloud_cluster_ready when the key cannot be checked
function ccloud::validate_ccloud_cluster_api_key_ready() {
  local api_key="${CLUSTER_CREDS%%:*}"
  local api_secret="${CLUSTER_CREDS#*:}"

  if [ -z "$CLUSTER_REST_ENDPOINT" ] || [ -z "$api_secret" ]
  then
    ccloud::validate_ccloud_cluster_ready
    return $?
  fi

  # 401 until the key is propagated; 403 means authenticated but no ACL yet, which is fine
  local http_code=$(curl -s -o /dev/null -w '%{http_code}' -u "$api_key:$api_secret" "$CLUSTER_REST_ENDPOINT/kafka/v3/clusters/$CLUSTER/topics")
  [ "$http_code" == "200" ] || [ "$http_code" == "403" ]
}

# runs in the background from ccloud::create_ccloud_stack: Schema Registry only depends on the environment
# and the service account. Results are written as shell assignments in $1
function ccloud::setup_schema_registry() {
  local output_file="$1"
  local need_role_binding="$2"
  local sr_creds="$SCHEMA_REGISTRY_CREDS"
  local sr_json=""
  local -i curr_wait=0

  # Schema Registry of a brand new environment may not be available right away
  until sr_json=$(confluent schema-registry cluster describe --environment "$ENVIRONMENT" -o json 2>/dev/null) && [ -n "$(echo "$sr_json" | jq -r '.cluster // empty')" ]
  do
    if (( curr_wait >= 300 ))
    then
      echo "ERROR: Schema Registry of environment $ENVIRONMENT is not available after $curr_wait seconds"
      return 1
    fi
    curr_wait=$((curr_wait+5))
    sleep 5
  done
  local sr_cluster=$(echo "$sr_json" | jq -r '.cluster')
  local sr_endpoint=$(echo "$sr_json" | jq -r '.endpoint_url')

  if [[ -z "$sr_creds" ]]
  then
    # always a new key: the secret of an existing one cannot be retrieved, and looking for it means
    # listing every key of the org (slow)
    sr_creds=$(ccloud::create_credentials_resource $SERVICE_ACCOUNT_ID $sr_cluster)
    if [[ -z "${sr_creds%%:*}" ]] || [[ "${sr_creds%%:*}" == "null" ]]
    then
      echo "ERROR: Could not create an API key for Schema Registry $sr_cluster"
      return 1
    fi
  fi

  if [ "$need_role_binding" == "1" ] && [ "$SERVICE_ACCOUNT_ID" != "" ]
  then
    log "Adding ResourceOwner RBAC role for all subjects"
    confluent iam rbac role-binding create --principal User:$SERVICE_ACCOUNT_ID --role ResourceOwner --environment $ENVIRONMENT --schema-registry-cluster $sr_cluster --resource "Subject:*" || true
  fi

  if [[ -z "$SCHEMA_REGISTRY_CREDS" ]] && [[ -n "${sr_creds#*:}" ]]
  then
    # wait for the new API key to be propagated: 401 until then, 403 means authenticated but the role
    # binding is not effective yet
    curr_wait=0
    until [[ "$(curl -s -o /dev/null -w '%{http_code}' -u "$sr_creds" "$sr_endpoint/subjects")" =~ ^(200|403)$ ]]
    do
      if (( curr_wait >= 300 ))
      then
        echo "ERROR: Schema Registry API key ${sr_creds%%:*} is not usable after $curr_wait seconds"
        return 1
      fi
      curr_wait=$((curr_wait+5))
      sleep 5
    done
  fi

  {
    printf 'SCHEMA_REGISTRY=%q\n' "$sr_cluster"
    printf 'SCHEMA_REGISTRY_ENDPOINT=%q\n' "$sr_endpoint"
    printf 'SCHEMA_REGISTRY_CREDS=%q\n' "$sr_creds"
  } > "$output_file"
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

  serviceAccount=$(confluent api-key list -o json | jq -r -c 'map(select((.key == "'"$key"'"))) | .[].owner')
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

  confluent kafka acl create --allow --service-account $serviceAccount --operations DESCRIBE --cluster-scope
  confluent kafka acl create --allow --service-account $serviceAccount --operations CREATE,WRITE --prefix --topic dlq-lcc
  confluent kafka acl create --allow --service-account $serviceAccount --operations READ --prefix --consumer-group connect-lcc

  return 0
}

function ccloud::create_acls_control_center() {
  serviceAccount=$1

  echo "Confluent Control Center: creating _confluent-command and ACLs for service account $serviceAccount"
  confluent kafka topic create _confluent-command --partitions 1

  confluent kafka acl create --allow --service-account $serviceAccount --operations WRITE,READ,CREATE --topic _confluent --prefix

  confluent kafka acl create --allow --service-account $serviceAccount --operations READ,WRITE,CREATE --consumer-group _confluent --prefix

  return 0
}


function ccloud::create_acls_replicator() {
  serviceAccount=$1
  topic=$2

  confluent kafka acl create --allow --service-account $serviceAccount --operations CREATE,WRITE,READ,DESCRIBE,DESCRIBE_CONFIGS,ALTER-CONFIGS,DESCRIBE --topic $topic

  return 0
}

function ccloud::create_acls_connect_topics() {
  serviceAccount=$1

  echo "Connect: creating topics and ACLs for service account $serviceAccount"

  TOPIC=connect-demo-configs
  confluent kafka topic create $TOPIC --partitions 1 --config "cleanup.policy=compact"
  confluent kafka acl create --allow --service-account $serviceAccount --operations WRITE,READ --topic $TOPIC --prefix

  TOPIC=connect-demo-offsets
  confluent kafka topic create $TOPIC --partitions 6 --config "cleanup.policy=compact"
  confluent kafka acl create --allow --service-account $serviceAccount --operations WRITE,READ --topic $TOPIC --prefix

  TOPIC=connect-demo-statuses
  confluent kafka topic create $TOPIC --partitions 3 --config "cleanup.policy=compact"
  confluent kafka acl create --allow --service-account $serviceAccount --operations WRITE,READ  --topic $TOPIC --prefix

  for TOPIC in _confluent-monitoring _confluent-command ; do
    confluent kafka topic create $TOPIC --partitions 1 &>/dev/null
    confluent kafka acl create --allow --service-account $serviceAccount --operations WRITE,READ  --topic $TOPIC --prefix
  done

  confluent kafka acl create --allow --service-account $serviceAccount --operations READ --consumer-group connect-cloud

  echo "Connectors: creating topics and ACLs for service account $serviceAccount"
  confluent kafka acl create --allow --service-account $serviceAccount --operations READ --consumer-group connect-replicator
  confluent kafka acl create --allow --service-account $serviceAccount --operations DESCRIBE --cluster-scope

  return 0
}

function ccloud::validate_ccloud_stack_up() {
  CLOUD_KEY=$1
  CCLOUD_CONFIG_FILE=$2
  enable_ksqldb=$3

  if [ -z "$enable_ksqldb" ]; then
    enable_ksqldb=true
  fi

  ccloud::validate_environment_set || exit 1
  ccloud::set_kafka_cluster_use_from_api_key "$CLOUD_KEY" || exit 1
  ccloud::validate_schema_registry_up "$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" "$SCHEMA_REGISTRY_URL" || exit 1
  if $enable_ksqldb ; then
    ccloud::validate_ksqldb_up "$KSQLDB_ENDPOINT" || exit 1
    ccloud::validate_credentials_ksqldb "$KSQLDB_ENDPOINT" "$CCLOUD_CONFIG_FILE" "$KSQLDB_BASIC_AUTH_USER_INFO" || exit 1
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

  local kafkaCluster=$(confluent api-key list -o json | jq -r -c 'map(select((.key == "'"$key"'" and .resource_type == "kafka"))) | .[].resource')
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
  ccloud::validate_version_cli $CLI_MIN_VERSION || exit 1
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
  # a service account is needed as soon as one of the API keys has to be created
  local need_role_binding=0
  if [[ -z "$CLUSTER_CREDS" ]] || [[ -z "$SCHEMA_REGISTRY_CREDS" ]]
  then
    need_role_binding=1
    if [[ -z "$SERVICE_ACCOUNT_ID" ]]; then
      # Service Account is not received so it will be created
      local RANDOM_NUM=$((1 + RANDOM % 1000000))
      SERVICE_NAME=${SERVICE_NAME:-"pg-${USER}-app-$RANDOM_NUM"}
      SERVICE_ACCOUNT_ID=$(ccloud::create_service_account $SERVICE_NAME)
    fi

    if [[ "$SERVICE_NAME" == "" ]]; then
      echo "ERROR: SERVICE_NAME is not defined. If you are providing the SERVICE_ACCOUNT_ID to this function please also provide the SERVICE_NAME"
      exit 1
    fi

    echo "Creating Confluent Cloud stack for service account $SERVICE_NAME, ID: $SERVICE_ACCOUNT_ID."
  fi

  local environment_created=0
  if [[ -z "$ENVIRONMENT" ]];
  then
    # Environment is not received so it will be created
    MAX_LENGTH=64
    ENVIRONMENT_NAME=${ENVIRONMENT_NAME:-"pg-${USER}-$SERVICE_ACCOUNT_ID-$EXAMPLE"}
    if [ ${#ENVIRONMENT_NAME} -gt $MAX_LENGTH ]
    then
      ENVIRONMENT_NAME=$(echo $ENVIRONMENT_NAME | cut -c 1-$MAX_LENGTH)
    fi

    ENVIRONMENT=$(ccloud::create_and_use_environment $ENVIRONMENT_NAME)
    (($? != 0)) && { echo "$ENVIRONMENT"; exit 1; }
    environment_created=1
  else
    confluent environment use $ENVIRONMENT || exit 1
  fi

  # Schema Registry does not depend on the Kafka cluster: set it up in the background meanwhile
  local sr_output_file=$(mktemp)
  ccloud::setup_schema_registry "$sr_output_file" $need_role_binding &
  local sr_pid=$!

  CLUSTER_NAME=${CLUSTER_NAME:-"pg-${USER}-cluster-$SERVICE_ACCOUNT_ID"}
  CLUSTER_CLOUD="${CLUSTER_CLOUD:-aws}"
  CLUSTER_REGION="${CLUSTER_REGION:-us-west-2}"
  CLUSTER_TYPE="${CLUSTER_TYPE:-basic}"
  if [ $environment_created -eq 1 ] && [[ -z "$CLUSTER_CREDS" ]]
  then
    # nothing to look for in a brand new environment
    CLUSTER=$(ccloud::create_and_use_cluster "$CLUSTER_NAME" $CLUSTER_CLOUD $CLUSTER_REGION $CLUSTER_TYPE)
  else
    CLUSTER=$(ccloud::maybe_create_and_use_cluster "$CLUSTER_NAME" $CLUSTER_CLOUD $CLUSTER_REGION $CLUSTER_TYPE)
  fi
  (($? != 0)) && { echo "$CLUSTER"; exit 1; }
  if [[ "$CLUSTER" == "" ]] ; then
    echo "Kafka cluster id is empty"
    echo "ERROR: Could not create cluster. Please troubleshoot."
    exit 1
  fi

  local cluster_json=$(confluent kafka cluster describe $CLUSTER -o json)
  endpoint=$(echo "$cluster_json" | jq -r ".endpoint")
  if [[ $endpoint == "SASL_SSL://"* ]]
  then
    BOOTSTRAP_SERVERS=$(echo "$endpoint" | cut -c 12-)
  else
    BOOTSTRAP_SERVERS="$endpoint"
  fi
  # also used by ccloud::generate_configs
  CLUSTER_REST_ENDPOINT=$(echo "$cluster_json" | jq -r ".rest_endpoint // empty")

  NEED_ACLS=0
  # VINC: added
  if [[ -z "$CLUSTER_CREDS" ]]
  then
    # always a new key: the secret of an existing one cannot be retrieved, and looking for it means
    # listing every key of the org (slow)
    CLUSTER_CREDS=$(ccloud::create_credentials_resource $SERVICE_ACCOUNT_ID $CLUSTER)
    NEED_ACLS=1
  fi

  MAX_WAIT=720
  if [[ $NEED_ACLS -eq 1 ]]
  then
    echo ""
    echo "Waiting up to $MAX_WAIT seconds for Confluent Cloud cluster $CLUSTER to be ready and its new API key to be usable"
    ccloud::retry $MAX_WAIT ccloud::validate_ccloud_cluster_api_key_ready || exit 1

    ccloud::create_acls_all_resources_full_access $SERVICE_ACCOUNT_ID || exit 1
  elif ! ccloud::validate_ccloud_cluster_api_key_ready
  then
    echo ""
    echo "Waiting up to $MAX_WAIT seconds for Confluent Cloud cluster $CLUSTER to be ready"
    ccloud::retry $MAX_WAIT ccloud::validate_ccloud_cluster_ready || exit 1
  fi

  if ! wait $sr_pid
  then
    rm -f "$sr_output_file"
    echo "ERROR: Could not set up Schema Registry. Please troubleshoot."
    exit 1
  fi
  source "$sr_output_file"
  rm -f "$sr_output_file"

  # done after the background Schema Registry setup, so that no concurrent confluent CLI call can
  # overwrite the active cluster in the CLI config
  confluent kafka cluster use $CLUSTER

  if $enable_ksqldb ; then
    KSQLDB_NAME=${KSQLDB_NAME:-"demo-ksqldb-$SERVICE_ACCOUNT_ID"}
    KSQLDB=$(ccloud::maybe_create_ksqldb_app "$KSQLDB_NAME" $CLUSTER "$CLUSTER_CREDS")
    KSQLDB_ENDPOINT=$(confluent ksql cluster describe $KSQLDB -o json | jq -r ".endpoint")
    KSQLDB_CREDS=$(ccloud::maybe_create_credentials_resource $SERVICE_ACCOUNT_ID $KSQLDB)
    confluent ksql cluster configure-acls $KSQLDB
  fi

  KAFKA_API_KEY=`echo $CLUSTER_CREDS | awk -F: '{print $1}'`
  KAFKA_API_SECRET=`echo $CLUSTER_CREDS | awk -F: '{print $2}'`
  # FIX THIS: added by me
  confluent api-key store "$KAFKA_API_KEY" "$KAFKA_API_SECRET" --resource ${CLUSTER} --force
  confluent api-key use $KAFKA_API_KEY --resource ${CLUSTER}

  if [[ -z "$SKIP_CONFIG_FILE_WRITE" ]]; then
    if [[ -z "$CCLOUD_CONFIG_FILE" ]]; then
      CCLOUD_CONFIG_FILE="/tmp/tmp.config"
    fi

    cat <<EOF > $CCLOUD_CONFIG_FILE
# --------------------------------------
# Confluent Cloud connection information
# --------------------------------------
# ENVIRONMENT ID: ${ENVIRONMENT}
# SERVICE ACCOUNT ID: ${SERVICE_ACCOUNT_ID}
# KAFKA CLUSTER ID: ${CLUSTER}
# SCHEMA REGISTRY CLUSTER ID: ${SCHEMA_REGISTRY}
EOF
    if $enable_ksqldb ; then
      cat <<EOF >> $CCLOUD_CONFIG_FILE
# KSQLDB APP ID: ${KSQLDB}
EOF
    fi
    cat <<EOF >> $CCLOUD_CONFIG_FILE
# --------------------------------------
sasl.mechanism=PLAIN
security.protocol=SASL_SSL
bootstrap.servers=${BOOTSTRAP_SERVERS}
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username='${KAFKA_API_KEY}' password='${KAFKA_API_SECRET}';
basic.auth.credentials.source=USER_INFO
schema.registry.url=${SCHEMA_REGISTRY_ENDPOINT}
basic.auth.user.info=`echo $SCHEMA_REGISTRY_CREDS | awk -F: '{print $1}'`:`echo $SCHEMA_REGISTRY_CREDS | awk -F: '{print $2}'`
replication.factor=${REPLICATION_FACTOR}
EOF
    if $enable_ksqldb ; then
      cat <<EOF >> $CCLOUD_CONFIG_FILE
ksql.endpoint=${KSQLDB_ENDPOINT}
ksql.basic.auth.user.info=`echo $KSQLDB_CREDS | awk -F: '{print $1}'`:`echo $KSQLDB_CREDS | awk -F: '{print $2}'`
EOF
    fi
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

  ENVIRONMENT_NAME_PREFIX=${ENVIRONMENT_NAME_PREFIX:-"pg-${USER}-$SERVICE_ACCOUNT_ID"}
  CLUSTER_NAME=${CLUSTER_NAME:-"pg-${USER}-cluster-$SERVICE_ACCOUNT_ID"}
  CCLOUD_CONFIG_FILE=${CCLOUD_CONFIG_FILE:-"/tmp/tmp.config"}
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
  confluent connect cluster list --cluster $cluster_id -o json | jq -r '.[].id' | xargs -I{} confluent connect cluster delete {} --force

  echo "Deleting CLUSTER: $CLUSTER_NAME : $cluster_id"
  confluent kafka cluster delete $cluster_id &> "$REDIRECT_TO"

  # Delete API keys associated to the service account
  confluent api-key list --service-account $SERVICE_ACCOUNT_ID -o json | jq -r '.[].key' | xargs -I{} confluent api-key delete {} --force

  # Delete service account
  confluent iam service-account delete $SERVICE_ACCOUNT_ID --force &>"$REDIRECT_TO"

  if [[ $PRESERVE_ENVIRONMENT == "false" ]]; then
    local environment_id=$(confluent environment list -o json | jq -r 'map(select(.name | startswith("'"$ENVIRONMENT_NAME_PREFIX"'"))) | .[].id')
    if [[ "$environment_id" == "" ]]; then
      echo "WARNING: Could not find environment with name that starts with $ENVIRONMENT_NAME_PREFIX (did you create this ccloud-stack reusing an existing environment?)"
    else
      echo "Deleting ENVIRONMENT: prefix $ENVIRONMENT_NAME_PREFIX : $environment_id"
      confluent environment delete $environment_id &> "$REDIRECT_TO"
    fi
  fi

  rm -f $CCLOUD_CONFIG_FILE

  return 0
}


function ccloud::generate_configs() {
  CCLOUD_CONFIG_FILE=$1
  if [[ -z "$CCLOUD_CONFIG_FILE" ]]; then
    CCLOUD_CONFIG_FILE=~/.ccloud/config
  fi
  if [[ ! -f "$CCLOUD_CONFIG_FILE" ]]; then
    echo "File $CCLOUD_CONFIG_FILE is not found.  Please create this properties file to connect to your Confluent Cloud cluster and then try again"
    echo "See https://docs.confluent.io/current/cloud/connect/auto-generate-configs.html for more information"
    return 1
  fi

  # log "Generating component configurations"
  # log "(If you want to run any of these components to talk to Confluent Cloud, these are the configurations to add to the properties file for each component)"

  # Set permissions
  PERM=600
  if ls --version 2>/dev/null | grep -q 'coreutils' ; then
    # GNU binutils
    PERM=$(stat -c "%a" $CCLOUD_CONFIG_FILE)
  else
    # BSD
    PERM=$(stat -f "%OLp" $CCLOUD_CONFIG_FILE)
  fi

  # Make destination
  get_kafka_docker_playground_dir
  DEST=$KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud
  mkdir -p $DEST
  ################################################################################
  # Glean parameters from the Confluent Cloud configuration file
  ################################################################################

  # Kafka cluster
  BOOTSTRAP_SERVERS=$( grep "^bootstrap.server" $CCLOUD_CONFIG_FILE | awk -F'=' '{print $2;}' )
  BOOTSTRAP_SERVERS=${BOOTSTRAP_SERVERS/\\/}
  SASL_JAAS_CONFIG=$( grep "^sasl.jaas.config" $CCLOUD_CONFIG_FILE | cut -d'=' -f2- )
  SASL_JAAS_CONFIG_PROPERTY_FORMAT=${SASL_JAAS_CONFIG/username\\=/username=}
  SASL_JAAS_CONFIG_PROPERTY_FORMAT=${SASL_JAAS_CONFIG_PROPERTY_FORMAT/password\\=/password=}
  CLOUD_KEY=$( echo $SASL_JAAS_CONFIG | awk '{print $3}' | awk -F"'" '$0=$2' )
  CLOUD_SECRET=$( echo $SASL_JAAS_CONFIG | awk '{print $4}' | awk -F"'" '$0=$2' )

  # Schema Registry
  BASIC_AUTH_CREDENTIALS_SOURCE=$( grep "^basic.auth.credentials.source" $CCLOUD_CONFIG_FILE | awk -F'=' '{print $2;}' )
  SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO=$( grep "^basic.auth.user.info" $CCLOUD_CONFIG_FILE | awk -F'=' '{print $2;}' )
  SCHEMA_REGISTRY_URL=$( grep "^schema.registry.url" $CCLOUD_CONFIG_FILE | awk -F'=' '{print $2;}' )

  # ksqlDB
  KSQLDB_ENDPOINT=$( grep "^ksql.endpoint" $CCLOUD_CONFIG_FILE | awk -F'=' '{print $2;}' )
  KSQLDB_BASIC_AUTH_USER_INFO=$( grep "^ksql.basic.auth.user.info" $CCLOUD_CONFIG_FILE | awk -F'=' '{print $2;}' )

  ################################################################################
  # AK command line tools
  ################################################################################
  AK_TOOLS_DELTA=$DEST/ak-tools-ccloud.delta
  #echo "$AK_TOOLS_DELTA"
  rm -f $AK_TOOLS_DELTA
  cp $CCLOUD_CONFIG_FILE $AK_TOOLS_DELTA
  chmod $PERM $AK_TOOLS_DELTA

  ################################################################################
  # librdkafka
  ################################################################################
  LIBRDKAFKA_CONFIG=$DEST/librdkafka.delta
  #echo "$LIBRDKAFKA_CONFIG"
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
  # ENV
  ################################################################################
  get_kafka_docker_playground_dir
  DELTA_CONFIGS_ENV=$KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/env.delta
  ENV_CONFIG=$DELTA_CONFIGS_ENV
  echo "$DELTA_CONFIGS_ENV"
  rm -f $DELTA_CONFIGS_ENV

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

  ################################################################################
  # CLAUDE CLI
  ################################################################################
  CLAUDE_MCP_CONFLUENT_CONFIG=$KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/.env
  echo "$CLAUDE_MCP_CONFLUENT_CONFIG"
  rm -f $CLAUDE_MCP_CONFLUENT_CONFIG

  SCHEMA_REGISTRY_API_KEY=$(echo $SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO | awk -F: '{print $1}')
  SCHEMA_REGISTRY_API_SECRET=$(echo $SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO | awk -F: '{print $2}')
  KAFKA_REST_ENDPOINT=${CLUSTER_REST_ENDPOINT:-$(confluent kafka cluster describe $CLUSTER -o json | jq -r ".rest_endpoint")}

  # example scripts source this file without the secrets library
  if type load_secrets_env_vars > /dev/null 2>&1
  then
    load_secrets_env_vars CONFLUENT_CLOUD_API_KEY CONFLUENT_CLOUD_API_SECRET
  fi

  if [ -z $CONFLUENT_CLOUD_API_KEY ]
  then
    logwarn "❌ environment variable CONFLUENT_CLOUD_API_KEY should be set to use MCP confluent server for Confluent Cloud"
    logwarn "Set it with Cloud API key, see https://docs.confluent.io/cloud/current/access-management/authenticate/api-keys/api-keys.html#cloud-cloud-api-keys"
  fi

  if [ -z $CONFLUENT_CLOUD_API_SECRET ]
  then
    logwarn "❌ environment variable CONFLUENT_CLOUD_API_SECRET should be set to use MCP confluent server for Confluent Cloud"
    logwarn "Set it with Cloud API secret, see https://docs.confluent.io/cloud/current/access-management/authenticate/api-keys/api-keys.html#cloud-cloud-api-keys"
  fi

  cat <<EOF >> $CLAUDE_MCP_CONFLUENT_CONFIG
# .env file
BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS"
KAFKA_API_KEY="$CLOUD_KEY"
KAFKA_API_SECRET="$CLOUD_SECRET"
KAFKA_REST_ENDPOINT="$KAFKA_REST_ENDPOINT"
KAFKA_CLUSTER_ID="$CLUSTER"
KAFKA_ENV_ID="$ENVIRONMENT"
# FLINK_ENV_ID="env-..."
# FLINK_ORG_ID=""
# FLINK_REST_ENDPOINT="https://flink.us-east4.gcp.confluent.cloud"
# FLINK_ENV_NAME=""
# FLINK_DATABASE_NAME=""
# FLINK_API_KEY=""
# FLINK_API_SECRET=""
# FLINK_COMPUTE_POOL_ID="lfcp-..."
# TABLEFLOW_API_KEY=""
# TABLEFLOW_API_SECRET=""
CONFLUENT_CLOUD_API_KEY="$CONFLUENT_CLOUD_API_KEY"
CONFLUENT_CLOUD_API_SECRET="$CONFLUENT_CLOUD_API_SECRET"
CONFLUENT_CLOUD_REST_ENDPOINT="https://api.confluent.cloud"
SCHEMA_REGISTRY_API_KEY="$SCHEMA_REGISTRY_API_KEY"
SCHEMA_REGISTRY_API_SECRET="$SCHEMA_REGISTRY_API_SECRET"
SCHEMA_REGISTRY_ENDPOINT="$SCHEMA_REGISTRY_URL"
EOF
  chmod $PERM $CLAUDE_MCP_CONFLUENT_CONFIG

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
            curr_wait=$((curr_wait+sleep_interval))
            sleep $sleep_interval
        fi
    done
}
function ccloud::version_gt() {
  test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1";
}


###############
## ccloud-utils functions
## END
##############

function check_arm64_support() {
  DIR="$1"
  DOCKER_COMPOSE_FILE="$2"
  set +e
  if [ "$(uname -m)" = "arm64" ]
  then
    test=$(echo "$DOCKER_COMPOSE_FILE" | awk -F"/" '{ print $(NF-2)"/"$(NF-1) }')
    base_folder=$(echo $test | cut -d "/" -f 1)
    base_test=$(echo $test | cut -d "/" -f 2)
    if [ "$base_folder" == "reproduction-models" ]
    then
      base_test=${base_test#*-}
    fi
    
    grep "${base_test}" ${DIR}/../../scripts/arm64-support-none.txt > /dev/null
    if [ $? = 0 ]
    then
        logerror "🖥️ This example is not working with ARM64 !"
        log "It is highly recommended to use 'playground ec2 command' (https://kafka-docker-playground.io/#/playground%20ec2) to run the example on ubuntu ec2 instance"
        log "Do you want to start the example anyway ?"
        check_if_continue
        return
    fi

    grep "${base_test}" ${DIR}/../../scripts/arm64-support-with-emulation.txt > /dev/null
    if [ $? = 0 ]
    then
        logwarn "🖥️ This example is working with ARM64 but requires emulation"
        return
    fi

    log "🖥️ This example should work natively with ARM64"
  fi
  set -e
}

# print the value of <section>.<key> from an ini file written by ini_save, same result as ini_load
function ini_file_get () {
  local ini_file="$1"
  local section="${2%%.*}"
  local key="${2#*.}"

  awk -v section="[$section]" -v key="$key" '
    /^\[.+\]/ { in_section = ($0 == section); next }
    in_section && index($0, key " = ") == 1 { print substr($0, length(key) + 4); exit }
  ' "$ini_file"
}

# set (3 args) or delete (2 args) <section>.<key> in an ini file written by ini_save, same result as
# ini_load + ini_save but without spawning the generated CLI. Values are passed through ENVIRON, as
# awk -v would interpret backslashes
function ini_file_update () {
  local ini_file="$1"
  local section="${2%%.*}"
  local key="${2#*.}"
  local delete="true"
  if [ $# -eq 3 ]
  then
    delete="false"
  fi
  local tmp_file
  touch "$ini_file"
  tmp_file=$(mktemp "${ini_file}.XXXXXX") || return 1

  INI_SECTION="[$section]" INI_KEY="$key" INI_VALUE="$3" INI_DELETE="$delete" awk '
    BEGIN { section = ENVIRON["INI_SECTION"]; key = ENVIRON["INI_KEY"]; line = key " = " ENVIRON["INI_VALUE"]; done = (ENVIRON["INI_DELETE"] == "true") }
    # blank lines separate sections: hold them so that a missing key is appended at the end of its section
    /^[[:space:]]*$/ { blanks++; next }
    /^\[.+\]/ {
      if (in_section && !done) { print line; done = 1 }
      for (; blanks > 0; blanks--) print ""
      in_section = ($0 == section); seen = seen || in_section; print; next
    }
    in_section && index($0, key " = ") == 1 { if (!done) { print line; done = 1 } next }
    { for (; blanks > 0; blanks--) print ""; print }
    END {
      if (!done) {
        if (!seen) { if (NR > 0) print ""; print section }
        print line
      }
    }
  ' "$ini_file" > "$tmp_file" && mv "$tmp_file" "$ini_file"
}

function playground() {
  verbose_begin
  local playground_cli
  if [[ $(type -f playground 2>&1) =~ "not found" ]]
  then
    if [ -f ../../scripts/cli/playground ]
    then
      playground_cli=../../scripts/cli/playground
    elif [ -f ../../../scripts/cli/playground ]
    then
      playground_cli=../../../scripts/cli/playground
    else
      logerror "🔍 playground command not found, add it to your PATH https://kafka-docker-playground.io/#/cli?id=🦶-setup-path"
      exit 1
    fi
  else
    playground_cli=$(which playground)
  fi

  # 'state get' and 'config get' are called very often: read the ini file directly instead of spawning the
  # generated CLI (~130ms per call, mostly spent parsing the script)
  local ini_file=""
  if [ $# -eq 3 ] && [ "$2" == "get" ] && [[ "$3" == *.* ]]
  then
    case "$1" in
      state) ini_file="${playground_cli%/*}/../../playground.ini" ;;
      config) ini_file="${playground_cli%/*}/../../playground_config.ini" ;;
    esac
  fi

  # same for 'state set' and 'state del', called ~10 times by set_profiles alone
  local state_update=""
  if [ "$1" == "state" ] && [[ "$3" == *.* ]] && { { [ $# -eq 4 ] && [ "$2" == "set" ]; } || { [ $# -eq 3 ] && [ "$2" == "del" ]; }; }
  then
    state_update="${playground_cli%/*}/../../playground.ini"
  fi

  if [ -n "$ini_file" ] && [ -f "$ini_file" ]
  then
    ini_file_get "$ini_file" "$3"
  elif [ -n "$state_update" ] && [ -f "$state_update" ]
  then
    shift 2
    ini_file_update "$state_update" "$@"
  else
    "$playground_cli" "$@"
  fi
  verbose_end
}

function force_enable () {
  flag=$1
  env_variable=$2

  logwarn "💪 Forcing $flag ($env_variable env variable)"
  line_final_source=$(grep -n 'source ${DIR}/../../scripts/utils.sh$' $test_file | cut -d ":" -f 1 | tail -n1)
  tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
  if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi
  echo "# remove or comment those lines if you don't need it anymore" > $tmp_dir/tmp_force_enable
  echo "logwarn \"💪 Forcing $flag ($env_variable env variable) as it was set when reproduction model was created\"" >> $tmp_dir/tmp_force_enable
  echo "export $env_variable=true" >> $tmp_dir/tmp_force_enable
  cp $test_file $tmp_dir/tmp_file

  { head -n $(($line_final_source+1)) $tmp_dir/tmp_file; cat $tmp_dir/tmp_force_enable; tail -n  +$(($line_final_source+1)) $tmp_dir/tmp_file; } > $test_file
}

function load_env_variables () {
  for item in {ENABLE_CONTROL_CENTER,ENABLE_FLINK,ENABLE_KSQLDB,ENABLE_RESTPROXY,ENABLE_JMX_GRAFANA,ENABLE_KCAT,ENABLE_CONDUKTOR,SQL_DATAGEN,ENABLE_KAFKA_NODES,ENABLE_CONNECT_NODES}
  do
    i=$(playground state get "flags.${item}")
    if [ "$i" != "" ]
    then
      log "⛳ exporting environment variable ${item}"
      export "${item}"=1
    fi
  done
}

function get_connector_paths () {
    # determining the docker-compose file from from test_file
    docker_compose_file=""
    if [ -f "$test_file" ]
    then
      docker_compose_file=$(grep "start-environment" "$test_file" |  awk '{print $6}' | cut -d "/" -f 2 | cut -d '"' -f 1 | tail -n1 | xargs)
      test_file_directory="$(dirname "${test_file}")"
      docker_compose_file="${test_file_directory}/${docker_compose_file}"
    fi

    if [ "${docker_compose_file}" != "" ] && [ -f "${docker_compose_file}" ]
    then
      connector_paths=$(grep "CONNECT_PLUGIN_PATH" "${docker_compose_file}" | grep -v "KSQL_CONNECT_PLUGIN_PATH" | cut -d ":" -f 2  | tr -s " " | head -1)
    else
      echo ""
    fi
}

function generate_connector_versions () {
  get_connector_paths
  if [ "$connector_paths" == "" ]
  then
      return
  else
      connector_tags=""
      for connector_path in ${connector_paths//,/ }
      do
        full_connector_name=$(basename "$connector_path")
        owner=$(echo "$full_connector_name" | cut -d'-' -f1)
        name=$(echo "$full_connector_name" | cut -d'-' -f2-)

        if [ "$owner" == "java" ] || [ "$name" == "hub-components" ] || [ "$owner" == "filestream" ]
        then
          # happens when plugin is not coming from confluent hub
          continue
        fi

        playground connector-plugin versions --connector-plugin $owner/$name --force-refresh
      done
  fi
}

CONNECTOR_TYPE_FULLY_MANAGED="🌤️🤖fully managed"
CONNECTOR_TYPE_CUSTOM="🌤️🛃custom"
CONNECTOR_TYPE_SELF_MANAGED="⛈️👷self managed"
CONNECTOR_TYPE_ONPREM="🌎onprem"

EC2_INSTANCE_STATE_STOPPED="🛑stopped"
EC2_INSTANCE_STATE_RUNNING="✅running"
EC2_INSTANCE_STATE_STOPPING="⌛stopping"
EC2_INSTANCE_STATE_PENDING="⌛pending"

function get_connector_type () {
  get_connector_paths
  if [ "$connector_paths" == "" ]
  then
    if grep -q -e "fm-" <<< "$test_file"
    then
      echo "$CONNECTOR_TYPE_FULLY_MANAGED"
    elif grep -q -e "custom-connector" <<< "$test_file"
    then
      echo "$CONNECTOR_TYPE_CUSTOM"
    else
      echo ""
    fi
  else
    if grep -q -e "ccloud" <<< "$test_file"
    then
      echo "$CONNECTOR_TYPE_SELF_MANAGED"
    elif [[ -n "$environment" ]] && [ "$environment" == "ccloud" ]
    then
      echo "$CONNECTOR_TYPE_SELF_MANAGED"
    else
      echo "$CONNECTOR_TYPE_ONPREM"
    fi
  fi
}

function handle_ccloud_connect_rest_api () {
  curl_request="$1"
  get_ccloud_connect
  if [[ -n "$verbose" ]]
  then
    log "🐞 curl command used"
    echo "$curl_request"
  fi
  eval "curl_output=\$($curl_request)"
  ret=$?
  if [ $ret -eq 0 ]
  then
      if [ "$curl_output" == "[]" ]
      then
        # logerror "No connector running"
        # return 1
        echo ""
        return
      fi
      if echo "$curl_output" | jq 'if .error then .error | has("code") else has("error_code") end' 2> /dev/null | grep -q true
      then
        if echo "$curl_output" | jq '.error | has("code")' 2> /dev/null | grep -q true
        then
          code=$(echo "$curl_output" | jq -r .error.code)
          message=$(echo "$curl_output" | jq -r .error.message)
        else
          code=$(echo "$curl_output" | jq -r .error_code)
          message=$(echo "$curl_output" | jq -r .message)
        fi
        logerror "Command failed with error code $code"
        logerror "$message"
        return 1
      elif echo "$curl_output" | jq 'has("errors") or has("warnings")' 2> /dev/null | grep -q true
      then
        code=$(echo "$curl_output" | jq -r '.errors[0].status')

        if [ "$code" == "null" ] || [ -z "$code" ]; then
            # this happen in translate mode
            echo "$curl_output" | jq .
            return 0
        fi

        message=$(echo "$curl_output" | jq -r '.errors[0].detail')
        logerror "Command failed with error code $code"
        logerror "$message"
        return 1
      fi
  else
    logerror "❌ curl request failed with error code $ret!"
    return 1
  fi
}

function handle_onprem_connect_rest_api () {
  curl_request="$1"
  if [[ -n "$verbose" ]]
  then
    log "🐞 curl command used"
    echo "$curl_request"
  fi
  # a worker rebalance makes the connect REST API answer 409 "Cannot complete request because
  # of a conflicting operation (e.g. worker rebalance)": retry it for up to a minute. Only
  # rebalances, a 409 "Connector ... already exists" is final
  local rebalance_attempt=1
  local rebalance_max_attempts=12
  while true
  do
    eval "curl_output=\$($curl_request)"
    ret=$?
    if [ $ret -eq 0 ] && [ $rebalance_attempt -lt $rebalance_max_attempts ] && echo "$curl_output" | jq -e '.error_code == 409 and (.message | test("rebalance"))' > /dev/null 2>&1
    then
      log "⌛ connect REST API is busy with a worker rebalance (409), retrying in 5 seconds ($rebalance_attempt/$rebalance_max_attempts)"
      sleep 5
      rebalance_attempt=$((rebalance_attempt + 1))
      continue
    fi
    break
  done
  if [ $ret -eq 0 ]
  then
      if [ "$curl_output" == "[]" ]
      then
        # logerror "No connector running"
        # return 1
        echo ""
        return
      fi
      if [[ "$curl_output" == "<html>"* ]]
      then
        # Jetty serves an HTML error page while the connect REST resources are not registered yet (worker still starting)
        title=$(echo "$curl_output" | sed -n 's:.*<title>\(.*\)</title>.*:\1:p' | head -1)
        logerror "Command failed: connect REST API returned an HTML page ($title), the worker is probably still starting"
        return 1
      fi
      if echo "$curl_output" | jq '. | has("error_code")' 2> /dev/null | grep -q true 
      then
        error_code=$(echo "$curl_output" | jq -r .error_code)
        message=$(echo "$curl_output" | jq -r .message)
        logerror "Command failed with error code $error_code"
        logerror "$message"
        return 1
      fi
  else
      logerror "❌ curl request failed with error code $ret!"
      return 1
  fi
}

function display_ngrok_warning () {

  set +e
  docker pull ngrok/ngrok > /dev/null 2>&1
  set +e

  if [ -z "$NGROK_AUTH_TOKEN" ]
  then
      logerror "NGROK_AUTH_TOKEN is not set. Export it as environment variable or pass it as argument"
      logerror "Sign up at: https://dashboard.ngrok.com/signup"
      logerror "If you have already signed up, make sure your authtoken is installed."
      logerror "Your authtoken is available on your dashboard: https://dashboard.ngrok.com/get-started/your-authtoken"
      exit 1
  fi

  if [ ! -z "$GITHUB_RUN_NUMBER" ]
  then
    test_file=$(playground state get run.test_file)

    DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
    dir1=$(echo ${DIR_CLI%/*})
    cli_folder=$(echo ${dir1%/*})

    # trick to use different ngrok token
    if [ ! -f $test_file ]
    then 
      logerror "File $test_file retrieved from $cli_folder/../../playground.ini does not exist!"
      exit 1
    fi
    last_two_folders=$(basename $(dirname $(dirname $test_file)))/$(basename $(dirname $test_file))

    if grep "$last_two_folders" ${cli_folder}/../../.github/workflows/ci.yml | grep -q "2️⃣"
    then
      log "😋 Using NGROK_CI_AUTH_TOKEN_BACKUP"
      export NGROK_AUTH_TOKEN=$NGROK_CI_AUTH_TOKEN_BACKUP
    fi
  fi

  if [ "$USER" == "vsaboulin" ]
  then
    return
  fi
  check_if_continue
}

function login_and_maybe_set_azure_subscription () {

  # 1. Warn if legacy AZ_PASS is being used
  if [ ! -z "$AZ_PASS" ]; then
    logwarn "AZ_PASS detected. User/Password login is no longer supported due to MFA requirements."
    logwarn "Please unset AZ_PASS and use interactive login locally (https://learn.microsoft.com/en-us/cli/azure/authenticate-azure-cli-interactively?view=azure-cli-latest), or Service Principal in CI."
  fi

  # 2. Authentication Logic
  if [ ! -z "$GITHUB_RUN_NUMBER" ]; then
    # CI/CD Mode: Use Service Principal
    if [ ! -z "$AZ_CLIENT_ID" ] && [ ! -z "$AZ_CLIENT_SECRET" ] && [ ! -z "$AZ_TENANT_ID" ]; then
      log "🚀 GitHub Action detected: Logging in via Service Principal (MFA-exempt)"
      az login --service-principal \
               -u "$AZ_CLIENT_ID" \
               -p "$AZ_CLIENT_SECRET" \
               --tenant "$AZ_TENANT_ID" > /dev/null 2>&1
    else
      logerror "❌ CI Mode Error: GITHUB_RUN_NUMBER is set but Service Principal env vars (AZ_CLIENT_ID, etc.) are missing."
      exit 1
    fi
  elif [ ! -z "$AZ_CLIENT_ID" ] && [ ! -z "$AZ_CLIENT_SECRET" ] && [ ! -z "$AZ_TENANT_ID" ]; then
    # Local Mode with the same Service Principal as CI: no browser needed
    log "🤖 Local detected with AZ_CLIENT_ID, AZ_CLIENT_SECRET and AZ_TENANT_ID set (env or playground secrets): Logging in via Service Principal (MFA-exempt)"
    if ! az login --service-principal \
             -u "$AZ_CLIENT_ID" \
             -p "$AZ_CLIENT_SECRET" \
             --tenant "$AZ_TENANT_ID" > /dev/null 2>&1
    then
      logerror "❌ Service Principal login failed, check AZ_CLIENT_ID, AZ_CLIENT_SECRET and AZ_TENANT_ID"
      exit 1
    fi
  else
    # Local Mode: Use Browser-based MFA login
    log "🫐 Local detected: Opening browser for interactive MFA login..."
    log "💡 to skip it, set AZ_CLIENT_ID, AZ_CLIENT_SECRET and AZ_TENANT_ID (same Service Principal as CI) with <playground secrets set>"
    az login
  fi

  # 3. Handle Subscription Selection
  if [ ! -z "$AZURE_SUBSCRIPTION_NAME" ]; then
    log "💙 AZURE_SUBSCRIPTION_NAME ($AZURE_SUBSCRIPTION_NAME) is set, searching for id..."
    
    # Using -o tsv is faster and safer than jq for single values
    subscriptionId=$(az account list --query "[?name=='$AZURE_SUBSCRIPTION_NAME'].id" -o tsv)

    if [ -z "$subscriptionId" ]; then
        logerror "❌ Could not find subscription: $AZURE_SUBSCRIPTION_NAME"
        exit 1
    fi

    [ -z "$GITHUB_RUN_NUMBER" ] && log "💙 Setting subscription to $AZURE_SUBSCRIPTION_NAME ($subscriptionId)"
    az account set --subscription "$subscriptionId"
    
  else
    # 4. Confluent Safety Check
    userEmail=$(az account show --query "user.name" -o tsv)
    
    if [[ $userEmail == *"confluent.io"* ]]; then
      logerror "🔒 Confluent account detected. Please set AZURE_SUBSCRIPTION_NAME to ensure correct billing/env!"
      if [ -z "$GITHUB_RUN_NUMBER" ]; then
        logerror "✨ Available subscriptions:"
        az account list --query "[].{name:name, tenantId:tenantId}" -o table
      fi
      exit 1
    fi

    default_sub=$(az account show --query "name" -o tsv)
    log "💎 AZURE_SUBSCRIPTION_NAME not set, using default: $default_sub"
  fi

  if [ -z "$GITHUB_RUN_NUMBER" ]
  then
    if [ -z "$AZ_USER" ]
    then
        AZ_USER=$(az account show --query "user.name" -o tsv)
    fi
    log "👤 Logged in as: $AZ_USER"
  fi
}

#
# Names of the environment variables an example requires, one per line.
#
# Derived from the standard error string that examples use:
#
#   logerror "FOO is not set. Export it as environment variable or pass it as argument"
#
# Shared by the fzf preview of `playground run`, by the pre-flight of a non
# interactive run, and by `playground secrets check`.
#
function get_mandatory_env_vars () {
  local test_file="$1"
  [ -f "$test_file" ] || return 0

  {
    awk -F '"' '/Export it as environment variable or pass it as argument/ { split($2,a," "); print a[1] }' "$test_file"

    # a few variables are required by a shared helper the example calls, so the
    # marker is in this library rather than in the example itself
    if grep -q "display_ngrok_warning" "$test_file"
    then
      echo "NGROK_AUTH_TOKEN"
    fi
  } | awk 'NF' | sort -u
}

# Confluent Cloud variables read by bootstrap_ccloud_environment and the
# fully managed connector commands. None of them is mandatory: without
# CLUSTER_NAME a new cluster is created.
function get_ccloud_env_vars () {
  echo "CONFLUENT_CLOUD_API_KEY CONFLUENT_CLOUD_API_SECRET ENVIRONMENT SCHEMA_REGISTRY_CREDS"
  local prefix
  for prefix in "" AWS_ GCP_ AZURE_ AWS_DATABRICKS_
  do
    echo "${prefix}CLUSTER_NAME ${prefix}CLUSTER_CLOUD ${prefix}CLUSTER_REGION ${prefix}CLUSTER_CREDS"
  done
}

#
# Variables an example does not declare, because they are read by a shared
# helper it calls and they are optional, but that should still come from the
# secrets store when they are not exported. Without them, a fully managed
# example would create a new ccloud cluster instead of using CLUSTER_NAME.
#
function get_optional_env_vars () {
  local test_file="$1"
  local environment="$2"
  [ -f "$test_file" ] || return 0

  {
    if [[ "$test_file" == *"ccloud"* ]] || [ "$environment" == "ccloud" ] || grep -q "bootstrap_ccloud_environment" "$test_file"
    then
      get_ccloud_env_vars
    fi

    if grep -q "handle_aws_credentials" "$test_file"
    then
      echo "AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION"
    fi

    if grep -q "login_and_maybe_set_azure_subscription" "$test_file"
    then
      echo "AZ_USER AZ_PASS AZ_CLIENT_ID AZ_CLIENT_SECRET AZ_TENANT_ID AZURE_SUBSCRIPTION_NAME"
    fi
  } | tr ' ' '\n' | awk 'NF' | sort -u
}

function handle_aws_credentials () {
  rm -rf /tmp/aws_credentials
  export AWS_CREDENTIALS_FILE_NAME="/tmp/aws_credentials"

  if [ -z "$AWS_SESSION_TOKEN" ]
  then
    if [ ! -f $HOME/.aws/credentials ] && ( [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ] )
    then
      logerror "❌ either the file $HOME/.aws/credentials is not present or environment variables AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY are not set!"
      exit 1
    else
      if [ ! -z "$AWS_ACCESS_KEY_ID" ] && [ ! -z "$AWS_SECRET_ACCESS_KEY" ]
      then
          log "💭 Using environment variables AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY"
          export AWS_ACCESS_KEY_ID
          export AWS_SECRET_ACCESS_KEY
      else
          if [ -f $HOME/.aws/credentials ]
          then
              logwarn "💭 AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY are set based on $HOME/.aws/credentials"
              export AWS_ACCESS_KEY_ID=$( grep "^aws_access_key_id" $HOME/.aws/credentials | head -1 | awk -F'=' '{print $2;}' )
              export AWS_SECRET_ACCESS_KEY=$( grep "^aws_secret_access_key" $HOME/.aws/credentials | head -1 | awk -F'=' '{print $2;}' ) 
          fi
      fi

      cat << EOF > $AWS_CREDENTIALS_FILE_NAME
[default]
aws_access_key_id=$AWS_ACCESS_KEY_ID
aws_secret_access_key=$AWS_SECRET_ACCESS_KEY
EOF
      if [ -z "$AWS_REGION" ]
      then
          AWS_REGION=$(aws configure get region | tr '\r' '\n')
          if [ "$AWS_REGION" == "" ]
          then
              logerror "❌ either the file $HOME/.aws/config is not present or environment variables AWS_REGION is not set!"
              exit 1
          fi
      fi
    fi
  else
    if [ ! -z $AWS_PROFILE ] && [ -z "$AWS_SESSION_TOKEN" ]
    then
      logwarn "💭 AWS_PROFILE environment variable is set with $AWS_PROFILE"
      logwarn "🚀 run manually this command and re-run the example again:"
      echo "source <(aws configure export-credentials --profile $AWS_PROFILE --format env)"
      exit 1
    fi

    #
    # AWS short live credentials
    #
    if [ ! -z $AWS_SESSION_TOKEN ] || grep -q "aws_session_token" $HOME/.aws/credentials
    then
      if [ ! -z $AWS_SESSION_TOKEN ]
      then
          log "🔏 AWS_SESSION_TOKEN environment variable is set, using AWS short live credentials"
      else
          log "🔏 the file $HOME/.aws/credentials contains aws_session_token, using AWS short live credentials"
      fi

      connector_type=$(playground state get run.connector_type)
      
      if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
      then
        logerror "❌ AWS short live credentials are not supported for fully managed connectors or custom connectors"
        exit 1
      fi

      if [ ! -z $AWS_ACCESS_KEY_ID ] && [ ! -z "$AWS_SECRET_ACCESS_KEY" ] && [ ! -z "$AWS_SESSION_TOKEN" ]
      then
          log "💭 Using environment variables AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY and AWS_SESSION_TOKEN"
          export AWS_ACCESS_KEY_ID
          export AWS_SECRET_ACCESS_KEY
          export AWS_SESSION_TOKEN

      cat << EOF > $AWS_CREDENTIALS_FILE_NAME
[default]
aws_access_key_id=$AWS_ACCESS_KEY_ID
aws_secret_access_key=$AWS_SECRET_ACCESS_KEY
aws_session_token=$AWS_SESSION_TOKEN
EOF
      elif grep -q "aws_session_token" $HOME/.aws/credentials
      then
          head -4 $HOME/.aws/credentials > $AWS_CREDENTIALS_FILE_NAME

          set +e
          grep -q default $AWS_CREDENTIALS_FILE_NAME
          if [ $? != 0 ]
          then
              logerror "$HOME/.aws/credentials does not have expected format, the 4 first lines must be:"
              echo "[default]"
              echo "aws_access_key_id=<AWS_ACCESS_KEY_ID>"
              echo "aws_secret_access_key=<AWS_SECRET_ACCESS_KEY>"
              echo "aws_session_token=<AWS_SESSION_TOKEN>"
              exit 1
          fi
          grep -q aws_session_token $AWS_CREDENTIALS_FILE_NAME
          if [ $? != 0 ]
          then
              logerror "$HOME/.aws/credentials does not have expected format, the 4 first lines must be:"
              echo "[default]"
              echo "aws_access_key_id=<AWS_ACCESS_KEY_ID>"
              echo "aws_secret_access_key=<AWS_SECRET_ACCESS_KEY>"
              echo "aws_session_token=<AWS_SESSION_TOKEN>"
              exit 1
          fi
          set +e
      fi

      log "✨ Using AWS short live with credentials file $AWS_CREDENTIALS_FILE_NAME"
      export AWS_SHORT_LIVE_CREDENTIALS_USED=1
    else
      if [ ! -f $HOME/.aws/credentials ] && ( [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ] )
      then
        logerror "❌ either the file $HOME/.aws/credentials is not present or environment variables AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY are not set!"
        exit 1
      fi
    fi
  fi

  if [ -z "$AWS_REGION" ]
  then
      AWS_REGION=$(aws configure get region | tr '\r' '\n')
      if [ "$AWS_REGION" == "" ]
      then
          logerror "❌ either the file $HOME/.aws/config is not present or environment variables AWS_REGION is not set!"
          exit 1
      fi
  fi

  if [[ "$TAG" == *ubi8 ]] || [[ "$TAG" == *ubi9 ]] || version_gt $TAG_BASE "5.9.0"
  then
      export CONNECT_CONTAINER_HOME_DIR="/home/appuser"
  else
      export CONNECT_CONTAINER_HOME_DIR="/root"
  fi
}

function delete_redshift_security_group_with_retry {
  local CLUSTER_TO_DELETE=$1
  aws redshift wait cluster-deleted --cluster-identifier "$CLUSTER_TO_DELETE" 2>/dev/null
  log "Delete security group sg$CLUSTER_TO_DELETE, if required"
  local SG_DELETE_RETRIES=${SG_DELETE_RETRIES:-5}
  local sg_deleted=false
  for sg_attempt in $(seq 1 "$SG_DELETE_RETRIES"); do
      sleep 120
      if aws ec2 delete-security-group --group-name sg$CLUSTER_TO_DELETE
      then
          sg_deleted=true
          break
      fi
  done
  if [ "$sg_deleted" != true ]
  then
      logwarn "Failed to delete security group sg$CLUSTER_TO_DELETE after cluster $CLUSTER_TO_DELETE was deleted - it will not be retried"
  fi
}

# Deletes a Redshift cluster and, only if that succeeds, its security group (via
# delete_redshift_security_group_with_retry - skipped on failure so callers don't block
# on "aws redshift wait cluster-deleted" for a cluster that isn't actually being deleted).
function delete_redshift_cluster {
  local CLUSTER_TO_DELETE=$1
  local error
  error=$(aws redshift delete-cluster --cluster-identifier $CLUSTER_TO_DELETE --skip-final-cluster-snapshot 2>&1)
  if [ $? -eq 0 ]
  then
      log "Cluster $CLUSTER_TO_DELETE deleted successfully"
      # Once the cluster is gone it never reappears in a future describe-clusters scan,
      # so this is the only chance the reaper gets to clean up its security group.
      delete_redshift_security_group_with_retry "$CLUSTER_TO_DELETE"
      return 0
  else
      logwarn "Failed to delete cluster $CLUSTER_TO_DELETE: $error"
      return 1
  fi
}

# Scans for this script's own Redshift clusters (by REAP_PREFIX) older than
# REDSHIFT_REAP_MAX_AGE_HOURS (env override, default 6) and reaps each one via
# delete_redshift_cluster. Call once, before creating this run's own cluster.
function reap_stale_redshift_clusters {
  local REAP_PREFIX=$1
  local REDSHIFT_REAP_MAX_AGE_HOURS=${REDSHIFT_REAP_MAX_AGE_HOURS:-6}
  log "Reap AWS Redshift clusters matching ${REAP_PREFIX}* older than ${REDSHIFT_REAP_MAX_AGE_HOURS}h, if any"
  set +e
  local NOW_EPOCH=$(date -u +%s)
  local STALE_CLUSTERS=$(aws redshift describe-clusters --query "Clusters[?starts_with(ClusterIdentifier, '${REAP_PREFIX}')].[ClusterIdentifier,ClusterCreateTime]" --output text)
  if [ -n "$STALE_CLUSTERS" ]
  then
      local STALE_NAME STALE_CREATE_TIME STALE_CREATE_EPOCH AGE_HOURS
      while IFS=$'\t' read -r STALE_NAME STALE_CREATE_TIME
      do
          [ -z "$STALE_NAME" ] && continue
          if [[ "$OSTYPE" == "darwin"* ]]
          then
              STALE_CREATE_EPOCH=$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "${STALE_CREATE_TIME%%.*}" +%s 2>/dev/null)
          else
              STALE_CREATE_EPOCH=$(date -u -d "$STALE_CREATE_TIME" +%s 2>/dev/null)
          fi
          [ -z "$STALE_CREATE_EPOCH" ] && continue
          AGE_HOURS=$(( (NOW_EPOCH - STALE_CREATE_EPOCH) / 3600 ))
          if [ "$AGE_HOURS" -ge "$REDSHIFT_REAP_MAX_AGE_HOURS" ]
          then
              logwarn "Reaping orphaned Redshift cluster $STALE_NAME (age ${AGE_HOURS}h)"
              delete_redshift_cluster "$STALE_NAME"
          fi
      done <<< "$STALE_CLUSTERS"
  fi
  set -e
}

function wait_for_end_of_hibernation () {
     MAX_WAIT=600
     CUR_WAIT=0
     set +e
     log "⌛ Waiting up to $MAX_WAIT seconds for end of hibernation to happen (it can take several minutes)"
     curl -X POST "${SERVICENOW_URL}/api/now/table/incident" --user admin:"$SERVICENOW_PASSWORD" -H 'Accept: application/json' -H 'Content-Type: application/json' -H 'cache-control: no-cache' -d '{"short_description": "This is test"}' > /tmp/out.txt 2>&1
     while [[ $(cat /tmp/out.txt) =~ "Sign in to the site to wake your instance" ]] || ! [[ $(cat /tmp/out.txt) =~ "made_sla" ]]
     do
          sleep 10
          curl -X POST "${SERVICENOW_URL}/api/now/table/incident" --user admin:"$SERVICENOW_PASSWORD" -H 'Accept: application/json' -H 'Content-Type: application/json' -H 'cache-control: no-cache' -d '{"short_description": "This is test"}' > /tmp/out.txt 2>&1
          CUR_WAIT=$(( CUR_WAIT+10 ))
          if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
               echo -e "\nERROR: The logs still show 'Sign in to the site to wake your instance' after $MAX_WAIT seconds.\n"
               exit 1
          fi
     done
     log "The instance is ready !"
     set -e
}

# free tier Capella clusters are turned off after 72 hours of inactivity
# set COUCHBASE_CAPELLA_FREE_TIER=false for a paid cluster
function couchbase_capella_ensure_cluster_on () {
  if [ -z "$COUCHBASE_CAPELLA_API_KEY" ] || [ -z "$COUCHBASE_CAPELLA_ORG_ID" ] || [ -z "$COUCHBASE_CAPELLA_PROJECT_ID" ] || [ -z "$COUCHBASE_CAPELLA_CLUSTER_ID" ]
  then
    logwarn "🛋️ COUCHBASE_CAPELLA_API_KEY, COUCHBASE_CAPELLA_ORG_ID, COUCHBASE_CAPELLA_PROJECT_ID or COUCHBASE_CAPELLA_CLUSTER_ID is not set, not checking if Capella cluster is turned on"
    return 0
  fi

  local cluster_path="clusters/${COUCHBASE_CAPELLA_CLUSTER_ID}"
  if [ "${COUCHBASE_CAPELLA_FREE_TIER:-true}" == "true" ]
  then
    cluster_path="clusters/freeTier/${COUCHBASE_CAPELLA_CLUSTER_ID}"
  fi
  local url="https://cloudapi.cloud.couchbase.com/v4/organizations/${COUCHBASE_CAPELLA_ORG_ID}/projects/${COUCHBASE_CAPELLA_PROJECT_ID}/${cluster_path}"

  local response
  response=$(curl -s -H "Authorization: Bearer ${COUCHBASE_CAPELLA_API_KEY}" "$url")
  local state
  state=$(echo "$response" | jq -r '.currentState // empty' 2>/dev/null)
  if [ -z "$state" ]
  then
    logerror "❌ could not get Capella cluster ${COUCHBASE_CAPELLA_CLUSTER_ID} state: $response"
    exit 1
  fi
  log "🛋️ Capella cluster ${COUCHBASE_CAPELLA_CLUSTER_ID} state is ${state}"
  if [ "$state" == "healthy" ]
  then
    return 0
  fi

  if [ "$state" == "turnedOff" ]
  then
    log "🔌 Turning on Capella cluster ${COUCHBASE_CAPELLA_CLUSTER_ID}"
    local http_code
    http_code=$(curl -s -o /tmp/capella_turn_on.txt -w '%{http_code}' -X POST -H "Authorization: Bearer ${COUCHBASE_CAPELLA_API_KEY}" -H "Content-Type: application/json" "${url}/activationState")
    if [ "$http_code" != "202" ]
    then
      logerror "❌ failed to turn on Capella cluster ${COUCHBASE_CAPELLA_CLUSTER_ID} (http code $http_code): $(cat /tmp/capella_turn_on.txt)"
      exit 1
    fi
  fi

  local max_wait=900
  local cur_wait=0
  log "⌛ Waiting up to $max_wait seconds for Capella cluster ${COUCHBASE_CAPELLA_CLUSTER_ID} to be healthy"
  while [ "$state" != "healthy" ]
  do
    sleep 30
    cur_wait=$(( cur_wait+30 ))
    if [[ "$cur_wait" -gt "$max_wait" ]]
    then
      logerror "❌ Capella cluster ${COUCHBASE_CAPELLA_CLUSTER_ID} is still ${state} after $max_wait seconds"
      exit 1
    fi
    state=$(curl -s -H "Authorization: Bearer ${COUCHBASE_CAPELLA_API_KEY}" "$url" | jq -r '.currentState // empty' 2>/dev/null)
    log "⏳ Capella cluster ${COUCHBASE_CAPELLA_CLUSTER_ID} state is ${state}"
  done
  log "✅ Capella cluster ${COUCHBASE_CAPELLA_CLUSTER_ID} is healthy"
}

# Databricks SQL warehouses auto stop after some inactivity (10 minutes minimum)
# usage: databricks_ensure_sql_warehouse_running <server hostname> <token> <http path>
function databricks_ensure_sql_warehouse_running () {
  local host="${1#https://}"
  host="${host%%/*}"
  local token="$2"
  local http_path="$3"

  if [ -z "$host" ] || [ -z "$token" ] || [ -z "$http_path" ]
  then
    logwarn "🧱 Databricks hostname, token or http path is not set, not checking if SQL warehouse is running"
    return 0
  fi

  if [[ "$http_path" != *"/warehouses/"* ]]
  then
    logwarn "🧱 Databricks http path $http_path is not a SQL warehouse, not checking if it is running"
    return 0
  fi

  local warehouse_id="${http_path##*/}"
  local url="https://${host}/api/2.0/sql/warehouses/${warehouse_id}"

  local max_wait=900
  local cur_wait=0
  local start_requested=0
  local state=""
  while true
  do
    local response
    response=$(curl -s -H "Authorization: Bearer ${token}" "$url")
    state=$(echo "$response" | jq -r '.state // empty' 2>/dev/null)
    if [ -z "$state" ]
    then
      logwarn "🧱 could not get Databricks SQL warehouse ${warehouse_id} state, not checking if it is running: $response"
      return 0
    fi
    log "🧱 Databricks SQL warehouse ${warehouse_id} state is ${state}"

    case "$state" in
      RUNNING)
        break
        ;;
      STOPPED)
        if [ $start_requested -eq 0 ]
        then
          log "🔌 Starting Databricks SQL warehouse ${warehouse_id}"
          local http_code
          http_code=$(curl -s -o /tmp/databricks_warehouse_start.txt -w '%{http_code}' -X POST -H "Authorization: Bearer ${token}" "${url}/start")
          if [ "$http_code" != "200" ]
          then
            logwarn "🧱 failed to start Databricks SQL warehouse ${warehouse_id} (http code $http_code), not waiting for it: $(cat /tmp/databricks_warehouse_start.txt)"
            return 0
          fi
          start_requested=1
        fi
        ;;
      DELETING|DELETED)
        logerror "❌ Databricks SQL warehouse ${warehouse_id} is ${state}"
        exit 1
        ;;
    esac

    if [[ "$cur_wait" -ge "$max_wait" ]]
    then
      logerror "❌ Databricks SQL warehouse ${warehouse_id} is still ${state} after $max_wait seconds"
      exit 1
    fi
    sleep 10
    cur_wait=$(( cur_wait+10 ))
  done
  log "✅ Databricks SQL warehouse ${warehouse_id} is running"
}

function connect_cp_version_greater_than_8 () {
  if [ ! -z "$CP_CONNECT_TAG" ] && version_gt $CP_CONNECT_TAG "7.9.99"
  then
    return 0
  elif [ ! -z "$TAG_BASE" ] && version_gt $TAG_BASE "7.9.99"
  then
    return 0
  else
    return 1
  fi
}