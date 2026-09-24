tag="${args[--tag]}"
verbose="${args[--verbose]}"

log "❌ Deleting Stream Catalog tag $tag"
encoded_tag=$(jq -rn --arg tag "$tag" '$tag | @uri')
if ! handle_catalog_rest_api DELETE "/catalog/v1/types/tagdefs/$encoded_tag"
then
    if [ "$http_code" == "409" ]
    then
        logwarn "💡 the tag is still assigned to entities, check with 'playground topic tag search --tag $tag'. Right after 'playground topic tag remove', wait a minute for the catalog to catch up"
    fi
    exit 1
fi
log "✅ Tag $tag deleted"
