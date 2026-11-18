day="${args[--day]}"
time="${args[--time]}"
# Convert the space delimited string to an array
eval "resources=(${args[--resource]})"
threshold="${args[--threshold]}"
days="${args[--days]}"

parse_schedule_time "$time" || exit 1
if [ "$days" -lt 1 ] || [ "$days" -gt 31 ]
then
    logerror "❌ --days $days must be between 1 and 31"
    exit 1
fi
week=(sunday monday tuesday wednesday thursday friday saturday)
for i in "${!week[@]}"
do
    [ "${week[$i]}" == "$day" ] && weekday=$i
done

resource_args=()
for resource in "${resources[@]}"
do
    resource_args+=(--resource "$resource")
done

scheduled_job_install cost-reminder "weekday=$weekday" "$time_hour" "$time_minute" cloud-resources cost-reminder run "${resource_args[@]}" --threshold "$threshold" --days "$days" --scheduled || exit 1
log "💸 cost reminder of ${resources[*]} scheduled every $day at $(printf '%02d:%02d' $time_hour $time_minute), last $days days, threshold \$$threshold ($(scheduled_job_where cost-reminder))"
log "📄 log: $scheduled_job_log"
if [[ " ${resources[*]} " == *" ccloud "* ]]
then
    log "🔑 the confluent CLI must stay logged in: confluent login --save"
fi
log "🔎 what it finds, as of now:"
playground cloud-resources cost-reminder run "${resource_args[@]}" --threshold "$threshold" --days "$days"
log "👉 playground cloud-resources cost-reminder status   # after the first run"
