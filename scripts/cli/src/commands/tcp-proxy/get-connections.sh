connection_id="${args[--connection-id]}"

handle_onprem_connect_rest_api "curl -s -X GET -H \"Content-Type: application/json\" \"http://localhost:9191/links/\""
if [[ ! -n "$connection_id" ]]
then
    echo "$curl_output" | jq -r '.[].links[] | select(.serviceReceiveError != "EOF") | {id, state, stats}'
else
    echo "$curl_output" | jq -r '.[].links[] | select(.id == '$connection_id' and .serviceReceiveError != "EOF") | {id, state, stats}'
fi