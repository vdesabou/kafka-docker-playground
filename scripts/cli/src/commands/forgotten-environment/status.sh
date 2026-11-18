lines="${args[--lines]}"
if scheduled_job_info forgotten-environment
then
    idle_hours=$(scheduled_job_flag_values --idle-hours)
    if [ "$scheduled_job_loaded" == "1" ]
    then
        log "🔔 forgotten environment check scheduled every day at $scheduled_job_time, idle for ${idle_hours:-3} hours ($(scheduled_job_where forgotten-environment))"
    else
        logwarn "⚠️ $scheduled_job_plist exists but is not loaded: playground forgotten-environment enable"
    fi
else
    log "💤 the forgotten environment check is not scheduled: playground forgotten-environment enable"
fi
if [ -f "$scheduled_job_log" ]
then
    log "📄 last $lines lines of $scheduled_job_log:"
    tail -n "$lines" "$scheduled_job_log"
else
    log "📄 no check yet ($scheduled_job_log)"
fi
