verbose="${args[--verbose]}"
connector="${args[--connector]}"
keep_related_topics="${args[--keep-related-topics]}"

connector_type=$(playground state get run.connector_type)
environment=$(playground state get run.environment)

if [[ ! -n "$connector" ]]
then
    connector=$(playground get-connector-list)
    if [ "$connector" == "" ]
    then
        log "💤 No $connector_type connector is running !"
        exit 1
    fi
fi

items=($connector)
length=${#items[@]}
if ((length > 1))
then
    log "✨ --connector flag was not provided, applying command to all connectors"
    check_if_continue
fi
for connector in "${items[@]}"
do
    log "❌ Deleting $connector_type connector $connector"
    if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
    then
        get_ccloud_connect
        related_topics=""
        if [[ -z "$keep_related_topics" ]]
        then
            # resolve dlq/success/error topics while the connector still exists
            if handle_ccloud_connect_rest_api "curl -s --request GET \"https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors?expand=id\" --header \"authorization: Basic $authorization\"" > /dev/null 2>&1
            then
                connector_id=$(echo "$curl_output" | jq -r --arg name "$connector" '.[$name].id.id // empty' 2>/dev/null)
                connector_config="{}"
                if handle_ccloud_connect_rest_api "curl -s --request GET \"https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector/config\" --header \"authorization: Basic $authorization\"" > /dev/null 2>&1
                then
                    connector_config="$curl_output"
                fi
                related_topics=$(get_ccloud_connector_related_topics "$connector_id" "$connector_config")
            fi
        fi
        handle_ccloud_connect_rest_api "curl -s --request DELETE \"https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector\" --header \"authorization: Basic $authorization\""
        if [ -n "$related_topics" ]
        then
            existing_topics=$(playground get-topic-list)
            for topic in $related_topics
            do
                if echo "$existing_topics" | grep -qFx -- "$topic"
                then
                    log "🧹 Deleting topic $topic created by connector $connector (use --keep-related-topics to keep it)"
                    playground topic delete --topic "$topic"
                fi
            done
        fi
    elif [[ "$environment" == "cfk" ]]
    then
        log "☸️ kubectl -n confluent delete connector $connector --ignore-not-found=true"
        kubectl -n confluent delete connector "$connector" --ignore-not-found=true >/dev/null
    else
        get_connect_url_and_security
        handle_onprem_connect_rest_api "curl $security -s -X DELETE \"$connect_url/connectors/$connector\""
    fi

    log "❌ $connector_type connector $connector has been deleted successfully"
done