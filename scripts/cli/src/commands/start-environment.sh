IGNORE_CHECK_FOR_DOCKER_COMPOSE=true

environment="${args[--environment]}"
docker_compose_override_file="${args[--docker-compose-override-file]}"
wait_for_control_center="${args[--wait-for-control-center]}"
no_stop="${args[--no-stop]}"
rbac_role_bindings_file="${args[--rbac-role-bindings-file]}"

if [ "$environment" = "ccloud" ]
then
  test_file="$root_folder/ccloud/environment/start.sh"
else
  test_file="$root_folder/environment/$environment/start.sh"
fi
test_file_directory="$(dirname "${test_file}")"

# a new environment invalidates any previous switch-ccloud, otherwise create-or-update
# and get-connector-list keep resolving the stale environment
playground state del run.environment_before_switch
playground state del run.connector_type_before_switch

if [[ ! -n "$no_stop" ]]
then
    set +e
    container_kill_all_before_run=$(playground config get container-kill-all-before-run)
    if [ "$container_kill_all_before_run" == "" ]
    then
        playground config set container-kill-all-before-run false
    fi

    if [ "$container_kill_all_before_run" == "true" ] || [ "$container_kill_all_before_run" == "" ]
    then
        log "💀 kill all docker containers (disable with 'playground config container-kill-all-before-run false')"
        playground container kill-all
    else
        playground stop
    fi
    set -e
fi

if [[ -n "$wait_for_control_center" ]]
then
  export WAIT_FOR_CONTROL_CENTER=1
fi

if [[ -n "$no_stop" ]]
then
  export NO_STOP=1
fi

if [[ -n "$rbac_role_bindings_file" ]]
then
  if [ "$environment" != "rbac-sasl-plain" ]
  then
    logerror "❌ --rbac-role-bindings-file only works with --environment rbac-sasl-plain (it is $environment)"
    exit 1
  fi
  export RBAC_ROLE_BINDINGS_FILE="$rbac_role_bindings_file"
fi

# Handle --service flag (can be passed multiple times)
services_list="${args[--service]}"
if [[ -n "$services_list" ]]
then
  eval "service_array=($services_list)"
  START_SERVICES="${service_array[*]}"
  export START_SERVICES
fi

# playground run --enable-multiple-connect-workers: connect2 and connect3 get the
# connect configuration of the example, in a generated copy of its override file,
# instead of editing the example's own file. Compose resolves relative paths from
# the first -f file, so the copy can live anywhere; it keeps the <folder>/<example>
# end of the path, which check_arm64_support relies on
if [ -n "$ENABLE_CONNECT_NODES" ] && [ "$environment" != "cfk" ] && [ -f "$docker_compose_override_file" ]
then
  example_dir="$(dirname "$docker_compose_override_file")"
  generated_override_dir="${PLAYGROUND_HOST_TMP_DIR:-/tmp}/playground-connect-workers/$(basename "$(dirname "$example_dir")")/$(basename "$example_dir")"
  mkdir -p "$generated_override_dir"
  generated_override_file="$generated_override_dir/$(basename "$docker_compose_override_file")"
  yq '.services.connect2 = (.services.connect // {}) | .services.connect3 = (.services.connect // {})' "$docker_compose_override_file" > "$generated_override_file"
  log "🥉 connect2 and connect3 use the connect configuration of $(basename "$docker_compose_override_file") (generated $generated_override_file)"
  docker_compose_override_file="$generated_override_file"
fi

cd $test_file_directory
if [ -f $docker_compose_override_file ]
then
  $test_file "$docker_compose_override_file"
else
  $test_file
fi

# playground run --connect-log-level: connect is ready, the example has not created its connector yet
apply_connect_log_levels
