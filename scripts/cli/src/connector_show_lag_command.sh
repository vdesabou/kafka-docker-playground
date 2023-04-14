connector="${args[--connector]}"

ret=$(get_connect_url_and_security)

connect_url=$(echo "$ret" | cut -d "@" -f 1)
security=$(echo "$ret" | cut -d "@" -f 2)

type=$(curl $security -s $connect_url/connectors\?expand\=status\&expand\=info | jq -r '. | to_entries[] | [ .value.info.type]|join(":|:")')
if [ "$type" != "sink" ]
then
  logerror "Connector $connector is a $type connector, it must be a sink to show the lag !"
  exit 1 
fi

ret=$(get_security_broker "--command-config")

container=$(echo "$ret" | cut -d "@" -f 1)
security=$(echo "$ret" | cut -d "@" -f 2)

log "Show lag for sink connector $connector"
docker exec $container kafka-consumer-groups --bootstrap-server broker:9092 --group connect-$connector --describe $security