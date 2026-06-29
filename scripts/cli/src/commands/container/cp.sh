source="${args[--source]}"
destination="${args[--destination]}"

get_environment_used

is_remote_ref() {
  local value="$1"
  [[ "$value" == *:* ]]
}

escape_single_quotes() {
  printf "%s" "$1" | sed "s/'/'\"'\"'/g"
}

cfk_stream_copy_fallback() {
  local original_source="$1"
  local original_destination="$2"
  local resolved_source_ref="$3"
  local resolved_destination_ref="$4"

  local source_is_remote=0
  local destination_is_remote=0
  local pod_with_ns=""
  local pod_name=""
  local remote_path=""
  local escaped_remote_path=""

  if is_remote_ref "$original_source"
  then
    source_is_remote=1
  fi

  if is_remote_ref "$original_destination"
  then
    destination_is_remote=1
  fi

  if [[ "$source_is_remote" -eq 0 && "$destination_is_remote" -eq 1 ]]
  then
    if [[ -d "$original_source" ]]
    then
      logerror "❌ CFK fallback copy does not support directory source: $original_source"
      return 1
    fi

    pod_with_ns="${resolved_destination_ref%%:*}"
    pod_name="${pod_with_ns#*/}"
    remote_path="${resolved_destination_ref#*:}"
    escaped_remote_path=$(escape_single_quotes "$remote_path")

    #logwarn "⚠️ kubectl cp requires tar in the target container, using stream fallback"
    kubectl -n confluent exec -i "$pod_name" -- sh -c "cat > '$escaped_remote_path'" < "$original_source"
    return $?
  fi

  if [[ "$source_is_remote" -eq 1 && "$destination_is_remote" -eq 0 ]]
  then
    pod_with_ns="${resolved_source_ref%%:*}"
    pod_name="${pod_with_ns#*/}"
    remote_path="${resolved_source_ref#*:}"
    escaped_remote_path=$(escape_single_quotes "$remote_path")

   # logwarn "⚠️ kubectl cp requires tar in the target container, using stream fallback"
    kubectl -n confluent exec -i "$pod_name" -- sh -c "cat '$escaped_remote_path'" > "$original_destination"
    return $?
  fi

  logerror "❌ CFK fallback copy only supports local<->pod file copies"
  return 1
}

transform_for_environment() {
  local value="$1"

  # local path, no container/pod prefix
  if [[ "$value" != *:* ]]
  then
    echo "$value"
    return
  fi

  local name="${value%%:*}"
  local path="${value#*:}"
  local resolved_name
  resolved_name=$(resolve_container_name_for_environment "$name")

  if [[ "$environment" == "cfk" ]]
  then
    echo "confluent/${resolved_name}:${path}"
  else
    echo "${resolved_name}:${path}"
  fi
}

resolved_source=$(transform_for_environment "$source")
resolved_destination=$(transform_for_environment "$destination")

if [[ "$environment" == "cfk" ]]
then
  log "🪄 Copying files with kubectl cp"
  set +e
  kubectl_cp_output=$(kubectl cp "$resolved_source" "$resolved_destination" -n confluent 2>&1)
  kubectl_cp_status=$?
  set -e

  if [[ "$kubectl_cp_status" -eq 0 ]]
  then
    if [[ -n "$kubectl_cp_output" ]]
    then
      echo "$kubectl_cp_output"
    fi
  elif echo "$kubectl_cp_output" | grep -Eqi 'exec: "tar"|tar: not found|executable file not found in \$PATH'
  then
    cfk_stream_copy_fallback "$source" "$destination" "$resolved_source" "$resolved_destination"
  else
    echo "$kubectl_cp_output"
    exit "$kubectl_cp_status"
  fi
else
  log "🪄 Copying files with docker cp"
  docker cp "$resolved_source" "$resolved_destination"
fi