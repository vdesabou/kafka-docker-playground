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

log "⌛ Waiting up to 900 seconds for all pods in namespace confluent to start"
wait-until-pods-ready "900" "10" "confluent"


CONTROL_CENTER_PF_PID=""
SCHEMA_REGISTRY_PF_PID=""
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
  if [ -n "$CONTROL_CENTER_PF_PID" ]
  then
    kill "$CONTROL_CENTER_PF_PID" >/dev/null 2>&1 || true
  fi
  if [ -n "$SCHEMA_REGISTRY_PF_PID" ]
  then
    kill "$SCHEMA_REGISTRY_PF_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

log "Port-forward controlcenter and schema-registry"
kubectl -n confluent port-forward service/controlcenter 9021:9021 >/tmp/control-center-port-forward.log 2>&1 &
CONTROL_CENTER_PF_PID=$!
kubectl -n confluent port-forward service/schemaregistry 8081:8081 >/tmp/schema-registry-port-forward.log 2>&1 &
SCHEMA_REGISTRY_PF_PID=$!


log "Control Center is reachable at http://127.0.0.1:9021"

playground state set run.environment "cfk"