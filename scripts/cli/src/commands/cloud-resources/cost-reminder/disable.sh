if scheduled_job_remove cost-reminder
then
    log "🛑 cost reminder disabled (its log stays in $scheduled_job_log)"
else
    log "🤷 the cost reminder was not scheduled"
fi
