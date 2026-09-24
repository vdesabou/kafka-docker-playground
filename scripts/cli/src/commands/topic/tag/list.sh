verbose="${args[--verbose]}"

log "🏷️ Listing Stream Catalog tag definitions"
handle_catalog_rest_api GET "/catalog/v1/types/tagdefs" || exit 1
if [ "$(echo "$curl_output" | jq 'length')" == "0" ]
then
    log "💤 No tag defined, create one with 'playground topic tag create --tag <tag>'"
    exit 0
fi
printf "%-30s %-60s\n" "TAG" "DESCRIPTION"
echo "$curl_output" | jq -r '.[] | [.name, (.description // "")] | @tsv' | sort | while IFS=$'\t' read -r name description
do
    printf "%-30s %-60s\n" "$name" "$description"
done
