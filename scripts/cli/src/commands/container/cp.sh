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

extract_remote_pod_name() {
  local resolved_ref="$1"
  local pod_with_ns=""

  if [[ "$resolved_ref" != *:* ]]
  then
    return 1
  fi

  pod_with_ns="${resolved_ref%%:*}"
  if [[ "$pod_with_ns" == confluent/* ]]
  then
    echo "${pod_with_ns#confluent/}"
    return 0
  fi

  return 1
}

if [[ "$environment" == "cfk" ]]
then
  log "🪄 Copying files with kubectl cp"
  cp_remote_pod=""
  wait_status=0
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
  elif echo "$kubectl_cp_output" | grep -Eqi 'unable to upgrade connection: container not found|container not found'
  then
    cp_remote_pod=$(extract_remote_pod_name "$resolved_source" || true)
    if [[ -z "$cp_remote_pod" ]]
    then
      cp_remote_pod=$(extract_remote_pod_name "$resolved_destination" || true)
    fi

    if [[ -n "$cp_remote_pod" ]]
    then
      logwarn "⚠️ kubectl cp reported container not found for pod $cp_remote_pod; waiting for pod readiness and retrying"
      set +e
      kubectl -n confluent wait --for=condition=Ready "pod/$cp_remote_pod" --timeout=180s >/dev/null 2>&1
      wait_status=$?
      set -e

      if [[ "$wait_status" -eq 0 ]]
      then
        set +e
        kubectl_cp_output=$(kubectl cp "$resolved_source" "$resolved_destination" -n confluent 2>&1)
        kubectl_cp_status=$?
        set -e
      fi
    fi

    if [[ "$kubectl_cp_status" -eq 0 ]]
    then
      if [[ -n "$kubectl_cp_output" ]]
      then
        echo "$kubectl_cp_output"
      fi
    else
      cfk_stream_copy_fallback "$source" "$destination" "$resolved_source" "$resolved_destination"
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