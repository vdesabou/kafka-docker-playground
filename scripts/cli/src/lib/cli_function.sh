function get_environment_used() {
  environment=$(playground state get run.environment)
}

# mdc-* environments run two clusters, us and europe: the commands work on the one set with --cluster, else
# $PLAYGROUND_CLUSTER, else 'playground state set run.cluster <cluster>'. Never guessed: exits when none is set.
# Sets $mdc_cluster and exports PLAYGROUND_CLUSTER so that the nested playground calls use the same cluster.
function get_mdc_cluster() {
  mdc_cluster="${args[--cluster]}"
  if [[ -z "$mdc_cluster" ]]
  then
    mdc_cluster="$PLAYGROUND_CLUSTER"
  fi
  if [[ -z "$mdc_cluster" ]]
  then
    mdc_cluster=$(playground state get run.cluster 2> /dev/null)
  fi
  if [[ -z "$mdc_cluster" ]]
  then
    # on stderr: also visible when the command runs in $(...), like the nested 'playground get-connector-list'
    logerror "❌ $environment runs two clusters: pass --cluster us|europe, or set it for the session with 'export PLAYGROUND_CLUSTER=us' or 'playground state set run.cluster us'" >&2
    exit 1
  fi
  if [[ "$mdc_cluster" != "us" ]] && [[ "$mdc_cluster" != "europe" ]]
  then
    logerror "❌ cluster should be us or europe (it is $mdc_cluster)" >&2
    exit 1
  fi
  export PLAYGROUND_CLUSTER="$mdc_cluster"
}

# Kafka client of the selected cluster of an mdc-* environment: sets $container (where to run the kafka-* tool),
# $bootstrap_server, $security ("<config option> <client properties file>", empty in mdc-plaintext) and $sr_url_cli.
# Usage: get_mdc_client <config option, e.g. --command-config> <command|producer|consumer>
# producer and consumer run in the connect worker (or the kerberos client), which has the avro/protobuf/json schema tools.
function get_mdc_client() {
  local config_option="$1"
  local role="${2:-command}"

  get_mdc_cluster
  bootstrap_server="broker-$mdc_cluster:9092"
  sr_url_cli="http://schema-registry-$mdc_cluster:8081"
  broker_container="broker-$mdc_cluster"
  connect_container="connect-$mdc_cluster"
  container="broker-$mdc_cluster"
  if [[ "$role" != "command" ]]
  then
    container="connect-$mdc_cluster"
  fi
  security=""

  case "$environment" in
    mdc-sasl-plain)
      # environment/mdc-sasl-plain/client/client.properties, user client
      security="$config_option /tmp/client.properties"
      ;;
    mdc-kerberos)
      # the GSSAPI client builds the broker principal from the bootstrap host: use the FQDN
      container="client"
      bootstrap_server="broker-$mdc_cluster.kerberos-demo.local:9092"
      security="$config_option /etc/kafka/$role-$mdc_cluster.properties"
      docker exec -i client kinit -k -t /var/lib/secret/kafka-connect.key connect
      ;;
  esac
}

# " --cluster <cluster>" in an mdc-* environment (empty otherwise): for the commands printed as next steps
function mdc_cluster_flag() {
  if is_mdc_environment
  then
    get_mdc_cluster
    echo " --cluster $mdc_cluster"
  fi
}

function is_mdc_environment() {
  if [[ -z "$environment" ]]
  then
    get_environment_used
  fi
  [[ "$environment" == mdc* ]]
}

function resolve_container_name_for_environment() {
  local requested_name="$1"
  local mapped_name=""
  local prefixed_pod=""

  if [[ -z "$environment" ]]
  then
    get_environment_used
  fi

  if [[ "$environment" != cfk* ]]
  then
    echo "$requested_name"
    return
  fi

  # Allow direct pod names first.
  if kubectl -n confluent get pod "$requested_name" >/dev/null 2>&1
  then
    echo "$requested_name"
    return
  fi

  # Most CFK components are statefulsets ending with -0.
  if kubectl -n confluent get pod "${requested_name}-0" >/dev/null 2>&1
  then
    echo "${requested_name}-0"
    return
  fi

  # Try common deployment/statefulset prefix match.
  prefixed_pod=$(kubectl -n confluent get pods -o name 2>/dev/null | sed 's#pod/##' | grep "^${requested_name}-" | head -1)
  if [[ -n "$prefixed_pod" ]]
  then
    echo "$prefixed_pod"
    return
  fi

  # Map common docker-style component names to CFK pod names.
  case "$requested_name" in
    connect)
      mapped_name="connect-0"
      ;;
    broker|kafka)
      mapped_name="kafka-0"
      ;;
    controller)
      mapped_name="kraftcontroller-0"
      ;;
    controller2)
      mapped_name="kraftcontroller-1"
      ;;
    controller3)
      mapped_name="kraftcontroller-2"
      ;;
    zookeeper2)
      mapped_name="zookeeper-1"
      ;;
    zookeeper3)
      mapped_name="zookeeper-2"
      ;;
    schema-registry|schemaregistry)
      mapped_name="schemaregistry-0"
      ;;
    control-center|controlcenter)
      mapped_name="controlcenter-0"
      ;;
    *)
      mapped_name="$requested_name"
      ;;
  esac

  echo "$mapped_name"
}

#
# Network tools (iptables, tc, ping) run from this image, in the network namespace of the
# target container or pod: nothing has to be installed in the target, whatever its image
#
PLAYGROUND_NETSHOOT_IMAGE="nicolaka/netshoot"

# run a command in an ephemeral netshoot container of a cfk pod (same network namespace),
# as root with the sysadmin profile (NET_ADMIN). Prints the output when $3 is true.
function run_cfk_netshoot_command() {
  local pod_name=$1
  local cmd=$2
  local emit_output=${3:-false}
  local target_container
  local debug_output
  local cleaned_output
  local debug_exit_code
  local debug_custom_file

  target_container=$(kubectl -n confluent get pod "$pod_name" -o jsonpath='{.spec.containers[0].name}' 2>/dev/null)
  if [[ -z "$target_container" ]]
  then
    logerror "❌ Could not resolve target container for pod $pod_name"
    exit 1
  fi

  debug_custom_file=$(mktemp -t pg-cfk-netshoot-XXXXXXXXXX.yaml)
  cat << EOF > "$debug_custom_file"
securityContext:
  runAsUser: 0
  runAsNonRoot: false
EOF

  # --attach waits for the command to finish and returns its output, otherwise the rule is applied asynchronously
  set +e
  debug_output=$(kubectl -n confluent debug "pod/$pod_name" --attach=true --profile=sysadmin --custom="$debug_custom_file" --image=$PLAYGROUND_NETSHOOT_IMAGE --target="$target_container" -- bash -lc "$cmd" 2>&1)
  debug_exit_code=$?
  set -e
  rm -f "$debug_custom_file"
  cleaned_output=$(echo "$debug_output" | sed -E '/^Targeting container /d; /^Defaulting debug container name to /d')
  if [ $debug_exit_code -ne 0 ]
  then
    logerror "❌ failed to execute command on pod $pod_name"
    if [[ -n "$cleaned_output" ]]
    then
      echo "$cleaned_output"
    else
      echo "$debug_output"
    fi
    exit 1
  fi

  if [[ "$emit_output" == "true" ]]
  then
    if [[ -n "$cleaned_output" ]]
    then
      echo "$cleaned_output"
    else
      log "(no output from: $cmd)"
    fi
  fi
}

# run a command in the network namespace of a container (docker, podman) or pod (cfk), with
# NET_ADMIN, and print its output. The changes it makes (tc, iptables) stay after it exits.
function run_in_network_namespace() {
  local container=$1
  local cmd=$2

  if [[ -z "$environment" ]]
  then
    get_environment_used
  fi

  if [[ "$environment" == cfk* ]]
  then
    run_cfk_netshoot_command "$container" "$cmd" "true"
    return
  fi

  if ! docker image inspect $PLAYGROUND_NETSHOOT_IMAGE > /dev/null 2>&1
  then
    log "📥 pulling $PLAYGROUND_NETSHOOT_IMAGE (network tools image, only the first time)"
    docker pull $PLAYGROUND_NETSHOOT_IMAGE > /dev/null
  fi
  docker run --rm --network "container:$container" --cap-add NET_ADMIN --cap-add NET_RAW $PLAYGROUND_NETSHOOT_IMAGE sh -c "$cmd"
}

# ip addresses of a destination (ip, container, pod, service or hostname), one per line
function resolve_traffic_destination_ips() {
  local destination=$1
  local ip_pattern="^([0-9]{1,3}\.){3}[0-9]{1,3}$"
  local ip_address=""

  if [[ -z "$environment" ]]
  then
    get_environment_used
  fi

  if [[ $destination =~ $ip_pattern ]]
  then
    echo "$destination"
    return
  fi

  if [[ "$environment" == cfk* ]]
  then
    ip_address=$(kubectl -n confluent get pod "$destination" -o jsonpath='{.status.podIP}' 2>/dev/null)
    if [[ -z "$ip_address" ]]
    then
      ip_address=$(kubectl -n confluent get svc "$destination" -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
      if [[ "$ip_address" == "None" || "$ip_address" == "none" ]]
      then
        ip_address=""
      fi
    fi
  else
    ip_address=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' "$destination" 2>/dev/null | awk '{ print $1 }')
  fi
  if [[ -n "$ip_address" ]]
  then
    echo "$ip_address"
    return
  fi

  log "🌐 Using nslookup to get IP address of $destination..." >&2
  if [[ "$environment" == cfk* ]]
  then
    local endpoint_ips
    endpoint_ips=$(kubectl -n confluent get endpoints "$destination" -o jsonpath='{range .subsets[*].addresses[*]}{.ip}{"\n"}{end}' 2>/dev/null | grep -E "$ip_pattern" | sort -u || true)
    if [[ -n "$endpoint_ips" ]]
    then
      echo "$endpoint_ips"
      return
    fi
  fi
  nslookup "$destination" 2>/dev/null | awk '/^Address: / { print $2 }' | grep -E "$ip_pattern" | sort -u || true
}

function is_container_running() {
  container_name=$1
  docker inspect -f '{{.State.Running}}' "$container_name" 2>/dev/null | grep -q "true"
}

function get_connect_container() {
  if is_mdc_environment
  then
    get_mdc_cluster
    connect_container="connect-$mdc_cluster"
    return
  fi
  for worker in connect connect2 connect3
  do
    if is_container_running $worker
    then
      connect_container=$worker
      break
    fi
  done
}

function is_multiple_connect_workers_running() {
  if is_container_running "connect2" || is_container_running "connect3"
  then
    return 0
  else
    return 1
  fi
}

function get_connect_url_and_security() {
  get_environment_used

  if [[ "$environment" == cfk* ]]
  then
      # CFK Connect is accessed through local port-forwards.
      # Prefer existing forwards first, then auto-start one on 8083 if needed.
      connect_port="8083"
      connect_reachable=0
      for candidate_port in 8083 8283 8383
      do
        if curl -s "http://localhost:${candidate_port}" > /dev/null 2>&1
        then
          connect_port="$candidate_port"
          connect_reachable=1
          break
        fi
      done

      if [[ "$connect_reachable" != "1" ]]
      then
        cfk_pf_running=$(ps -axo command= | grep -E '[k]ubectl( |.* )-n confluent( |.* )port-forward (svc/)?connect ' | head -1)
        if [[ -z "$cfk_pf_running" ]]
        then
          log "🔀 Starting CFK port-forward for Connect on localhost:8083"
          kubectl -n confluent port-forward svc/connect 8083:8083 > /tmp/playground-cfk-connect-port-forward.log 2>&1 &
        fi

        for _ in 1 2 3 4 5
        do
          if curl -s "http://localhost:8083" > /dev/null 2>&1
          then
            connect_reachable=1
            connect_port="8083"
            break
          fi
          sleep 1
        done

        if [[ "$connect_reachable" != "1" ]]
        then
          # The existing port-forward process (if any) is stale — kill it and start a
          # fresh one before giving up.  A broken background forward stays in ps,
          # which would otherwise block a subsequent call from starting a new one.
          pkill -f 'kubectl.*-n confluent.*port-forward.*connect' 2>/dev/null || true
          sleep 1
          log "🔀 Restarting CFK port-forward for Connect on localhost:8083"
          kubectl -n confluent port-forward svc/connect 8083:8083 > /tmp/playground-cfk-connect-port-forward.log 2>&1 &
          for _ in 1 2 3 4 5
          do
            if curl -s "http://localhost:8083" > /dev/null 2>&1
            then
              connect_reachable=1
              connect_port="8083"
              break
            fi
            sleep 1
          done
        fi
      fi

      connect_url="http://localhost:$connect_port"
      security=""
      if [[ "$environment" == "cfk-rbac" ]]
      then
          security="-u connectorSubmitter:connectorSubmitter"
      fi

      if [[ "$connect_reachable" != "1" ]]
      then
        logwarn "⚠️ Could not reach CFK Connect REST API on localhost (tried 8083/8283/8383)"
      fi
      return
  fi

  connect_port="8083"

  if [[ "$environment" == mdc* ]]
  then
    # connect-us publishes its REST API on 8083, connect-europe on 8283
    get_mdc_cluster
    if [[ "$mdc_cluster" == "europe" ]]
    then
      connect_port="8283"
    fi
    connect_url="http://localhost:$connect_port"
    security=""
    return
  fi

  if ! is_container_running "connect"
  then
    if is_container_running "connect2"
    then
      connect_port="8283"
      # log "💫 using connect rest api for connect2 as connect rest api on port 8083 is not available"
    elif is_container_running "connect3"
    then
      connect_port="8383"
      # log "💫 using connect rest api for connect3 as connect rest api on port 8083 and connect2 rest api on port 8283 are not available"
    else
      # Fallback for CFK-like runs where connect is not a local docker container.
      for candidate_port in 8083 8283 8383
      do
        if curl -s "http://localhost:${candidate_port}" > /dev/null 2>&1
        then
          connect_port="$candidate_port"
          break
        fi
      done

      if [[ "$connect_port" == "8083" ]] && ! curl -s "http://localhost:8083" > /dev/null 2>&1
      then
        if verify_installed "kubectl" >/dev/null 2>&1 && kubectl -n confluent get svc connect >/dev/null 2>&1
        then
          cfk_pf_running=$(ps -axo command= | grep -E '[k]ubectl( |.* )-n confluent( |.* )port-forward (svc/)?connect ' | head -1)
          if [[ -z "$cfk_pf_running" ]]
          then
            log "🔀 Starting fallback CFK port-forward for Connect on localhost:8083"
            kubectl -n confluent port-forward svc/connect 8083:8083 > /tmp/playground-cfk-connect-port-forward.log 2>&1 &
          fi

          for _ in 1 2 3 4 5
          do
            if curl -s "http://localhost:8083" > /dev/null 2>&1
            then
              connect_port="8083"
              break
            fi
            sleep 1
          done
        fi
      fi

      if ! curl -s "http://localhost:${connect_port}" > /dev/null 2>&1
      then
        logerror "❌ No available port found for connect rest api, none of containers connect, connect2 or connect3 are running!"
        exit 1
      fi
    fi
  fi

  connect_url="http://localhost:$connect_port"

  security=""
  if [[ "$environment" == "sasl-ssl" ]] || [[ "$environment" == "2way-ssl" ]]
  then
      connect_url="https://localhost:$connect_port"
      DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

      security="--cert $DIR_CLI/../../environment/$environment/security/connect.certificate.pem --key $DIR_CLI/../../environment/$environment/security/connect.key --tlsv1.2 --cacert $DIR_CLI/../../environment/$environment/security/snakeoil-ca-1.crt"
  elif [[ "$environment" == "rbac-sasl-plain" ]]
  then
      DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

      security="-u connectorSubmitter:connectorSubmitter"
  elif [[ "$environment" == "rbac-oauth" ]]
  then
      # bearer token of the Keycloak client superuser (SystemAdmin on the connect cluster)
      security="--oauth2-bearer $(get_rbac_oauth_token superuser)"
  fi
}

# consumer group of a sink connector: connect-<lcc id> for a fully managed or custom connector, otherwise
# consumer.override.group.id of its config, or connect-<connector>. Sets consumer_group, and consumer_group_override=1
# when the group comes from consumer.override.group.id. Calls get_connect_url_and_security, which sets $security for
# the connect REST API: save the broker $security of get_security_broker before calling it.
function get_connector_consumer_group () {
  local connector="$1" type override
  type=$(playground state get run.connector_type)
  consumer_group_override=""
  if [ "$type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$type" == "$CONNECTOR_TYPE_CUSTOM" ]
  then
    consumer_group="connect-$(get_ccloud_connector_lcc "$connector" || true)"
    return 0
  fi
  consumer_group="connect-$connector"
  get_connect_url_and_security
  if handle_onprem_connect_rest_api "curl -s $security \"$connect_url/connectors/$connector/config\"" > /dev/null 2>&1
  then
    override=$(echo "$curl_output" | jq -r '."consumer.override.group.id" // empty' 2> /dev/null)
    if [ -n "$override" ]
    then
      consumer_group="$override"
      consumer_group_override=1
    fi
  fi
  return 0
}

function generate_get_examples_add_emoji () {
  repro=""
  if [[ $file_path == *"reproduction-models"* ]]
  then
    repro="🛠"
  fi

  if [[ $file_path == *"ccloud"* ]]
  then
    if [[ $file_path == *"fm-"* ]]
    then
      echo "${repro}🌤️🤖 $file_path" >> $output_file
    elif [[ $file_path == *"custom-connector"* ]]
    then
      echo "${repro}🌤️🛃 $file_path" >> $output_file
    elif [[ $file_path == *"environment"* ]]
    then
      echo "${repro}🌤️🔐 $file_path" >> $output_file
    else
      echo "${repro}🌤️ $file_path" >> $output_file
    fi
  elif [[ $file_path == *"connect"* ]]
  then
    if [[ $file_path == *"sink"* ]]
    then
      echo "${repro}🔗🌎🔹 $file_path" >> $output_file
    elif [[ $file_path == *"source"* ]]
    then
      echo "${repro}🔗🌎🔻 $file_path" >> $output_file
    else
      echo "${repro}🔗🌎 $file_path" >> $output_file
    fi
  elif [[ $file_path == *"ksql"* ]]
  then
    echo "${repro}🎏 $file_path" >> $output_file
  elif [[ $file_path == *"schema-registry"* ]]
  then
    echo "${repro}🔰 $file_path" >> $output_file
  elif [[ $file_path == *"rest-proxy"* ]]
  then
    echo "${repro}😴 $file_path" >> $output_file
  elif [[ $file_path == *"environment"* ]]
  then
    echo "${repro}🔐 $file_path" >> $output_file
  else
    echo "${repro}👾 $file_path" >> $output_file
  fi
}

function generate_fzf_find_files() {
  generate_get_examples_list_with_fzf_without_repro_sink_only
  generate_get_examples_list_with_fzf_without_repro
  generate_get_examples_list_with_fzf_ccloud_only
  generate_get_examples_list_with_fzf

  generate_get_examples_list_with_fzf_connector_only
  generate_get_examples_list_with_fzf_repro_only
  generate_get_examples_list_with_fzf_environemnt_only
  generate_get_examples_list_with_fzf_ksql_only
  generate_get_examples_list_with_fzf_fully_managed_connector_only
  generate_get_examples_list_with_fzf_schema_registry_only
  generate_get_examples_list_with_fzf_rest_proxy_only
  generate_get_examples_list_with_fzf_academy_only
  generate_get_examples_list_with_fzf_other_playgrounds_only
}

function generate_get_examples_list_with_fzf_connector_only () {
  output_file="$root_folder/scripts/cli/get_examples_list_with_fzf_connector_only"
  rm -f $output_file
  find $root_folder -name \*.sh ! -name 'stop.sh' -path '*/connect/connect-*/*' ! -path '*/scripts/*' ! -path '*/security/*' ! -path '*/reproduction-models/*' ! -path '*/ccloud/*'  | while read file_path
  do
    if grep -q "scripts/utils.sh" "$file_path"; then
      generate_get_examples_add_emoji
    fi
  done
  sort -o $output_file $output_file
}

function generate_get_examples_list_with_fzf_repro_only () {
  output_file="$root_folder/scripts/cli/get_examples_list_with_fzf_repro_only"
  rm -f $output_file
  find $root_folder -name \*.sh ! -name 'stop.sh' ! -path '*/scripts/*'  ! -path '*/security/*' -path '*/reproduction-models/*' | while read file_path
  do
    if grep -q "scripts/utils.sh" "$file_path"; then
      generate_get_examples_add_emoji
    fi
  done
  if [ -s "$output_file" ]; then
    sort -o $output_file $output_file
  fi
}

function generate_get_examples_list_with_fzf_environemnt_only () {
  output_file="$root_folder/scripts/cli/get_examples_list_with_fzf_environment_only"
  rm -f $output_file
  find $root_folder -name \*.sh ! -name 'update_run.sh' ! -name 'stop.sh' ! -path '*/scripts/*' ! -path '*/security/*' -path '*/environment/*' | while read file_path
  do
    if grep -q "scripts/utils.sh" "$file_path"; then
      generate_get_examples_add_emoji
    fi
  done
  if [ -s "$output_file" ]; then
    sort -o $output_file $output_file
  fi
}

function generate_get_examples_list_with_fzf_ksql_only () {
  output_file="$root_folder/scripts/cli/get_examples_list_with_fzf_ksql_only"
  rm -f $output_file
  find $root_folder -name \*.sh ! -name 'stop.sh' -path '*/ksqldb/*' ! -path '*/scripts/*' ! -path '*/security/*' ! -path '*/reproduction-models/*'  ! -path '*/ccloud/*' | while read file_path
  do
    if grep -q "scripts/utils.sh" "$file_path"; then
      generate_get_examples_add_emoji
    fi
  done
  if [ -s "$output_file" ]; then
    sort -o $output_file $output_file
  fi
}

function generate_get_examples_list_with_fzf_fully_managed_connector_only () {
  output_file="$root_folder/scripts/cli/get_examples_list_with_fzf_fully_managed_connector_only"
  rm -f $output_file
  find $root_folder -name \*.sh ! -name 'stop.sh' -path '*/fm-*/*' ! -path '*/scripts/*' ! -path '*/security/*' ! -path '*/reproduction-models/*' -path '*/ccloud/*' | while read file_path
  do
    if grep -q "scripts/utils.sh" "$file_path"; then
      generate_get_examples_add_emoji
    fi
  done
  if [ -s "$output_file" ]; then
    sort -o $output_file $output_file
  fi
}

function generate_get_examples_list_with_fzf_schema_registry_only () {
  output_file="$root_folder/scripts/cli/get_examples_list_with_fzf_schema_registry_only"
  rm -f $output_file
  find $root_folder -name \*.sh ! -name 'stop.sh' -path '*/schema-registry/*' ! -path '*/scripts/*' ! -path '*/security/*' ! -path '*/reproduction-models/*' ! -path '*/ccloud/*' | while read file_path
  do
    if grep -q "scripts/utils.sh" "$file_path"; then
      generate_get_examples_add_emoji
    fi
  done
  if [ -s "$output_file" ]; then
    sort -o $output_file $output_file
  fi
}

function generate_get_examples_list_with_fzf_rest_proxy_only () {
  output_file="$root_folder/scripts/cli/get_examples_list_with_fzf_rest_proxy_only"
  rm -f $output_file
  find $root_folder -name \*.sh ! -name 'stop.sh' -path '*/rest-proxy/*' ! -path '*/scripts/*' ! -path '*/security/*' ! -path '*/reproduction-models/*'  ! -path '*/ccloud/*' | while read file_path
  do
    if grep -q "scripts/utils.sh" "$file_path"; then
      generate_get_examples_add_emoji
    fi
  done
  if [ -s "$output_file" ]; then
    sort -o $output_file $output_file
  fi
}

function generate_get_examples_list_with_fzf_academy_only () {
  output_file="$root_folder/scripts/cli/get_examples_list_with_fzf_academy_only"
  rm -f $output_file
  find $root_folder -name \*.sh ! -name 'stop.sh' -path '*/academy/*' ! -path '*/scripts/*' ! -path '*/security/*' ! -path '*/reproduction-models/*'  ! -path '*/ccloud/*' | while read file_path
  do
    if grep -q "scripts/utils.sh" "$file_path"; then
      generate_get_examples_add_emoji
    fi
  done
  if [ -s "$output_file" ]; then
    sort -o $output_file $output_file
  fi
}

function generate_get_examples_list_with_fzf_other_playgrounds_only () {
  output_file="$root_folder/scripts/cli/get_examples_list_with_fzf_other_playgrounds_only"
  rm -f $output_file
  find $root_folder -name \*.sh ! -name 'stop.sh' ! -path '*/scripts/*'  ! -path '*/security/*' ! -path '*/reproduction-models/*'  ! -path '*/ccloud/*' ! -path '*/reproduction-models/*' ! -path '*/connect/*' ! -path '*/ksqldb/*' ! -path '*/schema-registry/*'  | while read file_path
  do
    if grep -q "scripts/utils.sh" "$file_path"; then
      generate_get_examples_add_emoji
    fi
  done
  if [ -s "$output_file" ]; then
    sort -o $output_file $output_file
  fi
}


function generate_get_examples_list_with_fzf_without_repro_sink_only () {
  output_file="$root_folder/scripts/cli/get_examples_list_with_fzf_without_repro_sink_only"
  rm -f $output_file
  find $root_folder -name \*.sh ! -name 'stop.sh' -path '*/connect-*-sink/*' ! -path '*/scripts/*'  ! -path '*/other/*' ! -path '*/ccloud/*'  ! -path '*/academy/*' ! -path '*/security/*' ! -path '*/reproduction-models/*' | while read file_path
  do
    if grep -q "scripts/utils.sh" "$file_path"; then
      generate_get_examples_add_emoji
    fi
  done
  if [ -s "$output_file" ]; then
    sort -o $output_file $output_file
  fi
}

function generate_get_examples_list_with_fzf_without_repro () {
  output_file="$root_folder/scripts/cli/get_examples_list_with_fzf_without_repro"
  rm -f $output_file
  find $root_folder -name \*.sh ! -name 'stop.sh' ! -path '*/scripts/*'  ! -path '*/security/*' ! -path '*/reproduction-models/*' | while read file_path
  do
    if grep -q "scripts/utils.sh" "$file_path"; then
      generate_get_examples_add_emoji
    fi
  done
  if [ -s "$output_file" ]; then
    sort -o $output_file $output_file
  fi
}

function generate_get_examples_list_with_fzf_ccloud_only () {
  output_file="$root_folder/scripts/cli/get_examples_list_with_fzf_ccloud_only"
  rm -f $output_file
  find $root_folder -name \*.sh ! -name 'stop.sh' -path '*/ccloud*' ! -path '*/security/*' | while read file_path
  do
    if grep -q "scripts/utils.sh" "$file_path"; then
      generate_get_examples_add_emoji
    fi
  done
  if [ -s "$output_file" ]; then
    sort -o $output_file $output_file
  fi
}

function generate_get_examples_list_with_fzf () {
  output_file="$root_folder/scripts/cli/get_examples_list_with_fzf_all"
  rm -f $output_file
  find $root_folder -name \*.sh ! -name 'stop.sh' ! -path '*/scripts/*' ! -path '*/security/*' | while read file_path
  do
    if grep -q "scripts/utils.sh" "$file_path"; then
      generate_get_examples_add_emoji
    fi
  done
  if [ -s "$output_file" ]; then
    sort -o $output_file $output_file
  fi
}

function get_ccloud_connect() {
  get_kafka_docker_playground_dir

  if [ ! -f $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta ]
  then
      logerror "❌ $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta has not been generated"
      exit 1
  fi

  environment=$(grep "ENVIRONMENT ID" $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta | cut -d " " -f 4)
  cluster=$(grep "KAFKA CLUSTER ID" $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta | cut -d " " -f 5)

  load_secrets_env_vars CONFLUENT_CLOUD_API_KEY CONFLUENT_CLOUD_API_SECRET

  if [ -z $CONFLUENT_CLOUD_API_KEY ]
  then
    logerror "❌ environment variable CONFLUENT_CLOUD_API_KEY should be set to use $CONNECTOR_TYPE_FULLY_MANAGED or $CONNECTOR_TYPE_CUSTOM connector"
    logerror "Set it with Cloud API key, see https://docs.confluent.io/cloud/current/access-management/authenticate/api-keys/api-keys.html#cloud-cloud-api-keys"
    exit 1
  fi

  if [ -z $CONFLUENT_CLOUD_API_SECRET ]
  then
    logerror "❌ environment variable CONFLUENT_CLOUD_API_SECRET should be set to use $CONNECTOR_TYPE_FULLY_MANAGED or $CONNECTOR_TYPE_CUSTOM connector"
    logerror "Set it with Cloud API secret, see https://docs.confluent.io/cloud/current/access-management/authenticate/api-keys/api-keys.html#cloud-cloud-api-keys"
    exit 1
  fi
  
  authorization=$(echo -n "$CONFLUENT_CLOUD_API_KEY:$CONFLUENT_CLOUD_API_SECRET" | base64)
}

function get_sr_url_and_security() {
  get_environment_used


  sr_url="http://localhost:8081"
  sr_security=""

  if [[ "$environment" == mdc* ]]
  then
      # schema-registry-us is published on 28081, schema-registry-europe on 18081
      get_mdc_cluster
      sr_url="http://localhost:28081"
      if [[ "$mdc_cluster" == "europe" ]]
      then
        sr_url="http://localhost:18081"
      fi
  elif [[ "$environment" == "sasl-ssl" ]] || [[ "$environment" == "2way-ssl" ]]
  then
      sr_url="https://localhost:8081"
      DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

      sr_security="--cert $DIR_CLI/../../environment/$environment/security/schema-registry.certificate.pem --key $DIR_CLI/../../environment/$environment/security/schema-registry.key --tlsv1.2 --cacert $DIR_CLI/../../environment/$environment/security/snakeoil-ca-1.crt"
  elif [[ "$environment" == "rbac-sasl-plain" ]] || [[ "$environment" == "cfk-rbac" ]]
  then
      DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

      sr_security="-u superUser:superUser"
  elif [[ "$environment" == "rbac-oauth" ]]
  then
      # bearer token of the Keycloak client superuser (SystemAdmin on the schema registry cluster)
      sr_security="--oauth2-bearer $(get_rbac_oauth_token superuser)"
    elif [[ "$environment" == cfk* ]]
    then
        # CFK Schema Registry is exposed as a Kubernetes service.
        # Commands executed from the local machine should use a local port-forward.
        sr_url="http://localhost:8081"
        sr_security=""
  elif [[ "$environment" == "ccloud" ]]
  then
    if [[ ! -n "$root_folder" ]]
    then
      # can happen in filter function where before hook is not called
      DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
      dir1=$(echo ${DIR_CLI%/*})
      root_folder=$(echo ${dir1%/*})
    fi
    if [ -f $root_folder/.ccloud/env.delta ]
    then
        source $root_folder/.ccloud/env.delta
    else
        logerror "❌ $root_folder/.ccloud/env.delta has not been generated"
        exit 1
    fi
    sr_url=$SCHEMA_REGISTRY_URL
    sr_security="-u $SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO"
  fi

  # --context of the schema commands: every call goes to /contexts/<context>/… (contexts start with a dot)
  if [[ -n "${args[--context]}" ]] && [ "${args[--context]}" != "." ]
  then
    sr_context="${args[--context]}"
    [[ "$sr_context" != .* ]] && sr_context=".${sr_context}"
    sr_url="${sr_url}/contexts/${sr_context}"
  fi
}

# sr_request <method> <path> [<json body>]: one call to the Schema Registry of the running environment
# (get_sr_url_and_security must have been called). Sets:
#   sr_response       the body
#   sr_error_code     the registry's error_code (40401, 40408…), "curl" when curl failed, empty on success
#   sr_error_message  the registry's message
# returns 0 on success, 1 otherwise. Prints the curl command when $verbose is set.
function sr_request() {
  local method="$1"
  local path="$2"
  local data="$3"
  local ret
  sr_response=""
  sr_error_code=""
  sr_error_message=""
  if [[ -n "$verbose" ]]
  then
    log "🐞 curl command used"
    if [ -n "$data" ]
    then
      echo "curl $sr_security -s -X $method -H \"Content-Type: application/vnd.schemaregistry.v1+json\" --data '$data' \"${sr_url}${path}\""
    else
      echo "curl $sr_security -s -X $method \"${sr_url}${path}\""
    fi
  fi
  if [ -n "$data" ]
  then
    sr_response=$(curl $sr_security -s -X "$method" -H "Content-Type: application/vnd.schemaregistry.v1+json" --data "$data" "${sr_url}${path}")
  else
    sr_response=$(curl $sr_security -s -X "$method" "${sr_url}${path}")
  fi
  ret=$?
  if [ $ret -ne 0 ]
  then
    sr_error_code="curl"
    sr_error_message="curl request to ${sr_url}${path} failed with error code $ret"
    return 1
  fi
  sr_error_code=$(echo "$sr_response" | jq -r 'if type == "object" and has("error_code") then .error_code else empty end' 2> /dev/null)
  if [ -n "$sr_error_code" ]
  then
    sr_error_message=$(echo "$sr_response" | jq -r '.message // empty' 2> /dev/null)
    return 1
  fi
  return 0
}

# sr_exit_on_error [<context>]: after a failed sr_request, print the registry's error and exit 1
function sr_exit_on_error() {
  local context="$1"
  if [ "$sr_error_code" == "curl" ]
  then
    logerror "❌ $sr_error_message"
  else
    logerror "❌ ${context:+$context: }Command failed with error code $sr_error_code"
    logerror "$sr_error_message"
  fi
  exit 1
}

# sr_read_schema_arg <schema argument> <destination file>: the --schema value of the schema commands to a file:
# "-" reads stdin, "@file" or an existing path is copied, anything else is the schema itself
function sr_read_schema_arg() {
  local schema="$1"
  local dest="$2"
  if [ "$schema" = "-" ]
  then
    cat > "$dest"
  elif [[ $schema == @* ]]
  then
    cp "${schema#@}" "$dest" || return 1
  elif [ -f "$schema" ]
  then
    cp "$schema" "$dest" || return 1
  else
    echo "$schema" > "$dest"
  fi
  if [ ! -s "$dest" ]
  then
    logerror "❌ the schema is empty"
    return 1
  fi
}

# sr_detect_schema_type <file>: sets sr_schema_type to AVRO, JSON or PROTOBUF ("REQUEST" when the file is already a
# full request body with "references"), returns 1 when no known schema could be identified
function sr_detect_schema_type() {
  local schema_file="$1"
  sr_schema_type=""
  if grep -q "\"references\"\s*:" "$schema_file"
  then
    sr_schema_type=REQUEST
  elif grep -q "proto3\|proto2" "$schema_file"
  then
    sr_schema_type=PROTOBUF
  elif grep -q "\"type\"\s*:\s*\"object\"" "$schema_file" || grep -q "\"\\\$schema\"\s*:" "$schema_file"
  then
    sr_schema_type=JSON
  elif grep -q "\"type\"\s*:\s*\"record\"" "$schema_file"
  then
    sr_schema_type=AVRO
  elif grep -xq "\s*\"[a-z]*\"\s*" "$schema_file" || { grep -qE "\"type\"\s*:\s*\"(enum|array|map|fixed|string|bytes|int|long|float|double|boolean|null)\"" "$schema_file" && ! grep -qE "\"\\\$schema\"|\"properties\"" "$schema_file"; }
  then
    # the other avro schemas: a primitive alone ("string") or an enum, array, map, fixed or primitive type
    sr_schema_type=AVRO
  else
    return 1
  fi
}

# sr_schema_request_body <file>: the body of a register / compatibility request for the schema in <file>
# (detects the type, wraps the schema in {"schemaType", "schema"}; a full request with "references" is sent as is).
# Sets sr_schema_type and sr_body, returns 1 when the schema type can't be identified.
function sr_schema_request_body() {
  local schema_file="$1"
  local content
  sr_body=""
  sr_detect_schema_type "$schema_file" || return 1
  if [ "$sr_schema_type" == "REQUEST" ]
  then
    sr_body=$(cat "$schema_file" | tr -d '\n' | tr -s ' ')
    sr_schema_type=$(echo "$sr_body" | jq -r '.schemaType // "AVRO"' 2> /dev/null)
    return 0
  fi
  content=$(cat "$schema_file" | tr -d '\n' | tr -s ' ')
  sr_body=$(jq -cn --arg t "$sr_schema_type" --arg content "$content" '{schemaType: $t, schema: $content}')
}

# sr_compatibility_verdicts <from request body> <to request body> <result file>: asks the registry whether <to> can
# follow <from> under BACKWARD, FORWARD and FULL, in a temporary subject (registered then permanently deleted:
# <from> gets a new schema id if it isn't registered yet). Writes {"BACKWARD": {"compatible": …, "messages": […]}, …}.
# returns 1 when the registry refused the temporary subject (READONLY / IMPORT mode, invalid schema…)
function sr_compatibility_verdicts() {
  local from_body="$1"
  local to_body="$2"
  local result_file="$3"
  local tmp_subject="playground-schema-check-$$-$RANDOM"
  local rule
  local ret=0
  echo "{}" > "$result_file"
  if ! sr_request POST "/subjects/${tmp_subject}/versions" "$from_body"
  then
    logwarn "❌ can't register the temporary subject ${tmp_subject} for the verdicts: $sr_error_code $sr_error_message"
    return 1
  fi
  for rule in BACKWARD FORWARD FULL
  do
    sr_request PUT "/config/${tmp_subject}" "{\"compatibility\": \"$rule\"}" || { ret=1; break; }
    if sr_request POST "/compatibility/subjects/${tmp_subject}/versions/latest?verbose=true" "$to_body"
    then
      jq --arg rule "$rule" --argjson r "$sr_response" '. + {($rule): {compatible: ($r.is_compatible // false), messages: ($r.messages // [])}}' "$result_file" > "${result_file}.tmp" && mv "${result_file}.tmp" "$result_file"
    else
      logwarn "❌ the registry refused the schema: $sr_error_code $sr_error_message"
      ret=1
      break
    fi
  done
  sr_request DELETE "/config/${tmp_subject}" > /dev/null || true
  sr_request DELETE "/subjects/${tmp_subject}" > /dev/null || true
  sr_request DELETE "/subjects/${tmp_subject}?permanent=true" > /dev/null || true
  return $ret
}

# sr_global_compatibility: sets sr_global_compatibility_value to the global compatibility rule: the one of the
# context with --context when it has one, else the one of the registry (BACKWARD when nothing answers)
function sr_global_compatibility() {
  local saved_url="$sr_url"
  sr_global_compatibility_value=""
  if sr_request GET "/config"
  then
    sr_global_compatibility_value=$(echo "$sr_response" | jq -r '.compatibilityLevel // .compatibility // empty')
  elif [[ -n "$sr_context" ]]
  then
    sr_url="${sr_url%/contexts/*}"
    sr_request GET "/config" && sr_global_compatibility_value=$(echo "$sr_response" | jq -r '.compatibilityLevel // .compatibility // empty')
    sr_url="$saved_url"
  fi
  sr_global_compatibility_value="${sr_global_compatibility_value:-BACKWARD}"
  return 0
}

# sr_exporter_check_available: Schema Linking needs the exporter extension in the registry; returns 1 with the
# settings to add when /exporters isn't there
function sr_exporter_check_available() {
  if sr_request GET "/exporters" && echo "$sr_response" | jq -e 'type == "array"' > /dev/null 2>&1
  then
    return 0
  fi
  logerror "❌ the Schema Registry at ${sr_url} has no exporter API (Schema Linking): it needs, in the source registry,"
  logerror "   resource.extension.class=io.confluent.schema.exporter.SchemaExporterResourceExtension"
  logerror "   kafkastore.update.handlers=io.confluent.schema.exporter.storage.SchemaExporterUpdateHandler"
  logerror "   password.encoder.secret=<secret>"
  logerror "   (SCHEMA_REGISTRY_RESOURCE_EXTENSION_CLASS, SCHEMA_REGISTRY_KAFKASTORE_UPDATE_HANDLERS and SCHEMA_REGISTRY_PASSWORD_ENCODER_SECRET with"
  logerror "   playground container set-environment-variables -c <schema registry container> --env \"…\"; other/deep-dive-labs/docker-compose.mdc-plaintext.replication.yml has them)"
  return 1
}

# sr_format_compatibility_messages <messages json array>: the reasons of a compatibility verdict, one per line
# ("READER_FIELD_MISSING_DEFAULT_VALUE: The field 'currency' … has no default value…"), without the oldSchema,
# oldSchemaVersion and validateFields entries the registry adds
function sr_format_compatibility_messages() {
  echo "$1" | jq -r '.[]
    | select((startswith("{oldSchema") or startswith("{validateFields")) | not)
    | (capture("errorType:\"(?<t>[^\"]+)\", description:\"(?<d>[^\"]*)\"")? // null) as $m
    | if $m then "   \($m.t): \($m.d)" else "   \(.)" end'
}

function get_broker_container() {
  if is_mdc_environment
  then
    get_mdc_cluster
    broker_container="broker-$mdc_cluster"
    return
  fi
  for broker in broker broker2 broker3
  do
    if is_container_running $broker
    then
      broker_container=$broker
      break
    fi
  done
}

# CP version of the running environment, from the image tag of the connect container,
# or of the broker when connect is disabled (other/filebeat-to-kafka, ...)
# On cfk the CP components are pods in k3d, not docker containers: read the connect-0 pod (or kafka-0) instead
function get_running_cp_tag() {
  local images
  local tag
  local running_environment
  running_environment=$(playground state get run.environment)
  if [[ "$running_environment" == cfk* ]]
  then
    tag=$(kubectl -n confluent get pod connect-0 -o jsonpath='{.spec.containers[?(@.name=="connect")].image}' 2>/dev/null | awk -F':' '{print $NF}')
    # a connect image rebuilt by 'playground container change-jdk' is tagged with a timestamp, not a CP version
    if [[ ! "$tag" =~ ^[0-9]+\.[0-9]+ ]]
    then
      tag=$(kubectl -n confluent get pod kafka-0 -o jsonpath='{.spec.containers[?(@.name=="kafka")].image}' 2>/dev/null | awk -F':' '{print $NF}')
    fi
    if [[ ! "$tag" =~ ^[0-9]+\.[0-9]+ ]]
    then
      tag=""
    fi
    echo "$tag"
    return
  fi
  images=$(docker ps --format '{{.Image}}')
  tag=$(echo "$images" | grep -E 'confluentinc/cp-.*-connect.*:' | head -1 | awk -F':' '{print $2}')
  if [ -z "$tag" ]
  then
    tag=$(echo "$images" | grep -E 'confluentinc/cp-(server|kafka):' | head -1 | awk -F':' '{print $2}')
  fi
  echo "$tag"
}

# kafka-* tools of the CLI run in connect-0 on cfk environments: on cfk-rbac they authenticate as admin
# with this file, mounted from the playground-client secret (environment/cfk-rbac/cfk-rbac.sh)
cfk_rbac_client_properties="/mnt/secrets/playground-client/client.properties"

function get_security_broker() {
  config_file_name="$1"
  get_environment_used

  if [[ "$environment" == cfk* ]]
  then
      container="connect-0"
      bootstrap_server="kafka:9071"
      security=""
      if [[ "$environment" == "cfk-rbac" ]]
      then
          security="$config_file_name $cfk_rbac_client_properties"
      fi
      return
  fi

  if [[ "$environment" == mdc* ]]
  then
      get_mdc_client "$config_file_name" command
      return
  fi

  get_broker_container
  container="$broker_container"
  bootstrap_server="$broker_container:9092"

  security=""
  if [[ "$environment" == "kerberos" ]] || [[ "$environment" == "ssl_kerberos" ]]
  then
      container="client"
      # the GSSAPI client builds the broker principal from the bootstrap host: a short
      # name only becomes the FQDN through Docker's reverse DNS, not podman's
      bootstrap_server="${broker_container}.kerberos-demo.local:9092"
      security="$config_file_name /etc/kafka/consumer.properties"

      docker exec -i client kinit -k -t /var/lib/secret/kafka-connect.key connect
  elif [ "$environment" == "ldap-authorizer-sasl-plain" ]
  then
      security="$config_file_name /service/kafka/users/kafka.properties"
  elif [ "$environment" == "ldap-sasl-plain" ] || [ "$environment" == "sasl-plain" ] || [ "$environment" == "sasl-scram" ] || [ "$environment" == "sasl-oauthbearer" ] || [ "$environment" == "rbac-oauth" ]
  then
      security="$config_file_name /tmp/client.properties"
  elif [[ "$environment" != *plaintext ]]
  then
      security="$config_file_name /etc/kafka/secrets/client_without_interceptors.config"
  fi
}

# Call the Confluent Cloud Stream Catalog REST API, served by the Schema Registry
# endpoint of the environment. Sets $curl_output, returns 1 on an HTTP error.
# Honors $verbose to print the command.
# Usage: handle_catalog_rest_api <method> <path> [json body]
function handle_catalog_rest_api() {
  method="$1"
  path="$2"
  body="$3"

  get_kafka_docker_playground_dir
  DELTA_CONFIGS_ENV=$KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/env.delta
  if [ -f $DELTA_CONFIGS_ENV ]
  then
    source $DELTA_CONFIGS_ENV
  else
    logerror "❌ $DELTA_CONFIGS_ENV has not been generated"
    exit 1
  fi

  if [[ -n "$verbose" ]]
  then
    log "🐞 curl command used"
    if [ -n "$body" ]
    then
      echo "curl -s -X $method -u \$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO -H \"Content-Type: application/json\" --data '$body' \"$SCHEMA_REGISTRY_URL$path\""
    else
      echo "curl -s -X $method -u \$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO \"$SCHEMA_REGISTRY_URL$path\""
    fi
  fi

  if [ -n "$body" ]
  then
    curl_output=$(curl -s -w '\n%{http_code}' -X $method -u "$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -H "Content-Type: application/json" --data "$body" "$SCHEMA_REGISTRY_URL$path")
  else
    curl_output=$(curl -s -w '\n%{http_code}' -X $method -u "$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" "$SCHEMA_REGISTRY_URL$path")
  fi
  http_code=$(echo "$curl_output" | tail -n1)
  curl_output=$(echo "$curl_output" | sed '$d')

  if [[ ! "$http_code" =~ ^2 ]]
  then
    message=$(echo "$curl_output" | jq -r '.message // .error_message // empty' 2>/dev/null || true)
    logerror "❌ Stream Catalog API returned HTTP $http_code: ${message:-$curl_output}"
    return 1
  fi
}

# Resolve the Stream Catalog qualified name (lsrc-xxx:lkc-xxx:topic) of a topic.
# Sets $qualified_name, returns 1 if the topic is not (yet) in the catalog.
function get_catalog_topic_qualified_name() {
  topic="$1"
  handle_catalog_rest_api GET "/catalog/v1/search/basic?types=kafka_topic&query=$topic&limit=100" || return 1
  qualified_name=$(echo "$curl_output" | jq -r --arg topic "$topic" '[.entities[]? | select(.typeName == "kafka_topic") | .attributes.qualifiedName | select(endswith(":" + $topic))][0] // empty')
  if [ -z "$qualified_name" ]
  then
    logerror "❌ topic $topic was not found in the Stream Catalog (a newly created topic can take a minute to show up)"
    return 1
  fi
}

# Run a kafka-* admin tool (kafka-consumer-groups, kafka-run-class ...) against
# the current environment: bootstrap server and security properties are added,
# and the tool runs in the broker/client container, the connect pod (cfk) or a
# throwaway connect image container (ccloud).
# Honors $verbose to print the command.
# Usage: run_kafka_admin_tool <tool> [args...]
# CP version of the kafka-* tools run by run_kafka_admin_tool: the image of the container they run in (the broker,
# the kerberos client, connect-us…), not the version of connect (--connect-tag can differ). It decides the class names
# and the options of the tools (GetOffsetShell moved to org.apache.kafka.tools in 7.7)
function get_admin_tool_cp_tag() {
  local tag=""
  get_environment_used
  if [[ "$environment" != "ccloud" ]] && [[ "$environment" != cfk* ]]
  then
    tag=$(get_security_broker "--command-config" > /dev/null 2>&1; docker inspect -f '{{.Config.Image}}' "$container" 2> /dev/null | awk -F ':' '{print $NF}')
  fi
  if [[ ! "$tag" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]
  then
    get_connect_image
    tag="$CP_CONNECT_TAG"
  fi
  echo "$tag"
}

# GetOffsetShell class for the CP version $1
function get_offset_shell_class() {
  if version_gt "$1" "7.6.99"
  then
    echo "org.apache.kafka.tools.GetOffsetShell"
  else
    echo "kafka.tools.GetOffsetShell"
  fi
}

# --verbose: prints "🐞 CLI command used" and the command $1 on the file descriptor opened by before.sh, so that it is
# shown even when the output of the tool is captured by the command
function log_verbose_command() {
  if [[ -n "$playground_verbose_fd" ]]
  then
    { log "🐞 CLI command used" ; echo "$1" ; } >&$playground_verbose_fd
  else
    log "🐞 CLI command used"
    echo "$1"
  fi
}

function run_kafka_admin_tool() {
  tool="$1"
  shift
  get_environment_used

  if [[ "$environment" == "ccloud" ]]
  then
    get_kafka_docker_playground_dir
    DELTA_CONFIGS_ENV=$KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/env.delta
    if [ -f $DELTA_CONFIGS_ENV ]
    then
      source $DELTA_CONFIGS_ENV
    else
      logerror "❌ $DELTA_CONFIGS_ENV has not been generated"
      exit 1
    fi
    if [ ! -f $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta ]
    then
      logerror "❌ $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta has not been generated"
      exit 1
    fi
    if [[ -n "$verbose" ]]
    then
      log_verbose_command "$tool $* --bootstrap-server $BOOTSTRAP_SERVERS --command-config /tmp/configuration/ccloud.properties"
    fi
    get_connect_image
    docker run --quiet --rm -v $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta:/tmp/configuration/ccloud.properties ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} $tool "$@" --bootstrap-server $BOOTSTRAP_SERVERS --command-config /tmp/configuration/ccloud.properties
  else
    get_security_broker "--command-config"
    if [[ -n "$verbose" ]]
    then
      log_verbose_command "$tool $* --bootstrap-server $bootstrap_server $security"
    fi
    if [[ "$environment" == cfk* ]]
    then
      kubectl -n confluent exec -i $container -- $tool "$@" --bootstrap-server $bootstrap_server $security
    else
      docker exec -i $container $tool "$@" --bootstrap-server $bootstrap_server $security
    fi
  fi
}

function get_fzf_version() {
    version=$(fzf --version | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" | cut -d " " -f 1)
    echo "$version"
}

function get_examples_list_with_fzf() {
  cur="$1"
  file="$2"

  fzf_version=$(get_fzf_version)
  if version_gt $fzf_version "0.38"
  then
    fzf_option_wrap="--preview-window=40%,wrap"
    fzf_option_pointer="--pointer=👉"
    fzf_option_rounded="--border=rounded"
  else
    fzf_option_wrap=""
    fzf_option_pointer=""
    fzf_option_rounded=""
  fi

  terminal_columns=$(tput cols)
  if [[ $terminal_columns -gt 180 ]]
  then
    if [[ $(type -f bat 2>&1) =~ "not found" ]]
    then
        res=$(cat $file | fzf -i --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🚀" --header="select example" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" --delimiter / --with-nth "1,-3,-2,-1" $fzf_option_wrap $fzf_option_pointer --preview 'cat /{2..}');echo "$cur@$(echo $res | cut -d ' ' -f 2)"
    else
      res=$(cat $file | fzf -i --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🚀" --header="select example" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" --delimiter / --with-nth "1,-3,-2,-1" $fzf_option_wrap $fzf_option_pointer --preview 'bat --style=plain --color=always --line-range :500 /{2..}');echo "$cur@$(echo $res | cut -d ' ' -f 2)"
    fi
  else
    res=$(cat $file | fzf -i --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🚀" --header="select example" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" --delimiter / --with-nth "1,-3,-2,-1" $fzf_option_wrap $fzf_option_pointer);echo "$cur@$(echo $res | cut -d ' ' -f 2)"
  fi
}

function get_zip_or_jar_with_fzf() {
  cur="$1"
  type="$2"

  fzf_version=$(get_fzf_version)
  if version_gt $fzf_version "0.38"
  then
    fzf_option_wrap="--preview-window=40%,wrap"
    fzf_option_pointer="--pointer=👉"
    fzf_option_rounded="--border=rounded"
  else
    fzf_option_wrap=""
    fzf_option_pointer=""
    fzf_option_rounded=""
  fi

  folder_zip_or_jar=$(playground config get folder_zip_or_jar)
  if [ "$folder_zip_or_jar" == "" ]
  then
    logerror "Could not find config value <folder_zip_or_jar> !"
    exit 1
  fi

  folder_zip_or_jar=${folder_zip_or_jar//\~/$HOME}
  folder_zip_or_jar=${folder_zip_or_jar//,/ }
  
  fzf_output=$(find $folder_zip_or_jar $PWD -name \*.$type ! -path '*/\.*' | fzf -i --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🤐" --header="select zip or jar file (use option+enter to use the value you typed manually)" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer --print-query --bind "alt-enter:print-query")
  
  # Parse fzf output: first line is query, second line is selection (or query again if alt-enter was used)
  query_line=$(echo "$fzf_output" | head -n1)
  selected_line=$(echo "$fzf_output" | tail -n1)
  
  # If both lines are the same, user pressed alt-enter (use typed value)
  if [ "$query_line" = "$selected_line" ]; then
    res="$query_line"
  else
    res="$selected_line"
  fi
  
  echo "$cur@$res"
}

function get_specific_file_extension() {
  cur="$1"
  extension="$2"

  fzf_version=$(get_fzf_version)
  if version_gt $fzf_version "0.38"
  then
    fzf_option_wrap="--preview-window=40%,wrap"
    fzf_option_pointer="--pointer=👉"
    fzf_option_rounded="--border=rounded"
  else
    fzf_option_wrap=""
    fzf_option_pointer=""
    fzf_option_rounded=""
  fi
  
  fzf_output=$(find $PWD -name \*.$extension ! -path '*/\.*' | fzf -i --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🔖" --header="select $extension file (use option+enter to use the value you typed manually)" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer --print-query --bind "alt-enter:print-query")
  
  # Parse fzf output: first line is query, second line is selection (or query again if alt-enter was used)
  query_line=$(echo "$fzf_output" | head -n1)
  selected_line=$(echo "$fzf_output" | tail -n1)
  
  # If both lines are the same, user pressed alt-enter (use typed value)
  if [ "$query_line" = "$selected_line" ]; then
    res="$query_line"
  else
    res="$selected_line"
  fi
  
  echo "$cur@$res"
}

function get_playground_repro_export_with_fzf() {
  cur="$1"

  fzf_version=$(get_fzf_version)
  if version_gt $fzf_version "0.38"
  then
    fzf_option_wrap="--preview-window=40%,wrap"
    fzf_option_pointer="--pointer=👉"
    fzf_option_rounded="--border=rounded"
  else
    fzf_option_wrap=""
    fzf_option_pointer=""
    fzf_option_rounded=""
  fi

  folder_zip_or_jar=$(playground config get folder_zip_or_jar)
  if [ "$folder_zip_or_jar" == "" ]
  then
    logerror "Could not find config value <folder_zip_or_jar> !"
    exit 1
  fi

  folder_zip_or_jar=${folder_zip_or_jar//\~/$HOME}
  folder_zip_or_jar=${folder_zip_or_jar//,/ }
  
  # playground_repro_export.tgz is the name used by the former export
  fzf_output=$(find $folder_zip_or_jar $PWD \( -name 'playground_repro_*.tgz' -o -name 'playground_repro_*.tar.gz' \) ! -path '*/\.*' 2>/dev/null | sort -u | fzf -i --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="📃" --header="select repro bundle (use option+enter to use the value you typed manually)" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer --print-query --bind "alt-enter:print-query")

  # Parse fzf output: first line is query, second line is selection (or query again if alt-enter was used)
  query_line=$(echo "$fzf_output" | head -n1)
  selected_line=$(echo "$fzf_output" | tail -n1)

  # If both lines are the same, user pressed alt-enter (use typed value)
  if [ "$query_line" = "$selected_line" ]; then
    res="$query_line"
  else
    res="$selected_line"
  fi

  echo "$cur@$res"
}

# connector configs a customer sent (JSON, CFK / Strimzi resources, terraform, .properties), newest first: the files of
# the folders of 'playground config folder_zip_or_jar' and of the current folder (3 levels deep, not the playground
# itself) and of ~/Downloads and ~/Desktop (5 levels deep) that hold a connector.class, a Connector / KafkaConnector
# resource or a confluent_connector resource. When there is none, asks for the path
function get_connector_config_file_with_fzf() {
  cur="$1"

  fzf_version=$(get_fzf_version)
  if version_gt $fzf_version "0.38"
  then
    fzf_option_wrap="--preview-window=40%,wrap"
    fzf_option_pointer="--pointer=👉"
    fzf_option_rounded="--border=rounded"
  else
    fzf_option_wrap=""
    fzf_option_pointer=""
    fzf_option_rounded=""
  fi

  folder_zip_or_jar=$(playground config get folder_zip_or_jar)
  folder_zip_or_jar=${folder_zip_or_jar//\~/$HOME}
  folder_zip_or_jar=${folder_zip_or_jar//,/ }

  # modification time and path: GNU stat (Linux) or BSD stat (macOS)
  if stat -c '%Y' / > /dev/null 2>&1
  then
    stat_mtime=(stat -c '%Y %n')
  else
    stat_mtime=(stat -f '%m %N')
  fi

  # where customer files land: Downloads and Desktop, deeper (archived downloads, SendSafely folders…)
  deep_folders=""
  for folder in "$HOME/Downloads" "$HOME/Desktop"
  do
    if [ -d "$folder" ]
    then
      deep_folders="$deep_folders $folder"
    fi
  done

  # a home folder holds thousands of json / yaml files: one grep and one stat for all of them (a grep per file takes
  # minutes), fzf only gets the list once it is sorted
  files=$( {
      find $folder_zip_or_jar $PWD -maxdepth 3 \
        \( -path "$root_folder" -o -name node_modules -o -name Library -o -name target -o -name '.*' ! -name '.' \) -prune \
        -o -type f \( -name '*.json' -o -name '*.yaml' -o -name '*.yml' -o -name '*.tf' -o -name '*.properties' \) -size -1024k -print0 2>/dev/null
      if [ -n "$deep_folders" ]
      then
        find $deep_folders -maxdepth 5 \
          \( -name node_modules -o -name target -o -name '.*' ! -name '.' \) -prune \
          -o -type f \( -name '*.json' -o -name '*.yaml' -o -name '*.yml' -o -name '*.tf' -o -name '*.properties' \) -size -1024k -print0 2>/dev/null
      fi
    } \
    | sort -zu \
    | xargs -0 grep -lE 'connector\.class|kind:[[:space:]]*"?(Connector|KafkaConnector)|resource[[:space:]]+"confluent_connector"' 2>/dev/null \
    | tr '\n' '\0' \
    | xargs -0 "${stat_mtime[@]}" 2>/dev/null \
    | sort -rn | cut -d' ' -f2-)

  if [ -z "$files" ]
  then
    # nothing found: the path is typed, pasted or dragged onto the terminal
    res=$(echo "" | fzf --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="📄 " --header="no connector config found in ${folder_zip_or_jar:-your folders}, $PWD (3 levels) nor in Downloads / Desktop (5 levels): type, paste or drag the file here, then enter (configure the folders with playground config folder_zip_or_jar <folder1> <folder2>…)" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap --print-query 2>/dev/null | head -1)
    # a dragged file comes quoted, or with its spaces escaped
    res=$(echo "$res" | sed -E "s/^[[:space:]]*['\"]?//; s/['\"]?[[:space:]]*$//; s/\\\\ / /g")
    res=${res/#\~/$HOME}
    echo "$cur@$res"
    return
  fi

  fzf_output=$(echo "$files" \
    | fzf -i --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="📄" --header="select the connector config the customer sent, newest first (use option+enter to use the value you typed manually)" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer --preview "head -60 {}" --print-query --bind "alt-enter:print-query")

  # Parse fzf output: first line is query, second line is selection (or query again if alt-enter was used)
  query_line=$(echo "$fzf_output" | head -n1)
  selected_line=$(echo "$fzf_output" | tail -n1)

  # If both lines are the same, user pressed alt-enter (use typed value)
  if [ "$query_line" = "$selected_line" ]; then
    res="$query_line"
  else
    res="$selected_line"
  fi

  echo "$cur@$res"
}

# fzf picker for --file of playground analyze logs: the log files, exports (.csv, .json, .jsonl), archives (.zip, .tar.gz,
# .7z, .gz) and folders that a customer sends, newest first: files of ~/Downloads and ~/Desktop (3 levels deep, where
# bundles land and get extracted) and of the current folder (2 levels, the repository itself left out), and the folders at
# the top of ~/Downloads and ~/Desktop (an extracted bundle). The preview shows the size and the start of the file, the
# content of an archive, or the newest files of a folder. When there is none, asks for the path
function get_log_files_with_fzf() {
  cur="$1"

  fzf_version=$(get_fzf_version)
  if version_gt $fzf_version "0.38"
  then
    fzf_option_wrap="--preview-window=50%,wrap"
    fzf_option_pointer="--pointer=👉"
    fzf_option_rounded="--border=rounded"
  else
    fzf_option_wrap=""
    fzf_option_pointer=""
    fzf_option_rounded=""
  fi

  # modification time and path: GNU stat (Linux) or BSD stat (macOS)
  if stat -c '%Y' / > /dev/null 2>&1
  then
    stat_mtime=(stat -c '%Y %n')
  else
    stat_mtime=(stat -f '%m %N')
  fi

  deep_folders=()
  for folder in "$HOME/Downloads" "$HOME/Desktop"
  do
    if [ -d "$folder" ]
    then
      deep_folders+=("$folder")
    fi
  done
  log_names=(\( -name '*.log' -o -name '*.log.*' -o -name '*.txt' -o -name '*.out' -o -name '*.gz' -o -name '*.zip' \
    -o -name '*.tar' -o -name '*.tgz' -o -name '*.tbz2' -o -name '*.txz' -o -name '*.7z' -o -name '*.json' \
    -o -name '*.jsonl' -o -name '*.ndjson' -o -name '*.csv' \))

  files=$( {
      if [ "$PWD" != "$HOME" ]
      then
        find "$PWD" -maxdepth 2 \
          \( -path "$root_folder" -o -name node_modules -o -name target -o -name '.*' ! -name '.' \) -prune \
          -o -type f "${log_names[@]}" -size +0 -print0 2>/dev/null
      fi
      if [ ${#deep_folders[@]} -gt 0 ]
      then
        find "${deep_folders[@]}" -maxdepth 3 \
          \( -name node_modules -o -name target -o -name '.*' ! -name '.' \) -prune \
          -o -type f "${log_names[@]}" -size +0 -print0 2>/dev/null
        # an extracted bundle or a folder of logs
        find "${deep_folders[@]}" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -print0 2>/dev/null
      fi
    } \
    | sort -zu \
    | xargs -0 "${stat_mtime[@]}" 2>/dev/null \
    | sort -rn | cut -d' ' -f2-)

  if [ -z "$files" ]
  then
    # nothing found: the path is typed, pasted or dragged onto the terminal
    res=$(echo "" | fzf --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🗒️ " --header="no log file, export, archive or folder found in $PWD (2 levels) nor in Downloads / Desktop (3 levels): type, paste or drag it here, then enter" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap --print-query 2>/dev/null | head -1)
    # a dragged file comes quoted, or with its spaces escaped
    res=$(echo "$res" | sed -E "s/^[[:space:]]*['\"]?//; s/['\"]?[[:space:]]*$//; s/\\\\ / /g")
    res=${res/#\~/$HOME}
    echo "$cur@$res"
    return
  fi

  # size, then the start of a file, the content of an archive or the newest files of a folder
  preview='if [ -d {} ]; then du -sh {} 2>/dev/null; ls -lt {} 2>/dev/null | head -40; else ls -lh {} | awk "{print \$5, \$6, \$7, \$8}"; case {} in
    *.zip) unzip -l {} 2>/dev/null | head -40 ;;
    *.tar|*.tar.gz|*.tgz|*.tbz2|*.tar.bz2|*.txz|*.tar.xz|*.7z) tar -tvf {} 2>/dev/null | head -40 ;;
    *.gz) gzip -dc {} 2>/dev/null | head -c 6000 | head -40 ;;
    *) head -c 6000 {} | head -40 ;;
  esac; fi'

  fzf_output=$(echo "$files" \
    | fzf -i --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🗒️" --header="select the log file, export, archive or folder to analyze, newest first (use option+enter to use the value you typed manually)" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer --preview "$preview" --print-query --bind "alt-enter:print-query")

  # Parse fzf output: first line is query, second line is selection (or query again if alt-enter was used)
  query_line=$(echo "$fzf_output" | head -n1)
  selected_line=$(echo "$fzf_output" | tail -n1)

  # If both lines are the same, user pressed alt-enter (use typed value)
  if [ "$query_line" = "$selected_line" ]; then
    res="$query_line"
  else
    res="$selected_line"
  fi

  echo "$cur@$res"
}

#
# Reproduction model bundles (playground repro export / import)
#

# sha256 of a file, symlinks followed
function repro_sha256 () {
  if command -v sha256sum > /dev/null 2>&1
  then
    sha256sum "$1" | cut -d " " -f 1
  else
    shasum -a 256 "$1" | cut -d " " -f 1
  fi
}

# true when a path (relative to the folder of the model) must never go into a bundle:
# build output, dumps, recordings, logs, archives and credential files
function repro_bundle_denied () {
  local name="${1##*/}"
  case "/$1/" in
    */target/*|*/benchmark-history*|*-analysis-output/*|*/heap-analysis/*|*/cfk-reports/*) return 0 ;;
  esac
  case "$name" in
    *.hprof|*.hprof.gz|*.jfr|*.log|*.tgz|*.tar.gz|.DS_Store|repro-manifest.json) return 0 ;;
    keyfile.json|*.pem|*.key|*.p12|secrets.properties|playground.ini|playground-run-history|playground-repro-verdicts) return 0 ;;
  esac
  return 1
}

# value of a line '# <emoji> <key>: <value>' of the header written by repro bootstrap (empty for a field left to fill in)
function repro_header_value () {
  local script="$1"
  local key="$2"
  head -30 "$script" | grep -m1 -E "^# [^ ]+ $key:( |$)" | sed -E "s/^# [^ ]+ $key: ?//"
}

# the fields of the header that say what a model proves and what came out of it, in the order bootstrap writes them
function repro_header_fields () {
  echo "expected actual jira status"
}

function repro_header_emoji () {
  case "$1" in
    expected) echo "🎯" ;;
    actual) echo "💥" ;;
    jira) echo "🎫" ;;
    status) echo "🩹" ;;
  esac
}

# absolute path of a model with its folder resolved, the key of its verdicts in playground-repro-verdicts
function repro_model_path () {
  local script="$1"
  echo "$(cd -P "$(dirname "$script")" 2>/dev/null && pwd)/$(basename "$script")"
}

# last verdict recorded by 'playground repro assert' for a model, as JSON (empty when there is none)
function repro_last_verdict () {
  local script
  script=$(repro_model_path "$1")
  if [ -f "$root_folder/playground-repro-verdicts" ]
  then
    jq -c --arg script "$script" 'select(.script == $script)' "$root_folder/playground-repro-verdicts" 2>/dev/null | tail -1
  fi
}

# the base example of a model (folder relative to the repository), from the symlinks bootstrap created in its folder
function repro_base_example_of () {
  local script="$1" link target
  for link in README.md stop.sh
  do
    target=$(readlink "$(dirname "$script")/$link" 2>/dev/null || true)
    if [[ "$target" == ../../* ]]
    then
      dirname "${target#../../}"
      return 0
    fi
  done
}

# what 'repro diff' and the hand-off report compare, written in folder $2: base_scenario / model_scenario (the script of
# the base example and the scenario of the model: no header, no cheat sheet, no leading or trailing empty lines, the
# compose override renamed by bootstrap, docker-compose.plaintext.repro-<description>.yml, gets back the name of the
# example's), base_override / model_override when the model has its own override. Sets REPRO_DIFF_BASE_EXAMPLE,
# REPRO_DIFF_BASE_SCRIPT, REPRO_DIFF_BASE_OVERRIDE, REPRO_DIFF_MODEL_OVERRIDE (names); returns 1 without base example
function repro_diff_files () {
  local script="$1" out="$2" prefix trim
  REPRO_DIFF_BASE_EXAMPLE=$(repro_base_example_of "$script")
  prefix=$(basename "$script" | sed -E 's/-repro-.*$//')
  REPRO_DIFF_BASE_SCRIPT="$REPRO_DIFF_BASE_EXAMPLE/$prefix.sh"
  REPRO_DIFF_MODEL_OVERRIDE=""
  REPRO_DIFF_BASE_OVERRIDE=""
  if [ -z "$REPRO_DIFF_BASE_EXAMPLE" ] || [ ! -f "$root_folder/$REPRO_DIFF_BASE_SCRIPT" ]
  then
    return 1
  fi
  trim='{ lines[NR] = $0 } END { n = NR; while (n > 0 && lines[n] ~ /^[[:space:]]*$/) n--; s = 1; while (s <= n && lines[s] ~ /^[[:space:]]*$/) s++; for (i = s; i <= n; i++) print lines[i] }'
  awk 'banners < 2 { if (/^#####/) banners++; next } /^# 🧪 end the scenario with its verdict|^# 🧠 below is a list of cli commands/ { exit } { print }' "$script" \
    | sed -E 's/\.repro-[A-Za-z0-9-]+\.yml/.yml/g' | awk "$trim" > "$out/model_scenario"
  grep -v '^#!/bin/bash' "$root_folder/$REPRO_DIFF_BASE_SCRIPT" | awk "$trim" > "$out/base_scenario"
  REPRO_DIFF_MODEL_OVERRIDE=$(grep -oE 'docker-compose\.[A-Za-z0-9.-]*repro-[A-Za-z0-9-]+\.yml' "$script" | head -1 || true)
  if [ -n "$REPRO_DIFF_MODEL_OVERRIDE" ]
  then
    REPRO_DIFF_BASE_OVERRIDE=$(echo "$REPRO_DIFF_MODEL_OVERRIDE" | sed -E 's/\.repro-[A-Za-z0-9-]+\.yml/.yml/')
    if [ -f "$(dirname "$script")/$REPRO_DIFF_MODEL_OVERRIDE" ] && [ -f "$root_folder/$REPRO_DIFF_BASE_EXAMPLE/$REPRO_DIFF_BASE_OVERRIDE" ]
    then
      cp "$(dirname "$script")/$REPRO_DIFF_MODEL_OVERRIDE" "$out/model_override"
      cp "$root_folder/$REPRO_DIFF_BASE_EXAMPLE/$REPRO_DIFF_BASE_OVERRIDE" "$out/base_override"
    fi
  fi
  return 0
}

# the "key": value lines of the 'playground connector create-or-update' heredocs of a scenario: connector<TAB>key<TAB>value
function repro_config_keys () {
  awk '
    /playground connector create-or-update/ && /<</ {
      connector = $0; sub(/.*(--connector|-c)[ =]/, "", connector); sub(/[ \t].*/, "", connector); gsub(/["\047]/, "", connector)
      delim = $0; sub(/.*<<-?[ \t]*/, "", delim); gsub(/["\047]/, "", delim); sub(/[ \t].*/, "", delim)
      inside = 1; next
    }
    inside { line = $0; gsub(/^[ \t]+|[ \t]+$/, "", line); if (line == delim) { inside = 0; next } }
    inside && match($0, /^[ \t]*"[^"]+"[ \t]*:[ \t]*/) {
      key = $0; sub(/^[ \t]*"/, "", key); sub(/".*/, "", key)
      value = substr($0, RLENGTH + 1); sub(/[ \t]*,?[ \t]*$/, "", value)
      print connector "\t" key "\t" value
    }' "$1"
}

# the connector config keys changed, added and removed by the model ($2 its scenario) compared with the example ($1), as
# JSON: [{connector, compared_with, changed: [keys], added: [keys], removed: [keys]}], for the connectors of the model. A
# connector renamed in the model is compared with the connector of the example when the example has only one
function repro_config_changes () {
  jq -n -R --rawfile base <(repro_config_keys "$1") --rawfile model <(repro_config_keys "$2") '
    def entries($s): $s | split("\n") | map(select(length > 0) | split("\t") | {connector: .[0], key: .[1], value: (.[2:] | join("\t"))});
    entries($base) as $b | entries($model) as $m
    | ($b | map(.connector) | unique) as $base_connectors
    | [$m | map(.connector) | unique[] as $c
        | (if ($base_connectors | index($c)) != null then $c elif ($base_connectors | length) == 1 then $base_connectors[0] else null end) as $bname
        | ($b | map(select(.connector == $bname)) | map({key: .key, value: .value}) | from_entries) as $bc
        | ($m | map(select(.connector == $c)) | map({key: .key, value: .value}) | from_entries) as $mc
        | {connector: $c,
           compared_with: $bname,
           in_example: ($bc | length > 0),
           changed: [$mc | keys_unsorted[] | select($bc[.] != null and $bc[.] != $mc[.])],
           added: [$mc | keys_unsorted[] | select($bc[.] == null)],
           removed: [$bc | keys_unsorted[] | select($mc[.] == null)]}]'
}

# one line per connector of repro_config_changes ($1): "🧩 connector x: 2 key(s) changed (a, b), 1 added (c), 0 removed"
function repro_config_changes_lines () {
  echo "$1" | jq -r '.[] | if (.in_example | not) then "🧩 connector \(.connector): not in the example, \(.added | length) key(s)"
    elif ((.changed + .added + .removed) | length) == 0 then "🧩 connector \(.connector): same config as the example" + (if .compared_with != .connector then "\u0027s \(.compared_with)" else "" end)
    else "🧩 connector \(.connector)" + (if .compared_with != .connector then " (vs \(.compared_with) of the example)" else "" end) + ": " + ([
      (if (.changed | length) > 0 then "\(.changed | length) key(s) changed (\(.changed | join(", ")))" else empty end),
      (if (.added | length) > 0 then "\(.added | length) added (\(.added | join(", ")))" else empty end),
      (if (.removed | length) > 0 then "\(.removed | length) removed (\(.removed | join(", ")))" else empty end)] | join(", ")) end'
}

# one line for a verdict of playground-repro-verdicts: 🐞 reproduced on 2026-10-30 (CP 8.4.0, connector 10.8.0): <reason>
function repro_verdict_line () {
  echo "$1" | jq -r '(if .verdict == "reproduced" then "🐞 reproduced" else "✅ not reproduced" end)
    + " on \(.date[0:10]) (CP \(if .cp_version == "" then "default" else .cp_version end)"
    + (if .connector_version != "" then ", connector \(.connector_version)" else "" end) + "): \(.reason)"'
}

# a Jira key (CC-1234) becomes its link, anything else is kept as is
function repro_jira_url () {
  local jira="$1"
  if [[ "$jira" =~ ^[A-Z][A-Z0-9]+-[0-9]+$ ]]
  then
    echo "https://confluentinc.atlassian.net/browse/$jira"
  else
    echo "$jira"
  fi
}

# set a field of the header (see repro_header_fields): the line is replaced when it is there, otherwise it is added
# after '# 💬 comments:' and the fields that come before it (models created before the fields existed)
function repro_header_set_value () {
  local script="$1"
  local key="$2"
  local value="$3"
  local line="# $(repro_header_emoji "$key") $key:"
  if [ -n "$value" ]
  then
    line="$line $value"
  fi
  local before="comments" field
  for field in $(repro_header_fields)
  do
    [ "$field" == "$key" ] && break
    before="$before $field"
  done
  local tmp_file
  tmp_file=$(mktemp -t pg-XXXXXXXXXX)
  # ENVIRON: awk -v would interpret the backslashes of the value
  if ! REPRO_LINE="$line" REPRO_KEY="$key" REPRO_FIELDS="$before" awk '
    BEGIN {
      line = ENVIRON["REPRO_LINE"]; key = ENVIRON["REPRO_KEY"]
      n = split(ENVIRON["REPRO_FIELDS"], fields, " ")
    }
    { lines[NR] = $0 }
    NR <= 30 && !replaced && $0 ~ ("^# [^ ]+ " key ":( |$)") { replaced = NR }
    NR <= 30 {
      for (i = 1; i <= n; i++) if ($0 ~ ("^# [^ ]+ " fields[i] ":( |$)")) after = NR
      if ($0 ~ /^#####/ && ++banners == 2) closing = NR
    }
    END {
      if (!replaced && !after && !closing) exit 1
      for (i = 1; i <= NR; i++) {
        if (i == replaced) { print line; continue }
        if (!replaced && !after && i == closing) print line
        print lines[i]
        if (!replaced && i == after) print line
      }
    }' "$script" > "$tmp_file"
  then
    rm -f "$tmp_file"
    logerror "❌ $script has no reproduction model header (the '###…' block written by 'playground repro bootstrap')"
    return 1
  fi
  # in place: keeps the permissions of the script
  cat "$tmp_file" > "$script"
  rm -f "$tmp_file"
}

# normalize a relative path: remove '.' and resolve '..' (prints nothing when it goes above its root)
function repro_normalize_path () {
  local path="$1"
  local -a parts=()
  local part
  local IFS='/'
  for part in $path
  do
    case "$part" in
      ''|.) ;;
      ..)
        if [ ${#parts[@]} -eq 0 ]
        then
          return 0
        fi
        unset 'parts[${#parts[@]}-1]'
        ;;
      *) parts+=("$part") ;;
    esac
  done
  echo "${parts[*]}"
}

# path relative to the repository root of the target of a symlink, given its path
# relative to the repository root (prints nothing when it points outside the repository)
function repro_link_target () {
  local link_rel="$1"
  local target
  target=$(readlink "$root_folder/$link_rel")
  if [[ "$target" == /* ]]
  then
    return 0
  fi
  repro_normalize_path "$(dirname "$link_rel")/$target"
}

# files needed by a reproduction model, relative to the reproduction-models folder:
# the script, the support files linked by bootstrap, and every entry of its folder that is
# mentioned by the script or by a docker compose file it mentions (directories are expanded)
function repro_bundle_files () {
  local script="$1"
  local repro_root="$2"
  local dir=$(dirname "$script")
  local dir_name=$(basename "$dir")
  local script_name=$(basename "$script")
  local references
  local entry
  local file
  local -a selected=()

  references=$(cat "$script")
  for pass in 1 2
  do
    for entry in $(ls -A "$dir")
    do
      if [[ " ${selected[*]} " == *" $entry "* ]]
      then
        continue
      fi
      case "$entry" in
        "$script_name"|README.md|stop.sh|benchmark-load.bash|sql-datagen|.gitignore|config-*.json|config-*.txt)
          selected+=("$entry")
          ;;
        *)
          # a substring test, not one grep per entry: model folders hold hundreds of files
          if [[ "$references" == *"$entry"* ]]
          then
            selected+=("$entry")
          fi
          ;;
      esac
    done
    # second pass: what the selected docker compose files and load scripts mention
    for entry in "${selected[@]}"
    do
      case "$entry" in
        *.yml|*.yaml|benchmark-load*.bash)
          if [ -f "$dir/$entry" ]
          then
            references="$references"$'\n'"$(cat "$dir/$entry")"
          fi
          ;;
      esac
    done
  done

  # git-ignored entries, with one git call for all of them
  local -A ignored=()
  if [ -e "$repro_root/.git" ]
  then
    while IFS= read -r file
    do
      ignored[$file]=1
    done < <(for entry in "${selected[@]}"; do printf '%s/%s\n' "$dir_name" "$entry"; done | git -C "$repro_root" check-ignore --stdin 2>/dev/null)
  fi

  for entry in "${selected[@]}"
  do
    if [ -d "$dir/$entry" ] && [ ! -L "$dir/$entry" ]
    then
      if [ -e "$repro_root/.git" ]
      then
        git -C "$repro_root" ls-files --cached --others --exclude-standard -- "$dir_name/$entry" 2>/dev/null
      else
        (cd "$repro_root" && find "$dir_name/$entry" \( -type f -o -type l \))
      fi
    elif [ -n "${ignored[$dir_name/$entry]+set}" ]
    then
      continue
    else
      echo "$dir_name/$entry"
    fi
  done | sort -u | while read -r file
  do
    if repro_bundle_denied "${file#*/}"
    then
      continue
    fi
    if [ ! -e "$repro_root/$file" ]
    then
      logwarn "⏭️ skipping $file: broken symlink or missing file" >&2
      continue
    fi
    if [ -f "$repro_root/$file" ] && [ $(wc -c < "$repro_root/$file") -gt 52428800 ]
    then
      logwarn "⏭️ skipping $file: larger than 50 MB" >&2
      continue
    fi
    echo "$file"
  done
}

# names of the credentials a script uses: the variables it references that are known to the
# 'playground secrets' store, plus the credential helpers it calls (names only, never values)
function repro_required_credentials () {
  local script="$1"
  local known
  known=$({ secret_store_names default; secret_store_names "$(get_active_secret_profile)"; } 2>/dev/null | sort -u)
  {
    if [ -n "$known" ]
    then
      grep -oE '\$\{?[A-Z][A-Z0-9_]+' "$script" | tr -d '${' | sort -u | grep -xF -- "$known"
    fi
    grep -oE 'handle_(aws|azure|gcp)_credentials|bootstrap_ccloud_environment' "$script" | sort -u
  } | sort -u
}

# files outside the repository that text files of a model mention by absolute path
# ($HOME/…, ${HOME}/…, ~/…, /Users/…, /home/…): prints '<path as written>\t<absolute path>'
# for the ones that exist. Dot folders of the home ($HOME/.aws, .ssh, .m2…) and credential
# files are never returned, nor /tmp files, which the scripts write themselves.
function repro_external_paths () {
  local regex match path real_root
  regex=$(cat << 'EOF'
(\$\{HOME\}|\$HOME|~|/Users|/home)/[^[:space:]"'`:;,()<>|&{}]+
EOF
)
  real_root=$(cd -P "$root_folder" && pwd)
  grep -ohE -- "$regex" "$@" 2>/dev/null | sort -u | while IFS= read -r match
  do
    path="$match"
    case "$path" in
      '${HOME}'/*) path="$HOME/${path#'${HOME}'/}" ;;
      '$HOME'/*) path="$HOME/${path#'$HOME'/}" ;;
      '~'/*) path="$HOME/${path#'~'/}" ;;
    esac
    if [ ! -f "$path" ]
    then
      continue
    fi
    path="$(cd -P "$(dirname "$path")" && pwd)/$(basename "$path")"
    case "$path" in
      "$real_root"/*|"$HOME"/.*) continue ;;
    esac
    if repro_bundle_denied "$(basename "$path")"
    then
      continue
    fi
    printf '%s\t%s\n' "$match" "$path"
  done
}

# where the content of a bundle path comes from: an artifact (outside the repository,
# listed in the '<path>\t<source>\t<original>' file $3) or the reproduction-models folder $1
function repro_bundle_source () {
  local repro_root="$1"
  local artifacts_file="$2"
  local file="$3"
  local source=""
  if [ -n "$artifacts_file" ] && [ -f "$artifacts_file" ]
  then
    source=$(awk -F'\t' -v p="$file" '$1 == p { print $2; exit }' "$artifacts_file")
  fi
  echo "${source:-$repro_root/$file}"
}

# add the lines (8 chars or more) of a credential value to the pattern file of its label.
# values only ever go to files of a 0700 folder, never to a command line
function repro_scan_add_value () {
  local dir="$1"
  local label="$2"
  local value="$3"
  if [ ${#value} -lt 8 ]
  then
    return 0
  fi
  # a path is not a secret
  if [[ "$value" == /* ]] && [ -e "$value" ]
  then
    return 0
  fi
  printf '%s\n' "$value" | awk 'length($0) >= 8' >> "$dir/$label"
}

# true when a key name is the one of a credential (password, secret, token, api key, access
# key, private key) and not a setting about it (location, type, id, provider…)
function repro_is_credential_key () {
  local key="${1,,}"
  if ! [[ "$key" =~ (password|passwd|pwd|secret|token|api[._-]?key|apikey|access[._-]?key|private[._-]?key|credentials?)([._-]|$) ]] && ! [[ "$key" =~ (password|passwd|secret|token)$ ]]
  then
    return 1
  fi
  if [[ "$key" =~ (location|path|file|type|provider|class|url|uri|mode|algorithm|enabled|size|name|format|prefix|header|field|policy|expir|ttl|length|version|[._-]id)$ ]]
  then
    return 1
  fi
  return 0
}

# true when a hard-coded value looks like a real secret rather than a placeholder: 12 chars or
# more with 3 kinds of characters (lower case, upper case, digits, symbols), or 20 chars or more
# with 2 kinds (AWS secret access keys: 40 chars of base64). Never with a space (generated text),
# nor for a variable name used as a placeholder
function repro_is_strong_secret () {
  local value="$1"
  if [[ "$value" =~ [[:space:]] ]]
  then
    return 1
  fi
  # a variable name used as a placeholder: :AWS_SECRET_ACCESS_KEY:, {{TOKEN}}, [PASSWORD]
  if [[ "$value" =~ ^[^A-Za-z0-9]*[A-Z_]+[^A-Za-z0-9]*$ ]]
  then
    return 1
  fi
  case "${value,,}" in
    *confluent*|*password*|*changeit*|*changeme*|*example*|*dummy*|*redacted*|*placeholder*|*xxxx*|*'****'*|*'<'*|*'%'*) return 1 ;;
  esac
  local kinds=0
  [[ "$value" =~ [a-z] ]] && kinds=$((kinds+1))
  [[ "$value" =~ [A-Z] ]] && kinds=$((kinds+1))
  [[ "$value" =~ [0-9] ]] && kinds=$((kinds+1))
  [[ "$value" =~ [^A-Za-z0-9] ]] && kinds=$((kinds+1))
  if { [ ${#value} -ge 12 ] && [ $kinds -ge 3 ]; } || { [ ${#value} -ge 20 ] && [ $kinds -ge 2 ]; }
  then
    return 0
  fi
  return 1
}

# true when a value is in the files of the public base example (then it is not a leak).
# Cached in repro_public_value_cache (declared by repro_bundle_scan): one grep -r per value
function repro_value_in_public_example () {
  local value="$1"
  shift
  if [ $# -eq 0 ]
  then
    return 1
  fi
  if [ -z "${repro_public_value_cache[$value]+set}" ]
  then
    if printf '%s\n' "$value" | grep -rqIFf - -- "$@" 2>/dev/null
    then
      repro_public_value_cache[$value]=1
    else
      repro_public_value_cache[$value]=0
    fi
  fi
  [ "${repro_public_value_cache[$value]}" == "1" ]
}

# hard-coded values of credential keys, in JSON ("key": "value"), shell / env / properties
# (KEY=value, export KEY=value, - KEY=value) and YAML (key: value) lines: a value that looks
# like a real secret is a block, a weak one (placeholder, short) a warn. Values from ${VAR},
# and values also in the public base example, are not reported
#   $1 target (as shown), $2 file, $3 findings file, $4… public folders
function repro_scan_credential_literals () {
  local target="$1"
  local path="$2"
  local findings="$3"
  shift 3
  local -a public_folders=("$@")
  local line_number line key value regex_json regex_assign rest i
  local -a keys values
  regex_json='"([A-Za-z0-9._-]+)"[[:space:]]*:[[:space:]]*"([^"]*)"'
  regex_assign='^[[:space:]]*(-[[:space:]]+)?(export[[:space:]]+)?([A-Za-z0-9._-]+)[[:space:]]*(=|:[[:space:]])[[:space:]]*(.*)$'
  while IFS=: read -r line_number line
  do
    keys=()
    values=()
    rest="$line"
    while [[ "$rest" =~ $regex_json ]]
    do
      keys+=("${BASH_REMATCH[1]}")
      values+=("${BASH_REMATCH[2]}")
      rest="${rest#*"${BASH_REMATCH[0]}"}"
    done
    if [ ${#keys[@]} -eq 0 ] && [[ "$line" =~ $regex_assign ]]
    then
      keys+=("${BASH_REMATCH[3]}")
      values+=("${BASH_REMATCH[5]}")
    fi
    for i in "${!keys[@]}"
    do
      key="${keys[$i]}"
      value="${values[$i]}"
      [ -n "$key" ] || continue
      # strip quotes (escaped ones too, as in a JAAS config in a YAML string) and a trailing comment
      value="${value//\\\"/\"}"
      case "$value" in
        \"*) value="${value#\"}"; value="${value%%\"*}" ;;
        \'*) value="${value#\'}"; value="${value%%\'*}" ;;
        *) value="${value%%[[:space:]]#*}"; value="${value%%[[:space:]]}" ;;
      esac
      value="${value%,}"
      if [ -z "$value" ] || [[ "$value" == *'$'* ]] || ! repro_is_credential_key "$key"
      then
        continue
      fi
      if repro_value_in_public_example "$value" "${public_folders[@]}"
      then
        continue
      fi
      if repro_is_strong_secret "$value"
      then
        printf 'block\t%s:%s\t%s\n' "$target" "$line_number" "hard-coded value for $key that looks like a real secret: use \${VAR}" >> "$findings"
      else
        printf 'warn\t%s:%s\t%s\n' "$target" "$line_number" "hard-coded value for $key, not from the base example" >> "$findings"
      fi
    done
  done < <(grep -IniE '(password|passwd|pwd|secret|token|api.?key|access.?key|private.?key|credential)' "$path" 2>/dev/null || true)
}

# scan the files of a bundle for secrets and customer data, before it leaves the machine.
# writes one '<block|warn>\t<file>:<line>\t<message>' line per finding to $4, never a value
#   $1 reproduction-models folder, $2 file with the bundle paths (relative to $1),
#   $3 manifest (empty: no manifest, the files list has no symlink to skip), $4 findings file,
#   $5 base examples (relative to the repository root), $6 artifacts file (see repro_bundle_source),
#   $7 not empty: do not read the 'playground secrets' store (no backend prompt, for git hooks)
function repro_bundle_scan () {
  local repro_root="$1"
  local files_list="$2"
  local manifest="$3"
  local findings="$4"
  local base_examples="$5"
  local artifacts_file="${6:-}"
  local skip_secrets_store="${7:-}"
  local scan_dir
  scan_dir=$(mktemp -d)
  chmod 0700 "$scan_dir"
  mkdir "$scan_dir/values"
  : > "$findings"

  # 1. the credentials known to this machine
  local profile
  profile=$(get_active_secret_profile)
  local names name value
  names=$(secret_store_dump "$(get_secrets_file)" 2>/dev/null | awk -F"\t" -v p="$profile" '$1==p || $1=="default" { print $2 }')
  for name in $(compgen -e)
  do
    # PWD / OLDPWD match *PWD* but hold the current folder
    if [ "$name" != "PWD" ] && [ "$name" != "OLDPWD" ] && is_secret_env_var_name "$name"
    then
      names="$names"$'\n'"$name"
    fi
  done
  names=$(echo "$names" | awk 'NF' | sort -u)
  if [ -n "$names" ]
  then
    local backend_ready=1
    if [ -n "$skip_secrets_store" ]
    then
      backend_ready=0
    elif secret_backend_ready > /dev/null 2>&1
    then
      log "🔐 reading the $(echo "$names" | wc -l | tr -d ' ') credentials known to this machine to look for their values ($(get_secret_backend) backend)" >&2
      secret_prefetch "$profile" $names 2> /dev/null
    else
      backend_ready=0
      logwarn "🔐 the secrets backend is not ready, only the exported variables are checked: $(secret_backend_ready 2>&1 | head -1)" >&2
    fi
    for name in $names
    do
      if [ $backend_ready -eq 1 ]
      then
        value=$(secret_get "$name" "$profile" 2>/dev/null || true)
      else
        value="${!name:-}"
      fi
      repro_scan_add_value "$scan_dir/values" "$name" "$value"
    done
  fi
  # Confluent Cloud credentials of the playground (key:secret)
  if [ -f "$root_folder/playground.ini" ]
  then
    while IFS= read -r line
    do
      name="${line%%=*}"
      name="${name// /}"
      value="${line#*=}"
      value="${value#"${value%%[![:space:]]*}"}"
      value="${value%"${value##*[![:space:]]}"}"
      repro_scan_add_value "$scan_dir/values" "playground.ini-$name" "$value"
      repro_scan_add_value "$scan_dir/values" "playground.ini-$name" "${value%%:*}"
      repro_scan_add_value "$scan_dir/values" "playground.ini-$name" "${value#*:}"
    done < <(grep -E '^[A-Z_]*CREDS *=' "$root_folder/playground.ini" 2>/dev/null || true)
  fi
  # AWS credentials file read by handle_aws_credentials
  if [ -f "$HOME/.aws/credentials" ]
  then
    while IFS= read -r line
    do
      name="${line%%=*}"
      name="${name// /}"
      value="${line#*=}"
      value="${value// /}"
      repro_scan_add_value "$scan_dir/values" "aws-credentials-$name" "$value"
    done < <(grep -E '^ *(aws_access_key_id|aws_secret_access_key|aws_session_token) *=' "$HOME/.aws/credentials" 2>/dev/null || true)
  fi

  # 2. what is scanned: the files of the bundle, except the ones that are a public file
  # (symlink to the base example), plus the manifest (run flags)
  local -A linked=()
  local file
  if [ -n "$manifest" ]
  then
    while IFS= read -r file
    do
      linked[$file]=1
    done < <(jq -r '.files[] | select(.link_to) | .path' "$manifest")
  fi
  local -a targets=()
  while IFS= read -r file
  do
    if [ -z "${linked[$file]+set}" ]
    then
      targets+=("$file")
    fi
  done < "$files_list"

  # where each file is read from: artifacts come from outside the repository
  local -A sources=()
  local artifact source original
  if [ -n "$artifacts_file" ] && [ -f "$artifacts_file" ]
  then
    while IFS=$'\t' read -r artifact source original
    do
      if [ -n "$artifact" ] && [ -z "${sources[$artifact]+set}" ]
      then
        sources[$artifact]="$source"
      fi
    done < "$artifacts_file"
  fi

  local -a public_folders=()
  local base
  for base in $base_examples
  do
    if [ -d "$root_folder/$base" ]
    then
      public_folders+=("$root_folder/$base")
    fi
  done
  local -A repro_public_value_cache=()

  # the credential values, in one pattern file: a credential whose value is also in the public
  # base example is not a leak (checked once per credential, not once per file)
  local -a value_lines=() value_labels=()
  local value_file label value_line
  : > "$scan_dir/patterns"
  for value_file in "$scan_dir"/values/*
  do
    [ -f "$value_file" ] || continue
    label="${value_file##*/}"
    if [ ${#public_folders[@]} -gt 0 ] && grep -rqIFf "$value_file" -- "${public_folders[@]}" 2>/dev/null
    then
      continue
    fi
    while IFS= read -r value_line
    do
      value_lines+=("$value_line")
      value_labels+=("$label")
    done < "$value_file"
    cat "$value_file" >> "$scan_dir/patterns"
  done

  # well-known token formats
  local -a token_rules=(
    "an AWS access key id|(AKIA|ASIA)[A-Z0-9]{16}"
    "a private key|-----BEGIN ([A-Z]+ )?PRIVATE KEY-----"
    "a GitHub token|(gh[pousr]_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{22,})"
    "a Slack token|xox[abposr]-[A-Za-z0-9-]{10,}"
    "a Google API key|AIza[0-9A-Za-z_-]{35}"
    "a JWT (license, token)|eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"
    "an Azure storage account key|AccountKey=[A-Za-z0-9+/=]{40,}"
  )
  local -a token_grep_args=()
  local rule regex
  for rule in "${token_rules[@]}"
  do
    token_grep_args+=(-e "${rule#*|}")
  done

  local target path line_number line match domain ip o1 o2 o3 o4 i n nb_targets nb_done=0
  local -A labels_seen
  if [ -n "$manifest" ]
  then
    targets+=("repro-manifest.json")
  fi
  nb_targets=${#targets[@]}
  for target in "${targets[@]}"
  do
    nb_done=$((nb_done + 1))
    if [ $nb_targets -ge 200 ] && [ $((nb_done % 200)) -eq 0 ]
    then
      log "🕵️ $nb_done/$nb_targets files scanned" >&2
    fi
    if [ "$target" == "repro-manifest.json" ]
    then
      path="$manifest"
    else
      path="${sources[$target]:-$repro_root/$target}"
    fi

    # known credential values: one grep for all of them, then which ones matched
    if [ ${#value_lines[@]} -gt 0 ]
    then
      while IFS=: read -r line_number line
      do
        labels_seen=()
        for i in "${!value_lines[@]}"
        do
          if [[ "$line" == *"${value_lines[$i]}"* ]] && [ -z "${labels_seen[${value_labels[$i]}]+set}" ]
          then
            labels_seen[${value_labels[$i]}]=1
            printf 'block\t%s:%s\t%s\n' "$target" "$line_number" "contains the value of ${value_labels[$i]}" >> "$findings"
          fi
        done
      done < <(grep -InFf "$scan_dir/patterns" -- "$path" 2>/dev/null || true)
    fi

    # well-known token formats: one grep for all of them, then which ones matched
    while IFS=: read -r line_number line
    do
      if [[ "$line" == *EXAMPLE* ]]
      then
        continue
      fi
      for rule in "${token_rules[@]}"
      do
        regex="${rule#*|}"
        if [[ "$line" =~ $regex ]]
        then
          printf 'block\t%s:%s\t%s\n' "$target" "$line_number" "looks like ${rule%%|*}" >> "$findings"
        fi
      done
    done < <(grep -InE "${token_grep_args[@]}" -- "$path" 2>/dev/null || true)

    # possible customer data: warnings only. An address also in the public base example (the sample rows of its
    # tables…) is not customer data
    while IFS=: read -r line_number match
    do
      domain="${match#*@}"
      domain="${domain,,}"
      case "$domain" in
        example.com|example.org|example.net|*.example.com|confluent.io|*.confluent.io|confluent.cloud|*.local|*.noreply.github.com|anthropic.com|*.svc|*.internal) continue ;;
      esac
      if repro_value_in_public_example "$match" "${public_folders[@]}"
      then
        continue
      fi
      printf 'warn\t%s:%s\t%s\n' "$target" "$line_number" "email address at @$domain" >> "$findings"
    done < <(grep -InoE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "$path" 2>/dev/null || true)

    # versions (7.7.12.1) are not addresses: lines about versions, tags, images or archives are skipped
    while IFS=: read -r line_number match
    do
      if [[ "${match,,}" =~ version|tag|image|\.jar|\.zip ]]
      then
        continue
      fi
      ip=""
      if [[ "$match" =~ ([0-9]{1,3}\.){3}[0-9]{1,3} ]]
      then
        ip="${BASH_REMATCH[0]}"
      fi
      IFS=. read -r o1 o2 o3 o4 <<< "$ip"
      if [ "$o1" -gt 255 ] || [ "$o2" -gt 255 ] || [ "$o3" -gt 255 ] || [ "$o4" -gt 255 ]
      then
        continue
      fi
      case "$o1" in
        0|10|127|255) continue ;;
      esac
      if [ "$o1" -ge 224 ] || { [ "$o1" -eq 172 ] && [ "$o2" -ge 16 ] && [ "$o2" -le 31 ]; } || { [ "$o1" -eq 192 ] && [ "$o2" -eq 168 ]; } || { [ "$o1" -eq 169 ] && [ "$o2" -eq 254 ]; }
      then
        continue
      fi
      if repro_value_in_public_example "$ip" "${public_folders[@]}"
      then
        continue
      fi
      printf 'warn\t%s:%s\t%s\n' "$target" "$line_number" "public IP address $ip" >> "$findings"
    done < <(grep -InE '(^|[^0-9.])([0-9]{1,3}\.){3}[0-9]{1,3}([^0-9.]|$)' "$path" 2>/dev/null || true)

    repro_scan_credential_literals "$target" "$path" "$findings" "${public_folders[@]}"
  done

  rm -rf "$scan_dir"
  sort -u "$findings" | sort -t $'\t' -k1,1 -k2,2V -o "$findings"
}

# print the findings written by repro_bundle_scan, the first 20 of each kind
function repro_show_findings () {
  local findings="$1"
  local nb_blocks nb_warnings severity level location message
  nb_blocks=$(grep -c "^block" "$findings" || true)
  nb_warnings=$(grep -c "^warn" "$findings" || true)
  for severity in block warn
  do
    grep "^$severity" "$findings" | head -20 | while IFS=$'\t' read -r level location message
    do
      if [ "$level" == "block" ]
      then
        logerror "   🔐 $location $message"
      else
        logwarn "   👀 $location $message"
      fi
    done
  done
  if [ $((nb_blocks + nb_warnings)) -gt 40 ]
  then
    logwarn "   … $((nb_blocks + nb_warnings)) findings in total, only the first 20 of each kind are shown"
  fi
}

# public base examples of the model folders of a files list (relative to the reproduction-models
# folder $1): where the symlinks created by bootstrap point to, relative to the repository root
function repro_model_base_examples () {
  local repro_root="$1"
  local files_list="$2"
  local output_folder="reproduction-models"
  local dir_name link target
  for dir_name in $(grep '/' "$files_list" | cut -d "/" -f 1 | sort -u)
  do
    for link in "$repro_root/$dir_name"/*
    do
      if [ -L "$link" ]
      then
        target=$(repro_link_target "$output_folder/$dir_name/$(basename "$link")")
        if [ -n "$target" ] && [[ "$target" != "$output_folder"/* ]]
        then
          dirname "$target"
          break
        fi
      fi
    done
  done | sort -u | tr '\n' ' '
}

# the examples that deploy the connector.class of a normalized connector config ($1), best first, one path per line
# (relative to the repository). find-example finds the examples whose config uses the class; they are ranked by the
# words of the class (S3SinkConnector: s3, sink) and of the config (the database of a jdbc url, the auth type…) found in
# their path, then by the find-example score and the shortest path (the main example before its variants)
function repro_base_example_candidates () {
  local config="$1"
  local class category words
  class=$(echo "$config" | jq -r '."connector.class" // empty')
  if [ -z "$class" ]
  then
    return 0
  fi
  # a fully managed connector.class (S3_SINK) has no dot
  category="connect"
  if [[ "$class" != *.* ]]
  then
    category="ccloud"
  fi
  words=$( {
      echo "$class" | tr '._' '  ' | sed -E 's/([a-z0-9])([A-Z])/\1 \2/g'
      echo "$config" | jq -r '
        (to_entries[] | select(.key | test("connection\\.url$")) | .value | capture("^jdbc:(?<db>[a-z0-9]+):")?.db // empty),
        (to_entries[] | select(.key | test("auth\\.type$")) | .value | ascii_downcase | gsub("[^a-z]"; "") | select(. != "none")),
        (."value.converter" // "" | ascii_downcase | capture("(?<f>avro|protobuf|jsonschema)")?.f // empty)'
    } | tr ' A-Z' '\na-z' | sed -e 's/^postgresql$/postgres/' -e 's/^jsonschema$/json-schema/' \
      | grep . | grep -vxE 'io|com|org|net|confluent|confluentinc|connect|connector|kafka|apache|v[0-9]+' | sort -u | paste -sd ' ' -)
  playground find-example "$class" --category "$category" --limit 500 --json 2>/dev/null \
    | jq -r --arg class "$class" --arg words "$words" '
        ($words | split(" ") | map(select(. != ""))) as $words
        | map(select(.connector_classes | index($class)))
        | map(. + {rank: ([$words[] as $w | select(.path | ascii_downcase | contains($w))] | length)})
        | sort_by(-.rank, -.score, (.path | length))
        | .[].path'
}

# 'playground run' stops whatever runs (kill-all or stop): ask first when containers are running, another example or the
# environment of another session. $1 says what is about to run. Returns 1 when the answer is no. Never asks without a
# terminal (scripts, agents, CI), nor when nothing runs
function repro_confirm_stop_running_environment () {
  local what="$1" running
  if [ ! -t 0 ] || [ ! -t 1 ] || [ -n "$GITHUB_RUN_NUMBER" ]
  then
    return 0
  fi
  running=$(docker ps --format '{{.Names}}' 2>/dev/null | sort | tr '\n' ' ' | sed 's/ $//')
  if [ -z "$running" ]
  then
    return 0
  fi
  logwarn "⚠️ $what stops the $(echo "$running" | wc -w | tr -d ' ') container(s) that are running: $running"
  local choice
  read -r -p "Stop them and go on (y/N)? " choice
  [[ "$choice" == "y" || "$choice" == "Y" ]]
}

# point the git hooks of the reproduction-models repository to scripts/repro-git-hooks, whose
# pre-commit runs 'playground repro check --staged'. Never replaces hooks set up by the user
function repro_install_git_hook () {
  local repro_root="$root_folder/reproduction-models"
  local hooks_dir="$root_folder/scripts/repro-git-hooks"
  local current git_hooks
  if [ ! -e "$repro_root/.git" ] || [ ! -f "$hooks_dir/pre-commit" ]
  then
    return 0
  fi
  current=$(git -C "$repro_root" config --local --get core.hooksPath 2>/dev/null)
  if [ "$current" == "$hooks_dir" ]
  then
    return 0
  fi
  # ours, from a checkout that moved
  if [ -n "$current" ] && [[ "$current" != */scripts/repro-git-hooks ]]
  then
    logwarn "🪝 core.hooksPath of reproduction-models is set to $current: add 'playground repro check --staged' to your pre-commit hook to scan the commits for secrets"
    return 0
  fi
  git_hooks=$(cd "$repro_root" && cd "$(git rev-parse --git-path hooks)" 2>/dev/null && pwd)
  if [ -z "$current" ] && [ -n "$git_hooks" ] && [ -f "$git_hooks/pre-commit" ]
  then
    logwarn "🪝 reproduction-models already has a pre-commit hook: add 'playground repro check --staged' to it to scan the commits for secrets"
    return 0
  fi
  if git -C "$repro_root" config --local core.hooksPath "$hooks_dir"
  then
    log "🪝 reproduction-models commits are now scanned for secrets and customer data (pre-commit hook running 'playground repro check --staged')"
  fi
}

function get_ccloud_environment_list_with_fzf() {
  cur="$1"

  fzf_version=$(get_fzf_version)
  if version_gt $fzf_version "0.38"
  then
    fzf_option_wrap="--preview-window=40%,wrap"
    fzf_option_pointer="--pointer=👉"
    fzf_option_rounded="--border=rounded"
  else
    fzf_option_wrap=""
    fzf_option_pointer=""
    fzf_option_rounded=""
  fi

  res=$(confluent environment list | awk -F'|' '{print $2"/"$3}' | sed 's/[[:blank:]]//g' | grep -v "ID" | grep -v "\-\-\-" | grep -v '^/' | fzf -i --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🌐" --header="select ccloud environment" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer);echo "$cur@$res"
}

function get_ccloud_cluster_list_with_fzf() {
  cur="$1"

  fzf_version=$(get_fzf_version)
  if version_gt $fzf_version "0.38"
  then
    fzf_option_wrap="--preview-window=40%,wrap"
    fzf_option_pointer="--pointer=👉"
    fzf_option_rounded="--border=rounded"
  else
    fzf_option_wrap=""
    fzf_option_pointer=""
    fzf_option_rounded=""
  fi

  res=$(confluent kafka cluster list | awk -F'|' '{print $2"/"$3}' | sed 's/[[:blank:]]//g' | grep -v "ID" | grep -v "\-\-\-" | grep -v '^/' | fzf -i --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🌐" --header="select ccloud cluster" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer);echo "$cur@$res"
}

function get_confluent_kafka_region_list_with_fzf() {
  cur="$1"

  fzf_version=$(get_fzf_version)
  if version_gt $fzf_version "0.38"
  then
    fzf_option_wrap="--preview-window=40%,wrap"
    fzf_option_pointer="--pointer=👉"
    fzf_option_rounded="--border=rounded"
  else
    fzf_option_wrap=""
    fzf_option_pointer=""
    fzf_option_rounded=""
  fi
  
  res=$(cat $root_folder/scripts/cli/confluent-kafka-region-list.txt | fzf -i --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🌍" --header="select region" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer);echo "$cur@$res"
}

# get_container_env_value <container> <variable>: the value of an environment variable of a running container (a pod
# on cfk), empty when it isn't set
function get_container_env_value() {
  local container="$1"
  local variable="$2"
  get_environment_used
  if [[ "$environment" == cfk* ]]
  then
    kubectl -n confluent exec "$container" -- printenv "$variable" 2> /dev/null
    return 0
  fi
  docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$container" 2> /dev/null | sed -n "s/^${variable}=//p" | head -1
  return 0
}

# ec2_resolve_instances "<instances>": --instance of the ec2 commands can be a bare name (pg-user-xxx) or the
# name/state/dns/id form of 'playground ec2 list' (what the completion gives): sets ec2_resolved_instances to the
# name/state/dns/id form of each one, returns 1 when a name is not one of your instances
function ec2_resolve_instances() {
  local instances="$1"
  local item
  local list=""
  local found
  ec2_resolved_instances=""
  for item in $instances
  do
    if [[ "$item" == */* ]]
    then
      ec2_resolved_instances="${ec2_resolved_instances} ${item}"
      continue
    fi
    [ -z "$list" ] && list=$(ec2_instance_list)
    found=$(echo "$list" | awk -F/ -v n="$item" '$1 == n' | head -1)
    if [ -z "$found" ]
    then
      logerror "❌ ec2 instance $item not found (playground ec2 list shows your instances)"
      return 1
    fi
    ec2_resolved_instances="${ec2_resolved_instances} ${found}"
  done
  ec2_resolved_instances="${ec2_resolved_instances# }"
  return 0
}

function ec2_instance_list() {
  username=$(whoami)
  name="pg-${username}"

  for row in $(aws ec2 describe-instances --filters "Name=tag:Name,Values=$name-*" | jq '[.Reservations | .[] | .Instances | .[] | select(.State.Name!="terminated") | {PublicDnsName: .PublicDnsName, InstanceId: .InstanceId,State: .State.Name, Name: (.Tags[]|select(.Key=="Name")|.Value)}]' | jq -r '.[] | @base64'); do
      _jq() {
      echo ${row} | base64 -d | jq -r ${1}
      }

      Name=$(echo $(_jq '.Name'))
      if [[ $Name != $name* ]]
      then
          continue
      fi
      PublicDnsName=$(echo $(_jq '.PublicDnsName'))
      InstanceId=$(echo $(_jq '.InstanceId'))
      State=$(echo $(_jq '.State'))

      if [ "$State" = "stopped" ]
      then
          echo "$Name/$EC2_INSTANCE_STATE_STOPPED/$PublicDnsName/$InstanceId"
      elif [ "$State" = "stopping" ]
      then
          echo "$Name/$EC2_INSTANCE_STATE_STOPPING"
      elif [ "$State" = "pending" ]
      then
          echo "$Name/$EC2_INSTANCE_STATE_PENDING"
      else
          echo "$Name/$EC2_INSTANCE_STATE_RUNNING/$PublicDnsName/$InstanceId"
      fi
  done
}

function get_ec2_instance_list_with_fzf() {
  cur="$1"

  fzf_version=$(get_fzf_version)
  if version_gt $fzf_version "0.38"
  then
    fzf_option_wrap="--preview-window=40%,wrap"
    fzf_option_pointer="--pointer=👉"
    fzf_option_rounded="--border=rounded"
  else
    fzf_option_wrap=""
    fzf_option_pointer=""
    fzf_option_rounded=""
  fi

  res=$(ec2_instance_list | fzf -i --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🖥️" --header="select ec2 instance (wait for it)" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer);echo "$cur@$res"
}

function ec2_cloudformation_list() {
  username=$(whoami)
  name="pg-${username}"

  for row in $(aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE ROLLBACK_COMPLETE | jq '[.StackSummaries | .[] | {StackName: .StackName,StackStatus: .StackStatus }]' | jq -r '.[] | @base64'); do
      _jq() {
      echo ${row} | base64 -d | jq -r ${1}
      }

      StackName=$(echo $(_jq '.StackName'))
      StackStatus=$(echo $(_jq '.StackStatus'))

      if [[ $StackName != $name* ]]
      then
          continue
      fi

      echo "$StackName/$StackStatus"
  done
}

function get_ec2_cloudformation_list_with_fzf() {
  cur="$1"

  fzf_version=$(get_fzf_version)
  if version_gt $fzf_version "0.38"
  then
    fzf_option_wrap="--preview-window=40%,wrap"
    fzf_option_pointer="--pointer=👉"
    fzf_option_rounded="--border=rounded"
  else
    fzf_option_wrap=""
    fzf_option_pointer=""
    fzf_option_rounded=""
  fi

  res=$(ec2_cloudformation_list | fzf -i --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🌀" --header="select ec2 cloudformation (wait for it)" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer);echo "$cur@$res"
}

function get_tag_list_with_fzf() {
  cur="$1"
  connect_only="$2"

  if [[ "$connect_only" == "1" ]]
  then
    txt_file="connect-tag-list.txt"
  else
    txt_file="tag-list.txt"
  fi

  fzf_version=$(get_fzf_version)
  if version_gt $fzf_version "0.38"
  then
    fzf_option_wrap="--preview-window=40%,wrap"
    fzf_option_pointer="--pointer=👉"
    fzf_option_rounded="--border=rounded"
  else
    fzf_option_wrap=""
    fzf_option_pointer=""
    fzf_option_rounded=""
  fi

  # the list is refreshed in the background after each playground run: the very first time it does not exist yet
  if [ ! -s $root_folder/scripts/cli/$txt_file ]
  then
    log "⏳ generating the list of confluent platform versions (first time only)" >&2
    playground generate-tag-list > /dev/null
    if [ ! -s $root_folder/scripts/cli/$txt_file ]
    then
      logerror "❌ could not generate the list of confluent platform versions, check your internet access" >&2
      return
    fi
  fi

  # changes of the selected version, from the docs.confluent.io changelog feeds (7.4 onwards)
  fzf_option_preview=()
  if command -v python3 > /dev/null 2>&1
  then
    fzf_option_preview=(--preview "python3 -I '$root_folder/tools/cp-changelog/cp_changelog.py' --version {1} --format text 2>&1")
  fi

  res=$(cat $root_folder/scripts/cli/$txt_file | sed '1!G;h;$!d' | fzf -i --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🎯" --header="select cp version" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer "${fzf_option_preview[@]}");echo "$cur@$res"
}

function get_any_files_with_fzf() {
  cur="$1"

  fzf_version=$(get_fzf_version)
  if version_gt $fzf_version "0.38"
  then
    fzf_option_wrap="--preview-window=40%,wrap"
    fzf_option_pointer="--pointer=👉"
    fzf_option_rounded="--border=rounded"
  else
    fzf_option_wrap=""
    fzf_option_pointer=""
    fzf_option_rounded=""
  fi
  
  res=$(cat /tmp/get_any_files_with_fzf | fzf -i --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="📃" --header="select file" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer --print-query --bind "alt-enter:print-query");echo "$cur@$res"
}

function get_predefined_schemas_with_fzf() {
  DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
  dir1=$(echo ${DIR_CLI%/*})
  dir2=$(echo ${dir1%/*})

  cur="$1"

  predefined_folder=$dir2/scripts/cli/predefined-schemas
  fzf_version=$(get_fzf_version)
  if version_gt $fzf_version "0.38"
  then
    fzf_option_wrap="--preview-window=70%,wrap"
    fzf_option_pointer="--pointer=👉"
    fzf_option_rounded="--border=rounded"
  else
    fzf_option_wrap=""
    fzf_option_pointer=""
    fzf_option_rounded=""
  fi

  if [[ $(type -f bat 2>&1) =~ "not found" ]]
  then
    res=$(find $predefined_folder -maxdepth 3 \( -name "*.avro" -o -name "*.json" -o -name "*.avsc" -o -name "*.proto" -o -name "*.proto5" -o -name "*.sql"  \) | fzf -i --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🍟" --header="select a predefined schema" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" --delimiter / --with-nth "-2,-1" $fzf_option_wrap $fzf_option_pointer --preview 'cat {}')

    last_two_folders=$(basename $(dirname $(dirname $res)))/$(basename $(dirname $res))
    filename=$(basename "$res")
    file="$last_two_folders/$filename"
    echo "$cur@$file"
  else
    res=$(find $predefined_folder -maxdepth 3 \( -name "*.avro" -o -name "*.json" -o -name "*.avsc" -o -name "*.proto" -o -name "*.proto5" -o -name "*.sql" \) | fzf -i --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🍟" --header="select a predefined schema" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" --delimiter / --with-nth "-2,-1" $fzf_option_wrap $fzf_option_pointer --preview 'bat --style=plain --color=always --line-range :500 {}')

    last_two_folders=$(basename $(dirname $(dirname $res)))/$(basename $(dirname $res))
    filename=$(basename "$res")
    file="$last_two_folders/$filename"
    echo "$cur@$file"
  fi
}

function get_plugin_list() {
  cur="$1"
  type="$2"

  fzf_version=$(get_fzf_version)
  if version_gt $fzf_version "0.38"
  then
    fzf_option_wrap="--preview-window=40%,wrap"
    fzf_option_pointer="--pointer=👉"
    fzf_option_rounded="--border=rounded"
  else
    fzf_option_wrap=""
    fzf_option_pointer=""
    fzf_option_rounded=""
  fi

    if [ ! -f $root_folder/scripts/cli/confluent-hub-plugin-list.txt ]
    then
        playground generate-connector-plugin-list
    fi

    if [ ! -f $root_folder/scripts/cli/confluent-hub-plugin-list.txt ]
    then
        logerror "file $root_folder/scripts/cli/confluent-hub-plugin-list.txt could not be generated"
        exit 1
    fi

  case "${type}" in
    "fm")
        res=$(cat $root_folder/scripts/cli/confluent-hub-plugin-list.txt | grep -v "CONFLUENT EMPLOYEE VERSION" | cut -d "|" -f 1 | grep "^confluentinc/" | grep -v "-" | fzf -i --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🔌" --header="select connector plugin" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer);echo "$cur@$(echo $res | cut -d ' ' -f 2)"
    ;;
    "onprem")
        res=$(cat $root_folder/scripts/cli/confluent-hub-plugin-list.txt | grep -v "CONFLUENT EMPLOYEE VERSION" |cut -d "|" -f 1 | grep "-" | fzf -i --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🔌" --header="select connector plugin" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer);echo "$cur@$(echo $res | cut -d ' ' -f 2)"
    ;;
    *)
        res=$(cat $root_folder/scripts/cli/confluent-hub-plugin-list.txt | grep -v "CONFLUENT EMPLOYEE VERSION" |cut -d "|" -f 1 | fzf -i --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🔌" --header="select connector plugin" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer);echo "$cur@$(echo $res | cut -d ' ' -f 2)"
    ;;
  esac
}

function choose_connector_tag() {
  connector_plugin="$1"

  owner=$(echo "$connector_plugin" | cut -d "/" -f 1)
  name=$(echo "$connector_plugin" | cut -d "/" -f 2)

  filename="/tmp/version_${owner}_${name}"

  # renders $filename again from the cached Hub answer, so the age of each version is up to date
  playground connector-plugin versions --connector-plugin $owner/$name > /dev/null 2>&1

  if [ ! -f $filename ]
  then
      logerror "❌ could not get versions for connector plugin $connector_plugin"
      exit 1
  fi


  fzf_version=$(get_fzf_version)
  if version_gt $fzf_version "0.38"
  then
    fzf_option_wrap="--preview-window=40%,wrap"
    fzf_option_pointer="--pointer=👉"
    fzf_option_rounded="--border=rounded"
  else
    fzf_option_wrap=""
    fzf_option_pointer=""
    fzf_option_rounded=""
  fi

  # release notes of the selected version, from the docs.confluent.io changelog feeds (Confluent plugins only)
  fzf_option_preview=()
  if [ "$owner" == "confluentinc" ] && command -v python3 > /dev/null 2>&1
  then
    fzf_option_preview=(--preview "python3 -I '$root_folder/tools/connector-changelog/changelog.py' --connector-plugin '$owner/$name' --version {2} --format text 2>&1")
  fi

  cat $filename | grep -v "documentation"| sed '1!G;h;$!d' | fzf -i --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🔢" --header="select connector version for $owner/$name" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer "${fzf_option_preview[@]}"
}

function filter_ccloud_environment() {
  get_environment_used

  if [[ "$environment" != "ccloud" ]]
  then
    logerror "environment should be ccloud with this command (it is $environment)!"
  fi
}

function filter_not_ccloud_environment() {
  get_environment_used

  if [[ "$environment" == "ccloud" ]]
  then
    logerror "this command is not available with Confluent Cloud"
  fi
}

function filter_not_cfk_environment() {
  get_environment_used

  if [[ "$environment" == cfk* ]]
  then
    logerror "this command is not available with $environment (the brokers are pods managed by Confluent for Kubernetes)"
  fi
}

function filter_cfk_environment() {
  get_environment_used

  if [[ "$environment" != cfk* ]]
  then
    logerror "environment should be cfk with this command (it is $environment)!"
  fi
}

function filter_rbac_environment() {
  get_environment_used

  if [[ "$environment" != "rbac-sasl-plain" ]] && [[ "$environment" != "rbac-oauth" ]] && [[ "$environment" != "cfk-rbac" ]]
  then
    logerror "environment should be rbac-sasl-plain, rbac-oauth or cfk-rbac with this command (it is $environment)!"
  fi
}

function filter_rbac_or_ccloud_environment() {
  get_environment_used

  if [[ "$environment" != "rbac-sasl-plain" ]] && [[ "$environment" != "rbac-oauth" ]] && [[ "$environment" != "cfk-rbac" ]] && [[ "$environment" != "ccloud" ]]
  then
    logerror "environment should be rbac-sasl-plain, rbac-oauth, cfk-rbac or ccloud with this command (it is $environment)!"
  fi
}

# call the MDS REST API of the rbac-sasl-plain or cfk-rbac environment as superUser, or of the rbac-oauth environment
# with a bearer token of the Keycloak client superuser
# (on cfk-rbac, localhost:8091 is a port-forward to the MDS of the kafka service)
# usage: mds_request <method> <path> [json body]
# sets mds_output (response body), returns 1 when MDS is not reachable or answers an error
function mds_request() {
  local method="$1"
  local path="$2"
  local body="$3"
  local mds_url="http://localhost:8091"
  # bashly filters run in a subshell: environment is not set by filter_rbac_environment
  if [[ -z "$environment" ]]
  then
    get_environment_used
  fi
  local mds_auth=(-u superUser:superUser)
  local mds_auth_display="-u superUser:superUser"
  if [[ "$environment" == "rbac-oauth" ]]
  then
    if [[ -z "$mds_oauth_token" ]]
    then
      mds_oauth_token=$(get_rbac_oauth_token superuser)
      if [[ -z "$mds_oauth_token" ]]
      then
        logerror "❌ could not get a token of the Keycloak client superuser on http://localhost:8180, is the rbac-oauth environment running?"
        return 1
      fi
    fi
    mds_auth=(--oauth2-bearer "$mds_oauth_token")
    mds_auth_display="--oauth2-bearer \$(curl -s -d grant_type=client_credentials -d client_id=superuser -d client_secret=superuser-secret http://localhost:8180/realms/kafka/protocol/openid-connect/token | jq -r .access_token)"
  fi
  local curl_args=(-s -w '\n%{http_code}' "${mds_auth[@]}" -H "Content-Type: application/json" -X "$method" "$mds_url$path")

  if [[ -n "$body" ]]
  then
    curl_args+=(-d "$body")
  fi

  if [[ -n "$verbose" ]]
  then
    log "🐞 curl command used"
    echo "curl -X $method $mds_auth_display -H \"Content-Type: application/json\" $mds_url$path${body:+ -d '$body'}"
  fi

  local response
  response=$(curl "${curl_args[@]}")
  if [ $? -ne 0 ]
  then
    logerror "❌ MDS is not reachable at $mds_url, is the rbac-sasl-plain, rbac-oauth or cfk-rbac environment running?"
    return 1
  fi
  local http_code=$(tail -n 1 <<< "$response")
  mds_output=$(sed '$d' <<< "$response")
  if [[ "$http_code" != 2* ]]
  then
    logerror "❌ MDS answered HTTP $http_code to $method $path: $(jq -r '.message // .' <<< "$mds_output" 2> /dev/null || echo "$mds_output")"
    return 1
  fi
}

# usage: get_mds_scope <kafka|schema-registry|connect|ksqldb>
# sets mds_scope, the MDS JSON scope of that cluster
function get_mds_scope() {
  local scope="${1:-kafka}"

  if [[ -z "$mds_kafka_cluster_id" ]]
  then
    mds_request GET /security/1.0/metadataClusterId || return 1
    mds_kafka_cluster_id="$mds_output"
  fi

  # cluster names used in environment/rbac-sasl-plain (and rbac-oauth), or cluster ids set by CFK on cfk-rbac
  local schema_registry_cluster="schema-registry"
  local connect_cluster="connect-cluster"
  # bashly filters run in a subshell: environment is not set by filter_rbac_environment
  if [[ -z "$environment" ]]
  then
    get_environment_used
  fi
  if [[ "$environment" == "cfk-rbac" ]]
  then
    schema_registry_cluster="id_schemaregistry_confluent"
    connect_cluster="confluent.connect"
  fi
  case "$scope" in
    kafka)
      mds_scope=$(jq -nc --arg k "$mds_kafka_cluster_id" '{clusters: {"kafka-cluster": $k}}')
    ;;
    schema-registry)
      mds_scope=$(jq -nc --arg k "$mds_kafka_cluster_id" --arg c "$schema_registry_cluster" '{clusters: {"kafka-cluster": $k, "schema-registry-cluster": $c}}')
    ;;
    connect)
      mds_scope=$(jq -nc --arg k "$mds_kafka_cluster_id" --arg c "$connect_cluster" '{clusters: {"kafka-cluster": $k, "connect-cluster": $c}}')
    ;;
    ksqldb)
      mds_scope=$(jq -nc --arg k "$mds_kafka_cluster_id" '{clusters: {"kafka-cluster": $k, "ksql-cluster": "ksql-cluster"}}')
    ;;
    *)
      logerror "❌ unknown scope $scope, it should be kafka, schema-registry, connect or ksqldb"
      return 1
    ;;
  esac
}

# a bare name means User:<name>
function normalize_rbac_principal() {
  local principal="$1"
  if [[ "$principal" != User:* ]] && [[ "$principal" != Group:* ]]
  then
    principal="User:$principal"
  fi
  echo "$principal"
}

# split <ResourceType>:<name> into resource_type and resource_name
function parse_rbac_resource() {
  local resource="$1"
  if [[ "$resource" != *:* ]] || [[ -z "${resource%%:*}" ]] || [[ -z "${resource#*:}" ]]
  then
    logerror "❌ resource $resource should be <ResourceType>:<name>, for example Topic:orders"
    return 1
  fi
  resource_type="${resource%%:*}"
  resource_name="${resource#*:}"
}

# create or delete the role binding described by the --principal, --role,
# --resource, --prefix and --scope flags
# usage: mds_role_binding <POST|DELETE>
function mds_role_binding() {
  local method="$1"
  local principal=$(normalize_rbac_principal "${args[--principal]}")
  local role="${args[--role]}"
  local resource="${args[--resource]}"
  local prefix="${args[--prefix]}"
  local scope="${args[--scope]}"
  local pattern_type="LITERAL"
  local action="Creating"
  local resource_type=""
  local resource_name=""

  if [ "$method" == "DELETE" ]
  then
    action="Deleting"
  fi

  if [[ -n "$prefix" ]]
  then
    pattern_type="PREFIXED"
  fi

  if [[ -n "$resource" ]]
  then
    parse_rbac_resource "$resource" || return 1
  elif [[ -n "$prefix" ]]
  then
    logerror "❌ --prefix requires --resource"
    return 1
  fi

  if [[ -z "$scope" ]]
  then
    case "$resource_type" in
      Subject) scope="schema-registry" ;;
      Connector) scope="connect" ;;
      KsqlCluster) scope="ksqldb" ;;
      *) scope="kafka" ;;
    esac
  fi
  get_mds_scope "$scope" || return 1

  if [[ -z "$resource" ]]
  then
    log "🔐 $action role binding $role for $principal on $scope cluster"
    mds_request "$method" "/security/1.0/principals/$principal/roles/$role" "$mds_scope" || return 1
  else
    local pattern_log=""
    if [ "$pattern_type" == "PREFIXED" ]
    then
      pattern_log=" (prefixed)"
    fi
    log "🔐 $action role binding $role for $principal on $resource_type:$resource_name$pattern_log ($scope cluster)"
    local body=$(jq -nc --argjson scope "$mds_scope" --arg type "$resource_type" --arg name "$resource_name" --arg pattern "$pattern_type" \
      '{scope: $scope, resourcePatterns: [{resourceType: $type, name: $name, patternType: $pattern}]}')
    mds_request "$method" "/security/1.0/principals/$principal/roles/$role/bindings" "$body" || return 1
  fi
}

# create or delete the ACLs described by the --principal, --operation,
# --resource, --prefix, --deny, --host and --kafka-acls flags
# usage: mds_acl <create|delete>
function mds_acl() {
  local action="$1"
  if [[ -n "${args[--connector]}" ]]
  then
    logerror "❌ --connector is only supported with Confluent Cloud (fully managed connectors)"
    return 1
  fi
  if [[ -z "${args[--principal]}" ]]
  then
    logerror "❌ --principal is required"
    return 1
  fi
  local principal=$(normalize_rbac_principal "${args[--principal]}")
  local resource="${args[--resource]}"
  local prefix="${args[--prefix]}"
  local deny="${args[--deny]}"
  local host="${args[--host]:-*}"
  local kafka_acls="${args[--kafka-acls]}"
  local pattern_type="LITERAL"
  local permission="ALLOW"
  local resource_type=""
  local resource_name=""
  eval "local operations=(${args[--operation]})"

  if [[ -n "$prefix" ]]
  then
    pattern_type="PREFIXED"
  fi
  if [[ -n "$deny" ]]
  then
    permission="DENY"
  fi

  parse_rbac_resource "$resource" || return 1

  local mds_resource_type=""
  local kafka_acls_resource=""
  case "$resource_type" in
    Topic) mds_resource_type="TOPIC"; kafka_acls_resource="--topic $resource_name" ;;
    Group) mds_resource_type="GROUP"; kafka_acls_resource="--group $resource_name" ;;
    Cluster) mds_resource_type="CLUSTER"; kafka_acls_resource="--cluster" ;;
    TransactionalId) mds_resource_type="TRANSACTIONAL_ID"; kafka_acls_resource="--transactional-id $resource_name" ;;
    DelegationToken) mds_resource_type="DELEGATION_TOKEN"; kafka_acls_resource="--delegation-token $resource_name" ;;
    *)
      logerror "❌ resource type $resource_type is not supported for ACLs, it should be Topic, Group, Cluster, TransactionalId or DelegationToken"
      return 1
    ;;
  esac

  if [[ -n "$kafka_acls" ]]
  then
    local kafka_acls_args="--$action --$(tr '[:upper:]' '[:lower:]' <<< "$permission")-principal $principal --$(tr '[:upper:]' '[:lower:]' <<< "$permission")-host '$host' $kafka_acls_resource --resource-pattern-type $(tr '[:upper:]' '[:lower:]' <<< "$pattern_type")"
    local operation
    for operation in "${operations[@]}"
    do
      kafka_acls_args="$kafka_acls_args --operation $operation"
    done
    if [ "$action" == "remove" ]
    then
      kafka_acls_args="$kafka_acls_args --force"
    fi
    log "🧰 kafka-acls $kafka_acls_args"
    playground container exec -c broker --command "kafka-acls --bootstrap-server broker:9092 --command-config /etc/kafka/secrets/client_without_interceptors.config $kafka_acls_args" || return 1
    return 0
  fi

  get_mds_scope kafka || return 1
  local operation
  for operation in "${operations[@]}"
  do
    local entry=$(jq -nc --arg principal "$principal" --arg operation "$operation" --arg permission "$permission" --arg host "$host" \
      '{principal: $principal, operation: $operation, permissionType: $permission, host: $host}')
    local pattern=$(jq -nc --arg type "$mds_resource_type" --arg name "$resource_name" --arg pattern "$pattern_type" \
      '{resourceType: $type, name: $name, patternType: $pattern}')
    if [ "$action" == "add" ]
    then
      log "🚦 Creating ACL $permission $operation for $principal on $resource_type:$resource_name ($pattern_type)"
      mds_request POST "/security/1.0/acls" "$(jq -nc --argjson scope "$mds_scope" --argjson pattern "$pattern" --argjson entry "$entry" '{scope: $scope, aclBinding: {pattern: $pattern, entry: $entry}}')" || return 1
    else
      log "🗑️ Deleting ACL $permission $operation for $principal on $resource_type:$resource_name ($pattern_type)"
      mds_request DELETE "/security/1.0/acls" "$(jq -nc --argjson scope "$mds_scope" --argjson pattern "$pattern" --argjson entry "$entry" '{scope: $scope, aclBindingFilter: {patternFilter: $pattern, entryFilter: $entry}}')" || return 1
    fi
  done
}

# ⛅ Confluent Cloud ACLs and service accounts of fully managed connectors
# (playground run --ccloud-service-account, and playground rbac acl on a ccloud run)
# see https://docs.confluent.io/cloud/current/connectors/service-account.html

# flags of confluent kafka acl create|delete for one ACL
# $1 = principal (User:sa-xxx or User:u-xxx), $2 = operations (READ,WRITE), $3 = <ResourceType>:<name>,
# $4 = 1 when the resource name is a prefix, $5 = ALLOW (default) or DENY
# sets ccloud_acl_flags (array)
function get_ccloud_acl_flags() {
  local principal="$1"
  local operations="$2"
  local resource="$3"
  local prefix="$4"
  local permission="${5:-ALLOW}"
  local resource_type="${resource%%:*}"
  local resource_name="${resource#*:}"

  ccloud_acl_flags=()
  if [[ "$principal" == User:sa-* ]]
  then
    ccloud_acl_flags+=(--service-account "${principal#User:}")
  else
    ccloud_acl_flags+=(--principal "$principal")
  fi
  # READ,DESCRIBE_CONFIGS -> read,describe-configs
  ccloud_acl_flags+=(--operations "$(tr '[:upper:]_' '[:lower:]-' <<< "$operations")")
  ccloud_acl_flags+=("--$(tr '[:upper:]' '[:lower:]' <<< "$permission")")
  case "$resource_type" in
    Topic) ccloud_acl_flags+=(--topic "$resource_name") ;;
    Group) ccloud_acl_flags+=(--consumer-group "$resource_name") ;;
    Cluster) ccloud_acl_flags+=(--cluster-scope) ;;
    TransactionalId) ccloud_acl_flags+=(--transactional-id "$resource_name") ;;
    *)
      logerror "❌ resource type $resource_type is not supported for Confluent Cloud ACLs, it should be Topic, Group, Cluster or TransactionalId"
      return 1
    ;;
  esac
  if [ "$prefix" == "1" ]
  then
    ccloud_acl_flags+=(--prefix)
  fi
}

# log a confluent CLI command, quoted to be copied and pasted
function log_confluent_command() {
  local arg
  local command="confluent"
  for arg in "$@"
  do
    if [[ "$arg" =~ ^[A-Za-z0-9_./:,=@+-]+$ ]]
    then
      command="$command $arg"
    else
      command="$command '${arg//\'/\'\\\'\'}'"
    fi
  done
  log "💻 $command"
}

# create or delete one ACL on the Confluent Cloud cluster of the ccloud run. Creation is retried for a
# minute: a service account created a few seconds ago may not be known by the cluster yet
# usage: ccloud_acl_request <create|delete> <arguments of get_ccloud_acl_flags>
function ccloud_acl_request() {
  local action="$1"
  shift
  local output
  local -i curr_wait=0
  get_ccloud_acl_flags "$@" || return 1
  if [ "$action" == "delete" ]
  then
    ccloud_acl_flags+=(--force)
  fi
  local command=(kafka acl "$action" "${ccloud_acl_flags[@]}" --environment "$(get_ccloud_environment_id)" --cluster "$(get_ccloud_kafka_cluster_id)")
  log_confluent_command "${command[@]}"
  until output=$(confluent "${command[@]}" 2>&1)
  do
    if [ "$action" == "delete" ] || (( curr_wait >= 60 ))
    then
      logerror "❌ confluent ${command[*]} failed: $output"
      return 1
    fi
    curr_wait=$((curr_wait+5))
    sleep 5
  done
}

# ACLs of a principal on the Confluent Cloud cluster of the ccloud run, one per line:
# <PERMISSION> <OPERATION> <ResourceType>:<name> <LITERAL|PREFIXED> (all the ACLs of the cluster without $1)
# $1 = principal (User:sa-xxx), optional
function get_ccloud_acls() {
  local principal="$1"
  local principal_flags=()
  if [[ "$principal" == User:sa-* ]]
  then
    principal_flags=(--service-account "${principal#User:}")
  elif [[ -n "$principal" ]]
  then
    principal_flags=(--principal "$principal")
  fi
  local command=(kafka acl list "${principal_flags[@]}" --environment "$(get_ccloud_environment_id)" --cluster "$(get_ccloud_kafka_cluster_id)")
  # stderr: the output of this function is parsed
  log_confluent_command "${command[@]}" >&2
  confluent "${command[@]}" -o json | jq -r '.[] |
    (.resource_type | if . == "TOPIC" then "Topic" elif . == "GROUP" then "Group" elif . == "CLUSTER" then "Cluster" elif . == "TRANSACTIONAL_ID" then "TransactionalId" else . end) as $type |
    [.principal, .permission, .operation, "\($type):\(.resource_name)", .pattern_type] | @tsv'
}

# Topic resource of an ACL for a topic name of a connector config, which can contain templates:
# ${connector} is the lcc id (dlq-${connector} -> prefix dlq-lcc-), and any other ${...} turns the
# name into a prefix (${databaseName}.${schemaName}.${tableName} -> every topic, Topic:*)
# prints <ResourceType>:<name> [prefix]
function get_ccloud_acl_topic_resource() {
  local name="$1"
  name="${name//\$\{connector\}/lcc-\$\{connector\}}"
  if [[ "$name" != *'${'* ]]
  then
    echo "Topic:$name"
  elif [[ -n "${name%%\$\{*}" ]]
  then
    echo "Topic:${name%%\$\{*} prefix"
  else
    echo "Topic:*"
  fi
}

# ACLs the service account of a fully managed connector needs, derived from its config as listed in
# https://docs.confluent.io/cloud/current/connectors/service-account.html
# prints one ACL per line: <OPERATION> <ResourceType>:<name> [prefix]
# $1 = connector config as a JSON object, $2 = docs (default), full or none
function get_ccloud_connector_service_account_acls() {
  local config="$1"
  local profile="${2:-docs}"
  local connector_class
  local topic
  local resource
  local operation
  local prefix
  local value

  case "$profile" in
    none)
      return 0
    ;;
    full)
      # same as the service account of the Confluent Cloud stack (ccloud::create_acls_all_resources_full_access)
      printf '%s Topic:*\n' CREATE DELETE WRITE READ DESCRIBE DESCRIBE_CONFIGS ALTER_CONFIGS
      printf '%s Group:*\n' READ WRITE CREATE DESCRIBE
      printf '%s TransactionalId:*\n' DESCRIBE WRITE
      printf '%s Cluster:kafka-cluster\n' IDEMPOTENT_WRITE DESCRIBE
      return 0
    ;;
  esac

  connector_class=$(jq -r '."connector.class" // empty' <<< "$config")
  echo "DESCRIBE Cluster:kafka-cluster"

  if [ -n "$(jq -r '.topics // ."topics.regex" // empty' <<< "$config")" ]
  then
    # sink
    for topic in $(jq -r '.topics // empty' <<< "$config" | tr ',' '\n' | tr -d ' ')
    do
      echo "READ Topic:$topic"
    done
    if [ -n "$(jq -r '."topics.regex" // empty' <<< "$config")" ]
    then
      # a regex can't be an ACL
      echo "READ Topic:*"
    fi
    echo "READ Group:connect-lcc- prefix"
    resource=$(get_ccloud_acl_topic_resource "$(jq -r '."errors.deadletterqueue.topic.name" // "dlq-${connector}"' <<< "$config")")
    printf "%s $resource\n" CREATE WRITE
    case "$connector_class" in
      HttpSink|HttpSinkV2|LambdaSink|AzureFunctionsSink|DatadogMetricsSink|GoogleCloudFunctionsSink|GoogleCloudFunctionsGen2Sink|SalesforcePlatformEventSink|ServiceNowSink)
        resource=$(get_ccloud_acl_topic_resource "$(jq -r '."reporter.result.topic.name" // "success-${connector}"' <<< "$config")")
        printf "%s $resource\n" CREATE WRITE
        resource=$(get_ccloud_acl_topic_resource "$(jq -r '."reporter.error.topic.name" // "error-${connector}"' <<< "$config")")
        printf "%s $resource\n" CREATE WRITE
      ;;
    esac
  else
    # source: the documentation lists WRITE on an existing topic, CREATE lets the connector create it
    # as the examples expect (same keys as record_ccloud_connector_output_topics)
    for topic in $(jq -r 'to_entries[] | select(.key | test("^(kafka\\.topic|couchbase\\.topic|redo\\.log\\.topic\\.name|state\\.topic\\.name|[a-z]+[0-9]+\\.topics?)$")) | .value | strings' <<< "$config" | tr ',' '\n' | tr -d ' ')
    do
      resource=$(get_ccloud_acl_topic_resource "$topic")
      printf "%s $resource\n" CREATE WRITE
    done
    for prefix in $(jq -r 'to_entries[] | select(.key | test("^(topic\\.prefix|[a-z0-9]+\\.topic\\.prefix|database\\.server\\.name)$")) | .value | strings' <<< "$config" | tr -d ' ')
    do
      resource=$(get_ccloud_acl_topic_resource "$prefix")
      if [[ "$resource" != *" prefix" ]] && [[ "$resource" != "Topic:*" ]]
      then
        resource="$resource prefix"
      fi
      printf "%s $resource\n" CREATE WRITE
    done

    value=$(jq -r '."heartbeat.interval.ms" // "0"' <<< "$config")
    case "$connector_class" in
      MySqlCdcSource|SqlServerCdcSource)
        # Debezium legacy
        prefix=$(jq -r '."database.server.name" // empty' <<< "$config")
        echo "DESCRIBE_CONFIGS Cluster:kafka-cluster"
        printf "%s Topic:dbhistory.$prefix.lcc- prefix\n" READ CREATE WRITE
        echo "READ Group:$prefix-dbhistory"
        if [ "$value" != "0" ]
        then
          printf "%s Topic:__debezium-heartbeat.$prefix prefix\n" DESCRIBE CREATE WRITE
        fi
      ;;
      MySqlCdcSourceV2|SqlServerCdcSourceV2|MariaDbCdcSource|PostgresCdcSourceV2)
        # Debezium v2
        prefix=$(jq -r '."topic.prefix" // empty' <<< "$config")
        echo "DESCRIBE_CONFIGS Cluster:kafka-cluster"
        if [ "$connector_class" != "PostgresCdcSourceV2" ]
        then
          topic=$(jq -r '."schema.history.internal.kafka.topic" // empty' <<< "$config")
          if [ -n "$topic" ]
          then
            resource=$(get_ccloud_acl_topic_resource "$topic")
          else
            resource="Topic:dbhistory.$prefix.lcc- prefix"
          fi
          printf "%s $resource\n" READ CREATE WRITE
          echo "READ Group:$prefix-schemahistory"
        fi
        if [ "$value" != "0" ]
        then
          printf "%s Topic:__debezium-heartbeat-lcc- prefix\n" DESCRIBE CREATE WRITE
        fi
      ;;
      OracleCdcSource)
        # redo log topic ${connectorName}-${databaseName}-redo-log, prefixed with lcc-
        printf "%s Topic:lcc- prefix\n" CREATE READ WRITE
        echo "READ Group:lcc- prefix"
        topic=$(jq -r '."redo.log.topic.name" // empty' <<< "$config")
        if [ -n "$topic" ]
        then
          echo "READ $(get_ccloud_acl_topic_resource "$topic")"
        fi
        for topic in $(jq -r '.["table.topic.name.template", "lob.topic.name.template", "redo.log.corruption.topic"] // empty' <<< "$config")
        do
          resource=$(get_ccloud_acl_topic_resource "$topic")
          printf "%s $resource\n" CREATE WRITE
        done
      ;;
      OracleXStreamSource)
        prefix=$(jq -r '."topic.prefix" // empty' <<< "$config")
        echo "DESCRIBE_CONFIGS Cluster:kafka-cluster"
        printf "%s Topic:__orcl-schema-changes.$prefix.lcc- prefix\n" READ CREATE WRITE
        if [ "$value" != "0" ]
        then
          printf "%s Topic:__orcl-heartbeat.lcc- prefix\n" READ CREATE WRITE
        fi
        topic=$(jq -r '."signal.kafka.topic" // empty' <<< "$config")
        if [ -n "$topic" ]
        then
          echo "READ Topic:$topic"
          echo "READ Group:kafka-signal"
        fi
      ;;
    esac

    if [ "$(jq -r '."exactly.once.enabled" // "false"' <<< "$config")" == "true" ]
    then
      printf "%s Topic:connect-offsets-lcc- prefix\n" DESCRIBE CREATE READ WRITE
      printf "%s TransactionalId:transaction-lcc- prefix\n" DESCRIBE WRITE
    fi
  fi
}

# config keys that may name Kafka topics but are not covered by get_ccloud_connector_service_account_acls
# $1 = connector config as a JSON object
function get_ccloud_connector_uncovered_topic_keys() {
  jq -r 'to_entries[] | select(.key | test("topic")) | select(.key | test("^(topics|topics\\.regex|kafka\\.topic|couchbase\\.topic|redo\\.log\\.topic\\.name|state\\.topic\\.name|[a-z]+[0-9]+\\.topics?|topic\\.prefix|[a-z0-9]+\\.topic\\.prefix|errors\\.deadletterqueue\\.topic\\.name|reporter\\.(result|error)\\.topic\\.name|schema\\.history\\.internal\\.kafka\\.topic|table\\.topic\\.name\\.template|lob\\.topic\\.name\\.template|redo\\.log\\.corruption\\.topic|signal\\.kafka\\.topic|topic\\.creation\\..*)$") | not) | .key' <<< "$1" 2>/dev/null
}

# file where the service accounts created for fully managed connectors are recorded, one per line:
# <cluster id> <service account id> <connector name> <run id>
function get_ccloud_service_accounts_file() {
  get_kafka_docker_playground_dir
  ccloud_service_accounts_file="$KAFKA_DOCKER_PLAYGROUND_DIR/playground-ccloud-service-accounts"
}

# service account recorded for a connector of the cluster of the ccloud run (the last one created)
# $1 = connector name
function get_ccloud_connector_recorded_service_account() {
  get_ccloud_service_accounts_file
  if [ -f "$ccloud_service_accounts_file" ]
  then
    awk -v c="$(get_ccloud_kafka_cluster_id)" -v n="$1" '$1 == c && $3 == n {sa = $2} END {if (sa != "") print sa}' "$ccloud_service_accounts_file"
  fi
}

# service account of a fully managed connector: kafka.service.account.id of its config, or the one
# recorded when it was created
# $1 = connector name
function get_ccloud_connector_service_account() {
  local connector="$1"
  local service_account=""
  get_ccloud_connect
  if handle_ccloud_connect_rest_api "curl -s --request GET \"https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector/config\" --header \"authorization: Basic $authorization\"" > /dev/null 2>&1
  then
    if [ "$(jq -r '."kafka.auth.mode" // empty' <<< "$curl_output" 2>/dev/null)" == "SERVICE_ACCOUNT" ]
    then
      service_account=$(jq -r '."kafka.service.account.id" // empty' <<< "$curl_output" 2>/dev/null)
    else
      # the connector exists and uses an API key
      return 0
    fi
  fi
  if [ -z "$service_account" ]
  then
    service_account=$(get_ccloud_connector_recorded_service_account "$connector")
  fi
  echo "$service_account"
}

# delete a service account created for a fully managed connector: its ACLs on the cluster of the ccloud
# run first (deleting a service account does not delete them), then the service account
# $1 = service account id
function delete_ccloud_connector_service_account() {
  local service_account="$1"
  local principal permission operation resource pattern prefix
  log "❌ deleting service account $service_account and its ACLs"
  while IFS=$'\t' read -r principal permission operation resource pattern
  do
    if [ -n "$resource" ]
    then
      prefix=0
      if [ "$pattern" == "PREFIXED" ]
      then
        prefix=1
      fi
      ccloud_acl_request delete "User:$service_account" "$operation" "$resource" "$prefix" "$permission" 2> /dev/null || logwarn "❌ failed to delete ACL $permission $operation $resource ($pattern) of $service_account"
    fi
  done <<< "$(get_ccloud_acls "User:$service_account" 2>/dev/null)"
  log_confluent_command iam service-account delete "$service_account" --force
  confluent iam service-account delete "$service_account" --force > /dev/null 2>&1 || logwarn "❌ failed to delete service account $service_account"
  get_ccloud_service_accounts_file
  if [ -f "$ccloud_service_accounts_file" ]
  then
    awk -v s="$service_account" '$2 != s' "$ccloud_service_accounts_file" > "$ccloud_service_accounts_file.tmp"
    mv "$ccloud_service_accounts_file.tmp" "$ccloud_service_accounts_file"
  fi
}

# delete the service accounts recorded for the connectors of the cluster of the ccloud run, optionally
# only those of run $1, or of connector $2
function cleanup_ccloud_connector_service_accounts() {
  local run_id="$1"
  local connector="$2"
  local service_account
  get_ccloud_service_accounts_file
  if [ ! -f "$ccloud_service_accounts_file" ]
  then
    return 0
  fi
  for service_account in $(awk -v c="$(get_ccloud_kafka_cluster_id)" -v r="$run_id" -v n="$connector" '$1 == c && (r == "" || $4 == r) && (n == "" || $3 == n) {print $2}' "$ccloud_service_accounts_file" | sort -u)
  do
    delete_ccloud_connector_service_account "$service_account"
  done
}

# Switch the config of a fully managed or custom connector to kafka.auth.mode=SERVICE_ACCOUNT
# (playground run --ccloud-service-account, or PG_CCLOUD_SERVICE_ACCOUNT=true): on creation, create a
# service account for the connector, its ACLs (PG_CCLOUD_SERVICE_ACCOUNT_ACLS docs, full or none, minus
# the ones matching PG_CCLOUD_SERVICE_ACCOUNT_ACL_EXCLUDE) and the Assigner role binding of the owner of
# the Cloud API key creating the connector. PG_CCLOUD_SERVICE_ACCOUNT_ID uses an existing service account
# instead, as is. On update, the service account of the connector is kept.
# $1 = connector name, $2 = connector config as a JSON object, $3 = 1 when the connector is created
# sets json_content to the new config
function ccloud_connector_service_account_setup() {
  local connector="$1"
  local config="$2"
  local is_create="$3"
  local profile="${PG_CCLOUD_SERVICE_ACCOUNT_ACLS:-docs}"
  local exclude="${PG_CCLOUD_SERVICE_ACCOUNT_ACL_EXCLUDE}"
  local service_account="${PG_CCLOUD_SERVICE_ACCOUNT_ID}"
  local name
  local owner
  local acls
  local acl
  local uncovered_keys
  local run_id
  local operations resource prefix
  local pids=()
  local pid
  local failed=0

  json_content="$config"
  if [ "$(jq -r '."kafka.auth.mode" // empty' <<< "$config")" == "SERVICE_ACCOUNT" ]
  then
    log "👤 connector $connector config already sets kafka.auth.mode=SERVICE_ACCOUNT, keeping it"
    return 0
  fi
  case "$profile" in
    docs|full|none) ;;
    *)
      logerror "❌ PG_CCLOUD_SERVICE_ACCOUNT_ACLS should be docs, full or none (it is $profile)"
      return 1
    ;;
  esac

  if [ -z "$service_account" ] && [ "$is_create" != "1" ]
  then
    service_account=$(get_ccloud_connector_service_account "$connector")
    if [ -n "$service_account" ]
    then
      log "👤 keeping service account $service_account of connector $connector"
    fi
  fi

  if [ -n "$service_account" ]
  then
    if [ -n "${PG_CCLOUD_SERVICE_ACCOUNT_ID}" ]
    then
      log "👤 using service account $service_account for connector $connector, as is (no ACL created)"
    fi
  else
    # pg-<user>-conn-<connector>-<n>, at most 64 characters
    name="pg-${USER}-conn-$(tr -c 'a-zA-Z0-9_-' '-' <<< "$connector" | sed 's/-$//')"
    name="$(cut -c 1-57 <<< "$name")-$((RANDOM % 100000))"
    local create_command=(iam service-account create "$name" --description "Service account of fully managed connector $connector, created by kafka-docker-playground")
    log_confluent_command "${create_command[@]}"
    if ! service_account=$(confluent "${create_command[@]}" -o json | jq -r '.id // empty') || [ -z "$service_account" ]
    then
      logerror "❌ could not create service account $name"
      return 1
    fi
    run_id="${PG_CCLOUD_RUN_ID:-$(playground state get run.ccloud_run_id 2>/dev/null)}"
    get_ccloud_service_accounts_file
    echo "$(get_ccloud_kafka_cluster_id) $service_account $connector $run_id" >> "$ccloud_service_accounts_file"
    log "👤 created service account $service_account ($name) for connector $connector"

    # the principal creating a connector with a service account must hold the Assigner role on it
    owner=$(confluent api-key describe "$CONFLUENT_CLOUD_API_KEY" -o json 2>/dev/null | jq -r '(if type == "array" then .[0] else . end).owner // empty' 2>/dev/null)
    if [ -n "$owner" ]
    then
      log_confluent_command iam rbac role-binding create --principal "User:$owner" --role Assigner --resource "ServiceAccount:$service_account"
      if confluent iam rbac role-binding create --principal "User:$owner" --role Assigner --resource "ServiceAccount:$service_account" > /dev/null 2>&1
      then
        log "🎩 granted Assigner role on $service_account to User:$owner (owner of CONFLUENT_CLOUD_API_KEY)"
      else
        logwarn "🎩 could not grant Assigner role on $service_account to User:$owner (owner of CONFLUENT_CLOUD_API_KEY): connector creation fails if User:$owner does not hold it (OrgAdmin does)"
      fi
    else
      logwarn "🎩 could not find the owner of CONFLUENT_CLOUD_API_KEY: it must hold the Assigner role on $service_account (OrgAdmin does)"
    fi

    acls=$(get_ccloud_connector_service_account_acls "$config" "$profile" | awk '!seen[$0]++')
    if [ -n "$exclude" ] && [ -n "$acls" ]
    then
      while read -r acl
      do
        logwarn "🙈 not creating ACL $acl (PG_CCLOUD_SERVICE_ACCOUNT_ACL_EXCLUDE=$exclude)"
      done <<< "$(grep -E -- "$exclude" <<< "$acls")"
      acls=$(grep -Ev -- "$exclude" <<< "$acls")
    fi
    if [ -n "$acls" ]
    then
      log "🚦 creating the ACLs of service account $service_account ($profile profile), reproduce an error by removing one, e.g.:"
      log "   playground rbac acl delete --connector $connector --operation $(head -n 2 <<< "$acls" | tail -n 1 | awk '{print $1 " --resource " $2 ($3 == "prefix" ? " --prefix" : "")}')"
      # one confluent call per resource, concurrently
      while read -r operations resource prefix
      do
        ccloud_acl_request create "User:$service_account" "$operations" "$resource" "$([ "$prefix" == "prefix" ] && echo 1 || echo 0)" ALLOW &
        pids+=($!)
      done <<< "$(awk '{key = $2 " " $3; if (!(key in ops)) {order[++n] = key; ops[key] = $1} else ops[key] = ops[key] "," $1} END {for (i = 1; i <= n; i++) print ops[order[i]] " " order[i]}' <<< "$acls")"
      for pid in "${pids[@]}"
      do
        wait $pid || failed=1
      done
      if [ $failed -eq 1 ]
      then
        logerror "❌ could not create all the ACLs of service account $service_account"
        return 1
      fi
    else
      logwarn "🚦 no ACL created for service account $service_account ($profile profile): add them with playground rbac acl create --connector $connector"
    fi

    if [ "$profile" == "docs" ]
    then
      if grep -q ' Topic:\*$' <<< "$acls"
      then
        logwarn "🤔 a topic name of the config is a regex or starts with a template (\${...}): it can't be narrowed, the ACLs on Topic:* allow every topic"
      fi
      uncovered_keys=$(get_ccloud_connector_uncovered_topic_keys "$config" | paste -sd ',' - | sed 's/,/, /g')
      if [ -n "$uncovered_keys" ]
      then
        logwarn "🤔 these config keys may name Kafka topics that the ACLs don't cover: $uncovered_keys"
        logwarn "   if the connector fails with an authorization error, add the ACLs with playground rbac acl create --connector $connector, or use --ccloud-service-account-acls full"
      fi
    fi
  fi

  json_content=$(jq --arg sa "$service_account" 'del(."kafka.api.key", ."kafka.api.secret") + {"kafka.auth.mode": "SERVICE_ACCOUNT", "kafka.service.account.id": $sa}' <<< "$config")
}

# 0 when ACL $2 (<PERMISSION> <OPERATION> <ResourceType>:<name> <LITERAL|PREFIXED>, from get_ccloud_acls
# without principal) applies to the ACL $1 (<OPERATION> <ResourceType>:<name> [prefix])
function ccloud_acl_covers() {
  local expected_operation expected_resource expected_prefix
  local permission operation resource pattern
  read -r expected_operation expected_resource expected_prefix <<< "$1"
  read -r permission operation resource pattern <<< "$2"
  # READ, WRITE, DELETE and ALTER imply DESCRIBE, ALTER_CONFIGS implies DESCRIBE_CONFIGS
  if [[ "$operation" != "$expected_operation" ]] && [[ "$operation" != "ALL" ]] \
    && ! { [[ "$expected_operation" == "DESCRIBE" ]] && [[ " READ WRITE DELETE ALTER " == *" $operation "* ]]; } \
    && ! { [[ "$expected_operation" == "DESCRIBE_CONFIGS" ]] && [[ "$operation" == "ALTER_CONFIGS" ]]; }
  then
    return 1
  fi
  if [[ "${resource%%:*}" != "${expected_resource%%:*}" ]]
  then
    return 1
  fi
  local name="${resource#*:}"
  local expected_name="${expected_resource#*:}"
  if [[ "$pattern" == "PREFIXED" ]]
  then
    [[ "$expected_name" == "$name"* ]] && [[ "$expected_name" != "*" ]]
  elif [[ "$name" == "*" ]]
  then
    return 0
  else
    [[ "$expected_name" == "$name" ]] && [[ -z "$expected_prefix" ]]
  fi
}

# playground connector diagnose of a fully managed connector with kafka.auth.mode=SERVICE_ACCOUNT: the ACLs
# of the documentation that its service account misses, or that are denied
# $1 = connector name
function display_ccloud_connector_service_account_acl_check() {
  local connector="$1"
  local config
  local service_account
  local expected
  local actual
  local acl
  local line
  local allowed
  local denied
  local missing=""
  local denied_acls=""
  local denies=""
  get_ccloud_connect
  if ! handle_ccloud_connect_rest_api "curl -s --request GET \"https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector/config\" --header \"authorization: Basic $authorization\"" > /dev/null 2>&1
  then
    return 0
  fi
  config="$curl_output"
  if [ "$(jq -r '."kafka.auth.mode" // empty' <<< "$config" 2>/dev/null)" != "SERVICE_ACCOUNT" ]
  then
    return 0
  fi
  service_account=$(jq -r '."kafka.service.account.id" // empty' <<< "$config")
  echo ""
  log "🚦 service account $service_account: ACLs of the documentation (https://docs.confluent.io/cloud/current/connectors/service-account.html)"
  if ! actual=$(get_ccloud_acls "User:$service_account" | cut -f 2-)
  then
    logwarn "could not list the ACLs of $service_account"
    return 0
  fi
  expected=$(get_ccloud_connector_service_account_acls "$config" docs | awk '!seen[$0]++')
  while read -r acl
  do
    allowed=0
    denied=0
    while read -r line
    do
      if [ -n "$line" ] && ccloud_acl_covers "$acl" "$line"
      then
        if [[ "$line" == DENY* ]]
        then
          denied=1
          denies="$denies$line"$'\n'
        else
          allowed=1
        fi
      fi
    done <<< "$actual"
    if [ $denied -eq 1 ]
    then
      denied_acls="$denied_acls$acl"$'\n'
    fi
    if [ $allowed -eq 0 ]
    then
      missing="$missing$acl"$'\n'
    fi
  done <<< "$expected"

  if [ -z "$missing" ] && [ -z "$denied_acls" ]
  then
    log "✅ the $(wc -l <<< "$expected" | tr -d ' ') ACLs the connector needs are allowed"
    return 0
  fi
  while read -r acl
  do
    if [ -n "$acl" ]
    then
      logwarn "❌ missing: $acl"
    fi
  done <<< "$missing"
  while read -r acl
  do
    if [ -n "$acl" ]
    then
      logwarn "⛔ denied: $acl"
    fi
  done <<< "$denied_acls"
  if [ -n "$missing" ]
  then
    echo "   🔧 to create the missing ACLs:"
    while read -r acl
    do
      if [ -n "$acl" ]
      then
        awk -v c="$connector" '{print "   playground rbac acl create --connector " c " --operation " $1 " --resource " $2 ($3 == "prefix" ? " --prefix" : "")}' <<< "$acl"
      fi
    done <<< "$missing"
  fi
  if [ -n "$denies" ]
  then
    echo "   🔧 to delete the DENY ACLs:"
    sort -u <<< "$denies" | while read -r permission operation resource pattern
    do
      if [ -n "$resource" ]
      then
        echo "   playground rbac acl delete --connector $connector --deny --operation $operation --resource $resource$([ "$pattern" == "PREFIXED" ] && echo " --prefix")"
      fi
    done
  fi
}

# principal of playground rbac acl on a ccloud run: --principal, or the service account of the fully
# managed --connector
# sets principal
function get_ccloud_rbac_acl_principal() {
  local connector="${args[--connector]}"
  local service_account
  principal="${args[--principal]}"
  if [[ -n "$connector" ]] && [[ -n "$principal" ]]
  then
    logerror "❌ --connector and --principal can't be both set"
    return 1
  fi
  if [[ -n "$connector" ]]
  then
    service_account=$(get_ccloud_connector_service_account "$connector")
    if [ -z "$service_account" ]
    then
      logerror "❌ connector $connector does not use a service account (kafka.auth.mode=SERVICE_ACCOUNT), run the example with playground run --ccloud-service-account"
      return 1
    fi
    principal="User:$service_account"
  elif [[ -n "$principal" ]]
  then
    principal=$(normalize_rbac_principal "$principal")
  fi
}

# playground rbac acl create|delete on a ccloud run: Confluent Cloud ACL (confluent kafka acl)
# usage: ccloud_rbac_acl <create|delete>
function ccloud_rbac_acl() {
  local action="$1"
  local resource="${args[--resource]}"
  local permission="ALLOW"
  local prefix=0
  local principal
  local resource_type
  local resource_name
  local operation
  local operations=""
  eval "local operation_list=(${args[--operation]})"

  if [[ -n "${args[--kafka-acls]}" ]] || [[ -n "${args[--host]}" ]]
  then
    logerror "❌ --kafka-acls and --host are not supported with Confluent Cloud"
    return 1
  fi
  get_ccloud_rbac_acl_principal || return 1
  if [[ -z "$principal" ]]
  then
    logerror "❌ --principal or --connector is required"
    return 1
  fi
  parse_rbac_resource "$resource" || return 1
  if [[ -n "${args[--deny]}" ]]
  then
    permission="DENY"
  fi
  if [[ -n "${args[--prefix]}" ]]
  then
    prefix=1
  fi
  for operation in "${operation_list[@]}"
  do
    operations="${operations:+$operations,}$operation"
  done
  if [ "$action" == "create" ]
  then
    log "🚦 Creating Confluent Cloud ACL $permission $operations for $principal on $resource_type:$resource_name$([ $prefix -eq 1 ] && echo " (prefixed)")"
  else
    log "🗑️ Deleting Confluent Cloud ACL $permission $operations for $principal on $resource_type:$resource_name$([ $prefix -eq 1 ] && echo " (prefixed)")"
  fi
  ccloud_acl_request "$action" "$principal" "$operations" "$resource_type:$resource_name" "$prefix" "$permission" || return 1
  if [[ -n "${args[--connector]}" ]]
  then
    log "🎓 an ACL change takes up to a minute to be applied, then restart the connector: playground connector restart --connector ${args[--connector]}"
  fi
}

rbac_ldap_base_dn="dc=confluentdemo,dc=io"

# run an LDAP client command (ldapsearch, ldapadd, ldapmodify, ldapdelete) as LDAP admin in the
# openldap container of rbac-sasl-plain, stdin is forwarded
# usage: rbac_ldap <command> [arguments]
function rbac_ldap() {
  local ldap_command="$1"
  shift
  local output
  output=$(playground container exec -c openldap --command "$ldap_command -x -H ldap://localhost -D cn=admin,$rbac_ldap_base_dn -w admin $*" 2>&1)
  local ret=$?
  # drop the "Executing command in container" line of playground container exec
  grep -v "Executing command in container" <<< "$output"
  return $ret
}

# kcadm.sh of the keycloak container of the rbac-oauth environment, logged in as admin of the master realm.
# Arguments are passed to kcadm.sh, stdin is forwarded (create ... -f -)
function rbac_keycloak() {
  if [[ -z "$rbac_keycloak_logged_in" ]]
  then
    if ! docker exec keycloak /opt/keycloak/bin/kcadm.sh config credentials --config /tmp/kcadm.config --server http://localhost:8080 --realm master --user admin --password admin > /dev/null 2>&1
    then
      logerror "❌ could not log in to keycloak as admin, is the rbac-oauth environment running?"
      return 1
    fi
    rbac_keycloak_logged_in=1
  fi
  docker exec -i keycloak /opt/keycloak/bin/kcadm.sh "$@" --config /tmp/kcadm.config
}

# Keycloak client of the rbac-oauth environment (same as keycloak/kafka-realm.json): confidential, client_credentials
# grant (service account), audience kafka and groups claim in its tokens
# usage: rbac_keycloak_client_json <client id> <secret>
function rbac_keycloak_client_json() {
  jq -n --arg id "$1" --arg secret "$2" '{
    clientId: $id, name: $id, enabled: true, protocol: "openid-connect", publicClient: false,
    clientAuthenticatorType: "client-secret", secret: $secret, serviceAccountsEnabled: true,
    standardFlowEnabled: false, implicitFlowEnabled: false, directAccessGrantsEnabled: false,
    protocolMappers: [
      {name: "kafka-audience", protocol: "openid-connect", protocolMapper: "oidc-audience-mapper", consentRequired: false,
       config: {"included.custom.audience": "kafka", "access.token.claim": "true", "id.token.claim": "false", "introspection.token.claim": "true"}},
      {name: "groups", protocol: "openid-connect", protocolMapper: "oidc-group-membership-mapper", consentRequired: false,
       config: {"claim.name": "groups", "full.path": "false", "access.token.claim": "true", "id.token.claim": "false", "introspection.token.claim": "true", "userinfo.token.claim": "false"}}
    ]}'
}

# internal id of the Keycloak client <client id> of the realm kafka, empty if it does not exist
function rbac_keycloak_client_uuid() {
  rbac_keycloak get clients -r kafka -q "clientId=$1" --fields id,clientId | jq -r --arg id "$1" '.[] | select(.clientId == $id) | .id'
}

function filter_plaintext_or_ccloud_environment() {
  get_environment_used

  if [[ "$environment" != "ccloud" ]] && [[ "$environment" != "plaintext" ]]
  then
    logerror "environment should be plaintext or ccloud with this command (it is $environment)!"
  fi
}

function filter_schema_registry_running() {
  # bashly runs filters in $(...) under set -e: without this trap, an exit 1 in get_sr_url_and_security ends the cli
  # before bashly prints the error message
  trap 'exit 0' EXIT
  if is_mdc_environment
  then
    # get_mdc_cluster prints its error on stderr: make it the error of the filter
    local mdc_error
    mdc_error=$( (get_mdc_cluster) 2>&1 > /dev/null )
    if [[ -n "$mdc_error" ]]
    then
      echo "$mdc_error"
      return
    fi
    # mdc-kerberos has no usable Schema Registry: schema-registry-us / -europe come from the mdc-plaintext compose file,
    # bootstrap on broker-<cluster>:9092 without SASL and restart in a loop. topic produce / consume of plain string values
    # don't need one: let them run (the replicator Kerberos examples)
    if [[ "$environment" == "mdc-kerberos" ]] && { [[ "$action" == "topic produce" ]] || [[ "$action" == "topic consume" ]]; }
    then
      return
    fi
  fi
  get_sr_url_and_security

  local sr_ok=0
  for i in {1..30}; do
    if curl $sr_security -s "${sr_url}/config" > /dev/null 2>&1; then
      sr_ok=1
      break
    fi
    sleep 1
  done

  if [ $sr_ok == 0 ]; then
    logerror "schema registry rest api should be running to run this command"
  fi
}

function filter_oracle_running() {
  docker ps --filter "name=oracle" --filter "status=running" --format "{{.Names}}" | grep -q "oracle"
  if [ $? != 0 ]; then
    logerror "oracle docker container should be running to run this command"
  fi
}

function filter_connect_running() {
  # bashly runs filters in $(...) under set -e: without this trap, an exit 1 in get_connect_url_and_security ends the
  # cli before bashly prints the error message
  trap 'exit 0' EXIT
  # fully managed and custom connectors run in Confluent Cloud, not on a local worker
  local connector_type
  connector_type=$(playground state get run.connector_type)
  if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
  then
    return 0
  fi
  get_connect_url_and_security

  curl $security -s "${connect_url}" > /dev/null 2>&1
  if [ $? != 0 ]
  then
    logerror "connect rest api should be running to run this command"
  fi
}

function filter_flink_running() {
  local flink_ok=0
  get_flink_environment
  if [[ "$flink_environment" == "ccloud" ]]; then
    # Confluent Cloud statements: checked by get_ccloud_flink_context (confluent CLI logged in, compute pool)
    return
  fi
  # only wait for a jobmanager that is starting, not when there is none
  if get_flink_rest_url; then
    for i in {1..10}; do
      if curl -s -f "${flink_rest_url}/overview" > /dev/null 2>&1; then
        flink_ok=1
        break
      fi
      sleep 1
    done
  fi

  if [ $flink_ok == 0 ]; then
    logerror "flink jobmanager rest api should be running to run this command: start an example with playground run --enable-flink (or pass --environment ccloud for the statements of a Confluent Cloud compute pool)"
  fi
}

function filter_ksqldb_running() {
  if ! get_ksqldb_url_and_security; then
    logerror "ksqldb-server should be running to run this command: start an example with playground run --enable-ksqldb (the ksqldb/ examples enable it)"
    return
  fi
  # right after start-environment, ksqldb-server can still be starting: wait for it, 120 seconds at most
  local status="" i
  for i in {1..120}; do
    status=$(curl $ksqldb_security -s -f "${ksqldb_url}/info" 2>/dev/null | jq -r '.KsqlServerInfo.serverStatus // empty' 2>/dev/null)
    if [[ "$status" == "RUNNING" ]]; then
      return
    fi
    if [ $i -eq 5 ]; then
      log "⏳ waiting for ksqldb-server to be ready ($ksqldb_url)" >&2
    fi
    sleep 1
  done
  logerror "ksqldb-server REST API $ksqldb_url is not ready after 120 seconds (server status: ${status:-no answer}): check playground container logs -c ksqldb-server --errors"
}

function filter_docker_running() {
  # doctor is precisely the command you run when the engine is down (and the switch
  # commands are how you leave an engine that is down), and a bare
  # `playground` should still be able to print its help, so do not gate those.
  # state and config only read and write playground.ini, they never talk to the
  # engine, and several commands call them recursively - gating them only turned
  # one failure into two identical error messages.
  # $action is the sub-command, set by bashly before the filters are evaluated.
  # nested commands set it to "state get", "config set", ... hence the globs.
  case "${action:-}" in
    doctor|help|""|state|state\ *|config|config\ *|switch-podman|switch-docker)
      return 0
    ;;
  esac
  docker info >/dev/null 2>&1 || logerror "container engine must be running - run 'playground doctor'"
}

function filter_aws_ec2_permissions() {
  aws ec2 describe-instances --dry-run > /tmp/output_ec2_describe_instance.log 2>&1
  if ! grep -q "DryRunOperation" /tmp/output_ec2_describe_instance.log
  then
    logerror "aws ec2 describe-instances command got an error"
    logerror "please make sure to have AdministratorAccess in aws"
    cat /tmp/output_ec2_describe_instance.log
  fi
}

#
# GitHub Codespaces (playground codespace): a thin layer over 'gh codespace'
#

# repository the codespaces are created from (PLAYGROUND_CODESPACE_REPO for a fork)
function codespace_repo() {
  echo "${PLAYGROUND_CODESPACE_REPO:-vdesabou/kafka-docker-playground}"
}

# bashly filter of 'playground codespace': gh installed, logged in, with the codespace scope
function filter_gh_codespace() {
  if ! command -v gh > /dev/null 2>&1
  then
    logerror "❌ the GitHub CLI (gh) is required: https://cli.github.com"
    return
  fi
  local status
  if ! status=$(gh auth status --active -h github.com 2>&1)
  then
    logerror "❌ gh is not logged in to github.com: run 'gh auth login'"
    return
  fi
  # a token from GH_TOKEN / GITHUB_TOKEN shows no scopes: let gh itself report what is missing
  if echo "$status" | grep -qi "token scopes" && ! echo "$status" | grep -i "token scopes" | grep -q "'codespace'"
  then
    logerror "❌ the gh token is missing the 'codespace' scope: run 'gh auth refresh -h github.com -s codespace'"
  fi
}

# json of your codespaces of the repository, most recently used first
function codespace_list_json() {
  gh codespace list -R "$(codespace_repo)" --json name,displayName,state,machineName,lastUsedAt,gitStatus 2> /dev/null \
    | jq 'sort_by(.lastUsedAt) | reverse'
}

# names of your codespaces of the repository, most recently used first
function codespace_names() {
  codespace_list_json | jq -r '.[].name' 2> /dev/null
}

# state of a codespace: Available, Shutdown, ShuttingDown, Starting, Queued, Provisioning…
function codespace_state() {
  gh api "user/codespaces/$1" --jq .state 2> /dev/null
}

# waits until a codespace reaches a state (default timeout 300 seconds); prints the last state seen
function codespace_wait_state() {
  local codespace="$1" target="$2" timeout="${3:-300}" state="" waited=0
  while [ $waited -lt "$timeout" ]
  do
    state=$(codespace_state "$codespace")
    if [ "$state" == "$target" ]
    then
      echo "$state"
      return 0
    fi
    sleep 5
    waited=$((waited+5))
  done
  echo "$state"
  return 1
}

#
# Waits until ssh into a codespace works (default timeout 300 seconds).
#
# A codespace is Available as soon as its machine runs, but its container (and
# the SSH server in it) is still being built for a minute or two: an ssh then
# fails with "failed to invoke SSH RPC: ... context deadline exceeded".
#
function codespace_wait_ssh() {
  local codespace="$1" timeout="${2:-300}" start=$SECONDS logged=""
  while [ $((SECONDS-start)) -lt "$timeout" ]
  do
    if gh codespace ssh -c "$codespace" -- true > /dev/null 2>&1
    then
      return 0
    fi
    if [ -z "$logged" ]
    then
      log "⏳ waiting for the SSH server of codespace $codespace (its container may still be starting)"
      logged=1
    fi
    sleep 10
  done
  logerror "❌ could not ssh into codespace $codespace after $timeout seconds"
  logerror "👉 a codespace created before the SSH server was added to .devcontainer/, or from an older prebuild, has none: rebuild it with 'gh codespace rebuild -c $codespace' (/workspaces is kept, the home directory is emptied)"
  return 1
}

# folder of the repository in a codespace
function codespace_remote_root() {
  echo "/workspaces/$(basename "$(codespace_repo)")"
}

#
# OpenSSH config of a codespace, for the tools that need a plain ssh (rsync -e):
# 'gh codespace ssh --config' prints a Host entry whose ProxyCommand goes through
# gh's own authenticated tunnel. Writes it to a temporary file and prints
# "<config file> <host>"; the caller removes the file.
#
function codespace_ssh_config() {
  local codespace="$1" cfg host
  cfg=$(mktemp)
  if ! gh codespace ssh --config -c "$codespace" > "$cfg" 2> /dev/null
  then
    rm -f "$cfg"
    return 1
  fi
  host=$(awk '/^Host /{print $2; exit}' "$cfg")
  if [ -z "$host" ]
  then
    rm -f "$cfg"
    return 1
  fi
  echo "$cfg $host"
}

# the codespace to act on: the one given, else the most recently used one
function codespace_pick() {
  local codespace="$1"
  if [ -n "$codespace" ]
  then
    echo "$codespace"
    return 0
  fi
  local names
  names=$(codespace_names)
  if [ -z "$names" ]
  then
    logerror "💤 no codespace of $(codespace_repo) was found: create one with 'playground codespace create'" >&2
    return 1
  fi
  codespace=$(echo "$names" | head -1)
  if [ "$(echo "$names" | wc -l | tr -d ' ')" -gt 1 ]
  then
    logwarn "☁️ several codespaces, using the most recently used one: $codespace (--codespace to pick another)" >&2
  fi
  echo "$codespace"
}

function increment_cli_metric() {
  metric_name="$1"
  metric=$(playground state get "metrics.$metric_name")
  if [ "$metric" == "" ]
  then
    # initialize
    playground state set "metrics.$metric_name" 1
  else
    playground state set "metrics.$metric_name" $((metric+1))
  fi
}

function get_cli_metric() {
  metric_name="$1"
  playground state get "metrics.$metric_name"
}

function set_cli_metric() {
  metric_name="$1"
  metric_value="$2"
  playground state set "metrics.$metric_name" "$metric_value"
}

function add_connector_config_based_on_environment () {
  environment="$1"
  json_content="$2"

  echo "$json_content" > $tmp_dir/1.json

  if [ -n "$AWS_SHORT_LIVE_CREDENTIALS_USED" ]
  then
    log "💫 removing aws.access.key.id and aws.secret.access.key from config"
    echo "$json_content" > $tmp_dir/input.json
    jq 'del(.["aws.access.key.id"], .["aws.secret.access.key"])' $tmp_dir/input.json > $tmp_dir/output.json
    json_content=$(cat $tmp_dir/output.json)
  fi

  case "${environment}" in
    plaintext)
      # nothing to do
      return
    ;;
    ccloud)
      if [ -f $root_folder/.ccloud/env.delta ]
      then
          source $root_folder/.ccloud/env.delta
      else
          logerror "❌ $root_folder/.ccloud/env.delta has not been generated"
          exit 1
      fi

      echo "$json_content" > $tmp_dir/input.json
      jq ".[\"topic.creation.default.replication.factor\"] = \"-1\" | .[\"topic.creation.default.partitions\"] = \"-1\"" $tmp_dir/input.json > $tmp_dir/output.json
      json_content=$(cat $tmp_dir/output.json)

      for prefix in {"confluent.topic","redo.log.consumer"}
      do
        if echo "$json_content" | jq ". | has(\"$prefix.bootstrap.servers\")" 2> /dev/null | grep -q true 
        then
          # log "replacing $prefix config for environment $environment"

          echo "$json_content" > $tmp_dir/input.json
          jq ".[\"$prefix.bootstrap.servers\"] = \"\${file:/datacloud:bootstrap.servers}\" | .[\"$prefix.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"\${file:/datacloud:sasl.username}\\\" password=\\\"\${file:/datacloud:sasl.password}\\\";\" | .[\"$prefix.security.protocol\"] = \"SASL_SSL\" | .[\"$prefix.sasl.mechanism\"] = \"PLAIN\"" $tmp_dir/input.json > $tmp_dir/output.json
          json_content=$(cat $tmp_dir/output.json)

          if [ "$prefix" == "confluent.topic" ]
          then
            echo "$json_content" > $tmp_dir/input.json
            jq ".[\"confluent.topic.replication.factor\"] = \"3\"" $tmp_dir/input.json > $tmp_dir/output.json
            json_content=$(cat $tmp_dir/output.json)
          fi
        fi
      done

      for prefix in {"key","value"}
      do
        if echo "$json_content" | jq ". | has(\"$prefix.converter.schema.registry.url\")" 2> /dev/null | grep -q true 
        then
          # log "replacing $prefix.converter.schema.registry.url config for environment $environment"

          echo "$json_content" > $tmp_dir/input.json
          jq ".[\"$prefix.converter.schema.registry.url\"] = \"$SCHEMA_REGISTRY_URL\" | .[\"$prefix.converter.basic.auth.user.info\"] = \"\${file:/datacloud:schema.registry.basic.auth.user.info}\" | .[\"$prefix.converter.basic.auth.credentials.source\"] = \"USER_INFO\"" $tmp_dir/input.json > $tmp_dir/output.json
          json_content=$(cat $tmp_dir/output.json)
        fi
      done

      if echo "$json_content" | jq ". | has(\"database.history.kafka.bootstrap.servers\")" 2> /dev/null | grep -q true 
      then
        # log "replacing database.history.kafka.bootstrap.servers config for environment $environment"

        echo "$json_content" > $tmp_dir/input.json
        jq ".[\"database.history.kafka.bootstrap.servers\"] = \"\${file:/datacloud:bootstrap.servers}\" | .[\"database.history.producer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"\${file:/datacloud:sasl.username}\\\" password=\\\"\${file:/datacloud:sasl.password}\\\";\" | .[\"database.history.producer.security.protocol\"] = \"SASL_SSL\" | .[\"database.history.producer.sasl.mechanism\"] = \"PLAIN\" | .[\"database.history.consumer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"\${file:/datacloud:sasl.username}\\\" password=\\\"\${file:/datacloud:sasl.password}\\\";\" | .[\"database.history.consumer.security.protocol\"] = \"SASL_SSL\" | .[\"database.history.consumer.sasl.mechanism\"] = \"PLAIN\"" $tmp_dir/input.json > $tmp_dir/output.json
        json_content=$(cat $tmp_dir/output.json)
      fi

      if echo "$json_content" | jq ". | has(\"schema.history.internal.kafka.bootstrap.servers\")" 2> /dev/null | grep -q true 
      then
        # log "replacing schema.history.internal.kafka.bootstrap.servers config for environment $environment"

        echo "$json_content" > $tmp_dir/input.json
        jq ".[\"schema.history.internal.kafka.bootstrap.servers\"] = \"\${file:/datacloud:bootstrap.servers}\" | .[\"schema.history.internal.producer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"\${file:/datacloud:sasl.username}\\\" password=\\\"\${file:/datacloud:sasl.password}\\\";\" | .[\"schema.history.internal.producer.security.protocol\"] = \"SASL_SSL\" | .[\"schema.history.internal.producer.sasl.mechanism\"] = \"PLAIN\" | .[\"schema.history.internal.consumer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"\${file:/datacloud:sasl.username}\\\" password=\\\"\${file:/datacloud:sasl.password}\\\";\" | .[\"schema.history.internal.consumer.security.protocol\"] = \"SASL_SSL\" | .[\"schema.history.internal.consumer.sasl.mechanism\"] = \"PLAIN\"" $tmp_dir/input.json > $tmp_dir/output.json
        json_content=$(cat $tmp_dir/output.json)
      fi

      if echo "$json_content" | jq ". | has(\"reporter.bootstrap.servers\")" 2> /dev/null | grep -q true 
      then
        # log "replacing reporter.bootstrap.servers config for environment $environment"

        echo "$json_content" > $tmp_dir/input.json
        jq ".[\"reporter.bootstrap.servers\"] = \"\${file:/datacloud:bootstrap.servers}\" | .[\"reporter.result.topic.replication.factor\"] = \"3\" | .[\"reporter.error.topic.replication.factor\"] = \"3\" | .[\"reporter.admin.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"\${file:/datacloud:sasl.username}\\\" password=\\\"\${file:/datacloud:sasl.password}\\\";\" | .[\"reporter.admin.security.protocol\"] = \"SASL_SSL\" | .[\"reporter.admin.sasl.mechanism\"] = \"PLAIN\" | .[\"reporter.producer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"\${file:/datacloud:sasl.username}\\\" password=\\\"\${file:/datacloud:sasl.password}\\\";\" | .[\"reporter.producer.security.protocol\"] = \"SASL_SSL\" | .[\"reporter.producer.sasl.mechanism\"] = \"PLAIN\"" $tmp_dir/input.json > $tmp_dir/output.json
        json_content=$(cat $tmp_dir/output.json)
      fi
    ;;

    sasl-plain|ldap-authorizer-sasl-plain|ldap-sasl-plain)

      for prefix in {"confluent.topic","redo.log.consumer"}
      do
        if echo "$json_content" | jq ". | has(\"$prefix.bootstrap.servers\")" 2> /dev/null | grep -q true 
        then
          # log "replacing $prefix config for environment $environment"

          echo "$json_content" > $tmp_dir/input.json
          jq ".[\"$prefix.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"client\\\" password=\\\"client-secret\\\";\" | .[\"$prefix.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"$prefix.sasl.mechanism\"] = \"PLAIN\"" $tmp_dir/input.json > $tmp_dir/output.json
          json_content=$(cat $tmp_dir/output.json)
        fi
      done

      if echo "$json_content" | jq ". | has(\"database.history.kafka.bootstrap.servers\")" 2> /dev/null | grep -q true 
      then
        # log "replacing database.history.kafka.bootstrap.servers config for environment $environment"

        echo "$json_content" > $tmp_dir/input.json
        jq ".[\"database.history.producer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"client\\\" password=\\\"client-secret\\\";\" | .[\"database.history.producer.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"database.history.producer.sasl.mechanism\"] = \"PLAIN\" | .[\"database.history.consumer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"client\\\" password=\\\"client-secret\\\";\" | .[\"database.history.consumer.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"database.history.consumer.sasl.mechanism\"] = \"PLAIN\"" $tmp_dir/input.json > $tmp_dir/output.json
        json_content=$(cat $tmp_dir/output.json)
      fi

      if echo "$json_content" | jq ". | has(\"schema.history.internal.kafka.bootstrap.servers\")" 2> /dev/null | grep -q true 
      then
        # log "replacing schema.history.internal.kafka.bootstrap.servers config for environment $environment"

        echo "$json_content" > $tmp_dir/input.json
        jq ".[\"schema.history.internal.producer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"client\\\" password=\\\"client-secret\\\";\" | .[\"schema.history.internal.producer.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"schema.history.internal.producer.sasl.mechanism\"] = \"PLAIN\" | .[\"schema.history.internal.consumer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"client\\\" password=\\\"client-secret\\\";\" | .[\"schema.history.internal.consumer.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"schema.history.internal.consumer.sasl.mechanism\"] = \"PLAIN\"" $tmp_dir/input.json > $tmp_dir/output.json
        json_content=$(cat $tmp_dir/output.json)
      fi

      if echo "$json_content" | jq ". | has(\"reporter.bootstrap.servers\")" 2> /dev/null | grep -q true 
      then
        # log "replacing reporter.bootstrap.servers config for environment $environment"

        echo "$json_content" > $tmp_dir/input.json
        jq ".[\"reporter.admin.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"client\\\" password=\\\"client-secret\\\";\" | .[\"reporter.admin.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"reporter.admin.sasl.mechanism\"] = \"PLAIN\" | .[\"reporter.producer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"client\\\" password=\\\"client-secret\\\";\" | .[\"reporter.producer.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"reporter.producer.sasl.mechanism\"] = \"PLAIN\"" $tmp_dir/input.json > $tmp_dir/output.json
        json_content=$(cat $tmp_dir/output.json)
      fi
    ;;

    sasl-oauthbearer)
      # the connector's own Kafka clients log in to Keycloak (environment/sasl-oauthbearer) as the client "client"
      local oauth_keys='.["PREFIX.security.protocol"] = "SASL_PLAINTEXT" | .["PREFIX.sasl.mechanism"] = "OAUTHBEARER" | .["PREFIX.sasl.login.callback.handler.class"] = "org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginCallbackHandler" | .["PREFIX.sasl.oauthbearer.token.endpoint.url"] = "http://keycloak:8080/realms/kafka/protocol/openid-connect/token" | .["PREFIX.sasl.jaas.config"] = "org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required clientId=\"client\" clientSecret=\"client-secret\";"'
      local oauth_marker oauth_prefixes oauth_prefix
      for oauth_marker in "confluent.topic.bootstrap.servers:confluent.topic" "redo.log.consumer.bootstrap.servers:redo.log.consumer" "database.history.kafka.bootstrap.servers:database.history.producer database.history.consumer" "schema.history.internal.kafka.bootstrap.servers:schema.history.internal.producer schema.history.internal.consumer" "reporter.bootstrap.servers:reporter.admin reporter.producer"
      do
        if echo "$json_content" | jq -e ". | has(\"${oauth_marker%%:*}\")" > /dev/null 2>&1
        then
          oauth_prefixes="${oauth_marker#*:}"
          for oauth_prefix in $(echo "$oauth_prefixes")
          do
            json_content=$(echo "$json_content" | jq "${oauth_keys//PREFIX/$oauth_prefix}")
          done
        fi
      done
    ;;

    sasl-ssl)
      get_broker_container
      for prefix in {"confluent.topic","redo.log.consumer"}
      do
        if echo "$json_content" | jq ". | has(\"$prefix.bootstrap.servers\")" 2> /dev/null | grep -q true 
        then
          # log "replacing $prefix config for environment $environment"

          echo "$json_content" > $tmp_dir/input.json
          jq ".[\"$prefix.bootstrap.servers\"] = \"$broker_container:9092\" | .[\"$prefix.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"client\\\" password=\\\"client-secret\\\";\" | .[\"$prefix.security.protocol\"] = \"SASL_SSL\" | .[\"$prefix.sasl.mechanism\"] = \"PLAIN\" | .[\"$prefix.ssl.truststore.location\"] = \"/etc/kafka/secrets/kafka.connect.truststore.jks\" | .[\"$prefix.ssl.truststore.password\"] = \"confluent\"" $tmp_dir/input.json > $tmp_dir/output.json
          json_content=$(cat $tmp_dir/output.json)
        fi
      done

      for prefix in {"key","value"}
      do
        if echo "$json_content" | jq ". | has(\"$prefix.converter.schema.registry.url\")" 2> /dev/null | grep -q true 
        then
          # log "replacing $prefix.converter.schema.registry.url config for environment $environment"

          echo "$json_content" > $tmp_dir/input.json
          jq ".[\"$prefix.converter.schema.registry.url\"] = \"https://schema-registry:8081\" | .[\"$prefix.converter.schema.registry.ssl.truststore.location\"] = \"/etc/kafka/secrets/kafka.connect.truststore.jks\" | .[\"$prefix.converter.schema.registry.ssl.truststore.password\"] = \"confluent\" | .[\"$prefix.converter.schema.registry.ssl.keystore.location\"] = \"/etc/kafka/secrets/kafka.connect.keystore.jks\" | .[\"$prefix.converter.schema.registry.ssl.keystore.password\"] = \"confluent\" | .[\"$prefix.converter.schema.registry.ssl.key.password\"] = \"confluent\"" $tmp_dir/input.json > $tmp_dir/output.json
          json_content=$(cat $tmp_dir/output.json)
        fi
      done

      if echo "$json_content" | jq ". | has(\"database.history.kafka.bootstrap.servers\")" 2> /dev/null | grep -q true 
      then
        # log "replacing database.history.kafka.bootstrap.servers config for environment $environment"

        echo "$json_content" > $tmp_dir/input.json
        jq ".[\"database.history.kafka.bootstrap.servers\"] = \"$broker_container:9092\" | .[\"database.history.producer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"client\\\" password=\\\"client-secret\\\";\" | .[\"database.history.producer.security.protocol\"] = \"SASL_SSL\" | .[\"database.history.producer.sasl.mechanism\"] = \"PLAIN\" | .[\"database.history.consumer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"client\\\" password=\\\"client-secret\\\";\" | .[\"database.history.consumer.security.protocol\"] = \"SASL_SSL\" | .[\"database.history.consumer.sasl.mechanism\"] = \"PLAIN\" | .[\"database.history.producer.ssl.truststore.location\"] = \"/etc/kafka/secrets/kafka.connect.truststore.jks\" | .[\"database.history.producer.ssl.truststore.password\"] = \"confluent\" | .[\"database.history.consumer.ssl.truststore.location\"] = \"/etc/kafka/secrets/kafka.connect.truststore.jks\" | .[\"database.history.consumer.ssl.truststore.password\"] = \"confluent\"" $tmp_dir/input.json > $tmp_dir/output.json
        json_content=$(cat $tmp_dir/output.json)
      fi

      if echo "$json_content" | jq ". | has(\"schema.history.internal.kafka.bootstrap.servers\")" 2> /dev/null | grep -q true 
      then
        # log "replacing schema.history.internal.kafka.bootstrap.servers config for environment $environment"

        echo "$json_content" > $tmp_dir/input.json
        jq ".[\"schema.history.internal.kafka.bootstrap.servers\"] = \"$broker_container:9092\" | .[\"schema.history.internal.producer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"client\\\" password=\\\"client-secret\\\";\" | .[\"schema.history.internal.producer.security.protocol\"] = \"SASL_SSL\" | .[\"schema.history.internal.producer.sasl.mechanism\"] = \"PLAIN\" | .[\"schema.history.internal.consumer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"client\\\" password=\\\"client-secret\\\";\" | .[\"schema.history.internal.consumer.security.protocol\"] = \"SASL_SSL\" | .[\"schema.history.internal.consumer.sasl.mechanism\"] = \"PLAIN\" | .[\"schema.history.internal.producer.ssl.truststore.location\"] = \"/etc/kafka/secrets/kafka.connect.truststore.jks\" | .[\"schema.history.internal.producer.ssl.truststore.password\"] = \"confluent\" | .[\"schema.history.internal.consumer.ssl.truststore.location\"] = \"/etc/kafka/secrets/kafka.connect.truststore.jks\" | .[\"schema.history.internal.consumer.ssl.truststore.password\"] = \"confluent\"" $tmp_dir/input.json > $tmp_dir/output.json
        json_content=$(cat $tmp_dir/output.json)
      fi

      if echo "$json_content" | jq ". | has(\"reporter.bootstrap.servers\")" 2> /dev/null | grep -q true 
      then
        # log "replacing reporter.bootstrap.servers config for environment $environment"

        echo "$json_content" > $tmp_dir/input.json
        jq ".[\"reporter.admin.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"client\\\" password=\\\"client-secret\\\";\" | .[\"reporter.admin.security.protocol\"] = \"SASL_SSL\" | .[\"reporter.admin.sasl.mechanism\"] = \"PLAIN\" | .[\"reporter.producer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"client\\\" password=\\\"client-secret\\\";\" | .[\"reporter.producer.security.protocol\"] = \"SASL_SSL\" | .[\"reporter.producer.sasl.mechanism\"] = \"PLAIN\" | .[\"reporter.admin.ssl.truststore.location\"] = \"/etc/kafka/secrets/kafka.connect.truststore.jks\" | .[\"reporter.admin.ssl.truststore.password\"] = \"confluent\" | .[\"reporter.producer.ssl.truststore.location\"] = \"/etc/kafka/secrets/kafka.connect.truststore.jks\" | .[\"reporter.producer.ssl.truststore.password\"] = \"confluent\"" $tmp_dir/input.json > $tmp_dir/output.json
        json_content=$(cat $tmp_dir/output.json)
      fi
    ;;

    2way-ssl)
      get_broker_container
      for prefix in {"confluent.topic","redo.log.consumer"}
      do
        if echo "$json_content" | jq ". | has(\"$prefix.bootstrap.servers\")" 2> /dev/null | grep -q true 
        then
          # log "replacing $prefix config for environment $environment"

          echo "$json_content" > $tmp_dir/input.json
          jq ".[\"$prefix.bootstrap.servers\"] = \"$broker_container:9092\" | .[\"$prefix.security.protocol\"] = \"SSL\" | .[\"$prefix.ssl.truststore.location\"] = \"/etc/kafka/secrets/kafka.connect.truststore.jks\" | .[\"$prefix.ssl.truststore.password\"] = \"confluent\" | .[\"$prefix.ssl.keystore.location\"] = \"/etc/kafka/secrets/kafka.connect.keystore.jks\" | .[\"$prefix.ssl.keystore.password\"] = \"confluent\" | .[\"$prefix.ssl.key.password\"] = \"confluent\"" $tmp_dir/input.json > $tmp_dir/output.json
          json_content=$(cat $tmp_dir/output.json)
        fi
      done

      for prefix in {"key","value"}
      do
        if echo "$json_content" | jq ". | has(\"$prefix.converter.schema.registry.url\")" 2> /dev/null | grep -q true 
        then
          # log "replacing $prefix.converter.schema.registry.url config for environment $environment"

          echo "$json_content" > $tmp_dir/input.json
          jq ".[\"$prefix.converter.schema.registry.url\"] = \"https://schema-registry:8081\" | .[\"$prefix.converter.schema.registry.ssl.truststore.location\"] = \"/etc/kafka/secrets/kafka.connect.truststore.jks\" | .[\"$prefix.converter.schema.registry.ssl.truststore.password\"] = \"confluent\" | .[\"$prefix.converter.schema.registry.ssl.keystore.location\"] = \"/etc/kafka/secrets/kafka.connect.keystore.jks\" | .[\"$prefix.converter.schema.registry.ssl.keystore.password\"] = \"confluent\" | .[\"$prefix.converter.schema.registry.ssl.key.password\"] = \"confluent\"" $tmp_dir/input.json > $tmp_dir/output.json
          json_content=$(cat $tmp_dir/output.json)
        fi
      done

      if echo "$json_content" | jq ". | has(\"database.history.kafka.bootstrap.servers\")" 2> /dev/null | grep -q true 
      then
        # log "replacing database.history.kafka.bootstrap.servers config for environment $environment"

        echo "$json_content" > $tmp_dir/input.json
        jq ".[\"database.history.kafka.bootstrap.servers\"] = \"$broker_container:9092\" | .[\"database.history.producer.security.protocol\"] = \"SSL\" | .[\"database.history.consumer.security.protocol\"] = \"SSL\" | .[\"database.history.producer.ssl.truststore.location\"] = \"/etc/kafka/secrets/kafka.connect.truststore.jks\" | .[\"database.history.producer.ssl.truststore.password\"] = \"confluent\" | .[\"database.history.producer.ssl.keystore.location\"] = \"/etc/kafka/secrets/kafka.connect.keystore.jks\" | .[\"database.history.producer.ssl.keystore.password\"] = \"confluent\" | .[\"database.history.producer.ssl.keystore.password\"] = \"confluent\" | .[\"database.history.consumer.ssl.truststore.location\"] = \"/etc/kafka/secrets/kafka.connect.truststore.jks\" | .[\"database.history.consumer.ssl.truststore.password\"] = \"confluent\" | .[\"database.history.consumer.ssl.keystore.location\"] = \"/etc/kafka/secrets/kafka.connect.keystore.jks\" | .[\"database.history.consumer.ssl.keystore.password\"] = \"confluent\" | .[\"database.history.consumer.ssl.keystore.password\"] = \"confluent\"" $tmp_dir/input.json > $tmp_dir/output.json
        json_content=$(cat $tmp_dir/output.json)
      fi

      if echo "$json_content" | jq ". | has(\"schema.history.internal.kafka.bootstrap.servers\")" 2> /dev/null | grep -q true 
      then
        # log "replacing schema.history.internal.kafka.bootstrap.servers config for environment $environment"

        echo "$json_content" > $tmp_dir/input.json
        jq ".[\"schema.history.internal.kafka.bootstrap.servers\"] = \"$broker_container:9092\" | .[\"schema.history.internal.producer.security.protocol\"] = \"SSL\" | .[\"schema.history.internal.consumer.security.protocol\"] = \"SSL\" | .[\"schema.history.internal.producer.ssl.truststore.location\"] = \"/etc/kafka/secrets/kafka.connect.truststore.jks\" | .[\"schema.history.internal.producer.ssl.truststore.password\"] = \"confluent\" | .[\"schema.history.internal.producer.ssl.keystore.location\"] = \"/etc/kafka/secrets/kafka.connect.keystore.jks\" | .[\"schema.history.internal.producer.ssl.keystore.password\"] = \"confluent\" | .[\"schema.history.internal.producer.ssl.keystore.password\"] = \"confluent\" | .[\"schema.history.internal.consumer.ssl.truststore.location\"] = \"/etc/kafka/secrets/kafka.connect.truststore.jks\" | .[\"schema.history.internal.consumer.ssl.truststore.password\"] = \"confluent\" | .[\"schema.history.internal.consumer.ssl.keystore.location\"] = \"/etc/kafka/secrets/kafka.connect.keystore.jks\" | .[\"schema.history.internal.consumer.ssl.keystore.password\"] = \"confluent\" | .[\"schema.history.internal.consumer.ssl.keystore.password\"] = \"confluent\"" $tmp_dir/input.json > $tmp_dir/output.json
        json_content=$(cat $tmp_dir/output.json)
      fi

      if echo "$json_content" | jq ". | has(\"reporter.bootstrap.servers\")" 2> /dev/null | grep -q true 
      then
        # log "replacing reporter.bootstrap.servers config for environment $environment"

        echo "$json_content" > $tmp_dir/input.json
        jq ".[\"reporter.admin.security.protocol\"] = \"SSL\" | .[\"reporter.admin.ssl.truststore.location\"] = \"/etc/kafka/secrets/kafka.connect.truststore.jks\" | .[\"reporter.admin.ssl.truststore.password\"] = \"confluent\" | .[\"reporter.admin.ssl.keystore.location\"] = \"/etc/kafka/secrets/kafka.connect.keystore.jks\" | .[\"reporter.admin.ssl.keystore.password\"] = \"confluent\" | .[\"reporter.admin.ssl.keystore.password\"] = \"confluent\" | .[\"reporter.producer.ssl.truststore.location\"] = \"/etc/kafka/secrets/kafka.connect.truststore.jks\" | .[\"reporter.producer.ssl.truststore.password\"] = \"confluent\" | .[\"reporter.producer.security.protocol\"] = \"SSL\" | .[\"reporter.producer.ssl.keystore.location\"] = \"/etc/kafka/secrets/kafka.connect.keystore.jks\" | .[\"reporter.producer.ssl.keystore.password\"] = \"confluent\" | .[\"reporter.producer.ssl.keystore.password\"] = \"confluent\"" $tmp_dir/input.json > $tmp_dir/output.json
        json_content=$(cat $tmp_dir/output.json)
      fi
    ;;

    sasl-scram)

      for prefix in {"confluent.topic","redo.log.consumer"}
      do
        if echo "$json_content" | jq ". | has(\"$prefix.bootstrap.servers\")" 2> /dev/null | grep -q true 
        then
          # log "replacing $prefix config for environment $environment"

          echo "$json_content" > $tmp_dir/input.json
          jq ".[\"$prefix.sasl.jaas.config\"] = \"org.apache.kafka.common.security.scram.ScramLoginModule required username=\\\"client\\\" password=\\\"client-secret\\\";\" | .[\"$prefix.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"$prefix.sasl.mechanism\"] = \"SCRAM-SHA-256\"" $tmp_dir/input.json > $tmp_dir/output.json
          json_content=$(cat $tmp_dir/output.json)
        fi
      done

      if echo "$json_content" | jq ". | has(\"database.history.kafka.bootstrap.servers\")" 2> /dev/null | grep -q true 
      then
        # log "replacing database.history.kafka.bootstrap.servers config for environment $environment"

        echo "$json_content" > $tmp_dir/input.json
        jq ".[\"database.history.producer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.scram.ScramLoginModule required username=\\\"client\\\" password=\\\"client-secret\\\";\" | .[\"database.history.producer.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"database.history.producer.sasl.mechanism\"] = \"SCRAM-SHA-256\" | .[\"database.history.consumer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.scram.ScramLoginModule required username=\\\"client\\\" password=\\\"client-secret\\\";\" | .[\"database.history.consumer.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"database.history.consumer.sasl.mechanism\"] = \"SCRAM-SHA-256\"" $tmp_dir/input.json > $tmp_dir/output.json
        json_content=$(cat $tmp_dir/output.json)
      fi

      if echo "$json_content" | jq ". | has(\"schema.history.internal.kafka.bootstrap.servers\")" 2> /dev/null | grep -q true 
      then
        # log "replacing schema.history.internal.kafka.bootstrap.servers config for environment $environment"

        echo "$json_content" > $tmp_dir/input.json
        jq ".[\"schema.history.internal.producer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.scram.ScramLoginModule required username=\\\"client\\\" password=\\\"client-secret\\\";\" | .[\"schema.history.internal.producer.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"schema.history.internal.producer.sasl.mechanism\"] = \"SCRAM-SHA-256\" | .[\"schema.history.internal.consumer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.scram.ScramLoginModule required username=\\\"client\\\" password=\\\"client-secret\\\";\" | .[\"schema.history.internal.consumer.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"schema.history.internal.consumer.sasl.mechanism\"] = \"SCRAM-SHA-256\"" $tmp_dir/input.json > $tmp_dir/output.json
        json_content=$(cat $tmp_dir/output.json)
      fi

      if echo "$json_content" | jq ". | has(\"reporter.bootstrap.servers\")" 2> /dev/null | grep -q true 
      then
        # log "replacing reporter.bootstrap.servers config for environment $environment"

        echo "$json_content" > $tmp_dir/input.json
        jq ".[\"reporter.admin.sasl.jaas.config\"] = \"org.apache.kafka.common.security.scram.ScramLoginModule required username=\\\"client\\\" password=\\\"client-secret\\\";\" | .[\"reporter.admin.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"reporter.admin.sasl.mechanism\"] = \"SCRAM-SHA-256\" | .[\"reporter.producer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.scram.ScramLoginModule required username=\\\"client\\\" password=\\\"client-secret\\\";\" | .[\"reporter.producer.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"reporter.producer.sasl.mechanism\"] = \"SCRAM-SHA-256\"" $tmp_dir/input.json > $tmp_dir/output.json
        json_content=$(cat $tmp_dir/output.json)
      fi
    ;;

    kerberos)
      # the connector's own GSSAPI clients build the broker principal from the bootstrap
      # host: point them at the FQDN, a short name only works through Docker's reverse DNS
      get_broker_container
      for key in confluent.topic.bootstrap.servers redo.log.consumer.bootstrap.servers database.history.kafka.bootstrap.servers schema.history.internal.kafka.bootstrap.servers reporter.bootstrap.servers
      do
        if echo "$json_content" | jq -e ". | has(\"$key\")" > /dev/null 2>&1
        then
          json_content=$(echo "$json_content" | jq ".[\"$key\"] = \"${broker_container}.kerberos-demo.local:9092\"")
        fi
      done

      for prefix in {"confluent.topic","redo.log.consumer"}
      do
        if echo "$json_content" | jq ". | has(\"$prefix.bootstrap.servers\")" 2> /dev/null | grep -q true 
        then
          # log "replacing $prefix config for environment $environment"

          echo "$json_content" > $tmp_dir/input.json
          jq ".[\"$prefix.sasl.jaas.config\"] = \"com.sun.security.auth.module.Krb5LoginModule required useKeyTab=true storeKey=true keyTab=\\\"/var/lib/secret/kafka-connect.key\\\" principal=\\\"connect@TEST.CONFLUENT.IO\\\";\" | .[\"$prefix.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"$prefix.sasl.mechanism\"] = \"GSSAPI\" | .[\"$prefix.sasl.kerberos.service.name\"] = \"kafka\"" $tmp_dir/input.json > $tmp_dir/output.json
          json_content=$(cat $tmp_dir/output.json)
        fi
      done

      if echo "$json_content" | jq ". | has(\"database.history.kafka.bootstrap.servers\")" 2> /dev/null | grep -q true 
      then
        # log "replacing database.history.kafka.bootstrap.servers config for environment $environment"

        echo "$json_content" > $tmp_dir/input.json
        jq ".[\"database.history.producer.sasl.jaas.config\"] = \"com.sun.security.auth.module.Krb5LoginModule required useKeyTab=true storeKey=true keyTab=\\\"/var/lib/secret/kafka-connect.key\\\" principal=\\\"connect@TEST.CONFLUENT.IO\\\";\" | .[\"database.history.producer.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"database.history.producer.sasl.mechanism\"] = \"GSSAPI\" | .[\"database.history.producer.sasl.kerberos.service.name\"] = \"kafka\" | .[\"database.history.consumer.sasl.jaas.config\"] = \"com.sun.security.auth.module.Krb5LoginModule required useKeyTab=true storeKey=true keyTab=\\\"/var/lib/secret/kafka-connect.key\\\" principal=\\\"connect@TEST.CONFLUENT.IO\\\";\" | .[\"database.history.consumer.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"database.history.consumer.sasl.mechanism\"] = \"GSSAPI\" | .[\"database.history.consumer.sasl.kerberos.service.name\"] = \"kafka\"" $tmp_dir/input.json > $tmp_dir/output.json
        json_content=$(cat $tmp_dir/output.json)
      fi

      if echo "$json_content" | jq ". | has(\"schema.history.internal.kafka.bootstrap.servers\")" 2> /dev/null | grep -q true 
      then
        # log "replacing schema.history.internal.kafka.bootstrap.servers config for environment $environment"

        echo "$json_content" > $tmp_dir/input.json
        jq ".[\"schema.history.internal.producer.sasl.jaas.config\"] = \"com.sun.security.auth.module.Krb5LoginModule required useKeyTab=true storeKey=true keyTab=\\\"/var/lib/secret/kafka-connect.key\\\" principal=\\\"connect@TEST.CONFLUENT.IO\\\";\" | .[\"schema.history.internal.producer.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"schema.history.internal.producer.sasl.mechanism\"] = \"GSSAPI\" | .[\"schema.history.internal.producer.sasl.kerberos.service.name\"] = \"kafka\" | .[\"schema.history.internal.consumer.sasl.jaas.config\"] = \"com.sun.security.auth.module.Krb5LoginModule required useKeyTab=true storeKey=true keyTab=\\\"/var/lib/secret/kafka-connect.key\\\" principal=\\\"connect@TEST.CONFLUENT.IO\\\";\" | .[\"schema.history.internal.consumer.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"schema.history.internal.consumer.sasl.mechanism\"] = \"GSSAPI\" | .[\"schema.history.internal.consumer.sasl.kerberos.service.name\"] = \"kafka\"" $tmp_dir/input.json > $tmp_dir/output.json
        json_content=$(cat $tmp_dir/output.json)
      fi

      if echo "$json_content" | jq ". | has(\"reporter.bootstrap.servers\")" 2> /dev/null | grep -q true 
      then
        # log "replacing reporter.bootstrap.servers config for environment $environment"
        
        echo "$json_content" > $tmp_dir/input.json
        jq ".[\"reporter.admin.sasl.jaas.config\"] = \"com.sun.security.auth.module.Krb5LoginModule required useKeyTab=true storeKey=true keyTab=\\\"/var/lib/secret/kafka-connect.key\\\" principal=\\\"connect@TEST.CONFLUENT.IO\\\";\" | .[\"reporter.admin.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"reporter.admin.sasl.mechanism\"] = \"GSSAPI\" | .[\"reporter.admin.sasl.kerberos.service.name\"] = \"kafka\" | .[\"reporter.producer.sasl.jaas.config\"] = \"com.sun.security.auth.module.Krb5LoginModule required useKeyTab=true storeKey=true keyTab=\\\"/var/lib/secret/kafka-connect.key\\\" principal=\\\"connect@TEST.CONFLUENT.IO\\\";\" | .[\"reporter.producer.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"reporter.producer.sasl.mechanism\"] = \"GSSAPI\" | .[\"reporter.producer.sasl.kerberos.service.name\"] = \"kafka\"" $tmp_dir/input.json > $tmp_dir/output.json
        json_content=$(cat $tmp_dir/output.json)
      fi
    ;;

    ssl_kerberos)
      # the connector's own GSSAPI clients build the broker principal from the bootstrap
      # host: point them at the FQDN, a short name only works through Docker's reverse DNS
      get_broker_container
      for key in confluent.topic.bootstrap.servers redo.log.consumer.bootstrap.servers database.history.kafka.bootstrap.servers schema.history.internal.kafka.bootstrap.servers reporter.bootstrap.servers
      do
        if echo "$json_content" | jq -e ". | has(\"$key\")" > /dev/null 2>&1
        then
          json_content=$(echo "$json_content" | jq ".[\"$key\"] = \"${broker_container}.kerberos-demo.local:9092\"")
        fi
      done

      for prefix in {"confluent.topic","redo.log.consumer"}
      do
        if echo "$json_content" | jq ". | has(\"$prefix.bootstrap.servers\")" 2> /dev/null | grep -q true 
        then
          # log "replacing $prefix config for environment $environment"

          echo "$json_content" > $tmp_dir/input.json
          jq ".[\"$prefix.sasl.jaas.config\"] = \"com.sun.security.auth.module.Krb5LoginModule required useKeyTab=true storeKey=true keyTab=\\\"/var/lib/secret/kafka-connect.key\\\" principal=\\\"connect@TEST.CONFLUENT.IO\\\";\" | .[\"$prefix.security.protocol\"] = \"SASL_SSL\" | .[\"$prefix.sasl.mechanism\"] = \"GSSAPI\" | .[\"$prefix.sasl.kerberos.service.name\"] = \"kafka\" | .[\"$prefix.ssl.truststore.location\"] = \"/etc/kafka/secrets/kafka.connect.truststore.jks\" | .[\"$prefix.ssl.truststore.password\"] = \"confluent\"" $tmp_dir/input.json > $tmp_dir/output.json
          json_content=$(cat $tmp_dir/output.json)
        fi
      done

      if echo "$json_content" | jq ". | has(\"database.history.kafka.bootstrap.servers\")" 2> /dev/null | grep -q true 
      then
        # log "replacing database.history.kafka.bootstrap.servers config for environment $environment"

        echo "$json_content" > $tmp_dir/input.json
        jq ".[\"database.history.producer.sasl.jaas.config\"] = \"com.sun.security.auth.module.Krb5LoginModule required useKeyTab=true storeKey=true keyTab=\\\"/var/lib/secret/kafka-connect.key\\\" principal=\\\"connect@TEST.CONFLUENT.IO\\\";\" | .[\"database.history.producer.security.protocol\"] = \"SASL_SSL\" | .[\"database.history.producer.sasl.mechanism\"] = \"GSSAPI\" | .[\"database.history.producer.sasl.kerberos.service.name\"] = \"kafka\" | .[\"database.history.producer.ssl.truststore.location\"] = \"/etc/kafka/secrets/kafka.connect.truststore.jks\" | .[\"database.history.producer.ssl.truststore.password\"] = \"confluent\" | .[\"database.history.consumer.sasl.jaas.config\"] = \"com.sun.security.auth.module.Krb5LoginModule required useKeyTab=true storeKey=true keyTab=\\\"/var/lib/secret/kafka-connect.key\\\" principal=\\\"connect@TEST.CONFLUENT.IO\\\";\" | .[\"database.history.consumer.security.protocol\"] = \"SASL_SSL\" | .[\"database.history.consumer.sasl.mechanism\"] = \"GSSAPI\" | .[\"database.history.consumer.sasl.kerberos.service.name\"] = \"kafka\" | .[\"database.history.consumer.ssl.truststore.location\"] = \"/etc/kafka/secrets/kafka.connect.truststore.jks\" | .[\"database.history.consumer.ssl.truststore.password\"] = \"confluent\"" $tmp_dir/input.json > $tmp_dir/output.json
        json_content=$(cat $tmp_dir/output.json)
      fi

      if echo "$json_content" | jq ". | has(\"schema.history.internal.kafka.bootstrap.servers\")" 2> /dev/null | grep -q true 
      then
        # log "replacing schema.history.internal.kafka.bootstrap.servers config for environment $environment"

        echo "$json_content" > $tmp_dir/input.json
        jq ".[\"schema.history.internal.producer.sasl.jaas.config\"] = \"com.sun.security.auth.module.Krb5LoginModule required useKeyTab=true storeKey=true keyTab=\\\"/var/lib/secret/kafka-connect.key\\\" principal=\\\"connect@TEST.CONFLUENT.IO\\\";\" | .[\"schema.history.internal.producer.security.protocol\"] = \"SASL_SSL\" | .[\"schema.history.internal.producer.sasl.mechanism\"] = \"GSSAPI\" | .[\"schema.history.internal.producer.sasl.kerberos.service.name\"] = \"kafka\" | .[\"schema.history.internal.producer.ssl.truststore.location\"] = \"/etc/kafka/secrets/kafka.connect.truststore.jks\" | .[\"schema.history.internal.producer.ssl.truststore.password\"] = \"confluent\" | .[\"schema.history.internal.consumer.sasl.jaas.config\"] = \"com.sun.security.auth.module.Krb5LoginModule required useKeyTab=true storeKey=true keyTab=\\\"/var/lib/secret/kafka-connect.key\\\" principal=\\\"connect@TEST.CONFLUENT.IO\\\";\" | .[\"schema.history.internal.consumer.security.protocol\"] = \"SASL_SSL\" | .[\"schema.history.internal.consumer.sasl.mechanism\"] = \"GSSAPI\" | .[\"schema.history.internal.consumer.sasl.kerberos.service.name\"] = \"kafka\" | .[\"schema.history.internal.consumer.ssl.truststore.location\"] = \"/etc/kafka/secrets/kafka.connect.truststore.jks\" | .[\"schema.history.internal.consumer.ssl.truststore.password\"] = \"confluent\"" $tmp_dir/input.json > $tmp_dir/output.json
        json_content=$(cat $tmp_dir/output.json)
      fi

      if echo "$json_content" | jq ". | has(\"reporter.bootstrap.servers\")" 2> /dev/null | grep -q true 
      then
        # log "replacing reporter.bootstrap.servers config for environment $environment"
        
        echo "$json_content" > $tmp_dir/input.json
        jq ".[\"reporter.admin.sasl.jaas.config\"] = \"com.sun.security.auth.module.Krb5LoginModule required useKeyTab=true storeKey=true keyTab=\\\"/var/lib/secret/kafka-connect.key\\\" principal=\\\"connect@TEST.CONFLUENT.IO\\\";\" | .[\"reporter.admin.security.protocol\"] = \"SASL_SSL\" | .[\"reporter.admin.sasl.mechanism\"] = \"GSSAPI\" | .[\"reporter.admin.sasl.kerberos.service.name\"] = \"kafka\" | .[\"reporter.admin.ssl.truststore.location\"] = \"/etc/kafka/secrets/kafka.connect.truststore.jks\" | .[\"reporter.admin.ssl.truststore.password\"] = \"confluent\" | .[\"reporter.producer.sasl.jaas.config\"] = \"com.sun.security.auth.module.Krb5LoginModule required useKeyTab=true storeKey=true keyTab=\\\"/var/lib/secret/kafka-connect.key\\\" principal=\\\"connect@TEST.CONFLUENT.IO\\\";\" | .[\"reporter.producer.security.protocol\"] = \"SASL_SSL\" | .[\"reporter.producer.sasl.mechanism\"] = \"GSSAPI\" | .[\"reporter.producer.sasl.kerberos.service.name\"] = \"kafka\" | .[\"reporter.producer.ssl.truststore.location\"] = \"/etc/kafka/secrets/kafka.connect.truststore.jks\" | .[\"reporter.producer.ssl.truststore.password\"] = \"confluent\"" $tmp_dir/input.json > $tmp_dir/output.json
        json_content=$(cat $tmp_dir/output.json)
      fi
    ;;

    rbac-sasl-plain|cfk-rbac)

      echo "$json_content" > $tmp_dir/input.json
      jq ".[\"principal.service.name\"] = \"connectorSA\" | .[\"principal.service.password\"] = \"connectorSA\"" $tmp_dir/input.json > $tmp_dir/output.json
      json_content=$(cat $tmp_dir/output.json)

      for prefix in {"confluent.topic","redo.log.consumer"}
      do
        if echo "$json_content" | jq ". | has(\"$prefix.bootstrap.servers\")" 2> /dev/null | grep -q true 
        then
          # log "replacing $prefix config for environment $environment"

          echo "$json_content" > $tmp_dir/input.json
          jq ".[\"$prefix.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"admin\\\" password=\\\"admin-secret\\\";\" | .[\"$prefix.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"$prefix.sasl.mechanism\"] = \"PLAIN\"" $tmp_dir/input.json > $tmp_dir/output.json
          json_content=$(cat $tmp_dir/output.json)
        fi
      done

      if echo "$json_content" | jq ". | has(\"database.history.kafka.bootstrap.servers\")" 2> /dev/null | grep -q true 
      then
        # log "replacing database.history.kafka.bootstrap.servers config for environment $environment"

        echo "$json_content" > $tmp_dir/input.json
        jq ".[\"database.history.producer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"admin\\\" password=\\\"admin-secret\\\";\" | .[\"database.history.producer.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"database.history.producer.sasl.mechanism\"] = \"PLAIN\" | .[\"database.history.consumer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"admin\\\" password=\\\"admin-secret\\\";\" | .[\"database.history.consumer.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"database.history.consumer.sasl.mechanism\"] = \"PLAIN\"" $tmp_dir/input.json > $tmp_dir/output.json
        json_content=$(cat $tmp_dir/output.json)
      fi

      if echo "$json_content" | jq ". | has(\"schema.history.internal.kafka.bootstrap.servers\")" 2> /dev/null | grep -q true 
      then
        # log "replacing schema.history.internal.kafka.bootstrap.servers config for environment $environment"

        echo "$json_content" > $tmp_dir/input.json
        jq ".[\"schema.history.internal.producer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"admin\\\" password=\\\"admin-secret\\\";\" | .[\"schema.history.internal.producer.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"schema.history.internal.producer.sasl.mechanism\"] = \"PLAIN\" | .[\"schema.history.internal.consumer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"admin\\\" password=\\\"admin-secret\\\";\" | .[\"schema.history.internal.consumer.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"schema.history.internal.consumer.sasl.mechanism\"] = \"PLAIN\"" $tmp_dir/input.json > $tmp_dir/output.json
        json_content=$(cat $tmp_dir/output.json)
      fi

      if echo "$json_content" | jq ". | has(\"reporter.bootstrap.servers\")" 2> /dev/null | grep -q true 
      then
        # log "replacing reporter.bootstrap.servers config for environment $environment"
        
        echo "$json_content" > $tmp_dir/input.json
        jq ".[\"reporter.admin.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"admin\\\" password=\\\"admin-secret\\\";\" | .[\"reporter.admin.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"reporter.admin.sasl.mechanism\"] = \"PLAIN\" | .[\"reporter.producer.sasl.jaas.config\"] = \"org.apache.kafka.common.security.plain.PlainLoginModule required username=\\\"admin\\\" password=\\\"admin-secret\\\";\" | .[\"reporter.producer.security.protocol\"] = \"SASL_PLAINTEXT\" | .[\"reporter.producer.sasl.mechanism\"] = \"PLAIN\"" $tmp_dir/input.json > $tmp_dir/output.json
        json_content=$(cat $tmp_dir/output.json)
      fi
    ;;

    rbac-oauth)
      # connectors log in to Keycloak (environment/rbac-oauth) as the client "connector": their producer, consumer and
      # admin clients (*.override.*, unless the config already sets their sasl.jaas.config), the extra Kafka clients of
      # some connectors (confluent.topic.*, schema history, reporter...) and their Schema Registry clients (bearer.auth.*
      # of each converter with a schema.registry.url, unless it already sets basic.auth or bearer.auth)
      local rbac_oauth_jq='
        def oauth($p): .[$p+".security.protocol"] = "SASL_PLAINTEXT"
          | .[$p+".sasl.mechanism"] = "OAUTHBEARER"
          | .[$p+".sasl.login.callback.handler.class"] = "org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginCallbackHandler"
          | .[$p+".sasl.oauthbearer.token.endpoint.url"] = $token_url
          | .[$p+".sasl.jaas.config"] = "org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required clientId=\"connector\" clientSecret=\"connector-secret\";";
        def bearer($c): .[$c+".bearer.auth.credentials.source"] = "OAUTHBEARER"
          | .[$c+".bearer.auth.issuer.endpoint.url"] = $token_url
          | .[$c+".bearer.auth.client.id"] = "connector"
          | .[$c+".bearer.auth.client.secret"] = "connector-secret";
        reduce ("producer.override", "consumer.override", "admin.override") as $p
          (.; if has($p + ".sasl.jaas.config") then . else oauth($p) end)
        | reduce (
            ["confluent.topic.bootstrap.servers", "confluent.topic"],
            ["redo.log.consumer.bootstrap.servers", "redo.log.consumer"],
            ["database.history.kafka.bootstrap.servers", "database.history.producer", "database.history.consumer"],
            ["schema.history.internal.kafka.bootstrap.servers", "schema.history.internal.producer", "schema.history.internal.consumer"],
            ["reporter.bootstrap.servers", "reporter.admin", "reporter.producer"]
          ) as $m
          (.; if has($m[0]) then reduce $m[1:][] as $p (.; oauth($p)) else . end)
        | reduce (keys[] | select(endswith("converter.schema.registry.url")) | sub("\\.schema\\.registry\\.url$"; "")) as $c
          (.; if has($c + ".basic.auth.credentials.source") or has($c + ".bearer.auth.credentials.source") then . else bearer($c) end)
      '
      json_content=$(echo "$json_content" | jq --arg token_url "http://keycloak:8080/realms/kafka/protocol/openid-connect/token" "$rbac_oauth_jq")
    ;;

    *)
      return
    ;;
  esac

  echo "$json_content" > $tmp_dir/2.json
  log "✨ Following config was added to handle environment $environment:"
  set +e
  diff <(jq --sort-keys . $tmp_dir/1.json) <(jq --sort-keys . $tmp_dir/2.json)
  set -e
}

# the example of the last 'playground run' (run.test_file of playground.ini), on stdout. Errors go to stderr and
# return 1 when no example was run yet or its file no longer exists: test_file=$(get_current_test_file) || exit 1
function get_current_test_file () {
  local current_test_file
  current_test_file=$(playground state get run.test_file)
  if [ -z "$current_test_file" ]
  then
    logerror "❌ no example was run yet (run.test_file is not set in $root_folder/playground.ini), start one with 'playground run'" >&2
    return 1
  fi
  if [ ! -f "$current_test_file" ]
  then
    logerror "❌ file $current_test_file retrieved from $root_folder/playground.ini does not exist!" >&2
    return 1
  fi
  echo "$current_test_file"
}

# lock of a file shared by parallel runs (playground-run-history): mkdir is atomic, and flock is not on macOS.
# A lock older than 30 seconds was left by a killed process and is taken over; after 10 seconds of waiting the caller
# goes on without it (a history line is not worth blocking a run)
function file_lock () {
  local lock="$1.lock"
  local waited=0
  local lock_mtime
  while ! mkdir "$lock" 2> /dev/null
  do
    # GNU stat first: BSD stat -f is something else on Linux
    lock_mtime=$(stat -c %Y "$lock" 2> /dev/null || stat -f %m "$lock" 2> /dev/null)
    if [ -n "$lock_mtime" ] && [ $(( $(date +%s) - lock_mtime )) -gt 30 ]
    then
      rm -rf "$lock"
      continue
    fi
    sleep 0.1
    waited=$((waited + 1))
    if [ $waited -ge 100 ]
    then
      logwarn "⚠️ $1 is locked by another run ($lock), going on without the lock" >&2
      return 0
    fi
  done
}

function file_unlock () {
  rmdir "$1.lock" 2> /dev/null || true
}

# true when a browser can be opened: open on macOS, xdg-open with a display on Linux (Debian's /bin/open is openvt)
function can_open_url () {
  if [[ "$OSTYPE" == "darwin"* ]]
  then
    command -v open > /dev/null 2>&1
  else
    command -v xdg-open > /dev/null 2>&1 && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]
  fi
}

# opens $1 in the browser ($2: a browser application, macOS only), returns 1 when it can't (no browser: headless,
# ssh…), the caller then prints the url
function open_url () {
  if ! can_open_url
  then
    return 1
  fi
  if [[ "$OSTYPE" == "darwin"* ]]
  then
    if [ -n "${2:-}" ]
    then
      open -a "$2" "$1"
    else
      open "$1"
    fi
  else
    xdg-open "$1" > /dev/null 2>&1 &
  fi
}

function maybe_remove_flag () {
  flag="$1"
  local entry
  local kept=()
  for entry in "${array_flag_list[@]}"
  do
    # --flag=value, --flag value, or a flag without value
    if [[ $entry == ${flag}=* ]] || [[ $entry == "${flag} "* ]] || [[ $entry == "${flag}" ]]
    then
      continue
    fi
    kept+=("$entry")
  done
  array_flag_list=("${kept[@]}")
}

# replace the values of --cluster-creds / --cluster-schema-registry-creds by '<masked>' in a command line or a flag list
function mask_creds_in_command () {
  if [[ "$1" == *"creds"* ]]
  then
    # a value is a word, backslash-quoted characters included
    sed -E 's/(--cluster-(schema-registry-)?creds[ =])([^ \\]|\\.)+/\1'"'<masked>'"'/g' <<< "$1"
  else
    echo "$1"
  fi
}

# array_flag_list of playground run as arguments, in the flag_args array: "--flag value" entries are two arguments,
# "--flag=value" and "--flag" entries one, so values with spaces survive and no word splitting (IFS) is needed
function flag_list_to_args () {
  local flag name
  flag_args=()
  for flag in "${array_flag_list[@]}"
  do
    [ -z "$flag" ] && continue
    # the name ends at the first space or '=': a value can contain both (a secret ending with '=', a path with spaces)
    name="${flag%%[ =]*}"
    if [ "${flag:${#name}:1}" == " " ]
    then
      flag_args+=("$name" "${flag#* }")
    else
      flag_args+=("$flag")
    fi
  done
}

# set the log levels of PLAYGROUND_CONNECT_LOG_LEVELS (playground run --connect-log-level), best effort
function apply_connect_log_levels () {
  if [ -z "$PLAYGROUND_CONNECT_LOG_LEVELS" ]
  then
    return
  fi
  local entry
  set +e
  for entry in ${PLAYGROUND_CONNECT_LOG_LEVELS//,/ }
  do
    if ! playground debug log-level set --package "${entry%%=*}" --level "${entry#*=}"
    then
      logwarn "🔊 could not set connect log level $entry, set it manually with 'playground debug log-level set'"
    fi
  done
  set -e
}

# packages of the connector classes used by an example, for example io.confluent.connect.s3
function get_example_connector_packages () {
  local example_file="$1"
  grep -ho '"connector.class"[[:space:]]*:[[:space:]]*"[^"]*"' "$example_file" | sed 's/.*"\([^"]*\)"$/\1/' | sed 's/\.[^.]*$//' | grep "\." | sort -u
}

# playground run menu: append the entries of a group to options, followed by the
# group separator, only if the group is not empty
function add_menu_group () {
  local separator="$1"
  shift
  if [ $# -eq 0 ]
  then
    return
  fi
  options+=("$@")
  options+=("$separator")
}

# playground run menu: if the toggle applies (1), queue its entry, checked when
# the current value is set
function add_menu_toggle () {
  local applies="$1"
  local current_value="$2"
  local label="$3"
  if [ "$applies" != "1" ]
  then
    return
  fi
  if [ -z "$current_value" ]
  then
    toggle_group+=("[ ] $label")
  else
    toggle_group+=("[x] $label")
  fi
}

# environments an example can be run with (playground run --environment), one per
# line. Nothing when the example starts its own environment instead of
# "${PLAYGROUND_ENVIRONMENT}", and no cfk / cfk-rbac when it skips cfk (exit 111)
function get_example_supported_environments () {
  local example_file="$1"
  local environment_name
  if ! grep -qE 'start-environment --environment "?\$\{?PLAYGROUND_ENVIRONMENT' "$example_file"
  then
    return
  fi
  local skips_cfk=0
  if awk '/PLAYGROUND_ENVIRONMENT"? *==? *"?cfk/{inblock=1; next} inblock && /exit 111/{found=1} inblock && /^[[:space:]]*(fi|else)([[:space:]]|$)/{inblock=0} END{exit !found}' "$example_file"
  then
    skips_cfk=1
  fi
  for environment_name in plaintext ccloud cfk cfk-rbac 2way-ssl kerberos ldap-authorizer-sasl-plain ldap-sasl-plain rbac-sasl-plain rbac-oauth sasl-oauthbearer sasl-plain sasl-scram sasl-ssl ssl_kerberos
  do
    if [[ "$environment_name" == cfk* ]] && [ $skips_cfk == 1 ]
    then
      continue
    fi
    echo "$environment_name"
  done
}

# fzf menus: "<emoji> <text>", padded so that the flags (or values) line up in a
# column. <emoji> must be a single 2-column code point (no U+FE0F variation selector,
# no ZWJ sequence, no keycap): fzf and terminals disagree on the width of those, and
# the shifted row leaves stale characters behind when fzf redraws it.
# <reserved> is for a prefix added later (the "[x] " of toggles)
function menu_label () {
  local emoji="$1"
  local text="$2"
  local flag="$3"
  local reserved="${4:-0}"
  local padding=$((MAX_LENGTH - 3 - ${#text} - reserved))
  if [ $padding -lt 1 ]
  then
    padding=1
  fi
  printf '%s %s %*s %s' "$emoji" "$text" "$padding" ' ' "$flag"
}

# Does the example build a client whose version --client-version (CLIENT_VERSION) sets: a java application built with
# the Apache Kafka clients (mvn -Dkafka.client.tag=$KAFKA_CLIENT_TAG), or a client example reading CLIENT_VERSION
function example_uses_client_version () {
  example_files_contain "$1" "kafka.client.tag\|CLIENT_VERSION"
}

# Does the example file, or a file of its folder that it sources, match the grep pattern
function example_files_contain () {
  local example_file
  while IFS= read -r example_file
  do
    if grep -q "$2" "$example_file" 2> /dev/null
    then
      return 0
    fi
  done < <(get_example_files_with_sourced "$1")
  return 1
}

# The example file and the files of its folder that it sources (source ${DIR}/streams-functions.bash: the build of
# other/kafka-streams is there), one per line
function get_example_files_with_sourced () {
  local file="$1"
  local dir sourced
  [ -f "$file" ] || return 0
  echo "$file"
  dir=$(dirname "$file")
  for sourced in $(sed -n 's|^[[:space:]]*source[[:space:]]*"\{0,1\}\${DIR}/\([^/"[:space:]]*\)"\{0,1\}[[:space:]]*$|\1|p' "$file")
  do
    if [ -f "$dir/$sourced" ]
    then
      echo "$dir/$sourced"
    fi
  done
}

# The client whose version --client-version sets for this example, as a key of get_client_version_list (empty: none).
# ccloud/client-* build the image of other/client-*, so the same client
function get_example_client_kind () {
  local file="$1"
  case "$file" in
    */client-c/*) echo "librdkafka" ;;
    */client-dotnet/*) echo "confluent-kafka-dotnet" ;;
    */client-go/*) echo "confluent-kafka-go" ;;
    */client-java/*) echo "kafka-clients" ;;
    */client-javascript/*) echo "confluent-kafka-javascript" ;;
    */client-kafkajs/*) echo "kafkajs" ;;
    */client-python/*) echo "confluent-kafka-python" ;;
    */client-rust/*) echo "confluent-kafka-rust" ;;
    *)
      if example_files_contain "$file" "kafka.client.tag"
      then
        echo "kafka-clients"
      fi
      ;;
  esac
}

# Published versions of a client (a key printed by get_example_client_kind), newest first, from its package registry.
# Cached one day in /tmp/playground-client-version-list/<client>.txt, the stale cache is used when the registry is unreachable
function get_client_version_list () {
  local kind="$1"
  local cache_dir="/tmp/playground-client-version-list"
  local cache_file="$cache_dir/$kind.txt"
  local list=""

  if [ -s "$cache_file" ] && [ -z "$(find "$cache_file" -mmin +1440 2> /dev/null)" ]
  then
    cat "$cache_file"
    return
  fi

  case "$kind" in
    kafka-clients)
      # client-java supports kafka-clients 2.x onwards
      list=$(curl -fsSL --max-time 10 "https://repo1.maven.org/maven2/org/apache/kafka/kafka-clients/maven-metadata.xml" 2> /dev/null | sed -n 's:.*<version>\(.*\)</version>.*:\1:p' | grep -E '^[2-9]\.')
      ;;
    librdkafka)
      # the packages that other/client-c installs (librdkafka1=<version>-*)
      list=$(curl -fsSL --max-time 15 "https://packages.confluent.io/clients/deb/dists/bookworm/main/binary-amd64/Packages.gz" 2> /dev/null | gunzip 2> /dev/null | awk '/^Package: librdkafka1$/{p=1} p && /^Version:/{print $2; p=0}' | sed 's/-.*//')
      ;;
    confluent-kafka-dotnet)
      list=$(curl -fsSL --max-time 10 "https://api.nuget.org/v3-flatcontainer/confluent.kafka/index.json" 2> /dev/null | jq -r '.versions[]' 2> /dev/null)
      ;;
    confluent-kafka-go)
      list=$(curl -fsSL --max-time 10 "https://proxy.golang.org/github.com/confluentinc/confluent-kafka-go/v2/@v/list" 2> /dev/null | sed 's/^v//')
      ;;
    confluent-kafka-javascript)
      list=$(curl -fsSL --max-time 10 "https://registry.npmjs.org/@confluentinc/kafka-javascript" 2> /dev/null | jq -r '.versions | keys[]' 2> /dev/null)
      ;;
    kafkajs)
      list=$(curl -fsSL --max-time 10 "https://registry.npmjs.org/kafkajs" 2> /dev/null | jq -r '.versions | keys[]' 2> /dev/null)
      ;;
    confluent-kafka-python)
      list=$(curl -fsSL --max-time 10 "https://pypi.org/pypi/confluent-kafka/json" 2> /dev/null | jq -r '.releases | keys[]' 2> /dev/null)
      ;;
    confluent-kafka-rust)
      list=$(curl -fsSL --max-time 10 -A "kafka-docker-playground" "https://crates.io/api/v1/crates/confluent-kafka/versions" 2> /dev/null | jq -r '.versions[].num' 2> /dev/null)
      ;;
    *)
      return
      ;;
  esac

  # releases first, then the pre-releases and dev builds (rc, beta, -devel-…), newest first in both
  list=$(echo "$list" | grep -v '^$' | sort -urV)
  list=$( { echo "$list" | grep -E '^[0-9]+(\.[0-9]+)+$'; echo "$list" | grep -vE '^[0-9]+(\.[0-9]+)+$'; } | grep -v '^$')
  if [ -n "$list" ]
  then
    mkdir -p "$cache_dir"
    echo "$list" > "$cache_file"
    echo "$list"
  elif [ -s "$cache_file" ]
  then
    cat "$cache_file"
  fi
}

# The example file of a command line being completed: the value of -f / --file, else the example of the last run
function get_example_file_from_completion_words () {
  local file="" previous=""
  local word
  for word in "$@"
  do
    case "$previous" in
      -f|--file) file="$word" ;;
    esac
    case "$word" in
      --file=*) file="${word#--file=}" ;;
    esac
    previous="$word"
  done
  # the completion of --file prints <cur>@<file>
  file="${file#*@}"
  file="${file/#\~/$HOME}"
  if [ -z "$file" ]
  then
    file=$(playground state get run.test_file 2> /dev/null)
  fi
  echo "$file"
}

# fzf picker of the versions of the client that the example builds (get_example_client_kind); a version that is not in
# the list can be typed (alt-enter, or Enter when nothing matches). Prints the version, empty when cancelled or when the
# example builds no client
function get_client_version_with_fzf () {
  local cur="$1"
  local file="$2"
  local kind list res

  kind=$(get_example_client_kind "$file")
  if [ -z "$kind" ]
  then
    return
  fi
  list=$(get_client_version_list "$kind")

  local fzf_option_pointer="" fzf_option_rounded=""
  if version_gt "$(get_fzf_version)" "0.38"
  then
    fzf_option_pointer="--pointer=👉"
    fzf_option_rounded="--border=rounded"
  fi

  # --print-query: line 1 is the query, line 2 the selection (none when nothing matches); Esc exits 130
  res=$(echo "$list" | fzf -i --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="☕" --header="select the $kind version that $(example_relative_path "$file") builds (alt-enter: the typed version, Esc: the default)" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_pointer --print-query --bind "alt-enter:print-query") || [ $? -eq 1 ] || return 0
  if [ "$(echo "$res" | wc -l)" -gt 1 ]
  then
    echo "$res" | tail -1
  else
    echo "$res"
  fi
}

# playground run: known-bad combinations of the current flags / variables, one
# "error|<message>" or "warning|<message>" line each. Errors would make the run
# fail after the environment is started, warnings are combinations that run but
# probably not as expected
function get_run_flag_combination_problems () {
  local effective_tag=${TAG:-$(grep "# default tag" "$root_folder/scripts/utils.sh" | cut -d "=" -f 2 | cut -d " " -f 1)}
  local tag_base=${effective_tag%%-*}

  # --enable-legacy-control-center implies --enable-control-center
  if [ -n "$ENABLE_LEGACY_CONTROL_CENTER" ] && { [ -n "$ENABLE_CONTROL_CENTER" ] || [[ " ${array_flag_list[*]} " == *" --enable-legacy-control-center "* ]]; }
  then
    # both the platform (--tag) and the legacy Control Center image (--control-center-tag, CP versions) must be < 8
    local control_center_tag=${CP_CONTROL_CENTER_TAG:-$effective_tag}
    if version_gt "$tag_base" "7.9.99" || version_gt "${control_center_tag%%-*}" "7.9.99"
    then
      echo "error|legacy Control Center is only available for CP < 8 (--tag $effective_tag, Control Center $control_center_tag): use --tag (and --control-center-tag) to select an older version"
    fi
  fi

  if [ -n "$(get_menu_flag_value --ksqldb-tag)" ] && [ -z "$ENABLE_KSQLDB" ]
  then
    echo "warning|--ksqldb-tag has no effect without --enable-ksqldb"
  fi
  if [ -n "$(get_menu_flag_value --control-center-tag)" ] && [ -z "$ENABLE_CONTROL_CENTER" ] && [[ " ${array_flag_list[*]} " != *" --enable-legacy-control-center "* ]]
  then
    echo "warning|--control-center-tag has no effect without --enable-control-center"
  fi

  if [ -n "$(get_menu_flag_value --client-version)" ] && ! example_uses_client_version "$test_file"
  then
    echo "warning|--client-version has no effect: this example builds no client (no java application with the Apache Kafka clients, not a client example)"
  fi

  # the flag, not ENABLE_KRAFT: utils.sh exports ENABLE_KRAFT for every CP >= 8, so a run started from a shell that sourced
  # it (scripts/run-tests.sh, a nested playground run) inherits it without --enable-kraft
  if [[ " ${array_flag_list[*]} " == *" --enable-kraft "* ]]
  then
    if ! version_gt "$tag_base" "7.3.99"
    then
      echo "error|KRaft mode requires CP >= 7.4, CP $effective_tag is selected: use --tag to select a newer version or disable --enable-kraft"
    elif version_gt "$tag_base" "7.9.99"
    then
      echo "warning|--enable-kraft has no effect with CP $effective_tag, KRaft is always used for CP >= 8"
    fi
  fi

  # --environment the example does not support: a warning only, the example
  # handles it itself (exit 111 = skipped, which CI relies on)
  local selected_environment
  selected_environment=$(get_menu_flag_value --environment)
  if [ -n "$selected_environment" ] && [ "$selected_environment" != "plaintext" ] && [ -f "$test_file" ]
  then
    local supported_environments
    supported_environments=$(get_example_supported_environments "$test_file")
    if [ -z "$supported_environments" ]
    then
      echo "warning|--environment $selected_environment has no effect, $(basename "$test_file") always starts its own environment"
    elif ! echo "$supported_environments" | grep -qx "$selected_environment"
    then
      echo "warning|$(basename "$test_file") does not support --environment $selected_environment, it will be skipped (exit 111)"
    fi
  fi

  if [ -n "$ENABLE_CONTROL_CENTER" ]
  then
    if [[ $CP_KAFKA_IMAGE == *"cp-kafka" ]]
    then
      echo "warning|Control Center with the community kafka image: Confluent Metrics Reporter is disabled, so broker metrics will be missing"
    fi
    if [[ $CP_CONNECT_IMAGE == *"cp-kafka-connect"* ]] && ! version_gt "$tag_base" "7.9.99"
    then
      echo "warning|Control Center with the community connect image: monitoring interceptors are disabled, so consumer lag and stream monitoring will be missing"
    fi
  fi
}

# playground run menu: submenu showing every 'playground config' preference with
# its current value, until "go back". A change is saved right away, through the
# 'playground config <key>' command so that its validation applies
function interactive_config_menu () {
  local fzf_colors="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE"
  local back="🔙 Back to the example menu"
  # key|emoji|label|default
  local definitions=(
    "editor|🔖|Editor used to open files|code"
    "folder_zip_or_jar|📂|Folders searched for connector zip or jar|~"
    "clipboard|📋|Copy connector config to the clipboard|true"
    "container-kill-all-before-run|🔪|Kill all containers before each run|false"
    "cleanup-ccloud-resources-after-run|🧹|Delete ccloud resources left by the last run|ask"
    "check-and-update-repo-version|🔄|Check that the repo is up to date|true"
    "run-log|📄|Write a masked log of each run, to share it|true"
    "run-log-folder|🗂️|Folder of the run logs|$(run_log_default_folder)"
    "open-diagnose-report-on-failure|🩺|Open the diagnose HTML report when a connector fails|true"
    "display-last-updated-connector-plugins|🆕|List recently released connector plugins at the end of a run|false"
    "display-last-updated-connector-plugins-days|📅|Days to look back for recently released connector plugins|3"
    "display-last-updated-connector-plugins-vendor|🏢|Vendor of recently released connector plugins (all: every vendor)|confluentinc"
    "open-ccloud-connector-in-browser.automatically|☁️|Open fully managed connectors in browser|true"
    "open-ccloud-connector-in-browser.browser|🧭|Browser for fully managed connectors|default browser"
    "open-grafana-in-browser.automatically|📊|Open Grafana in browser|true"
    "open-grafana-in-browser.browser|🧭|Browser for Grafana|default browser"
  )
  local definition key emoji label default value entries res new_value i
  while true
  do
    entries=()
    for definition in "${definitions[@]}"
    do
      IFS='|' read -r key emoji label default <<< "$definition"
      if [ "$key" == "clipboard" ] && [[ "$OSTYPE" != "darwin"* ]]
      then
        continue
      fi
      value=$(playground config get "$key")
      # folder_zip_or_jar is stored as ",folder1,folder2"
      value=${value#,}
      entries+=("$(menu_value_label "$(menu_label "$emoji" "$label" "$key")" "${value:-default: $default}")")
    done
    entries+=("$back")

    set +e
    res=$(printf '%s\n' "${entries[@]}" | fzf --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="⚙️" --header="select a preference to change (saved right away, same as 'playground config')" --color="$fzf_colors" $fzf_option_pointer)
    set -e
    if [ -z "$res" ] || [ "$res" == "$back" ]
    then
      return
    fi

    for definition in "${definitions[@]}"
    do
      IFS='|' read -r key emoji label default <<< "$definition"
      if [[ "$res" == *" $key  ["* ]]
      then
        break
      fi
    done
    value=$(playground config get "$key")

    new_value=""
    set +e
    case "$key" in
      editor)
        new_value=$(printf '%s\n' code vi vim nano subl idea | fzf --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🔖" --header="select the editor, or type one and use <option+enter>" --color="$fzf_colors" $fzf_option_pointer --bind "alt-enter:print-query")
        ;;
      folder_zip_or_jar)
        # stored as ",folder1,folder2"
        value=${value#,}
        new_value=$(echo "" | fzf --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="📂" --header="enter the folders, separated by spaces (current folder is always included)" --color="$fzf_colors" $fzf_option_empty_pointer --print-query --query "${value//,/ }")
        ;;
      *.browser)
        new_value=$(printf '%s\n' "default browser" "Safari" "Google Chrome" "Firefox" "Microsoft Edge" "Arc" | fzf --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🧭" --header="select the browser, or type one and use <option+enter>" --color="$fzf_colors" $fzf_option_pointer --bind "alt-enter:print-query")
        ;;
      run-log-folder)
        new_value=$(echo "" | fzf --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🗂️" --header="enter the folder of the run logs" --color="$fzf_colors" $fzf_option_empty_pointer --print-query --query "${value:-$(run_log_default_folder)}")
        ;;
      display-last-updated-connector-plugins-days)
        new_value=$(printf '%s\n' 1 3 7 14 30 | fzf --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="📅" --header="select the number of days, or type one and use <option+enter>" --color="$fzf_colors" $fzf_option_pointer --bind "alt-enter:print-query")
        ;;
      display-last-updated-connector-plugins-vendor)
        new_value=$(printf '%s\n' confluentinc all debezium | fzf --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🏢" --header="select the vendor (all: every vendor), or type one and use <option+enter>" --color="$fzf_colors" $fzf_option_pointer --bind "alt-enter:print-query")
        ;;
      cleanup-ccloud-resources-after-run)
        new_value=$(printf '%s\n' ask true false | fzf --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🧹" --header="ask: list and confirm, true: delete without asking, false: never delete" --color="$fzf_colors" $fzf_option_pointer)
        ;;
      *)
        new_value=$(printf '%s\n' true false | fzf --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="⚙️" --header="$label" --color="$fzf_colors" $fzf_option_pointer)
        ;;
    esac
    set -e
    # --print-query: first line is the query
    new_value=$(echo "$new_value" | head -1)
    if [ -z "$new_value" ]
    then
      continue
    fi

    set +e
    case "$key" in
      editor)
        if command -v "$new_value" > /dev/null 2>&1
        then
          playground config editor "$new_value"
        else
          logwarn "❌ editor <$new_value> is not installed, ignoring it"
        fi
        ;;
      folder_zip_or_jar)
        local folders=() folder
        read -r -a folders <<< "$new_value"
        for i in "${!folders[@]}"
        do
          folder="${folders[$i]}"
          folders[$i]="${folder/#\~/$HOME}"
        done
        playground config folder_zip_or_jar "${folders[@]}"
        ;;
      *.browser)
        if [ "$new_value" == "default browser" ]
        then
          new_value=""
        fi
        playground config "${key%%.*}" browser "$new_value"
        ;;
      *.automatically)
        playground config "${key%%.*}" automatically "$new_value"
        ;;
      *)
        playground config "$key" "$new_value"
        ;;
    esac
    set -e
  done
}

# playground run menu: value of a flag in array_flag_list (--flag=value or --flag value)
function get_menu_flag_value () {
  local flag="$1"
  local entry
  for entry in "${array_flag_list[@]}"
  do
    case "$entry" in
      "$flag="*) echo "${entry#*=}"; return ;;
      "$flag "*) echo "${entry#* }"; return ;;
    esac
  done
}

# playground run menu: label followed by its current value, if any
function menu_value_label () {
  local label="$1"
  local value="$2"
  if [ -n "$value" ]
  then
    echo "$label  [$value]"
  else
    echo "$label"
  fi
}

function display_interactive_menu_categories () {
  repro=$1

  fzf_version=$(get_fzf_version)
  if version_gt $fzf_version "0.38"
  then
      fzf_option_wrap="--preview-window=40%,wrap"
      fzf_option_pointer="--pointer=👉"
      fzf_option_rounded="--border=rounded"
  else
      fzf_option_pointer=""
      fzf_option_rounded=""
  fi

  if [ ! -f $root_folder/scripts/cli/get_examples_list_with_fzf_fully_managed_connector_only ]
  then
    playground generate-fzf-find-files
  fi

  terminal_columns=$(tput cols)
  if [[ $terminal_columns -gt 180 ]]
  then
    MAX_LENGTH=$((${terminal_columns}-120))
  else
    MAX_LENGTH=$((${terminal_columns}-65))
  fi

  if [ -f $root_folder/scripts/cli/get_examples_list_with_fzf_repro_only ]
  then
    nb_repro=$(wc -l $root_folder/scripts/cli/get_examples_list_with_fzf_repro_only | awk '{print $1}')
  else
    nb_repro=0
  fi

  MENU_CONNECTOR="$(menu_label "🔗" "Connectors" "$(wc -l $root_folder/scripts/cli/get_examples_list_with_fzf_connector_only | awk '{print $1}') examples")"
  MENU_CCLOUD="$(menu_label "⛅" "Confluent cloud" "$(wc -l $root_folder/scripts/cli/get_examples_list_with_fzf_ccloud_only | awk '{print $1}') examples")"
  MENU_FULLY_MANAGED_CONNECTOR="$(menu_label "🤖" "Fully-Managed connectors" "$(wc -l $root_folder/scripts/cli/get_examples_list_with_fzf_fully_managed_connector_only | awk '{print $1}') examples")"
  MENU_REPRO="$(menu_label "🔧" "Reproduction models" "$nb_repro examples")"
  MENU_OTHER="$(menu_label "👾" "Other playgrounds" "$(wc -l $root_folder/scripts/cli/get_examples_list_with_fzf_other_playgrounds_only | awk '{print $1}') examples")"
  MENU_ENVIRONMENTS="$(menu_label "🔐" "Environments" "$(wc -l $root_folder/scripts/cli/get_examples_list_with_fzf_environment_only | awk '{print $1}') examples")"
  MENU_ALL="$(menu_label "🎲" "All" "$(wc -l $root_folder/scripts/cli/get_examples_list_with_fzf_all | awk '{print $1}') examples")"
  MENU_KSQL="$(menu_label "🎏" "ksqlDB" "$(wc -l $root_folder/scripts/cli/get_examples_list_with_fzf_ksql_only | awk '{print $1}') examples")"
  MENU_SR="$(menu_label "🔰" "Schema registry" "$(wc -l $root_folder/scripts/cli/get_examples_list_with_fzf_schema_registry_only | awk '{print $1}') examples")"
  MENU_RP="$(menu_label "🧲" "Rest proxy" "$(wc -l $root_folder/scripts/cli/get_examples_list_with_fzf_rest_proxy_only | awk '{print $1}') examples")"
  MENU_ACADEMY="$(menu_label "🎓" "Academy" "$(wc -l $root_folder/scripts/cli/get_examples_list_with_fzf_academy_only | awk '{print $1}') examples")"

  if [ "$repro" == 1 ]
  then
    propose_current_example=0
    set +e
    current_file=$(playground state get run.test_file)
    if [ $? -ne 0 ]
    then
      propose_current_example=0
    fi
    set -e
    if [ -f "$current_file" ]
    then
      last_two_folders=$(basename $(dirname $(dirname $current_file)))/$(basename $(dirname $current_file))
      filename=$(basename $current_file)
      current_file="$last_two_folders/$filename"

      if [[ $current_file != *"reproduction-models"* ]]
      then
        propose_current_example=1
      fi
    fi

    if [ $propose_current_example -eq 1 ]
    then
      MENU_CURRENT_EXAMPLE="$(menu_label "🎮" "Current example" "$current_file")"
      options=("$MENU_CURRENT_EXAMPLE" "$MENU_CONNECTOR" "$MENU_CCLOUD" "$MENU_FULLY_MANAGED_CONNECTOR" "$MENU_OTHER" "$MENU_ENVIRONMENTS" "$MENU_ALL" "$MENU_KSQL" "$MENU_SR" "$MENU_RP" "$MENU_ACADEMY")
    else
      options=("$MENU_CONNECTOR" "$MENU_CCLOUD" "$MENU_FULLY_MANAGED_CONNECTOR" "$MENU_OTHER" "$MENU_ENVIRONMENTS" "$MENU_ALL" "$MENU_KSQL" "$MENU_SR" "$MENU_RP" "$MENU_ACADEMY")
    fi
  else
    options=("$MENU_CONNECTOR" "$MENU_CCLOUD" "$MENU_FULLY_MANAGED_CONNECTOR" "$MENU_REPRO" "$MENU_OTHER" "$MENU_ENVIRONMENTS" "$MENU_ALL" "$MENU_KSQL" "$MENU_SR" "$MENU_RP" "$MENU_ACADEMY")
  fi

  set +e
  res=$(printf '%s\n' "${options[@]}" | fzf --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🚀" --header="select a category (ctrl-c or esc to quit)" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_pointer)
  set -e
  if [ -z "$res" ]
  then
    # esc or ctrl-c: an empty result would otherwise match the empty MENU_CURRENT_EXAMPLE below
    exit 0
  fi

  case "${res}" in
    "$MENU_CURRENT_EXAMPLE")
      test_file=$(playground state get run.test_file)
      if [ ! -f $test_file ]
      then
          logerror "❌ file $test_file retrieved from $root_folder/playground.ini does not exist!"
          exit 1
      fi
    ;;
    "$MENU_CONNECTOR")
      test_file=$(playground get-examples-list-with-fzf --connector-only)
    ;;
    "$MENU_CCLOUD")
      test_file=$(playground get-examples-list-with-fzf --ccloud-only)
    ;;
    "$MENU_FULLY_MANAGED_CONNECTOR")
      test_file=$(playground get-examples-list-with-fzf --fully-managed-connector-only)
    ;;
    "$MENU_REPRO")
      test_file=$(playground get-examples-list-with-fzf --repro-only)
    ;;
    "$MENU_ENVIRONMENTS")
      test_file=$(playground get-examples-list-with-fzf --environment-only)
    ;;
    "$MENU_KSQL")
      test_file=$(playground get-examples-list-with-fzf --ksql-only)
    ;;
    "$MENU_SR")
      test_file=$(playground get-examples-list-with-fzf --schema-registry-only)
    ;;
    "$MENU_RP")
      test_file=$(playground get-examples-list-with-fzf --rest-proxy-only)
    ;;
    "$MENU_ACADEMY")
      test_file=$(playground get-examples-list-with-fzf --academy-only)
    ;;
    "$MENU_OTHER")
      test_file=$(playground get-examples-list-with-fzf --other-playgrounds-only)
    ;;
    "$MENU_ALL")
      test_file=$(playground get-examples-list-with-fzf)
    ;;
    *)
      logerror "❌ wrong choice: $res"
      exit 1
    ;;
  esac
}

function cleanup_confluent_cloud_resources () {
  bootstrap_ccloud_environment

  log "🧹 cleanup resources for confluent cloud cluster $CLUSTER_NAME" 

  # for row in $(confluent api-key list --output json | jq -r '.[] | @base64'); do
  #     _jq() {
  #     echo ${row} | base64 -d | jq -r ${1}
  #     }
      
  #     key=$(echo $(_jq '.key'))
  #     resource_type=$(echo $(_jq '.resource_type'))

  #     if [[ $resource_type = cloud ]] && [[ "$key" != "$CONFLUENT_CLOUD_API_KEY" ]]
  #     then
  #       log "deleting cloud api key $key"
  #       confluent api-key delete $key --force
  #     fi
  # done

  cluster_id=$(get_ccloud_kafka_cluster_id)
  # dlq/success/error topics of the connectors deleted below
  connector_related_topics=""
  for row in $(confluent connect cluster list --output json | jq -r '.[] | @base64'); do
      _jq() {
      echo ${row} | base64 -d | jq -r ${1}
      }
      
      id=$(echo $(_jq '.id'))
      name=$(echo $(_jq '.name'))

      if [[ $name = *_${user}* ]]
      then
          connector_config=$(confluent connect cluster describe $id --output json 2>/dev/null | jq -c '(.configs // []) | map({(.config): .value}) | add // {}' 2>/dev/null)
          connector_related_topics="$connector_related_topics $(get_ccloud_connector_related_topics "$id" "$connector_config")"
          log "deleting connector $id ($name)"
          check_if_skip "confluent connect cluster delete $id --force || true"
      fi
  done

  for row in $(confluent environment list --output json | jq -r '.[] | @base64'); do
      _jq() {
      echo ${row} | base64 -d | jq -r ${1}
      }
      
      id=$(echo $(_jq '.id'))
      name=$(echo $(_jq '.name'))

      if [[ $name = pg-${user}-sa-* ]]
      then
          log "deleting environment $id ($name)"
          check_if_skip "confluent environment delete $id --force || true"
      fi
  done

  # service accounts created by --ccloud-service-account
  for id in $(confluent iam service-account list --output json | jq -r --arg p "pg-${user}-conn-" '.[] | select(.name | startswith($p)) | .id')
  do
      check_if_skip "delete_ccloud_connector_service_account $id"
  done

  existing_topics=$(confluent kafka topic list | awk '{if(NR>2) print $1}')
  if [ ! -z "$GITHUB_RUN_NUMBER" ] || [[ $CLUSTER_NAME = pg-${user}-* ]]
  then
    # cluster created by the playground for this user (or CI): nobody else uses it
    topics_to_delete="$existing_topics"
  else
    # cluster provided with CLUSTER_NAME, possibly shared with other people: only delete
    # topics created by this user's playground runs and by this user's connectors
    logwarn "🤝 cluster $CLUSTER_NAME was not created by the playground for user $user, it may be shared: only deleting topics recorded as created by your runs and connectors, and dlq/success/error topics of your connectors"
    logwarn "🎓 to delete topics anyway, use: playground topic delete --topic <topic or regex>"
    topics_to_delete=$( { get_ccloud_recorded_topics_matching "$cluster_id" "$existing_topics"; echo "$connector_related_topics" | tr ' ' '\n' | grep -Fx -f <(echo "$existing_topics"); } | grep -v '^$' | sort -u)
  fi

  for topic in $topics_to_delete
  do
      log "delete topic $topic"
      check_if_skip "confluent kafka topic delete \"$topic\" --force || true"
  done
  # their subjects (TopicNameStrategy), deleted below in CI
  deleted_topics="$topics_to_delete"

  # forget recorded topics and connectors that are gone (deleted above or by someone else)
  # only when both listings succeed, an empty list would forget everything; not in a dry-run (nothing was deleted)
  if [[ -z "${dry_run:-}" ]] && topics_json=$(confluent kafka topic list --output json) && connectors_json=$(confluent connect cluster list --output json)
  then
    prune_ccloud_recorded_entries "$cluster_id" "$(echo "$topics_json" | jq -r '.[].name')" "$(echo "$connectors_json" | jq -r '.[].name')"
  fi

  if [ ! -z "$GITHUB_RUN_NUMBER" ]
  then
    # only the subjects of the topics deleted above (<topic>-key, <topic>-value): the Schema Registry is shared by every
    # cluster of the environment
    local subject
    local subject_topic
    for subject in $(curl -s -u "$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" "$SCHEMA_REGISTRY_URL/subjects" | jq -r '.[]' 2>/dev/null)
    do
        case "$subject" in
          *-key) subject_topic="${subject%-key}" ;;
          *-value) subject_topic="${subject%-value}" ;;
          *) continue ;;
        esac
        if echo "$deleted_topics" | grep -Fxq -e "$subject_topic"
        then
            log "permanently delete subject $subject"
            check_if_skip "curl --request DELETE -u \"$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO\" \"$SCHEMA_REGISTRY_URL/subjects/$subject\" && curl --request DELETE -u \"$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO\" \"$SCHEMA_REGISTRY_URL/subjects/$subject?permanent=true\""
        fi
    done

    # only the service accounts created by the playground (pg-<user>-app-*, pg-<user>-conn-*): the organization also
    # holds the service accounts that own the API keys used by CI
    for row in $(confluent iam service-account list --output json | jq -r --arg p "pg-${user}-" '.[] | select(.name | startswith($p)) | @base64'); do
        _jq() {
        echo ${row} | base64 -d | jq -r ${1}
        }

        description=$(echo $(_jq '.description'))
        id=$(echo $(_jq '.id'))
        name=$(echo $(_jq '.name'))

        log "deleting service-account $id $name ($description)"
        check_if_skip "confluent iam service-account delete $id --force || true"
    done
  fi
}

# Remind the user what is still alive (and billed) on the Confluent Cloud cluster: connectors
# named *_<user> and the topics 'playground cloud-resources cleanup' would delete
function display_ccloud_leftovers () {
  local user="${USER}"
  local max_names=5
  get_kafka_docker_playground_dir
  local delta="$KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta"
  if [ ! -f "$delta" ]
  then
    return 0
  fi
  local environment_id
  local cluster_id
  local cluster_name
  environment_id=$(grep "ENVIRONMENT ID" "$delta" | cut -d " " -f 4)
  cluster_id=$(get_ccloud_kafka_cluster_id)
  cluster_name=$(playground state get ccloud.CLUSTER_NAME)
  if [ -z "$environment_id" ] || [ -z "$cluster_id" ]
  then
    return 0
  fi

  local connectors
  local existing_topics
  local topics
  local connectors_json
  connectors_json=$(confluent connect cluster list --environment "$environment_id" --cluster "$cluster_id" --output json 2>/dev/null | jq -c --arg u "_$user" '[.[] | select(.name | contains($u))]' 2>/dev/null)
  connectors=$(echo "$connectors_json" | jq -r '.[].name' 2>/dev/null | sort)
  # grep -v exits with 1 when every topic is internal (or there is none): without || true, set -e ends the command
  # here, silently, and playground run of a successful example exits with 1
  existing_topics=$(confluent kafka topic list --environment "$environment_id" --cluster "$cluster_id" --output json 2>/dev/null | jq -r '.[].name' 2>/dev/null | grep -v '^_' || true)
  if [[ $cluster_name = pg-${user}-* ]]
  then
    # cluster created by the playground for this user: every topic is theirs
    topics="$existing_topics"
  else
    # recorded topics, plus default dlq/success/error topics of the connectors above
    topics=$( { get_ccloud_recorded_topics_matching "$cluster_id" "$existing_topics"; for id in $(echo "$connectors_json" | jq -r '.[].id' 2>/dev/null); do get_ccloud_connector_related_topics "$id" "" | grep -Fx -f <(echo "$existing_topics"); done; } | grep -v '^$' | sort -u)
  fi

  local nb_connectors
  local nb_topics
  # grep -c exits with 1 when it counts 0: without || true, set -e ends the command right here
  nb_connectors=$(echo "$connectors" | grep -c . || true)
  nb_topics=$(echo "$topics" | grep -c . || true)
  if [ "$nb_connectors" -eq 0 ] && [ "$nb_topics" -eq 0 ]
  then
    log "✨ no connector or topic of yours left on cluster $cluster_name ($cluster_id)"
    return 0
  fi

  logwarn "🧹 still alive on cluster $cluster_name ($cluster_id):"
  if [ "$nb_connectors" -gt 0 ]
  then
    logwarn "   🔗 $nb_connectors connector(s), billed while they exist: $(echo "$connectors" | head -$max_names | paste -sd ',' - | sed 's/,/, /g')$( [ "$nb_connectors" -gt $max_names ] && echo ', ...')"
  fi
  if [ "$nb_topics" -gt 0 ]
  then
    logwarn "   📝 $nb_topics topic(s): $(echo "$topics" | head -$max_names | paste -sd ',' - | sed 's/,/, /g')$( [ "$nb_topics" -gt $max_names ] && echo ', ...')"
  fi
  logwarn "🧹 delete them with <playground cloud-resources cleanup --resource ccloud>"
}

# Forget recorded entries of a cluster that match nothing anymore: topics not in $2, prefixes
# no topic of $2 starts with, connectors not in $3 (lists of existing topic and connector names)
function prune_ccloud_recorded_entries () {
  local cluster_id="$1"
  local existing_topics="$2"
  local existing_connectors="$3"
  local entry
  for entry in $(get_ccloud_recorded_entries "$cluster_id")
  do
      if [[ $entry == connector:* ]]
      then
          if ! echo "$existing_connectors" | grep -qFx -- "${entry#connector:}"
          then
              forget_ccloud_recorded_topic "$cluster_id" "$entry"
          fi
      elif [[ $entry == prefix:* ]]
      then
          if ! echo "$existing_topics" | awk -v p="${entry#prefix:}" 'index($0, p) == 1 {found=1} END {exit !found}'
          then
              forget_ccloud_recorded_topic "$cluster_id" "$entry"
          fi
      elif ! echo "$existing_topics" | grep -qFx -- "$entry"
      then
          forget_ccloud_recorded_topic "$cluster_id" "$entry"
      fi
  done
}

# Topics that the connectors of the cluster read or write, as set in their config, in one call to the Connect API:
# "exact <topic> <connector>", "prefix <topic prefix> <connector>" and "regex <topics.regex> <connector>" lines.
# Fails when the API can't be reached.
function get_ccloud_topics_used_by_connectors () {
  local output
  # in a subshell: get_ccloud_connect exits when a setting is missing
  output=$(get_ccloud_connect > /dev/null 2>&1 && curl -s --fail --request GET "https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors?expand=info" --header "authorization: Basic $authorization") || return 1
  echo "$output" | jq -r 'to_entries[] | .key as $c | (.value.info.config // {}) | to_entries[]
    | if (.key | test("^topics\\.regex$")) then (.value | tostring | select(. != "") | "regex \(.) \($c)")
      elif (.key | test("(^|\\.)topic\\.prefix$|^database\\.server\\.name$")) then (.value | tostring | select(. != "") | "prefix \(.) \($c)")
      elif (.key | test("(^|\\.)topics?(\\.name)?$")) then (.value | tostring | split(",")[] | gsub(" "; "") | select(. != "") | "exact \(.) \($c)")
      else empty end' 2>/dev/null
}

# The topics of $1 (one per line) that no connector of the cluster reads or writes, except the connectors named in $2
# (being deleted). The cluster can be shared: by the parallel CI jobs, which use the same topic names in a few examples
# (users, http-topic...), or by people of a team. Logs on stderr the topics kept and why.
function filter_ccloud_topics_not_used_by_connectors () {
  local topics="$1"
  local ignored_connectors="$2"
  local used
  if ! used=$(get_ccloud_topics_used_by_connectors)
  then
    logwarn "🧹 could not read the configs of the connectors of the cluster, keeping the topics: $(echo "$topics" | paste -sd ',' - | sed 's/,/, /g')" >&2
    return 0
  fi
  local topic
  local kind
  local value
  local connector
  local kept
  for topic in $topics
  do
    kept=""
    while read -r kind value connector
    do
      if [ -z "$kind" ] || echo "$ignored_connectors" | grep -Fxq -- "$connector"
      then
        continue
      fi
      case "$kind" in
        exact) [ "$topic" == "$value" ] && kept="$connector" ;;
        prefix) [[ "$topic" == "$value"* ]] && kept="$connector" ;;
        regex) [[ "$topic" =~ ^($value)$ ]] && kept="$connector" ;;
      esac
      if [ -n "$kept" ]
      then
        break
      fi
    done <<< "$used"
    if [ -n "$kept" ]
    then
      log "⏭️ keeping topic $topic: connector $kept uses it" >&2
    else
      echo "$topic"
    fi
  done
}

# Delete the topics recorded in playground-ccloud-created-topics (by every run) that are still on the cluster, except
# the ones a connector of the cluster uses. Called by run-tests.sh at the end of each CI job
# (playground cloud-resources cleanup --recorded-topics-only): it catches the topics kept at the end of a run because a
# connector of another job used them, and the ones of a run killed before its cleanup. The podman nightly has no
# cleanup job, which would delete the resources of people using the cluster during the day.
function cleanup_ccloud_recorded_topics () {
  if ! command -v confluent > /dev/null 2>&1
  then
    return 0
  fi
  local cluster_id
  local environment_id
  cluster_id=$(get_ccloud_kafka_cluster_id)
  environment_id=$(get_ccloud_environment_id)
  if [ -z "$cluster_id" ] || [ -z "$environment_id" ]
  then
    return 0
  fi
  local cluster_flags="--environment $environment_id --cluster $cluster_id"
  local topics_json
  local connectors_json
  local topics_to_delete
  local topic
  if ! topics_json=$(confluent kafka topic list $cluster_flags --output json 2>/dev/null)
  then
    logwarn "🧹 could not list the topics of cluster $cluster_id, skipping the cleanup of the recorded topics"
    return 0
  fi
  topics_to_delete=$(get_ccloud_recorded_topics_matching "$cluster_id" "$(echo "$topics_json" | jq -r '.[].name' 2>/dev/null)")
  if [ -n "$topics_to_delete" ]
  then
    topics_to_delete=$(filter_ccloud_topics_not_used_by_connectors "$topics_to_delete")
  fi
  if [ -z "$topics_to_delete" ]
  then
    log "🧹 no recorded topic to delete on cluster $cluster_id"
    return 0
  fi
  for topic in $topics_to_delete
  do
      log "❌ deleting topic $topic"
      confluent kafka topic delete "$topic" $cluster_flags --force > /dev/null 2>&1 || logwarn "❌ failed to delete topic $topic"
  done
  if topics_json=$(confluent kafka topic list $cluster_flags --output json 2>/dev/null) && connectors_json=$(confluent connect cluster list $cluster_flags --output json 2>/dev/null)
  then
    prune_ccloud_recorded_entries "$cluster_id" "$(echo "$topics_json" | jq -r '.[].name' 2>/dev/null)" "$(echo "$connectors_json" | jq -r '.[].name' 2>/dev/null)"
  fi
}

# Delete the Confluent Cloud connectors and topics created by the last ccloud 'playground run'
# (recorded with its run id in playground-ccloud-created-topics). Called by 'playground stop'
# and at the start of the next 'playground run', so interrupted examples don't leave billed
# connectors behind. Each run is handled once: deleted, or kept when the user says no.
# Behaviour: 'playground config cleanup-ccloud-resources-after-run ask|true|false' (default ask)
# In CI it is also called at the end of every 'playground run' (success, failure or timeout), without asking: the
# cluster is shared by the parallel jobs, so a topic of the run is kept when a connector of another job uses it (same
# topic name or prefix in a few examples). run-tests.sh deletes those at the end of the job.
function maybe_cleanup_ccloud_run_resources () {
  local ci_mode=0
  if [ ! -z "$GITHUB_RUN_NUMBER" ]
  then
    ci_mode=1
  fi
  if [ "$(playground state get run.environment)" != "ccloud" ]
  then
    return 0
  fi
  local run_id
  run_id=$(playground state get run.ccloud_run_id)
  if [ -z "$run_id" ] || [ "$(playground state get run.ccloud_run_cleaned)" == "$run_id" ]
  then
    return 0
  fi
  local mode
  mode=$(playground config get cleanup-ccloud-resources-after-run)
  mode=${mode:-ask}
  if [ $ci_mode -eq 1 ]
  then
    mode="true"
  fi
  if [ "$mode" == "false" ]
  then
    return 0
  fi
  if ! command -v confluent > /dev/null 2>&1
  then
    return 0
  fi
  local cluster_id
  local environment_id
  cluster_id=$(get_ccloud_kafka_cluster_id)
  environment_id=$(get_ccloud_environment_id)
  if [ -z "$cluster_id" ] || [ -z "$environment_id" ]
  then
    return 0
  fi
  local run_connectors
  run_connectors=$(get_ccloud_recorded_connectors "$cluster_id" "$run_id")
  if [ -z "$run_connectors" ] && [ -z "$(get_ccloud_recorded_topics "$cluster_id" "$run_id")" ]
  then
    playground state set run.ccloud_run_cleaned "$run_id"
    return 0
  fi

  local cluster_flags="--environment $environment_id --cluster $cluster_id"
  local topics_json
  local connectors_json
  if ! topics_json=$(confluent kafka topic list $cluster_flags --output json 2>/dev/null) || ! connectors_json=$(confluent connect cluster list $cluster_flags --output json 2>/dev/null)
  then
    logwarn "🧹 could not list resources of cluster $cluster_id (logged out of Confluent Cloud?), skipping cleanup of the last ccloud run"
    return 0
  fi
  local existing_topics
  existing_topics=$(echo "$topics_json" | jq -r '.[].name' 2>/dev/null)

  # connectors of the run that still exist, as "<lcc id> <name>", and the topics they created
  local connectors_to_delete=""
  local topics_to_delete
  local related_topics=""
  local name
  local id
  local connector_config
  for name in $run_connectors
  do
      id=$(echo "$connectors_json" | jq -r --arg n "$name" '.[] | select(.name == $n) | .id' 2>/dev/null)
      if [ -n "$id" ]
      then
          connectors_to_delete="$connectors_to_delete$id $name"$'\n'
          connector_config=$(confluent connect cluster describe $id $cluster_flags --output json 2>/dev/null | jq -c '(.configs // []) | map({(.config): .value}) | add // {}' 2>/dev/null)
          related_topics="$related_topics $(get_ccloud_connector_related_topics "$id" "$connector_config")"
      fi
  done
  connectors_to_delete=$(echo "$connectors_to_delete" | grep -v '^$')
  topics_to_delete=$( { get_ccloud_recorded_topics_matching "$cluster_id" "$existing_topics" "$run_id"; echo "$related_topics" | tr ' ' '\n' | grep -Fx -f <(echo "$existing_topics"); } | grep -v '^$' | sort -u)

  if [ -z "$connectors_to_delete" ] && [ -z "$topics_to_delete" ]
  then
    # the connectors of the run are gone, so are the service accounts they used
    cleanup_ccloud_connector_service_accounts "$run_id"
    prune_ccloud_recorded_entries "$cluster_id" "$existing_topics" "$(echo "$connectors_json" | jq -r '.[].name' 2>/dev/null)"
    playground state set run.ccloud_run_cleaned "$run_id"
    return 0
  fi

  log "🧹 the last ccloud example ($(basename "$(playground state get run.test_file)")) left these on cluster $(playground state get ccloud.CLUSTER_NAME) ($cluster_id):"
  if [ -n "$connectors_to_delete" ]
  then
    log "   🔗 connector(s), billed while they exist: $(echo "$connectors_to_delete" | awk '{print $2}' | paste -sd ',' - | sed 's/,/, /g')"
  fi
  if [ -n "$topics_to_delete" ]
  then
    log "   📝 topic(s): $(echo "$topics_to_delete" | paste -sd ',' - | sed 's/,/, /g')"
  fi

  if [ "$mode" != "true" ]
  then
    if [ ! -t 0 ]
    then
      logwarn "🧹 not running interactively, keeping them. Delete them with <playground cloud-resources cleanup --resource ccloud>, or set <playground config cleanup-ccloud-resources-after-run true>"
      return 0
    fi
    local reply
    read -p "🧹 Delete them? (y/n) " reply
    if [[ ! "$reply" =~ ^[yY] ]]
    then
      log "🧹 keeping them. Never ask again with <playground config cleanup-ccloud-resources-after-run false>, always delete with <playground config cleanup-ccloud-resources-after-run true>"
      playground state set run.ccloud_run_cleaned "$run_id"
      return 0
    fi
  fi

  local topic
  while read -r id name
  do
      if [ -n "$id" ]
      then
          log "❌ deleting connector $name ($id)"
          confluent connect cluster delete $id $cluster_flags --force > /dev/null 2>&1 || logwarn "❌ failed to delete connector $name ($id)"
      fi
  done <<< "$connectors_to_delete"
  # service accounts created by --ccloud-service-account for the connectors of the run
  cleanup_ccloud_connector_service_accounts "$run_id"
  if [ $ci_mode -eq 1 ] && [ -n "$topics_to_delete" ]
  then
      # shared by the parallel jobs: keep the topics a connector of another job uses (the ones of the run, just deleted, can still be listed)
      topics_to_delete=$(filter_ccloud_topics_not_used_by_connectors "$topics_to_delete" "$(echo "$connectors_to_delete" | awk '{print $2}')")
  fi
  for topic in $topics_to_delete
  do
      log "❌ deleting topic $topic"
      confluent kafka topic delete "$topic" $cluster_flags --force > /dev/null 2>&1 || logwarn "❌ failed to delete topic $topic"
  done

  # only when both listings succeed, an empty list would forget everything
  if topics_json=$(confluent kafka topic list $cluster_flags --output json 2>/dev/null) && connectors_json=$(confluent connect cluster list $cluster_flags --output json 2>/dev/null)
  then
    prune_ccloud_recorded_entries "$cluster_id" "$(echo "$topics_json" | jq -r '.[].name' 2>/dev/null)" "$(echo "$connectors_json" | jq -r '.[].name' 2>/dev/null)"
  fi
  playground state set run.ccloud_run_cleaned "$run_id"
}

function get_zazkia_id_list () {
  handle_onprem_connect_rest_api "curl -s -X GET -H \"Content-Type: application/json\" \"http://localhost:9191/links/\""
  if [[ $(echo "$curl_output" | jq -r '.[].links[]') != "" ]]
  then
    echo "$curl_output" | jq -r '.[].links[] | select(.serviceReceiveError != "EOF") | .id' | tr '\n' ' ' | sed -e 's/[[:space:]]*$//'
  else
    echo ""
  fi
}

function wait_for_ec2_instance_to_be_running () {
  instance="$1"
  max_wait=${2:-300}
  cur_wait=0
  log "⌛ waiting up to $max_wait seconds for ec2 instance $instance to be running"
  playground ec2 status --instance "$instance" > /tmp/out.txt 2>&1
  while ! grep "running" /tmp/out.txt > /dev/null;
  do
    sleep 10
    playground ec2 status --instance "$instance" > /tmp/out.txt 2>&1
    status=$(cat /tmp/out.txt)
    log "⌛ current status: $status"
    cur_wait=$(( cur_wait+10 ))
    if [[ "$cur_wait" -gt "$max_wait" ]]
    then
      logerror "❌ ec2 instance $instance is still not running after $max_wait seconds"
      return 1
    fi
  done
  log "🟢 ec2 instance $instance is running"
}

function wait_for_ec2_cloudformation_to_be_completed () {
  stack_name="$1"
  max_wait=${2:-900}
  cur_wait=0
  log "⌛ waiting up to $max_wait seconds for ec2 cloudformation stack $stack_name to be in status CREATE_COMPLETE"
  log "⌛ you can check progress by checking log file output.log in root folder of ec2 instance"

  aws cloudformation describe-stacks --output text --query "Stacks[?StackName==\`$stack_name\`].StackStatus" > /tmp/out.txt 2>&1
  while ! grep "CREATE_COMPLETE" /tmp/out.txt > /dev/null;
  do
    sleep 10
    aws cloudformation describe-stacks --output text --query "Stacks[?StackName==\`$stack_name\`].StackStatus" > /tmp/out.txt 2>&1
    status=$(cat /tmp/out.txt)
    log "⌛ current status: $status"

    if grep "CREATE_FAILED" /tmp/out.txt > /dev/null;
    then
      logerror "❌ ec2 cloudformation stack $stack_name is in state $status"
      logerror "❌ check log file output.log in root folder of ec2 instance for troubleshooting the issue"
      return 1
    fi

    if grep "ROLLBACK_" /tmp/out.txt > /dev/null;
    then
      logerror "❌ ec2 cloudformation stack $stack_name is in state $status"
      logerror "❌ check log file output.log in root folder of ec2 instance for troubleshooting the issue"
      return 1
    fi

    cur_wait=$(( cur_wait+10 ))
    if [[ "$cur_wait" -gt "$max_wait" ]]
    then
      logerror "❌ ec2 cloudformation $stack_name is still not in status CREATE_COMPLETE after $max_wait seconds"
      logerror "❌ check log file output.log in root folder of ec2 instance for troubleshooting the issue"
      return 1
    fi
  done
  log "🟢 ec2 cloudformation $stack_name is in status CREATE_COMPLETE"
}

function add_ec2_instance_to_running_list() {
  instance="$1"
  current_list=$(playground state get "ec2.running_list")
  # list can be separated with |
  if [[ "$current_list" == "" ]]
  then
    playground state set "ec2.running_list" "$instance"
  else
    # make sure insance is not already in the list
    if [[ "$current_list" != *"$instance"* ]]
    then
      playground state set "ec2.running_list" "$current_list|$instance"
    fi
  fi
}

function remove_ec2_instance_from_running_list() {
  instance="$1"
  current_list=$(playground state get "ec2.running_list")
  # list can be separated with |
  if [[ "$current_list" != "" ]]
  then
    # make sure insance is not already in the list
    if [[ "$current_list" == *"$instance"* ]]
    then
      new_list=$(echo "$current_list" | sed -e "s/$instance//g" | sed -e 's/||/|/g' | sed -e 's/|$//')
      playground state set "ec2.running_list" "$new_list"
    fi
  fi
}

function check_for_ec2_instance_running() {
  # echo the name of ec2 instance running
  current_list=$(playground state get "ec2.running_list")
  if [[ "$current_list" != "" ]]
  then
    # loop through the list
    for instance in $(echo $current_list | tr "|" "\n")
    do
      echo ""
      echo ""
      log "💸💸💸💸💸💸💸💸💸💸💸💸💸💸💸💸💸💸💸💸💸💸💸"
      log "🤑 you have an ec2 instance $instance running !"
      log "💸💸💸💸💸💸💸💸💸💸💸💸💸💸💸💸💸💸💸💸💸💸💸"
    done
  fi
}

function open_file_with_editor() {
  filename="$1"
  wait="$2"

	if [ ! -z "$GITHUB_RUN_NUMBER" ]
	then
		# running with CI
		return
	fi
  editor=$(playground config get editor)
  if [ "$editor" != "" ] && command -v "$editor" > /dev/null
  then
    log "📖 opening ${filename} using configured editor \"$editor\" (you can change editor by using \"playground config set editor <editor>\")"
    if [ "$editor" = "code" ] && [ "$wait" != "" ]
    then
      code --wait ${filename}
    else
      $editor ${filename}
    fi
  else
    logerror "❌ editor \"$editor\" is not installed - you can change editor by using \"playground config set editor <editor>\""
    exit 1
  fi
}

function arm64_support() {

  test_file=$(playground state get run.test_file)

  if [ ! -f $test_file ]
  then 
    return
  fi

  set +e
  if [ "$(uname -m)" = "arm64" ]
  then
    base_folder=$(basename $(dirname $(dirname $test_file)))
    base_test=$(basename $(dirname $test_file))
    if [ "$base_folder" == "reproduction-models" ]
    then
      base_test=${base_test#*-}
    fi

    grep "${base_test}" ${root_folder}/scripts/arm64-support-none.txt > /dev/null
    if [ $? = 0 ]
    then
      echo "❌💻 this example is not working with ARM64 !"
      echo "❌💻 it is highly recommended to use 'playground ec2 command' to run the example on ubuntu ec2 instance"
      echo "❌💻 you can also run it in your browser with GitHub Codespaces (x86_64): https://codespaces.new/vdesabou/kafka-docker-playground?quickstart=1"
      return
    fi

    grep "${base_test}" ${root_folder}/scripts/arm64-support-with-emulation.txt > /dev/null
    if [ $? = 0 ]
    then
        echo "🔶💻 this example is working with ARM64 but requires emulation"
        return
    fi

    echo "✅💻 this example should work natively with ARM64"
  fi
  set -e
}


# Convert JSON connector config to Terraform HCL format
# This function generates a Terraform configuration for a Confluent Cloud connector
function json_to_terraform_connector() {
    local connector_name="$1"
    local json_content="$2"
    local output_file="$3"
    local environment_id="$4"
    local cluster_id="$5"

    # Extract connector.class from JSON
    local connector_class=$(echo "$json_content" | jq -r '."connector.class"')
    # a terraform resource name: letters, digits, "_" and "-", not starting with a digit
    local resource_name=$(echo "$connector_name" | sed -E 's/[^A-Za-z0-9_-]/_/g; s/^([^A-Za-z_])/_\1/')

    # Remove connector.class from config
    local config=$(echo "$json_content" | jq 'del(."connector.class")')

    # Separate sensitive and non-sensitive configs
    # Sensitive field patterns: password, secret, token, credentials, sasl.jaas, api_key, etc.
    # Also matches dot-notation fields ending with .key, .secret, .token, .password (e.g., kafka.api.key, aws.secret.access.key)
    local config_sensitive=$(echo "$config" | jq 'with_entries(select(.key | test("password|secret|token|credentials|credential|sasl\\.jaas|api_key|access_key|private_key|secret_key|auth_token|bearer_token|aws_secret|aws_access|azure_key|gcp_key|\\.key$|\\.secret$|\\.token$|\\.password$"; "i")))')
    local config_nonsensitive=$(echo "$config" | jq 'with_entries(select(.key | test("password|secret|token|credentials|credential|sasl\\.jaas|api_key|access_key|private_key|secret_key|auth_token|bearer_token|aws_secret|aws_access|azure_key|gcp_key|\\.key$|\\.secret$|\\.token$|\\.password$"; "i") | not))')

    # Create Terraform configuration
    cat > "$output_file" << EOF
terraform {
  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = "~> 2.0"
    }
  }
}

provider "confluent" {
  # Uses CONFLUENT_CLOUD_API_KEY and CONFLUENT_CLOUD_API_SECRET env vars
}

resource "confluent_connector" "${resource_name}" {
  environment {
    id = "${environment_id}"
  }

  kafka_cluster {
    id = "${cluster_id}"
  }

  config_nonsensitive = {
    "connector.class" = "${connector_class}"
EOF

    # Add non-sensitive config parameters from JSON
    # @json escapes quotes and backslashes (sasl.jaas.config...), $${ and %%{ keep "${" and "%{" from being interpolated
    echo "$config_nonsensitive" | jq -r 'to_entries[] | "    \(.key | @json) = \(.value | tostring | @json | gsub("\\$\\{"; "$${") | gsub("%\\{"; "%%{"))"' >> "$output_file"

    # Add sensitive config parameters
    if [ "$(echo "$config_sensitive" | jq 'length')""%" != "0%" ]; then
        cat >> "$output_file" << 'EOF'
  }

  config_sensitive = {
EOF
        echo "$config_sensitive" | jq -r 'to_entries[] | "    \(.key | @json) = \(.value | tostring | @json | gsub("\\$\\{"; "$${") | gsub("%\\{"; "%%{"))"' >> "$output_file"
        cat >> "$output_file" << 'EOF'
  }
EOF
    else
        cat >> "$output_file" << 'EOF'
  }

  config_sensitive = {}
EOF
    fi

    cat >> "$output_file" << 'EOF'

  lifecycle {
    prevent_destroy = false
  }
}

output "connector_id" {
  value = confluent_connector.${connector_name}.id
}

output "connector_status" {
  value = confluent_connector.${connector_name}.status
}
EOF

    # Replace ${connector_name} in output with actual connector name
    sed -i.bak "s/\${connector_name}/${resource_name}/g" "$output_file"
    rm -f "${output_file}.bak"
}

# Deploy connector using Terraform
function deploy_connector_with_terraform() {
    local connector_name="$1"
    local json_content="$2"
    local environment_id="$3"
    local cluster_id="$4"
    local terraform_base_dir=""
    local terraform_dir=""

    get_kafka_docker_playground_dir

    terraform_base_dir="$KAFKA_DOCKER_PLAYGROUND_DIR/.terraform-playground"
    # the .tf files and the terraform.tfstate hold the secrets of the connectors
    mkdir -p "$terraform_base_dir"
    chmod 700 "$terraform_base_dir"
    # the folder of a previous deployment of this connector: terraform apply then updates it, a new folder would try to
    # create a connector that already exists
    terraform_dir=$(playground state get "terraform.connector.$connector_name" 2> /dev/null)
    local import_existing=0
    if [ -n "$terraform_dir" ] && [ -f "$terraform_dir/terraform.tfstate" ]
    then
        log "♻️ connector $connector_name was deployed with Terraform before: its state is reused, terraform apply updates it"
    else
        terraform_dir=$(mktemp -d "$terraform_base_dir/${connector_name}-XXXXXXXXXX")
        # created with the REST API (or the state is gone): imported, so that it is updated instead of created again
        if [ "${is_create:-1}" == "0" ]
        then
            import_existing=1
        fi
    fi
    log "📂 Terraform directory: $terraform_dir"

    local tf_file="${terraform_dir}/connector.tf"

    log "🏗️ Generating Terraform configuration for connector $connector_name"
    json_to_terraform_connector "$connector_name" "$json_content" "$tf_file" "$environment_id" "$cluster_id"

    chmod 600 "$tf_file"
    local resource_name=$(echo "$connector_name" | sed -E 's/[^A-Za-z0-9_-]/_/g; s/^([^A-Za-z_])/_\1/')

    if [ -z "$GITHUB_RUN_NUMBER" ]
    then
      log "📄 Generated Terraform configuration (values of config_sensitive masked):"
      awk '/^  config_sensitive = \{$/ { in_sensitive = 1; print; next } in_sensitive && /^  \}/ { in_sensitive = 0 } in_sensitive { sub(/= .*/, "= \"****\"") } { print }' "$tf_file" | sed 's/^/    /'
    fi

    # Initialize Terraform
    log "🔧 Initializing Terraform..."
    if [[ -n "$verbose" ]]
    then
        log "🐞 CLI command used"
        echo "cd $terraform_dir && terraform init -no-color" >&2
    fi
    if ! (cd "$terraform_dir" && terraform init -no-color > /tmp/terraform-init.log 2>&1)
    then
        logerror "❌ Terraform init failed. See /tmp/terraform-init.log for details"
        cat /tmp/terraform-init.log
        exit 1
    fi

    # Validate Terraform configuration
    log "✅ Validating Terraform configuration..."
    if [[ -n "$verbose" ]]
    then
        log "🐞 CLI command used"
        echo "cd $terraform_dir && terraform validate -no-color" >&2
    fi
    if ! (cd "$terraform_dir" && terraform validate -no-color > /tmp/terraform-validate.log 2>&1)
    then
        logerror "❌ Terraform validation failed. See /tmp/terraform-validate.log for details"
        cat /tmp/terraform-validate.log
        exit 1
    fi

    if [ $import_existing -eq 1 ]
    then
        log "📥 connector $connector_name already exists: importing it into the Terraform state"
        if ! (cd "$terraform_dir" && terraform import -no-color "confluent_connector.$resource_name" "$environment_id/$cluster_id/$connector_name" > /tmp/terraform-import.log 2>&1)
        then
            logerror "❌ Terraform import failed. See /tmp/terraform-import.log for details"
            cat /tmp/terraform-import.log
            exit 1
        fi
    fi

    # Plan Terraform changes
    log "📋 Planning Terraform changes..."
    if [[ -n "$verbose" ]]
    then
        log "🐞 CLI command used"
        echo "cd $terraform_dir && terraform plan -no-color -out=tfplan" >&2
    fi
    if ! (cd "$terraform_dir" && terraform plan -no-color -out=tfplan > /tmp/terraform-plan.log 2>&1)
    then
        logerror "❌ Terraform plan failed. See /tmp/terraform-plan.log for details"
        cat /tmp/terraform-plan.log
        exit 1
    fi

    # Show plan summary
    if [ -z "$GITHUB_RUN_NUMBER" ]
    then
        log "📊 Terraform plan summary:"
        if [[ -n "$verbose" ]]
        then
            log "🐞 CLI command used"
            echo "cd $terraform_dir && terraform show -no-color tfplan" >&2
        fi
        # the resource actions (terraform shows "(sensitive value)" for config_sensitive), up to the Plan: line
        # with "No changes" (the same config again) there is nothing between these lines: grep would return 1 and end
        # the command under set -e
        local plan_summary
        plan_summary=$(cd "$terraform_dir" && terraform show -no-color tfplan | sed -n '/will perform the following actions/,/^Plan:/p' | grep -vE '^\s*$' || true)
        if [ -n "$plan_summary" ]
        then
            echo "$plan_summary"
        else
            log "💤 No changes: the connector already matches the configuration"
        fi
    fi

    # Apply Terraform changes
    log "🚀 Applying Terraform configuration..."
    if [[ -n "$verbose" ]]
    then
        log "🐞 CLI command used"
        echo "cd $terraform_dir && terraform apply -no-color -auto-approve tfplan" >&2
    fi
    if ! (cd "$terraform_dir" && terraform apply -no-color -auto-approve tfplan > /tmp/terraform-apply.log 2>&1)
    then
        logerror "❌ Terraform apply failed. See /tmp/terraform-apply.log for details"
        cat /tmp/terraform-apply.log
        exit 1
    fi

    # Get outputs
    if [[ -n "$verbose" ]]
    then
        log "🐞 CLI command used"
        echo "cd $terraform_dir && terraform output -raw connector_id" >&2
    fi
    local connector_id=$(cd "$terraform_dir" && terraform output -raw connector_id 2>/dev/null)
    if [[ -n "$verbose" ]]
    then
        log "🐞 CLI command used"
        echo "cd $terraform_dir && terraform output -raw connector_status" >&2
    fi
    local connector_status=$(cd "$terraform_dir" && terraform output -raw connector_status 2>/dev/null)

    log "✅ Terraform deployment completed successfully"
    if [[ -n "$connector_id" ]]
    then
        log "📌 Connector ID: $connector_id"
    fi
    if [[ -n "$connector_status" ]]
    then
        log "📊 Connector Status: $connector_status"
    fi

    # Save terraform state path for future operations
    playground state set terraform.state_dir "$terraform_dir"
    playground state set terraform.connector.$connector_name "$terraform_dir"

    # Return path via global variable to avoid stdout capture swallowing log output
    TERRAFORM_DEPLOY_DIR="$terraform_dir"
}

# connector deployed with 'connector create-or-update --terraform': terraform destroy in its folder, so that its state
# does not keep a connector that no longer exists. Returns 1 when the connector was not deployed with Terraform, or when
# destroy failed: the caller then deletes it with the REST API
function destroy_terraform_connector() {
    local connector_name="$1"
    local terraform_dir
    terraform_dir=$(playground state get "terraform.connector.$connector_name" 2> /dev/null)
    if [ -z "$terraform_dir" ] || [ ! -f "$terraform_dir/terraform.tfstate" ]
    then
        return 1
    fi
    if ! command -v terraform > /dev/null 2>&1
    then
        logwarn "⚠️ connector $connector_name was deployed with Terraform ($terraform_dir), but terraform is not installed: it is deleted with the REST API"
        return 1
    fi
    load_secrets_env_vars CONFLUENT_CLOUD_API_KEY CONFLUENT_CLOUD_API_SECRET
    log "🏗️ connector $connector_name was deployed with Terraform: terraform destroy in $terraform_dir"
    if (cd "$terraform_dir" && terraform destroy -no-color -auto-approve > /tmp/terraform-destroy.log 2>&1)
    then
        grep -E "Destroy complete" /tmp/terraform-destroy.log || true
        rm -rf "$terraform_dir"
        playground state del "terraform.connector.$connector_name"
        return 0
    fi
    logwarn "⚠️ terraform destroy failed (see /tmp/terraform-destroy.log): connector $connector_name is deleted with the REST API"
    return 1
}

# Check if Terraform is installed
function check_terraform_installed() {
    if ! command -v terraform &> /dev/null
    then
        logerror "❌ Terraform is not installed. Please install Terraform first:"
        logerror "   https://developer.hashicorp.com/terraform/downloads"
        exit 1
    fi

    local tf_version=$(terraform version -json 2>/dev/null | jq -r '.terraform_version')
    if [[ -z "$tf_version" ]]
    then
        tf_version=$(terraform version | head -1 | awk '{print $2}' | sed 's/v//')
    fi

    log "✅ Terraform version: $tf_version"
}

# Check if required Confluent Cloud environment variables are set
function check_confluent_cloud_terraform_env() {
    load_secrets_env_vars CONFLUENT_CLOUD_API_KEY CONFLUENT_CLOUD_API_SECRET
    if [[ -z "$CONFLUENT_CLOUD_API_KEY" ]] || [[ -z "$CONFLUENT_CLOUD_API_SECRET" ]]
    then
        logerror "❌ Confluent Cloud API credentials not found"
        logerror "   Please set CONFLUENT_CLOUD_API_KEY and CONFLUENT_CLOUD_API_SECRET environment variables"
        logerror "   You can create Cloud API keys at: https://confluent.cloud/settings/api-keys"
        exit 1
    fi

    log "✅ Confluent Cloud API credentials found"
}

# Function to install kubectl confluent plugin
# Used by CFK debug commands to ensure kubectl confluent plugin is available
function install_confluent_plugin() {
    log "📦 Installing kubectl confluent plugin..."
    
    # Create temporary directory for bundle
    tmp_bundle_dir=$(mktemp -d -t cfk-bundle-XXXXXXXXXX)
    if [ -z "$PG_VERBOSE_MODE" ]; then
        trap 'rm -rf $tmp_bundle_dir' EXIT
    else
        log "🐛📂 Bundle temp dir: $tmp_bundle_dir"
    fi
    
    # Detect CFK version (try to get latest or default to 3.3)
    cfk_version="${CFK_VERSION:-3.3.0}"
    log "⏳ Downloading CFK bundle version $cfk_version..."
    
    bundle_url="https://packages.confluent.io/bundle/cfk/confluent-for-kubernetes-${cfk_version}.tar.gz"
    bundle_file="$tmp_bundle_dir/confluent-for-kubernetes-${cfk_version}.tar.gz"
    
    # Download the bundle
    if ! curl -f -L -o "$bundle_file" "$bundle_url" 2>&1 | grep -v "^  "; then
        logerror "❌ Failed to download CFK bundle from $bundle_url"
        logerror "   Check the version is correct: $cfk_version"
        logerror "   You can set a custom version: export CFK_VERSION=3.2.0"
        exit 1
    fi
    
    # Extract bundle
    log "⏳ Extracting bundle..."
    tar -xzf "$bundle_file" -C "$tmp_bundle_dir" 2>&1 | grep -v "^x " || true
    
    # Detect OS and architecture
    os_type=$(uname -s)
    arch_type=$(arch)
    
    # Map OS type to plugin name
    case "$os_type" in
        Darwin)
            os_name="darwin"
            ;;
        Linux)
            os_name="linux"
            ;;
        *)
            logerror "❌ Unsupported OS: $os_type"
            logerror "   Supported: macOS (Darwin) and Linux"
            exit 1
            ;;
    esac
    
    # Map architecture
    case "$arch_type" in
        arm64|aarch64)
            arch_name="arm64"
            ;;
        x86_64)
            arch_name="amd64"
            ;;
        *)
            logerror "❌ Unsupported architecture: $arch_type"
            logerror "   Supported: arm64 and amd64"
            exit 1
            ;;
    esac
    
    log "🔧 Detected OS: $os_name, Architecture: $arch_name"
    
    # Find the extracted CFK bundle directory (it may have a timestamp suffix)
    cfk_dir=$(find "$tmp_bundle_dir" -maxdepth 1 -type d -name "confluent-for-kubernetes-${cfk_version}*" | head -1)
    
    if [[ -z "$cfk_dir" ]]; then
        logerror "❌ CFK bundle directory not found"
        logerror "   Available directories:"
        find "$tmp_bundle_dir" -maxdepth 1 -type d | sed 's/^/     /'
        exit 1
    fi
    
    # Find and extract the plugin
    plugin_tar="$cfk_dir/kubectl-plugin/kubectl-confluent-${os_name}-${arch_name}.tar.gz"
    
    if [[ ! -f "$plugin_tar" ]]; then
        logerror "❌ Plugin not found: $plugin_tar"
        logerror "   Available files:"
        find "$cfk_dir" -name "kubectl-confluent*" 2>/dev/null | sed 's/^/     /'
        exit 1
    fi
    
    log "📋 Extracting plugin to /usr/local/bin/"
    
    # Ensure /usr/local/bin exists
    if [[ ! -d /usr/local/bin ]]; then
        log "ℹ️  Creating /usr/local/bin directory..."
        sudo mkdir -p /usr/local/bin
    fi
    
    # Try to extract to /usr/local/bin
    extraction_success=false
    
    # First try without sudo
    if tar -xzf "$plugin_tar" -C /usr/local/bin/ 2>/dev/null; then
        extraction_success=true
    # Then try with sudo
    elif sudo tar -xzf "$plugin_tar" -C /usr/local/bin/ 2>/dev/null; then
        extraction_success=true
    fi
    
    if [[ "$extraction_success" == false ]]; then
        logerror "❌ Failed to extract plugin to /usr/local/bin/"
        logerror "   Trying alternative location: ~/.local/bin/"
        
        # Try alternative location
        mkdir -p ~/.local/bin
        if tar -xzf "$plugin_tar" -C ~/.local/bin/ 2>/dev/null; then
            log "✅ Plugin extracted to ~/.local/bin/"
            log ""
            log "⚠️  To use the plugin, add ~/.local/bin to your PATH:"
            log "   export PATH=~/.local/bin:\$PATH"
            log ""
            log "   Add this to your ~/.zshrc or ~/.bashrc to make it permanent"
            extraction_success=true
        else
            logerror "❌ Failed to extract to ~/.local/bin/ as well"
            logerror "   Try manually:"
            logerror "   sudo tar -xzf $plugin_tar -C /usr/local/bin/"
            exit 1
        fi
    fi
    
    # Refresh shell command cache
    hash -r 2>/dev/null || true
    
    # Verify plugin was installed
    if ! kubectl confluent support-bundle -h &> /dev/null 2>&1; then
        logerror "❌ Plugin extraction completed but kubectl still cannot find the confluent plugin"
        logerror "   Try restarting your terminal"
        exit 1
    fi
    
    log "✅ Confluent kubectl plugin installed successfully!"
}

# Reads container logs on stdin and prints de-duplicated ERROR/FATAL records
# (optionally WARN), each with an occurrence count, the exception chain and a
# few frames of the deepest cause, instead of tens of thousands of raw lines.
# $1: max number of findings to print, $2: non-empty to include WARN records
# PG_LOG_DIGEST_CONNECTORS (space separated) prints only the records of these connectors ([connector|task-0] context),
# plus the records without connector context with PG_LOG_DIGEST_WITH_WORKER; the records file keeps them all.
# When PG_LOG_DIGEST_RECORDS_FILE is set, every distinct record (not only the first $1) is also appended to that
# file for the HTML reports (tools/log-analyzer/log_report.py), labelled with PG_LOG_DIGEST_LABEL:
#   @@PGFILE@@<tab>label<tab>lines<tab>distinct records<tab>occurrences<tab>first timestamp of the file<tab>last one
#   @@PGREC@@<tab>level<tab>count<tab>first line<tab>last line<tab>first timestamp<tab>last timestamp
#   <the record as printed in the digest, on one or more lines (2000 characters per line at most instead of 300), a stack
#   trace flattened on one line split back into lines>
#   @@PGTS@@<tab>timestamps of the occurrences, space separated (1000 per record at most)
#   @@PGCTX@@<tab>raw lines around the first occurrence (2 before, the record (30 lines at most), 2 after), one per line
#              (2000 characters at most)
# then the "<Class>Config values:" dumps of the log (KafkaConfig, DistributedConfig, the config of a connector with its
# [connector|task-0] context, ProducerConfig of a client…), the last one of each class / context / client.id, 50 at most:
#   @@PGCFG@@<tab>config class<tab>[connector|task-0] context<tab>line<tab>timestamp<tab>client.id or name
#   @@PGCFGL@@<tab>key=value, one per line
#   @@PGCFGCHG@@<tab>line<tab>timestamp<tab>key=previous<tab>key=new: a key that changed since the previous dump of the config
# then the events read from the INFO lines (each distinct one once):
#   @@PGEVT@@<tab>plugin_version<tab>line<tab>timestamp<tab>connector<tab>version class ("Instantiated connector|task …")
#   @@PGEVT@@<tab>kafka_version<tab>line<tab>timestamp<tab><tab>version ("Kafka version: 8.3.2-ce" of AppInfoParser)
function summarize_log_errors() {
    local max_findings="${1:-40}"
    local include_warnings="${2:-}"

    PG_LOG_DIGEST_RECORDS_FILE="${PG_LOG_DIGEST_RECORDS_FILE:-}" PG_LOG_DIGEST_LABEL="${PG_LOG_DIGEST_LABEL:-}" \
    # LC_ALL=C: the digest reads bytes. In a UTF-8 locale, the awk of macOS aborts on the first invalid byte (a Latin-1
    # character in a customer log: "awk: towc: multibyte conversion failure") and every record of the file is lost
    PG_LOG_DIGEST_CONNECTORS="${PG_LOG_DIGEST_CONNECTORS:-}" PG_LOG_DIGEST_WITH_WORKER="${PG_LOG_DIGEST_WITH_WORKER:-}" \
    LC_ALL=C awk -v max_findings="$max_findings" -v include_warnings="$include_warnings" '
    # anything that does not look like the continuation of a stack trace or of a
    # multi-line message (indented line, "Caused by:", exception line) starts a record
    # (a .NET exception has a generic type: Confluent.Kafka.ProduceException`2[System.String,System.String]: …)
    function is_continuation(line) {
        if (line ~ /^[ \t]/ ||
            line ~ /^Caused by:/ ||
            line ~ /^[A-Za-z0-9_$]+(\.[A-Za-z0-9_$]+)+(Exception|Error|Throwable)(`[0-9]+\[[^]]*\])?(:|$)/) return 1
        if (nlines == 0) return 0
        # Rust >= 1.73 prints the message of a panic on the line after "thread main panicked at src/main.rs:10:5:"
        if (rec[nlines] ~ /panicked at [^ ]+:[0-9]+:[0-9]+:$/) return 1
        # Python: the traceback of logging.exception() continues its record (a bare one starts a record), then the
        # chained tracebacks ("The above exception was the direct cause…", after a blank line) and the exception line
        if (line ~ /^Traceback \(most recent call last\):/) return mode == "py" || level_of(rec[1]) != ""
        if (mode == "py") return line == "" || line ~ /^(During handling of the above exception|The above exception was the direct cause)/ ||
                                 line ~ /^[A-Za-z_][A-Za-z0-9_.]*(Error|Exception|Interrupt|Exit|Warning|Group)(:|$)/
        # Go: the goroutines after "panic: …" (blank line, "goroutine 1 [running]:", function lines, tab-indented file lines)
        if (mode == "go") return line == "" || line ~ /^goroutine [0-9]+ \[/ || line ~ /^\[signal / || line ~ /^[A-Za-z_][^ ]*\(.*\)$/ ||
                                 line ~ /^created by / || line ~ /^exit status [0-9]+$/
        return 0
    }
    function severity(lvl) {
        lvl = toupper(lvl)
        if (lvl == "FATAL" || lvl == "SEVERE" || lvl == "PANIC" || lvl == "F") return "FATAL"
        if (lvl == "ERROR" || lvl == "E") return "ERROR"
        if (lvl == "WARN" || lvl == "WARNING" || lvl == "W") return "WARN"
        # an explicit INFO/DEBUG/TRACE level wins over "Error"/"Exception"/"failed" words in the message
        return ""
    }
    # only an explicit level counts: an uppercase level token as a whole word (" ERROR ", "[ERROR]",
    # "\"ERROR\""), a logfmt or json level field (level=error, "level":"error") or a klog prefix (E1012)
    # librdkafka lines (C/C++, Python, Go, .NET and JavaScript clients) carry a syslog level: "%3|1730800000.123|FAIL|rdkafka#producer-1| …"
    # (0-2 emerg/alert/crit, 3 err, 4 warning, 5-7 notice/info/debug), the .NET console logger a 4 letters prefix
    # ("fail: Program[0]"), and crashes of the other languages have their own first line
    function level_of(head,    h, lvl) {
        h = substr(head, 1, 200)
        if (match(h, /%[0-7]\|[0-9]+\.[0-9]+\|/)) {
            lvl = substr(h, RSTART + 1, 1) + 0
            return lvl <= 2 ? "FATAL" : lvl == 3 ? "ERROR" : lvl == 4 ? "WARN" : ""
        }
        if (match(h, /^(crit|fail|warn|info|dbug|trce): /)) {
            lvl = substr(h, 1, 4)
            return lvl == "crit" ? "FATAL" : lvl == "fail" ? "ERROR" : lvl == "warn" ? "WARN" : ""
        }
        if (match(h, /(^|[] \t[("|])(TRACE|DEBUG|INFO|WARN|WARNING|ERROR|FATAL|SEVERE)([] \t:)"|]|$)/)) {
            lvl = substr(h, RSTART, RLENGTH)
            gsub(/[^A-Z]/, "", lvl)
            return severity(lvl)
        }
        if (match(h, /(^|[^A-Za-z])"?level"?[=:][ \t]*"?[A-Za-z]+/)) {
            lvl = substr(h, RSTART, RLENGTH)
            sub(/^.*[=:][ \t]*"?/, "", lvl)
            return severity(lvl)
        }
        if (match(h, /^[IWEF][0-9][0-9][0-9][0-9] [0-9][0-9]:/)) return severity(substr(h, 1, 1))
        # level-less line (stderr, raw stack trace): only an uncaught java exception
        if (h ~ /^Exception in thread / || h ~ /^([a-z][A-Za-z0-9_$]*\.)+[A-Z][A-Za-z0-9_$]*(Exception|Error|Throwable)(:|$)/) return "ERROR"
        # the crash of a process: a Go panic or runtime fatal error, a Rust panic, an unhandled .NET exception
        if (h ~ /^(panic: |fatal error: |Unhandled exception\. )/ || h ~ /^thread [^ ]+ panicked at /) return "FATAL"
        # a Python traceback, an uncaught Node.js or .NET error ("KafkaJSConnectionError: …", "Error [ERR_X]: …",
        # "Confluent.Kafka.KafkaException: …", the "Error: …" of a Rust main), and the KafkaError{code=…} of the Python
        # client printed by the application ("Failed to deliver record: KafkaError{code=_MSG_TIMED_OUT,…}")
        if (h ~ /^Traceback \(most recent call last\):/ || h ~ /^(Error|Exception|[A-Z][A-Za-z0-9_]*(Error|Exception))( \[[A-Z0-9_]+\])?: / ||
            h ~ /^([A-Z][A-Za-z0-9_]*\.)+[A-Z][A-Za-z0-9_]*Exception(`[0-9]+\[[^]]*\])?: / || index(h, "KafkaError{code=")) return "ERROR"
        return ""
    }
    # the first n bytes of s (LC_ALL=C: length and substr count bytes), without the incomplete UTF-8 character a cut can
    # leave at the end (a lead byte 0xC0-0xF7 followed by fewer continuation bytes 0x80-0xBF than it announces)
    # (not "cut": unflatten() has a local of that name, and mawk refuses a function and a parameter of the same name:
    # "cut is duplicated in argument list", the whole digest failed)
    function cut_utf8(s, n,    k, c, need) {
        s = substr(s, 1, n)
        k = 0
        while (k < 3 && k < length(s) && (c = substr(s, length(s) - k, 1)) >= "\200" && c < "\300") k++
        if (k >= length(s)) return s
        c = substr(s, length(s) - k, 1)
        need = c >= "\360" ? 4 : c >= "\340" ? 3 : c >= "\300" ? 2 : 1
        return need > k + 1 ? substr(s, 1, length(s) - k - 1) : s
    }
    function short(s) {
        return length(s) > 300 ? cut_utf8(s, 300) "..." : s
    }
    # the records file of the HTML reports keeps longer lines: the error is often at the end of a long message
    # ("Task is being killed and will not recover until manually restarted. Error: <the cause>")
    function long(s) {
        return length(s) > 2000 ? cut_utf8(s, 2000) "..." : s
    }
    # a stack trace flattened on one line by a log export or a log shipper: "msg org.x.FooException: m\n\tat a.b(C.java:1)
    # \nCaused by: …" with a literal \n, or with its backslash lost ("Source)n\tat a.b", "Source)nCaused by:"). Split back
    # into lines in r[] (message, exception, frames, Caused by), returns their number; a normal record is copied as is
    # ids of letters and digits in a key whose digits are already #: an AWS Request ID 5PPC305GEXB1A0R9 (#PPC#GEXB#A#R#),
    # an Extended Request ID, a token… one # each (8 characters or more, with letters and two # at least)
    function mask_ids(s,    out, t) {
        out = ""
        while (match(s, /[A-Za-z#+\/]*#[A-Za-z#+\/]*/)) {
            t = substr(s, RSTART, RLENGTH)
            out = out substr(s, 1, RSTART - 1) ((RLENGTH >= 8 && t ~ /[A-Za-z]/ && t ~ /#.*#/) ? "#" : t)
            s = substr(s, RSTART + RLENGTH)
        }
        return out s
    }
    function mask_key(key) {
        # Java identity hash of Object.toString() (KafkaConsumerReadTask@9c3da5a): a new one per object
        gsub(/@[0-9a-f]+/, "@#", key)
        # an AWS Request ID of letters only (VZPWGRBNDARQCDHD): another one per request
        gsub(/[Rr]equest I[Dd]: [^ ,)]+/, "Request ID: #", key)
        gsub(/[0-9]+/, "#", key)
        return mask_ids(key)
    }
    function unflatten(    i, n, line, parts, np, j, cut) {
        n = 0
        for (i = 1; i <= nlines; i++) {
            line = rec[i]
            if (line ~ /(\\n|n)\t(at |\.\.\. [0-9])/ || line ~ /\\nCaused by: /) {
                gsub(/\\n/, "\n", line)
                gsub(/n\tat /, "\n\tat ", line)
                gsub(/n\t\.\.\. /, "\n\t... ", line)
                gsub(/\)nCaused by: /, ")\nCaused by: ", line)
                np = split(line, parts, "\n")
                # Connect logs "<message> <exception>": the exception thrown on its own line, as in a normal trace
                if (i == 1 && match(parts[1], / ([a-z][A-Za-z0-9_$]*\.)+[A-Z][A-Za-z0-9_$]*(Exception|Error|Throwable)(: |$)/)) {
                    cut = RSTART
                    r[++n] = substr(parts[1], 1, cut - 1)
                    r[++n] = substr(parts[1], cut + 1)
                } else {
                    r[++n] = parts[1]
                }
                for (j = 2; j <= np; j++) r[++n] = parts[j]
            } else {
                r[++n] = line
            }
        }
        return n
    }
    # "2026-10-13 10:00:05" or "2026-10-13T10:00:05" at the start of the record, as 2026-10-13T10:00:05
    function timestamp_of(head,    h, t, z) {
        # journalctl export: "-- Logs begin at Tue 2026-11-03 01:59:29 PST, end at … --" is not a logged line, and the
        # "Nov 03 18:29:20 host connect-distributed[217934]: " prefix of each line pushes the log4j timestamp past
        # the first 80 characters
        if (substr(head, 1, 3) == "-- ") return ""
        h = head
        sub(/^[A-Z][a-z][a-z] [ 0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9] [^ ]+ [^ :]+: /, "", h)
        h = substr(h, 1, 80)
        if (!match(h, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][ T][0-9][0-9]:[0-9][0-9]:[0-9][0-9]/)) {
            # Go log package: "2026/11/05 10:00:05 …"
            if (match(h, /^[0-9][0-9][0-9][0-9]\/[0-9][0-9]\/[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]/)) {
                t = substr(h, 1, 19)
                gsub(/\//, "-", t)
                sub(/ /, "T", t)
                return t
            }
            # librdkafka: "%3|1730800000.123|…", epoch seconds (UTC)
            if (match(h, /%[0-7]\|[0-9]+\./)) return epoch_iso(substr(h, RSTART + 3, RLENGTH - 4))
            # a Node.js object of the JavaScript client (see js_rdkafka): "  timestamp: 1793896130218," epoch milliseconds
            if (h ~ /^  timestamp: [0-9]+,?$/) return epoch_iso(int(substr(h, 14) / 1000))
            return ""
        }
        t = substr(h, RSTART, RLENGTH)
        sub(/ /, "T", t)
        # the offset written after it (2026-10-13T10:00:05.123+02:00, …Z, …-0700), kept as +HH:MM: log_report.py strips it
        # when the input has one offset, and converts the times to UTC when its files mix several (UTC broker logs and
        # local time Connect logs: hours apart otherwise)
        z = substr(h, RSTART + RLENGTH)
        if (match(z, /^([.,][0-9]+)?(Z|[+-][0-9][0-9]:?[0-9][0-9])/)) {
            z = substr(z, 1, RLENGTH)
            sub(/^[.,][0-9]+/, "", z)
            if (z == "Z") z = "+00:00"
            else if (length(z) == 5) z = substr(z, 1, 3) ":" substr(z, 4, 2)
            t = t z
        }
        return t
    }
    # epoch seconds as 2026-11-05T10:00:05 (UTC), without strftime (not in every awk): days to civil date (H. Hinnant)
    function epoch_iso(e,    d, s, z, era, doe, yoe, y, doy, mp, dd, m) {
        e = int(e)
        d = int(e / 86400)
        s = e - d * 86400
        z = d + 719468
        era = int(z / 146097)
        doe = z - era * 146097
        yoe = int((doe - int(doe / 1460) + int(doe / 36524) - int(doe / 146096)) / 365)
        y = yoe + era * 400
        doy = doe - (365 * yoe + int(yoe / 4) - int(yoe / 100))
        mp = int((5 * doy + 2) / 153)
        dd = doy - int((153 * mp + 2) / 5) + 1
        m = mp < 10 ? mp + 3 : mp - 9
        if (m <= 2) y++
        return sprintf("%04d-%02d-%02dT%02d:%02d:%02d", y, m, dd, int(s / 3600), int((s % 3600) / 60), s % 60)
    }
    # a line of the context of a record, with its line number (▶ for the first line of the record)
    function ctx_line(n, s, mark) {
        gsub(/\033\[[0-9;]*m/, "", s)
        sub(/\r$/, "", s)
        return sprintf("%6d %s %s\n", n, mark, long(s))
    }
    function capture_after() {
        ctx[ctx_key] = ctx[ctx_key] ctx_line(NR, $0, " ")
        ctx_after--
    }
    # a record of one of the connectors of PG_LOG_DIGEST_CONNECTORS: its [connector|task-0] / [connector|worker] context or
    # its WorkerSourceTask{id=connector-0}; with PG_LOG_DIGEST_WITH_WORKER, also a record without connector context
    function of_connectors(t,    n, i, names) {
        n = split(connectors, names, " ")
        for (i = 1; i <= n; i++) if (index(t, "[" names[i] "|") || index(t, "Task{id=" names[i] "-")) return 1
        return with_worker != "" && t !~ /\[[^] |]+\|(task-[0-9]+|worker)/ && t !~ /Task\{id=/
    }
    # a "<Class>Config values:" header: the "<tab>key = value" lines that follow are its config
    function cfg_start(    h) {
        cfg_end()
        h = $0
        if (!match(h, /[A-Za-z]+Config values:/)) return
        cfg_on = 1
        cfg_cls = substr(h, RSTART, RLENGTH - 8)
        cfg_ctx = match(h, /\[[^] |]+\|(task-[0-9]+|worker)[^]]*\]/) ? substr(h, RSTART, RLENGTH) : ""
        cfg_ln = NR
        cfg_ts = timestamp_of(h)
        cfg_buf = ""
        cfg_id = ""
    }
    function cfg_add(line,    i, k, v) {
        sub(/^\t/, "", line)
        i = index(line, " = ")
        if (i == 0) return
        k = substr(line, 1, i - 1)
        v = substr(line, i + 3)
        # the logger of the record ends the last line: " (org.apache.kafka.common.config.AbstractConfig:370)"
        sub(/ \([A-Za-z0-9_.$]*Config(:[0-9]+)?\)$/, "", v)
        if (length(v) > 1000) v = substr(v, 1, 1000) "..."
        if (k == "client.id" || (k == "name" && cfg_id == "")) cfg_id = v
        # the key and the value converter of a task log the same class one after the other: two configs
        if (k == "converter.type") cfg_id = cfg_id (cfg_id == "" ? "" : " ") v
        cfg_buf = cfg_buf k "=" v "\n"
    }
    # keys whose value differs between the previous dump of a config and this one (a restart with another config),
    # appended to cfg_chg[key]: "line<tab>timestamp<tab>key=previous<tab>key=new" (key=value on both sides, so that the
    # sanitizer redacts a secret on each). A dump lists every key of its config class, defaults included: a key in only
    # one of them is another variant of the class logged at the same time (EnrichedConnectorConfig with or without the
    # topic.creation.* group), not a change
    function cfg_diff(key, old, new,    n, i, ol, nl, k, v, prev) {
        split("", prev)
        n = split(old, ol, "\n")
        for (i = 1; i < n; i++) { k = substr(ol[i], 1, index(ol[i], "=") - 1); prev[k] = substr(ol[i], index(ol[i], "=") + 1) }
        n = split(new, nl, "\n")
        for (i = 1; i < n; i++) {
            k = substr(nl[i], 1, index(nl[i], "=") - 1)
            v = substr(nl[i], index(nl[i], "=") + 1)
            if (nchg[key] < 50 && (k in prev) && prev[k] != v) {
                cfg_chg[key] = cfg_chg[key] cfg_ln "\t" cfg_ts "\t" k "=" prev[k] "\t" k "=" v "\n"
                nchg[key]++
            }
        }
    }
    function cfg_end(    key) {
        if (!cfg_on) return
        cfg_on = 0
        if (cfg_buf == "") return
        key = cfg_cls "|" cfg_ctx "|" cfg_id
        if (!(key in cfg_text)) {
            if (ncfg >= 50) return
            cfg_order[++ncfg] = key
        } else if (cfg_text[key] != cfg_buf) {
            cfg_diff(key, cfg_text[key], cfg_buf)
        }
        cfg_text[key] = cfg_buf
        cfg_head[key] = cfg_cls "\t" cfg_ctx "\t" cfg_ln "\t" cfg_ts "\t" cfg_id
    }
    # the message of a .NET console logger record ("fail: Program[0]" then the message, indented) or of a Rust panic
    # ("thread main panicked at src/main.rs:10:5:" then the message) is on its second line: joined to the first
    function join_second(nr,    i, line) {
        if (nr < 2 || (r[1] !~ /^(crit|fail|warn): [^ ]+\[[0-9]+\]$/ && r[1] !~ /panicked at [^ ]+:[0-9]+:[0-9]+:$/)) return nr
        line = r[2]
        sub(/^[ \t]+/, "", line)
        r[1] = r[1] " " line
        for (i = 2; i < nr; i++) r[i] = r[i + 1]
        delete r[nr]
        return nr - 1
    }
    # the default logger of the JavaScript client (@confluentinc/kafka-javascript) prints the librdkafka logs as Node.js
    # objects, its level only in the stream (console.error / console.warn / console.info):
    #   {
    #     message: "[thrd:broker:9092/bootstrap]: broker:9092/bootstrap: Connect to … failed: Connection refused …",
    #     fac: "FAIL",
    #     timestamp: 1793896130218,
    #     name: "rdkafka#producer-1"
    #   }
    # the FAIL and ERROR facilities are errors: written back as the librdkafka line ("%3|1793896130.218|FAIL|rdkafka#producer-1| …",
    # level 3 inferred from the facility), so that the same error of every client is one record. "" for another object
    function js_rdkafka(    i, line, msg, fac, ts, name) {
        msg = fac = name = ""
        ts = 0
        for (i = 2; i <= nlines && i <= 8; i++) {
            line = rec[i]
            sub(/,$/, "", line)
            if (line ~ /^  message: [\047"`]/) { msg = substr(line, 13, length(line) - 13) }
            else if (line ~ /^  fac: \047[A-Z_]+\047$/) { fac = substr(line, 9, length(line) - 9) }
            else if (line ~ /^  timestamp: [0-9]+$/) { ts = substr(line, 14) + 0 }
            else if (line ~ /^  name: \047/) { name = substr(line, 10, length(line) - 10) }
        }
        if (msg == "" || (fac != "FAIL" && fac != "ERROR")) return ""
        return sprintf("%%3|%d.%03d|%s|%s| %s", int(ts / 1000), ts % 1000, fac, name, msg)
    }
    function flush(    lvl, key, i, chain, long_chain, frames, nframes, line, cause, nrec, nr, py, gof, pf1, pf2, pf3, js) {
        if (nlines == 0) return
        # header of a digest already printed in the log (CI logs contain "playground container logs --errors" output)
        if (rec[1] ~ /^[^ ]+ (FATAL|ERROR|WARN) x[0-9]+ \(first seen line [0-9]+, last seen line [0-9]+\)$/) { nlines = 0; return }
        # (the "{" line of a Node.js object is set aside by the first regex of each line: rec[1] is "")
        js = ""
        if (nlines >= 3 && rec[1] ~ /^\{?$/ && rec[2] ~ /^  [a-z]+: /) {
            js = js_rdkafka()
            if (js == "") { nlines = 0; return }
            rec[1] = "{"
        }
        lvl = (js != "") ? "ERROR" : level_of(rec[1])
        if (lvl == "" || (lvl == "WARN" && include_warnings == "")) { nlines = 0; return }

        # exception chain: first exception line plus every "Caused by:", then frames of the deepest cause
        split("", r)
        nr = unflatten()
        nr = join_second(nr)
        if (js != "") {
            split("", r)
            r[1] = js
            nr = 1
        }
        chain = ""
        long_chain = ""
        cause = ""
        nframes = 0
        py = (mode == "py")
        gof = 0
        for (i = 2; i <= nr; i++) {
            line = r[i]
            # Python: frames ("  File "/app/client.py", line 57, in produce"), the deepest one last, then the exception
            # line; chained tracebacks print the deepest cause first. The chain is written outermost first, as in Java
            if (py) {
                if (line ~ /^  File "/) {
                    pf3 = pf2; pf2 = pf1
                    pf1 = line
                    sub(/^[ \t]*/, "", pf1)
                } else if (line ~ /^[A-Za-z_][A-Za-z0-9_.]*(Error|Exception|Interrupt|Exit|Warning|Group)(:|$)/) {
                    chain = "\n    " short(line) chain
                    long_chain = "\n    " long(line) long_chain
                    if (cause == "") {
                        cause = line
                        frames = (pf1 == "" ? "" : "\n        " short(pf1)) (pf2 == "" ? "" : "\n        " short(pf2)) (pf3 == "" ? "" : "\n        " short(pf3))
                    }
                    pf1 = pf2 = pf3 = ""
                }
                continue
            }
            # Go panic: the function lines of the first goroutine
            if (mode == "go") {
                if (line ~ /^goroutine [0-9]+ \[/) gof++
                else if (gof == 1 && nframes < 3 && line ~ /^[A-Za-z_][^ ]*\(.*\)$/) { frames = frames "\n        " short(line); nframes++ }
                continue
            }
            # .NET: the frames of the inner exception (the deepest cause) end at "--- End of inner exception stack trace ---",
            # the frames of the outer exception follow; "--- End of stack trace from previous location ---" (async) is skipped
            if (line ~ /^[ \t]*--- End of inner exception/) { nframes = 3; continue }
            if (line ~ /^[ \t]*--- End of /) continue
            if (line ~ /^[ \t]*at /) {
                if (nframes < 3) { sub(/^[ \t]*/, "", line); frames = frames "\n        " short(line); nframes++ }
                continue
            }
            if (line ~ /^[ \t]*\.\.\. [0-9]+ (more|common frames omitted)/) continue
            # the inner exception of .NET (" ---> X: …") and the cause of a Node.js error ("  [cause]: X: …") are its "Caused by:"
            if (line ~ /^[ \t]*(---> |\[cause\]: )/) sub(/^[ \t]*/, "", line)
            # JDBC: "Caused by: java.sql.SQLException: Exception chain:" is only a preface, the exceptions it chains follow on
            # their own lines (java.sql.BatchUpdateException: Batch entry 0 … was aborted: ERROR: null value in column …):
            # they are its causes, the deepest one is what to fix
            if (cause ~ /[Ee]xception chain:[ \t]*$/ && line ~ /^[A-Za-z_$][A-Za-z0-9_$.]*(Exception|Error)(:|[ \t]*$)/) line = "Caused by: " line
            if (line ~ /^(Caused by:|---> |\[cause\]: )/ || (chain == "" && line ~ /(Exception|Error|Throwable)(:|[ \t]*$)/)) {
                chain = chain "\n    " short(line)
                long_chain = long_chain "\n    " long(line)
                cause = line
                frames = ""
                nframes = 0
            }
        }
        if (chain == "" && mode != "go" && r[1] !~ /(Exception|Error|Throwable)(:|[ \t]|$)/) frames = ""

        # same message and same deepest cause = same finding, whatever the timestamps and ids
        key = r[1]
        sub(/^\[?[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][ T][0-9:,.]*\]?[ \t]*/, "", key)
        # masked before being cut to 200 characters: "(after 312ms in state CONNECT)" and "(after 2ms …" are the same record
        key = mask_key(substr(key, 1, 400))
        key = lvl ":" substr(key, 1, 200) "|" substr(mask_key(substr(cause, 1, 400)), 1, 200)

        total_occurrences++
        nrec = nlines
        nlines = 0
        ts = timestamp_of(r[1])
        # the times of the occurrences, at most 1000 per record, spread over its whole life: every stride-th one is kept,
        # and when 1000 are kept every other one is dropped and the stride doubles (the first 1000 were kept: an error
        # of a whole day showed as a burst at its start). Each time kept stands for stride occurrences
        if (records_file != "" && ts != "") {
            if (!(key in ts_stride)) ts_stride[key] = 1
            if (ts_seen[key]++ % ts_stride[key] == 0) {
                timestamps[key] = timestamps[key] " " ts
                if (++nts[key] >= 1000) {
                    nkept = split(substr(timestamps[key], 2), kept_ts, " ")
                    timestamps[key] = ""
                    for (i = 1; i <= nkept; i += 2) timestamps[key] = timestamps[key] " " kept_ts[i]
                    nts[key] = int((nkept + 1) / 2)
                    ts_stride[key] *= 2
                }
            }
        }
        if (key in count) {
            count[key]++
            last_seen[key] = rec_line
            if (ts != "") last_ts[key] = ts
            return
        }
        count[key] = 1
        first_seen[key] = rec_line
        last_seen[key] = rec_line
        first_ts[key] = ts
        last_ts[key] = ts
        level[key] = lvl
        order[++nkeys] = key
        text[key] = short(r[1]) chain frames
        if (records_file != "") {
            long_text[key] = long(r[1]) long_chain frames
            ctx[key] = rec_before
            for (i = 1; i <= nrec && i <= 30; i++) ctx[key] = ctx[key] ctx_line(rec_line + i - 1, rec[i], (i == 1 ? "▶" : " "))
            if (nrec > 30) ctx[key] = ctx[key] sprintf("%6s   … %d more line(s)\n", "", nrec - 30)
            # the 2 lines after the record are read next (capture_after)
            ctx_key = key
            ctx_after = 2
        }
    }
    BEGIN {
        records_file = ENVIRON["PG_LOG_DIGEST_RECORDS_FILE"]
        label = ENVIRON["PG_LOG_DIGEST_LABEL"]
        connectors = ENVIRON["PG_LOG_DIGEST_CONNECTORS"]
        with_worker = ENVIRON["PG_LOG_DIGEST_WITH_WORKER"]
    }
    {
        # the 2 lines before a record, for its context
        prev2 = prev1
        prev1 = cur
        cur = $0
        # period the file itself covers (first and last timestamped line, whatever its level): the reports say how
        # long the logs span, not only the records. Only for the reports (one more match per line). An indented line
        # continues a record (a stack frame, the next line of a multi-line message): a date in it is data, not the time
        # of the line
        if (records_file != "" && substr($0, 1, 1) != " " && substr($0, 1, 1) != "\t") {
            line_ts = timestamp_of($0)
            if (line_ts != "") {
                if (log_first_ts == "" || line_ts < log_first_ts) log_first_ts = line_ts
                if (line_ts > log_last_ts) log_last_ts = line_ts
            }
        }
        # the version of each connector and of Kafka, from INFO lines the digest does not keep otherwise
        if (records_file != "" && index($0, "Instantiated ") && match($0, /Instantiated (connector|task) [^ ]+ with version [^ ]+ of type (class )?[^ ]+/)) {
            n_evp = split(substr($0, RSTART, RLENGTH), evp, " ")
            ev_name = evp[3]
            if (evp[2] == "task") sub(/-[0-9]+$/, "", ev_name)
            ev_key = "plugin_version|" ev_name "|" evp[6] "|" evp[n_evp]
            if (!(ev_key in ev_seen)) {
                ev_seen[ev_key] = 1
                ev[++nev] = "plugin_version\t" NR "\t" timestamp_of($0) "\t" ev_name "\t" evp[6] " " evp[n_evp]
            }
        }
        if (records_file != "" && index($0, "Kafka version: ") && match($0, /Kafka version: [^ ]+/)) {
            # read before timestamp_of(), whose match() changes RSTART / RLENGTH
            ev_version = substr($0, RSTART + 15, RLENGTH - 15)
            ev_key = "kafka_version|" ev_version
            if (!(ev_key in ev_seen)) {
                ev_seen[ev_key] = 1
                ev[++nev] = "kafka_version\t" NR "\t" timestamp_of($0) "\t\t" ev_version
            }
        }
        # most lines of a big log have no level or exception word and do not continue a record: one regex (a
        # single pass over the line) sets them aside, as the start of a level-less record, without the work below
        # (the clients: librdkafka "%3|", .NET "fail: ", Go "panic: ", Rust "panicked at ", Python "Traceback (", and
        # the lines that continue a Python traceback, a Go panic or a Rust panic, whatever they contain)
        if ($0 !~ /ERROR|FATAL|SEVERE|PANIC|WARN|level|Exception|Error|Throwable|[EFW][0-9][0-9][0-9][0-9] [0-9][0-9]:|^[ \t]|^Caused by:|\033|Config values:|%[0-7]\||^(crit|fail|warn): |^panic: |^fatal error: |panicked at |^Traceback \(/ &&
            mode == "" && rec[nlines] !~ /panicked at [^ ]+:[0-9]+:[0-9]+:$/) {
            if (cfg_on) cfg_end()
            flush()
            if (ctx_after > 0) capture_after()
            rec_line = NR
            rec[nlines = 1] = ""
            next
        }
        gsub(/\033\[[0-9;]*m/, "")
        sub(/\r$/, "")
        if (records_file != "") {
            if (cfg_on) {
                if ($0 ~ /^\t[^ \t]+ = /) cfg_add($0)
                else cfg_end()
            }
            if (index($0, "Config values:")) cfg_start()
        }
        if (!is_continuation($0) || nlines == 0 || nlines >= 400) {
            flush()
            mode = ""
            rec_line = NR
            if (records_file != "") {
                rec_before = (NR > 2 ? ctx_line(NR - 2, prev2, " ") : "") (NR > 1 ? ctx_line(NR - 1, prev1, " ") : "")
            }
        }
        if (ctx_after > 0) capture_after()
        rec[++nlines] = $0
        if ($0 ~ /^Traceback \(most recent call last\):/) mode = "py"
        else if (nlines == 1 && $0 ~ /^(panic: |fatal error: )/) mode = "go"
    }
    END {
        flush()
        if (records_file != "") {
            printf "@@PGFILE@@\t%s\t%d\t%d\t%d\t%s\t%s\n", label, NR, nkeys, total_occurrences, log_first_ts, log_last_ts >> records_file
            for (i = 1; i <= nkeys; i++) {
                k = order[i]
                printf "@@PGREC@@\t%s\t%d\t%d\t%d\t%s\t%s\n%s\n@@PGTS@@\t%s\n", level[k], count[k], first_seen[k], last_seen[k], first_ts[k], last_ts[k], long_text[k], (ts_stride[k] > 1 ? "x" ts_stride[k] " " : "") substr(timestamps[k], 2) >> records_file
                n = split(ctx[k], cl, "\n")
                for (j = 1; j < n; j++) printf "@@PGCTX@@\t%s\n", cl[j] >> records_file
            }
            cfg_end()
            for (i = 1; i <= ncfg; i++) {
                k = cfg_order[i]
                printf "@@PGCFG@@\t%s\n", cfg_head[k] >> records_file
                n = split(cfg_text[k], cl, "\n")
                for (j = 1; j < n; j++) printf "@@PGCFGL@@\t%s\n", cl[j] >> records_file
                n = split(cfg_chg[k], cl, "\n")
                for (j = 1; j < n; j++) printf "@@PGCFGCHG@@\t%s\n", cl[j] >> records_file
            }
            for (i = 1; i <= nev; i++) printf "@@PGEVT@@\t%s\n", ev[i] >> records_file
            close(records_file)
        }
        # PG_LOG_DIGEST_CONNECTORS (analyze logs --connector): only the records of these connectors are printed
        nshown_keys = nkeys
        shown_occurrences = total_occurrences
        if (connectors != "") {
            nshown_keys = 0
            shown_occurrences = 0
            for (i = 1; i <= nkeys; i++) if (of_connectors(text[order[i]])) { nshown_keys++; shown_occurrences += count[order[i]] }
        }
        if (nshown_keys == 0) {
            printf "✅ no %s record found in %d lines%s\n", (include_warnings == "" ? "ERROR/FATAL" : "ERROR/FATAL/WARN"), NR, (connectors == "" ? "" : sprintf(" for --connector %s (%d distinct record(s) of other connectors or without connector context)", connectors, nkeys))
            exit 0
        }
        if (connectors == "") printf "🔎 %d distinct record(s), %d occurrence(s), in %d lines\n", nkeys, total_occurrences, NR
        else printf "🔎 %d distinct record(s), %d occurrence(s) for --connector %s (%d distinct record(s) in the file), in %d lines\n", nshown_keys, shown_occurrences, connectors, nkeys, NR
        shown = 0
        split("FATAL ERROR WARN", severities, " ")
        for (s = 1; s <= 3; s++) {
            for (i = 1; i <= nkeys && shown < max_findings; i++) {
                k = order[i]
                if (level[k] != severities[s]) continue
                if (connectors != "" && !of_connectors(text[k])) continue
                icon = (level[k] == "WARN") ? "🟠" : "🔴"
                printf "\n%s %s x%d (first seen line %d, last seen line %d)\n%s\n", icon, level[k], count[k], first_seen[k], last_seen[k], text[k]
                shown++
            }
        }
        if (shown < nshown_keys) printf "\n✂️ %d more distinct record(s) not shown, increase --max-findings or narrow with --since\n", nshown_keys - shown
    }'
}

# Prints where an HTML report was saved, and opens it in the browser when the command runs in an interactive terminal
# (PLAYGROUND_RUN_LOG_TERMINAL: still a terminal behind the run log of 'playground run', see run_log_start)
# $1: report, $2: non-empty to never open it (--no-open)
function open_html_report() {
    local report="$1"
    local no_open="$2"
    log "✅ HTML report saved: $report"
    if { [[ -t 1 ]] || [ -n "${PLAYGROUND_RUN_LOG_TERMINAL:-}" ]; } && [ -z "$GITHUB_RUN_NUMBER" ] && [[ -z "$no_open" ]] && { command -v open > /dev/null 2>&1 || command -v xdg-open > /dev/null 2>&1; }
    then
        log "🌐 Opening $report in browser..."
        if command -v open > /dev/null 2>&1
        then
            open "$report"
        else
            xdg-open "$report" > /dev/null 2>&1 || true
        fi
    else
        # percent-encoded: a space, a # or a ? in the path would cut the URL pasted in a browser
        log "🔗 Open in browser: file://$(python3 -I -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$report" 2>/dev/null || echo "$report")"
    fi
}

# S3 buckets tagged cflt_managed_id=<user>, for the "Amazon S3 details" of the HTML report of cloud-resources aws
# costs-history: region, size per storage class and number of objects (daily CloudWatch metrics), server access logging,
# lifecycle transitions. Cost Explorer has no cost per bucket without the resource-level data of the payer account.
# Best effort: a bucket or a region that cannot be read is left out. $1: user, $2: output json file
function save_aws_s3_buckets() {
    local user="$1"
    local out="$2"
    local tmp_dir
    tmp_dir=$(mktemp -d -t pg-aws-s3-buckets-XXXXXXXXXX)
    local regions
    regions=$(aws ec2 describe-regions --region us-east-1 --query 'Regions[].RegionName' --output text 2>/dev/null | tr '\t' '\n')
    if [ -z "$regions" ]
    then
        rm -rf "$tmp_dir"
        return 0
    fi
    # the tagging API only returns the buckets of the region it is called in: all the regions in parallel
    local region
    for region in $regions
    do
        aws resourcegroupstaggingapi get-resources --region "$region" --resource-type-filters s3 \
            --tag-filters Key=cflt_managed_id,Values="$user" --query 'ResourceTagMappingList[].ResourceARN' --output text 2>/dev/null \
            | tr '\t' '\n' | sed -n "s#^arn:aws:s3:::\(..*\)#\1 $region#p" > "$tmp_dir/buckets-$region.txt" &
    done
    wait
    local start end
    if [[ "$OSTYPE" == "darwin"* ]]
    then
        start=$(date -u -v-3d +%Y-%m-%dT00:00:00Z)
    else
        start=$(date -u -d "3 days ago" +%Y-%m-%dT00:00:00Z)
    fi
    end=$(date -u +%Y-%m-%dT00:00:00Z)
    local bucket storage storage_type bytes objects logging lifecycle
    # read on fd 3: the aws function of the playground can run docker run -i, which would eat the rest of the list on stdin
    while read -r bucket region <&3
    do
        storage="[]"
        for storage_type in $(aws cloudwatch list-metrics --region "$region" --namespace AWS/S3 --metric-name BucketSizeBytes \
            --dimensions Name=BucketName,Value="$bucket" --query 'Metrics[].Dimensions[?Name==`StorageType`].Value' --output text 2>/dev/null)
        do
            bytes=$(aws cloudwatch get-metric-statistics --region "$region" --namespace AWS/S3 --metric-name BucketSizeBytes \
                --dimensions Name=BucketName,Value="$bucket" Name=StorageType,Value="$storage_type" --start-time "$start" \
                --end-time "$end" --period 86400 --statistics Average --output json 2>/dev/null | jq '[.Datapoints[]] | sort_by(.Timestamp) | last | .Average // 0')
            storage=$(echo "$storage" | jq --arg t "$storage_type" --argjson b "${bytes:-0}" '. + [{type: $t, bytes: $b}]')
        done
        objects=$(aws cloudwatch get-metric-statistics --region "$region" --namespace AWS/S3 --metric-name NumberOfObjects \
            --dimensions Name=BucketName,Value="$bucket" Name=StorageType,Value=AllStorageTypes --start-time "$start" \
            --end-time "$end" --period 86400 --statistics Average --output json 2>/dev/null | jq '[.Datapoints[]] | sort_by(.Timestamp) | last | .Average // null')
        logging=$(aws s3api get-bucket-logging --bucket "$bucket" --region "$region" --output json 2>/dev/null | jq '.LoggingEnabled.TargetBucket // null' 2>/dev/null)
        lifecycle=$(aws s3api get-bucket-lifecycle-configuration --bucket "$bucket" --region "$region" --output json 2>/dev/null \
            | jq '[.Rules[]? | select(.Status == "Enabled") | .Transitions[]? | "\(.StorageClass) after \(.Days) days"] | unique' 2>/dev/null)
        jq -n --arg name "$bucket" --arg region "$region" --argjson storage "$storage" --argjson objects "${objects:-null}" \
            --argjson logging "${logging:-null}" --argjson lifecycle "${lifecycle:-[]}" \
            '{name: $name, region: $region, storage: $storage, objects: $objects, logging_target: $logging, lifecycle: $lifecycle}'
    done 3< <(cat "$tmp_dir"/buckets-*.txt 2>/dev/null | sort -u) | jq -s '.' > "$out" 2>/dev/null || rm -f "$out"
    rm -rf "$tmp_dir"
}

# HTML report of cloud-resources ccloud|aws|azure costs-history (tools/cloud-costs/costs_report.py)
# $1: ccloud, aws or azure, $2: folder with one raw cost API response per month (<start date>_<end date>.json),
# $3: output dir, $4: non-empty to never open it, $5: user of the cflt_managed_id tag (aws, azure)
function write_cloud_costs_report() {
    local cloud="$1"
    local data_dir="$2"
    local output_dir="$3"
    local no_open="$4"
    local user="$5"
    if ! command -v python3 > /dev/null 2>&1
    then
        logwarn "⚠️ python3 is not on PATH: no HTML report"
        return 0
    fi
    mkdir -p "$output_dir"
    output_dir=$(cd "$output_dir" && pwd)
    local report="$output_dir/${cloud}-costs-history-$(date '+%Y%m%d-%H%M%S').html"
    if ! python3 -I "$root_folder/tools/cloud-costs/costs_report.py" --cloud "$cloud" --data-dir "$data_dir" --user "$user" --html-out "$report"
    then
        logerror "❌ could not write the HTML report"
        return 1
    fi
    open_html_report "$report" "$no_open"
}

# HTML report of playground cloud-resources ccloud costs: one range of dates
# $1: raw response of confluent billing cost list, named <start date>_<end date>.json, $2: output dir, $3: non-empty for --no-open, $4: user
function write_ccloud_costs_range_report() {
    local range_file="$1"
    local output_dir="$2"
    local no_open="$3"
    local user="$4"
    if ! command -v python3 > /dev/null 2>&1
    then
        logwarn "⚠️ python3 is not on PATH: no HTML report"
        return 0
    fi
    mkdir -p "$output_dir"
    output_dir=$(cd "$output_dir" && pwd)
    local report="$output_dir/ccloud-costs-$(basename "$range_file" .json)-$(date '+%Y%m%d-%H%M%S').html"
    if ! python3 -I "$root_folder/tools/cloud-costs/costs_report.py" --cloud ccloud --range-file "$range_file" --user "$user" --html-out "$report"
    then
        logerror "❌ could not write the HTML report"
        return 1
    fi
    open_html_report "$report" "$no_open"
}

# Prints the image of cfk-analysis, built on first use: dependencies baked once, code mounted at run time. The tag changes
# when the Dockerfile or requirements change, so the image is rebuilt only then. playground analyze logs calls it once
# before analyzing several bundles in parallel (a single build). Messages on stderr: stdout is the image name
function cfk_analyzer_image() {
    local analyzer_dir="$root_folder/cfk-analysis"
    local image_tag
    image_tag=$(cat "$analyzer_dir/Dockerfile" "$analyzer_dir/requirements.txt" | cksum | cut -d ' ' -f 1)
    local image="cfk-bundle-analyzer:$image_tag"
    if ! docker image inspect "$image" > /dev/null 2>&1
    then
        log "🏗️  Building $image (first run only)..." >&2
        local build_log="/tmp/cfk-bundle-analyzer-build.log"
        if ! docker build --load -t "$image" "$analyzer_dir" > "$build_log" 2>&1 && ! docker build -t "$image" "$analyzer_dir" >> "$build_log" 2>&1
        then
            logerror "❌ Failed to build $image, see $build_log" >&2
            tail -20 "$build_log" >&2
            return 1
        fi
    fi
    echo "$image"
}

# Runs cfk-analysis (Docker image built on first use) on a CFK support bundle: prints the text digest and writes the
# HTML report in the output dir (opened in an interactive terminal), or prints the JSON on stdout.
# Used by playground analyze logs (CFK bundle detected) and its hidden alias playground analyze cfk-bundle.
# $1: bundle (directory or archive), $2: non-empty for --json, $3: non-empty to not sanitize (no --sanitize), $4: minimal severity,
# $5: max issues per category in text mode, $6: output dir, $7: non-empty for --include-warnings, then the components
# Returns the exit code of the analyzer: 0 analysis completed, 64 invalid, unsafe or empty bundle
function analyze_cfk_bundle() {
    local bundle="$1"
    local json_out="$2"
    local no_sanitize="$3"
    local severity="$4"
    local top="$5"
    local output_dir="$6"
    local include_warnings="$7"
    shift 7
    local component
    local analyzer_dir="$root_folder/cfk-analysis"
    if [[ ! -f "$analyzer_dir/analyzer_cli.py" ]]
    then
        logerror "❌ CFK analyzer not found at: $analyzer_dir/analyzer_cli.py"
        return 1
    fi

    local image
    image=$(cfk_analyzer_image) || return 1

    local bundle_abs
    bundle_abs=$(cd "$(dirname "$bundle")" && pwd -P)/$(basename "$bundle")
    local bundle_container="/tmp/input/$(basename "$bundle")"
    local cli_args=("$bundle_container")
    if [[ -n "$json_out" ]]
    then
        cli_args+=(--json)
    fi
    if [[ -n "$no_sanitize" ]]
    then
        cli_args+=(--no-sanitize)
    fi
    if [[ -n "$severity" ]]
    then
        cli_args+=(--severity "$severity")
    fi
    if [[ -n "$top" ]]
    then
        cli_args+=(--top "$top")
    fi
    if [[ -n "$include_warnings" ]]
    then
        cli_args+=(--include-warnings)
    fi
    for component in "$@"
    do
        cli_args+=(--component "$component")
    done

    # run as the current user: it can read the bundle and write the HTML report
    local docker_args=(
        --rm
        --user "$(id -u):$(id -g)"
        -v "$analyzer_dir:/tmp/cfk-analysis:ro"
        -v "$root_folder/tools/report-common:/tmp/report-common:ro"
        -v "$bundle_abs:$bundle_container:ro"
    )
    # internal links of the known CFK issues (cfk-analysis/runbooks.py), kept by Confluent support in the private
    # reproduction-models repository
    local runbooks_file="${PLAYGROUND_CFK_RUNBOOKS_FILE:-$root_folder/reproduction-models/_miscellaneous/cfk-analysis/runbooks-internal.json}"
    if [[ -f "$runbooks_file" ]]
    then
        docker_args+=(-v "$runbooks_file:/tmp/cfk-runbooks-private.json:ro" -e CFK_RUNBOOKS_PRIVATE=/tmp/cfk-runbooks-private.json)
    fi

    # the HTML report is always written (not with --json: stdout must stay JSON)
    local html_out=""
    if [[ -z "$json_out" ]]
    then
        mkdir -p "$output_dir"
        local output_dir_abs
        output_dir_abs=$(cd "$output_dir" && pwd -P)
        local bundle_basename
        bundle_basename=$(basename "$bundle")
        # strip common archive suffixes for a clean filename
        bundle_basename="${bundle_basename%.tar.gz}"
        bundle_basename="${bundle_basename%.tgz}"
        bundle_basename="${bundle_basename%.tar}"
        bundle_basename="${bundle_basename%.zip}"
        # CFK_ANALYSIS_REPORT_SUFFIX: set by playground analyze logs when bundles analyzed in parallel share a name
        html_out="${output_dir_abs}/${bundle_basename}${CFK_ANALYSIS_REPORT_SUFFIX:-}-cfk-report-$(date '+%Y%m%d-%H%M%S').html"
        cli_args+=(--html-out "/tmp/output/$(basename "$html_out")")
        # the JSON of the analysis next to the report: playground analyze logs compares several bundles with it
        CFK_ANALYSIS_JSON="${html_out%.html}.json"
        cli_args+=(--json-out "/tmp/output/$(basename "$CFK_ANALYSIS_JSON")")
        # the ✏️ links of the report open the files in the editor, at their path on the host: the files of the bundle
        # folder, or copies next to the report for an archive or a folder extracted by playground analyze logs
        docker_args+=(-v "$output_dir_abs:/tmp/output" -e PLAYGROUND_REPORT_HOST_DIR="$output_dir_abs"
                      -e PLAYGROUND_EDITOR="$(playground config get editor 2>/dev/null)")
        if [[ -d "$bundle" && -z "${CFK_ANALYSIS_TEMPORARY:-}" ]]
        then
            docker_args+=(-e PLAYGROUND_BUNDLE_HOST_DIR="$bundle_abs")
        fi
    fi
    if [[ -n "${CFK_ANALYSIS_LABEL:-}" ]]
    then
        cli_args+=(--label "$CFK_ANALYSIS_LABEL")
    fi
    # playground analyze logs --problem: the problem statement, matched against the bundle (cfk-analysis/problem.py)
    if [[ -n "${CFK_ANALYSIS_PROBLEM:-}" ]]
    then
        cli_args+=(--problem "$CFK_ANALYSIS_PROBLEM")
    fi

    docker run "${docker_args[@]}" "$image" "${cli_args[@]}"
    local exit_code=$?
    case $exit_code in
        0) ;;
        64) logerror "❌ Analysis failed — invalid, unsafe or empty bundle (see error above)." ;;
        *) logerror "❌ Analyzer failed with exit code $exit_code." ;;
    esac

    # CFK_ANALYSIS_HTML: the report written, CFK_ANALYSIS_NO_OPEN: not opened (playground analyze logs links it from its
    # own report, a tab per bundle is too many)
    CFK_ANALYSIS_HTML=""
    if [[ $exit_code -eq 0 && -n "$html_out" && -f "$html_out" ]]
    then
        CFK_ANALYSIS_HTML="$html_out"
        log ""
        open_html_report "$html_out" "${CFK_ANALYSIS_NO_OPEN:-}"
    fi
    return $exit_code
}

# Comparison of several CFK support bundles (cfk-analysis/compare.py), from the JSON of their analysis: sorted by the
# time they were collected, each one compared with the previous one (same cluster?, versions, changes between them,
# issues fixed / new / still there).
# $1: non-empty for JSON on stdout (no HTML report), $2: output directory of the HTML report, then the JSON files
function compare_cfk_bundles() {
    local json_out="$1"
    local output_dir="$2"
    shift 2
    local analyzer_dir="$root_folder/cfk-analysis"
    local image_tag
    image_tag=$(cat "$analyzer_dir/Dockerfile" "$analyzer_dir/requirements.txt" | cksum | cut -d ' ' -f 1)
    local image="cfk-bundle-analyzer:$image_tag"
    local docker_args=(--rm --user "$(id -u):$(id -g)" --entrypoint python
        -v "$analyzer_dir:/tmp/cfk-analysis:ro" -v "$root_folder/tools/report-common:/tmp/report-common:ro")
    local args=()
    local i=0
    local file
    for file in "$@"
    do
        docker_args+=(-v "$(cd "$(dirname "$file")" && pwd -P)/$(basename "$file"):/tmp/input/analysis-$i.json:ro")
        args+=("/tmp/input/analysis-$i.json")
        i=$((i + 1))
    done
    if [[ -n "$json_out" ]]
    then
        docker run "${docker_args[@]}" "$image" -E -s /tmp/cfk-analysis/compare.py "${args[@]}" --json
        return $?
    fi
    mkdir -p "$output_dir"
    local output_dir_abs
    output_dir_abs=$(cd "$output_dir" && pwd -P)
    local html_out="cfk-bundles-comparison-$(date '+%Y%m%d-%H%M%S').html"
    docker run "${docker_args[@]}" -v "$output_dir_abs:/tmp/output" "$image" -E -s /tmp/cfk-analysis/compare.py "${args[@]}" \
        --html-out "/tmp/output/$html_out"
    local exit_code=$?
    # CFK_COMPARISON_HTML: the report written, opened unless CFK_ANALYSIS_NO_OPEN (see analyze_cfk_bundle)
    CFK_COMPARISON_HTML=""
    if [[ $exit_code -eq 0 && -f "$output_dir_abs/$html_out" ]]
    then
        CFK_COMPARISON_HTML="$output_dir_abs/$html_out"
        log ""
        open_html_report "$output_dir_abs/$html_out" "${CFK_ANALYSIS_NO_OPEN:-}"
    fi
    return $exit_code
}

# HTML report of the records written by summarize_log_errors in PG_LOG_DIGEST_RECORDS_FILE (tools/log-analyzer/log_report.py)
# $1: records file, $2: report, $3: non-empty to never open it, then the options of log_report.py (--title, --heading...)
function write_log_records_report() {
    local records_file="$1"
    local report="$2"
    local no_open="$3"
    shift 3
    if ! command -v python3 > /dev/null 2>&1
    then
        logwarn "⚠️ python3 is not on PATH: no HTML report"
        return 0
    fi
    mkdir -p "$(dirname "$report")"
    if ! python3 -I "$root_folder/tools/log-analyzer/log_report.py" --records "$records_file" --html-out "$report" "$@"
    then
        logerror "❌ could not write the HTML report"
        return 1
    fi
    open_html_report "$report" "$no_open"
}

# Ranked search over every runnable example script (a .sh sourcing scripts/utils.sh).
# Each query term must match somewhere; path and connector class matches weigh
# more than the script body or README. An empty query matches every script of the category.
# $1: query, $2: limit, $3: optional category: a top-level folder, or a topic
# (security, broker, cfk, client) matched on the path, README title, default
# environment and script body of the examples of every folder
function find_examples() {
    local query="$1"
    local limit="${2:-10}"
    local category="$3"
    local categories="connect ccloud ksqldb flink schema-registry rest-proxy multi-data-center other operator academy environment reproduction-models"
    local topic=""

    case "$category" in
        security|broker|cfk|client)
            topic="$category"
        ;;
        "")
        ;;
        *)
            categories="$category"
        ;;
    esac

    local dirs=()
    local c
    for c in $categories
    do
        if [ -d "$root_folder/$c" ]
        then
            dirs+=("$root_folder/$c")
        fi
    done
    if [ ${#dirs[@]} -eq 0 ]
    then
        return 0
    fi

    find "${dirs[@]}" -maxdepth 5 -type f -name "*.sh" ! -name "stop.sh" -print0 2>/dev/null \
        | xargs -0 grep -l "scripts/utils.sh" 2>/dev/null \
        | awk -v query="$query" -v root="$root_folder/" -v topic="$topic" '
        # the example belongs to topic t. path: lowercase relative path and README title. A keyword in the path of a
        # connector example (connect/, academy/, ccloud/fm-*) is about the external system (SSL to a database,
        # Salesforce PushTopics, tools cert for the TLS of a database...), so those only count with their default
        # environment, playground rbac or playground broker
        function in_topic(t, path, env, body,    conn) {
            conn = path ~ /^(connect\/|academy\/|ccloud\/fm-)/
            if (t == "security")
                return (!conn && path ~ /(rbac|ldap|kerberos|sasl|ssl|mtls|oauth|oidc|audit|secret|security|authentication|csfle|certificate|redactor)/) \
                    || (!conn && path ~ /(^|[^a-z])(acls?|tls|krb5?)([^a-z]|$)/) \
                    || env ~ /^(sasl|2way-ssl|kerberos|ssl_kerberos|ldap|rbac|cfk-rbac)/ \
                    || body ~ /playground rbac / \
                    || (!conn && body ~ /playground tools cert /)
            if (t == "broker")
                return path ~ /(cluster-linking|mirrormaker|replicator|offsets-migrator)/ \
                    || path ~ /^multi-data-center\// \
                    || (!conn && path !~ /^ksqldb\// && path ~ /(broker|topic-policy|transaction|kraft|zookeeper|tiered-storage|quota|reassign|leader-election|rebalancer|log-compaction)/) \
                    || body ~ /playground broker /
            if (t == "cfk")
                return path ~ /(cfk|kubernetes|k8s|(^|[^a-z])operator)/ || env ~ /^cfk/
            if (t == "client")
                return path ~ /(client|producer|consumer|kafkajs|dotnet|librdkafka|kcat|golang|python)/
            return 0
        }
        function readme_title(dir,    file, line, title) {
            if (dir in titles) return titles[dir]
            title = ""
            readme[dir] = ""
            file = dir "/README.md"
            while ((getline line < file) > 0) {
                if (title == "" && line ~ /^#[ \t]+/) { title = line; sub(/^#[ \t]+/, "", title) }
                if (length(readme[dir]) < 8000) readme[dir] = readme[dir] "\n" tolower(line)
            }
            close(file)
            titles[dir] = title
            return title
        }
        BEGIN {
            nterms = split(tolower(query), raw, /[^a-z0-9.+_-]+/)
            n = 0
            for (i = 1; i <= nterms; i++) if (length(raw[i]) > 1) terms[++n] = raw[i]
            nterms = n
        }
        {
            file = $0
            rel = substr(file, length(root) + 1)
            dir = file
            sub(/\/[^\/]*$/, "", dir)
            name = file
            sub(/^.*\//, "", name)
            sub(/\.sh$/, "", name)
            title = readme_title(dir)

            body = ""
            classes = ""
            env = ""
            while ((getline line < file) > 0) {
                if (length(body) < 8000) body = body "\n" tolower(line)
                if (match(line, /"connector\.class"[ \t]*:[ \t]*"[^"$]+"/)) {
                    cls = substr(line, RSTART, RLENGTH)
                    sub(/^"connector\.class"[ \t]*:[ \t]*"/, "", cls)
                    sub(/"$/, "", cls)
                    if (index(" " classes " ", " " cls " ") == 0) classes = (classes == "" ? cls : classes " " cls)
                }
                if (env == "" && match(line, /PLAYGROUND_ENVIRONMENT:-"?[A-Za-z0-9_-]+/)) {
                    env = substr(line, RSTART, RLENGTH)
                    sub(/^PLAYGROUND_ENVIRONMENT:-"?/, "", env)
                }
            }
            close(file)

            lrel = tolower(rel)
            lclasses = tolower(classes)
            ltitle = tolower(title)
            if (topic != "" && !in_topic(topic, lrel "\n" ltitle, env, body)) next
            haystack = lrel "\n" ltitle "\n" lclasses "\n" body readme[dir]

            score = 0
            for (i = 1; i <= nterms; i++) {
                t = terms[i]
                in_path = index(lrel, t) > 0
                in_class = index(lclasses, t) > 0
                in_title = index(ltitle, t) > 0
                in_body = index(haystack, t) > 0
                if (!in_path && !in_class && !in_title && !in_body) { score = -1; break }
                score += in_path * 10 + in_class * 6 + in_title * 4 + in_body
            }
            if (score < 0) next
            # prefer the canonical variant of a family over its many derivatives
            score -= split(name, parts, "-") * 0.1

            printf "%.1f\t%s\t%s\t%s\t%s\n", score, rel, title, classes, env
        }' \
        | sort -t "$(printf '\t')" -k1,1nr -k2,2 \
        | head -n "$limit"
}

# Ranked search over what the CLI can do, for 'playground find-command'.
# Sources, best weighted first:
#   1. the tables of docs/which-command.md (question -> command, raw command -> playground command)
#   2. the "Recipes for support repros" tables of docs/deep-dive-*.md (symptom -> commands)
#   3. the help of every public command (scripts/cli/playground.json)
# Every hit is attached to the command it uses (longest known command path), one line per command.
# Output: one line per command, best first, fields separated by \037 (not a tab: read would merge empty fields):
# score, command, matched text, usage, deep dive URL, source
# $1: query, $2: limit
function find_commands() {
    local query="$1"
    local limit="${2:-5}"
    local catalog="$root_folder/docs/which-command.md"
    local spec="$root_folder/scripts/cli/playground.json"

    if [ ! -f "$spec" ]
    then
        logerror "❌ $spec not found"
        return 1
    fi

    local commands_tsv
    commands_tsv=$(mktemp)
    # path, summary (first line of the help), aliases + full help on one line, first deep dive URL of the help
    jq -r '
        def cmds(p): (.subcommands // [])[] | (p + [.name]) as $q
            | {path: ($q | join(" ")), names: (.names // [.name]), desc: (.description // "")}, cmds($q);
        cmds([]) | select(.path != "help")
        | [.path,
           (.desc | split("\n")[0]),
           # the URLs left out of the text searched: kafka-docker-playground.io in the 🍪 / 🎬 links of a help made it
           # match "docker" ("docker logs" found analyze logs before container logs)
           ((.names | join(" ")) + " " + (.desc | gsub("https?://[^ \t\n)]+"; " ") | gsub("[\t\n\r]+"; " "))),
           ((.desc | capture("Deep dive: (?<u>https://[^ \n)]+)") | .u) // "")]
        | @tsv' "$spec" > "$commands_tsv"

    local recipes=()
    local f
    for f in "$root_folder"/docs/deep-dive-*.md
    do
        [ -f "$f" ] && recipes+=("$f")
    done

    awk -v query="$query" -v limit="$limit" -v catalog="$catalog" '
    function stem(w) {
        if (length(w) > 5 && w ~ /ing$/) return substr(w, 1, length(w) - 3)
        if (length(w) > 4 && w ~ /ed$/) return substr(w, 1, length(w) - 2)
        if (length(w) > 4 && w ~ /es$/) return substr(w, 1, length(w) - 2)
        if (length(w) > 3 && w ~ /s$/ && w !~ /ss$/) return substr(w, 1, length(w) - 1)
        return w
    }
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    # longest known command path used in a table cell: `playground a b ...` or a bare `a b ...` in backticks
    function command_of(cell,    rest, seg, words, n, i, cand, best_here) {
        rest = cell
        while (match(rest, /`[^`]+`/)) {
            seg = substr(rest, RSTART + 1, RLENGTH - 2)
            rest = substr(rest, RSTART + RLENGTH)
            sub(/^playground[ \t]+/, "", seg)
            n = split(seg, words, /[ \t]+/)
            cand = ""
            best_here = ""
            for (i = 1; i <= n && i <= 4; i++) {
                cand = (i == 1 ? words[1] : cand " " words[i])
                if (cand in known) best_here = cand
                else if (i > 1) break
            }
            if (best_here != "") return best_here
        }
        return ""
    }
    # term t (or one of its synonyms) found in s
    function has(s, t,    k, n, w) {
        if (index(s, terms[t]) > 0) return 1
        if (!(t in syn)) return 0
        n = split(syn[t], w, " ")
        for (k = 1; k <= n; k++) if (index(s, w[k]) > 0) return 1
        return 0
    }
    # text is searched with weight, extra (the usage, with its flags) with weight 1.
    # Generic terms (connector, kafka...) add to the score but do not count to reach the coverage needed,
    # otherwise "memory issue with connector" matches anything that says connector.
    function add(cmd, matched, usage, url, source, weight, text, extra,    t, low, lowx, hits, score, path_hits, need, s, hit, phit, gw_factor) {
        if (cmd == "" || !(cmd in known)) return
        low = tolower(text)
        lowx = tolower(extra)
        hits = 0; score = 0; path_hits = 0
        for (t = 1; t <= nterms; t++) {
            hit = 0; phit = 0
            gw_factor = (t in generic ? 0.5 : 1)
            if (has(low, t)) {
                hit = 1; score += weight * gw_factor
                # the exact word typed ("working") beats its stem ("work" in "worker")
                if (word[t] != terms[t] && index(low, word[t]) > 0) score += gw_factor
            }
            else if (lowx != "" && has(lowx, t)) { hit = 1; score += gw_factor }
            if (index(" " cmd, " " terms[t]) > 0) { phit = 1; score += 2 * gw_factor }
            if (nsig > 0 && (t in generic)) continue
            hits += hit; path_hits += phit
        }
        need = (ncount <= 2 ? 1 : int((ncount + 1) / 2))
        if (hits < need && path_hits < need) return
        # the words typed, in that order, in the text ("docker logs" in "instead of `docker logs <c>`"): the row says what
        # was asked, not only a command whose help has one of the words many times
        if (nterms >= 2 && index(low, phrase) > 0) score += weight
        s = score * ((hits > path_hits ? hits : path_hits) / ncount)
        if (!(cmd in best) || s > best[cmd]) {
            best[cmd] = s
            bmatched[cmd] = matched; busage[cmd] = usage; bsource[cmd] = source
            if (url != "") burl[cmd] = url
        }
        # only the rows that match every specific term of the question add to the score: a page with many rows
        # repeating one word of it ("logs") must not outrank the command that matches the whole question
        if ((hits > path_hits ? hits : path_hits) >= ncount) full[cmd]++
    }
    BEGIN {
        split("a about an and any are as at be by can could do does doing for from get got has have having help how i if in into is issue it its me my no not of on or please problem show so some tell that the their them there these this to trouble was we what when where which who why will with without you your", sw, " ")
        for (i in sw) stop[sw[i]] = 1
        split("connector connect kafka playground command", gw, " ")
        for (i in gw) is_generic[gw[i]] = 1
        # synonyms, stemmed: a term of a group also matches the other words of its group
        ngroups = split("memory heap oom outofmemory leak|cpu stuck hanging|slow latency performance throughput|ssl tls certificat handshake", groups, "|")
        for (g = 1; g <= ngroups; g++) {
            split(groups[g], gwords, " ")
            for (i in gwords) group_of[gwords[i]] = groups[g]
        }
        n = split(tolower(query), raw, /[^a-z0-9._+-]+/)
        nterms = 0
        for (i = 1; i <= n; i++) {
            w = raw[i]; gsub(/^[-.]+|[-.]+$/, "", w)
            if (length(w) < 2 || (w in stop)) continue
            typed = w
            w = stem(w)
            if (!(w in seen)) {
                phrase = (nterms ? phrase " " : "") typed
                seen[w] = 1; terms[++nterms] = w; word[nterms] = typed
                if (w in is_generic) generic[nterms] = 1
                else nsig++
                if (w in group_of) { syn[nterms] = group_of[w] }
            }
        }
        if (nterms == 0) exit
        # number of terms the coverage is computed on: the specific ones when there are some
        ncount = (nsig > 0 ? nsig : nterms)
        FS = "\t"
    }
    # 1. help of every command
    FILENAME == ARGV[1] {
        known[$1] = 1; summary[$1] = $2; help_text[$1] = $3; help_url[$1] = $4
        next
    }
    FNR == 1 && FILENAME != ARGV[1] && !help_done {
        help_done = 1
        for (c in known) add(c, summary[c], "", help_url[c], "help", 1, summary[c] " " help_text[c], "")
    }
    # 2. catalog and deep-dive recipe tables (markdown rows)
    FNR == 1 { in_recipes = 0; page = FILENAME; sub(/^.*\//, "", page); sub(/\.md$/, "", page) }
    /^## / { in_recipes = (FILENAME != catalog && $0 ~ /[Rr]ecipes/) }
    /^\| *--- *\|/ { next }
    /^\| / {
        if (FILENAME != catalog && !in_recipes) next
        line = $0
        gsub(/\\\|/, "\001", line)
        nc = split(line, cells, /[ \t]*\|[ \t]*/)
        c1 = cells[2]; c2 = cells[3]; c3 = (nc > 4 ? cells[4] : "")
        gsub(/\001/, "|", c1); gsub(/\001/, "|", c2); gsub(/\001/, "|", c3)
        if (c1 ~ /^(Question|Instead of|Customer symptom|Symptom)/) next
        if (FILENAME == catalog) {
            if (c3 != "") {
                # question | command | instead of: the question weighs most, the raw command and the usage like flags
                add(command_of(c2), c1, c2, "", "catalog", 3, c1, c3 " " c2)
            } else {
                # instead of | use
                add(command_of(c2), "instead of " c1, c2, "", "catalog", 3, c1 " " c1, c2)
            }
        } else {
            add(command_of(c2), c1, c2, "https://kafka-docker-playground.io/#/" page, "deep dive", 2, c1 " " c1, c2)
        }
        next
    }
    END {
        if (nterms == 0) exit
        top = 0
        for (c in best) { total[c] = best[c] + (full[c] > 1 ? full[c] - 1 : 0) * 0.5; if (total[c] > top) top = total[c] }
        for (c in best) {
            # drop the long tail: weak matches far below the best one
            if (total[c] < top * 0.3) continue
            url = (c in burl ? burl[c] : help_url[c])
            if (url == "") {
                # inherit the deep dive of the parent command
                p = c; while (url == "" && sub(/ [^ ]+$/, "", p)) url = help_url[p]
            }
            m = bmatched[c]; u = busage[c]
            gsub(/[\t\r\n\037]+/, " ", m); gsub(/[\t\r\n\037]+/, " ", u)
            if (m ~ /^".*"$/) m = substr(m, 2, length(m) - 2)
            printf "%.1f\037%s\037%s\037%s\037%s\037%s\n", total[c], c, m, u, url, bsource[c]
        }
    }' "$commands_tsv" "$catalog" "${recipes[@]}" | sort -t $'\037' -k1,1nr -k2,2 | head -n "$limit"

    rm -f "$commands_tsv"
}

# shared by switch-podman / switch-docker: the docker context is what the docker CLI,
# docker compose, k3d and the playground follow, unless DOCKER_HOST overrides it
function warn_container_engine_switch() {
  local leaving="$1"
  if [ -n "${DOCKER_HOST:-}" ]
  then
    logwarn "DOCKER_HOST is set (${DOCKER_HOST}): it overrides the docker context in this shell"
    logwarn "  unset DOCKER_HOST"
  fi
  local running
  running=$(docker ps -q --filter "label=com.docker.compose.project" 2>/dev/null | wc -l | tr -d ' ')
  if [ "${running:-0}" -gt 0 ]
  then
    logwarn "${running} container(s) are still running on ${leaving}: they are not moved to the other engine"
    logwarn "  stop them first with 'playground stop', or switch back to reach them"
  fi
}

# the user's docker config, even when DOCKER_CONFIG points at the mirror without
# credHelpers (see export_docker_config_without_cred_helpers): `docker context use`
# must land there, or the switch would only exist inside this playground call
function docker_user_config_dir() {
  echo "${PLAYGROUND_DOCKER_CONFIG_ORIGINAL:-${DOCKER_CONFIG:-$HOME/.docker}}"
}

# DOCKER_HOST and DOCKER_CONTEXT are ignored too: they override the configured context,
# and `docker context show` would then report "default" instead of what is configured
function docker_with_user_config() {
  env -u DOCKER_HOST -u DOCKER_CONTEXT DOCKER_CONFIG="$(docker_user_config_dir)" docker "$@"
}

# values computed for the engine of the previous context, which the doctor run at the
# end of a switch must not inherit: it detects the new engine from scratch, and
# mirrors the docker config again if that engine needs it
function reset_container_engine_detection() {
  local user_config
  user_config=$(docker_user_config_dir)
  unset PLAYGROUND_CONTAINER_ENGINE DOCKER_BUILDKIT PLAYGROUND_DOCKER_CONFIG_ORIGINAL
  if [ "$user_config" = "$HOME/.docker" ]
  then
    unset DOCKER_CONFIG
  else
    export DOCKER_CONFIG="$user_config"
  fi
}

# Takes thread dumps of a container with kill -3: the JVM prints them on its stdout, so they land in the container
# logs. No JDK is needed in the image and the JVM is not restarted. The dumps are extracted from the logs (interleaved
# log4j lines removed) into the output file.
# $1: container (as given on the command line), $2: number of dumps, $3: seconds between dumps, $4: output file
# Returns 0 when at least one dump was captured.
function take_thread_dumps_with_kill_quit() {
  local container="$1" count="$2" interval="$3" output_file="$4"
  local resolved_container pid start since raw_file i

  resolved_container=$(resolve_container_name_for_environment "$container")
  pid=$(playground --output-level ERROR container exec --container "$resolved_container" --command "if ls -l /proc/1/exe 2>/dev/null | grep -q java; then echo 1; else for p in /proc/[0-9]*; do if tr '\\000' ' ' < \$p/cmdline 2>/dev/null | grep -q '^[^ ]*java '; then echo \${p#/proc/}; break; fi; done; fi" 2>/dev/null | tr -d '\r' | head -1)
  if [[ -z "$pid" ]]
  then
    logwarn "no java process found in container $container"
    return 1
  fi

  start=$(date +%s)
  for i in $(seq 1 "$count")
  do
    playground --output-level ERROR container exec --container "$resolved_container" --command "kill -3 $pid" > /dev/null 2>&1
    if [[ $i -lt $count ]]
    then
      sleep "$interval"
    fi
  done
  sleep 2
  since=$(( $(date +%s) - start + 5 ))
  raw_file=$(mktemp -t pg-thread-dump-XXXXXXXXXX)
  playground --output-level ERROR container logs --container "$container" --no-follow --since "${since}s" > "$raw_file" 2>&1

  # keep each dump from its timestamp line to "JNI global refs", without the application log lines printed meanwhile
  awk '
    /^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$/ { date = $0; next }
    /Full thread dump/ { in_dump = 1; if (date != "") print date; date = "" }
    in_dump && /^\[[0-9]{4}-[0-9]{2}-[0-9]{2}[ T]/ { next }
    in_dump { print }
    in_dump && /^JNI global ref/ { in_dump = 0; print "" }
  ' "$raw_file" > "$output_file"
  rm -f "$raw_file"

  grep -q "Full thread dump" "$output_file"
}

# 30 -> 30, 30s -> 30, 5m -> 300, 1h -> 3600 (format checked by validate_duration)
function duration_to_seconds() {
  local value="$1"
  case "$value" in
    *h) echo $(( ${value%h} * 3600 )) ;;
    *m) echo $(( ${value%m} * 60 )) ;;
    *s) echo "${value%s}" ;;
    *) echo "$value" ;;
  esac
}

# connect worker container and JMX port of a worker id from the connect REST API (connect:8083, connect2:8283...)
function benchmark_worker_container_and_port() {
  local worker_id="$1"
  local host="${worker_id%%:*}"
  host="${host%%.*}"
  case "$host" in
    connect2) echo "connect2 10022" ;;
    connect3) echo "connect3 10032" ;;
    *) echo "connect 10002" ;;
  esac
}

# jmxterm commands of one connect worker, read from stdin, printed as 'attribute = value;' lines
function benchmark_jmxterm() {
  local container="$1"
  local port="$2"
  docker exec -i "$container" java -jar "$BENCHMARK_JMXTERM_JAR" -l "localhost:$port" -n -v silent 2> /dev/null
}

# copies jmxterm to the connect workers running the tasks of the connector, fails when it cannot (no worker, download or
# copy failed): without it every sample would read 0 records
function benchmark_jmx_init() {
  local workers="$1"
  BENCHMARK_JMXTERM_JAR="/tmp/jmxterm-1.0.2-uber.jar"
  # bean names of each worker, listed once and refreshed when the task set changes (benchmark_jmx_invalidate_beans)
  if [ -z "$BENCHMARK_JMX_BEANS_DIR" ]
  then
    BENCHMARK_JMX_BEANS_DIR=$(mktemp -d -t playground-benchmark-beans.XXXXXX)
  fi
  if [ -z "$(echo "$workers" | grep .)" ]
  then
    logerror "❌ no connect worker runs a task of the connector: nothing to read the JMX metrics from"
    return 1
  fi
  # a failed download used to be cached as an html page: a jar is a zip file, it starts with PK
  if [ -f "$BENCHMARK_JMXTERM_JAR" ] && [ "$(head -c 2 "$BENCHMARK_JMXTERM_JAR" 2> /dev/null)" != "PK" ]
  then
    rm -f "$BENCHMARK_JMXTERM_JAR"
  fi
  if [ ! -f "$BENCHMARK_JMXTERM_JAR" ]
  then
    if ! curl -fsSL https://github.com/jiaqi/jmxterm/releases/download/v1.0.2/jmxterm-1.0.2-uber.jar -o "$BENCHMARK_JMXTERM_JAR.tmp" \
      || [ "$(head -c 2 "$BENCHMARK_JMXTERM_JAR.tmp" 2> /dev/null)" != "PK" ]
    then
      rm -f "$BENCHMARK_JMXTERM_JAR.tmp"
      logerror "❌ could not download jmxterm (https://github.com/jiaqi/jmxterm/releases/download/v1.0.2/jmxterm-1.0.2-uber.jar), needed to read the JMX metrics of the tasks"
      return 1
    fi
    mv "$BENCHMARK_JMXTERM_JAR.tmp" "$BENCHMARK_JMXTERM_JAR"
  fi
  local container port
  while read -r container port
  do
    [ -z "$container" ] && continue
    if ! playground container cp --source "$BENCHMARK_JMXTERM_JAR" --destination "$container:$BENCHMARK_JMXTERM_JAR" > /dev/null 2>&1
    then
      logerror "❌ could not copy jmxterm to container $container, needed to read the JMX metrics of the tasks"
      return 1
    fi
  done <<< "$workers"
}

# forgets the bean names listed by benchmark_jmx_sample: the next sample lists them again (task set changed)
function benchmark_jmx_invalidate_beans() {
  if [ -n "$BENCHMARK_JMX_BEANS_DIR" ] && [ -d "$BENCHMARK_JMX_BEANS_DIR" ]
  then
    rm -f "$BENCHMARK_JMX_BEANS_DIR"/*.beans
  fi
}

function benchmark_jmx_cleanup() {
  if [ -n "$BENCHMARK_JMX_BEANS_DIR" ] && [ -d "$BENCHMARK_JMX_BEANS_DIR" ]
  then
    rm -rf "$BENCHMARK_JMX_BEANS_DIR"
  fi
}

# grafana of the environment (--enable-jmx-grafana), for playground connector benchmark: an annotation of the measure on
# the dashboards of the connector, and links to them at the time of the run. Credentials of environment/plaintext.
BENCHMARK_GRAFANA_URL="http://localhost:3000"
BENCHMARK_GRAFANA_AUTH="admin:password"

# succeeds when the grafana container of the environment is running and answers
function benchmark_grafana_available () {
  [ "$(docker inspect -f '{{.State.Running}}' grafana 2> /dev/null)" == "true" ] || return 1
  curl -s -m 5 -u "$BENCHMARK_GRAFANA_AUTH" "$BENCHMARK_GRAFANA_URL/api/health" | jq -e '.database == "ok"' > /dev/null 2>&1
}

# dashboards of a connector class, "<uid>|<title>" lines read from the provisioned dashboards: kafka connect, the one of
# the connector when there is one, and the kafka cluster
function benchmark_grafana_dashboards () {
  local connector_class="$1" dir="$root_folder/environment/plaintext/grafana/provisioning/dashboards" files="kafka-connect-cluster.json" file
  case "$connector_class" in
    io.debezium.*) files="$files debezium-connectors.json" ;;
    *.OracleCdcSourceConnector) files="$files confluent-oracle-cdc.json" ;;
    *.OracleXStreamSourceConnector) files="$files xstream-connector.json" ;;
    com.mongodb.*) files="$files mongo.json" ;;
  esac
  for file in $files kafka-cluster.json
  do
    [ -f "$dir/$file" ] && jq -r '"\(.uid)|\(.title)"' "$dir/$file"
  done
}

# region annotation from <from ms> to <to ms> with <text> and <tags> (comma separated) on each dashboard of
# <dashboards> ("<uid>|<title>" lines), prints the number of dashboards annotated
function benchmark_grafana_annotate () {
  local from="$1" to="$2" text="$3" tags="$4" dashboards="$5" uid title id annotated=0
  while IFS='|' read -r uid title
  do
    [ -z "$uid" ] && continue
    # the built-in annotation query of a dashboard only shows the annotations of that dashboard
    id=$(curl -s -m 5 -u "$BENCHMARK_GRAFANA_AUTH" "$BENCHMARK_GRAFANA_URL/api/dashboards/uid/$uid" | jq -r '.dashboard.id // empty' 2> /dev/null)
    [ -z "$id" ] && continue
    if jq -n --argjson id "$id" --argjson from "$from" --argjson to "$to" --arg text "$text" --arg tags "$tags" \
        '{dashboardId: $id, time: $from, timeEnd: $to, text: $text, tags: ($tags | split(","))}' \
      | curl -s -m 5 -u "$BENCHMARK_GRAFANA_AUTH" -H 'Content-Type: application/json' -X POST "$BENCHMARK_GRAFANA_URL/api/annotations" -d @- \
      | jq -e '.id' > /dev/null 2>&1
    then
      annotated=$((annotated + 1))
    fi
  done <<< "$dashboards"
  echo "$annotated"
}

# scrape interval of the prometheus of the environment, in seconds (empty when it cannot be read)
function benchmark_grafana_scrape_interval () {
  local interval
  interval=$(curl -s -m 5 "http://localhost:9090/api/v1/status/config" | jq -r '.data.yaml // empty' 2> /dev/null | awk '/^global:/ { g = 1; next } g && /^[^ ]/ { g = 0 } g && $1 == "scrape_interval:" { print $2; exit }')
  [ -n "$interval" ] && duration_to_seconds "$interval"
}

# link to a dashboard from 30 s before <from ms> to 30 s after <to ms>
function benchmark_grafana_url () {
  local uid="$1" from="$2" to="$3"
  echo "$BENCHMARK_GRAFANA_URL/d/$uid?orgId=1&from=$((from - 30000))&to=$((to + 30000))"
}

# flight recorder of JVMs over JMX (FlightRecorderMXBean, jdk.management.jfr): the cp images ship a JRE without jcmd,
# and this needs neither jcmd nor a restart. Uses jmxterm, copied by benchmark_jmx_init.
JFR_BEAN="jdk.management.jfr:type=FlightRecorder"

# starts a recording on each "<container> <jmx port>" line of $1, with the settings $2: a .jfc file (default
# tools/jfr-analyzer/playground.jfc) or the name of settings of the JDK (profile, default). Prints
# "<container> <jmx port> <recording id>" lines. Returns 1 (after closing what was started) when a JVM has no flight
# recorder MBean (JDK 8 before 8u262) or refuses the settings
function jfr_jmx_start () {
  local workers="$1" settings="${2:-$root_folder/tools/jfr-analyzer/playground.jfc}"
  local config operation container port id out started=""
  if [ -f "$settings" ]
  then
    # setConfiguration takes the content of the .jfc: one line, without comments, single quotes (a double quote ends
    # the argument for jmxterm), spaces escaped for jmxterm
    operation="setConfiguration"
    config=$(sed '/<!--/,/-->/d' "$settings" | tr '\n' ' ' | sed "s/\"/'/g; s/  */ /g")
    config="${config// /\\ }"
  else
    operation="setPredefinedConfiguration"
    config="$settings"
  fi
  while read -r container port
  do
    [ -z "$container" ] && continue
    id=$(printf 'run -b %s newRecording\n' "$JFR_BEAN" | benchmark_jmxterm "$container" "$port" | tr -dc '0-9')
    # setConfiguration and startRecording return null when they succeed, nothing when they fail
    [ -n "$id" ] && out=$(printf 'run -b %s %s %s %s\nrun -b %s startRecording %s\n' "$JFR_BEAN" "$operation" "$id" "$config" "$JFR_BEAN" "$id" | benchmark_jmxterm "$container" "$port")
    if [ -z "$id" ] || [ "$(echo "$out" | grep -c '^null$')" -ne 2 ]
    then
      [ -n "$id" ] && started="$started"$'\n'"$container $port $id"
      jfr_jmx_discard "$started"
      return 1
    fi
    started="$started"$'\n'"$container $port $id"
    echo "$container $port $id"
  done <<< "$workers"
}

# stops the recordings of $1 ("<container> <jmx port> <recording id>" lines) and copies them to <prefix>-<container>.jfr,
# prints the paths of the .jfr files
function jfr_jmx_stop () {
  local recordings="$1" prefix="$2"
  local container port id remote local_file
  while read -r container port id
  do
    [ -z "$container" ] && continue
    remote="/tmp/playground-jfr-$id-$(date +%s).jfr"
    local_file="$prefix-$container.jfr"
    printf 'run -b %s stopRecording %s\nrun -b %s copyTo %s %s\nrun -b %s closeRecording %s\n' "$JFR_BEAN" "$id" "$JFR_BEAN" "$id" "$remote" "$JFR_BEAN" "$id" | benchmark_jmxterm "$container" "$port" > /dev/null
    if playground container cp --source "$container:$remote" --destination "$local_file" > /dev/null 2>&1 && [ -s "$local_file" ]
    then
      echo "$local_file"
    fi
    playground --output-level ERROR container exec --container "$container" --command "rm -f $remote" > /dev/null 2>&1
  done <<< "$recordings"
}

# closes (and discards) the recordings of $1, for an interrupted run
function jfr_jmx_discard () {
  local recordings="$1"
  local container port id
  while read -r container port id
  do
    [ -z "$container" ] && continue
    printf 'run -b %s closeRecording %s\n' "$JFR_BEAN" "$id" | benchmark_jmxterm "$container" "$port" > /dev/null
  done <<< "$recordings"
}

# digest of .jfr files with tools/jfr-analyzer/JfrDigest.java, in a JDK container (the source launcher needs a JDK, and
# a recent one reads the recordings of every JDK 11+): jfr_digest <output dir> <thread regex> <file.jfr>...
# prints the paths of the digests, <output dir>/<file name>.digest.json. Returns 1 when a file could not be read
function jfr_digest () {
  local output_dir="$1" threads="$2"
  shift 2
  local file digest ret=0
  for file in "$@"
  do
    digest="$output_dir/$(basename "${file%.jfr}").digest.json"
    # the recording goes through stdin: no volume for it, so it works from any folder and with podman
    if docker run --rm -i -v "$root_folder/tools/jfr-analyzer:/tools:ro" "$JFR_ANALYZER_IMAGE" \
        sh -c 'cat > /tmp/recording.jfr && exec java /tools/JfrDigest.java /tmp/recording.jfr --threads "$1"' sh "$threads" < "$file" > "$digest" 2> "$digest.log" && [ -s "$digest" ]
    then
      rm -f "$digest.log"
      echo "$digest"
    else
      ret=1
    fi
  done
  return $ret
}
JFR_ANALYZER_IMAGE="eclipse-temurin:25-jdk"

# --trace-method of the flight recorder commands: the .jfc $1 with the method tracing of JDK 25 (JEP 520) for the
# filters $2... (a class, Class::method or @Annotation): jdk.MethodTrace records every call of the methods with its
# duration and caller stack, jdk.MethodTiming the calls and min / avg / max of each method. Prints the path of the .jfc
function jfr_settings_with_method_trace () {
  local base="$1" filter jfc
  shift
  for filter in "$@"
  do
    if [[ ! "$filter" =~ ^@?[A-Za-z0-9_.$]+(::[A-Za-z0-9_$\<\>]+)?$ ]]
    then
      logerror "❌ --trace-method $filter: expected a class (io.confluent.connect.jdbc.sink.JdbcDbWriter), Class::method or @Annotation" >&2
      return 1
    fi
  done
  filter=$(IFS=';'; echo "$*")
  jfc="$(mktemp -t playground-trace-XXXXXXXXXX).jfc"
  sed '/<\/configuration>/d' "$base" > "$jfc"
  {
    echo "  <event name='jdk.MethodTrace'><setting name='enabled'>true</setting><setting name='filter'>$filter</setting><setting name='stackTrace'>true</setting><setting name='threshold'>0 ms</setting></event>"
    echo "  <event name='jdk.MethodTiming'><setting name='enabled'>true</setting><setting name='filter'>$filter</setting><setting name='period'>1 s</setting></event>"
    echo "</configuration>"
  } >> "$jfc"
  echo "$jfc"
}

# major version of the JDK of the java process of a container (8 for 1.8), empty when it cannot be read
function container_java_major () {
  local version
  version=$(playground --output-level ERROR container exec --container "$1" --command "java -version 2>&1" 2> /dev/null | sed -n 's/.*version "\([0-9.]*\).*/\1/p' | head -1)
  case "$version" in
    1.*) echo "${version#1.}" | cut -d . -f 1 ;;
    *) echo "${version%%.*}" ;;
  esac
}

# --trace-method needs the method tracing of JDK 25 (JEP 520): exits with the alternative when the JDK is older
function check_method_trace_supported () {
  local container="$1" major
  major=$(container_java_major "$container")
  if [[ -n "$major" && "$major" -lt 25 ]]
  then
    logerror "❌ --trace-method needs JDK 25 or later (method tracing, JEP 520): $container runs JDK $major"
    log "💡 playground debug jscissors -c $container --class <class> traces the calls on any JDK (8+), with their arguments"
    exit 1
  fi
}

# java agent of playground debug jscissors, built from tools/jscissors/agent with maven in a container the first time
# and after each change of its sources (no jar in the repository): prints the path of the jar. The sources are mounted
# read only and the jar comes back on stdout, so it works with podman and from any folder
function jscissors_agent_jar () {
  local src="$root_folder/tools/jscissors/agent" dir="/tmp/playground-jscissors" sum jar log
  sum=$(cd "$src" && find pom.xml src -type f | LC_ALL=C sort | xargs cat | cksum | cut -d ' ' -f 1)
  jar="$dir/jscissors-$sum.jar"
  if [ -s "$jar" ]
  then
    echo "$jar"
    return 0
  fi
  mkdir -p "$dir"
  log "📦 building the jscissors agent with maven ($JSCISSORS_BUILD_IMAGE), first run after a change of tools/jscissors/agent only" >&2
  log=$(mktemp -t jscissors-build-XXXXXXXXXX)
  if docker run --rm -v "$src:/src:ro" -v playground-jscissors-m2:/root/.m2 "$JSCISSORS_BUILD_IMAGE" \
      sh -c 'cp -r /src /build && cd /build && mvn -q -B package >&2 && cat target/jscissors.jar' > "$jar.tmp" 2> "$log" \
      && unzip -l "$jar.tmp" 2> /dev/null | grep -q 'jscissors/Agent.class'
  then
    mv "$jar.tmp" "$jar"
    rm -f "$log"
    echo "$jar"
    return 0
  fi
  rm -f "$jar.tmp"
  logerror "❌ failed to build the jscissors agent, see $log" >&2
  tail -20 "$log" >&2
  return 1
}
JSCISSORS_BUILD_IMAGE="maven:3.9.11-eclipse-temurin-17"

# one sample of the JMX metrics of the tasks of a connector, printed as space separated values:
#   1 records total (summed over the tasks)    2 batch avg ms        3 running ratio avg    4 cpu % of one core
#   5 consumer lag max (sink)                  6 cpu % of the cpus available to the worker JVM
#   7 pause ratio avg                          8 gc pause time ms (cumulative, summed over the workers)
#   9 records sent to the dlq (cumulative)     10 records skipped by errors.tolerance=all (cumulative)
#   11 records per task, as <task>:<records>;<task>:<records>
# "-" when not available. workers is a list of "container port" lines, type is sink or source
function benchmark_jmx_sample() {
  local connector="$1"
  local type="$2"
  local workers="$3"
  local counter="source-record-write-total"
  local batch="poll-batch-avg-time-ms"
  if [ "$type" == "sink" ]
  then
    # records read from kafka: the ones filtered by a transform or failing (dlq, errors.tolerance=all) never reach put
    counter="sink-record-read-total"
    batch="put-batch-avg-time-ms"
  fi
  local container port beans beans_cache task_beans task_ids
  while read -r container port
  do
    [ -z "$container" ] && continue
    # listing the beans starts a jvm in the worker, as long as reading them: list them once, until the task set changes
    # (benchmark_jmx_invalidate_beans), so that one sample is one jmxterm run per worker
    beans_cache="${BENCHMARK_JMX_BEANS_DIR:-/nonexistent}/$container-$port.beans"
    if [ -s "$beans_cache" ]
    then
      beans=$(cat "$beans_cache")
    else
      beans=$(printf 'beans -d kafka.connect\nbeans -d kafka.consumer\nbeans -d java.lang\nexit\n' | benchmark_jmxterm "$container" "$port" | grep -E "connector=$connector,task=|client-id=connector-consumer-$connector-[0-9]+,type=consumer-fetch-manager-metrics$|type=GarbageCollector" || true)
      # only a list with task beans is worth keeping: the tasks may still be starting
      if [ -n "$BENCHMARK_JMX_BEANS_DIR" ] && [ -d "$BENCHMARK_JMX_BEANS_DIR" ] && echo "$beans" | grep -qF "type=$type-task-metrics"
      then
        echo "$beans" > "$beans_cache"
      fi
    fi
    task_beans=$(echo "$beans" | grep -F "type=$type-task-metrics" || true)
    # the n-th counter value belongs to the n-th task bean
    task_ids=$(echo "$task_beans" | sed -n 's/.*task=\([0-9]*\).*/\1/p' | tr '\n' ' ')
    {
      echo "$task_beans" | while read -r bean; do [ -n "$bean" ] && echo "get -b $bean $counter $batch"; done
      echo "$beans" | grep -F "type=connector-task-metrics" | while read -r bean; do echo "get -b $bean running-ratio pause-ratio"; done
      echo "$beans" | grep -F "type=task-error-metrics" | while read -r bean; do echo "get -b $bean deadletterqueue-produce-requests total-records-skipped"; done
      echo "$beans" | grep -F "type=consumer-fetch-manager-metrics" | while read -r bean; do echo "get -b $bean records-lag-max"; done
      # pauses only: concurrent collectors report the time of their concurrent cycles; spaces escaped for jmxterm
      echo "$beans" | grep -F "type=GarbageCollector" | grep -v -E "Concurrent|Cycles" | while read -r bean; do echo "get -b ${bean// /\\ } CollectionTime"; done
      echo "get -b java.lang:type=OperatingSystem ProcessCpuLoad AvailableProcessors"
      echo "exit"
    } | benchmark_jmxterm "$container" "$port" | awk -v counter="$counter" -v ids="$task_ids" '
      BEGIN { n = split(ids, id, " ") }
      $1 == counter { i++; print "TASK", id[i], $3; next }
      $1 == "CollectionTime" { print "GC", $3; next }
      { print }'
  done <<< "$workers" | awk -v batch="$batch" '
    $1 == "TASK" { value = $3; sub(/;$/, "", value); total += value; tasks = tasks (tasks ? ";" : "") $2 ":" sprintf("%d", value); next }
    $1 == "GC" { value = $2; sub(/;$/, "", value); gc += value; gc_n++; next }
    {
      name = $1; value = $3; sub(/;$/, "", value)
      if (value == "NaN" || value == "") next
    }
    name == batch { batch_sum += value; batch_n++ }
    name == "running-ratio" { ratio_sum += value; ratio_n++ }
    name == "pause-ratio" { pause_sum += value; pause_n++ }
    name == "deadletterqueue-produce-requests" { dlq += value; dlq_n++ }
    name == "total-records-skipped" { skipped += value; skipped_n++ }
    name == "ProcessCpuLoad" { load = value }
    name == "AvailableProcessors" { cpu_sum += load * value * 100; cpu_avail_sum += load * 100; cpu_n++ }
    name == "records-lag-max" { if (!lag_n || value > lag) lag = value; lag_n++ }
    END {
      printf "%d %s %s %s %s %s %s %s %s %s %s\n", total,
        (batch_n ? sprintf("%.1f", batch_sum / batch_n) : "-"),
        (ratio_n ? sprintf("%.2f", ratio_sum / ratio_n) : "-"),
        (cpu_n ? sprintf("%.0f", cpu_sum / cpu_n) : "-"),
        (lag_n ? sprintf("%d", lag) : "-"),
        (cpu_n ? sprintf("%.0f", cpu_avail_sum / cpu_n) : "-"),
        (pause_n ? sprintf("%.2f", pause_sum / pause_n) : "-"),
        (gc_n ? sprintf("%d", gc) : "-"),
        (dlq_n ? sprintf("%d", dlq) : "-"),
        (skipped_n ? sprintf("%d", skipped) : "-"),
        (tasks != "" ? tasks : "-")
    }'
}

# fully managed connectors, for playground connector benchmark: no JMX, the records of a source are counted from the end
# offsets of its topics, read with kcat in one container started for the whole benchmark ('playground topic
# get-number-records' reads each topic from the beginning on ccloud, far too slow for a sample every few seconds)
BENCHMARK_CCLOUD_KCAT_CONTAINER="benchmark_kcat_$$"
function benchmark_ccloud_kcat_start () {
  if [ ! -f "$root_folder/.ccloud/librdkafka.delta" ]
  then
    logerror "❌ $root_folder/.ccloud/librdkafka.delta has not been generated"
    return 1
  fi
  tr -d '"' < "$root_folder/.ccloud/librdkafka.delta" | grep -v "basic.auth.user.info" > "$root_folder/.ccloud/librdkafka_benchmark.delta"
  docker run -d --rm --name "$BENCHMARK_CCLOUD_KCAT_CONTAINER" --network=host \
    -v "$root_folder/.ccloud/librdkafka_benchmark.delta:/tmp/configuration/ccloud.properties" \
    --entrypoint tail confluentinc/cp-kcat:latest -f /dev/null > /dev/null 2>&1
}

function benchmark_ccloud_kcat_stop () {
  docker rm -f "$BENCHMARK_CCLOUD_KCAT_CONTAINER" > /dev/null 2>&1 || true
}

# topics of the ccloud cluster (internal ones excluded), one per line
function benchmark_ccloud_topic_list () {
  docker exec "$BENCHMARK_CCLOUD_KCAT_CONTAINER" kcat -F /tmp/configuration/ccloud.properties -L -J 2> /dev/null \
    | jq -r '.topics[].topic | select(startswith("_") | not)' 2> /dev/null
}

# "<topic> <sum of the end offsets of its partitions>" lines for <topics>, 0 for a topic that does not exist (yet). Offsets
# overcount the records of a transactional producer (one commit marker per transaction and partition): fine for the
# difference over a drain of non transactional sources
# fails (nothing printed) when the metadata or the offsets cannot be read: a sample must not count 0 records then
function benchmark_ccloud_topic_end_offsets () {
  local metadata topic query_args=()
  metadata=$(docker exec "$BENCHMARK_CCLOUD_KCAT_CONTAINER" kcat -F /tmp/configuration/ccloud.properties -L -J 2> /dev/null) || return 1
  echo "$metadata" | jq -e '.topics' > /dev/null 2>&1 || return 1
  for topic in "$@"
  do
    while read -r partition
    do
      [ -n "$partition" ] && query_args+=(-t "$topic:$partition:-1")
    done <<< "$(echo "$metadata" | jq -r --arg t "$topic" '.topics[]? | select(.topic == $t) | .partitions[].partition' 2> /dev/null)"
  done
  local offsets='{}'
  if [ ${#query_args[@]} -gt 0 ]
  then
    offsets=$(docker exec "$BENCHMARK_CCLOUD_KCAT_CONTAINER" kcat -F /tmp/configuration/ccloud.properties -Q -J "${query_args[@]}" 2> /dev/null) || return 1
    echo "$offsets" | jq -e 'type == "object"' > /dev/null 2>&1 || return 1
  fi
  local lines="" count
  for topic in "$@"
  do
    count=$(echo "$offsets" | jq -r --arg t "$topic" '[.[$t] // {} | to_entries[] | .value.offset? // empty | select(. >= 0)] | add // 0' 2> /dev/null) || return 1
    lines="$lines$topic $count"$'\n'
  done
  printf '%s' "$lines"
}

# fully managed sink, for playground connector benchmark: the records are counted from the committed offsets of its consumer
# group (connect-<lcc id>), read with kafka-consumer-groups in one container started for the whole benchmark
BENCHMARK_CCLOUD_GROUPS_CONTAINER="benchmark_groups_$$"
function benchmark_ccloud_groups_start () {
  get_kafka_docker_playground_dir
  if [ ! -f "$KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/env.delta" ] || [ ! -f "$KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta" ]
  then
    logerror "❌ $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/env.delta or ak-tools-ccloud.delta has not been generated"
    return 1
  fi
  source "$KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/env.delta"
  get_connect_image
  docker run -d --rm --name "$BENCHMARK_CCLOUD_GROUPS_CONTAINER" \
    -v "$KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta:/tmp/configuration/ccloud.properties" \
    -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SASL_JAAS_CONFIG="$SASL_JAAS_CONFIG" \
    --entrypoint tail "${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG}" -f /dev/null > /dev/null 2>&1
}

function benchmark_ccloud_groups_stop () {
  docker rm -f "$BENCHMARK_CCLOUD_GROUPS_CONTAINER" > /dev/null 2>&1 || true
}

# "<sum of the committed offsets> <max lag>" of consumer group <group> ("0 -" when it has no committed offset yet). Fails
# (nothing printed) when the group could not be described: a sample must not count 0 records then
function benchmark_ccloud_group_offsets () {
  local group="$1" output
  output=$(docker exec "$BENCHMARK_CCLOUD_GROUPS_CONTAINER" bash -c "kafka-consumer-groups --bootstrap-server \$BOOTSTRAP_SERVERS --command-config /tmp/configuration/ccloud.properties --group '$group' --describe 2>&1")
  # a group that does not exist yet (a sink that never committed) has no committed offset: not a failed read
  if echo "$output" | grep -q "does not exist"
  then
    echo "0 -"
    return 0
  fi
  # the header of the table is printed when the group was described
  echo "$output" | grep -q "CURRENT-OFFSET" || return 1
  echo "$output" | awk '$4 ~ /^[0-9]+$/ { committed += $4; if ($6 ~ /^[0-9]+$/ && $6 > lag) lag = $6; n++ } END { printf "%d %s\n", committed, (n ? lag + 0 : "-") }'
}

# Confluent Cloud Metrics API, for playground connector benchmark: "<epoch> <value>" lines of
# io.confluent.kafka.connect/<metric> for connector <lcc id>, one point per minute from <from epoch> to <to epoch>. A point
# is published about 30s into its minute and never updated; a deleted connector is not authorized (no line)
function benchmark_ccloud_metric () {
  local metric="$1" id="$2" from="$3" to="$4" interval
  interval="$(benchmark_iso_minute "$from")/$(benchmark_iso_minute "$to")"
  curl -s -m 30 -u "$CONFLUENT_CLOUD_API_KEY:$CONFLUENT_CLOUD_API_SECRET" -H 'Content-Type: application/json' \
    https://api.telemetry.confluent.cloud/v2/metrics/cloud/query \
    -d "$(jq -n -c --arg m "io.confluent.kafka.connect/$metric" --arg id "$id" --arg i "$interval" \
      '{aggregations: [{metric: $m}], filter: {field: "resource.connector.id", op: "EQ", value: $id}, granularity: "PT1M", intervals: [$i]}')" \
    | jq -r '.data[]? | select(.value != "NaN") | "\(.timestamp | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) \(.value)"' 2> /dev/null
}

# <epoch> as the ISO 8601 date of its minute, e.g. 2026-10-19T10:37:00Z
function benchmark_iso_minute () {
  local epoch="${1%.*}"
  date -u -r "$epoch" +%Y-%m-%dT%H:%M:00Z 2> /dev/null || date -u -d "@$epoch" +%Y-%m-%dT%H:%M:00Z
}

# topics written by a fully managed source (the ccloud connect api has no /topics endpoint), one per line: the topics of
# its config (kafka.topic, topics...), the existing topics starting with its topic.prefix (or database.server.name), and
# the topics consumed by the example script (a topic name template like table.topic.name.template of oracle cdc).
# Needs benchmark_ccloud_kcat_start
function benchmark_fully_managed_source_topics () {
  local connector_config_json="$1" test_file="$2" explicit prefixes topics prefix
  explicit=$(echo "$connector_config_json" | jq -r '[."kafka.topic", ."kafka.topics", .topics, .topic, ."redo.log.topic.name"] | map(select(. != null and . != "")) | join(",") | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(. != "" and (test("\\$\\{") | not))) | .[]' 2> /dev/null)
  prefixes=$(echo "$connector_config_json" | jq -r '[."topic.prefix", ."database.server.name"] | map(select(. != null and . != "")) | .[]' 2> /dev/null)
  topics="$explicit"
  if [ -n "$prefixes" ]
  then
    local all_topics
    all_topics=$(benchmark_ccloud_topic_list)
    for prefix in $prefixes
    do
      topics="$topics"$'\n'"$(echo "$all_topics" | awk -v p="$prefix" 'index($0, p) == 1')"
    done
  fi
  if [ -n "$test_file" ] && [ -f "$test_file" ]
  then
    # literal --topic of the 'playground topic consume' commands of the example, before the exit 0 of a repro model
    topics="$topics"$'\n'$(sed '/^exit 0/q' "$test_file" | grep -E '^[[:space:]]*playground topic consume' | sed -n -E 's/.*--topic[ =]+"?([A-Za-z0-9._-]+)"?( |$).*/\1/p')
  fi
  echo "$topics" | grep . | sort -u
}

# load of a sink for 'playground connector benchmark': replays the 'playground topic produce' of the example script
# that feeds one of <topics>, with --nb-messages <nb>, from the example directory. With <stream> set, batches of <nb>
# records are produced until the file $BENCHMARK_STOP_FILE exists (killing the producer in the middle of a batch
# would send a truncated line as a record), each followed by a BENCHMARK_BATCH=<nb> <epoch> line.
# Writes the replay script to <output>. Returns 1 when the example has no produce command, 3 when the command uses
# variables that are not set in this shell (the message lists them)
function benchmark_produce_load_from_example () {
  local test_file="$1" topics="$2" nb="$3" record_size="$4" output="$5" stream="$6"
  python3 -I - "$test_file" "$topics" "$nb" "$record_size" "$output" "$root_folder" "$stream" << 'PYEOF'
import os, re, shlex, sys
test_file, topics, nb, record_size, output, root, stream = sys.argv[1:8]
topics = topics.split()
lines = open(test_file, errors="ignore").read().split("\n")
blocks = []
i = 0
while i < len(lines):
    line = lines[i]
    if re.match(r"^exit 0\s*$", line):
        break
    if re.match(r"^\s*playground topic produce\b", line):
        start = i
        block = [line]
        m = re.search(r"<<-?\s*(['\"]?)([A-Za-z_]+)\1", line)
        quoted = bool(m and m.group(1))
        if m:
            terminator = m.group(2)
            i += 1
            while i < len(lines) and lines[i].strip() != terminator:
                block.append(lines[i])
                i += 1
            block.append(terminator)
        blocks.append((block, quoted, start))
    i += 1
if not blocks:
    sys.exit(1)

topic_re = r"(?:-t|--topic)(?:\s+|=)(\"[^\"]*\"|'[^']*'|\S+)"
def topic_of(block):
    m = re.search(topic_re, block[0])
    return m.group(1).strip("\"'") if m else ""

chosen = None
for block, quoted, start in blocks:
    if topic_of(block) in topics:
        chosen, topic = (block, quoted, start), topic_of(block)
        break
if chosen is None:
    for block, quoted, start in blocks:
        if "$" in topic_of(block):
            chosen, topic = (block, quoted, start), topics[0]
            break
if chosen is None:
    sys.exit(1)

(block, quoted, start) = chosen
first = block[0]
first = re.sub(topic_re, "--topic " + shlex.quote(topic), first, count=1)
first = re.sub(r"\s--nb-messages(?:\s+|=)(\$\([^)]*\)|\"[^\"]*\"|'[^']*'|\S+)", "", first)
extra = " --nb-messages %s" % nb
if record_size != "0" and "--record-size" not in first:
    extra += " --record-size %s" % record_size
first = re.sub(r"playground topic produce", "playground topic produce" + extra, first, count=1)
block = [first] + block[1:]

# variables still used by the command (and by the heredoc when it is not quoted) must be set
checked = first.split("<<")[0] + ("" if quoted else "\n".join(block[1:]))
known = {"DIR", "PWD", "root_folder", "HOME", "USER", "RANDOM"}
def unset_vars(text, assigned):
    return sorted({v for v in re.findall(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)", text) if v not in known and v not in assigned and not os.environ.get(v)})
# variables computed by the script before the produce (TIMESTAMP=$(date +%s)...): replay their last assignment
assignments = []
assigned = set()
for v in unset_vars(checked, assigned):
    for line in reversed(lines[:start]):
        if re.match(r"^\s*%s=" % v, line):
            assignments.append(line.strip())
            assigned.add(v)
            break
missing = unset_vars(checked + "\n" + "\n".join(assignments), assigned)
if missing:
    print("variables used by the produce command of %s are not set: %s" % (os.path.basename(test_file), " ".join(missing)))
    sys.exit(3)

example_dir = os.path.dirname(test_file)
with open(output, "w") as f:
    f.write("#!/bin/bash\n# replay of the 'playground topic produce' of %s, generated by 'playground connector benchmark'\nset -e\n" % test_file)
    f.write("source %s\n" % shlex.quote(os.path.join(root, "scripts/cli/src/lib/utils_function.sh")))
    f.write("DIR=%s\ncd \"$DIR\"\n" % shlex.quote(example_dir))
    for a in assignments:
        f.write(a + "\n")
    if stream:
        f.write("while [ ! -f \"$BENCHMARK_STOP_FILE\" ]\ndo\n")
        f.write("\n".join(block) + "\n")
        f.write("echo \"BENCHMARK_BATCH=%s $(date +%%s)\"\ndone\n" % nb)
    else:
        f.write("\n".join(block) + "\n")
        f.write("echo \"BENCHMARK_RECORDS=%s\"\n" % nb)
print(topic)
PYEOF
}

# setup on which a 'playground connector benchmark' ran, as one json object: host, container engine, connect worker,
# kafka, connector (config with secrets masked) and playground version, so that results are only compared on the same setup
#   benchmark_collect_setup <workers ("container port" lines)> <connector config json> <test file> <environment>
function benchmark_collect_setup () {
  local workers="$1" connector_config_json="$2" test_file="$3" environment="$4" fully_managed="$5"
  local host_os host_arch cpu_model host_cpus host_memory engine engine_info first_worker image image_arch emulated heap heap_max jvm_version jvm_cpus nb_workers nb_brokers kraft commit dirty
  host_arch=$(uname -m)
  if [ "$(uname -s)" == "Darwin" ]
  then
    host_os="macOS $(sw_vers -productVersion 2>/dev/null)"
    cpu_model=$(sysctl -n machdep.cpu.brand_string 2>/dev/null)
    host_cpus=$(sysctl -n hw.ncpu 2>/dev/null)
    host_memory=$(sysctl -n hw.memsize 2>/dev/null)
  else
    host_os=$(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME")
    cpu_model=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^ *//')
    host_cpus=$(nproc 2>/dev/null)
    host_memory=$(( $(awk '/MemTotal/ { print $2 }' /proc/meminfo 2>/dev/null || echo 0) * 1024 ))
  fi
  engine="docker"
  container_engine_is_podman && engine="podman"
  # no playground command gives the engine resources and the image architecture
  engine_info=$(docker info --format '{{.ServerVersion}}|{{.OperatingSystem}}|{{.NCPU}}|{{.MemTotal}}' 2>/dev/null)
  first_worker=$(echo "$workers" | head -1 | awk '{ print $1 }')
  # a fully managed connector has no worker on this machine
  if [ -n "$fully_managed" ]
  then
    first_worker=""
  fi
  image=$(docker inspect -f '{{.Config.Image}}' "$first_worker" 2>/dev/null)
  image_arch=$(docker image inspect -f '{{.Architecture}}' "$image" 2>/dev/null)
  emulated=false
  case "$host_arch:$image_arch" in
    arm64:amd64|aarch64:amd64|x86_64:arm64|x86_64:aarch64) emulated=true ;;
  esac
  local jvm=""
  if [ -n "$first_worker" ]
  then
    heap=$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$first_worker" 2>/dev/null | sed -n 's/^KAFKA_HEAP_OPTS=//p' | head -1)
    jvm=$(printf 'get -b java.lang:type=Runtime VmVersion\nget -b java.lang:type=OperatingSystem AvailableProcessors\nget -b java.lang:type=Memory HeapMemoryUsage\nexit\n' | benchmark_jmxterm "$first_worker" "$(echo "$workers" | head -1 | awk '{ print $2 }')")
  fi
  jvm_version=$(echo "$jvm" | sed -n 's/^VmVersion = \(.*\);$/\1/p')
  jvm_cpus=$(echo "$jvm" | sed -n 's/^AvailableProcessors = \(.*\);$/\1/p')
  # HeapMemoryUsage is a composite value: { committed = ...; init = ...; max = <bytes>; used = ...; }
  heap_max=$(echo "$jvm" | sed -n 's/^ *max = \([0-9]*\);$/\1/p' | head -1)
  nb_workers=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -c -E '^connect[0-9]*$' || true)
  nb_brokers=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -c -E '^broker[0-9]*$' || true)
  # the local containers have nothing to do with a fully managed connector
  if [ -n "$fully_managed" ]
  then
    nb_workers=0
    nb_brokers=0
  fi
  kraft=false
  docker ps --format '{{.Names}}' 2>/dev/null | grep -q -E '^controller[0-9]*$' && kraft=true
  commit=$(git -C "$root_folder" rev-parse --short HEAD 2>/dev/null)
  dirty=false
  [ -n "$(git -C "$root_folder" status --porcelain -uno 2>/dev/null)" ] && dirty=true
  # documentation of the connector: documentation_url of the manifest of the plugin that contains the connector class
  # (and source_url, for the links of the flight recorder hot methods)
  local connector_class documentation_url="" source_url="" plugin_dir manifest
  connector_class=$(echo "$connector_config_json" | jq -r '."connector.class" // empty' 2> /dev/null)
  if [ -n "$connector_class" ] && [ -n "$first_worker" ]
  then
    plugin_dir=$(playground --output-level ERROR container exec --container "$first_worker" --command "for d in /usr/share/confluent-hub-components/* /usr/share/java/*; do [ -f \"\$d/manifest.json\" ] && grep -rlq --include='*.jar' '${connector_class//.//}.class' \"\$d\" && echo \"\$d\" && break; done" 2> /dev/null | tail -1)
    if [ -n "$plugin_dir" ]
    then
      manifest=$(playground --output-level ERROR container exec --container "$first_worker" --command "cat '$plugin_dir/manifest.json'" 2> /dev/null)
      documentation_url=$(echo "$manifest" | jq -r '.documentation_url // empty' 2> /dev/null)
      source_url=$(echo "$manifest" | jq -r '.source_url // empty' 2> /dev/null)
    fi
  fi
  # github link of the example: repro models are in the reproduction-models submodule, another repository
  local repo_dir="$root_folder" repo_path repo_url repo_commit repo_dirty=false
  repo_path="${test_file#$root_folder/}"
  if [[ "$repo_path" == reproduction-models/* ]]
  then
    repo_dir="$root_folder/reproduction-models"
    repo_path="${repo_path#reproduction-models/}"
  fi
  repo_url=$(git -C "$repo_dir" config --get remote.origin.url 2>/dev/null | sed -E 's#^git@github.com:#https://github.com/#; s#\.git$##')
  repo_commit=$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null)
  [ -n "$(git -C "$repo_dir" status --porcelain -uno 2>/dev/null)" ] && repo_dirty=true
  jq -n \
    --arg host_os "$host_os" --arg host_arch "$host_arch" --arg cpu_model "$cpu_model" --arg host_cpus "$host_cpus" --arg host_memory "$host_memory" \
    --arg engine "$engine" --arg engine_info "$engine_info" \
    --arg image "$image" --arg image_arch "$image_arch" --argjson emulated "$emulated" --arg heap "$heap" --arg heap_max "$heap_max" --arg jvm_version "$jvm_version" --arg jvm_cpus "$jvm_cpus" \
    --arg nb_workers "$nb_workers" --arg nb_brokers "$nb_brokers" --argjson kraft "$kraft" --arg environment "$environment" --argjson fully_managed "$([ -n "$fully_managed" ] && echo true || echo false)" \
    --arg test_file "${test_file#$root_folder/}" --arg commit "$commit" --argjson dirty "$dirty" \
    --arg repo_url "$repo_url" --arg repo_path "$repo_path" --arg repo_commit "$repo_commit" --argjson repo_dirty "$repo_dirty" \
    --arg documentation_url "$documentation_url" --arg source_url "$source_url" --arg plugin_dir "$plugin_dir" \
    --argjson config "$(echo "$connector_config_json" | jq -c 'with_entries(if (.key | test("password|secret|token|credentials|jaas|private\\.key|api\\.key|apikey"; "i")) then .value = "****" else . end)' 2>/dev/null || echo '{}')" \
    '($engine_info | split("|")) as $e |
     {host: {os: $host_os, arch: $host_arch, cpu_model: $cpu_model, cpus: ($host_cpus | tonumber? // null), memory_bytes: ($host_memory | tonumber? // null)},
      engine: {name: $engine, version: $e[0], os: $e[1], cpus: ($e[2] | tonumber? // null), memory_bytes: ($e[3] | tonumber? // null)},
      connect: {fully_managed: $fully_managed, image: $image, image_arch: $image_arch, emulated: $emulated, heap_opts: $heap, heap_max_bytes: ($heap_max | tonumber? // null), jvm_version: $jvm_version, jvm_cpus: ($jvm_cpus | tonumber? // null), workers: ($nb_workers | tonumber? // null)},
      kafka: {environment: $environment, brokers: ($nb_brokers | tonumber? // null), kraft: $kraft},
      playground: {test_file: $test_file, commit: $commit, dirty: $dirty,
                   repo_url: $repo_url, repo_path: $repo_path, repo_commit: $repo_commit, repo_dirty: $repo_dirty},
      connector: {documentation_url: $documentation_url, source_url: $source_url, plugin_dir: $plugin_dir},
      connector_config: $config}'
}

# one line summary of a setup json, e.g. "macOS 27.0.1 arm64, Apple M5 Max (18 cpus, 36 GiB) · docker 29.8.2 Docker Desktop (18 cpus, 23 GiB) · ..."
function benchmark_setup_summary () {
  echo "$1" | jq -r '
    def gib: if . == null then "?" else ((. / 1073741824) | floor | tostring) + " GiB" end;
    "\(.host.os) \(.host.arch), \(.host.cpu_model) (\(.host.cpus) cpus, \(.host.memory_bytes | gib)) · \(.engine.name) \(.engine.version) \(.engine.os) (\(.engine.cpus) cpus, \(.engine.memory_bytes | gib)) · " +
    if .connect.fully_managed then "fully managed connector, Confluent Cloud" else "connect \(.connect.image | split("/") | last)\(if .connect.emulated then " EMULATED" else "" end), \(.connect.workers) worker(s), jvm \(.connect.jvm_version), heap \(.connect.heap_max_bytes | gib) max\(if .connect.heap_opts == "" then "" else " (" + .connect.heap_opts + ")" end) · \(.kafka.brokers) broker(s), \(.kafka.environment)" end' 2>/dev/null
}

# differences between two setups on what changes the throughput (host, engine resources, connect image and jvm, heap,
# brokers), empty when they are the same
function benchmark_setup_differences () {
  local current="$1" previous="$2"
  jq -n -r --argjson c "$current" --argjson p "$previous" '
    [ ["host cpu", $c.host.cpu_model, $p.host.cpu_model], ["host cpus", $c.host.cpus, $p.host.cpus],
      ["engine cpus", $c.engine.cpus, $p.engine.cpus], ["engine memory", $c.engine.memory_bytes, $p.engine.memory_bytes],
      ["connect image", $c.connect.image, $p.connect.image], ["emulated", $c.connect.emulated, $p.connect.emulated],
      ["heap max", $c.connect.heap_max_bytes, $p.connect.heap_max_bytes], ["connect workers", $c.connect.workers, $p.connect.workers],
      ["brokers", $c.kafka.brokers, $p.kafka.brokers], ["environment", $c.kafka.environment, $p.kafka.environment] ]
    | map(select(.[1] != .[2])) | map("\(.[0]) \(.[2]) -> \(.[1])") | join(", ")' 2>/dev/null
}

# value of 'playground update-version --connector-tag' that puts the plugin of <connector class> at <version> and keeps
# the other confluent hub plugins of the example at their current version (one version per plugin, in the order of
# CONNECT_PLUGIN_PATH, like update-version expects). Needs $test_file. Prints nothing when the plugin is not found
function benchmark_connector_tag_value () {
  local connector_class="$1" version="$2"
  local class_path="${connector_class//.//}.class" value="" found=0 connector_path full_name owner name current
  get_connector_paths
  for connector_path in ${connector_paths//,/ }
  do
    full_name=$(basename "$connector_path")
    owner=$(echo "$full_name" | cut -d'-' -f1)
    name=$(echo "$full_name" | cut -d'-' -f2-)
    # same plugins as update-version: the ones coming from confluent hub
    if [ "$owner" == "java" ] || [ "$name" == "hub-components" ] || [ "$owner" == "filestream" ]
    then
      continue
    fi
    # the jar names of a zip are stored uncompressed: grep finds the class in the jars of the plugin
    if playground --output-level ERROR container exec --container connect --command "grep -rlq --include='*.jar' '$class_path' '$connector_path'" > /dev/null 2>&1
    then
      current="$version"
      found=1
    else
      current=$(playground --output-level ERROR container exec --container connect --command "cat '$connector_path/manifest.json'" 2> /dev/null | jq -r '.version // empty' 2> /dev/null)
    fi
    value="${value:+$value,}$current"
  done
  [ $found -eq 1 ] && echo "$value"
}

# version of the plugin of <connector class> in the connect worker (connect REST API /connector-plugins), "unknown" when
# not found; <empty> to print nothing instead of unknown
function benchmark_plugin_version () {
  local connector_class="$1" fallback="${2-unknown}"
  get_connect_url_and_security
  # the errors of the helper go to stderr, not into the version
  handle_onprem_connect_rest_api "curl -s $security \"$connect_url/connector-plugins\"" >&2 || return 1
  echo "$curl_output" | jq -r --arg c "$connector_class" --arg f "$fallback" '[.[] | select(.class == $c) | .version][0] // $f'
}

# opens the html report of playground connector benchmark in a browser: only in an interactive terminal, never in CI nor
# for the child runs of a comparison (BENCHMARK_NO_OPEN)
function benchmark_open_report () {
  local html_file="$1"
  if { [[ -t 1 ]] || [ -n "${PLAYGROUND_RUN_LOG_TERMINAL:-}" ]; } && [ -z "$GITHUB_RUN_NUMBER" ] && [ -z "$BENCHMARK_NO_OPEN" ]
  then
    if command -v open > /dev/null 2>&1
    then
      open "$html_file"
    elif command -v xdg-open > /dev/null 2>&1
    then
      xdg-open "$html_file" > /dev/null 2>&1 || true
    fi
  fi
}

# "<mean> <sample stddev> <coefficient of variation in %>" of the numbers on stdin, one per line ("- - -" without any, a
# stddev and cv of "-" with only one)
function benchmark_stats () {
  awk 'NF { v[n++] = $1; s += $1 }
    END {
      if (n == 0) { print "- - -"; exit }
      m = s / n
      if (n < 2) { printf "%.1f - -\n", m; exit }
      for (i = 0; i < n; i++) d += (v[i] - m) ^ 2
      sd = sqrt(d / (n - 1))
      printf "%.1f %.1f %s\n", m, sd, (m > 0 ? sprintf("%.1f", sd / m * 100) : "-")
    }'
}

# ---- playground connector smt test ------------------------------------------------------------------------------

SMT_TESTER_CACHE="$HOME/.playground-smt-tester"

# java release to compile the harness for a jvm: 8, 11 or 17 (the harness is compiled with a jdk 17)
function smt_tester_java_release () {
  local version_line="$1" major
  major=$(echo "$version_line" | sed -E 's/.*version "([0-9]+)(\.([0-9]+))?.*/\1 \3/')
  set -- $major
  if [ "$1" == "1" ]
  then
    major="$2"
  else
    major="$1"
  fi
  if [ "${major:-17}" -ge 17 ]
  then
    echo 17
  elif [ "$major" -ge 11 ]
  then
    echo 11
  else
    echo 8
  fi
}

# compiled SmtTester for the kafka jars of <jar dir> and a java <release>, cached: prints the classes folder
function smt_tester_classes () {
  local jar_dir="$1" release="$2" key source_file="$root_folder/tools/smt-tester/SmtTester.java" classes
  key="$(basename "$jar_dir")-$release-$(shasum "$source_file" | cut -c1-10)"
  classes="$SMT_TESTER_CACHE/classes/$key"
  if [ ! -f "$classes/SmtTester.class" ]
  then
    mkdir -p "$classes" "$SMT_TESTER_CACHE/src"
    cp "$source_file" "$SMT_TESTER_CACHE/src/SmtTester.java"
    # compiled in a jdk container: the connect images have no compiler
    if ! docker run --rm -v "$jar_dir:/jars" -v "$SMT_TESTER_CACHE/src:/src" -v "$classes:/out" eclipse-temurin:17-jdk javac --release "$release" -cp "/jars/*" -d /out /src/SmtTester.java > "$SMT_TESTER_CACHE/compile.log" 2>&1
    then
      logerror "❌ could not compile the smt tester, see $SMT_TESTER_CACHE/compile.log"
      rm -rf "$classes"
      return 1
    fi
  fi
  echo "$classes"
}

# kafka jars of the running connect worker (the jars of the image are symlinks: copied with cp -L in the container),
# cached by image id: prints the folder
function smt_tester_jars_from_container () {
  local container="$1" image_id dir
  image_id=$(docker inspect -f '{{.Image}}' "$container" 2> /dev/null | sed 's/sha256://' | cut -c1-12)
  dir="$SMT_TESTER_CACHE/jars/$image_id"
  if [ ! -d "$dir" ] || [ -z "$(ls "$dir" 2> /dev/null)" ]
  then
    rm -rf "$dir"
    mkdir -p "$SMT_TESTER_CACHE/jars"
    playground --output-level ERROR container exec --container "$container" --command "rm -rf /tmp/smt-tester-jars && mkdir -p /tmp/smt-tester-jars && cp -L /usr/share/java/kafka/*.jar /tmp/smt-tester-jars/" > /dev/null 2>&1
    playground --output-level ERROR container cp --source "$container:/tmp/smt-tester-jars" --destination "$dir" > /dev/null 2>&1
  fi
  echo "$dir"
}

# kafka jars of a cp-server-connect image, cached by image id: prints the folder
function smt_tester_jars_from_image () {
  local image="$1" image_id dir name
  docker image inspect "$image" > /dev/null 2>&1 || docker pull -q "$image" > /dev/null 2>&1 || { logerror "❌ could not pull $image"; return 1; }
  image_id=$(docker image inspect -f '{{.Id}}' "$image" | sed 's/sha256://' | cut -c1-12)
  dir="$SMT_TESTER_CACHE/jars/$image_id"
  if [ ! -d "$dir" ] || [ -z "$(ls "$dir" 2> /dev/null)" ]
  then
    rm -rf "$dir"
    mkdir -p "$SMT_TESTER_CACHE/jars"
    name="pg-smt-tester-jars-$$"
    docker run --name "$name" --entrypoint sh "$image" -c "mkdir -p /tmp/smt-tester-jars && cp -L /usr/share/java/kafka/*.jar /tmp/smt-tester-jars/" > /dev/null 2>&1
    docker cp "$name:/tmp/smt-tester-jars" "$dir" > /dev/null 2>&1
    docker rm -f "$name" > /dev/null 2>&1
  fi
  echo "$dir"
}

# confluent hub plugin installed for the smt test only, cached: prints the plugin folder
#   smt_tester_hub_plugin <owner/name:version> <connect image to run the confluent hub client>
function smt_tester_hub_plugin () {
  local spec="$1" image="$2" owner_name version dir
  owner_name="${spec%%:*}"
  version="${spec#*:}"
  [ "$version" == "$spec" ] && version="latest"
  dir="$SMT_TESTER_CACHE/plugins/${owner_name//\//-}-$version"
  if [ -z "$(ls -d "$dir"/*/ 2> /dev/null)" ]
  then
    mkdir -p "$dir"
    # same way as the examples install their connectors (scripts/utils.sh)
    if ! docker run -u0 --rm -v "$dir:/usr/share/confluent-hub-components" "$image" bash -c "confluent-hub install --no-prompt $owner_name:$version && chown -R $(id -u):$(id -g) /usr/share/confluent-hub-components" > "$dir.log" 2>&1
    then
      logerror "❌ could not install $spec from confluent hub, see $dir.log"
      rm -rf "$dir"
      return 1
    fi
  fi
  ls -d "$dir"/*/ | head -1 | sed 's#/$##'
}

# config of a running connector as a JSON object in $curl_output (REST API /config endpoint, or the Connector CR on cfk)
# returns 1 if it could not be read (the REST helpers log the error: called in an 'if', set -e does not stop on it)
function get_connector_config_json () {
  local connector="$1" connector_type env_used
  connector_type=$(playground state get run.connector_type)
  env_used=$(playground state get run.environment)
  curl_output=""
  if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
  then
    get_ccloud_connect
    handle_ccloud_connect_rest_api "curl $security -s -X GET -H \"Content-Type: application/json\" \"https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector/config\" --header \"authorization: Basic $authorization\"" || return 1
  elif [[ "$env_used" == cfk* ]]
  then
    # connector.class and tasks.max are not in spec.configs: they are spec.class and spec.taskMax of the CR
    curl_output=$(kubectl -n confluent get connector "$connector" -o json 2>/dev/null | jq -c 'select(.spec != null) | (.spec.configs // {}) + {"connector.class": .spec.class, "tasks.max": (.spec.taskMax // 1 | tostring)}' 2>/dev/null)
  else
    get_connect_url_and_security
    handle_onprem_connect_rest_api "curl $security -s -X GET -H \"Content-Type: application/json\" \"$connect_url/connectors/$connector/config\"" || return 1
  fi
  if [ -z "$curl_output" ] || ! echo "$curl_output" | jq -e 'type == "object"' > /dev/null 2>&1
  then
    return 1
  fi
}

# validate a connector config with the connector-plugins/<class>/config/validate endpoint (self managed or Confluent
# Cloud), as 'connector create-or-update --validate' and 'connector validate' do:
#   validate_connector_config <connector> <json content> <tmp dir> <environment> <is_cfk> <skip_automatic_connector_config|running>
# returns 0 if valid, 1 if not (errors logged), 2 if skipped (cfk: no connect REST validation endpoint)
function validate_connector_config () {
  local connector="$1" json_content="$2" tmp_dir="$3" env_used="$4" is_cfk="$5" skip_automatic="$6"
  local connector_type connector_class json_file="$tmp_dir/validate_connector.json" json_validate_file="$tmp_dir/json_validate_file"
  connector_type=$(playground state get run.connector_type)
  connector_class=$(echo "$json_content" | jq -r '."connector.class"')
  if [[ "$connector_class" == "null" ]] || [[ -z "$connector_class" ]]
  then
    logerror "❌ connector.class is required"
    return 1
  fi
  echo "$json_content" > "$json_file"

  set +e
  if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
  then
    get_ccloud_connect
    handle_ccloud_connect_rest_api "curl $security -s -X PUT -H \"Content-Type: application/json\" -H \"authorization: Basic $authorization\" --data @$json_file https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connector-plugins/$connector_class/config/validate"
  elif [[ "$is_cfk" -eq 1 ]]
  then
    logwarn "⚠️ validation with CFK currently performs basic checks only (no Connect REST validation endpoint)"
    log "✅ Basic CFK validation passed"
    set -e
    return 2
  else
    get_connect_url_and_security
    if [[ -n "$skip_automatic" ]]
    then
      # "running": the config of a running connector, it already has the automatic config
      [ "$skip_automatic" != "running" ] && log "🤖 --skip-automatic-connector-config is set"
    else
      add_connector_config_based_on_environment "$env_used" "$json_content"
    fi
    # add mandatory name field
    echo "$json_content" | jq ". + {\"name\": \"$connector\"}" > "$json_file"
    handle_onprem_connect_rest_api "curl $security -s -X PUT -H \"Content-Type: application/json\" --data @$json_file $connect_url/connector-plugins/$connector_class/config/validate"
  fi
  set -e

  if ! echo "$curl_output" | jq -e .  > /dev/null 2>&1
  then
    set +e
    echo "$curl_output" > "$json_validate_file"
    jq_output=$(jq . "$json_validate_file" 2>&1)
    error_line=$(echo "$jq_output" | grep -oE 'parse error.*at line [0-9]+' | grep -oE '[0-9]+')

    if [[ -n "$error_line" ]]; then
      logerror "❌ Invalid JSON at line $error_line"
    fi
    set -e

    if [ -z "$GITHUB_RUN_NUMBER" ]
    then
      if [[ $(type -f bat 2>&1) =~ "not found" ]]
      then
        cat -n "$json_validate_file"
      else
        bat "$json_validate_file" --highlight-line $error_line
      fi
    fi
    return 1
  fi

  # Check if there were any errors
  has_errors=$(echo "$curl_output" | jq '.configs[] | select(.value.errors | length > 0) | length' | tr -d '\n')

  if [[ "$has_errors" -gt 0 ]]
  then
    output=$(echo "$curl_output" | jq -r '.configs[] | select(.value.errors | length > 0) | .value.name + " ->> " + (.value.errors | to_entries | map("\(.value|tostring)") | join(", "))')
    logerror "❌ Validation errors found in connector config\n$output"
    return 1
  fi
  log "✅ $connector_type connector config is valid !"
}

# content of stdin, or nothing when stdin is a terminal or nothing comes within 3 seconds: an agent or a CI job runs
# commands with a stdin that is neither a terminal nor closed, a plain cat would wait forever
function read_stdin_if_any () {
  [ -t 0 ] && return 0
  local first=""
  if IFS= read -r -t 3 first || [ -n "$first" ]
  then
    printf '%s\n' "$first"
    cat
  fi
}

DLQ_TOOL_CACHE="$HOME/.playground-dlq-tool"

# compiled tools/dlq-tool/DlqTool.java, cached by source hash: prints the classes folder
# compiled against kafka-clients 3.9 for java 8: it only uses consumer / producer apis that the kafka jars of any
# cp image (6.x to 8.x) have, so the same class runs in every container
function dlq_tool_classes () {
  local source_file="$root_folder/tools/dlq-tool/DlqTool.java" key classes jar="kafka-clients-3.9.1.jar"
  key=$(shasum "$source_file" | cut -c1-10)
  classes="$DLQ_TOOL_CACHE/classes/$key"
  if [ ! -f "$classes/DlqTool.class" ]
  then
    mkdir -p "$classes" "$DLQ_TOOL_CACHE/src"
    if [ ! -f "$DLQ_TOOL_CACHE/$jar" ]
    then
      curl -sSfL -o "$DLQ_TOOL_CACHE/$jar" "https://repo1.maven.org/maven2/org/apache/kafka/kafka-clients/3.9.1/$jar" || { logerror "❌ could not download $jar"; rm -f "$DLQ_TOOL_CACHE/$jar"; return 1; }
    fi
    cp "$source_file" "$DLQ_TOOL_CACHE/src/DlqTool.java"
    # compiled in a jdk container: the cp images have no compiler
    if ! docker run --rm -v "$DLQ_TOOL_CACHE:/w" -v "$classes:/out" eclipse-temurin:17-jdk javac --release 8 -cp "/w/$jar" -d /out /w/src/DlqTool.java > "$DLQ_TOOL_CACHE/compile.log" 2>&1
    then
      logerror "❌ could not compile the dlq tool, see $DLQ_TOOL_CACHE/compile.log"
      rm -rf "$classes"
      return 1
    fi
  fi
  echo "$classes"
}

# run a java class that uses the kafka clients (one .class file in <classes dir>) with kafka-run-class, in the same
# container and with the same bootstrap server and security config as run_kafka_admin_tool:
#   run_kafka_java_tool <classes dir> <class name> <args...>
# --bootstrap-server <servers> [--command-config <client properties>] are appended to the arguments
function run_kafka_java_tool () {
  local classes="$1" class="$2"
  shift 2
  local remote_dir="/tmp/playground-$(echo "$class" | tr '[:upper:]' '[:lower:]')"
  get_environment_used

  if [[ "$environment" == "ccloud" ]]
  then
    get_kafka_docker_playground_dir
    DELTA_CONFIGS_ENV=$KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/env.delta
    if [ -f $DELTA_CONFIGS_ENV ]
    then
      source $DELTA_CONFIGS_ENV
    else
      logerror "❌ $DELTA_CONFIGS_ENV has not been generated"
      exit 1
    fi
    if [[ -n "$verbose" ]]
    then
      log "🐞 command used"
      echo "$class $* --bootstrap-server $BOOTSTRAP_SERVERS --command-config /tmp/configuration/ccloud.properties"
    fi
    get_connect_image
    docker run --quiet --rm -v "$classes:$remote_dir" -e CLASSPATH="$remote_dir" -v $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta:/tmp/configuration/ccloud.properties ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} kafka-run-class "$class" "$@" --bootstrap-server $BOOTSTRAP_SERVERS --command-config /tmp/configuration/ccloud.properties
  else
    get_security_broker "--command-config"
    if [[ -n "$verbose" ]]
    then
      log "🐞 command used (in container $container)"
      echo "$class $* --bootstrap-server $bootstrap_server $security"
    fi
    if [[ "$environment" == cfk* ]]
    then
      kubectl -n confluent exec -i $container -- sh -c "mkdir -p $remote_dir && cat > $remote_dir/$class.class" < "$classes/$class.class"
      kubectl -n confluent exec -i $container -- env CLASSPATH="$remote_dir" kafka-run-class "$class" "$@" --bootstrap-server $bootstrap_server $security
    else
      docker exec -i $container sh -c "mkdir -p $remote_dir && cat > $remote_dir/$class.class" < "$classes/$class.class"
      docker exec -i -e CLASSPATH="$remote_dir" $container kafka-run-class "$class" "$@" --bootstrap-server $bootstrap_server $security
    fi
  fi
}

# dead letter queue topic of a sink connector: errors.deadletterqueue.topic.name, or dlq-<lcc id> for a fully
# managed connector (the config can use ${connector} as a placeholder for the lcc id). Prints nothing if there is none
function get_connector_dlq_topic () {
  local connector="$1" connector_type dlq lcc
  get_connector_config_json "$connector" || return 1
  connector_type=$(playground state get run.connector_type)
  dlq=$(echo "$curl_output" | jq -r '."errors.deadletterqueue.topic.name" // empty')
  if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
  then
    if [ -z "$dlq" ] || [[ "$dlq" == *'${connector}'* ]]
    then
      lcc=$(get_ccloud_connector_lcc "$connector" 2> /dev/null)
      [ -z "$lcc" ] && return 1
      dlq="${dlq:-dlq-\${connector\}}"
      dlq="${dlq//\$\{connector\}/$lcc}"
    fi
  fi
  echo "$dlq"
}

# dead letter queue topic of 'playground topic dlq' commands, in $dlq_topic: --topic, or the dlq of --connector, or
# the dlq of the only connector of the example that has one
function resolve_dlq_topic () {
  local topic="$1" connector="$2" c t
  dlq_topic="$topic"
  [ -n "$dlq_topic" ] && return 0
  if [ -n "$connector" ]
  then
    dlq_topic=$(get_connector_dlq_topic "$connector")
    if [ -z "$dlq_topic" ]
    then
      logerror "❌ connector $connector has no dead letter queue (errors.deadletterqueue.topic.name is not set), use --topic"
      exit 1
    fi
    return 0
  fi
  local found=()
  for c in $(playground get-connector-list 2> /dev/null)
  do
    t=$(get_connector_dlq_topic "$c")
    [ -n "$t" ] && found+=("$t")
  done
  if [ ${#found[@]} -eq 1 ]
  then
    dlq_topic="${found[0]}"
    log "✨ --topic was not provided, using the dead letter queue of the running connector: $dlq_topic"
  elif [ ${#found[@]} -gt 1 ]
  then
    logerror "❌ several connectors have a dead letter queue (${found[*]}), use --topic or --connector"
    exit 1
  else
    logerror "❌ no running connector has a dead letter queue (errors.deadletterqueue.topic.name), use --topic"
    exit 1
  fi
}

# filter (stdin to stdout) masking connector secrets in tool output before it is printed: the values of secret-looking
# keys, in json ("key": "value") and python dict ('key': 'value') form, plus each exact value given as argument
function redact_connector_secrets() {
  REDACT_VALUES="$(printf '%s\n' "$@")" perl -pe '
    BEGIN { @values = grep { length($_) >= 4 } split(/\n/, $ENV{REDACT_VALUES} // ""); }
    s/((["\x27])[^"\x27]*(?:password|secret|token|credentials|access\.key\.id|api\.key|apikey|sasl\.jaas\.config)[^"\x27]*\2\s*:\s*)(["\x27])(?:\\.|(?!\3).)*\3/$1$3********$3/gi;
    for my $v (@values) { s/\Q$v\E/********/g; }
  '
}

################################################################################
# 📄 run log: a masked copy of the output of 'playground run', to share with a colleague
################################################################################

function run_log_default_folder () {
  echo "/tmp/playground-run-logs"
}

# values to mask in a run log, one per line: the secret-looking variables exported for the example (loaded from
# 'playground secrets' by load_secrets_for_example), the secret-looking values of playground.ini (ccloud api keys),
# the values kept in clear in the secrets store (file backend: no keychain or 1Password prompt at the end of a run)
# and ~/.aws/credentials, which the aws examples read themselves.
# Doesn't depend on IFS: 'playground run' sets it to a space
function run_log_secret_values () {
  local name value profile_or_key
  while read -r name
  do
    # PWD / OLDPWD match *PWD* but hold the current folder
    if [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && [ "$name" != "PWD" ] && [ "$name" != "OLDPWD" ] && is_secret_env_var_name "$name"
    then
      printf '%s\n' "${!name}"
    fi
  done < <(compgen -e)
  if [ -f "$root_folder/playground.ini" ]
  then
    secret_store_dump "$root_folder/playground.ini" | while IFS=$'\t' read -r profile_or_key name value
    do
      if is_secret_env_var_name "${name^^}"
      then
        printf '%s\n' "$value"
      fi
    done
  fi
  secret_store_dump "$(get_secrets_file)" 2> /dev/null | while IFS=$'\t' read -r profile_or_key name value
  do
    if [ "$(secret_reference_backend "$value")" == "file" ]
    then
      printf '%s\n' "$value"
    fi
  done
  local aws_credentials_file="${AWS_SHARED_CREDENTIALS_FILE:-$HOME/.aws/credentials}"
  if [ -f "$aws_credentials_file" ]
  then
    awk '/^[ \t]*aws_(access_key_id|secret_access_key|session_token)[ \t]*=/ { v=substr($0, index($0, "=")+1); gsub(/^[ \t]+|[ \t]+$/, "", v); print v }' "$aws_credentials_file"
  fi
}

# filter (stdin to stdout) turning a raw terminal capture into a shareable text: terminal control sequences and
# carriage returns removed, the docker compose progress redrawn in place reduced to its last state, then secrets masked:
#   - each value of the file $1 (one per line, see run_log_secret_values), and each part of a key:secret value
#   - the value of secret-looking keys: "password": "x" (json, python dict), password=x (properties, jdbc urls,
#     jaas), password: x (yaml), except ${...} config provider references and keys naming something else than the
#     secret (oauth2.token.property, ssl.keystore.password.type...)
#   - well-known shapes: private key blocks, AWS access key ids, JWTs, Bearer / Basic tokens, user:password@ in urls,
#     GitHub, Slack and Google api keys
# the number of masked strings is printed on stderr
function run_log_mask () {
  RUN_LOG_VALUES_FILE="${1:-}" perl -e '
    my %skip = map { $_ => 1 } qw(confluent password passwd changeit changeme secret admin true false null none playground localhost default);
    my (%seen, @values);
    if ($ENV{RUN_LOG_VALUES_FILE} ne "" && open(my $f, "<", $ENV{RUN_LOG_VALUES_FILE})) {
      while (my $v = <$f>) {
        chomp $v;
        $v =~ s/\r//g;
        for my $c ($v, split(/:/, $v)) {
          $c =~ s/^\s+|\s+$//g;
          next if length($c) < 6 || $skip{lc $c} || $c =~ /^[0-9]+$/ || $seen{$c}++;
          push @values, $c;
        }
      }
      close $f;
    }
    @values = sort { length($b) <=> length($a) } @values;
    my $secret_key = qr/[\w.\-]*(?:password|passwd|secret|token|credentials?|apikey|api[_.\-]key|access[_.\-]key|session[_.\-]key|private[_.\-]key|sasl\.jaas\.config)[\w.\-]*/i;
    my ($n, $in_key) = (0, 0);
    # last segment of a secret-looking key that names something else than the secret: oauth2.token.property (a field
    # name), *.password.type, *.token.url...
    my $not_secret_key = qr/[._\-](?:property|type|path|location|url|endpoint|algorithm|mode|enabled|separator|format|header)["\x27]?\s*[:=]\s*$/i;
    # value of a secret-looking key: kept when it is not a secret (config provider reference, already masked, enum such
    # as USER_INFO, boolean, number), masked otherwise
    sub mask_value {
      my ($v, $k) = @_;
      (my $u = $v) =~ s/^["\x27]|["\x27]$//g;
      return $v if (defined $k && $k =~ $not_secret_key) || $u eq "" || $u =~ /^\$\{/ || $u =~ /^\*+$/ || $u =~ /^[A-Z_]+$/ || $u =~ /^(?:true|false|null|none)$/i || $u =~ /^[0-9]+$/;
      $n++;
      return $v =~ /^(["\x27])/ ? "$1********$1" : "********";
    }
    # docker compose redraws its progress block in place (cursor up): once the escapes are removed, every frame
    # stays, with blank lines. Kept: the last header ([+] up 9/9) and the last line of each container, network...
    my ($compose_verb, $compose_header, @compose_order, %compose_item);
    sub compose_flush {
      return unless defined $compose_verb;
      print $compose_header;
      print $compose_item{$_} for @compose_order;
      ($compose_verb, $compose_header, @compose_order, %compose_item) = ();
    }
    while (my $line = <STDIN>) {
      $line =~ s/\e\][^\a\e]*(?:\a|\e\\)//g;
      $line =~ s/\e\[[0-9;?]*[ -\/]*[@-~]//g;
      $line =~ s/\e[()][0-9A-Za-z]//g;
      $line =~ s/\e[=>78]//g;
      $line =~ s/\r+\n/\n/g;
      # a progress line redrawn in place: keep what was shown last
      $line =~ s/^.*\r//;
      $line =~ s/[\x00-\x08\x0b-\x1f\x7f]//g;
      if ($line =~ /^\[\+\] (\w+) \d+\/\d+\s*$/) {
        compose_flush() if defined $compose_verb && $compose_verb ne $1;
        ($compose_verb, $compose_header) = ($1, $line);
        next;
      }
      if (defined $compose_verb) {
        next if $line =~ /^\s*$/;
        if ($line =~ /^\s*\S+\s+(Container|Network|Volume|Image)\s+(\S+)\s/) {
          push @compose_order, "$1 $2" unless exists $compose_item{"$1 $2"};
          $compose_item{"$1 $2"} = $line;
          next;
        }
        compose_flush();
      }
      if ($in_key) {
        if ($line =~ /-----END [A-Z ]*PRIVATE KEY-----/) { $in_key = 0; print $line; }
        next;
      }
      $n += ($line =~ s/(-----BEGIN [A-Z ]*PRIVATE KEY-----).*?(-----END [A-Z ]*PRIVATE KEY-----)/$1********$2/g);
      if ($line =~ /-----BEGIN [A-Z ]*PRIVATE KEY-----/ && $line !~ /-----END [A-Z ]*PRIVATE KEY-----/) {
        print $line, "********\n";
        $in_key = 1;
        $n++;
        next;
      }
      for my $v (@values) { $n += ($line =~ s/\Q$v\E/********/g); }
      $line =~ s/((["\x27])$secret_key\2\s*:\s*)(["\x27])((?:\\.|(?!\3).)*)\3/$1 . $3 . mask_value($4, $1) . $3/ge;
      $line =~ s/(?<![\w.\-])($secret_key\s*=\s*)("(?:\\.|[^"\\])*"|\x27[^\x27]*\x27|[^\s,;&"\x27)\]]+)/$1 . mask_value($2, $1)/ge;
      $line =~ s/^(\s*(?:-\s+)?$secret_key:\s+)(\S.*)$/$1 . mask_value($2, $1)/e;
      $n += ($line =~ s/\b(?:AKIA|ASIA)[0-9A-Z]{16}\b/********/g);
      $n += ($line =~ s/\beyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}/********/g);
      $n += ($line =~ s/\b(Bearer|Basic)\s+(?!\*{8})[A-Za-z0-9\-._~+\/]{8,}=*/$1 ********/g);
      $n += ($line =~ s/\b([a-z][a-z0-9+.\-]*:\/\/[^\s\/:@\x27"]+:)(?!\*{8}@)[^\s@\/\x27"]+@/$1********@/gi);
      $n += ($line =~ s/\b(?:gh[pousr]_[A-Za-z0-9]{30,}|xox[abprs]-[A-Za-z0-9\-]{10,}|AIza[0-9A-Za-z_\-]{35})/********/g);
      print $line;
    }
    compose_flush();
    print STDERR "$n\n";
  '
}

# 📄 start the run log of 'playground run': from now on, everything this shell prints (the example included) also goes
# to a raw capture in a private folder, masked into the run log by run_log_finish. The example itself is run with
# run_log_exec, so that it still writes to a terminal.
# globals read: test_file, run_log_file_flag, no_run_log_flag
function run_log_start () {
  run_log_raw=""
  run_log_finished=""
  if [ -n "$GITHUB_RUN_NUMBER" ] || [ -n "$no_run_log_flag" ] || [ -n "${PLAYGROUND_RUN_LOG_ACTIVE:-}" ]
  then
    return 0
  fi
  if [ -z "$run_log_file_flag" ] && [ "$(playground config get run-log)" == "false" ]
  then
    return 0
  fi
  if [ -n "$run_log_file_flag" ]
  then
    run_log_file="$run_log_file_flag"
  else
    local folder
    folder=$(playground config get run-log-folder)
    folder="${folder:-$(run_log_default_folder)}"
    run_log_file="${folder/#\~/$HOME}/$(basename "$test_file" .sh)-$(date +%Y%m%d-%H%M%S).log"
  fi
  if ! mkdir -p "$(dirname "$run_log_file")" 2> /dev/null
  then
    logwarn "⚠️ cannot create the folder of the run log $run_log_file, this run is not logged"
    return 0
  fi
  run_log_tmp_dir=$(mktemp -d)
  chmod 0700 "$run_log_tmp_dir"
  run_log_raw="$run_log_tmp_dir/raw.log"
  : > "$run_log_raw"
  run_log_started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  run_log_started_seconds=$(date +%s)
  # the shell is behind a pipe from now on: let the commands of the run know they still print to a terminal (HTML
  # reports opened in the browser), and don't start a second run log in a nested 'playground run'
  if [ -t 1 ]
  then
    export PLAYGROUND_RUN_LOG_TERMINAL=1
  fi
  export PLAYGROUND_RUN_LOG_ACTIVE=1
  exec 8>&1 9>&2
  # tee ignores ctrl-c and kill, so that the end of the run (cleanup trap) is still printed and logged
  exec > >(trap '' INT TERM; exec tee -a "$run_log_raw") 2>&1
  run_log_tee_pid=$!
}

# run a command (the example) with the run log on: under script(1) when stdin is a terminal, so that the command
# keeps writing to a terminal (colors, prompts, docker run -it) while its output goes through the run log
function run_log_exec () {
  if [ -n "$run_log_raw" ] && [ -t 0 ] && command -v script > /dev/null 2>&1
  then
    local command_line
    command_line=$(printf '%q ' "$@")
    if [[ "$OSTYPE" == "darwin"* ]]
    then
      script -q /dev/null "$@"
    else
      script -q -e -c "$command_line" /dev/null
    fi
  else
    "$@"
  fi
}

# 📄 end of the run log: back to the terminal, then the header, the masked capture and, for a failure, the error digest
# of the connect container go to the run log file (0600), and its path is printed. Does nothing if run_log_start did not
# start one, and only runs once.
# $1: exit code of the run
# globals read: test_file, flag_list, environment, tag, connector_tag, connector_zip, connector_jar, cluster_creds,
# cluster_schema_registry_creds
function run_log_finish () {
  local exit_code="${1:-0}"
  if [ -z "$run_log_raw" ] || [ -n "$run_log_finished" ]
  then
    return 0
  fi
  run_log_finished=1
  exec 1>&8 2>&9 8>&- 9>&-
  # an example that left a background job behind keeps the pipe open: don't wait for it
  local i
  for ((i = 0; i < 20; i++))
  do
    kill -0 "$run_log_tee_pid" 2> /dev/null || break
    sleep 0.1
  done
  unset PLAYGROUND_RUN_LOG_TERMINAL PLAYGROUND_RUN_LOG_ACTIVE

  local result="FAILURE"
  if [ "$exit_code" == "0" ]
  then
    result="SUCCESS"
  elif [ "$exit_code" == "111" ]
  then
    result="SKIPPED"
  fi
  local duration=$(( $(date +%s) - run_log_started_seconds ))
  local default_tag
  default_tag=$(grep "# default tag" "$root_folder/scripts/utils.sh" | head -1 | sed -e 's/.*TAG=\([^ ]*\).*/\1/')
  local connector="${connector_tag:-${connector_zip:-${connector_jar:-default}}}"
  local commit dirty=""
  commit=$(git -C "$root_folder" rev-parse --short HEAD 2> /dev/null)
  if [ -n "$(git -C "$root_folder" status --porcelain -uno 2> /dev/null)" ]
  then
    dirty=" (with local changes)"
  fi
  local engine engine_version
  engine=$(get_container_engine 2> /dev/null)
  engine_version=$(docker version --format '{{.Server.Version}}' 2> /dev/null)

  {
    echo "# 📄 playground run log"
    echo "command:      playground run -f ${test_file#$(cd "$root_folder" && pwd)/} $flag_list"
    echo "environment:  ${environment:-${PLAYGROUND_ENVIRONMENT:-plaintext}}"
    echo "CP version:   ${tag:-$default_tag}"
    echo "connector:    $connector"
    echo "playground:   ${commit:-unknown}$dirty"
    echo "host:         $(uname -sr), $engine ${engine_version:-unknown}"
    echo "started:      $run_log_started_at, duration $((duration / 60))min $((duration % 60))sec"
    echo "result:       $result (exit code $exit_code)"
    echo "masking:      secrets are masked with ********, best-effort: review this file before sharing it outside Confluent"
    echo ""
    cat "$run_log_raw"
    if [ "$result" == "FAILURE" ] && is_container_running connect
    then
      echo ""
      echo "# 🔥 errors of the connect container (playground container logs -c connect --errors)"
      playground --output-level ERROR container logs -c connect --errors 2>&1
    fi
  } > "$run_log_tmp_dir/full.log"

  { run_log_secret_values; printf '%s\n' "$cluster_creds" "$cluster_schema_registry_creds"; } > "$run_log_tmp_dir/values" 2> /dev/null
  local masked
  (umask 077 && run_log_mask "$run_log_tmp_dir/values" < "$run_log_tmp_dir/full.log" > "$run_log_file" 2> "$run_log_tmp_dir/count")
  masked=$(tail -1 "$run_log_tmp_dir/count" 2> /dev/null)
  chmod 0600 "$run_log_file" 2> /dev/null
  rm -rf "$run_log_tmp_dir"

  # keep the last 50 run logs of the default folder
  if [ -z "$run_log_file_flag" ]
  then
    ls -1t "$(dirname "$run_log_file")"/*.log 2> /dev/null | tail -n +51 | while read -r old
    do
      rm -f "$old"
    done
  fi
  log "📄 masked log of this run (${masked:-0} secrets masked), to share with a colleague: $run_log_file"
}

# end of playground run: tell when a newer patch of the running Confluent Platform version is published
function display_newer_cp_patch_hint () {
  if ! command -v python3 > /dev/null 2>&1
  then
    return
  fi
  current_cp_version=""
  for container in broker connect
  do
    current_cp_version=$(docker inspect -f '{{.Config.Image}}' $container 2> /dev/null | cut -d ":" -f 2)
    if [ -n "$current_cp_version" ]
    then
      break
    fi
  done
  # official x.y.z tags only (no custom or nightly images)
  if [[ ! "$current_cp_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
  then
    return
  fi
  changelog_json=$(python3 -I "$root_folder/tools/cp-changelog/cp_changelog.py" --from "$current_cp_version" --same-line 2> /dev/null)
  if [ $? -ne 0 ] || [ -z "$changelog_json" ] || [ "$(echo "$changelog_json" | jq -r '.up_to_date')" == "true" ]
  then
    return
  fi
  newer_cp_version=$(echo "$changelog_json" | jq -r '.versions[0].version // empty')
  if [ -z "$newer_cp_version" ]
  then
    return
  fi
  nb_changes=$(echo "$changelog_json" | jq '[.versions[].changes | length] | add // 0')
  nb_security=$(echo "$changelog_json" | jq '[.versions[].changes[] | select(.security)] | length')
  log "📢 Confluent Platform $newer_cp_version is published (you run $current_cp_version): $nb_changes change(s), $nb_security security related"
  log "📜 To see them: playground cp-changelog --from $current_cp_version --to $newer_cp_version (--security for the security ones only)"
  log "🔄 To update: playground update-version --tag $newer_cp_version"
}

# playground salesforce setup|check: the org is driven with the Salesforce CLI (sf) installed on the
# host. The sfdx-cli image of the examples is too old to know the External Client App metadata types,
# and 'sf org login web' needs the host browser anyway.
function salesforce_setup_require_tools () {
  if ! command -v sf > /dev/null 2>&1
  then
    logerror "❌ the Salesforce CLI (sf) is not installed"
    logerror "   install it with: npm install --global @salesforce/cli (or see https://developer.salesforce.com/tools/salesforcecli)"
    exit 1
  fi
  for tool in openssl curl jq
  do
    if ! command -v $tool > /dev/null 2>&1
    then
      logerror "❌ $tool is not installed"
      exit 1
    fi
  done
}

# Sets sf_username, sf_instance_url and sf_org_id from an org the host sf CLI is logged into.
function salesforce_setup_resolve_org () {
  target_org="$1"
  org_json=$(sf org display --target-org "$target_org" --json 2> /dev/null) || true
  if [ "$(echo "$org_json" | jq -r '.status // 1')" != "0" ]
  then
    logerror "❌ the Salesforce CLI is not logged into org $target_org"
    echo "$org_json" | jq -r '.message // empty' >&2
    logerror "   run without --target-org to log in with the browser, or log in first with: sf org login web --alias $target_org"
    exit 1
  fi
  sf_username=$(echo "$org_json" | jq -r '.result.username')
  sf_instance_url=$(echo "$org_json" | jq -r '.result.instanceUrl')
  sf_org_id=$(echo "$org_json" | jq -r '.result.id')
}

# Generate a new JWT key pair as a PKCS12 keystore (password confluent). PBE-SHA1-3DES keeps it
# readable by every JDK of the Connect images (OpenSSL 3 defaults need JDK 11.0.12 or later).
function salesforce_setup_generate_keystore () {
  out="$1"
  if ! openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
      -subj "/C=US/ST=Ca/L=PaloAlto/O=CONFLUENT/OU=TEST/CN=kafka-docker-playground-$USER" \
      -keyout "$sf_tmp_dir/new.key" -out "$sf_tmp_dir/new.crt" > /dev/null 2>&1 \
    || ! openssl pkcs12 -export -name salesforce-confluent -in "$sf_tmp_dir/new.crt" -inkey "$sf_tmp_dir/new.key" \
      -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
      -passout pass:confluent -out "$out" > /dev/null 2>&1
  then
    rm -f "$sf_tmp_dir/new.key" "$sf_tmp_dir/new.crt"
    logerror "❌ failed to generate the keystore"
    exit 1
  fi
  rm -f "$sf_tmp_dir/new.key" "$sf_tmp_dir/new.crt"
  chmod 600 "$out"
}

# Install a keystore as the user keystore (salesforce_user_keystore_path), keeping the previous one
# as .bak, then copy it into the Salesforce example folders.
function salesforce_setup_install_keystore () {
  src="$1"
  user_keystore="$(salesforce_user_keystore_path)"
  mkdir -p "$(dirname "$user_keystore")"
  if [ -f "$user_keystore" ] && ! cmp -s "$src" "$user_keystore"
  then
    mv "$user_keystore" "$user_keystore.bak"
    logwarn "⚠️ previous keystore kept as $user_keystore.bak: the orgs set up with it must be set up again (playground salesforce setup)"
  fi
  if ! cmp -s "$src" "$user_keystore" 2> /dev/null
  then
    cp "$src" "$user_keystore"
    chmod 600 "$user_keystore"
  fi
  salesforce_sync_user_keystore "$root_folder"
}

# The keystore 'playground salesforce setup' uses, made the user keystore:
#   --keystore <file>      that file
#   --generate-keystore    a new key pair
#   otherwise              the user keystore, else the one already in the examples (the shared one of
#                          the S3 bucket, so the orgs that trust it keep working), else a new key pair
function salesforce_setup_resolve_keystore () {
  keystore="$1"
  generate="$2"
  user_keystore="$(salesforce_user_keystore_path)"
  example_keystore="$root_folder/connect/connect-salesforce-cdc-source/salesforce-confluent.keystore.jks"

  if [[ -n "$keystore" ]]
  then
    if [ ! -f "$keystore" ]
    then
      logerror "❌ keystore $keystore does not exist"
      exit 1
    fi
    salesforce_setup_load_keystore "$keystore"
    salesforce_setup_install_keystore "$keystore"
  elif [[ -n "$generate" ]]
  then
    log "🔐 generating a new key pair (PKCS12, password confluent)"
    salesforce_setup_generate_keystore "$sf_tmp_dir/generated.jks"
    salesforce_setup_install_keystore "$sf_tmp_dir/generated.jks"
  elif [ -f "$user_keystore" ]
  then
    salesforce_sync_user_keystore "$root_folder"
  elif [ -f "$example_keystore" ]
  then
    log "🔐 reusing the keystore already in the examples ($example_keystore), so the orgs that trust it keep working"
    log "   pass --generate-keystore for a key pair of your own"
    salesforce_setup_load_keystore "$example_keystore"
    salesforce_setup_install_keystore "$example_keystore"
  else
    log "🔐 generating your key pair (PKCS12, password confluent): the private key never leaves this machine"
    salesforce_setup_generate_keystore "$sf_tmp_dir/generated.jks"
    salesforce_setup_install_keystore "$sf_tmp_dir/generated.jks"
  fi
  salesforce_setup_load_keystore "$user_keystore"
  log "🔐 using the certificate of $user_keystore"
}

# Sets sf_certificate (base64 body of the certificate, as the External Client App metadata wants it)
# and sf_jwt_key_file (unencrypted private key, in sf_tmp_dir) from a keystore (password confluent).
function salesforce_setup_load_keystore () {
  keystore="$1"
  sf_certificate=$(openssl pkcs12 -in "$keystore" -nokeys -clcerts -passin pass:confluent 2> /dev/null | openssl x509 2> /dev/null | grep -v -- "-----") || true
  if [ -z "$sf_certificate" ]
  then
    logerror "❌ could not read the certificate of $keystore (password confluent expected)"
    exit 1
  fi
  sf_jwt_key_file="$sf_tmp_dir/jwt.key"
  rm -f "$sf_jwt_key_file"
  (umask 077 && openssl pkcs12 -in "$keystore" -nocerts -nodes -passin pass:confluent -out "$sf_jwt_key_file" > /dev/null 2>&1) || true
  if [ ! -s "$sf_jwt_key_file" ]
  then
    logerror "❌ could not read the private key of $keystore"
    exit 1
  fi
}

# Prints the consumer key of an External Client App created by 'playground salesforce setup', empty if
# the app does not exist. Retrieving ExtlClntAppGlobalOauthSettings returns it.
function salesforce_setup_get_consumer_key () {
  target_org="$1"
  app_name="$2"
  retrieve_dir="$sf_tmp_dir/retrieve-$app_name"
  rm -rf "$retrieve_dir"
  sf project retrieve start --metadata "ExtlClntAppGlobalOauthSettings:${app_name}_glbloauth" \
    --target-metadata-dir "$retrieve_dir" --unzip --target-org "$target_org" --json > "$sf_tmp_dir/retrieve.json" 2>&1 || true
  file=$(find "$retrieve_dir" -name "${app_name}_glbloauth.ecaGlblOauth" 2> /dev/null | head -1)
  if [ -n "$file" ]
  then
    sed -n 's#.*<consumerKey>\(.*\)</consumerKey>.*#\1#p' "$file" | head -1
  fi
}

function salesforce_setup_base64url () {
  openssl base64 -A | tr '+/' '-_' | tr -d '='
}

# One OAuth JWT bearer token request, exactly what a connector with salesforce.grant.type=JWT_BEARER
# does. Prints Salesforce's answer (without the token), returns 0 when it contains an access token,
# kept in sf_access_token / sf_token_instance_url for the REST calls of 'playground salesforce check'
# (so don't call it in a subshell). Nothing is stored and the sf CLI logins are left alone.
function salesforce_setup_jwt_token () {
  login_url="${1%/}"
  consumer_key="$2"
  username="$3"
  key_file="$4"

  audience="https://login.salesforce.com"
  if [[ "$login_url" == *test.salesforce.com* ]] || [[ "$login_url" == *.sandbox.my.salesforce.com* ]]
  then
    audience="https://test.salesforce.com"
  fi
  header=$(printf '{"alg":"RS256"}' | salesforce_setup_base64url)
  claims=$(jq -cn --arg iss "$consumer_key" --arg sub "$username" --arg aud "$audience" --argjson exp "$(( $(date +%s) + 300 ))" \
    '{iss: $iss, sub: $sub, aud: $aud, exp: $exp}' | salesforce_setup_base64url)
  signature=$(printf '%s.%s' "$header" "$claims" | openssl dgst -sha256 -sign "$key_file" -binary | salesforce_setup_base64url)
  response=$(curl -sS -m 30 -X POST "$login_url/services/oauth2/token" \
    --data-urlencode "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer" \
    --data-urlencode "assertion=$header.$claims.$signature" 2>&1) || true
  sf_access_token=$(echo "$response" | jq -r '.access_token // empty' 2> /dev/null) || true
  sf_token_instance_url=$(echo "$response" | jq -r '.instance_url // empty' 2> /dev/null) || true
  echo "$response" | jq -c 'del(.access_token, .signature)' 2> /dev/null || echo "$response"
  [ -n "$sf_access_token" ]
}

# Name of the variable for one value: SALESFORCE_USERNAME, SALESFORCE_USERNAME_KDP_CDC,
# SALESFORCE_USERNAME_ACCOUNT2 or SALESFORCE_USERNAME_KDP_CDC_ACCOUNT2, as read by salesforce_use_test_creds.
function salesforce_setup_var_name () {
  name="$1"
  suffix="$2"
  account2="$3"
  if [[ -n "$suffix" ]]
  then
    name="${name}_${suffix}"
  fi
  if [[ -n "$account2" ]]
  then
    name="${name}_ACCOUNT2"
  fi
  echo "$name"
}

# url from the host of the rest api of the flink jobmanager started by --enable-flink (port 18081)
function get_flink_rest_url () {
  flink_rest_url=""
  flink_jobmanager_container="jobmanager"
  local mapped
  mapped=$(docker port "$flink_jobmanager_container" "18081/tcp" 2>/dev/null | head -1)
  if [ -z "$mapped" ]
  then
    return 1
  fi
  flink_rest_url="http://localhost:${mapped##*:}"
}

# ksqldb-server REST API seen from the host (published port of ksqldb-server:8088), and the credentials to use:
# rbac-sasl-plain authenticates the REST clients (basic auth), as ksqlDBAdmin. Sets $ksqldb_url, $ksqldb_security
# (curl arguments) and $ksqldb_cli_security (ksql cli arguments). Returns 1 when ksqldb-server is not running.
function get_ksqldb_url_and_security () {
  ksqldb_url=""
  ksqldb_security=""
  ksqldb_cli_security=""
  local mapped
  mapped=$(docker port ksqldb-server "8088/tcp" 2>/dev/null | head -1)
  if [ -z "$mapped" ]
  then
    return 1
  fi
  ksqldb_url="http://localhost:${mapped##*:}"
  get_environment_used
  if [[ "$environment" == "rbac-sasl-plain" ]]
  then
    ksqldb_security="-u ksqlDBAdmin:ksqlDBAdmin"
    ksqldb_cli_security="--user ksqlDBAdmin --password ksqlDBAdmin"
  elif [[ "$environment" == "rbac-oauth" ]]
  then
    # bearer token of the Keycloak client superuser (SystemAdmin on the ksqlDB cluster)
    local ksqldb_token
    ksqldb_token=$(get_rbac_oauth_token superuser)
    ksqldb_security="--oauth2-bearer $ksqldb_token"
    ksqldb_cli_security="--token $ksqldb_token"
  fi
}

# runs the ksql statements $1 with the /ksql REST endpoint (not for SELECT / PRINT, use the cli for those) and prints
# the JSON response. Returns 1 when the request fails, or when a statement fails (its error is in the response).
function ksqldb_rest_statement () {
  local statement="$1" body response
  body=$(jq -n --arg ksql "$statement" '{ksql: $ksql, streamsProperties: {}}')
  response=$(curl $ksqldb_security -s -X POST "${ksqldb_url}/ksql" \
    -H "Accept: application/vnd.ksql.v1+json" -H "Content-Type: application/vnd.ksql.v1+json" \
    -d "$body")
  if [[ -z "$response" ]]
  then
    logerror "❌ no response from ksqlDB REST API $ksqldb_url" >&2
    return 1
  fi
  printf '%s\n' "$response"
  if echo "$response" | jq -e 'type == "object" and (."@type" // "" | test("error"))' > /dev/null 2>&1
  then
    return 1
  fi
}

# client ids of the tasks of a self-managed connector, one per line: connector-consumer-<connector>-<task> for a sink,
# connector-producer-<connector>-<task> for a source, or the consumer|producer.override.client.id of its config (then
# shared by all the tasks)
function get_connector_client_ids () {
  local connector="$1" status config connector_kind role override
  get_connect_url_and_security
  status=$(curl $security -s "${connect_url}/connectors/${connector}/status")
  connector_kind=$(echo "$status" | jq -r '.type // empty' 2>/dev/null)
  if [[ -z "$connector_kind" ]]
  then
    logerror "❌ connector $connector not found on $connect_url" >&2
    return 1
  fi
  role="consumer"
  if [[ "$connector_kind" == "source" ]]
  then
    role="producer"
  fi
  config=$(curl $security -s "${connect_url}/connectors/${connector}/config")
  override=$(echo "$config" | jq -r --arg key "$role.override.client.id" '.[$key] // empty' 2>/dev/null)
  if [[ -n "$override" ]]
  then
    echo "$override"
    return 0
  fi
  echo "$status" | jq -r --arg prefix "connector-$role-$connector-" '.tasks[] | "\($prefix)\(.id)"'
}

# kafka-configs entities of the quota commands, from the --user, --client-id, --connector, --all-users and
# --all-client-ids flags: fills quota_entities (one element per entity, its kafka-configs arguments separated by tabs)
# and quota_entity_labels. returns 2 when no entity is set.
function get_quota_entities () {
  local user="$1" client_id="$2" connector="$3" all_users="$4" all_client_ids="$5"
  local user_args="" user_label="" client_ids="" c
  quota_entities=()
  quota_entity_labels=()

  if [[ -n "$user" ]]
  then
    user_args=$'--entity-type\tusers\t--entity-name\t'"$user"
    user_label="user $user"
  elif [[ -n "$all_users" ]]
  then
    user_args=$'--entity-type\tusers\t--entity-default'
    user_label="all users"
  fi

  if [[ -n "$connector" ]]
  then
    local connector_type
    connector_type=$(playground state get run.connector_type)
    if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
    then
      logerror "❌ --connector only works with self-managed connectors"
      return 1
    fi
    client_ids=$(get_connector_client_ids "$connector") || return 1
    if [[ -z "$client_ids" ]]
    then
      logerror "❌ connector $connector has no task, so no client id yet (playground connector status --connector $connector)"
      return 1
    fi
  elif [[ -n "$client_id" ]]
  then
    client_ids="$client_id"
  fi

  if [[ -n "$client_ids" ]]
  then
    while IFS= read -r c
    do
      [[ -z "$c" ]] && continue
      quota_entities+=("${user_args:+$user_args$'\t'}--entity-type"$'\t'"clients"$'\t'"--entity-name"$'\t'"$c")
      quota_entity_labels+=("${user_label:+$user_label, }client-id $c")
    done <<< "$client_ids"
  elif [[ -n "$all_client_ids" ]]
  then
    quota_entities+=("${user_args:+$user_args$'\t'}--entity-type"$'\t'"clients"$'\t'"--entity-default")
    quota_entity_labels+=("${user_label:+$user_label, }all client ids")
  elif [[ -n "$user_args" ]]
  then
    quota_entities+=("$user_args")
    quota_entity_labels+=("$user_label")
  fi

  if [ ${#quota_entities[@]} -eq 0 ]
  then
    return 2
  fi
}

# runs kafka-configs for a quota entity of get_quota_entities or a broker entity of broker_config_entity ($1), with
# the other arguments: exits 1 on error (the tool sometimes exits 0 on errors)
function run_quota_kafka_configs () {
  local entity="$1" output rc=0
  shift
  local entity_args=()
  IFS=$'\t' read -r -a entity_args <<< "$entity"
  output=$(run_kafka_admin_tool kafka-configs "$@" "${entity_args[@]}" 2>&1) || rc=$?
  output=$(echo "$output" | grep -v -E "^$|SLF4J|log4j")
  if [ $rc -ne 0 ] || echo "$output" | grep -q -E "^Error|Exception"
  then
    logerror "❌ kafka-configs failed:"
    echo "$output" | grep -v -E "^[[:space:]]+at "
    return 1
  fi
  [[ -n "$output" ]] && echo "$output"
  return 0
}

# kafka-configs entity (tab separated, for run_quota_kafka_configs) of broker $1, or of the cluster-wide default
# when $1 is empty
function broker_config_entity () {
  if [[ -n "$1" ]]
  then
    printf '%s\t%s\t%s\t%s' --entity-type brokers --entity-name "$1"
  else
    printf '%s\t%s\t%s' --entity-type brokers --entity-default
  fi
}

# reads kafka-configs --entity-type brokers --describe [--all] (one or several brokers, and the cluster-wide default)
# on stdin, prints one "<broker id or default>\t<key>\t<value>\t<sensitive true|false>\t<source>\t<raw line>" per
# config. source is the first synonym (DYNAMIC_BROKER_CONFIG, STATIC_BROKER_CONFIG, DEFAULT_CONFIG...), empty when
# nothing sets the key
function parse_broker_configs () {
  awk 'BEGIN { OFS = "\t" }
    /^(All|Dynamic) configs for broker [0-9]+ are:/ { b = $5 ; next }
    /^Default configs for brokers in the cluster are:/ { b = "default" ; next }
    /^[[:space:]]+[^ =]+=/ {
      line = $0 ; sub(/^[[:space:]]+/, "", line)
      eq = index(line, "=") ; k = substr(line, 1, eq - 1) ; rest = substr(line, eq + 1)
      tail = ""
      if (match(rest, / sensitive=(true|false) synonyms=[{].*[}]$/)) { v = substr(rest, 1, RSTART - 1) ; tail = substr(rest, RSTART + 1) } else { v = rest }
      s = (tail ~ /^sensitive=true/) ? "true" : "false"
      syn = tail ; sub(/^sensitive=(true|false) synonyms=[{]/, "", syn) ; sub(/[}]$/, "", syn)
      src = syn ; sub(/:.*/, "", src)
      print b, k, v, s, src, line
    }'
}

# sets broker_config_ids to broker $1 (checking that it exists), or to every broker when $1 is empty: returns 1 on
# error
function get_broker_config_ids () {
  local broker="$1" ids
  ids=$(get_broker_ids)
  if [[ -z "$ids" ]]
  then
    logerror "❌ no broker found, is an environment running? (playground status)"
    return 1
  fi
  if [[ -n "$broker" ]]
  then
    if ! echo "$ids" | grep -q -x "$broker"
    then
      logerror "❌ broker $broker does not exist, brokers are: $(echo $ids)"
      return 1
    fi
    broker_config_ids=("$broker")
  else
    broker_config_ids=()
    while read -r id
    do
      broker_config_ids+=("$id")
    done <<< "$ids"
  fi
  return 0
}

# partitions of a topic, one per line: "<partition> <leader> <replicas> <isr>" (replicas and isr comma separated)
function get_topic_partition_assignment () {
  local topic="$1"
  run_kafka_admin_tool kafka-topics --describe --topic "$topic" 2>/dev/null | awk '
    /Partition:/ {
      p=""; l=""; r=""; i=""
      for (n = 1; n <= NF; n++) {
        if ($n == "Partition:") p = $(n+1)
        if ($n == "Leader:") l = $(n+1)
        if ($n == "Replicas:") r = $(n+1)
        if ($n == "Isr:") i = $(n+1)
      }
      print p, l, r, i
    }'
}

# ids of the brokers of the cluster, one per line
function get_broker_ids () {
  run_kafka_admin_tool kafka-broker-api-versions 2>/dev/null | grep -o -E "\(id: [0-9]+" | grep -o -E "[0-9]+" | sort -n | uniq
}

# copies every record of topic $1 to topic $2 in one transaction of transactional id $3, ended with $4 (commit, abort or
# open) and transaction.timeout.ms $5, with scripts/cli/src/transactional-copier (built on first use, run with the
# kafka-clients of the broker container): returns 1 on error
function run_transactional_copier () {
  local input_topic="$1" output_topic="$2" transactional_id="$3" transaction="$4" transaction_timeout="$5"
  local copier_dir="$root_folder/scripts/cli/src/transactional-copier"
  local jar="$copier_dir/target/transactional-copier-1.0.0.jar"
  local output rc=0
  if [ ! -f "$jar" ] || [ -n "$(find "$copier_dir/src" "$copier_dir/pom.xml" -newer "$jar" 2>/dev/null)" ]
  then
    log "🏗 Building jar for transactional-copier"
    mkdir -p "$copier_dir/target"
    # built from a copy of the sources, like schema-validator: an IDE may write its own classes in target/classes
    build_java_component_with_retry "transactional-copier" docker run -i --rm -v "$copier_dir:/usr/src/transactional-copier:ro" -v "$HOME/.m2":/root/.m2 -v "$root_folder/scripts/settings.xml:/tmp/settings.xml" -v "$copier_dir/target:/usr/src/target" maven:3.9.11-eclipse-temurin-17 bash -c "mkdir -p /usr/src/mymaven && cp -r /usr/src/transactional-copier/pom.xml /usr/src/transactional-copier/src /usr/src/mymaven/ && cd /usr/src/mymaven && mvn -s /tmp/settings.xml package && cp target/transactional-copier-1.0.0.jar /usr/src/target/"
  fi

  get_security_broker "--command-config"
  local copier_cmd=(java -cp "/tmp/transactional-copier.jar:/usr/share/java/kafka/*" com.github.vdesabou.TransactionalCopier --bootstrap-server "$bootstrap_server" $security --input-topic "$input_topic" --output-topic "$output_topic" --transactional-id "$transactional_id" --transaction "$transaction" --transaction-timeout-ms "$transaction_timeout")
  if [[ -n "$verbose" ]]
  then
    log "🐞 CLI command used (in $container)"
    echo "${copier_cmd[*]}"
  fi
  if [[ "$environment" == cfk* ]]
  then
    kubectl -n confluent cp "$jar" "$container:/tmp/transactional-copier.jar" > /dev/null 2>&1 || { logerror "❌ could not copy the transactional copier to $container" ; return 1 ; }
    output=$(kubectl -n confluent exec -i "$container" -- "${copier_cmd[@]}" 2>&1) || rc=$?
  else
    docker cp "$jar" "$container:/tmp/transactional-copier.jar" > /dev/null 2>&1 || { logerror "❌ could not copy the transactional copier to $container" ; return 1 ; }
    output=$(docker exec -i "$container" "${copier_cmd[@]}" 2>&1) || rc=$?
  fi
  if [ $rc -ne 0 ] || ! echo "$output" | grep -q -E "^transaction (committed|aborted|left open)"
  then
    logerror "❌ the transactional copy to topic $output_topic failed:"
    echo "$output" | grep -v -E "^[[:space:]]+at |^SLF4J|^log4j" | tail -20
    return 1
  fi
  echo "$output" | grep -E "^records sent in the transaction|^transaction (committed|aborted|left open)"
  return 0
}

# runs a kafka-* tool whose connection options go before its subcommand (kafka-transactions,
# kafka-metadata-quorum, kafka-features): $1 tool, $2 subcommand, then the arguments of the subcommand
function run_kafka_admin_subcommand_tool () {
  local tool="$1" subcommand="$2"
  shift 2
  get_security_broker "--command-config"
  if [[ -n "$verbose" ]]
  then
    log_verbose_command "$tool --bootstrap-server $bootstrap_server $security $subcommand $*"
  fi
  if [[ "$environment" == cfk* ]]
  then
    kubectl -n confluent exec -i $container -- $tool --bootstrap-server $bootstrap_server $security $subcommand "$@"
  else
    docker exec -i $container $tool --bootstrap-server $bootstrap_server $security $subcommand "$@"
  fi
}

# id of the broker run by docker container $1 (running or stopped), empty when it is not a broker
function get_broker_id_of_container () {
  docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$1" 2>/dev/null | grep -E "^KAFKA_(BROKER|NODE)_ID=" | head -1 | cut -d= -f2
}

# docker containers of the brokers (running or stopped), one "<id> <container>" per line, sorted by id
function get_broker_containers () {
  local c id candidates="broker broker2 broker3"
  if is_mdc_environment
  then
    # one broker per cluster of an mdc-* environment
    get_mdc_cluster
    candidates="broker-$mdc_cluster"
  fi
  for c in $candidates
  do
    id=$(get_broker_id_of_container "$c")
    if [[ -n "$id" ]]
    then
      echo "$id $c"
    fi
  done | sort -n
}

# running docker containers of the KRaft controllers, one "<node id> <container>" per line, sorted by id (empty with
# ZooKeeper, where the active controller is a broker)
function get_controller_containers () {
  local c id candidates="controller controller2 controller3"
  if is_mdc_environment
  then
    get_mdc_cluster
    candidates="controller-$mdc_cluster"
  fi
  for c in $candidates
  do
    is_container_running "$c" || continue
    id=$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$c" 2>/dev/null | grep -E "^KAFKA_NODE_ID=" | head -1 | cut -d= -f2)
    [[ -n "$id" ]] && echo "$id $c"
  done | sort -n
}

# docker container of broker $1: returns 1 (with an error) when there is none
function get_broker_container_of_id () {
  local id="$1" containers
  containers=$(get_broker_containers)
  broker_id_container=$(echo "$containers" | awk -v id="$id" '$1 == id { print $2 }')
  if [[ -z "$broker_id_container" ]]
  then
    if [[ -z "$containers" ]]
    then
      logerror "❌ no broker container found, is an environment running? (playground status)"
    else
      logerror "❌ broker $id does not exist, brokers are: $(echo "$containers" | awk '{print $1}' | paste -sd, -)"
    fi
    return 1
  fi
  return 0
}

# partitions listed by kafka-topics --describe $1 (--under-replicated-partitions, --under-min-isr-partitions or
# --unavailable-partitions), one "<topic> <partition> <leader> <replicas> <isr>" per line: returns 1 when kafka-topics fails
function get_partitions_with_status () {
  local output
  output=$(run_kafka_admin_tool kafka-topics --describe "$1" 2>&1) || { echo "$output" | grep -v -E "^[[:space:]]+at " >&2 ; return 1 ; }
  echo "$output" | awk '
    /Partition:/ {
      t=""; p=""; l=""; r=""; i=""
      for (n = 1; n < NF; n++) {
        if ($n == "Topic:") t = $(n+1)
        if ($n == "Partition:") p = $(n+1)
        if ($n == "Leader:") l = $(n+1)
        if ($n == "Replicas:") r = $(n+1)
        if ($n == "Isr:" && $(n+1) !~ /:$/) i = $(n+1)
      }
      if (i == "") i = "-"
      print t, p, l, r, i
    }'
}

# checks the health of the cluster and sets health_* (registered, fenced and not registered brokers, partitions
# under-replicated, under min ISR and unavailable, KRaft quorum): returns 0 when healthy, 1 otherwise
function get_cluster_health () {
  local api_versions id container output now
  health_ok=1
  health_error=""

  api_versions=$(run_kafka_admin_tool kafka-broker-api-versions 2>/dev/null | grep -E "\(id: [0-9]+" || true)
  health_registered=$(echo "$api_versions" | grep -o -E "\(id: [0-9]+" | grep -o -E "[0-9]+" | sort -n | uniq || true)
  health_fenced=$(echo "$api_versions" | grep "isFenced: true" | grep -o -E "\(id: [0-9]+" | grep -o -E "[0-9]+" | sort -n | uniq || true)
  if [[ -z "$health_registered" ]]
  then
    health_error="no broker answers, is an environment running? (playground status)"
    health_ok=0
    return 1
  fi
  [[ -n "$health_fenced" ]] && health_ok=0

  # broker containers (not on cfk) whose broker is down: not registered (stopped, still starting), or stopped but
  # still registered (a killed broker stays registered until its session times out)
  health_not_registered=""
  get_environment_used
  if [[ "$environment" != cfk* ]]
  then
    while read -r id container
    do
      [[ -z "$id" ]] && continue
      if ! echo "$health_registered" | grep -q -x "$id" || ! is_container_running "$container"
      then
        health_not_registered+="$id $container"$'\n'
        health_ok=0
      fi
    done <<< "$(get_broker_containers)"
  fi
  health_not_registered=$(echo -n "$health_not_registered" | sed '/^$/d')

  health_urp=$(get_partitions_with_status --under-replicated-partitions) || { health_error="kafka-topics failed" ; health_ok=0 ; return 1 ; }
  health_under_min_isr=$(get_partitions_with_status --under-min-isr-partitions) || { health_error="kafka-topics failed" ; health_ok=0 ; return 1 ; }
  health_unavailable=$(get_partitions_with_status --unavailable-partitions) || { health_error="kafka-topics failed" ; health_ok=0 ; return 1 ; }
  # every replica in sync but still under min ISR: the replication factor is below min.insync.replicas, a config
  # problem (acks=all producers always fail) rather than a broker problem, reported apart
  health_rf_below_min_isr=$(echo "$health_under_min_isr" | awk 'NF && $3 != "none" && $3 != "-1" && $5 != "-" { if (split($4, r, ",") == split($5, i, ",")) print }')
  health_under_min_isr=$(echo "$health_under_min_isr" | awk 'NF { if ($3 == "none" || $3 == "-1" || $5 == "-" || split($4, r, ",") != split($5, i, ",")) print }')
  if [[ -n "$health_urp" ]] || [[ -n "$health_under_min_isr" ]] || [[ -n "$health_unavailable" ]]
  then
    health_ok=0
  fi

  # KRaft quorum, one "<node id> <status> <log end offset> <lag> <seconds since last caught up>" per line (empty with ZooKeeper)
  health_quorum=""
  health_quorum_leader=""
  health_quorum_error=""
  local rc=0
  output=$(run_kafka_admin_subcommand_tool kafka-metadata-quorum describe --replication 2>&1) || rc=$?
  if [ $rc -eq 0 ] && echo "$output" | grep -q "^NodeId"
  then
    now=$(($(date +%s) * 1000))
    health_quorum=$(echo "$output" | awk -v now="$now" '
      $1 ~ /^[0-9]+$/ {
        # the DirectoryId column only exists in recent versions
        if (NF >= 7) { leo = $3; lag = $4; caught = $6; status = $7 } else { leo = $2; lag = $3; caught = $5; status = $6 }
        age = (caught > 0) ? int((now - caught) / 1000) : -1
        if (age < 0 && caught > 0) age = 0
        print $1, status, leo, lag, age
      }')
    health_quorum_leader=$(echo "$health_quorum" | awk '$2 == "Leader" { print $1 }')
  elif ! echo "$output" | grep -q -E "UnsupportedVersion|ZooKeeper|zookeeper"
  then
    health_quorum_error=$(echo "$output" | grep -v -E "^[[:space:]]+at |SLF4J|log4j" | grep -E "Error|Exception" | head -3 || true)
    [[ -z "$health_quorum_error" ]] && health_quorum_error=$(echo "$output" | head -3)
    health_ok=0
  fi

  [ $health_ok -eq 1 ]
}

# waits up to $2 seconds for broker $1 to be registered (and not fenced): returns 1 on timeout
function wait_for_broker_registered () {
  local id="$1" max_wait="$2" start_time=$SECONDS api_versions
  while true
  do
    api_versions=$(run_kafka_admin_tool kafka-broker-api-versions 2>/dev/null | grep -E "\(id: ${id} " || true)
    if [[ -n "$api_versions" ]] && ! echo "$api_versions" | grep -q "isFenced: true"
    then
      return 0
    fi
    if [ $((SECONDS - start_time)) -ge $max_wait ]
    then
      logerror "❌ broker $id is still not registered after ${max_wait}s"
      return 1
    fi
    sleep 3
  done
}

# waits up to $1 seconds for the cluster to be healthy (see get_cluster_health), logging the progress: returns 1 on timeout
function wait_for_cluster_healthy () {
  local max_wait="$1" start_time=$SECONDS
  while ! get_cluster_health
  do
    if [ $((SECONDS - start_time)) -ge $max_wait ]
    then
      logerror "❌ cluster is still not healthy after ${max_wait}s: $(cluster_health_one_line)"
      return 1
    fi
    log "⏳ cluster not healthy yet ($(cluster_health_one_line)), waiting... ($((SECONDS - start_time))s/${max_wait}s)"
    sleep 5
  done
  return 0
}

# one line summary of the problems found by get_cluster_health
function cluster_health_one_line () {
  local problems=()
  [[ -n "$health_error" ]] && problems+=("$health_error")
  [[ -n "$health_not_registered" ]] && problems+=("brokers down: $(echo "$health_not_registered" | awk '{print $1}' | paste -sd, -)")
  [[ -n "$health_fenced" ]] && problems+=("brokers fenced: $(echo "$health_fenced" | paste -sd, -)")
  [[ -n "$health_urp" ]] && problems+=("$(echo "$health_urp" | wc -l | tr -d ' ') under-replicated partitions")
  [[ -n "$health_under_min_isr" ]] && problems+=("$(echo "$health_under_min_isr" | wc -l | tr -d ' ') under min ISR")
  [[ -n "$health_unavailable" ]] && problems+=("$(echo "$health_unavailable" | wc -l | tr -d ' ') unavailable")
  [[ -n "$health_quorum_error" ]] && problems+=("KRaft quorum not available")
  local IFS=","
  echo "${problems[*]}" | sed 's/,/, /g'
}

# table of the partitions of a topic, with ⚠️ on the partitions whose leader is not the preferred (first) replica
function print_topic_partition_assignment () {
  local topic="$1" p l r i preferred
  printf '%-10s %-8s %-12s %-12s\n' "PARTITION" "LEADER" "REPLICAS" "ISR"
  while read -r p l r i
  do
    [[ -z "$p" ]] && continue
    preferred="${r%%,*}"
    if [ "$l" != "$preferred" ]
    then
      printf '%-10s %-8s %-12s %-12s %s\n' "$p" "$l" "$r" "$i" "⚠️ preferred leader is $preferred"
    else
      printf '%-10s %-8s %-12s %-12s\n' "$p" "$l" "$r" "$i"
    fi
  done <<< "$(get_topic_partition_assignment "$topic")"
}

# executes a kafka-reassign-partitions plan (json), then waits until it is completed, unless no_wait is set
# usage: execute_partition_reassignment <plan> <throttle> <no_wait> <max_wait>
function execute_partition_reassignment () {
  local plan="$1" throttle="$2" no_wait="$3" max_wait="$4" output
  local throttle_args=()
  if [[ -n "$throttle" ]]
  then
    throttle_args=(--throttle "$throttle")
  fi
  output=$(echo "$plan" | run_kafka_admin_tool kafka-reassign-partitions --reassignment-json-file /dev/stdin --execute "${throttle_args[@]}" 2>&1)
  if ! echo "$output" | grep -q "Successfully started partition reassignment"
  then
    logerror "❌ the reassignment could not be started:"
    echo "$output" | grep -v -E "^$|SLF4J|^\{|Current partition replica assignment|Save this to use"
    return 1
  fi
  log "🚀 reassignment started${throttle:+, replication throttled to $throttle bytes/s}"
  if [[ -n "$no_wait" ]]
  then
    return 0
  fi
  wait_for_partition_reassignment "$plan" "$max_wait"
}

# runs kafka-reassign-partitions --verify every 5 seconds until the plan is completed (--verify also removes the throttle)
# with max_wait 0, checks only once: returns 2 when the reassignment is still in progress
function wait_for_partition_reassignment () {
  local plan="$1" max_wait="${2:-300}" cur_wait=0 output in_progress
  while true
  do
    output=$(echo "$plan" | run_kafka_admin_tool kafka-reassign-partitions --reassignment-json-file /dev/stdin --verify 2>&1)
    in_progress=$(echo "$output" | grep -c "is still in progress" || true)
    if echo "$output" | grep -q -E "^Error|Exception"
    then
      logerror "❌ kafka-reassign-partitions --verify failed:"
      echo "$output" | grep -v -E "^$|SLF4J"
      return 1
    fi
    if [ "$in_progress" == "0" ]
    then
      log "✅ reassignment completed"
      return 0
    fi
    if [ "$max_wait" == "0" ]
    then
      log "⏳ $in_progress partition(s) still being reassigned"
      echo "$output" | grep "is still in progress"
      return 2
    fi
    if [ $cur_wait -ge $max_wait ]
    then
      logerror "❌ $in_progress partition(s) still being reassigned after $max_wait seconds"
      echo "$output" | grep "is still in progress"
      return 1
    fi
    log "⏳ $in_progress partition(s) still being reassigned"
    sleep 5
    cur_wait=$((cur_wait+5))
  done
}

# connector config in one of the formats customers send, normalized to a flat json object of strings, for
# playground connector create-or-update / validate / diff / convert:
#   - json: a plain config, the REST API format {"name": ..., "config": {...}}, a dump of GET /connectors?expand=info
#   - a 'playground connector create-or-update' heredoc, as printed by show-config
#   - a CFK Connector or a Strimzi KafkaConnector custom resource (yaml, several documents allowed)
#   - a terraform confluent_connector resource (config_nonsensitive + config_sensitive)
#   - a connect-standalone .properties file
# $1 the content, $2 the connector to pick when the content has several (can be empty), $3 the format (json, heredoc,
# cfk, strimzi, terraform, properties; detected when empty or auto). Sets NORMALIZED_CONFIG,
# NORMALIZED_FORMAT (what was detected, for a log line) and NORMALIZED_NAME (the name in the source, can be empty).
# Returns 1 with NORMALIZED_ERROR set when the content is not a connector config, or holds several and $2 is not one.
function normalize_connector_config () {
  local content="$1" wanted="$2" format="${3:-auto}" candidates names count from=""
  NORMALIZED_CONFIG=""
  NORMALIZED_FORMAT=""
  NORMALIZED_NAME=""
  NORMALIZED_ERROR=""

  if [ "$format" == "heredoc" ] || { [ "$format" == "auto" ] && echo "$content" | grep -qE "<< *['\"]?EOF"; }
  then
    content=$(echo "$content" | sed -n '/<< *.\{0,1\}EOF/,/^EOF/p' | sed '1d;$d' | sed 's/\\\$/$/g')
    from=", from a create-or-update heredoc"
    format="json"
  fi
  if [ "$format" == "auto" ]
  then
    if echo "$content" | jq -e 'type == "object"' > /dev/null 2>&1
    then
      format="json"
    elif echo "$content" | grep -qE '^[[:space:]]*kind:[[:space:]]*["'"'"']?(Connector|KafkaConnector)["'"'"']?[[:space:]]*$'
    then
      format="cfk"
    elif echo "$content" | grep -qE 'resource[[:space:]]+"confluent_connector"'
    then
      format="terraform"
    elif echo "$content" | grep -qE '^[[:space:]]*[A-Za-z0-9_.-]+[[:space:]]*[=:]'
    then
      format="properties"
    fi
  fi

  # candidates: one json per line, {"name": <name or null>, "config": {...}, "format": "..."}
  if [ "$format" == "json" ]
  then
    candidates=$(echo "$content" | jq -c '
      if has("config") and (.config | type == "object") then
        {name: (.name // .config.name), config: .config, format: "REST API format ({\"name\": ..., \"config\": {...}})"}
      elif length > 0 and all(.[]; type == "object" and (.info.config | type) == "object") then
        to_entries[] | {name: .key, config: .value.info.config, format: "dump of GET /connectors?expand=info"}
      else
        {name: .name, config: ., format: "JSON"}
      end')
  elif [ "$format" == "cfk" ] || [ "$format" == "strimzi" ]
  then
    # both kinds, whatever --from says: a file can hold the two
    candidates=$(echo "$content" | yq -o json -I0 'select(.kind == "Connector" or .kind == "KafkaConnector")' 2> /dev/null | jq -c '
      if .kind == "Connector" then
        {name: .metadata.name, format: "CFK Connector custom resource (spec.class, spec.taskMax, spec.configs)",
         config: ({name: .metadata.name, "connector.class": .spec.class, "tasks.max": .spec.taskMax} + (.spec.configs // {}))}
      else
        {name: .metadata.name, format: "Strimzi KafkaConnector custom resource (spec.class, spec.tasksMax, spec.config)",
         config: ({name: .metadata.name, "connector.class": .spec.class, "tasks.max": .spec.tasksMax} + (.spec.config // {}))}
      end
      | .config |= with_entries(select(.value != null))')
  elif [ "$format" == "terraform" ]
  then
    candidates=$(echo "$content" | yq -p hcl -o json -I0 '.resource.confluent_connector | to_entries | .[]' 2> /dev/null | jq -c '
      ((.value.config_nonsensitive // {}) + (.value.config_sensitive // {})) as $config
      | {name: ($config.name // .key), config: $config, format: "terraform confluent_connector resource \"\(.key)\" (config_nonsensitive + config_sensitive)"}')
  elif [ "$format" == "properties" ]
  then
    candidates=$(echo "$content" | python3 -I "$root_folder/tools/connector-config/properties_to_json.py" 2> /dev/null | jq -c '{name: .name, config: ., format: "connect-standalone .properties file"}')
  fi

  if [ -z "$candidates" ]
  then
    NORMALIZED_ERROR="not a connector config: expected json (a config, the REST API format or a dump of GET /connectors?expand=info), a create-or-update heredoc, a CFK Connector or Strimzi KafkaConnector custom resource, a terraform confluent_connector resource, or a connect-standalone .properties file"
    return 1
  fi

  count=$(echo "$candidates" | grep -c .)
  if [ "$count" -gt 1 ]
  then
    names=$(echo "$candidates" | jq -r '.name // "?"' | paste -sd ' ' -)
    if [ -z "$wanted" ] || ! echo "$candidates" | jq -e --arg w "$wanted" 'select(.name == $w)' > /dev/null 2>&1
    then
      NORMALIZED_ERROR="$count connectors in the config ($names), pick one with --connector"
      return 1
    fi
    candidates=$(echo "$candidates" | jq -c --arg w "$wanted" 'select(.name == $w)' | head -1)
  fi

  # connect configs are maps of strings: yaml and hcl numbers and booleans, json numbers
  NORMALIZED_CONFIG=$(echo "$candidates" | jq '.config | with_entries(.value |= (if type == "string" then . elif type == "null" then "" else tostring end))')
  NORMALIZED_NAME=$(echo "$candidates" | jq -r '.name // empty')
  NORMALIZED_FORMAT="$(echo "$candidates" | jq -r '.format')$from"
  if ! echo "$NORMALIZED_CONFIG" | jq -e 'all(.[]; type == "string")' > /dev/null 2>&1
  then
    NORMALIZED_ERROR="the config of the $NORMALIZED_FORMAT has nested objects, a connector config is a flat map of strings"
    return 1
  fi
  return 0
}

# the values of a normalized connector config ($1) that cannot run as they are, one "<key>|<reason>" line each: masked
# secrets, config providers of the customer environment, terraform references
function connector_config_placeholders () {
  echo "$1" | jq -r '
    to_entries[]
    | .key as $k | .value as $v
    | if ($v | test("^\\*{3,}$|^\\[hidden\\]$")) then "\($k)|masked secret"
      # ${file:/data:...} is how the examples pass their secrets
      elif ($v | test("\\$\\{(file|directory|vault|env|aws|azure|gcp|secret|keyvault|ssm|k8s|kubernetes)[a-zA-Z]*:")) and ($v | test("\\$\\{file:/data:") | not) then "\($k)|config provider of the customer environment (\($v))"
      elif ($v | test("^(var|local|data|module|confluent_[a-z_]+)\\.[A-Za-z0-9_.\\[\\]-]+$")) or ($v | test("\\$\\{(var|local|data|module)\\.")) then "\($k)|terraform reference (\($v))"
      else empty end'
}

# logs what a normalized connector config ($1) needs before it can run: placeholders, and a fully managed config
# deployed as a self-managed one ($2 = fully_managed when the connector is a fully managed one)
function connector_config_findings () {
  local config="$1" context="$2" placeholders class
  class=$(echo "$config" | jq -r '."connector.class" // empty')
  if [ -z "$class" ]
  then
    logwarn "⚠️ the config has no connector.class"
  elif [[ "$class" != *.* ]] && [ "$context" != "fully_managed" ]
  then
    logwarn "☁️ connector.class $class is a fully managed connector: run it as a fully managed example (ccloud/fm-*), the self-managed plugin has another class and other keys"
  fi
  placeholders=$(connector_config_placeholders "$config")
  if [ -n "$placeholders" ]
  then
    logwarn "⚠️ $(echo "$placeholders" | grep -c .) value(s) to fill in, they cannot work as they are:"
    echo "$placeholders" | awk -F'|' '{ printf "   %s: %s\n", $1, $2 }'
  fi
}

# the values of a normalized self-managed connector config ($1) that point to the customer environment, rewritten for
# the playground. Only values whose hosts are not containers of the playground (nor localhost, nor confluent cloud) are
# touched, so the configs of the examples (broker-us, schema-registry, a confluent cloud cluster...) stay as they are:
#   - bootstrap servers -> broker:9092, schema registry urls -> http://schema-registry:8081 (broker-us:9092 and
#     http://schema-registry-us:8081 with --cluster us in an mdc environment)
#   - the credentials of a schema registry that was rewritten (basic / bearer auth, ssl)
#   - on plaintext, the security of the clients whose bootstrap servers were rewritten (confluent.topic.*, *.override.*)
#   - a confluent.license that is set, replication factors above the number of brokers
# Sets ADAPTED_CONFIG and ADAPTED_CHANGES (number of keys changed or removed), and logs them. With $2 = report, also
# logs the keys left as they are that point to external systems (hosts, files of the customer)
function connector_config_adapt () {
  local config="$1" report="$2" brokers=1 plaintext=false changes others local_hosts
  ADAPTED_CONFIG="$config"
  ADAPTED_CHANGES=0
  if [[ "$(echo "$config" | jq -r '."connector.class" // ""')" != *.* ]]
  then
    # fully managed: the keys are not the ones of a self-managed connector
    return 0
  fi
  get_environment_used
  if [[ "$environment" == "ccloud" ]]
  then
    # self-managed connect on a confluent cloud cluster: the bootstrap servers and schema registry are the cloud ones
    return 0
  fi
  [ -n "$(playground state get flags.ENABLE_KAFKA_NODES 2> /dev/null)" ] && brokers=3
  [[ "$environment" == *plaintext ]] && plaintext=true
  local playground_bootstrap="broker:9092" playground_sr_url="http://schema-registry:8081"
  if [[ "$environment" == mdc* ]]
  then
    get_mdc_cluster
    playground_bootstrap="broker-$mdc_cluster:9092"
    playground_sr_url="http://schema-registry-$mdc_cluster:8081"
  fi
  # hosts of the playground: its containers (cfk: the services of the confluent namespace)
  local_hosts=$( { docker ps --format '{{.Names}}' 2> /dev/null; echo "localhost kafka schemaregistry connect broker schema-registry"; } | tr ' ' '\n' | jq -R -s 'split("\n") | map(select(length > 0))')

  ADAPTED_CONFIG=$(echo "$config" | jq --argjson brokers "$brokers" --argjson plaintext "$plaintext" --argjson local "$local_hosts" --arg playground_bootstrap "$playground_bootstrap" --arg playground_sr_url "$playground_sr_url" '
    def is_local_host: . as $h | ($local | index($h)) or ($h | test("\\.confluent\\.cloud$|^127\\.0\\.0\\.1$"));
    def bootstrap_hosts: split(",") | map(gsub("^\\s+|\\s+$"; "") | sub("^[A-Za-z_]+://"; "") | sub(":[0-9]+$"; "")) | map(select(length > 0));
    def url_host: (capture("://(?<h>[^/:@]+)(:[0-9]+)?(/|$)") | .h) // "";
    . as $config
    | ([to_entries[] | select((.key | test("(^|\\.)bootstrap\\.servers$")) and ((.value | bootstrap_hosts) | any(is_local_host | not))) | .key]) as $bootstrap_keys
    | ([to_entries[] | select((.key | test("(^|\\.)schema\\.registry\\.url$")) and (.value | split(",") | any(url_host | is_local_host | not))) | .key]) as $sr_keys
    # the clients whose bootstrap servers are rewritten: their security settings are the ones of the customer cluster
    | ($bootstrap_keys | map(sub("\\.?bootstrap\\.servers$"; ""))) as $clients
    | with_entries(
        .key as $k
        | if ($bootstrap_keys | index($k)) then .value = $playground_bootstrap
          elif ($sr_keys | index($k)) then .value = $playground_sr_url
          elif ($sr_keys | length) > 0 and ($k | test("(^|\\.)(basic\\.auth\\.(credentials\\.source|user\\.info)|bearer\\.auth\\..+|schema\\.registry\\.ssl\\..+)$")) then empty
          elif $k == "confluent.license" and .value != "" then empty
          elif $plaintext and ($clients | any(. as $c | $c != "" and ($k | startswith($c + "."))))
               and ($k | test("\\.(security\\.protocol|sasl\\..+|ssl\\..+)$")) then empty
          elif ($k | test("replication\\.factor$")) and ((.value | tonumber? // 0) > $brokers) then .value = ($brokers | tostring)
          else . end)')

  changes=$(jq -n -r --argjson old "$config" --argjson new "$ADAPTED_CONFIG" '
    ($old | keys[] | select($new[.] == null) | "   - \(.)"),
    ($old | keys[] | select($new[.] != null and $new[.] != $old[.]) | "   \(.): \($old[.] | if test("password|secret|user\\.info"; "i") then "********" else . end) → \($new[.])")')
  if [ -n "$changes" ]
  then
    ADAPTED_CHANGES=$(echo "$changes" | grep -c .)
    log "🔧 adapted to the playground (--no-adapt to keep the config as is):"
    echo "$changes"
  fi
  if [ "$report" != "report" ]
  then
    return 0
  fi
  others=$(echo "$ADAPTED_CONFIG" | jq -r --argjson local "$local_hosts" '
    def is_local_host: . as $h | ($local | index($h)) or ($h | test("\\.confluent\\.cloud$|^127\\.0\\.0\\.1$"));
    def url_host: (capture("://(?<h>[^/:@]+)(:[0-9]+)?(/|$)") | .h) // "";
    to_entries[]
    | select(
        ((.key | test("ssl\\.(keystore|truststore)\\.location$|keytab|\\.file$|\\.path$|credentials\\.path$")) and (.value | test("^/")))
        or ((.value | test("^[a-z][a-z0-9+.:-]*://[^/]+")) and (.value | url_host | is_local_host | not))
        or ((.key | test("(^|\\.)(hostname|host|endpoint|server\\.name)$")) and .value != "" and (.value | is_local_host | not)))
    | "   \(.key)=\(.value | gsub("(?<k>(password|pwd)=)[^&;]*"; "\(.k)********"; "i") | gsub("(?<s>://[^/:@]+:)[^/@]+@"; "\(.s)********@"))"')
  if [ -n "$others" ]
  then
    log "🌍 still pointing to the customer environment (external systems, files): use the ones of the example"
    echo "$others"
  fi
}

# lib/ folder of a connector plugin version (or of a zip), downloaded once in /tmp/connector-plugin-jars and reused
# get_connector_plugin_lib_dir <owner/name> <version|latest|" "|""> <zip or ""> <force refresh or "">
# sets plugin_lib_dir, plugin_label and plugin_version; logs go to stderr; returns 1 when it fails
function get_connector_plugin_lib_dir () {
  local connector_plugin="$1"
  local connector_tag="$2"
  local connector_zip="$3"
  local force_refresh="$4"
  local cache_root="/tmp/connector-plugin-jars"
  local plugin_dir work_dir jar
  mkdir -p "$cache_root"
  plugin_lib_dir=""
  plugin_label=""
  plugin_version=""

  if [[ -n "$connector_zip" ]]
  then
    if [[ $connector_zip == *"@"* ]]
    then
      connector_zip=${connector_zip#*@}
    fi
    if [[ "$connector_zip" != *.zip ]]
    then
      logerror "❌ --connector-zip $connector_zip is not a .zip file"
      return 1
    fi
    plugin_dir="$cache_root/zip-$(basename "$connector_zip" .zip)-$(shasum "$connector_zip" | cut -c1-12)"
    plugin_label="$(basename "$connector_zip")"
    plugin_version="$(basename "$connector_zip" .zip)"
    if [[ -n "$force_refresh" ]] || { [ -d "$plugin_dir" ] && ! connector_plugin_cache_complete "$plugin_dir"; }
    then
      rm -rf "$plugin_dir"
    fi
    if [ ! -d "$plugin_dir" ]
    then
      log "📦 Extracting $connector_zip" >&2
      work_dir=$(mktemp -d -t pg-XXXXXXXXXX)
      if ! unzip -q "$connector_zip" -d "$work_dir"
      then
        logerror "❌ could not extract $connector_zip"
        rm -rf "$work_dir"
        return 1
      fi
      mkdir -p "$plugin_dir"
      mv "$work_dir"/* "$plugin_dir"/
      rm -rf "$work_dir"
    fi
  else
    if [ "$connector_tag" == " " ]
    then
      connector_tag=$(choose_connector_tag "$connector_plugin" | cut -d ' ' -f 2 | sed 's/^v//')
    fi
    if [[ -z "$connector_tag" ]] || [ "$connector_tag" == "latest" ]
    then
      connector_tag=$(playground connector-plugin versions --connector-plugin "$connector_plugin" --latest 2>/dev/null)
      if [[ -z "$connector_tag" ]]
      then
        logwarn "could not find the latest version of $connector_plugin on Confluent Hub, its jars won't be cached" >&2
        connector_tag="latest"
      fi
    fi
    plugin_label="$connector_plugin:$connector_tag"
    plugin_version="$connector_tag"
    plugin_dir="$cache_root/$(echo "$connector_plugin" | tr '/' '-')-$connector_tag"
    if [[ -n "$force_refresh" ]] || [ "$connector_tag" == "latest" ]
    then
      rm -rf "$plugin_dir"
    elif [ -d "$plugin_dir" ] && ! connector_plugin_cache_complete "$plugin_dir"
    then
      logwarn "📂 the jars of $plugin_label in $plugin_dir are incomplete (files deleted by the cleanup of /tmp?), downloading them again" >&2
      rm -rf "$plugin_dir"
    fi
    if [ ! -d "$plugin_dir" ]
    then
      get_connect_image
      log "🔌 Downloading connector plugin $connector_plugin:$connector_tag" >&2
      # in a mktemp folder: Docker Desktop doesn't share /tmp (/private/tmp) by default
      work_dir=$(mktemp -d -t pg-XXXXXXXXXX)
      if ! docker run -u0 -i --rm -v "$work_dir:/usr/share/confluent-hub-components" ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} bash -c "confluent-hub install --no-prompt $connector_plugin:$connector_tag && chown -R $(id -u $USER):$(id -g $USER) /usr/share/confluent-hub-components" > "$work_dir.log" 2>&1
      then
        logerror "❌ could not download $connector_plugin:$connector_tag from Confluent Hub:"
        tail -5 "$work_dir.log" >&2
        rm -rf "$work_dir" "$work_dir.log"
        return 1
      fi
      mkdir -p "$plugin_dir"
      mv "$work_dir"/* "$plugin_dir"/
      rm -rf "$work_dir" "$work_dir.log"
    else
      log "♻️ Using the jars of $plugin_label already downloaded in $plugin_dir" >&2
    fi
  fi

  plugin_lib_dir=$(find "$plugin_dir" -type d -name lib | head -1)
  if [[ -z "$plugin_lib_dir" ]]
  then
    # some zips have their jars at the top level
    plugin_lib_dir=$(dirname "$(find "$plugin_dir" -name '*.jar' | head -1)")
  fi
  if [[ -z "$plugin_lib_dir" ]] || [ "$plugin_lib_dir" == "." ]
  then
    logerror "❌ no jar found in $plugin_dir"
    return 1
  fi
  # list of the jars, to detect a folder emptied by the cleanup of /tmp (macOS deletes the files untouched for 3 days, keeps the folders)
  if [ ! -f "$plugin_dir/.jars" ]
  then
    (cd "$plugin_lib_dir" && ls -1 *.jar) > "$plugin_dir/.jars" 2>/dev/null
  fi
}

# true when the cached plugin folder $1 still has every jar listed when it was downloaded
function connector_plugin_cache_complete () {
  local plugin_dir="$1" lib_dir jar
  [ -s "$plugin_dir/.jars" ] || return 1
  lib_dir=$(find "$plugin_dir" -type d -name lib | head -1)
  [[ -n "$lib_dir" ]] || lib_dir=$(dirname "$(find "$plugin_dir" -name '*.jar' | head -1)")
  while IFS= read -r jar
  do
    [ -f "$lib_dir/$jar" ] || return 1
  done < "$plugin_dir/.jars"
}

# writes the configuration reference of a connector (the config-<class>.txt format read by connector-plugin config-key,
# and the "key": "default" json used by connector diff --defaults) from the answer of config/validate in file $1
# write_connector_config_reference <validate json file> <txt file> <json file>
function write_connector_config_reference () {
  local validate_file="$1" filename="$2" json_filename="$3"
  # one jq for all the parameters: splitting the fields with bash dropped the empty ones (an empty default
  # value shifted the type, importance... of the parameter by one)
  local excluded_groups='["Common","Transforms","Error Handling","Topic Creation","offsets.topic","Predicates","Confluent Licensing"]'
  jq -r --argjson excluded "$excluded_groups" '
      [.configs[].definition | select(.group as $g | $excluded | index($g) | not)]
      | reduce .[] as $d ({out: "", group: []};
          (if $d.group != .group then .out += "==========================\n\($d.group)\n==========================\n" | .group = $d.group else . end)
          | .out += "🔘 \($d.name)\n\n\($d.documentation)\n\n\t - Type: \($d.type)\n\t - Default: \($d.default_value)\n\t - Importance: \($d.importance)\n\t - Required: \($d.required)\n\n")
      | .out' "$validate_file" > "$filename"
  # fix unwanted commits like this one #7231
  jq -r --argjson excluded "$excluded_groups" '
      .configs[].definition | select(.group as $g | $excluded | index($g) | not)
      | "    \"\(.name)\": \"\(if .default_value == null then "" else .default_value end)\","' "$validate_file" | sort \
    | sed -E 's/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z/YYYY-MM-DDTHH:mm:ss/g' | sed -E 's/[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}/YYYY-MM-DD HH:mm/g' | sed -E 's/[0-9]{4}-[0-9]{2}-[0-9]{2}/YYYY-MM-DD/g' > "$json_filename"
  if [ ! -s "$filename" ]
  then
    rm -f "$filename" "$json_filename"
  fi
}

# configuration of the connectors of a plugin version, without a worker: tools/connector-plugin-jars/ConfigDump.java
# (compiled once in a JDK container) loads the plugin jars with the java of the connect image and prints its ConfigDef
# as the answer of config/validate. Also cached in .connector_config like playground connector show-config-parameters.
# get_connector_plugin_configs <owner/name> <version> [<connector class>]
# sets plugin_configs_dir (one config-<class>.json per connector class) and plugin_config_classes; returns 1 on failure
function get_connector_plugin_configs () {
  local connector_plugin="$1" version="$2" wanted_class="$3"
  local src="$root_folder/tools/connector-plugin-jars/ConfigDump.java"
  local dump_dir cp_script class out

  get_connector_plugin_lib_dir "$connector_plugin" "$version" "" "" || return 1
  # compiled once per version of the source (Docker Desktop shares /tmp), and the results kept per version of it
  dump_dir="/tmp/connector-plugin-jars/configdump-$(shasum "$src" | cut -c1-12)"
  plugin_configs_dir="$(dirname "$plugin_lib_dir")/.configs-$(basename "$dump_dir")"
  mkdir -p "$plugin_configs_dir"

  if [ ! -f "$dump_dir/ConfigDump.class" ]
  then
    log "☕ Compiling the configuration reader (once)" >&2
    mkdir -p "$dump_dir"
    cp "$src" "$dump_dir/"
    if ! docker run --rm -v "$dump_dir:/src" -w /src ${PG_JAVAP_IMAGE:-eclipse-temurin:21-jdk} javac --release 8 -Xlint:-options ConfigDump.java > "$dump_dir/javac.log" 2>&1
    then
      logerror "❌ could not compile $src:"
      cat "$dump_dir/javac.log" >&2
      rm -f "$dump_dir/ConfigDump.class"
      return 1
    fi
  fi

  get_connect_image
  # the Kafka API jars only (the plugin brings the rest, like in a worker); all the jars of the worker when that fails
  cp_script='cp=/dump; for j in /usr/share/java/kafka/connect_api*.jar /usr/share/java/kafka/connect-api*.jar /usr/share/java/kafka/clients_*.jar /usr/share/java/kafka/kafka-clients*.jar /usr/share/java/kafka/slf4j-api*.jar; do [ -f "$j" ] && cp="$cp:$j"; done; java -cp "$cp" ConfigDump "$@" 2>/dev/null || java -cp "/dump:/usr/share/java/kafka/*" ConfigDump "$@"'

  if [[ -n "$wanted_class" ]]
  then
    plugin_config_classes="$wanted_class"
  elif [ -s "$plugin_configs_dir/classes" ]
  then
    plugin_config_classes=$(cat "$plugin_configs_dir/classes")
  else
    plugin_config_classes=$(docker run --rm -v "$dump_dir:/dump:ro" -v "$plugin_lib_dir:/plugin:ro" --entrypoint bash ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} -c "$cp_script" _ /plugin --discover 2>/dev/null)
    if [[ -z "$plugin_config_classes" ]]
    then
      logerror "❌ no connector class found in $plugin_label: set --connector-class"
      return 1
    fi
    echo "$plugin_config_classes" > "$plugin_configs_dir/classes"
  fi

  for class in $plugin_config_classes
  do
    out="$plugin_configs_dir/config-$class.json"
    if [ ! -s "$out" ]
    then
      log "🔩 Reading the configuration of $class $version" >&2
      if ! docker run --rm -v "$dump_dir:/dump:ro" -v "$plugin_lib_dir:/plugin:ro" --entrypoint bash ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} -c "$cp_script" _ /plugin "$class" > "$out.tmp" 2> "$out.err" || ! jq -e '.configs' "$out.tmp" > /dev/null 2>&1
      then
        logerror "❌ could not read the configuration of $class in $plugin_label:"
        grep -m3 -E "Exception|Error" "$out.err" >&2
        rm -f "$out.tmp"
        return 1
      fi
      mv "$out.tmp" "$out"
      rm -f "$out.err"
    fi
    # same cache as playground connector show-config-parameters: config-key lists it in "versions run locally"
    if [ -z "$GITHUB_RUN_NUMBER" ]
    then
      mkdir -p "$root_folder/.connector_config"
      if [ "$(cat "$root_folder/.connector_config/.format" 2>/dev/null)" != "2" ]
      then
        rm -f "$root_folder"/.connector_config/config-*
        echo "2" > "$root_folder/.connector_config/.format"
      fi
      if [ ! -f "$root_folder/.connector_config/config-$class-$version.txt" ]
      then
        write_connector_config_reference "$out" "$root_folder/.connector_config/config-$class-$version.txt" "$root_folder/.connector_config/config-$class-$version.json"
        # dated in the past: connector diff takes the newest file as the reference of the running version
        touch -t 200001010000 "$root_folder/.connector_config/config-$class-$version.txt" "$root_folder/.connector_config/config-$class-$version.json" 2>/dev/null || true
      fi
    fi
  done
}

# owner/name of the Confluent Hub plugin of a connector class, from the examples of the repository: the plugin mounted
# (CONNECT_PLUGIN_PATH) by the examples that record (config-<class>.txt) or create ("connector.class") that class and use
# a single plugin; empty when none does
function connector_plugin_of_class () {
  local class="$1"
  (
    cd "$root_folder" > /dev/null || exit 0
    { git ls-files -- "*/config-$class.txt"; git grep -l -F "\"$class\"" -- 'connect/*.sh' 2>/dev/null; } | xargs -n1 dirname 2>/dev/null | sort -u | while read -r dir
    do
      plugins=$(grep -ohE "confluent-hub-components/[A-Za-z0-9_.-]+" "$dir"/docker-compose*.yml 2>/dev/null | sort -u)
      [ "$(echo "$plugins" | grep -c .)" == "1" ] && echo "$plugins"
    done | sort | uniq -c | sort -rn | head -1 | awk '{print $2}' | sed 's#confluent-hub-components/##; s#-#/#'
  )
}

# the owner/name of a connector plugin from what was typed for --connector-plugin: owner/name (also the "<typed>@owner/name"
# of the fzf completion), a connector class (io.confluent.connect.jdbc.JdbcSinkConnector: its plugin, see
# connector_plugin_of_class) or a fully managed type (S3_SINK: confluentinc/S3_SINK)
# prints it; returns 1, with an error on stderr, when a class can't be resolved
function resolve_connector_plugin () {
  local input="$1" plugin
  if [[ "$input" == *"@"* ]]
  then
    input=$(echo "$input" | cut -d "@" -f 2)
  fi
  if [[ -z "$input" ]] || [[ "$input" == */* ]]
  then
    echo "$input"
    return 0
  fi
  if [[ "$input" == *.* ]]
  then
    plugin=$(connector_plugin_of_class "$input")
    if [[ -z "$plugin" ]]
    then
      logerror "❌ could not find the plugin of connector class $input in the examples: set --connector-plugin <owner/name>" >&2
      return 1
    fi
    log "🔌 connector class $input is in plugin $plugin" >&2
    echo "$plugin"
    return 0
  fi
  log "☁️ $input is taken as the fully managed connector confluentinc/$input" >&2
  echo "confluentinc/$input"
}

# ---------------------------------------------------------------------------------------------------------------------
# JMX digests: broker metrics (and its controller section), schema metrics, ksqldb metrics, connector metrics --worker
#
# A spec is one metric per line: label|object name|attribute|format|warning
#   object name  an MBean name; a * is allowed in a value: io.confluent.ksql.metrics:type=*ksql-engine-query-stats
#   format       int, pct (a ratio, shown in %), ms, rate, bytes, bool (true/false or 1/0, shown yes/no), str (as it is)
#   warning      gt0 (⚠️ above 0), lt30 (⚠️ below 30%), yes (⚠️ when true), empty for none
# The MBeans are read in the container: with kafka-jmx when the image has it (brokers, controllers, connect: no download),
# otherwise with jmxterm (schema-registry, ksqldb-server), like get-jmx-metrics.
# ---------------------------------------------------------------------------------------------------------------------

# the awk functions shared by the reader: MBean names are compared once normalized (keys sorted: kafka-jmx and jmxterm
# don't print them in the same order), and a spec object name is a glob
JMX_DIGEST_AWK_FUNCTIONS='
function jmx_norm(n,    i, d, rest, cnt, arr, j, t, out) {
    i = index(n, ":"); d = substr(n, 1, i - 1); rest = substr(n, i + 1)
    cnt = split(rest, arr, ",")
    for (i = 1; i <= cnt; i++) for (j = i + 1; j <= cnt; j++) if (arr[j] < arr[i]) { t = arr[i]; arr[i] = arr[j]; arr[j] = t }
    out = d ":"
    for (i = 1; i <= cnt; i++) out = out (i > 1 ? "," : "") arr[i]
    return out
}
function jmx_glob_re(g,    r, i, c) {
    r = "^"
    for (i = 1; i <= length(g); i++) {
        c = substr(g, i, 1)
        if (c == "*") r = r ".*"
        else if (index("\\.[](){}+?^$|", c) > 0) r = r "\\" c
        else r = r c
    }
    return r "$"
}
'

# jmx_digest_read <container> <spec>: prints "<label>|<raw value>" for each metric of the spec (empty value when the MBean
# or the attribute doesn't exist). Returns 1 when the JMX metrics of the container can't be read.
function jmx_digest_read () {
    local container="$1" spec="$2" port raw="" jar beans work_dir
    port=$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$container" 2>/dev/null | grep -E "^[A-Z_]*JMX_PORT=" | head -1 | cut -d= -f2)
    if [[ -z "$port" ]]
    then
        logwarn "⚠️ JMX is not enabled on container $container (no *_JMX_PORT environment variable), skipped"
        return 1
    fi
    work_dir=$(mktemp -d -t playground-jmx-digest.XXXXXX)
    echo "$spec" > "$work_dir/spec"

    local jmx_tool=""
    if docker exec "$container" bash -c "command -v kafka-jmx" > /dev/null 2>&1
    then
        jmx_tool="kafka-jmx"
    elif docker exec "$container" bash -c "command -v kafka-run-class" > /dev/null 2>&1
    then
        # before Kafka 3.5
        jmx_tool="kafka-run-class kafka.tools.JmxTool"
    fi

    if [[ -n "$jmx_tool" ]]
    then
        local object_args=()
        while read -r object
        do
            [[ -n "$object" ]] && object_args+=(--object-name "$object")
        done < <(cut -d'|' -f2 "$work_dir/spec" | sort -u)
        # "<object name>:<attribute>\t<value>" per line
        docker exec "$container" $jmx_tool --jmx-url "service:jmx:rmi:///jndi/rmi://localhost:$port/jmxrmi" "${object_args[@]}" --one-time true --report-format tsv > "$work_dir/raw" 2>&1 || true
        # kafka-jmx gives up on the whole query when one MBean of it can't be read (no attribute, for example): jmxterm then
        grep -q $'\t' "$work_dir/raw" || jmx_tool=""
    fi
    if [[ -z "$jmx_tool" ]]
    then
        jar=$(get_jmxterm_jar) || { rm -rf "$work_dir"; return 1; }
        docker cp "$jar" "$container:$jar" > /dev/null 2>&1 || { logwarn "⚠️ could not copy jmxterm to container $container, skipped"; rm -rf "$work_dir"; return 1; }
        printf 'beans\nexit\n' | docker exec -i "$container" java -jar "$jar" -l "localhost:$port" -n -v silent > "$work_dir/beans" 2>/dev/null || true
        # the attributes of the spec, per MBean that exists: "get -b <bean> <attribute>..." prints the "#mbean = <name>:"
        # header, then one line per attribute found (not "get *": one attribute that can't be read, like "schemas" of the
        # jersey-metrics of Schema Registry, would hide the others)
        awk -F'|' "$JMX_DIGEST_AWK_FUNCTIONS"'
            NR == FNR { if ($0 != "") beans[++nb] = $0; next }
            $2 != "" {
                re = jmx_glob_re(jmx_norm($2))
                for (i = 1; i <= nb; i++) if (jmx_norm(beans[i]) ~ re && index(" " wanted[beans[i]] " ", " " $3 " ") == 0) wanted[beans[i]] = wanted[beans[i]] " " $3
            }
            END { for (b in wanted) print "get -b " b wanted[b] }' "$work_dir/beans" "$work_dir/spec" > "$work_dir/commands"
        echo "exit" >> "$work_dir/commands"
        # "#mbean = <name>:" then "<attribute> = <value>;" lines, turned into the kafka-jmx format
        # (jmxterm prints the values of "get" on stderr)
        docker exec -i "$container" java -jar "$jar" -l "localhost:$port" -n < "$work_dir/commands" 2>&1 | awk '
            /^#mbean = / { bean = substr($0, 10); sub(/:$/, "", bean); next }
            / = / && bean != "" {
                i = index($0, " = "); attr = substr($0, 1, i - 1); value = substr($0, i + 3)
                sub(/;$/, "", value); gsub(/"/, "", value); gsub(/^[ \t]+/, "", attr)
                print bean ":" attr "\t" value
            }' > "$work_dir/raw"
    fi

    if ! grep -q $'\t' "$work_dir/raw"
    then
        logwarn "⚠️ could not read the JMX metrics of container $container:"
        grep -v -E "^[[:space:]]+at " "$work_dir/raw" | tail -3
        rm -rf "$work_dir"
        return 1
    fi

    awk -F'\t' "$JMX_DIGEST_AWK_FUNCTIONS"'
        NR == FNR {
            # the attribute is after the last ":" of the key (a value of the MBean name may contain ":")
            key = $1; last = 0
            for (i = 1; i <= length(key); i++) if (substr(key, i, 1) == ":") last = i
            if (last == 0) next
            n++; names[n] = jmx_norm(substr(key, 1, last - 1)); attrs[n] = substr(key, last + 1); values[n] = $2
            next
        }
        {
            split($0, f, "|")
            re = jmx_glob_re(jmx_norm(f[2])); value = ""
            for (i = 1; i <= n; i++) if (attrs[i] == f[3] && names[i] ~ re) { value = values[i]; break }
            print f[1] "|" value
        }' "$work_dir/raw" "$work_dir/spec"
    rm -rf "$work_dir"
}

# jmx_digest_collect <spec> <targets: "<column id> <container>" per line>: reads every target, sets JMX_DIGEST_IDS (the
# columns that could be read) and JMX_DIGEST_VALUES ("<column id>|<label>|<raw value>" per line)
function jmx_digest_collect () {
    local spec="$1" targets="$2" id container output
    JMX_DIGEST_IDS=""
    JMX_DIGEST_VALUES=""
    while read -r id container
    do
        [[ -z "$id" ]] && continue
        if ! is_container_running "$container"
        then
            logwarn "⚠️ container $container is not running, skipped"
            continue
        fi
        output=$(jmx_digest_read "$container" "$spec") || continue
        JMX_DIGEST_IDS+="$id "
        JMX_DIGEST_VALUES+=$(echo "$output" | sed "s/^/$id|/")$'\n'
    done <<< "$targets"
}

# jmx_digest_table <column header> <spec>: prints JMX_DIGEST_VALUES as a table, one column per JMX_DIGEST_IDS
function jmx_digest_table () {
    local header="$1" spec="$2" id label object attribute format warning value
    {
        printf 'METRIC'
        for id in $JMX_DIGEST_IDS
        do
            printf '\t%s %s' "$header" "$id"
        done
        printf '\n'
        while IFS='|' read -r label object attribute format warning
        do
            [[ -z "$label" ]] && continue
            printf '%s' "$label"
            for id in $JMX_DIGEST_IDS
            do
                value=$(echo -n "$JMX_DIGEST_VALUES" | awk -F'|' -v id="$id" -v label="$label" '$1 == id && $2 == label { print $3 ; exit }')
                printf '\t%s' "$(echo "$value" | awk -v format="$format" -v warning="$warning" '
                    $0 == "" || $0 == "NaN" { print "-" ; exit }
                    format == "str" { print ; exit }
                    format == "bool" {
                        yes = ($0 == "true" || $0 == "1" || $0 == "1.0")
                        out = yes ? "yes" : "no"
                        if (warning == "yes" && yes) out = out " ⚠️"
                        print out ; exit
                    }
                    {
                        v = $0 + 0
                        if (format == "pct") out = sprintf("%.0f%%", v * 100)
                        else if (format == "ms") out = sprintf("%.0f ms", v)
                        else if (format == "rate") out = sprintf("%.1f", v)
                        else if (format == "bytes") {
                            if (v >= 1048576) out = sprintf("%.1f MB", v / 1048576)
                            else if (v >= 1024) out = sprintf("%.1f KB", v / 1024)
                            else out = sprintf("%.0f B", v)
                        }
                        else out = sprintf("%.0f", v)
                        if ((warning == "gt0" && v > 0) || (warning == "lt30" && v < 0.3)) out = out " ⚠️"
                        print out
                    }')"
            done
            printf '\n'
        done <<< "$spec"
    } | column -t -s $'\t'
}

# jmx_digest_json <id key>: prints JMX_DIGEST_VALUES as a JSON array, one object per column: {"<id key>": <id>,
# "metrics": {"<label>": <value>}} (numbers when numeric, true/false, null when missing, strings otherwise)
function jmx_digest_json () {
    local id_key="$1"
    echo -n "$JMX_DIGEST_VALUES" | jq -R -s --arg key "$id_key" 'split("\n") | map(select(length > 0) | split("|"))
        | group_by(.[0]) | map({ ($key): (.[0][0] | tonumber? // .), metrics: (map({ (.[1]): (.[2] as $v
            | if $v == "" or $v == "NaN" then null elif $v == "true" then true elif $v == "false" then false
              else ($v | tonumber? // $v) end) }) | add) })'
}

# jmx_digest_value <id> <label>: the raw value of one metric of JMX_DIGEST_VALUES (for the findings of a command)
function jmx_digest_value () {
    echo -n "$JMX_DIGEST_VALUES" | awk -F'|' -v id="$1" -v label="$2" '$1 == id && $2 == label { print $3 ; exit }'
}
