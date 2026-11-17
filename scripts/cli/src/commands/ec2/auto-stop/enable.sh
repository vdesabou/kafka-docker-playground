time="${args[--time]}"
idle_minutes="${args[--idle-minutes]}"

parse_schedule_time "$time" || exit 1
if [ "$idle_minutes" -lt 0 ]
then
    logerror "❌ --idle-minutes $idle_minutes must be 0 or more"
    exit 1
fi

scheduled_job_install ec2-auto-stop "$time_hour" "$time_minute" ec2 auto-stop run --idle-minutes "$idle_minutes" --scheduled || exit 1
log "⏰ ec2 auto-stop scheduled every day at $(printf '%02d:%02d' $time_hour $time_minute) ($(scheduled_job_where ec2-auto-stop))"
if [ "$idle_minutes" -eq 0 ]
then
    log "💤 every instance still running is stopped, whatever it is doing (except the ones tagged playground-keep-running=true)"
else
    log "💤 an instance whose CPU reached 5% in the last $idle_minutes minutes, or started less than $idle_minutes minutes ago, is kept"
fi
log "📄 log: $scheduled_job_log"
log "🔑 the aws CLI must work without a prompt at that time: ~/.aws/credentials (no SSO login to renew) and a region"
log "🔎 what tonight's run would stop, as of now:"
playground ec2 auto-stop run --idle-minutes "$idle_minutes" --dry-run
log "👉 playground ec2 auto-stop status   # after the first run"
