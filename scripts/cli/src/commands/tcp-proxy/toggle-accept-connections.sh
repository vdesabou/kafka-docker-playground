log "🙅‍♂️ Change whether new connections can be accepted"
handle_onprem_connect_rest_api "curl -s -X POST -H \"Content-Type: application/json\"  --header 'Accept: application/json' \"http://localhost:9191/routes/tcp-proxy/toggle-accept\""

echo "$curl_output" | jq -r '.'