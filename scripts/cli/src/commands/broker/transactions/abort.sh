topic="${args[--topic]}"
partition="${args[--partition]}"
start_offset="${args[--start-offset]}"
verbose="${args[--verbose]}"

log "🧹 Aborting the transaction of topic $topic partition $partition started at offset $start_offset"
rc=0
output=$(run_kafka_admin_subcommand_tool kafka-transactions abort --topic "$topic" --partition "$partition" --start-offset "$start_offset" 2>&1) || rc=$?
output=$(echo "$output" | grep -v -E "^$|SLF4J|log4j|^[[:space:]]+at " || true)
if [ $rc -ne 0 ] || echo "$output" | grep -q -E "^Error|Exception"
then
    logerror "❌ kafka-transactions abort failed:"
    echo "$output"
    logerror "   the start offset must be the one of an open transaction: playground broker transactions describe-producers --topic $topic --partition $partition"
    exit 1
fi
[[ -n "$output" ]] && echo "$output"
log "✅ transaction aborted"
playground broker transactions describe-producers --topic "$topic" --partition "$partition"
