lines="${args[--lines]}"
if scheduled_job_info docker-cleanup
then
    older_than=$(scheduled_job_flag_values --older-than)
    max_build_cache=$(scheduled_job_flag_values --max-build-cache)
    if [ "$scheduled_job_loaded" == "1" ]
    then
        log "🧽 docker cleanup scheduled every ${scheduled_job_day:-day} at $scheduled_job_time, older than ${older_than:-60} days, build cache up to ${max_build_cache:-10}GB ($(scheduled_job_where docker-cleanup))"
    else
        logwarn "⚠️ $scheduled_job_plist exists but is not loaded: playground docker-cleanup enable"
    fi
else
    log "💤 the docker cleanup is not scheduled: playground docker-cleanup enable"
fi
if [ -f "$scheduled_job_log" ]
then
    log "📄 last $lines lines of $scheduled_job_log:"
    tail -n "$lines" "$scheduled_job_log"
else
    log "📄 no run yet ($scheduled_job_log)"
fi
