get_flink_rest_url || exit 0
curl -s "${flink_rest_url}/jobs/overview" 2>/dev/null | jq -r '.jobs[] | select(.state | IN("FINISHED", "CANCELED", "FAILED") | not) | .jid' 2>/dev/null
