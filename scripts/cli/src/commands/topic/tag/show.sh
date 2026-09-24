topic="${args[--topic]}"
verbose="${args[--verbose]}"

get_catalog_topic_qualified_name "$topic" || exit 1
log "🔎 Tags of topic $topic ($qualified_name)"
handle_catalog_rest_api GET "/catalog/v1/entity/type/kafka_topic/name/$qualified_name/tags" || exit 1
if [ "$(echo "$curl_output" | jq 'length')" == "0" ]
then
    log "💤 Topic $topic has no tag"
    exit 0
fi
echo "$curl_output" | jq -r '.[].typeName' | sort
