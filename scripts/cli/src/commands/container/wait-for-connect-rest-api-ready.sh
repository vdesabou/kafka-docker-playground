max_wait="${args[--max-wait]}"

# every curl has --max-time, and the budget is elapsed time ($SECONDS), not loop iterations: a connection that is
# accepted but never answered (podman port forwarder) used to block one curl, and the whole wait, until the test timeout
curl_max_time=10

get_environment_used

if [[ "$environment" == cfk* ]]
then
  connect_pod=$(resolve_container_name_for_environment "connect")
  start_wait=$SECONDS
  while ! kubectl -n confluent exec "$connect_pod" -- curl -s --max-time $curl_max_time http://localhost:8083 > /dev/null 2>&1
  do
    if [[ $(( SECONDS - start_wait )) -gt "$max_wait" ]]
    then
      logerror "❌ the connect REST API is still not ready after $max_wait seconds, see output"
      kubectl -n confluent exec "$connect_pod" -- curl -sS --max-time $curl_max_time -w '\n(HTTP %{http_code})\n' http://localhost:8083 || true
      return 1
    fi
    sleep 1
  done
else
  get_connect_url_and_security
  start_wait=$SECONDS
  # poll /connectors rather than / : the root endpoint answers before the herder resources are registered
  while ! handle_onprem_connect_rest_api "curl $security -s --max-time $curl_max_time \"$connect_url/connectors\"" > /dev/null 2>&1 || ! echo "$curl_output" | jq -e 'type == "array"' > /dev/null 2>&1;
  do
    if [[ $(( SECONDS - start_wait )) -gt "$max_wait" ]]
    then
      logerror "❌ the connect REST API is still not ready after $max_wait seconds, see output"
      # -S -w: show the curl error (for example "Operation timed out") or the HTTP status, not only the body
      eval "curl $security -sS --max-time $curl_max_time -w '\n(HTTP %{http_code})\n' \"$connect_url/connectors\"" 2>&1 || true
      return 1
    fi
    sleep 1
  done
fi
