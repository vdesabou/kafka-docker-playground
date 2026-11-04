get_flink_environment
if [[ "$flink_environment" == "ccloud" ]]
then
    get_ccloud_flink_context > /dev/null 2>&1 || exit 0
    get_ccloud_flink_statements "RUNNING" | jq -r '.[].name' 2>/dev/null
    exit 0
fi
get_flink_rest_url || exit 0
curl -s "${flink_rest_url}/jobs/overview" 2>/dev/null | jq -r '.jobs[] | select(.state | IN("FINISHED", "CANCELED", "FAILED") | not) | .jid' 2>/dev/null
