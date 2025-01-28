max_wait="${args[--max-wait]}"

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