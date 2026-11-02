if ! can_open_url
then
    log "🔗 Cannot open browser, use url:"
    echo "http://localhost:9191"
else
    log "🧲 Open Zazkia UI"
    open_url "http://localhost:9191"
fi
