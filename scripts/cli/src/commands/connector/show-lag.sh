connector="${args[--connector]}"
verbose="${args[--verbose]}"
interval="${args[--interval]}"

connector_type=$(playground state get run.connector_type)

if [[ ! -n "$connector" ]]
then
    connector=$(playground get-connector-list)
    if [ "$connector" == "" ]
    then
        log "💤 No $connector_type connector is running !"
        exit 1
    fi
fi

if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
then
  get_ccloud_connect
  get_kafka_docker_playground_dir
  DELTA_CONFIGS_ENV=$KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/env.delta

  if [ -f $DELTA_CONFIGS_ENV ]
  then
      source $DELTA_CONFIGS_ENV
  else
      logerror "ERROR: $DELTA_CONFIGS_ENV has not been generated"
      exit 1
  fi
  if [ ! -f $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta ]
  then
      logerror "ERROR: $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta has not been generated"
      exit 1
  fi
else
  get_security_broker "--command-config"
fi

declare -A prev_lags
prev_lags=()

function show_output () {
  prev_topic=""
  while read line; do
    arr=($line)
    topic=${arr[1]}
    partition=${arr[2]}
    current_offset=${arr[3]}
    end_offset=${arr[4]}
    lag=${arr[5]}
    prev_lag=${prev_lags["${topic}_${partition}"]}
    compare_line=""
    compare_action=""

    if [ "$topic" != "$prev_topic" ] && [ "$prev_topic" != "" ]
    then
      echo "---"
    fi

    if [[ "$total_lag" =~ ^[0-9]+$ ]]
    then
      if [[ "$prev_lag" =~ ^[0-9]+$ ]] && [[ "$lag" =~ ^[0-9]+$ ]]
      then
        if [ $lag -lt $prev_lag ]
        then
          compare_line="🔻 $(($prev_lag - $lag))"
          compare_action="up"
        elif [ $lag -eq $prev_lag ]
        then
          compare_line="🔸"
          compare_action="same"
        else
          compare_line="🔺 $(($lag - $prev_lag))"
          compare_action="down"
        fi
      fi
    fi

    if [ $lag == 0 ]
    then
      compare_line="🏁"
    fi

    if [[ "$end_offset" =~ ^[0-9]+$ ]] && [[ "$end_offset" =~ ^[0-9]+$ ]] && [ $end_offset != 0 ] && [[ "$lag" =~ ^[0-9]+$ ]]
    then
      # calculate the percentage of lag
      percentage=$((100 * lag / end_offset))
      inverse_percentage=$((100 - percentage))

      # create the progress bar
      bar_length=20
      filled_length=$((percentage * bar_length / 100))
      empty_length=$((bar_length - filled_length))
      bar=$(printf "%${empty_length}s" | tr ' ' '🔹')
      bar+=$(printf "%${filled_length}s" | tr ' ' '💠')
    fi

    prev_lags["${topic}_${partition}"]=$lag
    if [ "$compare_line" != "" ]
    then
      case "${compare_action}" in
        up)
          printf "\033[32mtopic: %-10s partition: %-3s current-offset: %-10s end-offset: %-10s lag: %-10s [%s] %3d%% %s\033[0m\n" "$topic" "$partition" "$current_offset" "$end_offset" "$lag" "$bar" "$inverse_percentage" "$compare_line"
        ;;
        down)
          printf "\033[31mtopic: %-10s partition: %-3s current-offset: %-10s end-offset: %-10s lag: %-10s [%s] %3d%% %s\033[0m\n" "$topic" "$partition" "$current_offset" "$end_offset" "$lag" "$bar" "$inverse_percentage" "$compare_line"
        ;;
        *)
          printf "topic: %-10s partition: %-3s current-offset: %-10s end-offset: %-10s lag: %-10s [%s] %3d%% %s\n" "$topic" "$partition" "$current_offset" "$end_offset" "$lag" "$bar" "$inverse_percentage" "$compare_line"
        ;;
      esac
    else
      printf "topic: %-10s partition: %-3s current-offset: %-10s end-offset: %-10s lag: %-10s [%s] %3d%%\n" "$topic" "$partition" "$current_offset" "$end_offset" "$lag" "$bar" "$inverse_percentage"
    fi
    prev_topic="$topic"
  done < <(cat "$lag_output" | grep -v PARTITION | sed '/^$/d' | sort -k2n)
}

function log_down() {
  GREEN='\033[0;32m'
  NC='\033[0m' # No Color
  echo -e "$GREEN$(date +"%H:%M:%S") 🔻$@$NC"
}

function log_up() {
  RED='\033[0;31m'
  NC='\033[0m' # No Color
  echo -e "$RED$(date +"%H:%M:%S") 🔺$@$NC"
}

function log_same() {
  ORANGE='\033[0;33m'
  NC='\033[0m' # No Color
  echo -e "$ORANGE`date +"%H:%M:%S"` 🔸$@$NC"
}

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi
lag_output=$tmp_dir/lag_output

function handle_signal {
  echo "Stopping..."
  stop=1
}
# Set the signal handler
trap handle_signal SIGINT

items=($connector)
length=${#items[@]}
if ((length > 1))
then
    log "✨ --connector flag was not provided, applying command to all connectors"
fi
for connector in "${items[@]}"
do
  maybe_id=""
  if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
  then
      get_ccloud_connect
      handle_ccloud_connect_rest_api "curl -s --request GET \"https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector/status\" --header \"authorization: Basic $authorization\""
      connectorId=$(get_ccloud_connector_lcc $connector)
      maybe_id=" ($connectorId)"
  else
      get_connect_url_and_security
      handle_onprem_connect_rest_api "curl -s $security \"$connect_url/connectors/$connector/status\""
  fi

  type=$(echo "$curl_output" | jq -r '.type')
  if [ "$type" != "sink" ]
  then
    logwarn "⏭️ Skipping $type $connector_type connector ${connector}${maybe_id}, it must be a sink to show the lag"
    continue 
  fi

  playground connector status --connector $connector  > $tmp_dir/result.log  2>&1
  if [ $(grep -c "✅" $tmp_dir/result.log) -ne 1 ]
  then
      logerror "❌ $connector_type connector ${connector}${maybe_id} instance is not in ✅ RUNNING state"
      exit 1
  fi

  if [ $(grep -c "🟢" $tmp_dir/result.log) -lt 1 ]
  then
      logerror "❌ $connector_type connector ${connector}${maybe_id} does not have 🟢 task in RUNNING state"
      exit 1
  fi

  if [[ -n "$verbose" ]]
  then
      log "🐞 CLI command used"
      echo "kafka-consumer-groups --bootstrap-server broker:9092 --group connect-$connector --describe $security"
  fi

  SECONDS=0
  prev_lag=0
  stop=0

  get_environment_used
  while [ $stop != 1 ]
  do
    if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ] || [[ "$environment" == "ccloud" ]]
    then
      get_ccloud_connect
      get_connect_image

      if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ] 
      then
        consumer_group="connect-$connectorId"
      else
        consumer_group="connect-$connector"
      fi
      docker run --quiet --rm -v $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta:/tmp/configuration/ccloud.properties -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SASL_JAAS_CONFIG="$SASL_JAAS_CONFIG" ${CP_CONNECT_IMAGE}:${CONNECT_TAG} kafka-consumer-groups --bootstrap-server $BOOTSTRAP_SERVERS --command-config /tmp/configuration/ccloud.properties --group $consumer_group --describe | grep -v PARTITION | sed '/^$/d' &> $lag_output
    else
      docker exec $container kafka-consumer-groups --bootstrap-server broker:9092 --group connect-$connector --describe $security | grep -v PARTITION | sed '/^$/d' &> $lag_output
    fi

    if grep -q "Warning" $lag_output
    then
      logwarn "🐢 consumer group for $connector_type connector ${connector}${maybe_id} is rebalancing"
      cat $lag_output
      sleep $interval
      continue
    fi

    set +e
    lag_not_set=$(cat "$lag_output" | awk -F" " '{ print $6 }' | grep "-")

    if [ ! -z "$lag_not_set" ]
    then
      logwarn "🐢 consumer lag for $connector_type connector ${connector}${maybe_id} is not available"
      show_output
      sleep $interval
    else
      total_lag=$(cat "$lag_output" | grep -v "PARTITION" | awk -F" " '{sum+=$6;} END{print sum;}')

      if [[ "$total_lag" =~ ^[0-9]+$ ]]
      then
        if [ $total_lag -ne 0 ]
        then
          compare=""
          compare_action=""
          if [[ "$prev_lag" =~ ^[0-9]+$ ]]
          then
            if [ $prev_lag != 0 ]
            then
              if [ $total_lag -lt $prev_lag ]
              then
                compare="🔻 $(($prev_lag - $total_lag))"
                compare_action="down"
              elif [ $total_lag -eq $prev_lag ]
              then
                compare="🔸"
                compare_action="same"
              else
                compare="🔺 $(($total_lag - $prev_lag))"
                compare_action="up"
              fi
            fi
          fi
          if [ "$compare" != "" ]
          then
            case "${compare_action}" in
              up)
                log_up "🔥 total consumer lag for $connector_type connector ${connector}${maybe_id} has increased to $total_lag $compare (press ctrl-c to stop)"
              ;;
              down)
                log_down "🚀 consumer lag for $connector_type connector ${connector}${maybe_id} has decreased to $total_lag $compare (press ctrl-c to stop)"
              ;;
              *)
                log_same "🐌 consumer lag for $connector_type connector ${connector}${maybe_id} is still $total_lag $compare (press ctrl-c to stop)"
              ;;
            esac
          else
            log "🐢 consumer lag for $connector_type connector ${connector}${maybe_id} is $total_lag"
          fi
          show_output
          prev_lag=$total_lag
          sleep $interval
        else
          ELAPSED="took: $((($SECONDS / 60) % 60))min $(($SECONDS % 60))sec"
          log "🏁 consumer lag for $connector_type connector ${connector}${maybe_id} is 0 ! $ELAPSED"
          stop=1
          show_output
          break
        fi
      fi
    fi
  done
done