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
function get_running_cp_tag() {
  local images
  local tag
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
  
  fzf_output=$(cat /tmp/get_any_files_with_fzf | fzf -i --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="📃" --header="select file" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer --print-query --bind "alt-enter:print-query")
  
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

  res=$(cat $root_folder/scripts/cli/$txt_file | sed '1!G;h;$!d' | fzf -i --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🎯" --header="select cp version" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer);echo "$cur@$res"
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

  filename="/tmp/version_$owner_$name"

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

  cat $filename | grep -v "documentation"| sed '1!G;h;$!d' | fzf -i --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🔢" --header="select connector version for $owner/$name" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer
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
  get_sr_url_and_security

  for i in {1..30}; do
    curl $sr_security -s "${sr_url}/config" > /dev/null 2>&1
    if [ $? == 0 ]; then
      break
    fi
    sleep 1
  done

  if [ $? != 0 ]; then
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
  for ((i=0; i<${#array_flag_list[@]}; i++))
  do
    if [[ ${array_flag_list[i]} == ${flag}=* ]]
    then
        unset "array_flag_list[i]"
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

  if [ -n "$ENABLE_KRAFT" ]
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
  nb_connectors=$(echo "$connectors" | grep -c . )
  nb_topics=$(echo "$topics" | grep -c . )
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

# Delete the Confluent Cloud connectors and topics created by the last ccloud 'playground run'
# (recorded with its run id in playground-ccloud-created-topics). Called by 'playground stop'
# and at the start of the next 'playground run', so interrupted examples don't leave billed
# connectors behind. Each run is handled once: deleted, or kept when the user says no.
# Behaviour: 'playground config cleanup-ccloud-resources-after-run ask|true|false' (default ask)
function maybe_cleanup_ccloud_run_resources () {
  if [ ! -z "$GITHUB_RUN_NUMBER" ]
  then
    # CI runs a full cleanup-cloud-resources
    return 0
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

resource "confluent_connector" "${connector_name}" {
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
    echo "$config_nonsensitive" | jq -r 'to_entries[] | "    \"\(.key)\" = \"\(.value)\""' >> "$output_file"

    # Add sensitive config parameters
    if [ "$(echo "$config_sensitive" | jq 'length')""%" != "0%" ]; then
        cat >> "$output_file" << 'EOF'
  }

  config_sensitive = {
EOF
        echo "$config_sensitive" | jq -r 'to_entries[] | "    \"\(.key)\" = \"\(.value)\""' >> "$output_file"
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
    sed -i.bak "s/\${connector_name}/${connector_name}/g" "$output_file"
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
    mkdir -p "$terraform_base_dir"
    terraform_dir=$(mktemp -d "$terraform_base_dir/${connector_name}-XXXXXXXXXX")
    log "📂 Terraform directory: $terraform_dir"

    local tf_file="${terraform_dir}/connector.tf"

    log "🏗️ Generating Terraform configuration for connector $connector_name"
    json_to_terraform_connector "$connector_name" "$json_content" "$tf_file" "$environment_id" "$cluster_id"

    if [ -z "$GITHUB_RUN_NUMBER" ]
    then
      log "📄 Generated Terraform configuration:"
      sed 's/^/    /' "$tf_file"
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
        (cd "$terraform_dir" && terraform show -no-color tfplan | grep -A 10 "Plan:")
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
function summarize_log_errors() {
    local max_findings="${1:-40}"
    local include_warnings="${2:-}"

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
    function flush(    lvl, key, i, chain, frames, nframes, line, cause) {
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
        nlines = 0
        if (key in count) {
            count[key]++
            last_seen[key] = rec_line
            return
        }
        count[key] = 1
        first_seen[key] = rec_line
        last_seen[key] = rec_line
        level[key] = lvl
        order[++nkeys] = key
        text[key] = short(rec[1]) chain frames
    }
    {
        gsub(/\033\[[0-9;]*m/, "")
        sub(/\r$/, "")
        if (!is_continuation($0) || nlines == 0 || nlines >= 400) {
            flush()
            rec_line = NR
        }
        rec[++nlines] = $0
    }
    END {
        flush()
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
  local workers="$1" connector_config_json="$2" test_file="$3" environment="$4"
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
  image=$(docker inspect -f '{{.Config.Image}}' "$first_worker" 2>/dev/null)
  image_arch=$(docker image inspect -f '{{.Architecture}}' "$image" 2>/dev/null)
  emulated=false
  case "$host_arch:$image_arch" in
    arm64:amd64|aarch64:amd64|x86_64:arm64|x86_64:aarch64) emulated=true ;;
  esac
  heap=$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$first_worker" 2>/dev/null | sed -n 's/^KAFKA_HEAP_OPTS=//p' | head -1)
  local jvm
  jvm=$(printf 'get -b java.lang:type=Runtime VmVersion\nget -b java.lang:type=OperatingSystem AvailableProcessors\nget -b java.lang:type=Memory HeapMemoryUsage\nexit\n' | benchmark_jmxterm "$first_worker" "$(echo "$workers" | head -1 | awk '{ print $2 }')")
  jvm_version=$(echo "$jvm" | sed -n 's/^VmVersion = \(.*\);$/\1/p')
  jvm_cpus=$(echo "$jvm" | sed -n 's/^AvailableProcessors = \(.*\);$/\1/p')
  # HeapMemoryUsage is a composite value: { committed = ...; init = ...; max = <bytes>; used = ...; }
  heap_max=$(echo "$jvm" | sed -n 's/^ *max = \([0-9]*\);$/\1/p' | head -1)
  nb_workers=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -c -E '^connect[0-9]*$')
  nb_brokers=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -c -E '^broker[0-9]*$')
  kraft=false
  docker ps --format '{{.Names}}' 2>/dev/null | grep -q -E '^controller[0-9]*$' && kraft=true
  commit=$(git -C "$root_folder" rev-parse --short HEAD 2>/dev/null)
  dirty=false
  [ -n "$(git -C "$root_folder" status --porcelain -uno 2>/dev/null)" ] && dirty=true
  # documentation of the connector: documentation_url of the manifest of the plugin that contains the connector class
  # (and source_url, for the links of the flight recorder hot methods)
  local connector_class documentation_url="" source_url="" plugin_dir manifest
  connector_class=$(echo "$connector_config_json" | jq -r '."connector.class" // empty' 2> /dev/null)
  if [ -n "$connector_class" ]
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
    --arg nb_workers "$nb_workers" --arg nb_brokers "$nb_brokers" --argjson kraft "$kraft" --arg environment "$environment" \
    --arg test_file "${test_file#$root_folder/}" --arg commit "$commit" --argjson dirty "$dirty" \
    --arg repo_url "$repo_url" --arg repo_path "$repo_path" --arg repo_commit "$repo_commit" --argjson repo_dirty "$repo_dirty" \
    --arg documentation_url "$documentation_url" --arg source_url "$source_url" --arg plugin_dir "$plugin_dir" \
    --argjson config "$(echo "$connector_config_json" | jq -c 'with_entries(if (.key | test("password|secret|token|credentials|jaas|private\\.key|api\\.key|apikey"; "i")) then .value = "****" else . end)' 2>/dev/null || echo '{}')" \
    '($engine_info | split("|")) as $e |
     {host: {os: $host_os, arch: $host_arch, cpu_model: $cpu_model, cpus: ($host_cpus | tonumber? // null), memory_bytes: ($host_memory | tonumber? // null)},
      engine: {name: $engine, version: $e[0], os: $e[1], cpus: ($e[2] | tonumber? // null), memory_bytes: ($e[3] | tonumber? // null)},
      connect: {image: $image, image_arch: $image_arch, emulated: $emulated, heap_opts: $heap, heap_max_bytes: ($heap_max | tonumber? // null), jvm_version: $jvm_version, jvm_cpus: ($jvm_cpus | tonumber? // null), workers: ($nb_workers | tonumber? // null)},
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
    "\(.host.os) \(.host.arch), \(.host.cpu_model) (\(.host.cpus) cpus, \(.host.memory_bytes | gib)) · \(.engine.name) \(.engine.version) \(.engine.os) (\(.engine.cpus) cpus, \(.engine.memory_bytes | gib)) · connect \(.connect.image | split("/") | last)\(if .connect.emulated then " EMULATED" else "" end), \(.connect.workers) worker(s), jvm \(.connect.jvm_version), heap \(.connect.heap_max_bytes | gib) max\(if .connect.heap_opts == "" then "" else " (" + .connect.heap_opts + ")" end) · \(.kafka.brokers) broker(s), \(.kafka.environment)"' 2>/dev/null
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
