#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

check_bash_version
check_and_update_playground_version

verify_docker_and_memory
verify_installed "kubectl"
verify_installed "k3d"
verify_installed "helm"
verify_installed "envsubst"
verify_installed "zip"
verify_installed "shasum"

SHASUM_BIN="$(command -v shasum)"
if [[ -x "/usr/bin/shasum" ]]
then
  SHASUM_BIN="/usr/bin/shasum"
fi

function checksum_sha512() {
  local file_path="$1"

  env -u PERL5LIB -u PERL_LOCAL_LIB_ROOT -u PERL_MB_OPT -u PERL_MM_OPT -u PERL5OPT \
    "$SHASUM_BIN" -a 512 "$file_path" | awk '{print $1}'
}

function normalize_cfk_connect_plugin_path() {
  local raw_value="$1"
  local normalized=""
  local token=""
  local has_mnt_plugins=0

  IFS=',' read -r -a plugin_tokens <<< "$raw_value"
  for token in "${plugin_tokens[@]}"
  do
    token=$(echo "$token" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
    token="${token%/}"
    if [[ -z "$token" ]]
    then
      continue
    fi

    # CFK on-demand plugins are materialized under /mnt/plugins/<plugin>.
    # Normalize plugin-specific paths to stable base directories to avoid
    # noisy FileNotFoundException when a specific subdirectory is absent.
    if [[ "$token" == /usr/share/confluent-hub-components/* ]]
    then
      token="/usr/share/confluent-hub-components"
    elif [[ "$token" == /mnt/plugins/* ]]
    then
      token="/mnt/plugins"
    fi

    if [[ ",$normalized," != *",$token,"* ]]
    then
      if [[ -z "$normalized" ]]
      then
        normalized="$token"
      else
        normalized="${normalized},${token}"
      fi
    fi

    if [[ "$token" == "/mnt/plugins" ]] || [[ "$token" == /mnt/plugins/* ]]
    then
      has_mnt_plugins=1
    fi
  done

  if [[ -z "$normalized" ]]
  then
    normalized="/usr/share/confluent-hub-components,/mnt/plugins"
    echo "$normalized"
    return 0
  fi

  if [[ "$has_mnt_plugins" -ne 1 ]]
  then
    normalized="${normalized},/mnt/plugins"
  fi

  echo "$normalized"
}

: "${K3D_CLUSTER_NAME:=playground-cfk}"
: "${K3D_REGISTRY_CACHE_ENABLED:=0}"
: "${K3D_REGISTRY_CACHE_NAME:=playground-registry}"
: "${K3D_REGISTRY_CACHE_PORT:=5111}"
: "${K3D_REGISTRY_CACHE_IMAGE:=ligfx/k3d-registry-dockerd:latest}"

: "${CP_SERVER_IMAGE:=confluentinc/cp-server}"
: "${CP_SERVER_TAG:=8.3.0}"
: "${CP_CONNECT_IMAGE:=confluentinc/cp-server-connect}"
: "${CP_CONNECT_TAG:=8.3.0}"
: "${CP_SCHEMA_REGISTRY_IMAGE:=confluentinc/cp-schema-registry}"
: "${CP_SCHEMA_REGISTRY_TAG:=8.3.0}"
: "${CP_KSQL_IMAGE:=confluentinc/cp-ksqldb-server}"
: "${CP_KSQL_TAG:=8.3.0}"
: "${CP_REST_PROXY_IMAGE:=confluentinc/cp-kafka-rest}"
: "${CP_REST_PROXY_TAG:=8.3.0}"
: "${CP_CONTROL_CENTER_IMAGE:=confluentinc/cp-enterprise-control-center-next-gen}"
: "${CP_CONTROL_CENTER_TAG:=latest}"
: "${CP_INIT_IMAGE:=confluentinc/confluent-init-container}"
: "${CP_INIT_TAG:=3.3.0}"

export CP_SERVER_IMAGE CP_SERVER_TAG
export CP_CONNECT_IMAGE CP_CONNECT_TAG
export CP_SCHEMA_REGISTRY_IMAGE CP_SCHEMA_REGISTRY_TAG
export CP_KSQL_IMAGE CP_KSQL_TAG
export CP_REST_PROXY_IMAGE CP_REST_PROXY_TAG
export CP_CONTROL_CENTER_IMAGE CP_CONTROL_CENTER_TAG
export CP_INIT_IMAGE CP_INIT_TAG

: "${CFK_TMPFS_DEFAULT_SIZE_LIMIT:=256Mi}"
: "${CFK_TMPFS_SHM_SIZE_LIMIT:=1Gi}"
: "${CFK_CONNECTOR_ARCHIVE_HOST:=}"

: "${CFK_CONNECT_PLUGIN_PATH:=}"
if [[ -n "${CONNECT_PLUGIN_PATH+x}" ]]
then
  CFK_CONNECT_PLUGIN_PATH=$(normalize_cfk_connect_plugin_path "${CONNECT_PLUGIN_PATH}")
fi
if [[ -z "$CFK_CONNECT_PLUGIN_PATH" ]]
then
  CFK_CONNECT_PLUGIN_PATH="/usr/share/confluent-hub-components,/mnt/plugins"
fi
CFK_CONNECT_PLUGIN_PATH=$(normalize_cfk_connect_plugin_path "$CFK_CONNECT_PLUGIN_PATH")
export CFK_CONNECT_PLUGIN_PATH

playground state set run.environment "cfk"

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

function import_image_into_k3d() {
  local image="$1"
  local image_to_import="$image"
  local image_alias="$2"
  local force_import="${3:-0}"
  local timeout_seconds="${K3D_IMAGE_IMPORT_TIMEOUT_SECONDS:-600}"
  local import_log=""
  local import_ret=1
  local k3d_server_node=""
  local image_name_no_tag=""
  local image_repo_part=""
  local image_repo_first_segment=""
  local normalized_image=""

  normalize_image_ref_for_k8s() {
    local raw_image="$1"
    local image_name_no_tag=""
    local image_repo_part=""
    local image_repo_first_segment=""

    if [[ "$raw_image" == *@* ]] || [[ "${raw_image##*/}" == *:* ]]
    then
      :
    else
      raw_image="${raw_image}:latest"
    fi

    image_name_no_tag="${raw_image%%@*}"
    image_name_no_tag="${image_name_no_tag%%:*}"
    image_repo_part="${image_name_no_tag%%/*}"
    image_repo_first_segment="$image_repo_part"

    if [[ "$raw_image" != */* ]]
    then
      echo "docker.io/library/$raw_image"
      return
    fi

    if [[ "$image_repo_first_segment" != *.* ]] && [[ "$image_repo_first_segment" != *:* ]] && [[ "$image_repo_first_segment" != "localhost" ]]
    then
      echo "docker.io/$raw_image"
      return
    fi

    echo "$raw_image"
  }

  image_present_in_k3d_node() {
    local image_ref="$1"
    docker exec "$k3d_server_node" sh -lc "ctr -n k8s.io images list -q 2>/dev/null | grep -Fx -- \"$image_ref\" >/dev/null || k3s ctr images list -q 2>/dev/null | grep -Fx -- \"$image_ref\" >/dev/null" >/dev/null 2>&1
  }

  import_image_into_server_node_direct() {
    local image_to_import="$1"
    local server_node="$2"

    # Fallback path for very large images when k3d tools-container import gets OOM-killed.
    # Stream straight into the server node's containerd to avoid the intermediate tools container.
    docker save "$image_to_import" | docker exec -i "$server_node" sh -lc 'ctr -n k8s.io images import - || k3s ctr images import -'
  }

  if [[ -z "$image_alias" ]]
  then
    image_alias="$(echo "$image" | tr '/:.' '_')"
  fi

  if [[ "$image_to_import" != *@* ]] && [[ "${image_to_import##*/}" != *:* ]]
  then
    image_to_import="${image_to_import}:latest"
  fi

  normalized_image="$(normalize_image_ref_for_k8s "$image_to_import")"

  if ! docker image inspect "$image_to_import" >/dev/null 2>&1
  then
    return 1
  fi

  k3d_server_node="k3d-${K3D_CLUSTER_NAME}-server-0"
  if [[ "$force_import" -ne 1 ]] && docker ps --format '{{.Names}}' | grep -qx "$k3d_server_node"
  then
    if image_present_in_k3d_node "$normalized_image"
    then
      log "⏭️ Image $normalized_image already present in k3d cluster $K3D_CLUSTER_NAME, skipping import"
      return 0
    fi
  fi

  import_log="/tmp/k3d-image-import-${image_alias}.log"
  : > "$import_log"
  log "📦 Importing image $image_to_import into k3d cluster $K3D_CLUSTER_NAME"

  set +e
  run_with_timeout "$timeout_seconds" k3d image import --cluster "$K3D_CLUSTER_NAME" "$image_to_import" >> "$import_log" 2>&1
  import_ret=$?
  set -e

  if [[ "$import_ret" -eq 0 ]]
  then
    if image_present_in_k3d_node "$normalized_image" || image_present_in_k3d_node "$image_to_import"
    then
      log "✅ Imported image $image_to_import into k3d"
      return 0
    fi

    logwarn "⚠️ k3d import reported success but image '$normalized_image' is not present in node runtime"
    import_ret=1
  fi

  logwarn "⚠️ Retrying image import using direct server-node stream (fallback mode)"
  set +e
  import_image_into_server_node_direct "$image_to_import" "$k3d_server_node" >> "$import_log" 2>&1
  import_ret=$?
  set -e

  if [[ "$import_ret" -eq 0 ]]
  then
    if image_present_in_k3d_node "$normalized_image" || image_present_in_k3d_node "$image_to_import"
    then
      log "✅ Imported image $image_to_import into k3d via fallback mode"
      return 0
    fi

    logwarn "⚠️ Fallback import reported success but image '$normalized_image' is not present in node runtime"
    import_ret=1
  fi

  if [[ "$import_ret" -eq 124 ]]
  then
    logwarn "⚠️ Timed out after ${timeout_seconds}s while importing image $image_to_import into k3d"
  else
    logwarn "⚠️ Failed to import image $image_to_import into k3d"
  fi
  logwarn "⚠️ See $import_log for details"
  return 1
}

function resolve_cfk_connector_archive_host() {
  local k3d_server_node="k3d-${K3D_CLUSTER_NAME}-server-0"
  local k3d_network_name="k3d-${K3D_CLUSTER_NAME}"
  local host_os=""
  local gateway_ip=""

  if [[ -n "$CFK_CONNECTOR_ARCHIVE_HOST" ]]
  then
    log "🌐 Using configured CFK connector archive host ${CFK_CONNECTOR_ARCHIVE_HOST}"
    return 0
  fi

  host_os=$(uname -s 2>/dev/null || echo "")
  if [[ "$host_os" == "Darwin" ]]
  then
    # Docker Desktop on macOS exposes the host reliably via host.docker.internal.
    CFK_CONNECTOR_ARCHIVE_HOST="host.docker.internal"
    log "🌐 Using Docker Desktop host alias ${CFK_CONNECTOR_ARCHIVE_HOST} for CFK connector archives"
    return 0
  fi

  gateway_ip=$(docker inspect "$k3d_server_node" --format '{{range .NetworkSettings.Networks}}{{.Gateway}}{{end}}' 2>/dev/null | tr -d '[:space:]')
  if [[ ! "$gateway_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
  then
    gateway_ip=$(docker network inspect "$k3d_network_name" --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}' 2>/dev/null | tr -d '[:space:]')
  fi
  if [[ -n "$gateway_ip" ]]
  then
    CFK_CONNECTOR_ARCHIVE_HOST="$gateway_ip"
    log "🌐 Using k3d gateway ${CFK_CONNECTOR_ARCHIVE_HOST} for CFK connector archives"
    return 0
  fi

  CFK_CONNECTOR_ARCHIVE_HOST="host.k3d.internal"
  logwarn "⚠️ Could not determine k3d gateway IP, falling back to ${CFK_CONNECTOR_ARCHIVE_HOST}"
  return 0
}

function wait_for_kubernetes_apiserver() {
  local max_wait_seconds="${1:-120}"
  local waited=0
  local wait_interval=2

  while [[ "$waited" -lt "$max_wait_seconds" ]]
  do
    if kubectl --request-timeout=5s get --raw='/readyz' >/dev/null 2>&1
    then
      return 0
    fi

    sleep "$wait_interval"
    waited=$(( waited + wait_interval ))
  done

  return 1
}

function verify_build_archive_urls_reachable_from_cluster() {
  local patch_file="$1"
  local archive_urls=()
  local archive_url=""
  local probe_pod=""
  local phase=""
  local attempt=0
  local all_ok=1

  if [[ -z "$patch_file" ]] || [[ ! -s "$patch_file" ]]
  then
    return 0
  fi

  archive_urls=()
  while IFS= read -r archive_url
  do
    archive_urls+=("$archive_url")
  done < <(awk '/archivePath:[[:space:]]*/ {print $2}' "$patch_file" | sed -E 's/^["\'"'"']|["\'"'"']$//g' | awk '!seen[$0]++')
  if [[ "${#archive_urls[@]}" -eq 0 ]]
  then
    return 0
  fi

  for archive_url in "${archive_urls[@]}"
  do
    probe_pod="cfk-archive-url-check-$(date +%s)-$RANDOM"
    log "🔎 Verifying in-cluster access to plugin archive URL: $archive_url"

    set +e
    kubectl -n confluent run "$probe_pod" --restart=Never --image=curlimages/curl:8.9.1 --command -- sh -lc "curl -fsS --max-time 10 '$archive_url' >/dev/null"
    if [[ $? -ne 0 ]]
    then
      set -e
      logerror "❌ Could not create URL probe pod for archive URL validation"
      return 1
    fi

    phase=""
    for attempt in {1..20}
    do
      phase=$(kubectl -n confluent get pod "$probe_pod" -o jsonpath='{.status.phase}' 2>/dev/null)
      if [[ "$phase" == "Succeeded" ]] || [[ "$phase" == "Failed" ]]
      then
        break
      fi
      sleep 1
    done

    if [[ "$phase" != "Succeeded" ]]
    then
      all_ok=0
      logerror "❌ Archive URL is not reachable from cluster: $archive_url"
      log "  Probe pod logs:"
      kubectl -n confluent logs "$probe_pod" --tail=80 2>/dev/null || true
      log "  Hint: override host with CFK_CONNECTOR_ARCHIVE_HOST (current: ${CFK_CONNECTOR_ARCHIVE_HOST})"
    else
      log "✅ Archive URL is reachable from cluster: $archive_url"
    fi

    kubectl -n confluent delete pod "$probe_pod" --ignore-not-found=true >/dev/null 2>&1 || true
    set -e
  done

  if [[ "$all_ok" -ne 1 ]]
  then
    return 1
  fi

  return 0
}

function generate_k3d_config_with_registry_cache() {
  local output_file="$1"

  cat > "$output_file" << EOF
apiVersion: k3d.io/v1alpha5
kind: Simple
metadata:
  name: ${K3D_CLUSTER_NAME}
servers: 1
agents: 0
registries:
  create:
    name: ${K3D_REGISTRY_CACHE_NAME}
    hostPort: "${K3D_REGISTRY_CACHE_PORT}"
    image: ${K3D_REGISTRY_CACHE_IMAGE}
    proxy:
      remoteURL: "*"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
EOF
}

function sanitize_k8s_name() {
  local raw_name="$1"

  echo "$raw_name" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9.-]+/-/g; s/^-+//; s/-+$//'
}

function sanitize_secret_key() {
  local raw_key="$1"

  echo "$raw_key" | sed -E 's/[^A-Za-z0-9._-]+/_/g'
}

function append_secret_manifest_from_file() {
  local output_file="$1"
  local secret_name="$2"
  local source_file="$3"
  local secret_key="$4"
  local encoded=""

  encoded=$(base64 < "$source_file" | tr -d '\n')

  if [[ -s "$output_file" ]]
  then
    echo "---" >> "$output_file"
  fi

  cat >> "$output_file" << EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${secret_name}
  namespace: confluent
type: Opaque
data:
  ${secret_key}: ${encoded}
EOF
}

function parse_compose_file_volume_mount() {
  local raw_volume="$1"
  local source_path=""
  local target_path=""

  raw_volume=$(echo "$raw_volume" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' | sed -E "s/^[\"']//; s/[\"']$//")
  if [[ "$raw_volume" != *":"* ]]
  then
    return 1
  fi

  source_path="${raw_volume%%:*}"
  target_path="${raw_volume#*:}"
  target_path="${target_path%%:*}"

  if [[ -z "$source_path" ]] || [[ -z "$target_path" ]]
  then
    return 1
  fi

  if [[ "$source_path" != /* ]] && [[ "$source_path" != .* ]]
  then
    return 1
  fi

  printf '%s|%s\n' "$source_path" "$target_path"
}

function collect_service_volume_mounts_from_compose() {
  local compose_file="$1"
  local output_file="$2"

  awk '
    function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
    function unquote(s) { gsub(/^"|"$/, "", s); gsub(/^\047|\047$/, "", s); return s }
    BEGIN { in_services=0; service=""; section="" }
    /^services:[[:space:]]*$/ { in_services=1; next }
    {
      if (in_services == 1 && $0 ~ /^[^[:space:]]/) {
        in_services=0
      }
      if (in_services == 0) {
        next
      }
      if ($0 ~ /^  [A-Za-z0-9_.-]+:[[:space:]]*$/) {
        service=$1
        sub(/:$/, "", service)
        section=""
        next
      }
      if (service == "") {
        next
      }
      if ($0 ~ /^    volumes:[[:space:]]*$/) {
        section="volumes"
        next
      }
      if ($0 ~ /^    [A-Za-z0-9_.-]+:[[:space:]]*$/) {
        section=""
      }
      if (section == "volumes" && $0 ~ /^[[:space:]]*-[[:space:]]*/) {
        value=$0
        sub(/^[[:space:]]*-[[:space:]]*/, "", value)
        value=trim(unquote(value))
        if (value != "") {
          print service "|" value
        }
      }
    }
  ' "$compose_file" > "$output_file"
}

function generate_connect_mounted_volumes_from_compose() {
  local compose_file="$1"
  local resources_file="$2"
  local patch_file="$3"
  local compose_dir=""
  local tmp_mounts_file=""
  local service_name=""
  local raw_volume=""
  local parsed_volume=""
  local source_path=""
  local target_path=""
  local source_abs=""
  local source_file=""
  local volume_index=0
  local volume_name=""
  local secret_name=""
  local secret_key=""
  local target_file_path=""
  local has_mounts=0

  if [[ ! -f "$compose_file" ]]
  then
    return 1
  fi

  compose_dir="$(cd "$(dirname "$compose_file")" && pwd)"
  tmp_mounts_file=$(mktemp)
  collect_service_volume_mounts_from_compose "$compose_file" "$tmp_mounts_file"

  : > "$resources_file"
  : > "$patch_file"

  while IFS='|' read -r service_name raw_volume
  do
    if [[ "$service_name" != "connect" ]]
    then
      continue
    fi

    if ! parsed_volume=$(parse_compose_file_volume_mount "$raw_volume")
    then
      continue
    fi

    source_path="${parsed_volume%%|*}"
    target_path="${parsed_volume#*|}"
    source_path=$(echo "$source_path" | envsubst)
    target_path=$(echo "$target_path" | envsubst)

    if [[ "$source_path" = /* ]]
    then
      source_abs="$source_path"
    else
      source_abs="$compose_dir/$source_path"
    fi

    if [[ -f "$source_abs" ]]
    then
      volume_index=$((volume_index + 1))
      volume_name="compose-file-${volume_index}"
      secret_name="$(sanitize_k8s_name "connect-${volume_name}")"
      secret_key="$(sanitize_secret_key "$(basename "$target_path")")"
      append_secret_manifest_from_file "$resources_file" "$secret_name" "$source_abs" "$secret_key"

      if [[ "$has_mounts" -eq 0 ]]
      then
        cat > "$patch_file" << EOF
spec:
  mountedVolumes:
    volumes:
EOF
        has_mounts=1
      fi

      cat >> "$patch_file" << EOF
      - name: ${volume_name}
        secret:
          secretName: ${secret_name}
EOF
    elif [[ -d "$source_abs" ]]
    then
      volume_index=$((volume_index + 1))
      volume_name="compose-file-${volume_index}"
      secret_name="$(sanitize_k8s_name "connect-${volume_name}")"

      if [[ -s "$resources_file" ]]
      then
        echo "---" >> "$resources_file"
      fi

      {
        echo "apiVersion: v1"
        echo "kind: Secret"
        echo "metadata:"
        echo "  name: ${secret_name}"
        echo "  namespace: confluent"
        echo "type: Opaque"
        echo "data:"
      } >> "$resources_file"

      while IFS= read -r source_file
      do
        secret_key="$(sanitize_secret_key "$(basename "$source_file")")"
        printf "  %s: %s\n" "$secret_key" "$(base64 < "$source_file" | tr -d '\n')" >> "$resources_file"
      done < <(find "$source_abs" -type f | sort)

      if [[ "$has_mounts" -eq 0 ]]
      then
        cat > "$patch_file" << EOF
spec:
  mountedVolumes:
    volumes:
EOF
        has_mounts=1
      fi

      cat >> "$patch_file" << EOF
      - name: ${volume_name}
        secret:
          secretName: ${secret_name}
EOF
    else
      if [[ -e "$source_abs" ]]
      then
        logwarn "⚠️ Compose volume source $source_abs for connect is neither file nor directory, skipping"
      fi
      continue
    fi
  done < "$tmp_mounts_file"

  if [[ "$has_mounts" -eq 1 ]]
  then
    cat >> "$patch_file" << EOF
    volumeMounts:
EOF

    volume_index=0
    while IFS='|' read -r service_name raw_volume
    do
      if [[ "$service_name" != "connect" ]]
      then
        continue
      fi

      if ! parsed_volume=$(parse_compose_file_volume_mount "$raw_volume")
      then
        continue
      fi

      source_path="${parsed_volume%%|*}"
      target_path="${parsed_volume#*|}"
      source_path=$(echo "$source_path" | envsubst)

      if [[ "$source_path" = /* ]]
      then
        source_abs="$source_path"
      else
        source_abs="$compose_dir/$source_path"
      fi

      if [[ -f "$source_abs" ]]
      then
        volume_index=$((volume_index + 1))
        volume_name="compose-file-${volume_index}"
        secret_key="$(sanitize_secret_key "$(basename "$target_path")")"

        cat >> "$patch_file" << EOF
      - name: ${volume_name}
        mountPath: ${target_path}
        subPath: ${secret_key}
        readOnly: true
EOF
      elif [[ -d "$source_abs" ]]
      then
        volume_index=$((volume_index + 1))
        volume_name="compose-file-${volume_index}"

        cat >> "$patch_file" << EOF
      - name: ${volume_name}
        mountPath: ${target_path}
        readOnly: true
EOF
      fi
    done < "$tmp_mounts_file"
  fi

  rm -f "$tmp_mounts_file"

  if [[ "$has_mounts" -eq 1 ]]
  then
    return 0
  fi

  rm -f "$resources_file" "$patch_file"
  return 1
}

function generate_connect_env_patch_from_compose() {
  local compose_file="$1"
  local patch_file="$2"
  local tmp_env_file=""
  local env_key=""
  local env_value=""
  local env_mode=""
  local escaped_value=""
  local has_env=0

  if [[ ! -f "$compose_file" ]]
  then
    return 1
  fi

  tmp_env_file=$(mktemp)

  awk '
    function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
    function unquote(s) { gsub(/^"|"$/, "", s); gsub(/^\047|\047$/, "", s); return s }

    BEGIN {
      in_services=0
      service=""
      section=""
    }

    /^services:[[:space:]]*$/ {
      in_services=1
      next
    }

    {
      if (in_services == 1 && $0 ~ /^[^[:space:]]/) {
        in_services=0
      }
      if (in_services == 0) {
        next
      }

      if ($0 ~ /^  [A-Za-z0-9_.-]+:[[:space:]]*$/) {
        service=$1
        sub(/:$/, "", service)
        section=""
        next
      }

      if (service != "connect") {
        next
      }

      if ($0 ~ /^    environment:[[:space:]]*$/) {
        section="environment"
        next
      }

      if ($0 ~ /^    [A-Za-z0-9_.-]+:[[:space:]]*$/) {
        section=""
      }

      if (section == "environment" && $0 ~ /^      -[[:space:]]*/) {
        entry=$0
        sub(/^      -[[:space:]]*/, "", entry)
        entry=trim(unquote(entry))
        if (entry == "") {
          next
        }

        if (index(entry, "=") > 0) {
          key=entry
          sub(/=.*/, "", key)
          value=entry
          sub(/^[^=]*=/, "", value)
          key=trim(key)
          value=trim(unquote(value))
          if (key != "") {
            print key "|" value "|literal"
          }
        } else {
          key=trim(entry)
          if (key != "") {
            print key "||from_env"
          }
        }
        next
      }

      if (section == "environment" && $0 ~ /^      [A-Za-z_][A-Za-z0-9_]*:[[:space:]]*/) {
        kv=$0
        sub(/^      /, "", kv)
        key=kv
        sub(/:.*/, "", key)
        value=kv
        sub(/^[^:]+:[[:space:]]*/, "", value)
        key=trim(key)
        value=trim(unquote(value))
        if (key != "") {
          print key "|" value "|literal"
        }
        next
      }
    }
  ' "$compose_file" > "$tmp_env_file"

  : > "$patch_file"

  while IFS='|' read -r env_key env_value env_mode
  do
    if [[ -z "$env_key" ]]
    then
      continue
    fi

    if [[ "$env_mode" == "from_env" ]]
    then
      env_value="${!env_key}"
    fi

    env_value=$(echo "$env_value" | envsubst)

    if [[ "$env_key" == "CONNECT_PLUGIN_PATH" ]]
    then
      env_value=$(normalize_cfk_connect_plugin_path "$env_value")
      CFK_CONNECT_PLUGIN_PATH="$env_value"
      export CFK_CONNECT_PLUGIN_PATH
      log "🔎 Effective CFK plugin.path source set from CONNECT_PLUGIN_PATH: ${CFK_CONNECT_PLUGIN_PATH}"
      # Skip adding to podTemplate envVars since it's already set via configOverrides.server.plugin.path
      continue
    fi

    escaped_value=$(printf '%s' "$env_value" | sed 's/\\/\\\\/g; s/"/\\"/g')

    if [[ "$has_env" -eq 0 ]]
    then
      cat > "$patch_file" << EOF
spec:
  podTemplate:
    envVars:
EOF
      has_env=1
    fi

    cat >> "$patch_file" << EOF
      - name: ${env_key}
        value: "${escaped_value}"
EOF
  done < "$tmp_env_file"

  rm -f "$tmp_env_file"

  if [[ "$has_env" -eq 1 ]]
  then
    return 0
  fi

  rm -f "$patch_file"
  return 1
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
  local compose_user=""
  local run_as_user=""
  local run_as_group=""
  local run_as_non_root=""
  local tmpfs_list=""
  local env_list=""
  local ports_list=""
  local entrypoint_list=""
  local command_list=""
  local volumes_list=""
  local env_items=()
  local port_items=()
  local entrypoint_items=()
  local command_items=()
  local volume_items=()
  local env_item=""
  local port_item=""
  local entrypoint_item=""
  local command_item=""
  local volume_item=""
  local env_key=""
  local env_value=""
  local escaped_value=""
  local escaped_command=""
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
  local parsed_volume=""
  local source_path=""
  local source_abs=""
  local target_path=""
  local volume_index=0
  local volume_name=""
  local secret_name=""
  local secret_key=""
  local volume_names=()
  local volume_secret_names=()
  local volume_mount_paths=()
  local volume_secret_keys=()
  local tmpfs_items=()
  local tmpfs_item=""
  local tmpfs_path=""
  local tmpfs_index=0
  local tmpfs_volume_name=""
  local tmpfs_size_limit=""
  local tmpfs_volume_names=()
  local tmpfs_mount_paths=()
  local tmpfs_size_limits=()
  local file_size_bytes=0
  local bake_tmp_dir=""
  local bake_filename=""
  local deferred_import=0

  if [[ ! -f "$compose_file" ]]
  then
    return 1
  fi

  compose_dir="$(cd "$(dirname "$compose_file")" && pwd)"

  tmp_services_file=$(mktemp)

  awk '
    function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
    function unquote(s) { gsub(/^"|"$/, "", s); gsub(/^\047|\047$/, "", s); return s }
    function append_list_items(raw, target) {
      local_raw = trim(raw)
      if (local_raw ~ /^\[.*\]$/) {
        sub(/^\[/, "", local_raw)
        sub(/\]$/, "", local_raw)
        count = split(local_raw, parts, ",")
        for (i = 1; i <= count; i++) {
          item = trim(unquote(parts[i]))
          if (item != "") {
            if (target == "command") {
              commands[++command_count] = item
            } else if (target == "entrypoint") {
              entrypoints[++entrypoint_count] = item
            } else if (target == "tmpfs") {
              tmpfs[++tmpfs_count] = item
            }
          }
        }
        return 1
      }
      return 0
    }
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
        entrypoint_joined=""
        for (i = 1; i <= entrypoint_count; i++) {
          entrypoint_joined = entrypoint_joined (i > 1 ? ";" : "") entrypoints[i]
        }
        command_joined=""
        for (i = 1; i <= command_count; i++) {
          command_joined = command_joined (i > 1 ? ";" : "") commands[i]
        }
        volumes_joined=""
        for (i = 1; i <= volumes_count; i++) {
          volumes_joined = volumes_joined (i > 1 ? ";" : "") volumes[i]
        }
        tmpfs_joined=""
        for (i = 1; i <= tmpfs_count; i++) {
          tmpfs_joined = tmpfs_joined (i > 1 ? ";" : "") tmpfs[i]
        }
        profiles_joined=""
        for (i = 1; i <= profiles_count; i++) {
          profiles_joined = profiles_joined (i > 1 ? ";" : "") prof[i]
        }
        print service "|" image "|" build_context "|" platform "|" user_value "|" tmpfs_joined "|" env_joined "|" ports_joined "|" entrypoint_joined "|" command_joined "|" volumes_joined "|" profiles_joined
      }
      service=""
      image=""
      platform=""
      user_value=""
      build_context=""
      section=""
      env_count=0
      ports_count=0
      entrypoint_count=0
      command_count=0
      volumes_count=0
      tmpfs_count=0
      profiles_count=0
      delete envs
      delete ports
      delete entrypoints
      delete commands
      delete volumes
      delete tmpfs
      delete prof
    }

    BEGIN { in_services=0; service=""; image=""; platform=""; user_value=""; build_context=""; section=""; env_count=0; ports_count=0; entrypoint_count=0; command_count=0; volumes_count=0; tmpfs_count=0; profiles_count=0 }
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
      if ($0 ~ /^    user:[[:space:]]*/) {
        user_value=$0
        sub(/^    user:[[:space:]]*/, "", user_value)
        user_value=trim(unquote(user_value))
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
      if ($0 ~ /^    volumes:[[:space:]]*$/) {
        section="volumes"
        next
      }
      if ($0 ~ /^    tmpfs:[[:space:]]*$/) {
        section="tmpfs"
        next
      }
      if ($0 ~ /^    tmpfs:[[:space:]]*[^[:space:]].*$/) {
        tf=$0
        sub(/^    tmpfs:[[:space:]]*/, "", tf)
        tf=trim(tf)
        if (tf != "") {
          if (!append_list_items(tf, "tmpfs")) {
            tmpfs[++tmpfs_count]=trim(unquote(tf))
          }
        }
        section=""
        next
      }
      if ($0 ~ /^    entrypoint:[[:space:]]*$/) {
        section="entrypoint"
        next
      }
      if ($0 ~ /^    entrypoint:[[:space:]]*[^[:space:]].*$/) {
        ep=$0
        sub(/^    entrypoint:[[:space:]]*/, "", ep)
        ep=trim(ep)
        if (ep != "") {
          if (!append_list_items(ep, "entrypoint")) {
            entrypoints[++entrypoint_count]=trim(unquote(ep))
          }
        }
        section=""
        next
      }
      if ($0 ~ /^    profiles:[[:space:]]*$/) {
        section="profiles"
        next
      }
      if ($0 ~ /^    command:[[:space:]]*$/) {
        section="command"
        next
      }
      if ($0 ~ /^    command:[[:space:]]*[^[:space:]].*$/) {
        cmd=$0
        sub(/^    command:[[:space:]]*/, "", cmd)
        cmd=trim(cmd)
        if (cmd != "") {
          if (!append_list_items(cmd, "command")) {
            commands[++command_count]=trim(unquote(cmd))
          }
        }
        section=""
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

      if (section == "volumes") {
        if ($0 ~ /^      -[[:space:]]*/) {
          v=$0
          sub(/^      -[[:space:]]*/, "", v)
          v=trim(unquote(v))
          if (v != "") {
            volumes[++volumes_count]=v
          }
          next
        }
      }

      if (section == "tmpfs") {
        if ($0 ~ /^      -[[:space:]]*/) {
          t=$0
          sub(/^      -[[:space:]]*/, "", t)
          t=trim(unquote(t))
          if (t != "") {
            tmpfs[++tmpfs_count]=t
          }
          next
        }
      }

      if (section == "entrypoint") {
        if ($0 ~ /^      -[[:space:]]*/) {
          e=$0
          sub(/^      -[[:space:]]*/, "", e)
          e=trim(unquote(e))
          if (e != "") {
            entrypoints[++entrypoint_count]=e
          }
          next
        }
      }

      if (section == "command") {
        if ($0 ~ /^      -[[:space:]]*/) {
          c=$0
          sub(/^      -[[:space:]]*/, "", c)
          c=trim(unquote(c))
          if (c != "") {
            commands[++command_count]=c
          }
          next
        }
      }

      if (section == "profiles") {
        if ($0 ~ /^      -[[:space:]]*/) {
          pr=$0
          sub(/^      -[[:space:]]*/, "", pr)
          pr=trim(unquote(pr))
          if (pr != "") {
            prof[++profiles_count]=pr
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
  while IFS='|' read -r service_name image build_context platform compose_user tmpfs_list env_list ports_list entrypoint_list command_list volumes_list profiles_list
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

    # Respect docker-compose profiles: skip services that declare profiles unless the
    # corresponding env var (profile name uppercased, hyphens→underscores) is non-empty.
    if [[ -n "$profiles_list" ]]
    then
      local profile_matched=0
      local profile_item=""
      local profile_env_var=""
      IFS=';' read -r -a _profile_items <<< "$profiles_list"
      for profile_item in "${_profile_items[@]}"
      do
        profile_env_var=$(echo "$profile_item" | tr '[:lower:]-' '[:upper:]_')
        if [[ -n "${!profile_env_var:-}" ]]
        then
          profile_matched=1
          break
        fi
      done
      if [[ "$profile_matched" -eq 0 ]]
      then
        log "⏭️  Skipping service $service_name (profiles: $profiles_list) — no matching active env var"
        continue
      fi
    fi

    pod_name=$(echo "$service_name" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9.-]+/-/g' | sed -E 's/^-+//;s/-+$//')
    container_name="${pod_name}"

    image_pull_policy="IfNotPresent"
    run_as_user=""
    run_as_group=""
    run_as_non_root=""
    deferred_import=0
    volume_names=()
    volume_secret_names=()
    volume_mount_paths=()
    volume_secret_keys=()
    tmpfs_volume_names=()
    tmpfs_mount_paths=()
    tmpfs_size_limits=()

    if [[ -n "$image" ]]
    then
      image=$(echo "$image" | envsubst)
      if [[ -n "$platform" ]]
      then
        log "📦 Pulling image $image for platform $platform for service $service_name"
        docker pull --platform "$platform" "$image"
        if import_image_into_k3d "$image" "$pod_name"
        then
          image_pull_policy="Never"
        else
          image_pull_policy="IfNotPresent"
          logwarn "⚠️ Could not import platform image $image into k3d; using imagePullPolicy=IfNotPresent"
        fi
      else
        # If the image is local, import it into k3d and force local usage.
        # Otherwise keep IfNotPresent so Kubernetes can pull it from registry.
        host_image_exists=1
        if docker image inspect "$image" >/dev/null 2>&1
        then
          host_image_exists=0
          if import_image_into_k3d "$image" "$pod_name"
          then
            load_ret=0
          else
            load_ret=1
          fi
        else
          load_ret=1
        fi

        if [[ "$load_ret" -eq 0 ]]
        then
          image_pull_policy="Never"
        elif [[ "$host_image_exists" -ne 0 ]]
        then
          logwarn "⚠️ Image $image was not found in host docker daemon; Kubernetes may attempt registry pull"
        else
          logwarn "⚠️ Could not import local image $image into k3d; Kubernetes may attempt registry pull"
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
      # Defer k3d import until after all large-file baking for this service
      deferred_import=1
    else
      continue
    fi

    if [[ -n "$volumes_list" ]]
    then
      volume_index=0
      IFS=';' read -r -a volume_items <<< "$volumes_list"
      for volume_item in "${volume_items[@]}"
      do
        if ! parsed_volume=$(parse_compose_file_volume_mount "$volume_item")
        then
          continue
        fi

        source_path="${parsed_volume%%|*}"
        target_path="${parsed_volume#*|}"
        source_path=$(echo "$source_path" | envsubst)
        target_path=$(echo "$target_path" | envsubst)

        if [[ "$source_path" = /* ]]
        then
          source_abs="$source_path"
        else
          source_abs="$compose_dir/$source_path"
        fi

        if [[ ! -f "$source_abs" ]]
        then
          if [[ -e "$source_abs" ]]
          then
            logwarn "⚠️ Compose volume source $source_abs for service $service_name is not a file, skipping"
          fi
          continue
        fi

        # K8s API server rejects objects > 3 MB. A 1 MB raw file base64-encodes to ~1.33 MB,
        # leaving comfortable headroom. Files larger than 1 MB are baked into the image instead.
        file_size_bytes=$(wc -c < "$source_abs" 2>/dev/null || echo 0)
        if [[ "$file_size_bytes" -gt 1048576 ]]
        then
          log "📦 Volume file $source_abs is $(( file_size_bytes / 1024 ))KB — too large for a Kubernetes Secret; baking into image $image instead"
          bake_tmp_dir=$(mktemp -d)
          bake_filename="$(basename "$source_abs")"
          cp "$source_abs" "${bake_tmp_dir}/"
          printf 'FROM %s\nCOPY %s %s\n' "$image" "$bake_filename" "$target_path" > "${bake_tmp_dir}/Dockerfile"
          if docker build -t "$image" "${bake_tmp_dir}" > /tmp/docker-bake-${pod_name}.log 2>&1
          then
            log "✅ Baked $bake_filename into image $image at $target_path"
            deferred_import=1
          else
            logwarn "⚠️ Could not bake $source_abs into image $image (see /tmp/docker-bake-${pod_name}.log); volume mount will be skipped"
          fi
          rm -rf "${bake_tmp_dir}"
          # File is now in the image; skip Secret creation and volume mount
          continue
        fi

        volume_index=$((volume_index + 1))
        volume_name="compose-file-${volume_index}"
        secret_name="$(sanitize_k8s_name "${pod_name}-${volume_name}")"
        secret_key="$(sanitize_secret_key "$(basename "$target_path")")"
        append_secret_manifest_from_file "$output_file" "$secret_name" "$source_abs" "$secret_key"
        volume_names+=("$volume_name")
        volume_secret_names+=("$secret_name")
        volume_mount_paths+=("$target_path")
        volume_secret_keys+=("$secret_key")
      done
    fi

    if [[ -n "$tmpfs_list" ]]
    then
      tmpfs_index=0
      IFS=';' read -r -a tmpfs_items <<< "$tmpfs_list"
      for tmpfs_item in "${tmpfs_items[@]}"
      do
        tmpfs_item=$(echo "$tmpfs_item" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
        if [[ -z "$tmpfs_item" ]]
        then
          continue
        fi

        tmpfs_path="${tmpfs_item%%:*}"
        tmpfs_path=$(echo "$tmpfs_path" | envsubst)
        tmpfs_path=$(echo "$tmpfs_path" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
        if [[ -z "$tmpfs_path" ]]
        then
          continue
        fi

        if [[ "$tmpfs_path" == "/dev/shm" ]]
        then
          tmpfs_size_limit="${CFK_TMPFS_SHM_SIZE_LIMIT}"
        else
          tmpfs_size_limit="${CFK_TMPFS_DEFAULT_SIZE_LIMIT}"
        fi

        tmpfs_index=$((tmpfs_index + 1))
        tmpfs_volume_name="compose-tmpfs-${tmpfs_index}"
        tmpfs_volume_names+=("$tmpfs_volume_name")
        tmpfs_mount_paths+=("$tmpfs_path")
        tmpfs_size_limits+=("$tmpfs_size_limit")
      done
    fi

    # Import the final (possibly baked) image into k3d once, after all volume processing.
    # This ensures k3d always receives the image with all files already baked in.
    if [[ "$deferred_import" -eq 1 ]]
    then
      if ! import_image_into_k3d "$image" "$pod_name" 1
      then
        logerror "❌ Could not import image $image into k3d for service $service_name"
        exit 1
      fi
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

    if [[ -n "$compose_user" ]]
    then
      compose_user=$(echo "$compose_user" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
      if [[ "$compose_user" == "root" ]] || [[ "$compose_user" == "0" ]] || [[ "$compose_user" == "0:0" ]]
      then
        run_as_user="0"
        run_as_group="0"
        run_as_non_root="false"
      elif [[ "$compose_user" =~ ^([0-9]+):([0-9]+)$ ]]
      then
        run_as_user="${BASH_REMATCH[1]}"
        run_as_group="${BASH_REMATCH[2]}"
      elif [[ "$compose_user" =~ ^[0-9]+$ ]]
      then
        run_as_user="$compose_user"
      else
        logwarn "⚠️ Unsupported compose user value '$compose_user' for service $service_name; skipping securityContext mapping"
      fi

      if [[ -n "$run_as_user" ]] || [[ -n "$run_as_group" ]] || [[ -n "$run_as_non_root" ]]
      then
        echo "      securityContext:" >> "$output_file"
        if [[ -n "$run_as_user" ]]
        then
          echo "        runAsUser: ${run_as_user}" >> "$output_file"
        fi
        if [[ -n "$run_as_group" ]]
        then
          echo "        runAsGroup: ${run_as_group}" >> "$output_file"
        fi
        if [[ -n "$run_as_non_root" ]]
        then
          echo "        runAsNonRoot: ${run_as_non_root}" >> "$output_file"
        fi
      fi
    fi

    if [[ "${#volume_names[@]}" -gt 0 ]] || [[ "${#tmpfs_volume_names[@]}" -gt 0 ]]
    then
      echo "      volumeMounts:" >> "$output_file"
      for tmpfs_index in "${!tmpfs_volume_names[@]}"
      do
        cat >> "$output_file" << EOF
        - name: ${tmpfs_volume_names[$tmpfs_index]}
          mountPath: ${tmpfs_mount_paths[$tmpfs_index]}
EOF
      done
      for volume_index in "${!volume_names[@]}"
      do
        cat >> "$output_file" << EOF
        - name: ${volume_names[$volume_index]}
          mountPath: ${volume_mount_paths[$volume_index]}
          subPath: ${volume_secret_keys[$volume_index]}
          readOnly: true
EOF
      done
    fi

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

    if [[ -n "$command_list" ]]
    then
      echo "      args:" >> "$output_file"
      IFS=';' read -r -a command_items <<< "$command_list"
      for command_item in "${command_items[@]}"
      do
        if [[ -z "$command_item" ]]
        then
          continue
        fi
        # Remove leading/trailing quotes from YAML array items if present
        clean_item=$(echo "$command_item" | sed -e 's/^[[:space:]]*"//; s/"[[:space:]]*$//')
        echo "        - $clean_item" >> "$output_file"
      done
    fi

    if [[ -n "$entrypoint_list" ]]
    then
      echo "      command:" >> "$output_file"
      IFS=';' read -r -a entrypoint_items <<< "$entrypoint_list"
      for entrypoint_item in "${entrypoint_items[@]}"
      do
        if [[ -z "$entrypoint_item" ]]
        then
          continue
        fi
        # Remove leading/trailing quotes from YAML array items if present
        clean_item=$(echo "$entrypoint_item" | sed -e 's/^[[:space:]]*"//; s/"[[:space:]]*$//')
        echo "        - $clean_item" >> "$output_file"
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

    # Solace source examples rely on SMF over 55555, which may be omitted from
    # compose overrides because host exposure is not required in Docker mode.
    # Ensure the in-cluster Service still exposes 55555 so Connect can reach Solace.
    if [[ "$pod_name" == "solace" ]] && [[ ! " ${parsed_ports[*]} " =~ " 55555 " ]]
    then
      if [[ "$has_any_port" -eq 0 ]]
      then
        echo "      ports:" >> "$output_file"
        has_any_port=1
      fi
      parsed_ports+=("55555")
      echo "        - containerPort: 55555" >> "$output_file"
    fi

    if [[ "${#volume_names[@]}" -gt 0 ]] || [[ "${#tmpfs_volume_names[@]}" -gt 0 ]]
    then
      echo "  volumes:" >> "$output_file"
      for tmpfs_index in "${!tmpfs_volume_names[@]}"
      do
        cat >> "$output_file" << EOF
    - name: ${tmpfs_volume_names[$tmpfs_index]}
      emptyDir:
        medium: Memory
        sizeLimit: ${tmpfs_size_limits[$tmpfs_index]}
EOF
      done
      for volume_index in "${!volume_names[@]}"
      do
        cat >> "$output_file" << EOF
    - name: ${volume_names[$volume_index]}
      secret:
        secretName: ${volume_secret_names[$volume_index]}
EOF
      done
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

function collect_connect_ports_from_compose() {
  local compose_file="$1"
  local output_file="$2"

  if [[ ! -f "$compose_file" ]]
  then
    return 1
  fi

  awk '
    function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
    function unquote(s) { gsub(/^"|"$/, "", s); gsub(/^\047|\047$/, "", s); return s }

    BEGIN { in_services=0; service=""; section="" }
    /^services:[[:space:]]*$/ { in_services=1; next }

    {
      if (in_services == 1 && $0 ~ /^[^[:space:]]/) {
        in_services=0
      }
      if (in_services == 0) {
        next
      }

      if ($0 ~ /^  [A-Za-z0-9_.-]+:[[:space:]]*$/) {
        service=$1
        sub(/:$/, "", service)
        section=""
        next
      }

      if (service != "connect") {
        next
      }

      if ($0 ~ /^    ports:[[:space:]]*$/) {
        section="ports"
        next
      }

      if ($0 ~ /^    [A-Za-z0-9_.-]+:[[:space:]]*$/) {
        section=""
      }

      if (section == "ports" && $0 ~ /^[[:space:]]*-[[:space:]]*/) {
        value=$0
        sub(/^[[:space:]]*-[[:space:]]*/, "", value)
        value=trim(unquote(value))
        if (value != "") {
          print value
        }
      }
    }
  ' "$compose_file" > "$output_file"

  if [[ -s "$output_file" ]]
  then
    return 0
  fi

  rm -f "$output_file"
  return 1
}

function parse_compose_connect_port_mapping() {
  local raw_port="$1"
  local protocol="tcp"
  local local_port=""
  local target_port=""
  local IFS=':'
  local parts=()
  local count=0

  raw_port=$(echo "$raw_port" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
  raw_port=$(echo "$raw_port" | sed -E "s/^'|'$//g; s/^\"|\"$//g")

  if [[ "$raw_port" == */* ]]
  then
    protocol=$(echo "$raw_port" | awk -F'/' '{print tolower($NF)}')
    raw_port="${raw_port%%/*}"
  fi

  read -r -a parts <<< "$raw_port"
  count=${#parts[@]}

  if [[ "$count" -ge 2 ]]
  then
    local_port="${parts[$((count-2))]}"
    target_port="${parts[$((count-1))]}"
  elif [[ "$count" -eq 1 ]]
  then
    local_port="${parts[0]}"
    target_port="${parts[0]}"
  else
    return 1
  fi

  local_port="${local_port##*:}"
  target_port="${target_port##*:}"

  if [[ "$local_port" == *-* ]]
  then
    local_port="${local_port%%-*}"
  fi
  if [[ "$target_port" == *-* ]]
  then
    target_port="${target_port%%-*}"
  fi

  if [[ ! "$local_port" =~ ^[0-9]+$ ]] || [[ ! "$target_port" =~ ^[0-9]+$ ]]
  then
    return 1
  fi

  echo "${local_port}|${target_port}|${protocol}"
  return 0
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
    while IFS=: read -r compose_line raw_paths
    do
      raw_paths=$(echo "$raw_paths" | sed -E 's/.*CONNECT_PLUGIN_PATH[[:space:]]*:[[:space:]]*//')
      raw_paths=$(echo "$raw_paths" | sed -E "s/[\"']//g" | sed -E 's/[[:space:]]+#.*$//')
      log "🔎 CONNECT_PLUGIN_PATH source: ${compose_file}:${compose_line}"
      log "🔎 CONNECT_PLUGIN_PATH tokens from compose: $raw_paths"

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
          logwarn "⚠️ Ignoring CONNECT_PLUGIN_PATH token '$plugin_path' because owner/name could not be derived"
          continue
        fi

        log "🔎 Derived plugin tuple from CONNECT_PLUGIN_PATH: owner=$owner name=$name plugin_id=$plugin_id"

        echo "$owner|$name|$plugin_id" >> "$tmp_plugins_file"
      done
    done < <(grep -En 'CONNECT_PLUGIN_PATH[[:space:]]*:' "$compose_file" 2>/dev/null)
  fi

  if [[ -s "$tmp_plugins_file" ]]
  then
    awk '!seen[$0]++' "$tmp_plugins_file" > "$tmp_plugins_unique_file"
    while IFS='|' read -r owner name plugin_id
    do
      log "🔎 Selected plugin for CFK build: owner=$owner name=$name plugin_id=$plugin_id"
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
        local_zip_checksum=$(checksum_sha512 "$local_zip_path")
        local_zip_url="http://${CFK_CONNECTOR_ARCHIVE_HOST}:18080/${plugin_id}.zip"
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

function build_cfk_manifest() {
  local output_file="$1"
  local rendered_file
  local base_manifest_file
  local include_control_center=0
  local include_ksqldb=0
  local include_restproxy=0
  local kafka_replicas=1
  local connect_replicas=1

  rendered_file=$(mktemp)
  base_manifest_file=$(mktemp)

  envsubst '${CP_SERVER_IMAGE} ${CP_SERVER_TAG} ${CP_CONNECT_IMAGE} ${CP_CONNECT_TAG} ${CP_SCHEMA_REGISTRY_IMAGE} ${CP_SCHEMA_REGISTRY_TAG} ${CP_CONTROL_CENTER_IMAGE} ${CP_CONTROL_CENTER_TAG} ${CP_INIT_IMAGE} ${CP_INIT_TAG} ${CFK_CONNECT_PLUGIN_PATH}' < "${DIR}/confluent-platform.yaml" > "$rendered_file"

  if [[ -n "$ENABLE_CONTROL_CENTER" ]]
  then
    include_control_center=1
  else
    log "🛑 Control Center is disabled for CFK deployment"
  fi

  if [[ -n "$ENABLE_KSQLDB" ]]
  then
    include_ksqldb=1
    log "🚀 ksqlDB is enabled for CFK deployment"
  fi

  if [[ -n "$ENABLE_RESTPROXY" ]]
  then
    include_restproxy=1
    log "📲 REST Proxy is enabled for CFK deployment"
  fi

  if [[ -n "$ENABLE_KAFKA_NODES" ]]
  then
    kafka_replicas=3
    log "3️⃣  Kafka replicas set to 3 for CFK deployment"
  fi

  if [[ -n "$ENABLE_CONNECT_NODES" ]]
  then
    connect_replicas=3
    log "🥉 Connect replicas set to 3 for CFK deployment"
  fi

  # Filter ControlCenter and patch Kafka/Connect replicas based on set_profiles options.
  awk -v include_control_center="$include_control_center" -v kafka_replicas="$kafka_replicas" -v connect_replicas="$connect_replicas" '
    function emit_doc(d) {
      if (d ~ /^[[:space:]]*$/) {
        return
      }

      if (d ~ /kind:[[:space:]]*ControlCenter([[:space:]]|$)/ && include_control_center != 1) {
        return
      }

      if (d ~ /kind:[[:space:]]*Kafka([[:space:]]|$)/) {
        sub(/replicas:[[:space:]]*[0-9]+/, "replicas: " kafka_replicas, d)
      }

      if (d ~ /kind:[[:space:]]*Connect([[:space:]]|$)/) {
        sub(/replicas:[[:space:]]*[0-9]+/, "replicas: " connect_replicas, d)
      }

      if (emitted_docs > 0) {
        print "---"
      }
      printf "%s", d
      emitted_docs++
    }

    BEGIN {
      doc = ""
      emitted_docs = 0
    }

    /^---[[:space:]]*$/ {
      emit_doc(doc)
      doc = ""
      next
    }

    {
      doc = doc $0 "\n"
    }

    END {
      emit_doc(doc)
    }
  ' "$rendered_file" > "$base_manifest_file"

  cp "$base_manifest_file" "$output_file"

  if [[ "$include_ksqldb" -eq 1 ]]
  then
    cat >> "$output_file" << EOF
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ksqldb-server
  namespace: confluent
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ksqldb-server
  template:
    metadata:
      labels:
        app: ksqldb-server
    spec:
      containers:
        - name: ksqldb-server
          image: ${CP_KSQL_IMAGE}:${CP_KSQL_TAG}
          ports:
            - containerPort: 8088
          env:
            - name: KSQL_BOOTSTRAP_SERVERS
              value: "kafka:9071"
            - name: KSQL_LISTENERS
              value: "http://0.0.0.0:8088"
            - name: KSQL_KSQL_SERVICE_ID
              value: "playground_"
            - name: KSQL_SCHEMA_REGISTRY_URL
              value: "http://schemaregistry:8081"
            - name: KSQL_KSQL_LOGGING_PROCESSING_TOPIC_REPLICATION_FACTOR
              value: "1"
            - name: KSQL_KSQL_LOGGING_PROCESSING_STREAM_AUTO_CREATE
              value: "true"
            - name: KSQL_KSQL_LOGGING_PROCESSING_TOPIC_AUTO_CREATE
              value: "true"
---
apiVersion: v1
kind: Service
metadata:
  name: ksqldb-server
  namespace: confluent
spec:
  selector:
    app: ksqldb-server
  ports:
    - name: ksqldb
      port: 8088
      targetPort: 8088
EOF
  fi

  if [[ "$include_restproxy" -eq 1 ]]
  then
    cat >> "$output_file" << EOF
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: restproxy
  namespace: confluent
spec:
  replicas: 1
  selector:
    matchLabels:
      app: restproxy
  template:
    metadata:
      labels:
        app: restproxy
    spec:
      containers:
        - name: restproxy
          image: ${CP_REST_PROXY_IMAGE}:${CP_REST_PROXY_TAG}
          ports:
            - containerPort: 8082
          env:
            - name: KAFKA_REST_BOOTSTRAP_SERVERS
              value: "kafka:9071"
            - name: KAFKA_REST_LISTENERS
              value: "http://0.0.0.0:8082"
            - name: KAFKA_REST_HOST_NAME
              value: "restproxy"
            - name: KAFKA_REST_SCHEMA_REGISTRY_URL
              value: "http://schemaregistry:8081"
---
apiVersion: v1
kind: Service
metadata:
  name: restproxy
  namespace: confluent
spec:
  selector:
    app: restproxy
  ports:
    - name: restproxy
      port: 8082
      targetPort: 8082
EOF
  fi

  rm -f "$base_manifest_file"
  rm -f "$rendered_file"
}

function log_unsupported_cfk_profile_options() {
  if [[ -n "$ENABLE_ZOOKEEPER" ]]
  then
    logwarn "⚠️ ENABLE_ZOOKEEPER is ignored in CFK mode (CFK deployment is KRaft-only)"
  fi

  if [[ -n "$ENABLE_JMX_GRAFANA" ]]
  then
    logwarn "⚠️ ENABLE_JMX_GRAFANA is not implemented in environment/cfk/start.sh"
  fi

  if [[ -n "$ENABLE_KCAT" ]]
  then
    logwarn "⚠️ ENABLE_KCAT is not implemented in environment/cfk/start.sh"
  fi

  if [[ -n "$ENABLE_CONDUKTOR" ]]
  then
    logwarn "⚠️ ENABLE_CONDUKTOR is not implemented in environment/cfk/start.sh"
  fi

  if [[ -n "$ENABLE_FLINK" ]]
  then
    logwarn "⚠️ ENABLE_FLINK is not implemented in environment/cfk/start.sh"
  fi

}

DOCKER_COMPOSE_FILE_OVERRIDE=$1
if [ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]
then
  check_arm64_support "${DIR}" "${DOCKER_COMPOSE_FILE_OVERRIDE}"
fi
export PLAYGROUND_CFK_MODE=1
set_profiles
log_unsupported_cfk_profile_options

CONNECT_BUILD_PATCH_FILE=""
CONNECT_BUILD_EXPECTED_PLUGIN_NAMES=""
CONNECT_BUILD_PATCH_CHECKSUM=""
CONNECTOR_ZIP_URL=""
CONNECTOR_ZIP_CHECKSUM=""
CONNECTOR_ZIP_PLUGIN_NAME=""
CONNECTOR_ZIP_DIR=""
CONNECTOR_ZIP_SERVER_PID=""
EXTRA_PODS_FILE=""
CFK_MANIFEST_FILE=""
K3D_CONFIG_FILE=""
CONNECT_MOUNT_RESOURCES_FILE=""
CONNECT_MOUNT_PATCH_FILE=""
CONNECT_ENV_PATCH_FILE=""

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
    CONNECTOR_ZIP_CHECKSUM=$(checksum_sha512 "$tmp_connector_zip_download")
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
    CONNECTOR_ZIP_CHECKSUM=$(checksum_sha512 "$CONNECTOR_ZIP")
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
fi

log "Start or reuse k3d (k3s)"
if k3d cluster list 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "$K3D_CLUSTER_NAME"
then
  log "✅ k3d cluster $K3D_CLUSTER_NAME already exists, ensuring it is running"
  k3d cluster start "$K3D_CLUSTER_NAME" >/dev/null 2>&1 || true
else
  log "🚀 Creating k3d cluster $K3D_CLUSTER_NAME"
  if [[ "$K3D_REGISTRY_CACHE_ENABLED" == "1" ]]
  then
    K3D_CONFIG_FILE=$(mktemp)
    generate_k3d_config_with_registry_cache "$K3D_CONFIG_FILE"
    log "🗂️ Using registry cache for k3d cluster creation (${K3D_REGISTRY_CACHE_NAME}:${K3D_REGISTRY_CACHE_PORT})"
    k3d cluster create --config "$K3D_CONFIG_FILE" --wait
  else
    k3d cluster create "$K3D_CLUSTER_NAME" --servers 1 --agents 0 --wait
  fi
fi

kubectl config use-context "k3d-${K3D_CLUSTER_NAME}" >/dev/null

if ! wait_for_kubernetes_apiserver "120"
then
  logerror "❌ Kubernetes API server did not become ready within 120s"
  exit 1
fi

set +e
resolve_cfk_connector_archive_host
set -e
if [[ -n "$CONNECTOR_ZIP_DIR" ]] && [[ -z "$CONNECTOR_ZIP_URL" ]]
then
  connector_zip_basename=""
  while IFS= read -r connector_zip_path
  do
    connector_zip_basename=$(basename "$connector_zip_path")
    break
  done < <(find "$CONNECTOR_ZIP_DIR" -maxdepth 1 -name '*.zip' 2>/dev/null)
  if [[ -n "$connector_zip_basename" ]]
  then
    CONNECTOR_ZIP_URL="http://${CFK_CONNECTOR_ARCHIVE_HOST}:18080/$connector_zip_basename"
  fi
fi

if [[ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]]
then
  CONNECT_BUILD_PATCH_FILE=$(mktemp)
  if generate_connect_build_patch_from_compose "${DOCKER_COMPOSE_FILE_OVERRIDE}" "${CONNECT_BUILD_PATCH_FILE}" "$CONNECTOR_ZIP_URL" "$CONNECTOR_ZIP_CHECKSUM" "$CONNECTOR_ZIP_PLUGIN_NAME" "$CONNECTOR_ZIP_DIR"
  then
    CONNECT_BUILD_PATCH_CHECKSUM=$(checksum_sha512 "${CONNECT_BUILD_PATCH_FILE}")
    CONNECT_BUILD_EXPECTED_PLUGIN_NAMES=$(awk '/^[[:space:]]*- name:[[:space:]]*/ {print $3}' "${CONNECT_BUILD_PATCH_FILE}" | paste -sd ',' -)
    log "🔌 CFK Connect build plugins will be patched dynamically"
    log "🔎 Connect build patch checksum (sha512): ${CONNECT_BUILD_PATCH_CHECKSUM}"
    if [[ -n "$CONNECT_BUILD_EXPECTED_PLUGIN_NAMES" ]]
    then
      log "🔎 Expected plugin names from build patch: ${CONNECT_BUILD_EXPECTED_PLUGIN_NAMES}"
    fi
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
    CONNECT_BUILD_PATCH_CHECKSUM=$(checksum_sha512 "${CONNECT_BUILD_PATCH_FILE}")
    CONNECT_BUILD_EXPECTED_PLUGIN_NAMES=$(awk '/^[[:space:]]*- name:[[:space:]]*/ {print $3}' "${CONNECT_BUILD_PATCH_FILE}" | paste -sd ',' -)
    log "🔎 Connect build patch checksum (sha512): ${CONNECT_BUILD_PATCH_CHECKSUM}"
    if [[ -n "$CONNECT_BUILD_EXPECTED_PLUGIN_NAMES" ]]
    then
      log "🔎 Expected plugin names from build patch: ${CONNECT_BUILD_EXPECTED_PLUGIN_NAMES}"
    fi
    log_generated_yaml_file "Dynamic Connect build patch generated:" "${CONNECT_BUILD_PATCH_FILE}"
  fi
fi

if [[ -n "$CONNECTOR_ZIP_DIR" ]] && [[ -n "$(find "$CONNECTOR_ZIP_DIR" -maxdepth 1 -name '*.zip' -print -quit 2>/dev/null)" ]]
then
  log "Serve local CONNECTOR_ZIP for CFK on-demand plugin download"

  # Avoid stale listeners from previous runs serving the wrong directory on 18080.
  set +e
  lsof -i ":18080" 2>/dev/null | awk 'NR>1 {print $2}' | xargs kill -9 2>/dev/null || true
  
  # Clean up old connector archive directory from previous run
  if [[ -f /tmp/cfk-connector-archive-dir.state ]]
  then
    old_connector_zip_dir=$(cat /tmp/cfk-connector-archive-dir.state 2>/dev/null)
    if [[ -n "$old_connector_zip_dir" ]] && [[ "$old_connector_zip_dir" != "$CONNECTOR_ZIP_DIR" ]] && [[ -d "$old_connector_zip_dir" ]]
    then
      rm -rf "$old_connector_zip_dir" 2>/dev/null || true
    fi
  fi
  
  # Save current connector archive directory for cleanup on next run
  echo "$CONNECTOR_ZIP_DIR" > /tmp/cfk-connector-archive-dir.state 2>/dev/null || true
  
  set -e

  python3 -m http.server 18080 --directory "$CONNECTOR_ZIP_DIR" >/tmp/cfk-connector-zip-http.log 2>&1 &
  CONNECTOR_ZIP_SERVER_PID=$!
  disown "$CONNECTOR_ZIP_SERVER_PID" 2>/dev/null || true

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
    log "✅ Local plugin archive is served at http://${CFK_CONNECTOR_ARCHIVE_HOST}:18080/${local_served_zip_name}"
  fi
fi

log "Build/patch CP images in host docker daemon"
# Build/patch CP images locally, then import them into k3d.
maybe_create_image

for base_image in \
  "${CP_SERVER_IMAGE}:${CP_SERVER_TAG}" \
  "${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG}" \
  "${CP_SCHEMA_REGISTRY_IMAGE}:${CP_SCHEMA_REGISTRY_TAG}" \
  "${CP_INIT_IMAGE}:${CP_INIT_TAG}"
do
  if docker image inspect "$base_image" >/dev/null 2>&1
  then
    import_image_into_k3d "$base_image" "$(echo "$base_image" | tr '/:.' '_')" || true
  fi
done

if [[ -n "$ENABLE_CONTROL_CENTER" ]] && docker image inspect "${CP_CONTROL_CENTER_IMAGE}:${CP_CONTROL_CENTER_TAG}" >/dev/null 2>&1
then
  import_image_into_k3d "${CP_CONTROL_CENTER_IMAGE}:${CP_CONTROL_CENTER_TAG}" "control-center" || true
fi

if [[ -n "$ENABLE_KSQLDB" ]] && docker image inspect "${CP_KSQL_IMAGE}:${CP_KSQL_TAG}" >/dev/null 2>&1
then
  import_image_into_k3d "${CP_KSQL_IMAGE}:${CP_KSQL_TAG}" "ksqldb" || true
fi

if [[ -n "$ENABLE_RESTPROXY" ]] && docker image inspect "${CP_REST_PROXY_IMAGE}:${CP_REST_PROXY_TAG}" >/dev/null 2>&1
then
  import_image_into_k3d "${CP_REST_PROXY_IMAGE}:${CP_REST_PROXY_TAG}" "restproxy" || true
fi

if [[ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]]
then
  CONNECT_MOUNT_RESOURCES_FILE=$(mktemp)
  CONNECT_MOUNT_PATCH_FILE=$(mktemp)
  if ! generate_connect_mounted_volumes_from_compose "${DOCKER_COMPOSE_FILE_OVERRIDE}" "${CONNECT_MOUNT_RESOURCES_FILE}" "${CONNECT_MOUNT_PATCH_FILE}"
  then
    rm -f "${CONNECT_MOUNT_RESOURCES_FILE}" "${CONNECT_MOUNT_PATCH_FILE}"
    CONNECT_MOUNT_RESOURCES_FILE=""
    CONNECT_MOUNT_PATCH_FILE=""
  else
    log_generated_yaml_file "Dynamic Connect mounted volumes patch generated:" "${CONNECT_MOUNT_PATCH_FILE}"
  fi

  CONNECT_ENV_PATCH_FILE=$(mktemp)
  if ! generate_connect_env_patch_from_compose "${DOCKER_COMPOSE_FILE_OVERRIDE}" "${CONNECT_ENV_PATCH_FILE}"
  then
    rm -f "${CONNECT_ENV_PATCH_FILE}"
    CONNECT_ENV_PATCH_FILE=""
  else
    log_generated_yaml_file "Dynamic Connect environment patch generated:" "${CONNECT_ENV_PATCH_FILE}"
  fi

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
CFK_MANIFEST_FILE=$(mktemp)
build_cfk_manifest "$CFK_MANIFEST_FILE"
if [[ -z "$GITHUB_RUN_NUMBER" ]]
then
  log_generated_yaml_file "📋 Generated CFK manifest:" "$CFK_MANIFEST_FILE"
fi
kubectl apply -f "$CFK_MANIFEST_FILE"

if [[ -n "$CONNECT_MOUNT_RESOURCES_FILE" ]] && [[ -s "$CONNECT_MOUNT_RESOURCES_FILE" ]]
then
  log "Deploy file-backed Secrets from DOCKER_COMPOSE_FILE_OVERRIDE for Connect mounts"
  # Use server-side apply to avoid storing large last-applied annotations on Secrets.
  kubectl -n confluent apply --server-side --force-conflicts -f "$CONNECT_MOUNT_RESOURCES_FILE"
fi

if [[ -n "$EXTRA_PODS_FILE" ]] && [[ -s "$EXTRA_PODS_FILE" ]]
then
  log "Deploy extra pods from DOCKER_COMPOSE_FILE_OVERRIDE (excluding connect)"
  kubectl -n confluent apply -f "$EXTRA_PODS_FILE"
fi

patched_connect_spec=0

if [[ -n "$CONNECT_MOUNT_PATCH_FILE" ]] && [[ -s "$CONNECT_MOUNT_PATCH_FILE" ]]
then
  log "Patch Connect mounted volumes from compose file mounts"
  connect_mount_patch_error_log="/tmp/cfk-connect-mount-patch.error.log"
  : > "$connect_mount_patch_error_log"
  set +e
  for _ in {1..30}
  do
    kubectl -n confluent patch connect connect --type merge --patch-file "$CONNECT_MOUNT_PATCH_FILE" > /dev/null 2> "$connect_mount_patch_error_log"
    if [[ $? -eq 0 ]]
    then
      patched_connect_spec=1
      break
    fi
    sleep 2
  done
  if [[ "$patched_connect_spec" -ne 1 ]]
  then
    logerror "❌ Could not patch connect/connect mounted volumes in CFK"
    if [[ -s "$connect_mount_patch_error_log" ]]
    then
      logerror "Patch error details:"
      sed 's/^/  /' "$connect_mount_patch_error_log"
    fi
    exit 1
  fi
  set -e
fi

if [[ -n "$CONNECT_ENV_PATCH_FILE" ]] && [[ -s "$CONNECT_ENV_PATCH_FILE" ]]
then
  log "Patch Connect environment variables from compose override"
  patched_connect_env=0
  set +e
  for _ in {1..30}
  do
    kubectl -n confluent patch connect connect --type merge --patch-file "$CONNECT_ENV_PATCH_FILE" > /dev/null 2>&1
    if [[ $? -eq 0 ]]
    then
      patched_connect_env=1
      break
    fi
    sleep 2
  done
  if [[ "$patched_connect_env" -ne 1 ]]
  then
    logerror "❌ Could not patch connect/connect environment variables in CFK"
    exit 1
  fi
  set -e
  patched_connect_spec=1
fi

if [[ -n "$CONNECT_BUILD_PATCH_FILE" ]] && [[ -s "$CONNECT_BUILD_PATCH_FILE" ]]
then
  if ! verify_build_archive_urls_reachable_from_cluster "$CONNECT_BUILD_PATCH_FILE"
  then
    logerror "❌ Aborting: Connect build archive URLs are not reachable from cluster"
    exit 1
  fi

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
  patched_connect_spec=1
fi

if [[ "$patched_connect_spec" -eq 1 ]]
then
  # The Connect CR may have already scheduled a pod before the patches were
  # processed. Force-delete connect-0 so CFK recreates it from the updated spec.
  log "🔄 Restarting connect-0 to ensure patched Connect spec takes effect"
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
  connect_plugins_json=""
  connect_plugin_classes_rest=""
  connect_expected_plugin_total=0
  connect_expected_plugin_match=0
  connect_expected_plugin_array=()
  if [[ -n "$CONNECT_BUILD_EXPECTED_PLUGIN_NAMES" ]]
  then
    IFS=',' read -r -a connect_expected_plugin_array <<< "$CONNECT_BUILD_EXPECTED_PLUGIN_NAMES"
  fi
  while true
  do
    connect_plugins_json=$(kubectl -n confluent exec connect-0 -- curl -fsS --max-time 5 http://localhost:8083/connector-plugins 2>/dev/null)
    connect_plugin_count_rest=$(printf '%s' "$connect_plugins_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d))" 2>/dev/null)
    connect_plugin_classes_rest=$(printf '%s' "$connect_plugins_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(' '.join(sorted({x.get('class','') for x in d if isinstance(x,dict) and x.get('class')})))" 2>/dev/null)
    connect_plugin_count_status=$(kubectl -n confluent get connect connect -o jsonpath='{.status.connectorPlugins[*].class}' 2>/dev/null | awk '{print NF}')
    connect_plugin_count="0"
    connect_plugin_count_source="rest"
    if [[ "$connect_plugin_count_rest" =~ ^[0-9]+$ ]]
    then
      connect_plugin_count="$connect_plugin_count_rest"
    fi
    if [[ "$connect_plugin_count" -eq 0 ]] && [[ "$connect_plugin_count_status" =~ ^[0-9]+$ ]] && [[ "$connect_plugin_count_status" -gt 0 ]]
    then
      connect_plugin_count="$connect_plugin_count_status"
      connect_plugin_count_source="status"
    fi

    connect_expected_plugin_total=0
    connect_expected_plugin_match=0
    if [[ -n "$connect_plugin_classes_rest" ]] && [[ "${#connect_expected_plugin_array[@]}" -gt 0 ]]
    then
      plugin_classes_lc=$(echo "$connect_plugin_classes_rest" | tr '[:upper:]' '[:lower:]')
      for expected_plugin_name in "${connect_expected_plugin_array[@]}"
      do
        expected_plugin_name=$(echo "$expected_plugin_name" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
        if [[ -z "$expected_plugin_name" ]]
        then
          continue
        fi
        connect_expected_plugin_total=$((connect_expected_plugin_total + 1))

        expected_matched=0
        expected_plugin_lc=$(echo "$expected_plugin_name" | tr '[:upper:]' '[:lower:]')
        if echo "$plugin_classes_lc" | grep -q "$expected_plugin_lc"
        then
          expected_matched=1
        else
          for token in $(echo "$expected_plugin_lc" | tr -cs 'a-z0-9' '\n')
          do
            # Keep short but meaningful tokens like "s3" while filtering generic words.
            if [[ ${#token} -lt 2 ]] || [[ "$token" =~ ^[0-9]+$ ]] || [[ "$token" == "kafka" ]] || [[ "$token" == "connect" ]] || [[ "$token" == "confluentinc" ]] || [[ "$token" == "plugin" ]] || [[ "$token" == "source" ]] || [[ "$token" == "sink" ]]
            then
              continue
            fi
            if echo "$plugin_classes_lc" | grep -q "$token"
            then
              expected_matched=1
              break
            fi
          done
        fi

        if [[ "$expected_matched" -eq 1 ]]
        then
          connect_expected_plugin_match=$((connect_expected_plugin_match + 1))
        fi
      done
    fi

    if [[ "$connect_plugin_count" =~ ^[0-9]+$ ]] && [[ "$connect_plugin_count" -gt 3 ]]
    then
      if [[ "$connect_expected_plugin_total" -gt 0 ]] && [[ "$connect_expected_plugin_match" -eq 0 ]]
      then
        log "  ⌛ Connect has >3 plugins but none match expected build plugin names yet (${connect_expected_plugin_match}/${connect_expected_plugin_total})"
      else
      log "✅ Connect reports $connect_plugin_count connector plugins via $connect_plugin_count_source (on-demand build complete)"
      break
      fi
    fi
    connect_build_cur_wait=$(( connect_build_cur_wait + connect_build_interval ))
    if [[ "$connect_build_cur_wait" -ge "$connect_build_wait_max" ]]
    then
      logerror "❌ Only $connect_plugin_count plugins visible after ${connect_build_wait_max}s — on-demand build failed"
      if [[ -n "$CONNECT_BUILD_PATCH_CHECKSUM" ]]
      then
        log "  Connect build patch checksum (sha512): ${CONNECT_BUILD_PATCH_CHECKSUM}"
      fi
      if [[ -n "$CONNECT_BUILD_EXPECTED_PLUGIN_NAMES" ]]
      then
        log "  Expected plugin names from patch: ${CONNECT_BUILD_EXPECTED_PLUGIN_NAMES}"
      fi
      log "  Connect plugin classes from REST (if reachable):"
      kubectl -n confluent exec connect-0 -- curl -fsS --max-time 5 http://localhost:8083/connector-plugins 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print('\n'.join(sorted({x.get('class','') for x in d if isinstance(x,dict) and x.get('class')})))" 2>/dev/null || true
      log "  Init container logs:"
      kubectl -n confluent logs connect-0 -c config-init-container 2>/dev/null | tail -30 || true
      log "  Connect container logs (tail 200):"
      kubectl -n confluent logs connect-0 -c connect --tail=200 2>/dev/null || true
      log "  Connect CR build spec:"
      kubectl -n confluent get connect connect -o json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(json.dumps(d.get('spec',{}).get('build',{}), indent=2))" 2>/dev/null || true
      log "  Connect CR status:"
      kubectl -n confluent get connect connect -o jsonpath='{.status}' 2>/dev/null | python3 -m json.tool 2>/dev/null || true
      log "  Connect CR events:"
      kubectl -n confluent describe connect connect 2>/dev/null | sed -n '/Events:/,$p' | tail -80 || true
      log "  Namespace events (tail 80):"
      kubectl -n confluent get events --sort-by='.lastTimestamp' 2>/dev/null | tail -80 || true
      exit 1
    fi
    if [[ "$connect_expected_plugin_total" -gt 0 ]]
    then
      log "  ⌛ Connect plugins=${connect_plugin_count} via ${connect_plugin_count_source}, expected-plugin-match=${connect_expected_plugin_match}/${connect_expected_plugin_total}, elapsed: ${connect_build_cur_wait}/${connect_build_wait_max}s"
    else
      log "  ⌛ Connect plugins=${connect_plugin_count} via ${connect_plugin_count_source} (waiting for >3), elapsed: ${connect_build_cur_wait}/${connect_build_wait_max}s"
    fi
    sleep "$connect_build_interval"
  done
  set -e
fi

CONTROL_CENTER_PF_PID=""
SCHEMA_REGISTRY_PF_PID=""
CONNECT_PF_PID=""
CONNECT2_PF_PID=""
CONNECT3_PF_PID=""
KSQLDB_PF_PID=""
REST_PROXY_PF_PID=""
cleanup() {
  # Note: CONNECTOR_ZIP_SERVER_PID is intentionally NOT killed here
  # It continues running to support `playground container update` and similar operations
  # The server is killed at the start of the next run if a new one needs to be started
  
  # Also DO NOT delete CONNECTOR_ZIP_DIR while the server is running
  # The directory will be cleaned up when the server is killed at the start of the next run
  
  if [ -n "$CONNECT_BUILD_PATCH_FILE" ]
  then
    rm -f "$CONNECT_BUILD_PATCH_FILE" >/dev/null 2>&1 || true
  fi
  if [ -n "$EXTRA_PODS_FILE" ]
  then
    rm -f "$EXTRA_PODS_FILE" >/dev/null 2>&1 || true
  fi
  if [ -n "$CFK_MANIFEST_FILE" ]
  then
    rm -f "$CFK_MANIFEST_FILE" >/dev/null 2>&1 || true
  fi
  if [ -n "$CONNECT_MOUNT_RESOURCES_FILE" ]
  then
    rm -f "$CONNECT_MOUNT_RESOURCES_FILE" >/dev/null 2>&1 || true
  fi
  if [ -n "$CONNECT_MOUNT_PATCH_FILE" ]
  then
    rm -f "$CONNECT_MOUNT_PATCH_FILE" >/dev/null 2>&1 || true
  fi
  if [ -n "$CONNECT_ENV_PATCH_FILE" ]
  then
    rm -f "$CONNECT_ENV_PATCH_FILE" >/dev/null 2>&1 || true
  fi
  if [ -n "$K3D_CONFIG_FILE" ]
  then
    rm -f "$K3D_CONFIG_FILE" >/dev/null 2>&1 || true
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
  local endpoint_count=""

  while [[ "$waited" -lt "$max_wait_seconds" ]]
  do
    if kubectl -n confluent get service "$service" >/dev/null 2>&1
    then
      endpoint_count=$(kubectl -n confluent get endpoints "$service" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w | tr -d '[:space:]')
      if [[ -n "$endpoint_count" ]] && [[ "$endpoint_count" -gt 0 ]]
      then
        pf_pid=$(start_port_forward "$service" "$local_port" "$remote_port" "$log_file" "$description")
        if [[ -n "$pf_pid" ]]
        then
          echo "$pf_pid"
          return 0
        fi
      fi
    fi

    sleep "$wait_interval"
    waited=$(( waited + wait_interval ))
  done

  logwarn "⚠️ Timed out after ${max_wait_seconds}s starting port-forward for $description"
  return 1
}

function start_pod_port_forward() {
  local pod_name="$1"
  local local_port="$2"
  local remote_port="$3"
  local log_file="$4"
  local description="$5"

  log "🔀 Starting port-forward for $description (local:$local_port -> pod $pod_name:$remote_port)"

  set +e
  lsof -i ":${local_port}" 2>/dev/null | grep -i kubectl | awk '{print $2}' | xargs kill -9 2>/dev/null || true
  set -e

  sleep 1

  kubectl -n confluent port-forward "pod/${pod_name}" "${local_port}:${remote_port}" >"${log_file}" 2>&1 &
  local pf_pid=$!

  sleep 2

  if ! kill -0 "$pf_pid" 2>/dev/null
  then
    logwarn "⚠️ Port-forward for $description (port $local_port) failed to start"
    cat "${log_file}" | head -10 | while read -r line; do logwarn "  $line"; done
    return 1
  fi

  if grep -i "error\|unable\|failed" "${log_file}" > /dev/null 2>&1
  then
    logwarn "⚠️ Port-forward for $description may have encountered an error"
    cat "${log_file}" | head -10 | while read -r line; do logwarn "  $line"; done
    return 1
  fi

  echo "$pf_pid"
  return 0
}

function start_pod_port_forward_with_retry() {
  local pod_name="$1"
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
    if kubectl -n confluent get pod "$pod_name" >/dev/null 2>&1
    then
      if [[ "$(kubectl -n confluent get pod "$pod_name" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" == "True" ]]
      then
        pf_pid=$(start_pod_port_forward "$pod_name" "$local_port" "$remote_port" "$log_file" "$description")
        if [[ -n "$pf_pid" ]]
        then
          echo "$pf_pid"
          return 0
        fi
      fi
    fi

    sleep "$wait_interval"
    waited=$(( waited + wait_interval ))
  done

  logwarn "⚠️ Timed out after ${max_wait_seconds}s starting port-forward for $description"
  return 1
}

if [[ -n "$ENABLE_CONTROL_CENTER" ]]
then
  log "Port-forward controlcenter, schema-registry, and connect"
  CONTROL_CENTER_PF_PID=$(start_port_forward_with_retry "controlcenter" "9021" "9021" "/tmp/control-center-port-forward.log" "Control Center" "120") || true
else
  log "Port-forward schema-registry and connect (controlcenter disabled)"
  CONTROL_CENTER_PF_PID=""
fi
SCHEMA_REGISTRY_PF_PID=$(start_port_forward_with_retry "schemaregistry" "8081" "8081" "/tmp/schema-registry-port-forward.log" "Schema Registry" "120") || true
CONNECT_PF_PID=$(start_port_forward_with_retry "connect" "8083" "8083" "/tmp/connect-port-forward.log" "Connect" "120") || true
if [[ -n "$ENABLE_CONNECT_NODES" ]]
then
  CONNECT2_PF_PID=$(start_port_forward_with_retry "connect" "8283" "8083" "/tmp/connect2-port-forward.log" "Connect (alt 8283)" "120") || true
  CONNECT3_PF_PID=$(start_port_forward_with_retry "connect" "8383" "8083" "/tmp/connect3-port-forward.log" "Connect (alt 8383)" "120") || true
fi

if [[ -n "$ENABLE_KSQLDB" ]]
then
  KSQLDB_PF_PID=$(start_port_forward_with_retry "ksqldb-server" "8088" "8088" "/tmp/ksqldb-port-forward.log" "ksqlDB" "120") || true
fi

if [[ -n "$ENABLE_RESTPROXY" ]]
then
  REST_PROXY_PF_PID=$(start_port_forward_with_retry "restproxy" "8082" "8082" "/tmp/restproxy-port-forward.log" "REST Proxy" "120") || true
fi

port_forward_logs="/tmp/schema-registry-port-forward.log, /tmp/connect-port-forward.log"
port_forward_missing=0

if [[ -n "$ENABLE_CONTROL_CENTER" ]]
then
  port_forward_logs="$port_forward_logs, /tmp/control-center-port-forward.log"
  if [[ -z "$CONTROL_CENTER_PF_PID" ]]
  then
    port_forward_missing=1
  fi
fi

if [[ -z "$SCHEMA_REGISTRY_PF_PID" ]] || [[ -z "$CONNECT_PF_PID" ]]
then
  port_forward_missing=1
fi

if [[ -n "$ENABLE_CONNECT_NODES" ]]
then
  port_forward_logs="$port_forward_logs, /tmp/connect2-port-forward.log, /tmp/connect3-port-forward.log"
  if [[ -z "$CONNECT2_PF_PID" ]] || [[ -z "$CONNECT3_PF_PID" ]]
  then
    port_forward_missing=1
  fi
fi

if [[ -n "$ENABLE_KSQLDB" ]]
then
  port_forward_logs="$port_forward_logs, /tmp/ksqldb-port-forward.log"
  if [[ -z "$KSQLDB_PF_PID" ]]
  then
    port_forward_missing=1
  fi
fi

if [[ -n "$ENABLE_RESTPROXY" ]]
then
  port_forward_logs="$port_forward_logs, /tmp/restproxy-port-forward.log"
  if [[ -z "$REST_PROXY_PF_PID" ]]
  then
    port_forward_missing=1
  fi
fi

if [[ "$port_forward_missing" -eq 1 ]]
then
  logwarn "⚠️ Some port-forwards may not be available; check logs in ${port_forward_logs}"
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
if [[ -n "$CONNECT2_PF_PID" ]]
then
  log "🔌 Connect REST API is reachable at http://127.0.0.1:8283"
fi
if [[ -n "$CONNECT3_PF_PID" ]]
then
  log "🔌 Connect REST API is reachable at http://127.0.0.1:8383"
fi
if [[ -n "$KSQLDB_PF_PID" ]]
then
  log "🚀 ksqlDB is reachable at http://127.0.0.1:8088"
fi
if [[ -n "$REST_PROXY_PF_PID" ]]
then
  log "📲 REST Proxy is reachable at http://127.0.0.1:8082"
fi

# Port-forward connect service ports declared in compose override (for listeners like syslog.port)
if [[ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]]
then
  CONNECT_PORTS_FILE=$(mktemp)
  if collect_connect_ports_from_compose "${DOCKER_COMPOSE_FILE_OVERRIDE}" "${CONNECT_PORTS_FILE}"
  then
    log "🔀 Port-forwarding connect ports from compose override"
    set +e
    while IFS= read -r raw_connect_port
    do
      parsed_connect_port=$(parse_compose_connect_port_mapping "$raw_connect_port")
      if [[ $? -ne 0 ]] || [[ -z "$parsed_connect_port" ]]
      then
        logwarn "⚠️ Could not parse connect port mapping '$raw_connect_port' from compose override"
        continue
      fi

      connect_local_port="${parsed_connect_port%%|*}"
      connect_target_and_proto="${parsed_connect_port#*|}"
      connect_target_port="${connect_target_and_proto%%|*}"
      connect_protocol="${connect_target_and_proto##*|}"

      if [[ "$connect_protocol" != "tcp" ]]
      then
        logwarn "⚠️ Skipping connect port mapping '$raw_connect_port' (protocol ${connect_protocol} is not supported by kubectl port-forward)"
        continue
      fi

      if [[ "$connect_target_port" == "8083" ]]
      then
        continue
      fi

      start_pod_port_forward_with_retry "connect-0" "$connect_local_port" "$connect_target_port" "/tmp/connect-${connect_local_port}-port-forward.log" "Connect listener ${connect_local_port}->${connect_target_port}" "120" > /dev/null || true
      log "🔌 Connect listener is reachable at tcp://127.0.0.1:${connect_local_port}"
    done < "$CONNECT_PORTS_FILE"
    set -e
  fi
  rm -f "$CONNECT_PORTS_FILE" >/dev/null 2>&1 || true
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