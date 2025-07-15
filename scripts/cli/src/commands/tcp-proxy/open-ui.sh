if [[ $(type -f open 2>&1) =~ "not found" ]]
then
    log "🔗 Cannot open browser, use url:"
    echo "http://localhost:9191"
else
    log "🧲 Open Zazkia UI"
    open "http://localhost:9191"
fi
