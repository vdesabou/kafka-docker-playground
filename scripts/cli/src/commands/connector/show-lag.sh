connector="${args[--connector]}"
verbose="${args[--verbose]}"
interval=$(duration_to_seconds "${args[--interval]}")
max_wait=$(duration_to_seconds "${args[--max-wait]}")
fail_on_timeout="${args[--fail-on-timeout]}"
once="${args[--once]}"
json="${args[--json]}"
# --json: one shot, the JSON array goes to stdout (fd 3), everything else to stderr
if [[ -n "$json" ]]
then
  once=1
  exec 3>&1 1>&2
fi
lag_entries=()

connector_type=$(playground state get run.connector_type)
get_environment_used

if [[ ! -n "$connector" ]]
then
    connector=$(playground get-connector-list)
    if [ "$connector" == "" ]
    then
        log "💤 No $connector_type connector is running !"
        exit 1
    fi
fi

# decided once: get_ccloud_connect overwrites $environment with the env-xxxx id, so testing
# "$environment" == "ccloud" again later would take the self managed branch on the 2nd poll
use_ccloud_tools=0
if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ] || [ "$environment" == "ccloud" ]
then
  use_ccloud_tools=1
fi

if [ $use_ccloud_tools == 1 ]
then
  get_ccloud_connect
  get_kafka_docker_playground_dir
  DELTA_CONFIGS_ENV=$KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/env.delta

  if [ -f $DELTA_CONFIGS_ENV ]
  then
      source $DELTA_CONFIGS_ENV
  else
      logerror "❌ $DELTA_CONFIGS_ENV has not been generated"
      exit 1
  fi
  if [ ! -f $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta ]
  then
      logerror "❌ $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta has not been generated"
      exit 1
  fi
else
  get_security_broker "--command-config"
fi
# get_connect_url_and_security (connect REST API) overwrites $security: kafka-consumer-groups uses the broker one
broker_security="$security"

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
    # lag is "-" when the consumer group has not committed any offset yet for this partition
    bar=""
    inverse_percentage=0

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

    if [[ "$end_offset" =~ ^[0-9]+$ ]] && [ $end_offset != 0 ] && [[ "$lag" =~ ^[0-9]+$ ]]
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
  done < <(cat "$lag_output" | grep -v PARTITION | sed '/^$/d' | sort -k2,2 -k3,3n)
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
  echo -e "$ORANGE$(date +"%H:%M:%S") 🔸$@$NC"
}

timed_out=0
# sleep --interval, then return 1 once --max-wait is exceeded
function wait_next_poll () {
  sleep $interval
  cur_wait=$(( cur_wait+interval ))
  if [ "$max_wait" != "0" ] && [[ "$cur_wait" -gt "$max_wait" ]]
  then
    logwarn "🐢 the consumer lag for $connector_type connector ${connector}${maybe_id} is still not 0 after $max_wait seconds."
    timed_out=1
    return 1
  fi
  return 0
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

    status_wait_timeout=60
    status_wait_interval=2
    status_wait_elapsed=0
    connector_ready=0

    # --once: a snapshot of the lag, also when the tasks are not RUNNING (committed offsets)
    if [[ -n "$once" ]]
    then
      connector_ready=1
    fi
    while [ "$connector_ready" -ne 1 ] && [ "$status_wait_elapsed" -le "$status_wait_timeout" ]
    do
      PG_SKIP_ERROR_RECOMMENDATIONS=1 playground connector status --connector $connector > $tmp_dir/result.log 2>&1

      if [ "$(grep -c "✅" $tmp_dir/result.log)" -eq 1 ] && [ "$(grep -c "🟢" $tmp_dir/result.log)" -ge 1 ]
      then
        connector_ready=1
        break
      fi

      sleep "$status_wait_interval"
      status_wait_elapsed=$((status_wait_elapsed + status_wait_interval))
    done

    if [ "$connector_ready" -ne 1 ]
    then
      if [ "$(grep -c "✅" $tmp_dir/result.log)" -ne 1 ]
      then
        logerror "❌ $connector_type connector ${connector}${maybe_id} instance is not in ✅ RUNNING state after ${status_wait_timeout}s"
      else
        logerror "❌ $connector_type connector ${connector}${maybe_id} does not have 🟢 task in RUNNING state after ${status_wait_timeout}s"
      fi
      exit 1
    fi

  # connect-<connector>, connect-<lcc id>, or the group set with consumer.override.group.id
  get_connector_consumer_group "$connector"
  if [ -n "$consumer_group_override" ]
  then
    log "👥 $connector_type connector ${connector} uses consumer group $consumer_group (consumer.override.group.id)"
  fi

  if [[ -n "$verbose" ]]
  then
      log "🐞 CLI command used"
      echo "kafka-consumer-groups --bootstrap-server $bootstrap_server --group $consumer_group --describe $broker_security"
  fi

  SECONDS=0
  prev_lag=0
  stop=0
  cur_wait=0

  while [ $stop != 1 ]
  do
    # stderr is kept: an error ("does not exist", timeout) must not be read as an empty or 0 lag
    if [ $use_ccloud_tools == 1 ]
    then
      get_connect_image
      docker run --quiet --rm -v $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta:/tmp/configuration/ccloud.properties -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SASL_JAAS_CONFIG="$SASL_JAAS_CONFIG" ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} kafka-consumer-groups --bootstrap-server $BOOTSTRAP_SERVERS --command-config /tmp/configuration/ccloud.properties --group $consumer_group --describe 2>&1 | grep -v PARTITION | sed '/^$/d' &> $lag_output
    else
      playground --output-level ERROR container exec --container "$container" --command "kafka-consumer-groups --bootstrap-server $bootstrap_server --group $consumer_group --describe $broker_security" 2>&1 | grep -v PARTITION | sed '/^$/d' &> $lag_output
    fi
    # keep the partition rows (3rd field is the partition number) and the errors: informational stderr lines such as
    # "Consumer group 'x' has no active members." or SLF4J noise must neither be summed as a 0 lag nor shown as a row
    awk 'tolower($0) ~ /warning|does not exist|^error|exception/ || $3 ~ /^[0-9]+$/' "$lag_output" > "$lag_output.rows"
    mv "$lag_output.rows" "$lag_output"

    if [[ -n "$once" ]]
    then
      lag_error=""
      partitions_json='[]'
      if grep -qiE "Warning|does not exist|^Error|Exception" $lag_output
      then
        lag_error=$(grep -iE "Warning|does not exist|Error|Exception" $lag_output | head -3 | tr '\n' ' ')
      else
        partitions_json=$(grep -v PARTITION "$lag_output" | sed '/^$/d' | jq -R -s '
          split("\n") | map(select(length > 0) | split(" ") | map(select(length > 0)))
          | map(select(length >= 6 and (.[2] | test("^[0-9]+$")))) | map({topic: .[1], partition: (.[2] | tonumber), current_offset: (.[3] | tonumber? // null), end_offset: (.[4] | tonumber? // null), lag: (.[5] | tonumber? // null)})
          | sort_by(.topic, .partition)')
      fi
      lag_entries+=("$(echo "$partitions_json" | jq -c --arg connector "$connector" --arg type "$connector_type" --arg group "$consumer_group" --arg error "$lag_error" '
        {connector: $connector, type: $type, consumer_group: $group,
         total_lag: (if length > 0 and all(.[]; .lag != null) then (map(.lag) | add) else null end),
         partitions: .} + (if $error != "" then {error: $error} else {} end)')")
      if [[ -z "$json" ]]
      then
        if [ -n "$lag_error" ]
        then
          logwarn "🐢 could not read the lag of consumer group $consumer_group for $connector_type connector ${connector}${maybe_id}: $lag_error"
        else
          total_lag=$(echo "${lag_entries[-1]}" | jq -r '.total_lag // "not available (no offset committed yet)"')
          log "🐢 consumer lag for $connector_type connector ${connector}${maybe_id} is $total_lag"
          show_output
        fi
      fi
      break
    fi

    if grep -q "Warning" $lag_output
    then
      logwarn "🐢 consumer group for $connector_type connector ${connector}${maybe_id} is rebalancing"
      cat $lag_output
      wait_next_poll || break
      continue
    fi

    if grep -qiE "does not exist|^Error|Exception" $lag_output
    then
      logwarn "🐢 could not read the lag of consumer group $consumer_group for $connector_type connector ${connector}${maybe_id}:"
      grep -iE "does not exist|Error|Exception" $lag_output | head -5
      wait_next_poll || break
      continue
    fi

    set +e
    lag_not_set=$(cat "$lag_output" | awk -F" " '{ print $6 }' | grep "-")

    if [ ! -z "$lag_not_set" ]
    then
      logwarn "🐢 consumer lag for $connector_type connector ${connector}${maybe_id} is not available (no offset committed yet), check the connector status if this persists"
      show_output
      wait_next_poll || break
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
          wait_next_poll || break
        else
          ELAPSED="took: $((($SECONDS / 60) % 60))min $(($SECONDS % 60))sec"
          log "🏁 consumer lag for $connector_type connector ${connector}${maybe_id} is 0 ! $ELAPSED"
          stop=1
          show_output
          break
        fi
      else
        # empty output (the command failed or the group has no member yet): never loop without sleeping
        logwarn "🐢 consumer lag for $connector_type connector ${connector}${maybe_id} could not be read (empty output)"
        wait_next_poll || break
      fi
    fi
  done
done

if [ $timed_out == 1 ] && [[ -n "$fail_on_timeout" ]]
then
  logerror "❌ the consumer lag did not reach 0 within --max-wait $max_wait seconds"
  exit 1
fi

if [[ -n "$json" ]]
then
  if [ ${#lag_entries[@]} -eq 0 ]
  then
    echo "[]" >&3
  else
    printf '%s\n' "${lag_entries[@]}" | jq -s '.' >&3
  fi
fi
