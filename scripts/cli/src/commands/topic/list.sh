show_internal="${args[--show-internal]}"

if [[ -n "$show_internal" ]]
then
    log "🫥 List of topics (internal topics are included)"
    playground get-topic-list
else 
    log "🔘 List of topics (internal topics are excluded)"
    playground get-topic-list --skip-internal-topics
fi