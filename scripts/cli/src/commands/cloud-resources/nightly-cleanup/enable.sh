time="${args[--time]}"
# Convert the space delimited string to an array
eval "resources=(${args[--resource]})"

parse_schedule_time "$time" || exit 1

if ! command -v jq > /dev/null 2>&1
then
    logwarn "⚠️ jq is not installed on this machine: the job would need Docker running at night, install jq (brew install jq)"
fi

resource_args=()
for resource in "${resources[@]}"
do
    resource_args+=(--resource "$resource")
done

scheduled_job_install nightly-cleanup "$time_hour" "$time_minute" cloud-resources cleanup "${resource_args[@]}" --force --nightly || exit 1
log "🌙 nightly cleanup of ${resources[*]} scheduled every day at $(printf '%02d:%02d' $time_hour $time_minute) ($(scheduled_job_where nightly-cleanup))"
log "📄 log: $scheduled_job_log"
if [[ " ${resources[*]} " == *" ccloud "* ]]
then
    log "🔑 the confluent CLI must stay logged in: confluent login --save"
fi
log "🔎 what tonight's run would delete, as of now (a cloud it would skip at night is skipped here too):"
playground cloud-resources cleanup "${resource_args[@]}" --nightly --dry-run
log "👉 playground cloud-resources nightly-cleanup status   # after the first night"
