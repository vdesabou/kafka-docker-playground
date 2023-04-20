connector="${args[--connector]}"

ret=$(get_connect_url_and_security)

connect_url=$(echo "$ret" | cut -d "@" -f 1)
security=$(echo "$ret" | cut -d "@" -f 2)

if [[ ! -n "$connector" ]]
then
    logwarn "--connector flag was not provided, applying command to all connectors"
    connector=$(playground get-connector-list)
    if [ "$connector" == "" ]
    then
        logerror "💤 No connector is running !"
        exit 1
    fi
fi

ret=$(get_security_broker "--command-config")

container=$(echo "$ret" | cut -d "@" -f 1)
security=$(echo "$ret" | cut -d "@" -f 2)

items=($connector)
for connector in ${items[@]}
do
  type=$(curl -s $security "$connect_url/connectors/$connector/status" | jq -r '.type')
  if [ "$type" != "sink" ]
  then
    logwarn "⏭️ Skipping $type connector $connector, it must be a sink to show the lag"
    continue 
  fi

  log "🐢 Show lag for sink connector $connector"
  docker exec $container kafka-consumer-groups --bootstrap-server broker:9092 --group connect-$connector --describe $security
done