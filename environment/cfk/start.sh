#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

check_bash_version
check_and_update_playground_version

verify_docker_and_memory
verify_installed "kubectl"
verify_installed "minikube"
verify_installed "helm"
verify_installed "envsubst"
verify_installed "zip"

: "${CP_SERVER_IMAGE:=confluentinc/cp-server}"
: "${CP_SERVER_TAG:=8.3.0}"
: "${CP_CONNECT_IMAGE:=confluentinc/cp-server-connect}"
: "${CP_CONNECT_TAG:=8.3.0}"
: "${CP_SCHEMA_REGISTRY_IMAGE:=confluentinc/cp-schema-registry}"
: "${CP_SCHEMA_REGISTRY_TAG:=8.3.0}"
: "${CP_CONTROL_CENTER_IMAGE:=confluentinc/cp-enterprise-control-center-next-gen}"
: "${CP_CONTROL_CENTER_TAG:=latest}"
: "${CP_INIT_IMAGE:=confluentinc/confluent-init-container}"
: "${CP_INIT_TAG:=3.0.0}"

export CP_SERVER_IMAGE CP_SERVER_TAG
export CP_CONNECT_IMAGE CP_CONNECT_TAG
export CP_SCHEMA_REGISTRY_IMAGE CP_SCHEMA_REGISTRY_TAG
export CP_CONTROL_CENTER_IMAGE CP_CONTROL_CENTER_TAG
export CP_INIT_IMAGE CP_INIT_TAG

function log_generated_yaml_file() {
  local label="$1"
  local file_path="$2"

  if [[ -z "$file_path" ]] || [[ ! -s "$file_path" ]]
  then
    return
  fi

  log "$label"
  sed 's/^/    /' "$file_path"
}

function run_with_timeout() {
  local timeout_seconds="$1"
  shift

  if command -v gtimeout >/dev/null 2>&1
  then
    gtimeout "$timeout_seconds" "$@"
    return $?
  fi

  if command -v timeout >/dev/null 2>&1
  then
    timeout "$timeout_seconds" "$@"
    return $?
  fi

  "$@" &
  local cmd_pid=$!
  local started_at=$SECONDS

  while kill -0 "$cmd_pid" >/dev/null 2>&1
  do
    if (( SECONDS - started_at >= timeout_seconds ))
    then
      # Stop direct child and likely descendants when coreutils timeout is unavailable.
      pkill -TERM -P "$cmd_pid" >/dev/null 2>&1 || true
      kill -TERM "$cmd_pid" >/dev/null 2>&1 || true
      sleep 2
      pkill -KILL -P "$cmd_pid" >/dev/null 2>&1 || true
      kill -KILL "$cmd_pid" >/dev/null 2>&1 || true
      wait "$cmd_pid" >/dev/null 2>&1 || true
      return 124
    fi
    sleep 1
  done

  wait "$cmd_pid"
  return $?
}

function generate_extra_pods_from_compose_override() {
  local compose_file="$1"
  local output_file="$2"
  local compose_dir=""
  local tmp_services_file
  local service_name=""
  local pod_name=""
  local container_name=""
  local image=""
  local platform=""
  local build_context=""
  local build_context_abs=""
  local auto_image=""
  local image_pull_policy="IfNotPresent"
  local env_list=""
  local ports_list=""
  local env_items=()
  local port_items=()
  local env_item=""
  local port_item=""
  local env_key=""
  local env_value=""
  local escaped_value=""
  local container_port=""
  local has_any_port=0
  local service_port_index=0
  local parsed_ports=()
  local host_image_exists=1
  local load_ret=1
  local save_ret=1
  local image_load_timeout_seconds=0
  local image_size_bytes=0
  local image_size_gb=0
  local tmp_image_tar=""
  local image_load_log=""

  if [[ ! -f "$compose_file" ]]
  then
    return 1
  fi

  compose_dir="$(cd "$(dirname "$compose_file")" && pwd)"

  tmp_services_file=$(mktemp)

  awk '
    function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
    function unquote(s) { gsub(/^"|"$/, "", s); gsub(/^\047|\047$/, "", s); return s }
    function flush_record() {
      if (service != "" && (image != "" || build_context != "") && service != "connect") {
        env_joined=""
        for (i = 1; i <= env_count; i++) {
          env_joined = env_joined (i > 1 ? ";" : "") envs[i]
        }
        ports_joined=""
        for (i = 1; i <= ports_count; i++) {
          ports_joined = ports_joined (i > 1 ? ";" : "") ports[i]
        }
        print service "|" image "|" build_context "|" platform "|" env_joined "|" ports_joined
      }
      service=""
      image=""
      platform=""
      build_context=""
      section=""
      env_count=0
      ports_count=0
      delete envs
      delete ports
    }

    BEGIN { in_services=0; service=""; image=""; platform=""; build_context=""; section=""; env_count=0; ports_count=0 }
    /^services:[[:space:]]*$/ { in_services=1; next }
    {
      if (in_services == 1 && $0 ~ /^[^[:space:]]/) {
        flush_record()
        in_services=0
      }
      if (in_services == 0) {
        next
      }
      if ($0 ~ /^  [A-Za-z0-9_.-]+:[[:space:]]*$/) {
        flush_record()
        service=$1
        sub(/:$/, "", service)
        next
      }

      if (service == "") {
        next
      }

      if ($0 ~ /^    image:[[:space:]]*/) {
        image=$0
        sub(/^    image:[[:space:]]*/, "", image)
        image=trim(unquote(image))
        section=""
        next
      }
      if ($0 ~ /^    platform:[[:space:]]*/) {
        platform=$0
        sub(/^    platform:[[:space:]]*/, "", platform)
        platform=trim(unquote(platform))
        section=""
        next
      }
      if ($0 ~ /^    build:[[:space:]]*$/) {
        section="build"
        next
      }
      if ($0 ~ /^    build:[[:space:]]*[^[:space:]].*$/) {
        build_context=$0
        sub(/^    build:[[:space:]]*/, "", build_context)
        build_context=trim(unquote(build_context))
        section=""
        next
      }
      if ($0 ~ /^    environment:[[:space:]]*$/) {
        section="environment"
        next
      }
      if ($0 ~ /^    ports:[[:space:]]*$/) {
        section="ports"
        next
      }
      if ($0 ~ /^    [A-Za-z0-9_.-]+:[[:space:]]*$/) {
        section=""
      }

      if (section == "build") {
        if ($0 ~ /^      context:[[:space:]]*/) {
          bc=$0
          sub(/^      context:[[:space:]]*/, "", bc)
          build_context=trim(unquote(bc))
          next
        }
      }

      if (section == "environment") {
        if ($0 ~ /^      -[[:space:]]*/) {
          entry=$0
          sub(/^      -[[:space:]]*/, "", entry)
          entry=trim(unquote(entry))
          if (entry != "") {
            envs[++env_count]=entry
          }
          next
        }
        if ($0 ~ /^      [A-Za-z_][A-Za-z0-9_]*:[[:space:]]*/) {
          kv=$0
          sub(/^      /, "", kv)
          key=kv
          sub(/:.*/, "", key)
          val=kv
          sub(/^[^:]+:[[:space:]]*/, "", val)
          val=trim(unquote(val))
          envs[++env_count]=key "=" val
          next
        }
      }

      if (section == "ports") {
        if ($0 ~ /^      -[[:space:]]*/) {
          p=$0
          sub(/^      -[[:space:]]*/, "", p)
          p=trim(unquote(p))
          if (p != "") {
            ports[++ports_count]=p
          }
          next
        }
      }
    }
    END { flush_record() }
  ' "$compose_file" > "$tmp_services_file"

  parse_compose_container_port() {
    local raw_port="$1"
    raw_port=$(echo "$raw_port" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
    raw_port="${raw_port%%/*}"
    if [[ "$raw_port" == *":"* ]]
    then
      raw_port="${raw_port##*:}"
    fi
    if [[ "$raw_port" == *"-"* ]]
    then
      raw_port="${raw_port%%-*}"
    fi
    if [[ "$raw_port" =~ ^[0-9]+$ ]]
    then
      echo "$raw_port"
    fi
  }

  : > "$output_file"
  while IFS='|' read -r service_name image build_context platform env_list ports_list
  do
    if [[ -z "$service_name" ]]
    then
      continue
    fi

    # Connect is managed by CFK Connect CR.
    if [[ "$service_name" == "connect" ]]
    then
      continue
    fi

    pod_name=$(echo "$service_name" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9.-]+/-/g' | sed -E 's/^-+//;s/-+$//')
    container_name="${pod_name}"

    image_pull_policy="IfNotPresent"

    if [[ -n "$image" ]]
    then
      image=$(echo "$image" | envsubst)
      if [[ -n "$platform" ]]
      then
        log "📦 Pulling image $image for platform $platform for service $service_name"
        docker pull --platform "$platform" "$image"
        image_pull_policy="Never"
      else
        # If the image is already local (or can be loaded from host), avoid registry pulls.
        if docker image inspect "$image" >/dev/null 2>&1
        then
          image_pull_policy="Never"
        else
          log "📦 Attempting to load local image $image into minikube for service $service_name"
          set +e
          # minikube image load must use host docker daemon (not minikube DOCKER_HOST).
          eval "$(minikube docker-env -u)" >/dev/null 2>&1
          docker image inspect "$image" >/dev/null 2>&1
          host_image_exists=$?
          if [[ "$host_image_exists" -eq 0 ]]
          then
            image_load_log="/tmp/minikube-image-load-${pod_name}.log"
            : > "$image_load_log"

            # Derive a practical timeout from image size unless explicitly set.
            image_size_bytes=$(docker image inspect "$image" --format '{{.Size}}' 2>/dev/null)
            if [[ ! "$image_size_bytes" =~ ^[0-9]+$ ]]
            then
              image_size_bytes=0
            fi
            image_size_gb=$(((image_size_bytes + 1073741823) / 1073741824))

            if [[ -n "$MINIKUBE_IMAGE_LOAD_TIMEOUT_SECONDS" ]]
            then
              image_load_timeout_seconds="$MINIKUBE_IMAGE_LOAD_TIMEOUT_SECONDS"
            else
              # 120s base + 180s per GiB, capped at 1h.
              image_load_timeout_seconds=$((120 + (image_size_gb * 180)))
              if (( image_load_timeout_seconds > 3600 ))
              then
                image_load_timeout_seconds=3600
              fi
            fi

            log "📦 Loading image $image into minikube (size ~${image_size_gb}GiB, timeout: ${image_load_timeout_seconds}s)"
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] source image: $image" >> "$image_load_log"
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] estimated size GiB: $image_size_gb" >> "$image_load_log"
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] timeout seconds: $image_load_timeout_seconds" >> "$image_load_log"

            tmp_image_tar=$(mktemp "/tmp/${pod_name}-image-XXXXXX.tar")
            run_with_timeout "$image_load_timeout_seconds" docker save -o "$tmp_image_tar" "$image" >> "$image_load_log" 2>&1
            save_ret=$?

            if [[ "$save_ret" -eq 0 ]]
            then
              eval "$(minikube docker-env)" >/dev/null 2>&1
              run_with_timeout "$image_load_timeout_seconds" docker load -i "$tmp_image_tar" >> "$image_load_log" 2>&1
              load_ret=$?
              eval "$(minikube docker-env -u)" >/dev/null 2>&1
            else
              load_ret="$save_ret"
            fi

            rm -f "$tmp_image_tar" >/dev/null 2>&1 || true
          else
            load_ret=1
          fi
          eval "$(minikube docker-env)" >/dev/null 2>&1
          set -e

          if [[ "$load_ret" -eq 0 ]]
          then
            image_pull_policy="Never"
            log "✅ Loaded image $image into minikube"
          elif [[ "$load_ret" -eq 124 ]]
          then
            logwarn "⚠️ Timed out after ${image_load_timeout_seconds}s while loading image $image into minikube"
            logwarn "⚠️ See /tmp/minikube-image-load-${pod_name}.log for details; Kubernetes may attempt registry pull"
          elif [[ "$host_image_exists" -ne 0 ]]
          then
            logwarn "⚠️ Image $image was not found in host docker daemon; Kubernetes may attempt registry pull"
          else
            logwarn "⚠️ Failed to load image $image into minikube (see /tmp/minikube-image-load-${pod_name}.log)"
          fi
        fi
      fi
    elif [[ -n "$build_context" ]]
    then
      build_context=$(echo "$build_context" | envsubst)
      if [[ "$build_context" = /* ]]
      then
        build_context_abs="$build_context"
      else
        build_context_abs="$compose_dir/$build_context"
      fi

      if [[ ! -d "$build_context_abs" ]]
      then
        logwarn "⚠️ Build context $build_context_abs for service $service_name does not exist, skipping pod"
        continue
      fi

      auto_image="local/${pod_name}-cfk:latest"
      log "🧱 Building image $auto_image for service $service_name from $build_context_abs"
      docker build -t "$auto_image" "$build_context_abs"
      image="$auto_image"
      image_pull_policy="Never"
    else
      continue
    fi

    if [[ -s "$output_file" ]]
    then
      echo "---" >> "$output_file"
    fi

    cat >> "$output_file" << EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${pod_name}
  namespace: confluent
  labels:
    app: ${pod_name}
spec:
  containers:
    - name: ${container_name}
      image: ${image}
      imagePullPolicy: ${image_pull_policy}
EOF

    if [[ -n "$env_list" ]]
    then
      echo "      env:" >> "$output_file"
      IFS=';' read -r -a env_items <<< "$env_list"
      for env_item in "${env_items[@]}"
      do
        if [[ -z "$env_item" ]]
        then
          continue
        fi

        if [[ "$env_item" == *"="* ]]
        then
          env_key="${env_item%%=*}"
          env_value="${env_item#*=}"
        else
          env_key="$env_item"
          env_value="${!env_key}"
        fi

        env_key=$(echo "$env_key" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
        escaped_value=$(printf '%s' "$env_value" | sed 's/\\/\\\\/g; s/"/\\"/g')
        if [[ -n "$env_key" ]]
        then
          {
            echo "        - name: ${env_key}"
            echo "          value: \"${escaped_value}\""
          } >> "$output_file"
        fi
      done
    fi

    has_any_port=0
    parsed_ports=()
    if [[ -n "$ports_list" ]]
    then
      IFS=';' read -r -a port_items <<< "$ports_list"
      for port_item in "${port_items[@]}"
      do
        container_port=$(parse_compose_container_port "$port_item")
        if [[ -n "$container_port" ]]
        then
          if [[ "$has_any_port" -eq 0 ]]
          then
            echo "      ports:" >> "$output_file"
            has_any_port=1
          fi
          parsed_ports+=("$container_port")
          echo "        - containerPort: ${container_port}" >> "$output_file"
        fi
      done
    fi

    # MySQL examples often omit explicit port mapping in compose overrides.
    # Create a Service on 3306 so hostname "mysql" resolves from Connect in CFK.
    if [[ "$has_any_port" -eq 0 ]] && [[ "$pod_name" == "mysql" ]]
    then
      parsed_ports=("3306")
      has_any_port=1
    fi

    # Hadoop NameNode examples often omit explicit port mapping in compose overrides.
    # Create a Service with common NameNode ports so hostname "namenode" resolves.
    if [[ "$has_any_port" -eq 0 ]] && [[ "$pod_name" == "namenode" ]]
    then
      parsed_ports=("8020" "9000" "50070" "9870")
      has_any_port=1
    fi

    if [[ "$has_any_port" -eq 1 ]]
    then
      echo "---" >> "$output_file"
      cat >> "$output_file" << EOF
apiVersion: v1
kind: Service
metadata:
  name: ${pod_name}
  namespace: confluent
spec:
  selector:
    app: ${pod_name}
  ports:
EOF
      service_port_index=1
      for container_port in "${parsed_ports[@]}"
      do
        {
          echo "    - name: port-${service_port_index}"
          echo "      port: ${container_port}"
          echo "      targetPort: ${container_port}"
        } >> "$output_file"
        ((service_port_index=service_port_index+1))
      done
    fi
  done < "$tmp_services_file"

  rm -f "$tmp_services_file"

  if [[ -s "$output_file" ]]
  then
    return 0
  fi

  return 1
}

function generate_connect_build_patch_from_compose() {
  local compose_file="$1"
  local output_file="$2"
  local connector_zip_url="$3"
  local connector_zip_checksum="$4"
  local connector_zip_plugin_name="$5"
  local connector_zip_dir="$6"
  local raw_paths=""
  local tmp_plugins_file
  local tmp_plugins_unique_file
  local tmp_confluent_hub_plugins_file
  local tmp_url_plugins_file
  local plugin_path=""
  local plugin_id=""
  local owner=""
  local name=""
  local version_value=""
  local local_plugin_dir=""
  local local_plugin_has_manifest=0
  local local_plugin_root=""
  local local_plugin_effective_dir=""
  local local_zip_path=""
  local local_zip_checksum=""
  local local_zip_url=""
  local has_confluent_hub_plugins=0
  local has_url_plugins=0
  local plugin_index=0
  local my_array_connector_tag=()
  local plugin_paths=()

  tmp_plugins_file=$(mktemp)
  tmp_plugins_unique_file=$(mktemp)
  tmp_confluent_hub_plugins_file=$(mktemp)
  tmp_url_plugins_file=$(mktemp)

  if [[ -n "$CONNECTOR_TAG" ]]
  then
    IFS=',' read -r -a my_array_connector_tag <<< "$CONNECTOR_TAG"
  fi

  if [[ -f "$compose_file" ]]
  then
    while IFS= read -r raw_paths
    do
      raw_paths=$(echo "$raw_paths" | sed -E 's/.*CONNECT_PLUGIN_PATH[[:space:]]*:[[:space:]]*//')
      raw_paths=$(echo "$raw_paths" | sed -E 's/["\x27]//g' | sed -E 's/[[:space:]]+#.*$//')

      IFS=',' read -r -a plugin_paths <<< "$raw_paths"
      for plugin_path in "${plugin_paths[@]}"
      do
        plugin_path=$(echo "$plugin_path" | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//')
        if [[ "$plugin_path" != *"/usr/share/confluent-hub-components/"* ]]
        then
          continue
        fi

        plugin_id="${plugin_path##*/usr/share/confluent-hub-components/}"
        plugin_id="${plugin_id%/}"
        if [[ -z "$plugin_id" ]]
        then
          continue
        fi

        owner="${plugin_id%%-*}"
        name="${plugin_id#*-}"
        if [[ -z "$owner" ]] || [[ -z "$name" ]] || [[ "$owner" == "$plugin_id" ]]
        then
          continue
        fi

        echo "$owner|$name|$plugin_id" >> "$tmp_plugins_file"
      done
    done < <(grep -E 'CONNECT_PLUGIN_PATH[[:space:]]*:' "$compose_file" 2>/dev/null)
  fi

  if [[ -s "$tmp_plugins_file" ]]
  then
    awk '!seen[$0]++' "$tmp_plugins_file" > "$tmp_plugins_unique_file"
    while IFS='|' read -r owner name plugin_id
    do
      if [[ -n "$CONNECTOR_TAG" ]]
      then
        version_value="${my_array_connector_tag[$plugin_index]}"
        if [[ -z "$version_value" ]]
        then
          logwarn "CONNECTOR_TAG (--connector-tag option) was not set for element $plugin_index, setting it to latest"
          version_value="latest"
        fi
      else
        version_value="latest"
        logwarn "⚠️ CONNECTOR_TAG is not set, using plugin version latest for $owner/$name"
      fi

      local_plugin_dir="${DIR}/../../confluent-hub/${plugin_id}"
      if [[ -n "$connector_zip_dir" ]] && [[ -d "$local_plugin_dir" ]] && [[ -n "$(find "$local_plugin_dir" -type f -print -quit 2>/dev/null)" ]]
      then
        local_plugin_effective_dir="$local_plugin_dir"
        local_plugin_has_manifest=0
        if [[ -f "$local_plugin_dir/manifest.json" ]]
        then
          local_plugin_has_manifest=1
        fi

        if [[ "$local_plugin_has_manifest" -ne 1 ]]
        then
          local_plugin_root=$(mktemp -d)
          log "🔧 Local override for $plugin_id is partial, installing base $owner/$name:$version_value before packaging"
          if ! docker run -u0 -i --rm -v "$local_plugin_root:/usr/share/confluent-hub-components" ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} bash -c "confluent-hub install --no-prompt $owner/$name:$version_value && chown -R $(id -u $USER):$(id -g $USER) /usr/share/confluent-hub-components"
          then
            logwarn "⚠️ Could not prepare base plugin for local override $plugin_id, falling back to Confluent Hub install"
            rm -rf "$local_plugin_root"
            echo "$owner|$name|$version_value" >> "$tmp_confluent_hub_plugins_file"
            has_confluent_hub_plugins=1
            ((plugin_index=plugin_index+1))
            continue
          fi

          if [[ ! -d "$local_plugin_root/$plugin_id" ]]
          then
            logwarn "⚠️ Base plugin directory $plugin_id was not created, falling back to Confluent Hub install"
            rm -rf "$local_plugin_root"
            echo "$owner|$name|$version_value" >> "$tmp_confluent_hub_plugins_file"
            has_confluent_hub_plugins=1
            ((plugin_index=plugin_index+1))
            continue
          fi

          cp -R "$local_plugin_dir/." "$local_plugin_root/$plugin_id/"
          local_plugin_effective_dir="$local_plugin_root/$plugin_id"
        fi

        local_zip_path="$connector_zip_dir/${plugin_id}.zip"
        rm -f "$local_zip_path"
        (
          cd "$(dirname "$local_plugin_effective_dir")"
          zip -qr "$local_zip_path" "$(basename "$local_plugin_effective_dir")"
        )
        local_zip_checksum=$(shasum -a 512 "$local_zip_path" | awk '{print $1}')
        local_zip_url="http://host.minikube.internal:18080/${plugin_id}.zip"
        echo "${plugin_id}|${local_zip_url}|${local_zip_checksum}" >> "$tmp_url_plugins_file"
        has_url_plugins=1
        log "🔌 Using local plugin override for $plugin_id in CFK build"

        if [[ -n "$local_plugin_root" ]] && [[ -d "$local_plugin_root" ]]
        then
          rm -rf "$local_plugin_root"
        fi
        local_plugin_root=""
      else
        echo "$owner|$name|$version_value" >> "$tmp_confluent_hub_plugins_file"
        has_confluent_hub_plugins=1
      fi

      ((plugin_index=plugin_index+1))
    done < "$tmp_plugins_unique_file"
  fi

  if [[ -n "$connector_zip_url" ]] && [[ -n "$connector_zip_checksum" ]]
  then
    has_url_plugins=1
  fi

  if [[ "$has_confluent_hub_plugins" -ne 1 ]] && [[ "$has_url_plugins" -ne 1 ]]
  then
    rm -f "$tmp_plugins_file" "$tmp_plugins_unique_file" "$tmp_confluent_hub_plugins_file" "$tmp_url_plugins_file"
    return 1
  fi

  cat > "$output_file" << EOF
spec:
  build:
    type: onDemand
    onDemand:
      plugins:
EOF

  if [[ "$has_confluent_hub_plugins" -eq 1 ]]
  then
    echo "        confluentHub:" >> "$output_file"
    while IFS='|' read -r owner name version_value
    do
      {
        printf '          - name: %s\n' "$name"
        printf '            owner: %s\n' "$owner"
        printf '            version: %s\n' "$version_value"
      } >> "$output_file"
    done < "$tmp_confluent_hub_plugins_file"
  fi

  if [[ "$has_url_plugins" -eq 1 ]]
  then
    echo "        url:" >> "$output_file"

    if [[ -n "$connector_zip_url" ]] && [[ -n "$connector_zip_checksum" ]]
    then
      if [[ -z "$connector_zip_plugin_name" ]]
      then
        connector_zip_plugin_name="custom-zip-plugin"
      fi
      {
        printf '          - name: %s\n' "$connector_zip_plugin_name"
        printf '            archivePath: %s\n' "$connector_zip_url"
        printf '            checksum: %s\n' "$connector_zip_checksum"
      } >> "$output_file"
    fi

    if [[ -s "$tmp_url_plugins_file" ]]
    then
      while IFS='|' read -r plugin_id local_zip_url local_zip_checksum
      do
        {
          printf '          - name: %s\n' "$plugin_id"
          printf '            archivePath: %s\n' "$local_zip_url"
          printf '            checksum: %s\n' "$local_zip_checksum"
        } >> "$output_file"
      done < "$tmp_url_plugins_file"
    fi
  fi

  rm -f "$tmp_plugins_file" "$tmp_plugins_unique_file" "$tmp_confluent_hub_plugins_file" "$tmp_url_plugins_file"
  return 0
}

DOCKER_COMPOSE_FILE_OVERRIDE=$1
if [ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]
then
  check_arm64_support "${DIR}" "${DOCKER_COMPOSE_FILE_OVERRIDE}"
fi
set_profiles

CONNECT_BUILD_PATCH_FILE=""
CONNECTOR_ZIP_URL=""
CONNECTOR_ZIP_CHECKSUM=""
CONNECTOR_ZIP_PLUGIN_NAME=""
CONNECTOR_ZIP_DIR=""
CONNECTOR_ZIP_SERVER_PID=""
EXTRA_PODS_FILE=""

function reset_cfk_namespace_state() {
  local namespace="confluent"
  local reset_mode="${CFK_NAMESPACE_RESET_MODE:-namespace}"
  local pv_list=""
  local pv_name=""
  local namespace_exists=1
  local namespace_phase=""
  local resource_name=""
  local force_finalize_file=""
  local wait_attempt=0

  log "🧹 Reset Kubernetes namespace $namespace for a clean run (mode: $reset_mode)"

  set +e
  kubectl get namespace "$namespace" >/dev/null 2>&1
  namespace_exists=$?
  set -e

  if [[ "$namespace_exists" -ne 0 ]]
  then
    kubectl create namespace "$namespace" >/dev/null
    kubectl config set-context --current --namespace="$namespace" >/dev/null
    return
  fi

  namespace_phase=$(kubectl get namespace "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null || true)
  if [[ "$namespace_phase" == "Terminating" ]]
  then
    logwarn "⚠️ Namespace $namespace is stuck terminating; force-clearing finalizers"

    set +e

    # Strip finalizers from all namespaced resources
    local all_resource_type=""
    local all_resource_name=""
    while IFS= read -r all_resource_type
    do
      if [[ -z "$all_resource_type" ]]; then continue; fi
      while IFS= read -r all_resource_name
      do
        if [[ -z "$all_resource_name" ]]; then continue; fi
        kubectl -n "$namespace" patch "$all_resource_type" "$all_resource_name" \
          --type=merge -p '{"metadata":{"finalizers":[]}}' >/dev/null 2>&1 || true
      done < <(kubectl -n "$namespace" get "$all_resource_type" \
          -o jsonpath='{range .items[?(@.metadata.finalizers)]}{.metadata.name}{"\n"}{end}' 2>/dev/null)
    done < <(kubectl api-resources --namespaced=true -o name 2>/dev/null)

    # Strip namespace-level finalizers via the finalize API
    local force_finalize_file
    force_finalize_file=$(mktemp)
    if kubectl get namespace "$namespace" -o json > "$force_finalize_file" 2>/dev/null
    then
      sed -E 's/"finalizers"[[:space:]]*:[[:space:]]*\[[^]]*\]/"finalizers": []/g' "$force_finalize_file" > "${force_finalize_file}.patched"
      kubectl replace --raw "/api/v1/namespaces/${namespace}/finalize" -f "${force_finalize_file}.patched" >/dev/null 2>&1 || true
      rm -f "$force_finalize_file" "${force_finalize_file}.patched"
    fi

    # Wait briefly for namespace to delete (should be quick now that finalizers are gone)
    for wait_attempt in {1..10}
    do
      kubectl get namespace "$namespace" >/dev/null 2>&1
      namespace_exists=$?
      if [[ "$namespace_exists" -ne 0 ]]; then break; fi
      sleep 1
    done
    set -e

    set +e
    kubectl get namespace "$namespace" >/dev/null 2>&1
    namespace_exists=$?
    set -e

    if [[ "$namespace_exists" -eq 0 ]]
    then
      logerror "❌ Namespace $namespace still exists after finalizer stripping"
      exit 1
    fi

    log "✅ Namespace $namespace recovered (finalizers cleared, namespace deleted)"
    kubectl create namespace "$namespace" >/dev/null
    kubectl config set-context --current --namespace="$namespace" >/dev/null
    return
  fi

  if [[ "$reset_mode" == "namespace" ]]
  then
    log "🔁 Hard reset requested: force-deleting namespace $namespace"

    set +e

    # Kick off a regular delete (may hang if finalizers present, that's fine — we fix it next)
    kubectl delete namespace "$namespace" --ignore-not-found=true --wait=false >/dev/null 2>&1 || true

    # Repeatedly clear finalizers from all namespaced resources + namespace itself.
    # This mirrors manual recovery commands and is resilient to CFK resources reappearing.
    local ns_json_file
    local all_resource_type=""
    local all_resource_name=""
    local cfk_resource_type=""
    local clear_pass=0
    for clear_pass in {1..4}
    do
      log "  Stripping resource finalizers (pass ${clear_pass}/4)..."

      # Generic pass over every namespaced resource type.
      while IFS= read -r all_resource_type
      do
        if [[ -z "$all_resource_type" ]]; then continue; fi
        while IFS= read -r all_resource_name
        do
          if [[ -z "$all_resource_name" ]]; then continue; fi
          kubectl -n "$namespace" patch "$all_resource_type" "$all_resource_name" \
            --type=merge -p '{"metadata":{"finalizers":[]}}' >/dev/null 2>&1 || true
        done < <(kubectl -n "$namespace" get "$all_resource_type" --no-headers 2>/dev/null | awk '{print $1}')
      done < <(kubectl api-resources --verbs=list --namespaced=true -o name 2>/dev/null)

      # Explicit CFK pass (same intent as the manual command shared by user).
      while IFS= read -r cfk_resource_type
      do
        if [[ -z "$cfk_resource_type" ]]; then continue; fi
        while IFS= read -r all_resource_name
        do
          if [[ -z "$all_resource_name" ]]; then continue; fi
          kubectl -n "$namespace" patch "$cfk_resource_type" "$all_resource_name" \
            --type=merge -p '{"metadata":{"finalizers":[]}}' >/dev/null 2>&1 || true
        done < <(kubectl -n "$namespace" get "$cfk_resource_type" --no-headers 2>/dev/null | awk '{print $1}')
      done < <(kubectl api-resources --api-group=platform.confluent.io --verbs=list --namespaced=true -o name 2>/dev/null)

      # Namespace-level finalize call.
      ns_json_file=$(mktemp)
      if kubectl get namespace "$namespace" -o json > "$ns_json_file" 2>/dev/null
      then
        sed -E 's/"finalizers"[[:space:]]*:[[:space:]]*\[[^]]*\]/"finalizers": []/g' "$ns_json_file" > "${ns_json_file}.patched"
        kubectl replace --raw "/api/v1/namespaces/${namespace}/finalize" -f "${ns_json_file}.patched" >/dev/null 2>&1 || true
      fi
      rm -f "$ns_json_file" "${ns_json_file}.patched" >/dev/null 2>&1 || true

      kubectl get namespace "$namespace" >/dev/null 2>&1
      if [[ "$?" -ne 0 ]]
      then
        break
      fi
      sleep 2
    done

    # Wait for the namespace to fully disappear
    local ns_wait=0
    while kubectl get namespace "$namespace" >/dev/null 2>&1
    do
      ns_wait=$(( ns_wait + 1 ))
      if [[ "$ns_wait" -ge 120 ]]; then
        logerror "❌ Namespace $namespace still exists after 120s"
        logerror "❌ Remaining namespace details (status + finalizers):"
        kubectl get namespace "$namespace" -o yaml | sed -n '1,160p' || true
        logerror "❌ Remaining CFK resources in namespace (if any):"
        kubectl -n "$namespace" get $(kubectl api-resources --api-group=platform.confluent.io --verbs=list --namespaced=true -o name 2>/dev/null | tr '\n' ',' | sed 's/,$//') 2>/dev/null || true
        exit 1
      fi
      sleep 1
    done

    set -e

    # Recreate clean namespace
    kubectl create namespace "$namespace" >/dev/null
    kubectl config set-context --current --namespace="$namespace" >/dev/null
    return
  fi

  # Fast reset: keep namespace, remove operator release and namespaced resources.
  set +e
  helm -n "$namespace" uninstall confluent-operator >/dev/null 2>&1 || true

  kubectl -n "$namespace" delete \
    pods,services,deployments,statefulsets,daemonsets,replicasets,jobs,cronjobs,ingresses,networkpolicies,configmaps,secrets,serviceaccounts,roles,rolebindings,persistentvolumeclaims \
    --all --ignore-not-found=true >/dev/null 2>&1 || true

  while IFS= read -r resource_name
  do
    if [[ -n "$resource_name" ]]
    then
      kubectl -n "$namespace" delete "$resource_name" --all --ignore-not-found=true >/dev/null 2>&1 || true
    fi
  done < <(kubectl api-resources --api-group=platform.confluent.io --namespaced -o name 2>/dev/null)
  set -e

  # Some storage classes keep PVs after PVC deletion; remove them to avoid data leakage across runs.
  pv_list=$(kubectl get pv -o jsonpath='{range .items[?(@.spec.claimRef.namespace=="confluent")]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
  if [[ -n "$pv_list" ]]
  then
    while IFS= read -r pv_name
    do
      if [[ -n "$pv_name" ]]
      then
        log "🗑 Deleting retained PV $pv_name"
        kubectl delete pv "$pv_name" --ignore-not-found=true >/dev/null 2>&1 || true
      fi
    done <<< "$pv_list"
  fi

  kubectl config set-context --current --namespace="$namespace" >/dev/null
}

if [[ -n "$CONNECTOR_ZIP" ]]
then
  if [[ "$CONNECTOR_ZIP" =~ ^https?:// ]]
  then
    verify_installed "curl"
    tmp_connector_zip_download=$(mktemp)
    if ! curl -fsSL "$CONNECTOR_ZIP" -o "$tmp_connector_zip_download"
    then
      logerror "❌ Could not download CONNECTOR_ZIP URL $CONNECTOR_ZIP"
      exit 1
    fi
    CONNECTOR_ZIP_URL="$CONNECTOR_ZIP"
    CONNECTOR_ZIP_CHECKSUM=$(shasum -a 512 "$tmp_connector_zip_download" | awk '{print $1}')
    rm -f "$tmp_connector_zip_download"
    CONNECTOR_ZIP_PLUGIN_NAME=$(basename "$CONNECTOR_ZIP")
    CONNECTOR_ZIP_PLUGIN_NAME="${CONNECTOR_ZIP_PLUGIN_NAME%.zip}"
  else
    if [[ ! -f "$CONNECTOR_ZIP" ]]
    then
      logerror "❌ CONNECTOR_ZIP $CONNECTOR_ZIP does not exist"
      exit 1
    fi
    verify_installed "python3"
    CONNECTOR_ZIP_DIR=$(mktemp -d)
    connector_zip_basename=$(basename "$CONNECTOR_ZIP")
    cp "$CONNECTOR_ZIP" "$CONNECTOR_ZIP_DIR/$connector_zip_basename"
    CONNECTOR_ZIP_URL="http://host.minikube.internal:18080/$connector_zip_basename"
    CONNECTOR_ZIP_CHECKSUM=$(shasum -a 512 "$CONNECTOR_ZIP" | awk '{print $1}')
    CONNECTOR_ZIP_PLUGIN_NAME="${connector_zip_basename%.zip}"
  fi

  if [[ -z "$CONNECTOR_ZIP_PLUGIN_NAME" ]] || [[ "$CONNECTOR_ZIP_PLUGIN_NAME" == "" ]]
  then
    CONNECTOR_ZIP_PLUGIN_NAME="custom-zip-plugin"
  fi
fi

if [[ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]]
then
  if [[ -z "$CONNECTOR_ZIP_DIR" ]]
  then
    CONNECTOR_ZIP_DIR=$(mktemp -d)
  fi
  CONNECT_BUILD_PATCH_FILE=$(mktemp)
  if generate_connect_build_patch_from_compose "${DOCKER_COMPOSE_FILE_OVERRIDE}" "${CONNECT_BUILD_PATCH_FILE}" "$CONNECTOR_ZIP_URL" "$CONNECTOR_ZIP_CHECKSUM" "$CONNECTOR_ZIP_PLUGIN_NAME" "$CONNECTOR_ZIP_DIR"
  then
    log "🔌 CFK Connect build plugins will be patched dynamically"
    log_generated_yaml_file "Dynamic Connect build patch generated:" "${CONNECT_BUILD_PATCH_FILE}"
  else
    rm -f "${CONNECT_BUILD_PATCH_FILE}"
    CONNECT_BUILD_PATCH_FILE=""
  fi
elif [[ -n "$CONNECTOR_ZIP_URL" ]] && [[ -n "$CONNECTOR_ZIP_CHECKSUM" ]]
then
  if [[ -z "$CONNECTOR_ZIP_DIR" ]]
  then
    CONNECTOR_ZIP_DIR=$(mktemp -d)
  fi
  CONNECT_BUILD_PATCH_FILE=$(mktemp)
  if ! generate_connect_build_patch_from_compose "" "${CONNECT_BUILD_PATCH_FILE}" "$CONNECTOR_ZIP_URL" "$CONNECTOR_ZIP_CHECKSUM" "$CONNECTOR_ZIP_PLUGIN_NAME" "$CONNECTOR_ZIP_DIR"
  then
    rm -f "${CONNECT_BUILD_PATCH_FILE}"
    CONNECT_BUILD_PATCH_FILE=""
  else
    log_generated_yaml_file "Dynamic Connect build patch generated:" "${CONNECT_BUILD_PATCH_FILE}"
  fi
fi

log "Start or reuse minikube"
minikube_status_output="$(minikube status --profile=minikube 2>/dev/null || true)"
if echo "$minikube_status_output" | grep -q "host: Running" && \
   echo "$minikube_status_output" | grep -q "kubelet: Running" && \
   echo "$minikube_status_output" | grep -q "apiserver: Running"
then
  log "✅ Minikube is already running, skipping start"
else
  minikube start --cpus=8 --disk-size='50gb' --memory=16384
fi

if [[ -n "$CONNECTOR_ZIP_DIR" ]] && [[ -n "$(find "$CONNECTOR_ZIP_DIR" -maxdepth 1 -name '*.zip' -print -quit 2>/dev/null)" ]]
then
  log "Serve local CONNECTOR_ZIP for CFK on-demand plugin download"

  # Avoid stale listeners from previous runs serving the wrong directory on 18080.
  set +e
  lsof -i ":18080" 2>/dev/null | awk 'NR>1 {print $2}' | xargs kill -9 2>/dev/null || true
  set -e

  python3 -m http.server 18080 --directory "$CONNECTOR_ZIP_DIR" >/tmp/cfk-connector-zip-http.log 2>&1 &
  CONNECTOR_ZIP_SERVER_PID=$!

  # Fail fast if server did not start or expected zip is not served.
  sleep 1
  if ! kill -0 "$CONNECTOR_ZIP_SERVER_PID" >/dev/null 2>&1
  then
    logerror "❌ Could not start local CONNECTOR_ZIP HTTP server on port 18080"
    cat /tmp/cfk-connector-zip-http.log | tail -30 || true
    exit 1
  fi

  local_served_zip=$(find "$CONNECTOR_ZIP_DIR" -maxdepth 1 -name '*.zip' -print -quit 2>/dev/null)
  if [[ -n "$local_served_zip" ]]
  then
    local_served_zip_name=$(basename "$local_served_zip")
    if ! curl -fsS "http://127.0.0.1:18080/${local_served_zip_name}" >/dev/null 2>&1
    then
      logerror "❌ Local CONNECTOR_ZIP HTTP server is up but ${local_served_zip_name} is not downloadable"
      cat /tmp/cfk-connector-zip-http.log | tail -30 || true
      exit 1
    fi
    log "✅ Local plugin archive is served at http://host.minikube.internal:18080/${local_served_zip_name}"
  fi
fi

log "Build images in minikube docker daemon"
eval $(minikube docker-env)

# Build/patch CP images in minikube daemon so CFK pods can use them.
maybe_create_image

if [[ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]]
then
  EXTRA_PODS_FILE=$(mktemp)
  if ! generate_extra_pods_from_compose_override "${DOCKER_COMPOSE_FILE_OVERRIDE}" "${EXTRA_PODS_FILE}"
  then
    rm -f "${EXTRA_PODS_FILE}"
    EXTRA_PODS_FILE=""
  else
    log_generated_yaml_file "Dynamic extra pods manifest generated:" "${EXTRA_PODS_FILE}"
  fi
fi

reset_cfk_namespace_state

log "Add the Confluent for Kubernetes Helm repository"
if ! helm repo list | awk 'NR>1 {print $1}' | grep -qx "confluentinc"
then
  helm repo add confluentinc https://packages.confluent.io/helm
fi
helm repo update confluentinc

log "Install Confluent for Kubernetes"
helm upgrade --install confluent-operator confluentinc/confluent-for-kubernetes

log "Deploy Confluent Platform"
envsubst '${CP_SERVER_IMAGE} ${CP_SERVER_TAG} ${CP_CONNECT_IMAGE} ${CP_CONNECT_TAG} ${CP_SCHEMA_REGISTRY_IMAGE} ${CP_SCHEMA_REGISTRY_TAG} ${CP_CONTROL_CENTER_IMAGE} ${CP_CONTROL_CENTER_TAG} ${CP_INIT_IMAGE} ${CP_INIT_TAG}' < "${DIR}/confluent-platform.yaml" | kubectl apply -f -

if [[ -n "$EXTRA_PODS_FILE" ]] && [[ -s "$EXTRA_PODS_FILE" ]]
then
  log "Deploy extra pods from DOCKER_COMPOSE_FILE_OVERRIDE (excluding connect)"
  kubectl -n confluent apply -f "$EXTRA_PODS_FILE"
fi

if [[ -n "$CONNECT_BUILD_PATCH_FILE" ]] && [[ -s "$CONNECT_BUILD_PATCH_FILE" ]]
then
  log "Patch Connect build plugins from CONNECT_PLUGIN_PATH"
  patched_connect_build=0
  set +e
  for _ in {1..30}
  do
    kubectl -n confluent patch connect connect --type merge --patch-file "$CONNECT_BUILD_PATCH_FILE" > /dev/null 2>&1
    if [[ $? -eq 0 ]]
    then
      patched_connect_build=1
      break
    fi
    sleep 2
  done
  if [[ "$patched_connect_build" -ne 1 ]]
  then
    logerror "❌ Could not patch connect/connect build plugins in CFK"
    exit 1
  fi
  set -e

  # The Connect CR may have already scheduled a pod before the build patch was
  # processed.  Force-delete connect-0 so CFK recreates it from the updated
  # spec, which now includes the on-demand build init container.
  log "🔄 Restarting connect-0 to ensure on-demand build spec takes effect"
  kubectl -n confluent delete pod connect-0 --ignore-not-found=true >/dev/null 2>&1 || true
fi

wait_container_ready

# When an on-demand build patch is applied, the Connect pod becomes Kubernetes-ready
# while CFK is still downloading and installing plugins asynchronously.
# Wait until the Connect CR's appState reaches "Running" to ensure plugins are loaded.
if [[ -n "$CONNECT_BUILD_PATCH_FILE" ]]
then
  log "⏳ Waiting for Connect on-demand build plugins to appear via REST API..."
  set +e
  connect_build_wait_max=300
  connect_build_cur_wait=0
  connect_build_interval=10
  while true
  do
    connect_plugin_count=$(kubectl -n confluent exec connect-0 -- curl -s http://localhost:8083/connector-plugins 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d))" 2>/dev/null || echo "0")
    if [[ "$connect_plugin_count" =~ ^[0-9]+$ ]] && [[ "$connect_plugin_count" -gt 3 ]]
    then
      log "✅ Connect REST API reports $connect_plugin_count connector plugins (on-demand build complete)"
      break
    fi
    connect_build_cur_wait=$(( connect_build_cur_wait + connect_build_interval ))
    if [[ "$connect_build_cur_wait" -ge "$connect_build_wait_max" ]]
    then
      logwarn "⚠️ Only $connect_plugin_count plugins visible after ${connect_build_wait_max}s — on-demand build may have failed"
      log "  Init container logs:"
      kubectl -n confluent logs connect-0 -c config-init-container 2>/dev/null | tail -30 || true
      log "  Connect CR status:"
      kubectl -n confluent get connect connect -o jsonpath='{.status}' 2>/dev/null | python3 -m json.tool 2>/dev/null || true
      break
    fi
    log "  ⌛ Connect REST API plugins=${connect_plugin_count} (waiting for >3), elapsed: ${connect_build_cur_wait}/${connect_build_wait_max}s"
    sleep "$connect_build_interval"
  done
  set -e
fi

CONTROL_CENTER_PF_PID=""
SCHEMA_REGISTRY_PF_PID=""
CONNECT_PF_PID=""
cleanup() {
  if [ -n "$CONNECTOR_ZIP_SERVER_PID" ]
  then
    kill "$CONNECTOR_ZIP_SERVER_PID" >/dev/null 2>&1 || true
  fi
  if [ -n "$CONNECTOR_ZIP_DIR" ]
  then
    rm -rf "$CONNECTOR_ZIP_DIR" >/dev/null 2>&1 || true
  fi
  if [ -n "$CONNECT_BUILD_PATCH_FILE" ]
  then
    rm -f "$CONNECT_BUILD_PATCH_FILE" >/dev/null 2>&1 || true
  fi
  if [ -n "$EXTRA_PODS_FILE" ]
  then
    rm -f "$EXTRA_PODS_FILE" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

function start_port_forward() {
  local service="$1"
  local local_port="$2"
  local remote_port="$3"
  local log_file="$4"
  local description="$5"

  log "🔀 Starting port-forward for $description (local:$local_port -> service $service:$remote_port)"

  # Kill any existing port-forward processes listening on the local port
  set +e
  lsof -i ":${local_port}" 2>/dev/null | grep -i kubectl | awk '{print $2}' | xargs kill -9 2>/dev/null || true
  set -e

  sleep 1

  # Start the port-forward
  kubectl -n confluent port-forward "service/${service}" "${local_port}:${remote_port}" >"${log_file}" 2>&1 &
  local pf_pid=$!

  # Give the port-forward a moment to start and check if it succeeded
  sleep 2

  if ! kill -0 "$pf_pid" 2>/dev/null
  then
    logwarn "⚠️ Port-forward for $description (port $local_port) failed to start"
    cat "${log_file}" | head -10 | while read -r line; do logwarn "  $line"; done
    return 1
  fi

  # Check the log for any errors
  if grep -i "error\|unable\|failed" "${log_file}" > /dev/null 2>&1
  then
    logwarn "⚠️ Port-forward for $description may have encountered an error"
    cat "${log_file}" | head -10 | while read -r line; do logwarn "  $line"; done
    return 1
  fi

  echo "$pf_pid"
  return 0
}

function start_port_forward_with_retry() {
  local service="$1"
  local local_port="$2"
  local remote_port="$3"
  local log_file="$4"
  local description="$5"
  local max_wait_seconds="${6:-120}"
  local waited=0
  local wait_interval=2
  local pf_pid=""

  while [[ "$waited" -lt "$max_wait_seconds" ]]
  do
    if kubectl -n confluent get service "$service" >/dev/null 2>&1
    then
      pf_pid=$(start_port_forward "$service" "$local_port" "$remote_port" "$log_file" "$description")
      if [[ -n "$pf_pid" ]]
      then
        echo "$pf_pid"
        return 0
      fi
    fi

    sleep "$wait_interval"
    waited=$(( waited + wait_interval ))
  done

  logwarn "⚠️ Timed out after ${max_wait_seconds}s starting port-forward for $description"
  return 1
}

log "Port-forward controlcenter, schema-registry, and connect"
CONTROL_CENTER_PF_PID=$(start_port_forward_with_retry "controlcenter" "9021" "9021" "/tmp/control-center-port-forward.log" "Control Center" "120") || true
SCHEMA_REGISTRY_PF_PID=$(start_port_forward_with_retry "schemaregistry" "8081" "8081" "/tmp/schema-registry-port-forward.log" "Schema Registry" "120") || true
CONNECT_PF_PID=$(start_port_forward_with_retry "connect" "8083" "8083" "/tmp/connect-port-forward.log" "Connect" "120") || true

if [[ -z "$CONTROL_CENTER_PF_PID" ]] || [[ -z "$SCHEMA_REGISTRY_PF_PID" ]] || [[ -z "$CONNECT_PF_PID" ]]
then
  logwarn "⚠️ Some port-forwards may not be available; check logs in /tmp/control-center-port-forward.log, /tmp/schema-registry-port-forward.log, /tmp/connect-port-forward.log"
fi

if [[ -n "$CONTROL_CENTER_PF_PID" ]]
then
  log "💠 Control Center is reachable at http://127.0.0.1:9021"
fi
if [[ -n "$SCHEMA_REGISTRY_PF_PID" ]]
then
  log "🗂️ Schema Registry is reachable at http://127.0.0.1:8081"
fi
if [[ -n "$CONNECT_PF_PID" ]]
then
  log "🔌 Connect REST API is reachable at http://127.0.0.1:8083"
fi


# Port-forward extra pod Services (parsed directly from EXTRA_PODS_FILE, not from cluster)
if [[ -n "$EXTRA_PODS_FILE" ]] && [[ -s "$EXTRA_PODS_FILE" ]]
then
  log "🔀 Port-forwarding extra pod services"
  in_service_block=0
  current_svc_name=""
  set +e
  while IFS= read -r yaml_line
  do
    # Entering a Service block
    if [[ "$yaml_line" =~ ^kind:[[:space:]]*Service ]]
    then
      in_service_block=1
      current_svc_name=""
      continue
    fi
    # Leaving a Service block (new document)
    if [[ "$yaml_line" == "---" ]]
    then
      in_service_block=0
      current_svc_name=""
      continue
    fi
    if [[ "$in_service_block" -eq 0 ]]
    then
      continue
    fi
    # Capture service name
    if [[ -z "$current_svc_name" ]] && [[ "$yaml_line" =~ ^[[:space:]]*name:[[:space:]]*([a-z0-9-]+) ]]
    then
      current_svc_name="${BASH_REMATCH[1]}"
      continue
    fi
    # Forward each port listed under spec.ports
    if [[ -n "$current_svc_name" ]] && [[ "$yaml_line" =~ ^[[:space:]]*port:[[:space:]]*([0-9]+) ]]
    then
      svc_port="${BASH_REMATCH[1]}"
      start_port_forward "$current_svc_name" "$svc_port" "$svc_port" \
        "/tmp/${current_svc_name}-${svc_port}-port-forward.log" "$current_svc_name" > /dev/null || true
      log "🔌 Extra service ${current_svc_name} is reachable at http://127.0.0.1:${svc_port}"
    fi
  done < "$EXTRA_PODS_FILE"
  set -e
fi

playground state set run.environment "cfk"