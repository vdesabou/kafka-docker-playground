ret=$(get_connect_url_and_security)

connect_url=$(echo "$ret" | cut -d "@" -f 1)
security=$(echo "$ret" | cut -d "@" -f 2)

json="${args[--json]}"

if [[ -n "$json" ]]
then
  curl $security -s "$connect_url/connectors?expand=status&expand=info" | jq .
else
  curl $security -s "$connect_url/connectors?expand=info&expand=status" | jq '. | to_entries[] | [ .value.info.type, .key, .value.status.connector.state,.value.status.tasks[].state,.value.info.config."connector.class"]|join(":|:")' | column -s : -t| sed 's/\"//g'| sort
fi