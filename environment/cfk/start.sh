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

function generate_extra_pods_from_compose_override() {
  local compose_file="$1"
  local output_file="$2"
  local compose_dir=""
  local tmp_services_file
  local service_name=""
  local pod_name=""
  local container_name=""
  local image=""
  local build_context=""
  local build_context_abs=""
  local auto_image=""
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
        print service "|" image "|" build_context "|" env_joined "|" ports_joined
      }
      service=""
      image=""
      build_context=""
      section=""
      env_count=0
      ports_count=0
      delete envs
      delete ports
    }

    BEGIN { in_services=0; service=""; image=""; build_context=""; section=""; env_count=0; ports_count=0 }
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
  while IFS='|' read -r service_name image build_context env_list ports_list
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

    if [[ -n "$image" ]]
    then
      image=$(echo "$image" | envsubst)
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
      imagePullPolicy: IfNotPresent
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

    if [[ -n "$ports_list" ]]
    then
      IFS=';' read -r -a port_items <<< "$ports_list"
      has_any_port=0
      parsed_ports=()
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
  local raw_paths=""
  local tmp_plugins_file
  local tmp_plugins_unique_file
  local plugin_path=""
  local plugin_id=""
  local owner=""
  local name=""
  local version_value=""
  local has_confluent_hub_plugins=0
  local has_url_plugins=0
  local plugin_index=0
  local my_array_connector_tag=()
  local plugin_paths=()

  tmp_plugins_file=$(mktemp)
  tmp_plugins_unique_file=$(mktemp)

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

        echo "$owner|$name" >> "$tmp_plugins_file"
      done
    done < <(grep -E 'CONNECT_PLUGIN_PATH[[:space:]]*:' "$compose_file" 2>/dev/null)
  fi

  if [[ -s "$tmp_plugins_file" ]]
  then
    awk '!seen[$0]++' "$tmp_plugins_file" > "$tmp_plugins_unique_file"
    has_confluent_hub_plugins=1
  fi

  if [[ -n "$connector_zip_url" ]] && [[ -n "$connector_zip_checksum" ]]
  then
    has_url_plugins=1
  fi

  if [[ "$has_confluent_hub_plugins" -ne 1 ]] && [[ "$has_url_plugins" -ne 1 ]]
  then
    rm -f "$tmp_plugins_file" "$tmp_plugins_unique_file"
    return 1
  fi

  if [[ -n "$CONNECTOR_TAG" ]]
  then
    IFS=',' read -r -a my_array_connector_tag <<< "$CONNECTOR_TAG"
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
    while IFS='|' read -r owner name
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

      {
        printf '          - name: %s\n' "$name"
        printf '            owner: %s\n' "$owner"
        printf '            version: %s\n' "$version_value"
      } >> "$output_file"

      ((plugin_index=plugin_index+1))
    done < "$tmp_plugins_unique_file"
  fi

  if [[ "$has_url_plugins" -eq 1 ]]
  then
    if [[ -z "$connector_zip_plugin_name" ]]
    then
      connector_zip_plugin_name="custom-zip-plugin"
    fi
    {
      echo "        url:"
      printf '          - name: %s\n' "$connector_zip_plugin_name"
      printf '            archivePath: %s\n' "$connector_zip_url"
      printf '            checksum: %s\n' "$connector_zip_checksum"
    } >> "$output_file"
  fi

  rm -f "$tmp_plugins_file" "$tmp_plugins_unique_file"
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
CONNECTOR_ZIP_HTTP_DIR=""
CONNECTOR_ZIP_SERVER_PID=""
EXTRA_PODS_FILE=""

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
    CONNECTOR_ZIP_HTTP_DIR=$(mktemp -d)
    connector_zip_basename=$(basename "$CONNECTOR_ZIP")
    cp "$CONNECTOR_ZIP" "$CONNECTOR_ZIP_HTTP_DIR/$connector_zip_basename"
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
  CONNECT_BUILD_PATCH_FILE=$(mktemp)
  if generate_connect_build_patch_from_compose "${DOCKER_COMPOSE_FILE_OVERRIDE}" "${CONNECT_BUILD_PATCH_FILE}" "$CONNECTOR_ZIP_URL" "$CONNECTOR_ZIP_CHECKSUM" "$CONNECTOR_ZIP_PLUGIN_NAME"
  then
    log "🔌 CFK Connect build plugins will be patched dynamically"
    log_generated_yaml_file "Dynamic Connect build patch generated:" "${CONNECT_BUILD_PATCH_FILE}"
  else
    rm -f "${CONNECT_BUILD_PATCH_FILE}"
    CONNECT_BUILD_PATCH_FILE=""
  fi
elif [[ -n "$CONNECTOR_ZIP_URL" ]] && [[ -n "$CONNECTOR_ZIP_CHECKSUM" ]]
then
  CONNECT_BUILD_PATCH_FILE=$(mktemp)
  if ! generate_connect_build_patch_from_compose "" "${CONNECT_BUILD_PATCH_FILE}" "$CONNECTOR_ZIP_URL" "$CONNECTOR_ZIP_CHECKSUM" "$CONNECTOR_ZIP_PLUGIN_NAME"
  then
    rm -f "${CONNECT_BUILD_PATCH_FILE}"
    CONNECT_BUILD_PATCH_FILE=""
  else
    log_generated_yaml_file "Dynamic Connect build patch generated:" "${CONNECT_BUILD_PATCH_FILE}"
  fi
fi

set +e
log "Stop minikube if required"
minikube delete
set -e

log "Start minikube"
minikube start --cpus=8 --disk-size='50gb' --memory=16384

if [[ -n "$CONNECTOR_ZIP_HTTP_DIR" ]]
then
  log "Serve local CONNECTOR_ZIP for CFK on-demand plugin download"
  python3 -m http.server 18080 --directory "$CONNECTOR_ZIP_HTTP_DIR" >/tmp/cfk-connector-zip-http.log 2>&1 &
  CONNECTOR_ZIP_SERVER_PID=$!
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

log "Create namespace"
kubectl create namespace confluent || true
kubectl config set-context --current --namespace=confluent

set +e
helm repo remove confluentinc
set -e

log "Add the Confluent for Kubernetes Helm repository"
helm repo add confluentinc https://packages.confluent.io/helm
helm repo update

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
fi

wait_container_ready


CONTROL_CENTER_PF_PID=""
SCHEMA_REGISTRY_PF_PID=""
CONNECT_PF_PID=""
cleanup() {
  if [ -n "$CONNECTOR_ZIP_SERVER_PID" ]
  then
    kill "$CONNECTOR_ZIP_SERVER_PID" >/dev/null 2>&1 || true
  fi
  if [ -n "$CONNECTOR_ZIP_HTTP_DIR" ]
  then
    rm -rf "$CONNECTOR_ZIP_HTTP_DIR" >/dev/null 2>&1 || true
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

log "Port-forward controlcenter, schema-registry, and connect"
CONTROL_CENTER_PF_PID=$(start_port_forward "controlcenter" "9021" "9021" "/tmp/control-center-port-forward.log" "Control Center") || true
SCHEMA_REGISTRY_PF_PID=$(start_port_forward "schemaregistry" "8081" "8081" "/tmp/schema-registry-port-forward.log" "Schema Registry") || true
CONNECT_PF_PID=$(start_port_forward "connect" "8083" "8083" "/tmp/connect-port-forward.log" "Connect") || true

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

playground state set run.environment "cfk"