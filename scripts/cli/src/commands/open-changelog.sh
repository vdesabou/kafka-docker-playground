only_show_url="${args[--only-show-url]}"

if [[ -n "$only_show_url" ]] || [[ $(type -f open 2>&1) =~ "not found" ]]
then
    log "📜 changelog is available at:"
    echo "https://kafka-docker-playground.io/#/changelog"
else
    log "📜 opening changelog https://kafka-docker-playground.io/#/changelog"
    open "https://kafka-docker-playground.io/#/changelog"
fi