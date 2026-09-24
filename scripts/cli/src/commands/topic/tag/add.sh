topic="${args[--topic]}"
tag="${args[--tag]}"
verbose="${args[--verbose]}"

get_catalog_topic_qualified_name "$topic" || exit 1
log "🏷️ Adding tag $tag to topic $topic ($qualified_name)"
body=$(jq -cn --arg name "$qualified_name" --arg tag "$tag" '[{entityType: "kafka_topic", entityName: $name, typeName: $tag}]')
handle_catalog_rest_api POST "/catalog/v1/entity/tags" "$body" || exit 1
error=$(echo "$curl_output" | jq -r '.[0].error // empty' 2>/dev/null || true)
if [ -n "$error" ]
then
    logerror "❌ Failed to add tag $tag to topic $topic: $error"
    exit 1
fi
log "✅ Tag $tag added to topic $topic"
