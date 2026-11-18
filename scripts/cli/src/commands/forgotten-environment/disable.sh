if scheduled_job_remove forgotten-environment
then
    log "🛑 forgotten environment check disabled (its log stays in $scheduled_job_log)"
else
    log "🤷 the forgotten environment check was not scheduled"
fi
