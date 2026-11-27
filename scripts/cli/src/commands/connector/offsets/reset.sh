connector="${args[--connector]}"
verbose="${args[--verbose]}"

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

if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ] || [ "$environment" == "ccloud" ]
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

if [ "$connector_type" != "$CONNECTOR_TYPE_FULLY_MANAGED" ] && [ "$connector_type" != "$CONNECTOR_TYPE_CUSTOM" ]
then
    # one tag per connect worker (connect, connect2, connect3...): get_running_cp_tag keeps the first one
    tag=$(get_running_cp_tag)
    if [ "$tag" == "" ]
    then
        logerror "❌ could not find current CP version from docker ps"
        exit 1
    fi
fi

# returns 1 when the offsets could not be reset: called as 'handle_first_class_offset || ...', so set -e does
# not apply inside it and every failure must be checked explicitly
function handle_first_class_offset() {
    if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
    then

        echo '{"type":"DELETE"}' > $tmp_dir/delete.json
        get_ccloud_connect
        handle_ccloud_connect_rest_api "curl -s --request POST -H \"Content-Type: application/json\" --data @$tmp_dir/delete.json \"https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector/offsets/request\" --header \"authorization: Basic $authorization\"" || return 1
    else
        if ! version_gt $tag "7.5.99"; then
            logerror "❌ command is available since CP 7.6 only"
            return 1
        fi
        get_connect_url_and_security
        # a connector that was already STOPPED stays STOPPED
        initial_state=""
        if handle_onprem_connect_rest_api "curl $security -s \"$connect_url/connectors/$connector/status\"" > /dev/null 2>&1
        then
            initial_state=$(echo "$curl_output" | jq -r '.connector.state // empty' 2>/dev/null)
        fi
        if [ "$initial_state" != "STOPPED" ]
        then
            playground connector stop --connector $connector || return 1
        fi

        # always resume the connector, even when the DELETE is refused: otherwise it stays STOPPED
        get_connect_url_and_security
        delete_ret=0
        handle_onprem_connect_rest_api "curl $security -s -X DELETE \"$connect_url/connectors/$connector/offsets\"" || delete_ret=1
        if [ $delete_ret -eq 0 ]
        then
            echo "$curl_output" | jq .
        fi

        if [ "$initial_state" == "STOPPED" ]
        then
            log "🛑 connector $connector was STOPPED before the reset: left STOPPED (playground connector resume --connector $connector to start it)"
            if [ $delete_ret -ne 0 ]
            then
                logerror "❌ offsets of connector $connector were not reset"
                return 1
            fi
            return 0
        fi
        playground connector resume --connector $connector || return 1
        if [ $delete_ret -ne 0 ]
        then
            logerror "❌ offsets of connector $connector were not reset (the connector has been resumed)"
            return 1
        fi
    fi
}

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

failed=0
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
    log "🆕 Resetting offsets for $connector_type connector $connector"
    type=$(echo "$curl_output" | jq -r '.type')
    # a reset through the offsets API deletes the committed offsets of a sink: it then starts from its
    # auto.offset.reset, the END of its topics with consumer.override.auto.offset.reset=latest, so nothing is consumed
    # again (the kafka-consumer-groups --to-earliest of CP < 7.6 sets the offsets explicitly and is not concerned)
    sink_auto_offset_reset=""
    if [ "$type" == "sink" ]
    then
        if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
        then
            handle_ccloud_connect_rest_api "curl -s --request GET \"https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector/config\" --header \"authorization: Basic $authorization\"" > /dev/null 2>&1 || true
        else
            handle_onprem_connect_rest_api "curl -s $security \"$connect_url/connectors/$connector/config\"" > /dev/null 2>&1 || true
        fi
        sink_auto_offset_reset=$(echo "$curl_output" | jq -r '."consumer.override.auto.offset.reset" // empty' 2>/dev/null | tr '[:upper:]' '[:lower:]')
    fi
    if [ "$sink_auto_offset_reset" == "latest" ] && { [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ] || version_gt $tag "7.5.99"; }
    then
        logwarn "⚠️ $connector has consumer.override.auto.offset.reset=latest: without committed offsets it starts from the END of its topics, so the reset re-reads nothing. Remove the key first (Connect sinks default to earliest), or move it back to a given offset with playground connector offsets alter --connector $connector"
    fi
    if [ "$type" == "source" ]
    then
        ##
        # SOURCE CONNECTOR
        ##
        handle_first_class_offset || { failed=1; continue; }
        if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
        then
            # Confluent Cloud applies the request asynchronously
            sleep 5
            playground connector offsets get-offsets-request-status --connector $connector
            sleep 20
        fi
        playground connector offsets get --connector $connector
    else
        if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
        then
            handle_first_class_offset || { failed=1; continue; }
            sleep 5
            playground connector offsets get-offsets-request-status --connector $connector
            sleep 20
            playground connector offsets get --connector $connector
            continue
        fi

        if version_gt $tag "7.5.99"
        then
            handle_first_class_offset || { failed=1; continue; }
            playground connector offsets get --connector $connector
        else
            # connect-<connector>, or the group set with consumer.override.group.id (read before the connector is deleted)
            get_connector_consumer_group "$connector"
            playground --output-level ERROR container exec --container "$container" --command "kafka-consumer-groups --bootstrap-server $bootstrap_server --group $consumer_group --describe $broker_security" | grep -v PARTITION

            if version_gt $tag "7.4.99"
            then
                playground connector stop --connector $connector
            else
                playground --output-level ERROR connector show-config --connector $connector > "$tmp_dir/create-$connector-config.sh"
                playground connector delete --connector $connector
            fi

            playground --output-level ERROR container exec --container "$container" --command "kafka-consumer-groups --bootstrap-server $bootstrap_server --group $consumer_group $broker_security --to-earliest --reset-offsets --all-topics --execute"

            if version_gt $tag "7.4.99"
            then
                playground connector resume --connector $connector
            else
                bash "$tmp_dir/create-$connector-config.sh"
            fi
            playground connector offsets get --connector $connector
        fi
    fi
done

if [ $failed -ne 0 ]
then
    exit 1
fi
