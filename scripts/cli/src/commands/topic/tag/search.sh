tag="${args[--tag]}"
verbose="${args[--verbose]}"

log "🔎 Topics with tag $tag"
encoded_tag=$(jq -rn --arg tag "$tag" '$tag | @uri')
# 500 entities per page at most: read the next pages until one is not full
topics=""
search_offset=0
while true
do
    handle_catalog_rest_api GET "/catalog/v1/search/basic?types=kafka_topic&tag=$encoded_tag&limit=500&offset=$search_offset" || exit 1
    page=$(echo "$curl_output" | jq -r '.entities[]? | .attributes.qualifiedName')
    topics=$(printf '%s\n%s' "$topics" "$page" | grep -v '^$' || true)
    if [ "$(echo "$curl_output" | jq '.entities | length' 2>/dev/null || echo 0)" -lt 500 ]
    then
        break
    fi
    search_offset=$((search_offset + 500))
done
topics=$(echo "$topics" | sort)
if [ -z "$topics" ]
then
    log "💤 No topic has tag $tag"
    exit 0
fi
printf "%-30s %-60s\n" "TOPIC" "QUALIFIED NAME"
for qualified_name in $topics
do
    printf "%-30s %-60s\n" "${qualified_name##*:}" "$qualified_name"
done
