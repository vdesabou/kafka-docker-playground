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
# - with a customer inventory (ANSIBLE_CUSTOMER_INVENTORY, playground run --ansible-inventory): its confluent_package_version
#   and installation_method, see below
export ANSIBLE_CORE_VERSION="${ANSIBLE_CORE_VERSION:-2.17.*}"
function set_cp_versions () {
  cp_version="$1"
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
  export ANSIBLE_CONTROLLER_IMAGE_TAG="cp-ansible-${cp_ansible_label}-core-${ANSIBLE_CORE_VERSION//\*/x}"
}
set_cp_versions "${TAG_BASE:-$TAG}"
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

# the inventory of the customer (ANSIBLE_CUSTOMER_INVENTORY, playground run --ansible-inventory <hosts.yml>): its variables
# are kept, its hosts become the playground hosts, see inventory_overlay.py. It runs in the controller image (python and
# the yaml loader of ansible, for the !vault values)
overlay_json=""
if [ -n "${ANSIBLE_CUSTOMER_INVENTORY:-}" ]
then
  if [ ! -f "$ANSIBLE_CUSTOMER_INVENTORY" ]
  then
    logerror "❌ the customer inventory $ANSIBLE_CUSTOMER_INVENTORY does not exist"
    exit 1
  fi
  customer_inventory="$(cd "$(dirname "$ANSIBLE_CUSTOMER_INVENTORY")" && pwd)/$(basename "$ANSIBLE_CUSTOMER_INVENTORY")"
  function run_inventory_overlay () {
    docker compose -f ../../environment/ansible/docker-compose.yml build --quiet ansible-controller > /dev/null
    docker run --rm -v "$customer_inventory:/input/hosts.yml:ro" -v "${DIR}/inventory_overlay.py:/overlay.py:ro" "kdp-ansible-controller:${ANSIBLE_CONTROLLER_IMAGE_TAG}" python3 /overlay.py /input/hosts.yml
  }
  log "📋 reading the customer inventory $customer_inventory"
  overlay_json=$(run_inventory_overlay)
  if [ -z "$overlay_json" ] || [ "$(echo "$overlay_json" | jq -r '.error // empty')" != "" ]
  then
    logerror "❌ ${overlay_json:+$(echo "$overlay_json" | jq -r '.error')}"
    exit 1
  fi
  customer_version=$(echo "$overlay_json" | jq -r '.version')
  if [ -n "$customer_version" ] && [ "$customer_version" != "$cp_version" ]
  then
    log "📋 confluent_package_version of the customer inventory: $customer_version (instead of $cp_version)"
    set_cp_versions "$customer_version"
  fi
  customer_method=$(echo "$overlay_json" | jq -r '.method')
  if [ -n "$customer_method" ]
  then
    ANSIBLE_INSTALLATION_METHOD="$customer_method"
  fi
  echo "$overlay_json" | jq -r '.changes[] | "   ✏️ " + .' | while read -r line; do log "$line"; done
  echo "$overlay_json" | jq -r '.warnings[] | "   ⚠️ " + .' | while read -r line; do logwarn "$line"; done
fi

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
ansible_hosts_table="zookeeper zookeeper KAFKA_JMX_PORT 9999 zookeeper
zookeeper2 zookeeper KAFKA_JMX_PORT 12999 zookeeper
zookeeper3 zookeeper KAFKA_JMX_PORT 13999 zookeeper
controller kafka_controller KAFKA_JMX_PORT 10005 -
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
if [ -n "$overlay_json" ]
then
  # the hosts of the customer inventory, the --enable-* flags don't apply
  read -r -a ansible_hosts <<< "$(echo "$overlay_json" | jq -r '.hosts | join(" ")')"
  enabled_profiles=()
  while read -r host group jmx_var jmx_port profile
  do
    if [ "$profile" != "-" ] && [[ " ${ansible_hosts[*]} " == *" $host "* ]] && [[ " ${enabled_profiles[*]} " != *" $profile "* ]]
    then
      enabled_profiles+=("$profile")
    fi
  done <<< "$ansible_hosts_table"
else
  while read -r host group jmx_var jmx_port profile
  do
    if [ "$profile" == "-" ] || [[ " ${enabled_profiles[*]} " == *" $profile "* ]]
    then
      ansible_hosts+=("$host")
    fi
  done <<< "$ansible_hosts_table"
fi
for profile in "${enabled_profiles[@]}"
do
  profile_args+=(--profile "$profile")
done
log "🖥️ hosts: ${ansible_hosts[*]}"

# security of the cluster (environment/ansible-sasl-ssl sets ANSIBLE_SECURITY): cp-ansible generates the certificates
security_vars=""
ansible_environment_name="ansible"
if [ -n "$overlay_json" ] && [ -n "${ANSIBLE_SECURITY:-}" ]
then
  logwarn "⚠️ the security of the customer inventory is used, not the one of the ansible-${ANSIBLE_SECURITY} environment"
  ANSIBLE_SECURITY=""
fi
case "${ANSIBLE_SECURITY:-}" in
  "")
    ;;
  sasl-ssl)
    ansible_environment_name="ansible-sasl-ssl"
    security_vars="    # SASL/PLAIN authentication and SSL encryption on every listener, self-signed certificates generated by cp-ansible
    sasl_protocol: plain
    ssl_enabled: true"
    ;;
  *)
    logerror "❌ ANSIBLE_SECURITY=${ANSIBLE_SECURITY} is not supported (sasl-ssl)"
    exit 1
    ;;
esac

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
if [ -n "$overlay_json" ]
then
  {
    echo "# generated by environment/ansible/start.sh from the customer inventory $customer_inventory: edit it, then run"
    echo "# the playbook again with docker exec -it ansible-controller ansible-playbook -i /inventory/hosts.yml confluent.platform.all"
    echo "$overlay_json" | jq '.inventory' | yq -P -o yaml '.'
  } > "$inventory_file"
  # what the hosts of the playground need: the docker connection, the JDK of the hosts, the archive of the cache
  ARCHIVE_SOURCE="/cache/${archive_file}" CP_VERSION="$cp_version" METHOD="$ANSIBLE_INSTALLATION_METHOD" yq -i -P '
    .all.vars.ansible_connection = "community.docker.docker"
    | .all.vars.ansible_user = "root"
    | .all.vars.ansible_become = false
    | .all.vars.custom_java_path = "/usr/lib/jvm/default-java"
    | .all.vars.confluent_package_version = strenv(CP_VERSION)
    | .all.vars.installation_method = strenv(METHOD)
    | (select(strenv(METHOD) == "archive") | .all.vars.confluent_archive_file_source = strenv(ARCHIVE_SOURCE) | .all.vars.confluent_archive_file_remote = true) // .' "$inventory_file"
  # the JMX ports of the other playground environments, as host variables
  while read -r host group jmx_var jmx_port profile
  do
    if [ "$jmx_var" != "-" ] && [[ " ${ansible_hosts[*]} " == *" $host "* ]]
    then
      yq -i -P ".all.children.${group}.hosts.\"${host}\".${group}_service_environment_overrides.JMX_PORT = ${jmx_port} | .all.children.${group}.hosts.\"${host}\".${group}_service_environment_overrides.${jmx_var} = ${jmx_port}" "$inventory_file"
    fi
  done <<< "$ansible_hosts_table"
else
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
${security_vars}
  children:
EOF
for group in zookeeper kafka_controller kafka_broker schema_registry kafka_connect ksql kafka_rest control_center_next_gen
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
fi

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

log "🅰️ cp-ansible environment ${ansible_environment_name}: Confluent Platform $cp_version (installation_method: $ANSIBLE_INSTALLATION_METHOD), confluent.platform collection $cp_ansible_label, ansible-core $ANSIBLE_CORE_VERSION"

docker compose "${compose_files[@]}" "${profile_args[@]}" build --quiet

if [[ -z "$NO_STOP" ]]
then
  docker compose "${compose_files[@]}" --profile '*' down -v --remove-orphans
fi

# connector plugins installed by playground run (--connector-tag, --connector-zip...), mounted in connect as in the
# other environments
mkdir -p "${DIR}/../../confluent-hub"
docker compose "${compose_files[@]}" "${profile_args[@]}" up -d --quiet-pull
# the hosts started but not in the inventory: a customer inventory without some of the default hosts (no connect,
# ZooKeeper instead of KRaft controllers...), or with 2 brokers (a compose profile starts broker2 and broker3)
unused_hosts=()
while read -r host group jmx_var jmx_port profile
do
  if { [ "$profile" == "-" ] || [[ " ${enabled_profiles[*]} " == *" $profile "* ]]; } && [[ " ${ansible_hosts[*]} " != *" $host "* ]]
  then
    unused_hosts+=("$host")
  fi
done <<< "$ansible_hosts_table"
if [ ${#unused_hosts[@]} -gt 0 ]
then
  docker compose "${compose_files[@]}" "${profile_args[@]}" rm -s -f "${unused_hosts[@]}" > /dev/null 2>&1
fi
# the variables of the compose file are exported by this script: the saved command (stop, re-run) sets them again
command="source ${DIR}/../../scripts/utils.sh && ANSIBLE_ARCHIVE_CACHE_DIR='${ANSIBLE_ARCHIVE_CACHE_DIR}' ANSIBLE_DOCKER_SOCKET='${ANSIBLE_DOCKER_SOCKET}' ANSIBLE_CORE_VERSION='${ANSIBLE_CORE_VERSION}' CP_ANSIBLE_VERSION_SPEC='${CP_ANSIBLE_VERSION_SPEC}' ANSIBLE_CONTROLLER_IMAGE_TAG='${ANSIBLE_CONTROLLER_IMAGE_TAG}' docker compose -f ${DIR}/../../environment/ansible/docker-compose.yml ${generated_override:+-f ${generated_override}} ${profile_args[*]} up -d --quiet-pull"
playground state set run.docker_command "$command"
playground state set run.environment "$ansible_environment_name"

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

# security of the clients of the playground commands, derived from the configuration cp-ansible rendered (any
# security of the inventory, nothing to set with plaintext): on each host, /etc/kafka/client.properties is the one of
# the broker, else the client settings of the component itself (connect worker, kafkastore.* of schema registry,
# ksqlDB server, client.* of REST Proxy). The playground commands run their Kafka tools with it
for host in "${ansible_hosts[@]}"
do
  docker exec -i "$host" bash << 'EOF'
if [ ! -e /etc/kafka/client.properties ]
then
  mkdir -p /etc/kafka
  for root in /opt/confluent/etc /etc
  do
    for spec in kafka/connect-distributed.properties: schema-registry/schema-registry.properties:kafkastore. ksqldb/ksql-server.properties: kafka-rest/kafka-rest.properties:client.
    do
      file="$root/${spec%%:*}"
      prefix="${spec#*:}"
      if [ -f "$file" ]
      then
        sed -n -E "s/^${prefix//./\\.}(security\.protocol|sasl\.[a-z.]+|ssl\.(truststore|keystore|key|endpoint)[a-z.]*)=/\1=/p" "$file" > /etc/kafka/client.properties
        break 2
      fi
    done
  done
  # nothing to set with plaintext (security.protocol=PLAINTEXT only)
  if ! grep -qv "^security.protocol=PLAINTEXT$" /etc/kafka/client.properties 2> /dev/null
  then
    rm -f /etc/kafka/client.properties
  fi
fi
EOF
done
# CA of the cluster, for the https REST APIs (curl --cacert): the certificates of the truststore of connect
rm -f "${inventory_dir}/ca.pem"
ca_host="connect"
if [[ " ${ansible_hosts[*]} " != *" connect "* ]]
then
  ca_host="broker"
fi
truststore=$(docker exec "$ca_host" sh -c 'sed -n "s/^ssl.truststore.location=//p" /etc/kafka/client.properties 2> /dev/null' | head -1)
truststore_password=$(docker exec "$ca_host" sh -c 'sed -n "s/^ssl.truststore.password=//p" /etc/kafka/client.properties 2> /dev/null' | head -1)
if [ -n "$truststore" ]
then
  docker exec "$ca_host" keytool -list -rfc -keystore "$truststore" -storepass "$truststore_password" 2> /dev/null | awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/' > "${inventory_dir}/ca.pem"
  log "🔐 security of the cluster: $(docker exec "$ca_host" sed -n 's/^security.protocol=//p' /etc/kafka/client.properties), CA of the REST APIs in ${inventory_dir}/ca.pem"
  if is_ansible_host ksqldb-server 2> /dev/null && [[ " ${ansible_hosts[*]} " == *" ksqldb-server "* ]]
  then
    # the ksql cli of playground ksqldb sql: the truststore of the ksqlDB host for its https listener
    docker exec ksqldb-server sh -c 'sed -n -E "s/^(ssl\.truststore\.(location|password))=/\1=/p" /etc/kafka/client.properties > /etc/kafka/ksql-cli.properties'
  fi
fi

log "📝 To see the properties files generated by cp-ansible, use cli command 'playground container exec -c broker --command \"cat /opt/confluent/etc/kafka/server.properties\"' (package install: /etc/kafka/server.properties)"
log "📝 Inventory: $inventory_file, playbook output: $playbook_log"

if [[ " ${ansible_hosts[*]} " == *" connect "* ]]
then
  wait_container_ready
else
  log "🚦 no connect host in the inventory, the cluster is ready"
fi
