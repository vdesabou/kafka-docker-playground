if scheduled_job_remove docker-cleanup
then
    log "🛑 docker cleanup disabled (its log stays in $scheduled_job_log)"
else
    log "🤷 the docker cleanup was not scheduled"
fi
