topic="${args[--topic]}"
tag="${args[--tag]}"
verbose="${args[--verbose]}"

get_catalog_topic_qualified_name "$topic" || exit 1
log "🧽 Removing tag $tag from topic $topic ($qualified_name)"
encoded_tag=$(jq -rn --arg tag "$tag" '$tag | @uri')
handle_catalog_rest_api DELETE "/catalog/v1/entity/type/kafka_topic/name/$qualified_name/tags/$encoded_tag" || exit 1
log "✅ Tag $tag removed from topic $topic"
