tag="${args[--tag]}"
description="${args[--description]}"
verbose="${args[--verbose]}"

if [[ ! "$tag" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]]
then
    logerror "❌ tag name $tag is not valid: it must start with a letter and contain only letters, digits and underscores"
    exit 1
fi

log "🆕 Creating Stream Catalog tag $tag"
body=$(jq -cn --arg name "$tag" --arg description "$description" '[{name: $name, description: $description, entityTypes: ["kafka_topic"]}]')
handle_catalog_rest_api POST "/catalog/v1/types/tagdefs" "$body" || exit 1
error=$(echo "$curl_output" | jq -r '.[0].error // empty' 2>/dev/null || true)
if [ -n "$error" ]
then
    logerror "❌ Failed to create tag $tag: $error"
    exit 1
fi
log "✅ Tag $tag created, assign it with 'playground topic tag add --topic <topic> --tag $tag'"
