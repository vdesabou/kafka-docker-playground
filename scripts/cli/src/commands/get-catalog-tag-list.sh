set +e
handle_catalog_rest_api GET "/catalog/v1/types/tagdefs" > /dev/null 2>&1 && echo "$curl_output" | jq -r '.[].name' | sort
set -e
