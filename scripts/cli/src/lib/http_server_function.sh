# helpers of 'playground tools http-server': the http test server of the http examples (connect/connect-http-sink/httpserver,
# container httpserver, port 9006). The calls run curl inside its container (docker exec, kubectl exec on cfk), so they
# do not depend on the port published on the host

# sets http_server_container and http_server_transport, exits when the container is not running
function http_server_resolve () {
  local wanted="${1:-httpserver}"
  http_server_transport="docker"
  get_environment_used
  if [[ "$environment" == cfk* ]]
  then
    http_server_transport="kubectl"
    http_server_container=$(resolve_container_name_for_environment "$wanted")
    if ! kubectl -n confluent get pod "$http_server_container" -o jsonpath='{.status.phase}' 2>/dev/null | grep -q Running
    then
      logerror "❌ pod $http_server_container is not running: start an http example (connect/connect-http-sink, connect-http-v2-sink...)"
      exit 1
    fi
    return 0
  fi
  http_server_container="$wanted"
  if [[ -z "$(docker ps --filter "name=^${http_server_container}$" --filter "status=running" --format "{{.Names}}")" ]]
  then
    logerror "❌ container $http_server_container is not running: start an http example (connect/connect-http-sink, connect-http-v2-sink...)"
    exit 1
  fi
}

# http_server_call <method> <path> [json body]: prints the response body, returns 1 when the call fails
function http_server_call () {
  local method="$1" path="$2" body="${3:-}"
  local curl_cmd=(curl -s -S --max-time 30 -X "$method" "http://localhost:9006$path")
  if [[ -n "$body" ]]
  then
    curl_cmd+=(-H "Content-Type: application/json" --data-binary @-)
  fi
  if [[ "$http_server_transport" == "kubectl" ]]
  then
    printf '%s' "$body" | kubectl -n confluent exec -i "$http_server_container" -- "${curl_cmd[@]}"
  else
    printf '%s' "$body" | docker exec -i "$http_server_container" "${curl_cmd[@]}"
  fi
}

# the settings and requests (GET /received-requests), exits with a hint when the image is older than the endpoint
function http_server_received_requests () {
  local response
  response=$(http_server_call GET /received-requests) || {
    logerror "❌ could not reach the http server in $http_server_container" >&2
    exit 1
  }
  if ! jq -e '.settings and .requests' > /dev/null 2>&1 <<< "$response"
  then
    http_server_old_image_error
  fi
  printf '%s\n' "$response"
}

# on stderr: also shown when called in $(...)
function http_server_old_image_error () {
  logerror "❌ the $http_server_container container runs an image built before 'playground tools http-server' (no /reset nor /received-requests endpoint)" >&2
  logerror "   🎓 rebuild it with the example: playground re-run (its compose service has pull_policy: build)" >&2
  exit 1
}
