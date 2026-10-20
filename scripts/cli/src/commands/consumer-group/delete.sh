group="${args[--group]}"
topic="${args[--topic]}"
verbose="${args[--verbose]}"

if [[ -n "$topic" ]]
then
    log "🧹 Deleting committed offsets of consumer group $group for topic $topic"
    delete_args=(--delete-offsets --group "$group" --topic "$topic")
else
    log "🗑️ Deleting consumer group $group"
    delete_args=(--delete --group "$group")
fi

output=$(run_kafka_admin_tool kafka-consumer-groups "${delete_args[@]}" 2>&1) || true

# kafka-consumer-groups exits 0 on errors such as an unknown or non-empty group, detect them from the output
error=$(echo "$output" | grep -m1 -E "^Error: |Error: Deletion|GroupNotEmptyException|GroupIdNotFoundException|does not exist|is not empty|failed" || true)
if [ -n "$error" ]
then
    logerror "❌ Failed to delete: ${error#Error: }"
    echo "$output" | grep -v "^$" | grep -vF "$error" || true
    if echo "$output" | grep -qE "NonEmpty|not empty|GroupNotEmpty"
    then
        connector_name="${group#connect-}"
        if [ "$connector_name" != "$group" ]
        then
            logerror "   $group is the group of sink connector $connector_name: stop or delete the connector first (playground connector stop|delete --connector $connector_name)"
        else
            logerror "   the group still has active members: stop its consumers first (playground consumer-group describe --group $group --members)"
        fi
    fi
    exit 1
fi
echo "$output" | grep -v "^$"
log "✅ Done"
