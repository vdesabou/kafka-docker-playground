verbose="${args[--verbose]}"
state="${args[--state]}"

log "👥 Listing consumer groups"
if [[ -n "$state" ]]
then
    run_kafka_admin_tool kafka-consumer-groups --list --state
else
    run_kafka_admin_tool kafka-consumer-groups --list
fi
