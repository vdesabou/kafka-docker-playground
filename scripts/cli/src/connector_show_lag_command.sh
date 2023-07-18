connector="${args[--connector]}"
wait_for_zero_lag="${args[--wait-for-zero-lag]}"

ret=$(get_connect_url_and_security)

connect_url=$(echo "$ret" | cut -d "@" -f 1)
security=$(echo "$ret" | cut -d "@" -f 2)

if [[ ! -n "$connector" ]]
then
    log "✨ --connector flag was not provided, applying command to all connectors"
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

  if [[ -n "$wait_for_zero_lag" ]]
  then
    CHECK_INTERVAL=5
    SECONDS=0
    # Loop until all consumer lags become 0
    while true
    do
      # Get the consumer group lag details
      lag_output=$(docker exec $container kafka-consumer-groups --bootstrap-server broker:9092 --group connect-$connector --describe $securityP)

      # Check if any non-zero lag value is found
      if echo "$lag_output" | grep -q -v "LAG\s\+0"
      then
          log "🐢 consumer lag is not 0..."
          echo "$lag_output" | awk -F" " '{ print $3,$4,$5,$6 }'
          sleep $CHECK_INTERVAL
      else
          ELAPSED="took: $((($SECONDS / 60) % 60))min $(($SECONDS % 60))sec"
          log "🏁 all consumer lags are 0 ! $ELAPSED"
          continue
      fi
    done
  else
    log "🐢 Show lag for sink connector $connector"
    docker exec $container kafka-consumer-groups --bootstrap-server broker:9092 --group connect-$connector --describe $security
  fi

done