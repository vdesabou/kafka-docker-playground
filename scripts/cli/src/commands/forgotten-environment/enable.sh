time="${args[--time]}"
idle_hours="${args[--idle-hours]}"

parse_schedule_time "$time" || exit 1
if [ "$idle_hours" -lt 1 ]
then
    logerror "❌ --idle-hours $idle_hours must be 1 or more"
    exit 1
fi

scheduled_job_install forgotten-environment "$time_hour" "$time_minute" forgotten-environment run --idle-hours "$idle_hours" --scheduled || exit 1
log "🔔 forgotten environment check scheduled every day at $(printf '%02d:%02d' $time_hour $time_minute), idle for $idle_hours hours ($(scheduled_job_where forgotten-environment))"
log "📄 log: $scheduled_job_log"
log "🔎 what it finds, as of now:"
playground forgotten-environment run --idle-hours "$idle_hours"
log "👉 playground forgotten-environment status   # after the first check"
