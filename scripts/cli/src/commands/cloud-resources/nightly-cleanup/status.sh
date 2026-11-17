lines="${args[--lines]}"
if scheduled_job_info nightly-cleanup
then
    # the clouds are the values of the --resource arguments of the job
    resources=$(scheduled_job_flag_values --resource)
    if [ "$scheduled_job_loaded" == "1" ]
    then
        log "🌙 nightly cleanup of ${resources:-ccloud} scheduled every day at $scheduled_job_time ($(scheduled_job_where nightly-cleanup))"
    else
        logwarn "⚠️ $scheduled_job_plist exists but is not loaded: playground cloud-resources nightly-cleanup enable"
    fi
else
    log "💤 the nightly cleanup is not scheduled: playground cloud-resources nightly-cleanup enable"
fi
if [ -f "$scheduled_job_log" ]
then
    log "📄 last $lines lines of $scheduled_job_log:"
    tail -n "$lines" "$scheduled_job_log"
else
    log "📄 no run yet ($scheduled_job_log)"
fi
