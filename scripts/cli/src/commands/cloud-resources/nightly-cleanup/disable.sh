if scheduled_job_remove nightly-cleanup
then
    log "🛑 nightly cleanup disabled (its log stays in $scheduled_job_log)"
else
    log "🤷 the nightly cleanup was not scheduled"
fi
