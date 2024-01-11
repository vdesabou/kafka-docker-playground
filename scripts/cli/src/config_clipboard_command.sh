if [[ "$OSTYPE" != "darwin"* ]]
then
    logerror "❌ clipboard is only working on MacOS"
    exit 1
fi

log "📋 configuring clipboard with ${args[enabled]}"
playground config set clipboard "${args[enabled]}"