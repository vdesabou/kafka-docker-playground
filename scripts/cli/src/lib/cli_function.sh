function get_environment_used() {
  environment=$(playground state get run.environment)
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
  for worker in connect connect2 connect3 connect-us connect-europe
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

  if ! is_container_running "connect" && ! is_container_running "connect-us"
  then
    if is_container_running "connect2" || is_container_running "connect-europe"
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
  fi
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

  if [[ "$environment" == "sasl-ssl" ]] || [[ "$environment" == "2way-ssl" ]]
  then
      sr_url="https://localhost:8081"
      DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

      sr_security="--cert $DIR_CLI/../../environment/$environment/security/schema-registry.certificate.pem --key $DIR_CLI/../../environment/$environment/security/schema-registry.key --tlsv1.2 --cacert $DIR_CLI/../../environment/$environment/security/snakeoil-ca-1.crt"
  elif [[ "$environment" == "rbac-sasl-plain" ]] || [[ "$environment" == "cfk-rbac" ]]
  then
      DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

      sr_security="-u superUser:superUser"
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
}

function get_broker_container() {
  for broker in broker broker2 broker3 broker-us broker-europe
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
  elif [ "$environment" == "ldap-sasl-plain" ] || [ "$environment" == "sasl-plain" ] || [ "$environment" == "sasl-scram" ]
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
      log "🐞 CLI command used"
      echo "$tool $* --bootstrap-server $BOOTSTRAP_SERVERS --command-config /tmp/configuration/ccloud.properties"
    fi
    get_connect_image
    docker run --quiet --rm -v $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta:/tmp/configuration/ccloud.properties ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} $tool "$@" --bootstrap-server $BOOTSTRAP_SERVERS --command-config /tmp/configuration/ccloud.properties
  else
    get_security_broker "--command-config"
    if [[ -n "$verbose" ]]
    then
      log "🐞 CLI command used"
      echo "$tool $* --bootstrap-server $bootstrap_server $security"
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
    keyfile.json|*.pem|*.key|*.p12|secrets.properties|playground.ini|playground-run-history) return 0 ;;
  esac
  return 1
}

# value of a line '# <key>: <value>' of the header written by repro bootstrap
function repro_header_value () {
  local script="$1"
  local key="$2"
  head -30 "$script" | grep -m1 "^# .*$key: " | sed -e "s/^# .*$key: //"
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

    # possible customer data: warnings only
    while IFS=: read -r line_number match
    do
      domain="${match#*@}"
      domain="${domain,,}"
      case "$domain" in
        example.com|example.org|example.net|*.example.com|confluent.io|*.confluent.io|confluent.cloud|*.local|*.noreply.github.com|anthropic.com|*.svc|*.internal) continue ;;
      esac
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

  if [ ! -f $filename ]
  then
    playground connector-plugin versions --connector-plugin $owner/$name > /dev/null 2>&1
  fi

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

function filter_not_mdc_environment() {
  get_environment_used


  if [[ "$environment" == "mdc"* ]]
  then
    logerror "$environment is not supported with this command !"
  fi
}

function filter_ccloud_environment() {
  get_environment_used

  if [[ "$environment" != "ccloud" ]]
  then
    logerror "environment should be ccloud with this command (it is $environment)!"
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

  if [[ "$environment" != "rbac-sasl-plain" ]] && [[ "$environment" != "cfk-rbac" ]]
  then
    logerror "environment should be rbac-sasl-plain or cfk-rbac with this command (it is $environment)!"
  fi
}

function filter_rbac_or_ccloud_environment() {
  get_environment_used

  if [[ "$environment" != "rbac-sasl-plain" ]] && [[ "$environment" != "cfk-rbac" ]] && [[ "$environment" != "ccloud" ]]
  then
    logerror "environment should be rbac-sasl-plain, cfk-rbac or ccloud with this command (it is $environment)!"
  fi
}

# call the MDS REST API of the rbac-sasl-plain or cfk-rbac environment as superUser
# (on cfk-rbac, localhost:8091 is a port-forward to the MDS of the kafka service)
# usage: mds_request <method> <path> [json body]
# sets mds_output (response body), returns 1 when MDS is not reachable or answers an error
function mds_request() {
  local method="$1"
  local path="$2"
  local body="$3"
  local mds_url="http://localhost:8091"
  local curl_args=(-s -w '\n%{http_code}' -u superUser:superUser -H "Content-Type: application/json" -X "$method" "$mds_url$path")

  if [[ -n "$body" ]]
  then
    curl_args+=(-d "$body")
  fi

  if [[ -n "$verbose" ]]
  then
    log "🐞 curl command used"
    echo "curl -X $method -u superUser:superUser -H \"Content-Type: application/json\" $mds_url$path${body:+ -d '$body'}"
  fi

  local response
  response=$(curl "${curl_args[@]}")
  if [ $? -ne 0 ]
  then
    logerror "❌ MDS is not reachable at $mds_url, is the rbac-sasl-plain or cfk-rbac environment running?"
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

  # cluster names used in environment/rbac-sasl-plain/docker-compose.yml, or cluster ids set by CFK on cfk-rbac
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
  for environment_name in plaintext ccloud cfk cfk-rbac 2way-ssl kerberos ldap-authorizer-sasl-plain ldap-sasl-plain rbac-sasl-plain sasl-plain sasl-scram sasl-ssl ssl_kerberos
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

  # forget recorded topics and connectors that are gone (deleted above or by someone else)
  # only when both listings succeed, an empty list would forget everything
  if topics_json=$(confluent kafka topic list --output json) && connectors_json=$(confluent connect cluster list --output json)
  then
    prune_ccloud_recorded_entries "$cluster_id" "$(echo "$topics_json" | jq -r '.[].name')" "$(echo "$connectors_json" | jq -r '.[].name')"
  fi

  if [ ! -z "$GITHUB_RUN_NUMBER" ]
  then
    for subject in $(curl -u "$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" "$SCHEMA_REGISTRY_URL/subjects" | jq -r '.[]')
    do
        log "permanently delete subject $subject"
        check_if_skip "curl --request DELETE -u \"$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO\" \"$SCHEMA_REGISTRY_URL/subjects/$subject\" && curl --request DELETE -u \"$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO\" \"$SCHEMA_REGISTRY_URL/subjects/$subject?permanent=true\""
    done

    for row in $(confluent iam service-account list --output json | jq -r '.[] | @base64'); do
        _jq() {
        echo ${row} | base64 -d | jq -r ${1}
        }
        
        description=$(echo $(_jq '.description'))
        id=$(echo $(_jq '.id'))
        name=$(echo $(_jq '.name'))

        log "deleting service-account $id ($description)"
        check_if_skip "confluent iam service-account delete $id --force || true"
    done
  fi
}

# Remind the user what is still alive (and billed) on the Confluent Cloud cluster: connectors
# named *_<user> and the topics 'playground cleanup-cloud-resources' would delete
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
  existing_topics=$(confluent kafka topic list --environment "$environment_id" --cluster "$cluster_id" --output json 2>/dev/null | jq -r '.[].name' 2>/dev/null | grep -v '^_')
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
  logwarn "🧹 delete them with <playground cleanup-cloud-resources --resource ccloud>"
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
# (playground cleanup-cloud-resources --recorded-topics-only): it catches the topics kept at the end of a run because a
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
      logwarn "🧹 not running interactively, keeping them. Delete them with <playground cleanup-cloud-resources --resource ccloud>, or set <playground config cleanup-ccloud-resources-after-run true>"
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
# When PG_LOG_DIGEST_RECORDS_FILE is set, every distinct record (not only the first $1) is also appended to that
# file for the HTML reports (tools/log-analyzer/log_report.py), labelled with PG_LOG_DIGEST_LABEL:
#   @@PGFILE@@<tab>label<tab>lines<tab>distinct records<tab>occurrences
#   @@PGREC@@<tab>level<tab>count<tab>first line<tab>last line<tab>first timestamp<tab>last timestamp
#   <the record as printed in the digest, on one or more lines>
#   @@PGTS@@<tab>timestamps of the occurrences, space separated (1000 per record at most)
#   @@PGCTX@@<tab>raw lines around the first occurrence (2 before, the record (30 lines at most), 2 after), one per line
# then the "<Class>Config values:" dumps of the log (KafkaConfig, DistributedConfig, the config of a connector with its
# [connector|task-0] context, ProducerConfig of a client…), the last one of each class / context / client.id, 50 at most:
#   @@PGCFG@@<tab>config class<tab>[connector|task-0] context<tab>line<tab>timestamp<tab>client.id or name
#   @@PGCFGL@@<tab>key=value, one per line
function summarize_log_errors() {
    local max_findings="${1:-40}"
    local include_warnings="${2:-}"

    PG_LOG_DIGEST_RECORDS_FILE="${PG_LOG_DIGEST_RECORDS_FILE:-}" PG_LOG_DIGEST_LABEL="${PG_LOG_DIGEST_LABEL:-}" \
    awk -v max_findings="$max_findings" -v include_warnings="$include_warnings" '
    # anything that does not look like the continuation of a stack trace or of a
    # multi-line message (indented line, "Caused by:", exception line) starts a record
    function is_continuation(line) {
        return line ~ /^[ \t]/ ||
               line ~ /^Caused by:/ ||
               line ~ /^[A-Za-z0-9_$]+(\.[A-Za-z0-9_$]+)+(Exception|Error|Throwable)(:|$)/
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
    function level_of(head,    h, lvl) {
        h = substr(head, 1, 200)
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
        return ""
    }
    function short(s) {
        return length(s) > 300 ? substr(s, 1, 300) "..." : s
    }
    # "2026-10-13 10:00:05" or "2026-10-13T10:00:05" at the start of the record, as 2026-10-13T10:00:05
    function timestamp_of(head,    h, t) {
        h = substr(head, 1, 80)
        if (!match(h, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][ T][0-9][0-9]:[0-9][0-9]:[0-9][0-9]/)) return ""
        t = substr(h, RSTART, RLENGTH)
        sub(/ /, "T", t)
        return t
    }
    # a line of the context of a record, with its line number (▶ for the first line of the record)
    function ctx_line(n, s, mark) {
        gsub(/\033\[[0-9;]*m/, "", s)
        sub(/\r$/, "", s)
        return sprintf("%6d %s %s\n", n, mark, short(s))
    }
    function capture_after() {
        ctx[ctx_key] = ctx[ctx_key] ctx_line(NR, $0, " ")
        ctx_after--
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
        cfg_buf = cfg_buf k "=" v "\n"
    }
    function cfg_end(    key) {
        if (!cfg_on) return
        cfg_on = 0
        if (cfg_buf == "") return
        key = cfg_cls "|" cfg_ctx "|" cfg_id
        if (!(key in cfg_text)) {
            if (ncfg >= 50) return
            cfg_order[++ncfg] = key
        }
        cfg_text[key] = cfg_buf
        cfg_head[key] = cfg_cls "\t" cfg_ctx "\t" cfg_ln "\t" cfg_ts "\t" cfg_id
    }
    function flush(    lvl, key, i, chain, frames, nframes, line, cause, nrec) {
        if (nlines == 0) return
        # header of a digest already printed in the log (CI logs contain "playground container logs --errors" output)
        if (rec[1] ~ /^[^ ]+ (FATAL|ERROR|WARN) x[0-9]+ \(first seen line [0-9]+, last seen line [0-9]+\)$/) { nlines = 0; return }
        lvl = level_of(rec[1])
        if (lvl == "" || (lvl == "WARN" && include_warnings == "")) { nlines = 0; return }

        # exception chain: first exception line plus every "Caused by:", then frames of the deepest cause
        chain = ""
        cause = ""
        nframes = 0
        for (i = 2; i <= nlines; i++) {
            line = rec[i]
            if (line ~ /^[ \t]*at /) {
                if (nframes < 3) { sub(/^[ \t]*/, "", line); frames = frames "\n        " short(line); nframes++ }
                continue
            }
            if (line ~ /^[ \t]*\.\.\. [0-9]+ (more|common frames omitted)/) continue
            if (line ~ /^Caused by:/ || (chain == "" && line ~ /(Exception|Error|Throwable)(:|[ \t]*$)/)) {
                chain = chain "\n    " short(line)
                cause = line
                frames = ""
                nframes = 0
            }
        }
        if (chain == "" && rec[1] !~ /(Exception|Error|Throwable)(:|[ \t]|$)/) frames = ""

        # same message and same deepest cause = same finding, whatever the timestamps and ids
        key = rec[1]
        sub(/^\[?[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][ T][0-9:,.]*\]?[ \t]*/, "", key)
        key = lvl ":" substr(key, 1, 200) "|" substr(cause, 1, 200)
        gsub(/[0-9]+/, "#", key)

        total_occurrences++
        nrec = nlines
        nlines = 0
        ts = timestamp_of(rec[1])
        if (records_file != "" && ts != "" && nts[key] < 1000) { timestamps[key] = timestamps[key] " " ts; nts[key]++ }
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
        text[key] = short(rec[1]) chain frames
        if (records_file != "") {
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
    }
    {
        # the 2 lines before a record, for its context
        prev2 = prev1
        prev1 = cur
        cur = $0
        # most lines of a big log have no level or exception word and do not continue a record: one regex (a
        # single pass over the line) sets them aside, as the start of a level-less record, without the work below
        if ($0 !~ /ERROR|FATAL|SEVERE|PANIC|WARN|level|Exception|Error|Throwable|[EFW][0-9][0-9][0-9][0-9] [0-9][0-9]:|^[ \t]|^Caused by:|\033|Config values:/) {
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
            rec_line = NR
            if (records_file != "") {
                rec_before = (NR > 2 ? ctx_line(NR - 2, prev2, " ") : "") (NR > 1 ? ctx_line(NR - 1, prev1, " ") : "")
            }
        }
        if (ctx_after > 0) capture_after()
        rec[++nlines] = $0
    }
    END {
        flush()
        if (records_file != "") {
            printf "@@PGFILE@@\t%s\t%d\t%d\t%d\n", label, NR, nkeys, total_occurrences >> records_file
            for (i = 1; i <= nkeys; i++) {
                k = order[i]
                printf "@@PGREC@@\t%s\t%d\t%d\t%d\t%s\t%s\n%s\n@@PGTS@@\t%s\n", level[k], count[k], first_seen[k], last_seen[k], first_ts[k], last_ts[k], text[k], substr(timestamps[k], 2) >> records_file
                n = split(ctx[k], cl, "\n")
                for (j = 1; j < n; j++) printf "@@PGCTX@@\t%s\n", cl[j] >> records_file
            }
            cfg_end()
            for (i = 1; i <= ncfg; i++) {
                k = cfg_order[i]
                printf "@@PGCFG@@\t%s\n", cfg_head[k] >> records_file
                n = split(cfg_text[k], cl, "\n")
                for (j = 1; j < n; j++) printf "@@PGCFGL@@\t%s\n", cl[j] >> records_file
            }
            close(records_file)
        }
        if (nkeys == 0) {
            printf "✅ no %s record found in %d lines\n", (include_warnings == "" ? "ERROR/FATAL" : "ERROR/FATAL/WARN"), NR
            exit 0
        }
        printf "🔎 %d distinct record(s), %d occurrence(s), in %d lines\n", nkeys, total_occurrences, NR
        shown = 0
        split("FATAL ERROR WARN", severities, " ")
        for (s = 1; s <= 3; s++) {
            for (i = 1; i <= nkeys && shown < max_findings; i++) {
                k = order[i]
                if (level[k] != severities[s]) continue
                icon = (level[k] == "WARN") ? "🟠" : "🔴"
                printf "\n%s %s x%d (first seen line %d, last seen line %d)\n%s\n", icon, level[k], count[k], first_seen[k], last_seen[k], text[k]
                shown++
            }
        }
        if (shown < nkeys) printf "\n✂️ %d more distinct record(s) not shown, increase --max-findings or narrow with --since\n", nkeys - shown
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
        log "🔗 Open in browser: file://$report"
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

# HTML report of ccloud-costs-history / cloud-resources aws|azure costs-history (tools/cloud-costs/costs_report.py)
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

# Runs cfk-analysis (Docker image built on first use) on a CFK support bundle: prints the text digest and writes the
# HTML report in the output dir (opened in an interactive terminal), or prints the JSON on stdout.
# Used by playground analyze logs (CFK bundle detected) and its hidden alias playground analyze cfk-bundle.
# $1: bundle (directory or archive), $2: non-empty for --json, $3: non-empty for --no-sanitize, $4: minimal severity,
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

    # analyzer image: dependencies baked once, code mounted at run time. The tag changes when the Dockerfile or
    # requirements change, so the image is rebuilt only then
    local image_tag
    image_tag=$(cat "$analyzer_dir/Dockerfile" "$analyzer_dir/requirements.txt" | cksum | cut -d ' ' -f 1)
    local image="cfk-bundle-analyzer:$image_tag"
    if ! docker image inspect "$image" > /dev/null 2>&1
    then
        # stderr: stdout must stay valid JSON with --json
        log "🏗️  Building $image (first run only)..." >&2
        local build_log="/tmp/cfk-bundle-analyzer-build.log"
        if ! docker build --load -t "$image" "$analyzer_dir" > "$build_log" 2>&1 && ! docker build -t "$image" "$analyzer_dir" >> "$build_log" 2>&1
        then
            logerror "❌ Failed to build $image, see $build_log"
            tail -20 "$build_log" >&2
            return 1
        fi
    fi

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
        logwarn "⚠️  Sanitization DISABLED. Do not share this output for customer bundles." >&2
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
        html_out="${output_dir_abs}/${bundle_basename}-cfk-report-$(date '+%Y%m%d-%H%M%S').html"
        cli_args+=(--html-out "/tmp/output/$(basename "$html_out")")
        docker_args+=(-v "$output_dir_abs:/tmp/output")
    fi

    docker run "${docker_args[@]}" "$image" "${cli_args[@]}"
    local exit_code=$?
    case $exit_code in
        0) ;;
        64) logerror "❌ Analysis failed — invalid, unsafe or empty bundle (see error above)." ;;
        *) logerror "❌ Analyzer failed with exit code $exit_code." ;;
    esac

    if [[ $exit_code -eq 0 && -n "$html_out" && -f "$html_out" ]]
    then
        log ""
        open_html_report "$html_out"
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
# more than the script body or README.
# $1: query, $2: limit, $3: optional top-level category
function find_examples() {
    local query="$1"
    local limit="${2:-10}"
    local category="$3"
    local categories="connect ccloud ksqldb flink schema-registry rest-proxy multi-data-center other operator academy environment reproduction-models"

    if [[ -n "$category" ]]
    then
        categories="$category"
    fi

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
        | awk -v query="$query" -v root="$root_folder/" '
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
            if (score < 0 || nterms == 0) next
            # prefer the canonical variant of a family over its many derivatives
            score -= split(name, parts, "-") * 0.1

            printf "%.1f\t%s\t%s\t%s\t%s\n", score, rel, title, classes, env
        }' \
        | sort -t "$(printf '\t')" -k1,1nr -k2,2 \
        | head -n "$limit"
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

# copies jmxterm to the connect workers running the tasks of the connector
function benchmark_jmx_init() {
  local workers="$1"
  BENCHMARK_JMXTERM_JAR="/tmp/jmxterm-1.0.2-uber.jar"
  if [ ! -f "$BENCHMARK_JMXTERM_JAR" ]
  then
    curl -L https://github.com/jiaqi/jmxterm/releases/download/v1.0.2/jmxterm-1.0.2-uber.jar -o "$BENCHMARK_JMXTERM_JAR" -s
  fi
  local container port
  while read -r container port
  do
    [ -z "$container" ] && continue
    playground container cp --source "$BENCHMARK_JMXTERM_JAR" --destination "$container:$BENCHMARK_JMXTERM_JAR" > /dev/null 2>&1
  done <<< "$workers"
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
  local container port beans task_beans task_ids
  while read -r container port
  do
    [ -z "$container" ] && continue
    beans=$(printf 'beans -d kafka.connect\nbeans -d kafka.consumer\nbeans -d java.lang\nexit\n' | benchmark_jmxterm "$container" "$port" | grep -E "connector=$connector,task=|client-id=connector-consumer-$connector-[0-9]+,type=consumer-fetch-manager-metrics$|type=GarbageCollector" || true)
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
function benchmark_ccloud_topic_end_offsets () {
  local metadata topic query_args=()
  metadata=$(docker exec "$BENCHMARK_CCLOUD_KCAT_CONTAINER" kcat -F /tmp/configuration/ccloud.properties -L -J 2> /dev/null)
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
    offsets=$(docker exec "$BENCHMARK_CCLOUD_KCAT_CONTAINER" kcat -F /tmp/configuration/ccloud.properties -Q -J "${query_args[@]}" 2> /dev/null)
  fi
  for topic in "$@"
  do
    echo "$topic $(echo "$offsets" | jq -r --arg t "$topic" '[.[$t] // {} | to_entries[] | .value.offset? // empty | select(. >= 0)] | add // 0' 2> /dev/null || echo 0)"
  done
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

# "<sum of the committed offsets> <max lag>" of consumer group <group> ("0 -" when it has no committed offset yet)
function benchmark_ccloud_group_offsets () {
  local group="$1"
  docker exec "$BENCHMARK_CCLOUD_GROUPS_CONTAINER" bash -c "kafka-consumer-groups --bootstrap-server \$BOOTSTRAP_SERVERS --command-config /tmp/configuration/ccloud.properties --group '$group' --describe 2> /dev/null" \
    | awk '$4 ~ /^[0-9]+$/ { committed += $4; if ($6 ~ /^[0-9]+$/ && $6 > lag) lag = $6; n++ } END { printf "%d %s\n", committed, (n ? lag + 0 : "-") }'
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
# returns 1 if it could not be read
function get_connector_config_json () {
  local connector="$1" connector_type env_used
  connector_type=$(playground state get run.connector_type)
  env_used=$(playground state get run.environment)
  curl_output=""
  if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
  then
    get_ccloud_connect
    handle_ccloud_connect_rest_api "curl $security -s -X GET -H \"Content-Type: application/json\" \"https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector/config\" --header \"authorization: Basic $authorization\""
  elif [[ "$env_used" == cfk* ]]
  then
    # connector.class and tasks.max are not in spec.configs: they are spec.class and spec.taskMax of the CR
    curl_output=$(kubectl -n confluent get connector "$connector" -o json 2>/dev/null | jq -c 'select(.spec != null) | (.spec.configs // {}) + {"connector.class": .spec.class, "tasks.max": (.spec.taskMax // 1 | tostring)}' 2>/dev/null)
  else
    get_connect_url_and_security
    handle_onprem_connect_rest_api "curl $security -s -X GET -H \"Content-Type: application/json\" \"$connect_url/connectors/$connector/config\""
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
# carriage returns removed, then secrets masked:
#   - each value of the file $1 (one per line, see run_log_secret_values), and each part of a key:secret value
#   - the value of secret-looking keys: "password": "x" (json, python dict), password=x (properties, jdbc urls,
#     jaas), password: x (yaml), except ${...} config provider references
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
    # value of a secret-looking key: kept when it is not a secret (config provider reference, already masked, enum such
    # as USER_INFO, boolean, number), masked otherwise
    sub mask_value {
      my $v = shift;
      (my $u = $v) =~ s/^["\x27]|["\x27]$//g;
      return $v if $u eq "" || $u =~ /^\$\{/ || $u =~ /^\*+$/ || $u =~ /^[A-Z_]+$/ || $u =~ /^(?:true|false|null|none)$/i || $u =~ /^[0-9]+$/;
      $n++;
      return $v =~ /^(["\x27])/ ? "$1********$1" : "********";
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
      $line =~ s/((["\x27])$secret_key\2\s*:\s*)(["\x27])((?:\\.|(?!\3).)*)\3/$1 . $3 . mask_value($4) . $3/ge;
      $line =~ s/(?<![\w.\-])($secret_key\s*=\s*)("(?:\\.|[^"\\])*"|\x27[^\x27]*\x27|[^\s,;&"\x27)\]]+)/$1 . mask_value($2)/ge;
      $line =~ s/^(\s*(?:-\s+)?$secret_key:\s+)(\S.*)$/$1 . mask_value($2)/e;
      $n += ($line =~ s/\b(?:AKIA|ASIA)[0-9A-Z]{16}\b/********/g);
      $n += ($line =~ s/\beyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}/********/g);
      $n += ($line =~ s/\b(Bearer|Basic)\s+(?!\*{8})[A-Za-z0-9\-._~+\/]{8,}=*/$1 ********/g);
      $n += ($line =~ s/\b([a-z][a-z0-9+.\-]*:\/\/[^\s\/:@\x27"]+:)(?!\*{8}@)[^\s@\/\x27"]+@/$1********@/gi);
      $n += ($line =~ s/\b(?:gh[pousr]_[A-Za-z0-9]{30,}|xox[abprs]-[A-Za-z0-9\-]{10,}|AIza[0-9A-Za-z_\-]{35})/********/g);
      print $line;
    }
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
