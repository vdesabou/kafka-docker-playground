only_show_url="${args[--only-show-url]}"

url="https://kafka-docker-playground.io/#/changelog"
if [[ -z "$only_show_url" ]] && can_open_url
then
    log "📜 opening changelog $url"
    open_url "$url"
else
    log "📜 changelog is available at:"
    echo "$url"
fi