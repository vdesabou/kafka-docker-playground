if scheduled_job_remove ec2-auto-stop
then
    log "🛑 ec2 auto-stop disabled (its log stays in $scheduled_job_log)"
else
    log "🤷 the ec2 auto-stop was not scheduled"
fi
