tag="${args[--tag]}"
verbose="${args[--verbose]}"

log "🔎 Topics with tag $tag"
encoded_tag=$(jq -rn --arg tag "$tag" '$tag | @uri')
handle_catalog_rest_api GET "/catalog/v1/search/basic?types=kafka_topic&tag=$encoded_tag&limit=500" || exit 1
topics=$(echo "$curl_output" | jq -r '.entities[]? | .attributes.qualifiedName' | sort)
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
