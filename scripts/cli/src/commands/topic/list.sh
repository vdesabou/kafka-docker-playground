show_internal="${args[--show-internal]}"
sort_by_size="${args[--sort-by-size]}"

if [[ -n "$sort_by_size" ]]
then
    if [[ -n "$show_internal" ]]
    then
        playground topic get-size --show-internal
    else
        playground topic get-size
    fi
elif [[ -n "$show_internal" ]]
then
    log "🫥 List of topics (internal topics are included)"
    playground get-topic-list
else 
    log "🔘 List of topics (internal topics are excluded)"
    playground get-topic-list --skip-internal-topics
fi
