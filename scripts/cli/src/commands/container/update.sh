containers="${args[--container]}"

get_environment_used

IFS=' ' read -ra container_array <<< "$containers"
if [[ "${#container_array[@]}" -eq 0 ]]
then
  logerror "❌ No container was provided"
  exit 1
fi

if [[ "${#container_array[@]}" -gt 1 ]]
then
  logwarn "⚠️ Multiple --container values provided, only the first one will be edited"
fi

container="${container_array[0]}"
resolved_container=$(resolve_container_name_for_environment "$container")

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
  trap 'rm -rf "$tmp_dir"' EXIT
else
  log "🐛📂 not deleting tmp dir $tmp_dir"
fi

edit_file="$tmp_dir/${resolved_container}.yaml"

if [[ "$environment" == "cfk" ]]
then
  resource_kind="pod"
  resource_name="$resolved_container"

  case "$resolved_container" in
    connect|connect-0|connect-1|connect-2|connect-3)
      resource_kind="connect"
      resource_name="connect"
      ;;
    controlcenter|controlcenter-0|control-center|control-center-0)
      resource_kind="controlcenter"
      resource_name="controlcenter"
      ;;
    schemaregistry|schemaregistry-0|schema-registry|schema-registry-0)
      resource_kind="schemaregistry"
      resource_name="schemaregistry"
      ;;
    kafka|kafka-0|broker|broker-0|controller|controller-0)
      resource_kind="kafka"
      resource_name="kafka"
      ;;
    ksqldb-server)
      resource_kind="deployment"
      resource_name="ksqldb-server"
      ;;
    restproxy)
      resource_kind="deployment"
      resource_name="restproxy"
      ;;
  esac

  log "✍️ Opening ${resource_kind}/${resource_name} for editing"
  kubectl -n confluent get "$resource_kind" "$resource_name" -o yaml > "$edit_file"

  if command -v yq >/dev/null 2>&1
  then
    yq -i 'del(.metadata.managedFields, .metadata.creationTimestamp, .metadata.resourceVersion, .metadata.uid, .metadata.generation, .metadata.annotations."kubectl.kubernetes.io/last-applied-configuration", .status)' "$edit_file"
  fi

  open_file_with_editor "$edit_file" "wait"

  set +e
  kubectl -n confluent apply -f "$edit_file"
  apply_exit_code=$?
  set -e

  if [[ "$apply_exit_code" -ne 0 ]] && [[ "$resource_kind" == "pod" ]]
  then
    logwarn "⚠️ Pod apply failed (likely immutable fields), trying force replace"
    kubectl -n confluent replace --force -f "$edit_file"
  elif [[ "$apply_exit_code" -ne 0 ]]
  then
    logerror "❌ Failed to apply changes for ${resource_kind}/${resource_name}"
    exit "$apply_exit_code"
  fi

  log "✅ Applied changes for ${resource_kind}/${resource_name}"
else
  docker_command=$(playground state get run.docker_command)
  if [ "$docker_command" == "" ]
  then
    logerror "docker_command retrieved from $root_folder/playground.ini is empty !"
    exit 1
  fi

  raw_file="$tmp_dir/${resolved_container}.raw"
  clean_file="$tmp_dir/${resolved_container}.clean.yaml"
  filtered_file="$tmp_dir/${resolved_container}.override.yaml"
  config_command=$(echo "$docker_command" | sed -E 's/up -d( --quiet-pull)?/config/g')
  set +e
  eval "$config_command \"$resolved_container\"" > "$raw_file" 2>&1
  config_exit_code=$?
  set -e

  if [[ "$config_exit_code" -ne 0 ]]
  then
    cat "$raw_file"
    exit "$config_exit_code"
  fi

  sed -E 's/\x1B\[[0-9;]*[A-Za-z]//g' "$raw_file" | awk '
    BEGIN { started=0 }
    {
      if (started == 0 && $0 ~ /^(name|services|volumes|networks|configs|secrets):/) {
        started=1
      }
      if (started == 1) {
        print
      }
    }
  ' > "$clean_file"

  awk -v target="$resolved_container" '
    BEGIN {
      in_services = 0
      in_target_service = 0
      found_target = 0
      printed_services_header = 0
    }
    {
      if ($0 ~ /^services:[[:space:]]*$/) {
        in_services = 1
        in_target_service = 0
        next
      }

      if (in_services == 1 && $0 ~ /^[^[:space:]]/) {
        in_services = 0
        in_target_service = 0
      }

      if (in_services == 1) {
        if ($0 ~ /^  [^[:space:]][^:]*:[[:space:]]*$/) {
          service_name = $0
          sub(/^  /, "", service_name)
          sub(/:.*/, "", service_name)
          if (service_name == target) {
            if (printed_services_header == 0) {
              print "services:"
              printed_services_header = 1
            }
            in_target_service = 1
            found_target = 1
            print
          } else {
            in_target_service = 0
          }
          next
        }

        if (in_target_service == 1) {
          print
        }
        next
      }
    }
    END {
      if (found_target == 0) {
        exit 42
      }
    }
  ' "$clean_file" > "$filtered_file"

  filter_exit_code=$?
  if [[ "$filter_exit_code" -eq 42 ]]
  then
    logerror "❌ Service $resolved_container is not present in generated docker compose config"
    cat "$clean_file"
    exit 1
  elif [[ "$filter_exit_code" -ne 0 ]]
  then
    logerror "❌ Could not post-process generated docker compose YAML for service $resolved_container"
    exit "$filter_exit_code"
  fi

  mv "$filtered_file" "$edit_file"

  if [[ ! -s "$edit_file" ]]
  then
    logerror "❌ Could not generate docker compose YAML for service $resolved_container"
    cat "$raw_file"
    exit 1
  fi

  log "✍️ Opening generated docker-compose for editing"
  open_file_with_editor "$edit_file" "wait"

  log "🔄 Applying docker-compose changes for service $resolved_container"
  apply_command="${docker_command/ up -d/ -f \"$edit_file\" up -d}"
  eval "$apply_command \"$resolved_container\""
  log "✅ Applied docker-compose changes"
fi

wait_container_ready
