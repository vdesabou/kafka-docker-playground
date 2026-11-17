lines="${args[--lines]}"
if scheduled_job_info ec2-auto-stop
then
    idle_minutes=$(scheduled_job_flag_values --idle-minutes)
    if [ "$scheduled_job_loaded" == "1" ]
    then
        log "⏰ ec2 auto-stop scheduled every day at $scheduled_job_time, idle minutes ${idle_minutes:-60} ($(scheduled_job_where ec2-auto-stop))"
    else
        logwarn "⚠️ $scheduled_job_plist exists but is not loaded: playground ec2 auto-stop enable"
    fi
else
    log "💤 the ec2 auto-stop is not scheduled: playground ec2 auto-stop enable"
fi
if [ -f "$scheduled_job_log" ]
then
    log "📄 last $lines lines of $scheduled_job_log:"
    tail -n "$lines" "$scheduled_job_log"
else
    log "📄 no run yet ($scheduled_job_log)"
fi
