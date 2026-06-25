max_wait="${args[--max-wait]}"

get_environment_used

if [[ "$environment" == "cfk" ]]
then
  connect_pod=$(resolve_container_name_for_environment "connect")
  cur_wait=0
  while ! kubectl -n confluent exec "$connect_pod" -- curl -s http://localhost:8083 > /dev/null 2>&1
  do
    sleep 1
    cur_wait=$(( cur_wait+1 ))
    if [[ "$cur_wait" -gt "$max_wait" ]]
    then
      logerror "❌ the connect REST API is still not ready after $max_wait seconds, see output"
      kubectl -n confluent exec "$connect_pod" -- curl -s http://localhost:8083
      return 1
    fi
  done
else
  get_connect_url_and_security
  cur_wait=0
  while ! handle_onprem_connect_rest_api "curl $security -s \"$connect_url\"" > /dev/null;
  do
    sleep 1
    cur_wait=$(( cur_wait+1 ))
    if [[ "$cur_wait" -gt "$max_wait" ]]
    then
      logerror "❌ the connect REST API is still not ready after $max_wait seconds, see output"
      handle_onprem_connect_rest_api "curl $security -s \"$connect_url\""
      return 1
    fi
  done
fi