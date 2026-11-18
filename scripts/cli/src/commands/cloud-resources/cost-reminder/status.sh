lines="${args[--lines]}"
if scheduled_job_info cost-reminder
then
    resources=$(scheduled_job_flag_values --resource)
    threshold=$(scheduled_job_flag_values --threshold)
    days=$(scheduled_job_flag_values --days)
    if [ "$scheduled_job_loaded" == "1" ]
    then
        log "💸 cost reminder of ${resources:-ccloud} scheduled every ${scheduled_job_day:-day} at $scheduled_job_time, last ${days:-7} days, threshold \$${threshold:-50} ($(scheduled_job_where cost-reminder))"
    else
        logwarn "⚠️ $scheduled_job_plist exists but is not loaded: playground cloud-resources cost-reminder enable"
    fi
else
    log "💤 the cost reminder is not scheduled: playground cloud-resources cost-reminder enable"
fi
if [ -f "$scheduled_job_log" ]
then
    log "📄 last $lines lines of $scheduled_job_log:"
    tail -n "$lines" "$scheduled_job_log"
else
    log "📄 no run yet ($scheduled_job_log)"
fi
