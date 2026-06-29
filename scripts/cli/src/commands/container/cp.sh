source="${args[--source]}"
destination="${args[--destination]}"

get_environment_used

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
  kubectl cp "$resolved_source" "$resolved_destination" -n confluent
else
  log "🪄 Copying files with docker cp"
  docker cp "$resolved_source" "$resolved_destination"
fi