connector="${args[--connector]}"
wait_for_zero_lag="${args[--wait-for-zero-lag]}"
verbose="${args[--verbose]}"

get_connect_url_and_security

if [[ ! -n "$connector" ]]
then
    connector=$(playground get-connector-list)
    if [ "$connector" == "" ]
    then
        logerror "💤 No connector is running !"
        exit 1
    fi
fi

get_security_broker "--command-config"

tmp_dir=$(mktemp -d -t ci-XXXXXXXXXX)
trap 'rm -rf $tmp_dir' EXIT
lag_output=$tmp_dir/lag_output
items=($connector)
length=${#items[@]}
if ((length > 1))
then
    log "✨ --connector flag was not provided, applying command to all connectors"
fi
for connector in ${items[@]}
do
  type=$(curl -s $security "$connect_url/connectors/$connector/status" | jq -r '.type')
  if [ "$type" != "sink" ]
  then
    logwarn "⏭️ Skipping $type connector $connector, it must be a sink to show the lag"
    continue 
  fi

  if [[ -n "$verbose" ]]
  then
      log "🐞 CLI command used"
      echo "kafka-consumer-groups --bootstrap-server broker:9092 --group connect-$connector --describe $security"
  fi

  CHECK_INTERVAL=5
  SECONDS=0
  while true
  do
    docker exec $container kafka-consumer-groups --bootstrap-server broker:9092 --group connect-$connector --describe $security | grep -v PARTITION | sed '/^$/d' > $lag_output
    set +e
    lag_not_set=$(cat "$lag_output" | awk -F" " '{ print $6 }' | grep "-")

    if [ ! -z "$lag_not_set" ]
    then
      logwarn "🐢 consumer lag for connector $connector is not set"
      cat "$lag_output" | awk -F" " '{ print "partition: "$3," current-offset: "$4," log-end-offset: "$5," lag: "$6 }' | sort -k2n | column -t
      sleep $CHECK_INTERVAL
    else
      total_lag=$(cat "$lag_output" | grep -v "PARTITION" | awk -F" " '{sum+=$6;} END{print sum;}')
      if [ $total_lag -ne 0 ]
      then
        log "🐢 consumer lag for connector $connector is $total_lag"
        cat "$lag_output" | awk -F" " '{ print "partition: "$3," current-offset: "$4," log-end-offset: "$5," lag: "$6 }' | sort -k2n | column -t
        sleep $CHECK_INTERVAL
      else
        if [[ ! -n "$wait_for_zero_lag" ]]
        then
          log "🏁 consumer lag for connector $connector is 0 !"
        else
          ELAPSED="took: $((($SECONDS / 60) % 60))min $(($SECONDS % 60))sec"
          log "🏁 consumer lag for connector $connector is 0 ! $ELAPSED"
        fi
        cat "$lag_output" | awk -F" " '{ print "partition: "$3," current-offset: "$4," log-end-offset: "$5," lag: "$6 }' | sort -k2n | column -t
        break
      fi
    fi

    if [[ ! -n "$wait_for_zero_lag" ]]
    then
      break
    fi
  done
done