codespace=$(codespace_pick "${args[--codespace]}") || exit 1

state=$(codespace_state "$codespace")
case "$state" in
  Available)
    log "🟢 codespace $codespace is already running"
    exit 0
  ;;
  ShuttingDown)
    # a start request now is refused with "already running" (HTTP 409)
    log "⏳ codespace $codespace is shutting down, waiting for it to stop first"
    codespace_wait_state "$codespace" "Shutdown" > /dev/null
  ;;
esac

state=$(codespace_state "$codespace")
case "$state" in
  Starting|Queued|Provisioning|Rebuilding|Updating)
    log "⏳ codespace $codespace is already $state"
  ;;
  *)
    log "🟢 starting codespace $codespace"
    if ! gh api -X POST "user/codespaces/$codespace/start" --silent
    then
      logerror "❌ could not start codespace $codespace (state $state)"
      exit 1
    fi
  ;;
esac

# usually about a minute
if state=$(codespace_wait_state "$codespace" "Available")
then
  log "✅ codespace $codespace is available: playground codespace open --codespace $codespace"
else
  logerror "❌ codespace $codespace is still $state after 5 minutes"
  exit 1
fi
