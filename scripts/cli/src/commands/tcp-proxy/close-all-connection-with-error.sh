log "🧹 Close all Zazkia TCP connections which are in error state"
handle_onprem_connect_rest_api "curl -o /dev/null -w '%{http_code}' -s -X POST -H \"Content-Type: application/json\" \"http://localhost:9191/links/closeAllWithError\""
echo "$curl_output"