#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

verify_docker_and_memory

check_docker_compose_version
check_bash_version
check_and_update_playground_version

DOCKER_COMPOSE_FILE_OVERRIDE=$1

# versions of the case:
# - Confluent Platform: --tag (TAG), installed by cp-ansible as confluent_package_version
# - cp-ansible (the confluent.platform collection): ANSIBLE_CP_VERSION, else the latest patch of the same major.minor as TAG
# - ansible-core: ANSIBLE_CORE_VERSION
cp_version="${TAG_BASE:-$TAG}"
cp_major_minor=$(echo "$cp_version" | cut -d "." -f 1,2)
cp_next_minor="$(echo "$cp_major_minor" | cut -d "." -f 1).$(( $(echo "$cp_major_minor" | cut -d "." -f 2) + 1 )).0"
if [ -n "$ANSIBLE_CP_VERSION" ]
then
  export CP_ANSIBLE_VERSION_SPEC="==${ANSIBLE_CP_VERSION}"
  cp_ansible_label="$ANSIBLE_CP_VERSION"
else
  export CP_ANSIBLE_VERSION_SPEC=">=${cp_major_minor}.0,<${cp_next_minor}"
  cp_ansible_label="${cp_major_minor}.x"
fi
export ANSIBLE_CORE_VERSION="${ANSIBLE_CORE_VERSION:-2.17.*}"
export ANSIBLE_CONTROLLER_IMAGE_TAG="cp-ansible-${cp_ansible_label}-core-${ANSIBLE_CORE_VERSION//\*/x}"
ANSIBLE_INSTALLATION_METHOD="${ANSIBLE_INSTALLATION_METHOD:-archive}"

# the docker connection plugin of the controller talks to the engine through its socket
export ANSIBLE_DOCKER_SOCKET="/var/run/docker.sock"
if [[ "${DOCKER_HOST:-}" == unix://* ]]
then
  export ANSIBLE_DOCKER_SOCKET="${DOCKER_HOST#unix://}"
fi

# installation_method archive: the Confluent Platform archive (~1.4 GB) is downloaded once, then every host unpacks it
# from /cache instead of downloading it on each run
export ANSIBLE_ARCHIVE_CACHE_DIR="${ANSIBLE_ARCHIVE_CACHE_DIR:-$HOME/.playground-ansible-cache}"
mkdir -p "$ANSIBLE_ARCHIVE_CACHE_DIR"
archive_file="confluent-${cp_version}.tar.gz"
if [ "$ANSIBLE_INSTALLATION_METHOD" == "archive" ] && [ ! -f "$ANSIBLE_ARCHIVE_CACHE_DIR/$archive_file" ]
then
  archive_url="https://packages.confluent.io/archive/${cp_major_minor}/${archive_file}"
  log "📥 Downloading $archive_url to $ANSIBLE_ARCHIVE_CACHE_DIR (once, ~1.4 GB)"
  if ! curl -fSL --progress-bar -o "$ANSIBLE_ARCHIVE_CACHE_DIR/$archive_file.part" "$archive_url"
  then
    rm -f "$ANSIBLE_ARCHIVE_CACHE_DIR/$archive_file.part"
    logerror "❌ could not download $archive_url: is $cp_version a released Confluent Platform version?"
    exit 1
  fi
  mv "$ANSIBLE_ARCHIVE_CACHE_DIR/$archive_file.part" "$ANSIBLE_ARCHIVE_CACHE_DIR/$archive_file"
fi

# hosts: the default ones, plus the optional ones of the --enable-* flags of playground run, each with the JMX port it
# has in the other playground environments (used by the playground commands that read JMX metrics: JMX_PORT is read
# by the *-run-class scripts, KAFKA_JMX_PORT / SCHEMA_REGISTRY_JMX_PORT / KSQL_JMX_PORT by the playground commands)
# <host> <cp-ansible group> <JMX variable of the playground commands> <JMX port> <compose profile>
ansible_hosts_table="controller kafka_controller KAFKA_JMX_PORT 10005 -
controller2 kafka_controller KAFKA_JMX_PORT 12005 controller-nodes
controller3 kafka_controller KAFKA_JMX_PORT 13005 controller-nodes
broker kafka_broker KAFKA_JMX_PORT 10000 -
broker2 kafka_broker KAFKA_JMX_PORT 12000 kafka-nodes
broker3 kafka_broker KAFKA_JMX_PORT 13000 kafka-nodes
schema-registry schema_registry SCHEMA_REGISTRY_JMX_PORT 10001 -
connect kafka_connect KAFKA_JMX_PORT 10002 -
connect2 kafka_connect KAFKA_JMX_PORT 10022 connect-nodes
connect3 kafka_connect KAFKA_JMX_PORT 10032 connect-nodes
ksqldb-server ksql KSQL_JMX_PORT 10003 ksqldb
rest-proxy kafka_rest - - rest-proxy
control-center control_center_next_gen - - control-center"
enabled_profiles=()
[ -n "$ENABLE_CONTROLLER_NODES" ] && enabled_profiles+=(controller-nodes)
[ -n "$ENABLE_KAFKA_NODES" ] && enabled_profiles+=(kafka-nodes)
[ -n "$ENABLE_CONNECT_NODES" ] && enabled_profiles+=(connect-nodes)
[ -n "$ENABLE_KSQLDB" ] && enabled_profiles+=(ksqldb)
[ -n "$ENABLE_RESTPROXY" ] && enabled_profiles+=(rest-proxy)
[ -n "$ENABLE_CONTROL_CENTER" ] && enabled_profiles+=(control-center)
for unsupported in ENABLE_FLINK ENABLE_JMX_GRAFANA ENABLE_KCAT ENABLE_CONDUKTOR ENABLE_SQL_DATAGEN ENABLE_ZOOKEEPER
do
  if [ -n "${!unsupported}" ]
  then
    logwarn "⚠️ $unsupported is not supported with the ansible environment, ignored"
  fi
done
profile_args=()
ansible_hosts=()
while read -r host group jmx_var jmx_port profile
do
  if [ "$profile" == "-" ] || [[ " ${enabled_profiles[*]} " == *" $profile "* ]]
  then
    ansible_hosts+=("$host")
  fi
done <<< "$ansible_hosts_table"
for profile in "${enabled_profiles[@]}"
do
  profile_args+=(--profile "$profile")
done
log "🖥️ hosts: ${ansible_hosts[*]}"

# inventory: the containers are the hosts, reached with docker exec as root
inventory_dir="${DIR}/inventory"
inventory_file="${inventory_dir}/hosts.yml"
mkdir -p "$inventory_dir"
archive_vars=""
if [ "$ANSIBLE_INSTALLATION_METHOD" == "archive" ]
then
  archive_vars="    confluent_archive_file_source: /cache/${archive_file}
    confluent_archive_file_remote: true"
fi
cat > "$inventory_file" << EOF
# generated by environment/ansible/start.sh: edit it, then run the playbook again with
# docker exec -it ansible-controller ansible-playbook -i /inventory/hosts.yml confluent.platform.all
all:
  vars:
    ansible_connection: community.docker.docker
    ansible_user: root
    ansible_become: false
    confluent_package_version: ${cp_version}
    installation_method: ${ANSIBLE_INSTALLATION_METHOD}
${archive_vars}
    # the hosts come with a JDK (environment/ansible/host/Dockerfile)
    custom_java_path: /usr/lib/jvm/default-java
  children:
EOF
for group in kafka_controller kafka_broker schema_registry kafka_connect ksql kafka_rest control_center_next_gen
do
  group_hosts=""
  while read -r host host_group jmx_var jmx_port profile
  do
    if [ "$host_group" != "$group" ] || [[ " ${ansible_hosts[*]} " != *" $host "* ]]
    then
      continue
    fi
    group_hosts+="        ${host}:
"
    if [ "$jmx_var" != "-" ]
    then
      # host variables: merged with the group variables (hash_behaviour = merge)
      group_hosts+="          ${group}_service_environment_overrides:
            JMX_PORT: ${jmx_port}
            ${jmx_var}: ${jmx_port}
"
    fi
  done <<< "$ansible_hosts_table"
  if [ -z "$group_hosts" ]
  then
    continue
  fi
  {
    echo "    ${group}:"
    echo "      hosts:"
    printf "%s" "$group_hosts"
    if [ "$group" == "kafka_connect" ]
    then
      cat << 'EOF'
      vars:
        # worker settings of the other playground environments, the examples rely on them
        kafka_connect_custom_properties:
          key.converter: org.apache.kafka.connect.storage.StringConverter
          config.providers: file
          config.providers.file.class: org.apache.kafka.common.config.provider.FileConfigProvider
EOF
    fi
  } >> "$inventory_file"
done

# the docker compose override of an example (playground run --environment ansible): the hosts are not cp images, so
#  - the environment variables of controller, broker, schema-registry and connect become inventory variables, with the
#    naming of the cp images (CONNECT_PLUGIN_PATH -> plugin.path in kafka_connect_custom_properties, KAFKA_OPTS and the
#    other JVM variables -> <component>_service_environment_overrides)
#  - their image, command, entrypoint... are removed (they would replace the host), their volumes and ports are kept
#  - the other services of the example (databases, http servers...) start as they are
compose_files=(-f ../../environment/ansible/docker-compose.yml)
if [ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]
then
  check_arm64_support "${DIR}" "${DOCKER_COMPOSE_FILE_OVERRIDE}"
  log "🧩 translating the example's docker compose override $(basename "${DOCKER_COMPOSE_FILE_OVERRIDE}") into inventory variables"
  merged_json=$(docker compose -f ../../environment/ansible/docker-compose.yml -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" config --format json)
  archive_share_dir=""
  if [ "$ANSIBLE_INSTALLATION_METHOD" == "archive" ]
  then
    archive_share_dir="/opt/confluent/confluent-${cp_version}/share/"
  fi
  # host group prefix skip(regex) env(regex): variables starting with <prefix> are properties, except <skip> (log4j
  # settings of the cp images, ignored) and <env> (JVM settings); variables without the prefix go to the environment
  while read -r host group prefix skip env_re
  do
    vars_json=$(echo "$merged_json" | jq -c --arg svc "$host" --arg prefix "$prefix" --arg skip "$skip" --arg envre "$env_re" --arg share "$archive_share_dir" '
      (.services[$svc].environment // {}) | to_entries | map(select(.value != null and .value != "")) |
      reduce .[] as $e ({props: {}, env: {}, skipped: []};
        if ($e.key | startswith($prefix)) and ($e.key | test($skip)) then .skipped += [$e.key]
        elif ($e.key | startswith($prefix)) and (($e.key | test($envre)) | not) then
          .props[$e.key | ltrimstr($prefix) | ascii_downcase | gsub("___"; "-") | gsub("__"; "\u0001") | gsub("_"; ".") | gsub("\u0001"; "_")] = $e.value
        else .env[$e.key] = $e.value end)
      | if $share != "" and .props["plugin.path"] then
          .props["plugin.path"] |= (split(",") | map(gsub("^\\s+|\\s+$"; "") | if test("^/usr/share/(?!confluent-hub-components)") then sub("^/usr/share/"; $share) else . end) | join(","))
        else . end')
    nb_props=$(echo "$vars_json" | jq '.props | length')
    nb_env=$(echo "$vars_json" | jq '.env | length')
    if [ "$nb_props" != "0" ]
    then
      PROPS=$(echo "$vars_json" | jq -c '.props') yq -i -P ".all.children.${group}.vars.${group}_custom_properties *= (strenv(PROPS) | from_yaml)" "$inventory_file"
      log "   $host: $(echo "$vars_json" | jq -r '.props | to_entries | map("\(.key)=\(.value)") | join(", ")' | cut -c1-300) (${group}_custom_properties)"
    fi
    # KAFKA_OPTS / SCHEMA_REGISTRY_OPTS: appended to the java arguments cp-ansible builds (<group>_custom_java_args),
    # instead of replacing them
    java_args=$(echo "$vars_json" | jq -r '.env | to_entries | map(select(.key | test("^(KAFKA|SCHEMA_REGISTRY)_OPTS$")) | .value) | join(" ")')
    if [ -n "$java_args" ]
    then
      JARGS="$java_args" yq -i -P ".all.children.${group}.vars.${group}_custom_java_args = strenv(JARGS)" "$inventory_file"
      log "   $host: java arguments $java_args (${group}_custom_java_args)"
      vars_json=$(echo "$vars_json" | jq -c '.env |= with_entries(select(.key | test("^(KAFKA|SCHEMA_REGISTRY)_OPTS$") | not))')
      nb_env=$(echo "$vars_json" | jq '.env | length')
    fi
    if [ "$nb_env" != "0" ]
    then
      ENVS=$(echo "$vars_json" | jq -c '.env') yq -i -P ".all.children.${group}.vars.${group}_service_environment_overrides *= (strenv(ENVS) | from_yaml)" "$inventory_file"
      log "   $host: environment $(echo "$vars_json" | jq -r '.env | keys | join(", ")') (${group}_service_environment_overrides)"
    fi
    skipped=$(echo "$vars_json" | jq -r '.skipped | join(", ")')
    if [ -n "$skipped" ]
    then
      logwarn "   $host: ignored $skipped (log4j settings of the cp images: use ${group}_custom_log4j2 or playground debug log-level)"
    fi
  done << 'HOSTS'
controller kafka_controller KAFKA_ ^KAFKA_(LOG4J_|TOOLS_LOG4J|JMX_HOSTNAME) ^KAFKA_(OPTS|HEAP_OPTS|JMX_PORT|JMX_OPTS|JVM_PERFORMANCE_OPTS|GC_LOG_OPTS|DEBUG)$
broker kafka_broker KAFKA_ ^KAFKA_(LOG4J_|TOOLS_LOG4J|JMX_HOSTNAME) ^KAFKA_(OPTS|HEAP_OPTS|JMX_PORT|JMX_OPTS|JVM_PERFORMANCE_OPTS|GC_LOG_OPTS|DEBUG)$
schema-registry schema_registry SCHEMA_REGISTRY_ ^SCHEMA_REGISTRY_(LOG4J_|JMX_HOSTNAME) ^SCHEMA_REGISTRY_(OPTS|HEAP_OPTS|JMX_PORT|JMX_OPTS|JVM_PERFORMANCE_OPTS)$
connect kafka_connect CONNECT_ ^CONNECT_LOG4J_ ^$
HOSTS
  generated_override="${inventory_dir}/docker-compose.override.yml"
  yq '.services |= with_entries(select(.key | test("^(controller|broker|connect)[23]?$|^schema-registry$")).value |= del(.image, .build, .entrypoint, .command, .environment, .env_file, .healthcheck, .user, .restart, .profiles, .hostname, .container_name, .platform))' "${DOCKER_COMPOSE_FILE_OVERRIDE}" > "$generated_override"
  compose_files+=(-f "$generated_override")
fi

log "🅰️ cp-ansible environment: Confluent Platform $cp_version (installation_method: $ANSIBLE_INSTALLATION_METHOD), confluent.platform collection $cp_ansible_label, ansible-core $ANSIBLE_CORE_VERSION"

docker compose "${compose_files[@]}" "${profile_args[@]}" build --quiet

if [[ -z "$NO_STOP" ]]
then
  docker compose "${compose_files[@]}" --profile '*' down -v --remove-orphans
fi

# connector plugins installed by playground run (--connector-tag, --connector-zip...), mounted in connect as in the
# other environments
mkdir -p "${DIR}/../../confluent-hub"
docker compose "${compose_files[@]}" "${profile_args[@]}" up -d --quiet-pull
# the variables of the compose file are exported by this script: the saved command (stop, re-run) sets them again
command="source ${DIR}/../../scripts/utils.sh && ANSIBLE_ARCHIVE_CACHE_DIR='${ANSIBLE_ARCHIVE_CACHE_DIR}' ANSIBLE_DOCKER_SOCKET='${ANSIBLE_DOCKER_SOCKET}' ANSIBLE_CORE_VERSION='${ANSIBLE_CORE_VERSION}' CP_ANSIBLE_VERSION_SPEC='${CP_ANSIBLE_VERSION_SPEC}' ANSIBLE_CONTROLLER_IMAGE_TAG='${ANSIBLE_CONTROLLER_IMAGE_TAG}' docker compose -f ${DIR}/../../environment/ansible/docker-compose.yml ${generated_override:+-f ${generated_override}} ${profile_args[*]} up -d --quiet-pull"
playground state set run.docker_command "$command"
playground state set run.environment "ansible"

cp_ansible_installed=$(docker exec ansible-controller ansible-galaxy collection list confluent.platform 2> /dev/null | awk '$1 == "confluent.platform" {print $2}' | head -1)
log "🅰️ installed collection: confluent.platform ${cp_ansible_installed:-unknown}"

playbook_log="${PLAYGROUND_HOST_TMP_DIR:-/tmp}/playground-ansible-playbook.log"
playbook_command="ansible-playbook -i /inventory/hosts.yml confluent.platform.all ${ANSIBLE_PLAYBOOK_EXTRA_ARGS}"
log "▶️ Running the playbook (a few minutes): docker exec ansible-controller $playbook_command"
log "📄 Playbook output: tail -f $playbook_log"
set +e
docker exec -e ANSIBLE_FORCE_COLOR=0 ansible-controller $playbook_command > "$playbook_log" 2>&1
playbook_rc=$?
set -e
sed -n '/^PLAY RECAP/,/^$/p' "$playbook_log"
if [ $playbook_rc -ne 0 ]
then
  # the task that failed and its error ("fatal:" for a task, "failed:" for an item of a loop)
  grep -E "^(fatal|failed): " "$playbook_log" | sed -E 's/^(fatal|failed): \[([^]]*)\].*"msg": "([^"]*).*/   ❌ \2: \3/' | sort -u | head -20
  logerror "❌ the playbook failed (exit code $playbook_rc), full output in $playbook_log"
  log "🎓 the hosts are still running: fix $inventory_file, then run the playbook again (add -vvv or --tags <tag>)"
  log "    docker exec -it ansible-controller ansible-playbook -i /inventory/hosts.yml confluent.platform.all"
  exit 1
fi

# hand over to the CLI: the playground commands run kafka-* tools with docker exec, and look for client.properties
# and the log4j configuration of the tools in /etc/kafka. With installation_method archive, the binaries are in /opt/confluent/confluent-<version>/bin, not on
# the PATH, and the configuration under /opt/confluent/etc. Wrappers, not symlinks: kafka-run-class finds its jars
# relative to its own path
for host in "${ansible_hosts[@]}"
do
  docker exec -i "$host" bash << 'EOF'
bin_dir=$(ls -d /opt/confluent/confluent-[0-9]*/bin 2> /dev/null | head -1)
if [ -n "$bin_dir" ]
then
  etc_dir="${bin_dir%/bin}/etc"
  for f in "$bin_dir"/*
  do
    [ -f "$f" ] && [ -x "$f" ] || continue
    target="/usr/local/bin/$(basename "$f")"
    rm -f "$target"
    cat > "$target" << WRAPPER
#!/bin/sh
# environment/ansible: $f, with the log4j configuration of the tools (an archive install has no bin/../config)
export KAFKA_LOG4J_OPTS="\${KAFKA_LOG4J_OPTS:--Dlog4j2.configurationFile=file:$etc_dir/kafka/tools-log4j2.yaml}"
export SCHEMA_REGISTRY_LOG4J_OPTS="\${SCHEMA_REGISTRY_LOG4J_OPTS:--Dlog4j2.configurationFile=file:$etc_dir/kafka/tools-log4j2.yaml}"
exec $f "\$@"
WRAPPER
    chmod 755 "$target"
  done
  # the playground commands pass the paths of the cp images: /etc/kafka/client.properties, /etc/kafka/tools-log4j2.yaml
  mkdir -p /etc/kafka
  for file in /opt/confluent/etc/kafka/client.properties "$etc_dir"/kafka/tools-log4j*
  do
    if [ -f "$file" ] && [ ! -e "/etc/kafka/$(basename "$file")" ]
    then
      ln -s "$file" "/etc/kafka/$(basename "$file")"
    fi
  done
fi
EOF
done

log "📝 To see the properties files generated by cp-ansible, use cli command 'playground container exec -c broker --command \"cat /opt/confluent/etc/kafka/server.properties\"' (package install: /etc/kafka/server.properties)"
log "📝 Inventory: $inventory_file, playbook output: $playbook_log"

wait_container_ready
