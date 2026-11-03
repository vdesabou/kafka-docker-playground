connector="${args[--connector]}"
verbose="${args[--verbose]}"
json="${args[--json]}"
# --json: one JSON array with the offsets of each connector is the only thing on stdout (fd 3), everything else (log
# lines, --verbose commands, nested commands) goes to stderr
if [[ -n "$json" ]]
then
    exec 3>&1 1>&2
fi
offsets_entries=()

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

# returns 1 when the offsets could not be read: called as 'handle_first_class_offset || ...', so set -e does
# not apply inside it and every failure must be checked explicitly
function handle_first_class_offset() {
    if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
    then
        get_ccloud_connect
        handle_ccloud_connect_rest_api "curl -s --request GET \"https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector/offsets\" --header \"authorization: Basic $authorization\"" || return 1
    else
        if ! version_gt $tag "7.4.99"
        then
            logerror "❌ command is available since CP 7.5 only"
            return 1
        fi

        get_connect_url_and_security
        handle_onprem_connect_rest_api "curl $security -s -X GET \"$connect_url/connectors/$connector/offsets\"" || return 1
    fi

    if [[ -n "$json" ]]
    then
        offsets_entries+=("$(echo "$curl_output" | jq -c --arg c "$connector" --arg t "$type" '{connector: $c, type: $t, offsets: (.offsets // .)}')")
    else
        echo "$curl_output" | jq .
    fi
}
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
    type=$(echo "$curl_output" | jq -r '.type')
    log "🏹 Getting offsets for $connector_type $type connector $connector${maybe_id}"
    if [ "$type" == "source" ]
    then
        ##
        # SOURCE CONNECTOR
        ##
        handle_first_class_offset || { failed=1; continue; }
    else
        ##
        # SINK CONNECTOR
        ##
        get_environment_used
        if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ] || [[ "$environment" == "ccloud" ]]
        then
            handle_first_class_offset || { failed=1; continue; }
        else
            # the offsets API (KIP-875) reads the offsets of a sink since CP 7.5, like for a source
            if version_gt $tag "7.4.99"
            then
                handle_first_class_offset || { failed=1; continue; }
            else
                # connect-<connector>, or the group set with consumer.override.group.id
                get_connector_consumer_group "$connector"
                if [[ -n "$verbose" ]]
                then
                    log "🐞 CLI command used"
                    echo "kafka-consumer-groups --bootstrap-server $bootstrap_server --group $consumer_group --describe $broker_security"
                fi
                consumer_groups_output=$(playground --output-level ERROR container exec --container "$container" --command "kafka-consumer-groups --bootstrap-server $bootstrap_server --group $consumer_group --describe $broker_security")
                if [[ -n "$json" ]]
                then
                    offsets_entries+=("$(jq -cn --arg c "$connector" --arg t "$type" --arg g "$consumer_group" --arg out "$consumer_groups_output" '{connector: $c, type: $t, consumer_group: $g, kafka_consumer_groups_describe: $out}')")
                else
                    echo "$consumer_groups_output"
                fi
            fi
        fi
    fi
done

if [[ -n "$json" ]]
then
    if [ ${#offsets_entries[@]} -eq 0 ]
    then
        echo "[]" >&3
    else
        printf '%s\n' "${offsets_entries[@]}" | jq -s '.' >&3
    fi
fi
if [ $failed -ne 0 ]
then
    exit 1
fi
